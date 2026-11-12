import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_listening_reporter.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';

import 'netease_v112_listening_test.dart' show session, song;
import 'netease_v114_workflows_test.dart' show eapiBody;
import 'release_107_listening_sync_test.dart' show FakeClock, FakeFeed;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final receipt in <String, Map<String, Object?>>{
    'missing code': {},
    'nonnumeric code': {'code': 'not-a-receipt'},
  }.entries) {
    test('${receipt.key} stays uncertain and never replays', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      await store.put(
        owner: 'netease:7',
        id: 'one-measured-play',
        kind: 'netease-scrobble',
        payload: {'id': '17', 'time': 12, 'heardMs': 12000},
        now: DateTime(2026, 11, 2),
      );
      var requests = 0;
      final api = NeteaseApi(
        MockClient((request) async {
          requests++;
          return http.Response(jsonEncode(receipt.value), 200);
        }),
      )..configure(session);
      NeteaseListeningReporter createReporter() => NeteaseListeningReporter(
        feed: FakeFeed(),
        music: NeteaseMusicRepository(api),
        store: store,
        current: () => true,
        observeLifecycle: false,
        automaticTimers: false,
      );
      final first = createReporter();
      await first.settle();
      expect(
        (await store.entry('netease:7', 'one-measured-play'))!.state,
        ListeningSyncState.unknown,
      );
      await first.recoverPending();
      first.dispose();
      await first.settle();
      final restarted = createReporter();
      await restarted.settle();
      await restarted.recoverPending();
      restarted.dispose();
      await restarted.settle();
      expect(requests, 1);
    });
  }

  test('explicit business rejection remains rejected without replay', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = ListeningSyncStore(db);
    await store.put(
      owner: 'netease:7',
      id: 'rejected-measured-play',
      kind: 'netease-scrobble',
      payload: {'id': '17', 'time': 12, 'heardMs': 12000},
      now: DateTime(2026, 11, 2),
    );
    var requests = 0;
    final api = NeteaseApi(
      MockClient((request) async {
        requests++;
        return http.Response('{"code":301}', 200);
      }),
    )..configure(session);
    final reporter = NeteaseListeningReporter(
      feed: FakeFeed(),
      music: NeteaseMusicRepository(api),
      store: store,
      current: () => true,
      observeLifecycle: false,
      automaticTimers: false,
    );
    await reporter.settle();
    expect(
      (await store.entry('netease:7', 'rejected-measured-play'))!.state,
      ListeningSyncState.rejected,
    );
    await reporter.recoverPending();
    reporter.dispose();
    await reporter.settle();
    expect(requests, 1);
  });

  test(
    'non-log requests retain their optional business-code contract',
    () async {
      final api = NeteaseApi(
        MockClient(
          (request) async => http.Response('{"data":{"ok":true}}', 200),
        ),
      )..configure(session);
      final result = await api.request('/api/song/detail', const {});
      expect(result['data'], {'ok': true});
    },
  );

  test('seek end opens once after readiness and excludes seek time', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final feed = FakeFeed(), clock = FakeClock();
    addTearDown(feed.close);
    feed.setTrack(song);
    feed.setState(true, false);
    feed.seek(true);
    final logs = <Map>[];
    final api = NeteaseApi(
      MockClient((request) async {
        logs.addAll(
          (jsonDecode(eapiBody(request)['logs'] as String) as List).cast<Map>(),
        );
        return http.Response('{"code":200}', 200);
      }),
    )..configure(session);
    final reporter = NeteaseListeningReporter(
      feed: feed,
      music: NeteaseMusicRepository(api),
      store: ListeningSyncStore(db),
      current: () => true,
      clock: clock,
      observeLifecycle: false,
      automaticTimers: false,
    );
    clock.elapse(2000);
    feed.setState(true, true);
    clock.elapse(3000);
    await reporter.settle();
    expect(logs, isEmpty);
    final startedAt = clock.now;
    feed.seek(false);
    await reporter.settle();
    expect(logs.single['action'], 'startplay');
    expect(
      logs.single['json']['startlogtime'],
      startedAt.millisecondsSinceEpoch ~/ 1000,
    );
    feed.seek(false);
    await reporter.settle();
    expect(logs, hasLength(1));
    clock.elapse(6000);
    feed.setTrack(null);
    await reporter.settle();
    expect(logs.map((row) => row['action']), ['startplay', 'play']);
    expect(logs.last['json']['time'], 6);
    expect(logs.last['json']['realtime'], 6);
    reporter.dispose();
    await reporter.settle();
  });

  for (final gate in ['paused', 'not ready', 'account changed']) {
    test('seek end cannot open while $gate', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final feed = FakeFeed();
      addTearDown(feed.close);
      feed.setTrack(song);
      feed.seek(true);
      feed.setState(gate != 'paused', gate != 'not ready');
      var requests = 0;
      final api = NeteaseApi(
        MockClient((request) async {
          requests++;
          return http.Response('{"code":200}', 200);
        }),
      )..configure(session);
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: NeteaseMusicRepository(api),
        store: ListeningSyncStore(db),
        current: () => gate != 'account changed',
        clock: FakeClock(),
        observeLifecycle: false,
        automaticTimers: false,
      );
      feed.seek(false);
      await reporter.settle();
      reporter.dispose();
      await reporter.settle();
      expect(requests, 0);
    });
  }
}
