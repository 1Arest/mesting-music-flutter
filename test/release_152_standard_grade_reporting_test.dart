import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/open.dart';

import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/kugou_v4_grade_repository.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_repository.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_worker.dart';

const _standard = PlatformSession(
  userId: '12345',
  token: 'synthetic-lite-credential',
  kugouStandardToken: 'synthetic-standard-credential',
);
const _lite = PlatformSession(
  userId: '12345',
  token: 'synthetic-lite-credential',
);

class _LegacyGateway implements ListeningPlatformGateway {
  int gradeWrites = 0;
  @override
  Future<void> prepare(PlatformSession identity) async {}
  @override
  Future<String> resolveRecording(PlatformSession identity, String id) async =>
      '';
  @override
  Future<List<OfficialHistoryFact>> history(PlatformSession identity) async =>
      [];
  @override
  Future<bool> uploadHistory(
    PlatformSession identity,
    String id,
    int time,
    int count,
  ) async => true;
  @override
  Future<int?> gradeSeconds(PlatformSession identity) async => 850;
  @override
  Future<bool> reportGrade(
    PlatformSession identity,
    int baseline,
    int delta,
  ) async {
    gradeWrites++;
    return true;
  }

  @override
  Future<bool> reportEvent(
    PlatformSession identity,
    Map<String, Object?> payload,
  ) async => true;
}

class _StandardGateway implements KugouStandardGradeGateway {
  int total = 850;
  bool timeout = false, confirm = true;
  bool rejected = false;
  Completer<bool>? pending;
  final reports = <({int localMillis, int diffSeconds})>[];
  @override
  Future<int?> seconds(PlatformSession identity) async => total;
  @override
  Future<bool> report(
    PlatformSession identity, {
    required int localMillis,
    required int diffSeconds,
  }) async {
    reports.add((localMillis: localMillis, diffSeconds: diffSeconds));
    if (rejected) {
      throw const KugouStandardGradeRejected(
        'Synthetic explicit rejection',
        loginRequired: true,
      );
    }
    if (timeout) throw TimeoutException('synthetic ambiguous write');
    if (pending != null) return pending!.future;
    if (confirm) total = localMillis ~/ 1000;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    const dll = String.fromEnvironment('SQLITE3_TEST_DLL');
    if (Platform.isWindows && dll.isNotEmpty) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dll));
    }
  });
  late AppDatabase database;
  late ListeningSyncStore store;
  late DateTime now;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = ListeningSyncStore(database);
    now = DateTime(2026, 11, 4, 15);
  });
  tearDown(() async => database.close());

  Future<void> queue(String id, int milliseconds, {bool marker = true}) =>
      store.put(
        owner: _standard.ownerId,
        id: id,
        kind: 'grade_v4',
        payload: {
          'segmentId': id,
          'heardMs': milliseconds,
          if (marker) ...{
            'gradeProtocol': kugouStandardGradeProtocol,
            'credentialAppId': 1005,
          },
        },
        now: now,
      );

  ListeningSyncWorker worker(
    _StandardGateway gateway, {
    PlatformSession identity = _standard,
    PlatformSession? Function()? current,
    _LegacyGateway? legacy,
  }) => ListeningSyncWorker(
    store: store,
    gateway: legacy ?? _LegacyGateway(),
    identity: identity,
    currentIdentity: current ?? () => identity,
    standardGradeGateway: gateway,
    now: () => now,
  );

  test(
    'native cumulative target and fresh delta are distinct from Lite rows',
    () async {
      final gateway = _StandardGateway();
      final legacy = _LegacyGateway();
      await store.put(
        owner: _standard.ownerId,
        id: 'old-lite-row',
        kind: 'grade',
        payload: {'heardMs': 60000},
        now: now,
      );
      await queue('current-segment', 75500);
      final drain = worker(gateway, legacy: legacy)
        ..registerLiveSegment('current-segment');
      await drain.flush();
      expect(gateway.reports.single.localMillis, 925500);
      expect(gateway.reports.single.diffSeconds, 75);
      expect(legacy.gradeWrites, 0);
      expect(
        (await store.entry(_standard.ownerId, 'old-lite-row'))!.state,
        ListeningSyncState.queued,
      );
      final sent = (await store.entry(_standard.ownerId, 'current-segment'))!;
      expect(sent.state, ListeningSyncState.verified);
      expect(sent.number('observedV4Seconds'), 925);
      final carry = (await store.entries(
        _standard.ownerId,
        kinds: {'grade_v4'},
        states: {ListeningSyncState.queued},
      )).single;
      expect(carry.number('heardMs'), 500);
      expect(carry.text('segmentId'), 'current-segment');
      drain.dispose();
    },
  );

  test(
    'restart never submits old standard measurements or unmarked rows',
    () async {
      await queue('previous-process', 75000);
      await queue('unmarked-row', 75000, marker: false);
      final gateway = _StandardGateway();
      final drain = worker(gateway);
      await drain.flush();
      expect(gateway.reports, isEmpty);
      expect(
        (await store.entry(_standard.ownerId, 'previous-process'))!.state,
        ListeningSyncState.interrupted,
      );
      expect(
        (await store.entry(_standard.ownerId, 'unmarked-row'))!.state,
        ListeningSyncState.queued,
      );
      drain.dispose();
    },
  );

  test(
    'a timed out write is only read back, never folded into another delta',
    () async {
      final gateway = _StandardGateway()..timeout = true;
      await queue('first', 75000);
      final drain = worker(gateway)..registerLiveSegment('first');
      await drain.flush();
      expect(gateway.reports.length, 1);
      expect(
        (await store.entry(_standard.ownerId, 'first'))!.state,
        ListeningSyncState.unknown,
      );
      await queue('later', 60000);
      drain.registerLiveSegment('later');
      await drain.verifyPending();
      await drain.flush();
      expect(gateway.reports.length, 1);
      gateway
        ..timeout = false
        ..total = 925;
      await drain.flush();
      expect(gateway.reports.length, 2);
      expect(gateway.reports.last.localMillis, 985000);
      expect(gateway.reports.last.diffSeconds, 60);
      expect(
        (await store.entry(_standard.ownerId, 'first'))!.state,
        ListeningSyncState.verified,
      );
      drain.dispose();
    },
  );

  test('zero-counter verification never drains fresh queued reports', () async {
    final gateway = _StandardGateway();
    await queue('fresh', 60000);
    final drain = worker(gateway)..registerLiveSegment('fresh');
    await drain.verifyPending();
    expect(gateway.reports, isEmpty);
    expect(
      (await store.entry(_standard.ownerId, 'fresh'))!.state,
      ListeningSyncState.queued,
    );
    drain.dispose();
  });

  test(
    'explicit rejection is never replayed and does not block fresh playback',
    () async {
      final gateway = _StandardGateway()..rejected = true;
      await queue('rejected-play', 60000);
      final drain = worker(gateway)..registerLiveSegment('rejected-play');
      await drain.flush();
      expect(gateway.reports.length, 1);
      expect(
        (await store.entry(_standard.ownerId, 'rejected-play'))!.state,
        ListeningSyncState.rejected,
      );
      gateway.rejected = false;
      await queue('new-play', 30000);
      drain.registerLiveSegment('new-play');
      await drain.flush();
      expect(gateway.reports.length, 2);
      expect(gateway.reports.last.diffSeconds, 30);
      expect(gateway.reports.last.localMillis, 880000);
      drain.dispose();
    },
  );

  test('Lite credentials cannot activate the standard journal', () async {
    await queue('fresh', 60000);
    final gateway = _StandardGateway();
    final drain = worker(gateway, identity: _lite)
      ..registerLiveSegment('fresh');
    await drain.flush();
    expect(gateway.reports, isEmpty);
    drain.dispose();
  });

  test(
    'same UID reauthorization leaves an in-flight write ambiguous',
    () async {
      final gateway = _StandardGateway()..pending = Completer<bool>();
      PlatformSession active = _standard;
      await queue('fresh', 60000);
      final drain = worker(gateway, current: () => active)
        ..registerLiveSegment('fresh');
      final operation = drain.flush();
      while (gateway.reports.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      active = const PlatformSession(
        userId: '12345',
        token: 'synthetic-lite-credential',
        kugouStandardToken: 'replacement-standard-credential',
      );
      gateway.pending!.complete(true);
      await operation;
      expect(drain.current, isFalse);
      expect(
        (await store.entry(_standard.ownerId, 'fresh'))!.state,
        ListeningSyncState.dispatched,
      );
      expect(gateway.reports.length, 1);
      drain.dispose();
    },
  );

  test(
    'the transport uses the standard envelope, read counters stay zero',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'status': 1,
            'error_code': 0,
            'data': {'userid': 12345, 'd_sec': 925},
          }),
          200,
        );
      });
      final repository = KugouV4GradeRepository(
        client: client,
        currentIdentity: () => _standard,
        device: () async => {
          'mid': 'real-app-mid',
          'uuid': 'own-uuid',
          'dfid': 'own-dfid',
        },
        clock: () => now,
      );
      expect(await repository.seconds(_standard), 925);
      final readBody = jsonDecode(requests.single.body) as Map;
      expect(readBody['d_sec'], 0);
      expect(readBody['diff_sec'], 0);
      await repository.report(_standard, localMillis: 925500, diffSeconds: 75);
      final report = requests.last;
      expect(report.url.scheme, 'https');
      expect(report.url.host, 'userinfoservice.kugou.com');
      expect(report.url.path, '/v4/get_grade_info');
      expect(report.url.queryParameters['appid'], '1005');
      expect(report.url.queryParameters['clientver'], '20869');
      expect(
        report.url.queryParameters['signature'],
        matches(r'^[0-9a-f]{32}$'),
      );
      final body = jsonDecode(report.body) as Map;
      expect(body['d_sec'], 925);
      expect(body['diff_sec'], 75);
      expect(report.body, isNot(contains(_standard.kugouStandardToken)));
      expect(report.body, isNot(contains(_standard.token)));
      client.close();
    },
  );

  test(
    'transport refuses Lite identity before creating any network request',
    () async {
      var networkCalls = 0;
      final client = MockClient((request) async {
        networkCalls++;
        return http.Response('{}', 200);
      });
      final repository = KugouV4GradeRepository(
        client: client,
        currentIdentity: () => _lite,
        device: () async => {},
      );
      await expectLater(repository.seconds(_lite), throwsException);
      expect(networkCalls, 0);
      client.close();
    },
  );

  test(
    'mismatched official user and late credential epochs are rejected',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'status': 1,
            'data': {'userid': 99999, 'd_sec': 925},
          }),
          200,
        ),
      );
      final repository = KugouV4GradeRepository(
        client: client,
        currentIdentity: () => _standard,
        device: () async => {'mid': 'mid', 'uuid': 'uuid', 'dfid': 'dfid'},
        clock: () => now,
      );
      await expectLater(repository.seconds(_standard), throwsException);
      client.close();
    },
  );
}
