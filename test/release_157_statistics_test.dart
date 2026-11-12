import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/kugou_listening_profile_repository.dart';
import 'package:mesting_music/features/music_platform/data/kugou_official_api.dart';
import 'package:mesting_music/features/music_platform/data/kugou_v4_grade_repository.dart';
import 'package:mesting_music/features/music_platform/domain/kugou_listening_profile.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/kugou_listening_profile_providers.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_repository.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_worker.dart';
import 'release_107_listening_sync_test.dart' show FakeGateway;
import 'release_157_ranking_test.dart' show owner157, api157, reply157;

class _Statistics extends KugouListeningProfileRepository {
  _Statistics(DateTime Function() clock)
    : super(
        api: api157((_) async => reply157({'status': 1})),
        official: KugouOfficialApi(
          client: MockClient((_) async => reply157({'status': 1})),
          currentIdentity: () => owner157,
          device: () async => {},
        ),
        clock: clock,
      );
  final reads = <KugouListenPeriod>[];
  bool fail = false;
  int seconds = 30;
  Completer<KugouListeningStatistics>? pending;
  @override
  Future<KugouListeningStatistics> statistics(
    PlatformSession owner,
    KugouListenPeriod period,
    DateTime day,
  ) async {
    reads.add(period);
    if (fail) throw const KugouOfficialException('合成读取失败');
    if (pending != null) return pending!.future;
    return KugouListeningStatistics(
      {'listen_duration': seconds},
      period,
      period.start(day),
      clock(),
    );
  }
}

class _Rejecting extends FakeGateway {
  bool rejected = true;
  @override
  Future<bool> reportGrade(
    PlatformSession owner,
    int baseline,
    int delta,
  ) async {
    gradeWrites++;
    if (rejected) throw const KugouListeningRejected();
    total += delta;
    return true;
  }
}

class _Trickle extends http.BaseClient {
  int sends = 0;
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    final stream = StreamController<List<int>>();
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => stream.add([32]),
    );
    final abort = (request as http.AbortableRequest).abortTrigger;
    unawaited(
      abort!.then((_) {
        aborted = true;
        timer.cancel();
        stream.addError(http.RequestAbortedException());
        unawaited(stream.close());
      }),
    );
    return http.StreamedResponse(stream.stream, 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'successful current reports expire and refresh only periods already viewed',
    () async {
      var now = DateTime(2026, 11, 5, 12);
      final repository = _Statistics(() => now);
      final reader = KugouListeningProfileReader(
        owner: owner157,
        repository: repository,
      );
      addTearDown(reader.dispose);
      await reader.loadStatistics(KugouListenPeriod.week, now);
      await reader.loadStatistics(KugouListenPeriod.month, now);
      await reader.refreshCurrentStatistics();
      expect(repository.reads.length, 2);
      repository.seconds = 95;
      now = now.add(const Duration(minutes: 3));
      await reader.refreshCurrentStatistics();
      expect(repository.reads, [
        KugouListenPeriod.week,
        KugouListenPeriod.month,
        KugouListenPeriod.week,
        KugouListenPeriod.month,
      ]);
      expect(reader.statistics(KugouListenPeriod.week, now).value!.seconds, 95);
      expect(
        reader.statistics(KugouListenPeriod.month, now).value!.seconds,
        95,
      );
    },
  );
  test(
    'official readback updates the shared day without replacing it with local elapsed time',
    () async {
      final now = DateTime(2026, 11, 5);
      final repository = _Statistics(() => now);
      final reader = KugouListeningProfileReader(
        owner: owner157,
        repository: repository,
      );
      addTearDown(reader.dispose);
      await reader.loadStatistics(KugouListenPeriod.day, now);
      reader.acceptStatistics(
        KugouListeningStatistics(
          {'listen_duration': 71},
          KugouListenPeriod.day,
          now,
          now,
        ),
      );
      expect(reader.statistics(KugouListenPeriod.day, now).value!.seconds, 71);
      expect(repository.reads.length, 1);
      repository.fail = true;
      await reader.loadStatistics(KugouListenPeriod.day, now, force: true);
      expect(reader.statistics(KugouListenPeriod.day, now).value!.seconds, 71);
      expect(reader.statistics(KugouListenPeriod.day, now).error, '合成读取失败');
      await reader.loadStatistics(KugouListenPeriod.day, now);
      expect(repository.reads.length, 2);
    },
  );
  test('disposed reader drops a late official report', () async {
    final now = DateTime(2026, 11, 5);
    final repository = _Statistics(() => now)
      ..pending = Completer<KugouListeningStatistics>();
    final reader = KugouListeningProfileReader(
      owner: owner157,
      repository: repository,
    );
    final state = reader.statistics(KugouListenPeriod.week, now);
    final request = reader.loadStatistics(KugouListenPeriod.week, now);
    reader.dispose();
    repository.pending!.complete(
      KugouListeningStatistics(
        {'listen_duration': 99},
        KugouListenPeriod.week,
        now,
        now,
      ),
    );
    await request;
    expect(state.value, isNull);
  });
  test(
    'an older in-flight read cannot replace a newly observed official day',
    () async {
      final now = DateTime(2026, 11, 5);
      final repository = _Statistics(() => now)
        ..pending = Completer<KugouListeningStatistics>();
      final reader = KugouListeningProfileReader(
        owner: owner157,
        repository: repository,
      );
      addTearDown(reader.dispose);
      final operation = reader.loadStatistics(KugouListenPeriod.day, now);
      reader.acceptStatistics(
        KugouListeningStatistics(
          {'listen_duration': 95},
          KugouListenPeriod.day,
          now,
          now,
        ),
      );
      repository.pending!.complete(
        KugouListeningStatistics(
          {'listen_duration': 30},
          KugouListenPeriod.day,
          now,
          now,
        ),
      );
      await operation;
      expect(reader.statistics(KugouListenPeriod.day, now).value!.seconds, 95);
    },
  );
  test(
    'known grade rejection is final and does not poison later fresh listening',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      final now = DateTime(2026, 11, 5);
      final gateway = _Rejecting();
      final worker = ListeningSyncWorker(
        store: store,
        gateway: gateway,
        identity: owner157,
        currentIdentity: () => owner157,
        now: () => now,
      );
      addTearDown(worker.dispose);
      Future<void> queue(String id) => store.put(
        owner: owner157.ownerId,
        id: id,
        kind: 'grade',
        payload: {'heardMs': 5000},
        now: now,
      );
      await queue('first');
      await worker.flush();
      expect(
        (await store.entry(owner157.ownerId, 'first'))!.state,
        ListeningSyncState.rejected,
      );
      gateway.rejected = false;
      await queue('second');
      await worker.flush();
      expect(gateway.gradeWrites, 2);
      expect(
        (await store.entry(owner157.ownerId, 'second'))!.state,
        ListeningSyncState.verified,
      );
    },
  );
  test(
    'historical ambiguous grade remains read-only and is never reclassified or resent',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      final now = DateTime(2026, 11, 5);
      await store.put(
        owner: owner157.ownerId,
        id: 'old',
        kind: 'grade',
        payload: {'target': 900, 'diffSec': 50},
        now: now,
        state: ListeningSyncState.unknown,
      );
      final gateway = _Rejecting()..rejected = false;
      final worker = ListeningSyncWorker(
        store: store,
        gateway: gateway,
        identity: owner157,
        currentIdentity: () => owner157,
        now: () => now,
      );
      addTearDown(worker.dispose);
      await worker.flush();
      await worker.verifyPending();
      expect(gateway.gradeWrites, 0);
      expect(
        (await store.entry(owner157.ownerId, 'old'))!.state,
        ListeningSyncState.unknown,
      );
    },
  );
  test('only a parsed business refusal becomes a known rejection', () async {
    for (final explicit in [true, false]) {
      final repository = KugouListeningRepository(
        api157(
          (_) async => explicit
              ? reply157({'status': 0, 'error_code': 20018})
              : http.Response(jsonEncode({'unexpected': 'synthetic'}), 200),
        ),
        uuidLoader: () async => 'a' * 32,
      );
      if (explicit) {
        await expectLater(
          repository.reportGrade(owner157, 850, 5),
          throwsA(isA<KugouListeningRejected>()),
        );
      } else {
        expect(await repository.reportGrade(owner157, 850, 5), isFalse);
      }
    }
  });
  test(
    'a trickling standard-grade response is aborted at the complete deadline without retry',
    () async {
      const owner = PlatformSession(
        userId: '7',
        token: 'synthetic-lite',
        kugouStandardToken: 'synthetic-standard',
      );
      final client = _Trickle();
      final repository = KugouV4GradeRepository(
        client: client,
        currentIdentity: () => owner,
        device: () async => {
          'mid': 'fixture-mid',
          'uuid': 'fixture-uuid',
          'dfid': 'fixture-dfid',
        },
        requestTimeout: const Duration(milliseconds: 70),
      );
      await expectLater(
        repository.report(owner, localMillis: 855000, diffSeconds: 5),
        throwsA(isA<KugouOfficialException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(client.aborted, isTrue);
      expect(client.sends, 1);
    },
  );
}
