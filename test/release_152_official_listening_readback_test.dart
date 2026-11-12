import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// Match the established host-only sqlite override without touching production
// dependency pins, native loading or any SDK binary.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/open.dart';

import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_daily_readback.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_repository.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_worker.dart';

const _identity = PlatformSession(
  userId: '12345',
  token: 'synthetic-readback-token',
);

class _EventSpyGateway implements ListeningPlatformGateway {
  final sent = Completer<void>();
  int eventWrites = 0;
  @override
  Future<void> prepare(PlatformSession identity) async {}
  @override
  Future<String> resolveRecording(PlatformSession identity, String id) async =>
      '7654321';
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
  Future<int?> gradeSeconds(PlatformSession identity) async => 0;
  @override
  Future<bool> reportGrade(
    PlatformSession identity,
    int baseline,
    int delta,
  ) async => true;
  @override
  Future<bool> reportEvent(
    PlatformSession identity,
    Map<String, Object?> payload,
  ) async {
    eventWrites++;
    if (!sent.isCompleted) sent.complete();
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
  late DateTime clock;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = ListeningSyncStore(database);
    clock = DateTime(2026, 11, 4, 12);
  });
  tearDown(() async => database.close());

  Future<OfficialListeningDayStatus?> readStatus(DateTime day) async =>
      OfficialListeningDayStatus.fromEntry(
        await store.entry(
          'kugou:12345',
          OfficialListeningDayStatus.entryId(day),
        ),
      );

  test(
    'a receipt and unchanged official time never imply credited playback',
    () async {
      // This reproduces the historical limitation: a successful endpoint receipt
      // with an unchanged independent official total is still no growth evidence.
      await store.put(
        owner: 'kugou:12345',
        id: 'synthetic-grade',
        kind: 'grade',
        payload: {'heardMs': 75000},
        now: clock,
        state: ListeningSyncState.accepted,
      );
      final readback = ListeningDailyReadback(
        store: store,
        identity: _identity,
        isCurrent: () => true,
        now: () => clock,
        reader: (_, day) async =>
            OfficialListeningDayFact(day: day, seconds: 850, readAt: clock),
      );
      await readback.observe();
      clock = clock.add(const Duration(minutes: 3));
      await readback.observe();
      final value = (await readStatus(clock))!;
      expect(value.seconds, 850);
      expect(value.baselineSeconds, 850);
      expect(value.observedIncreaseSeconds, 0);
      expect(
        (await store.entry('kugou:12345', 'synthetic-grade'))!.state,
        ListeningSyncState.accepted,
      );
    },
  );

  test(
    'only independently returned seconds change the official observation',
    () async {
      var seconds = 850;
      final readback = ListeningDailyReadback(
        store: store,
        identity: _identity,
        isCurrent: () => true,
        now: () => clock,
        reader: (_, day) async => OfficialListeningDayFact(
          day: day,
          seconds: seconds,
          totalSeconds: 1200,
          readAt: clock,
        ),
      );
      await readback.observe();
      final firstRead = clock;
      seconds = 925;
      clock = clock.add(const Duration(minutes: 3));
      await readback.observe();
      final value = (await readStatus(clock))!;
      expect(value.baselineReadAt, firstRead);
      expect(value.readAt, clock);
      expect(value.observedIncreaseSeconds, 75);
      expect(value.totalSeconds, 1200);
      expect(value.readFailed, isFalse);
    },
  );

  test(
    'failed reads keep the last official fact and exclude private errors',
    () async {
      var fail = false;
      final readback = ListeningDailyReadback(
        store: store,
        identity: _identity,
        isCurrent: () => true,
        now: () => clock,
        reader: (_, day) async {
          if (fail) throw StateError('secret-token-must-not-be-stored');
          return OfficialListeningDayFact(day: day, seconds: 50, readAt: clock);
        },
      );
      await readback.observe();
      final firstRead = clock;
      fail = true;
      clock = clock.add(const Duration(minutes: 3));
      await readback.observe();
      final value = (await readStatus(clock))!;
      expect(value.seconds, 50);
      expect(value.readAt, firstRead);
      expect(value.attemptedAt, clock);
      expect(value.readFailed, isTrue);
      final row = await store.entry(
        'kugou:12345',
        OfficialListeningDayStatus.entryId(clock),
      );
      expect('${row!.payload}', isNot(contains('secret-token')));
    },
  );

  test('a failed first read does not manufacture a zero baseline', () async {
    var fail = true;
    final readback = ListeningDailyReadback(
      store: store,
      identity: _identity,
      isCurrent: () => true,
      now: () => clock,
      reader: (_, day) async {
        if (fail) throw StateError('synthetic failure');
        return OfficialListeningDayFact(day: day, seconds: 60, readAt: clock);
      },
    );
    await readback.observe();
    expect((await readStatus(clock))!.seconds, isNull);
    expect((await readStatus(clock))!.baselineSeconds, isNull);
    fail = false;
    await readback.observe(force: true);
    expect((await readStatus(clock))!.baselineSeconds, 60);
    expect((await readStatus(clock))!.observedIncreaseSeconds, 0);
  });

  test('disposed account epochs discard A to B to A late replies', () async {
    final pending = Completer<OfficialListeningDayFact>();
    final started = Completer<void>();
    var generation = 1;
    final readback = ListeningDailyReadback(
      store: store,
      identity: _identity,
      isCurrent: () => generation == 1,
      now: () => clock,
      reader: (_, day) {
        started.complete();
        return pending.future;
      },
    );
    final operation = readback.observe();
    await started.future;
    generation = 2; // Account B.
    generation = 3; // Same account A, a different authentication epoch.
    pending.complete(
      OfficialListeningDayFact(day: clock, seconds: 80, readAt: clock),
    );
    await operation;
    expect(await readStatus(clock), isNull);
    expect(await store.entries('kugou:other-account'), isEmpty);
  });

  test(
    'midnight retries the observed previous day without carrying its value',
    () async {
      var seconds = 10;
      final calls = <String>[];
      Future<OfficialListeningDayFact> reader(
        PlatformSession _,
        DateTime day,
      ) async {
        calls.add(OfficialListeningDayStatus.dayKey(day));
        return OfficialListeningDayFact(
          day: day,
          seconds: seconds,
          readAt: clock,
        );
      }

      ListeningDailyReadback create() => ListeningDailyReadback(
        store: store,
        identity: _identity,
        isCurrent: () => true,
        now: () => clock,
        reader: reader,
      );
      await create().observe();
      final yesterday = clock;
      clock = DateTime(2026, 11, 5, 0, 1);
      seconds = 20;
      // A fresh readback object models restart; persisted dates remain distinct.
      await create().observe();
      expect(calls, ['20261104', '20261104', '20261105']);
      expect((await readStatus(yesterday))!.observedIncreaseSeconds, 10);
      expect((await readStatus(clock))!.observedIncreaseSeconds, 0);
    },
  );

  test(
    'automatic reads are bounded and explicit refresh stays read only',
    () async {
      var calls = 0;
      final readback = ListeningDailyReadback(
        store: store,
        identity: _identity,
        isCurrent: () => true,
        now: () => clock,
        reader: (_, day) async {
          calls++;
          return OfficialListeningDayFact(day: day, seconds: 12, readAt: clock);
        },
      );
      await readback.observe();
      await readback.observe();
      expect(calls, 1);
      await readback.observe(force: true);
      expect(calls, 2);
      expect(
        (await store.entries('kugou:12345')).map((row) => row.kind),
        everyElement('official_day_readback'),
      );
    },
  );

  test(
    'mismatched dates and negative server values remain unavailable',
    () async {
      var wrongDate = true;
      final readback = ListeningDailyReadback(
        store: store,
        identity: _identity,
        isCurrent: () => true,
        now: () => clock,
        reader: (_, day) async => OfficialListeningDayFact(
          day: wrongDate ? day.add(const Duration(days: 1)) : day,
          seconds: wrongDate ? 80 : -1,
          readAt: clock,
        ),
      );
      await readback.observe();
      expect((await readStatus(clock))!.seconds, isNull);
      wrongDate = false;
      await readback.observe(force: true);
      expect((await readStatus(clock))!.seconds, isNull);
      expect((await readStatus(clock))!.readFailed, isTrue);
    },
  );

  test(
    'slow statistics never delay live reports and refresh joins one read',
    () async {
      final gateway = _EventSpyGateway();
      final reply = Completer<OfficialListeningDayFact>();
      final started = Completer<void>();
      var reads = 0;
      await store.put(
        owner: 'kugou:12345',
        id: 'cscc:synthetic-start',
        kind: 'cscc',
        payload: {
          'segmentId': 'synthetic-live-segment',
          'recordingId': '7654321',
          'event': 'start',
        },
        now: clock,
      );
      final worker = ListeningSyncWorker(
        store: store,
        gateway: gateway,
        identity: _identity,
        currentIdentity: () => _identity,
        now: () => clock,
        officialDayReader: (_, day) {
          reads++;
          started.complete();
          return reply.future;
        },
      )..registerLiveSegment('synthetic-live-segment');
      final drain = worker.flush();
      await started.future;
      // This completes even while the official daily response remains blocked.
      await gateway.sent.future;
      final refresh = worker.verifyPending();
      expect(gateway.eventWrites, 1);
      expect(reads, 1);
      reply.complete(
        OfficialListeningDayFact(day: clock, seconds: 30, readAt: clock),
      );
      await Future.wait([drain, refresh]);
      expect(reads, 1);
      expect(gateway.eventWrites, 1);
      expect((await readStatus(clock))!.seconds, 30);
      worker.dispose();
    },
  );
}
