import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/audio/actual_listening_counter.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_footprint.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_listening_reporter.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_log.dart';
import 'netease_v112_listening_test.dart' show session, song;
import 'netease_v114_workflows_test.dart' show eapiBody;
import 'release_107_listening_sync_test.dart' show FakeClock, FakeFeed;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'official real/media clocks differ at 2x and ignore seek/buffer/pause',
    () {
      final clock = FakeClock();
      final counter = ActualListeningCounter(clock)
        ..update(playing: true, ready: true, speed: 2);
      clock.elapse(12000);
      counter.update(seeking: true);
      clock.elapse(15000);
      counter.update(seeking: false, ready: false);
      clock.elapse(7000);
      counter.update(ready: true, speed: .5);
      clock.elapse(8000);
      counter.update(playing: false);
      clock.elapse(5000);
      expect(counter.sample(), 20000);
      expect(counter.sampleMediaMilliseconds(), 28000);
    },
  );
  test(
    'queued October event keeps original date and real time while other states never replay',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      final original = DateTime(2026, 10, 20, 14, 30);
      for (final state in [
        ListeningSyncState.queued,
        ListeningSyncState.open,
        ListeningSyncState.accepted,
        ListeningSyncState.unknown,
        ListeningSyncState.dispatched,
      ]) {
        await store.put(
          owner: 'netease:7',
          id: 'old-${state.name}',
          kind: 'netease-scrobble',
          payload: {'id': '17', 'time': 123, 'heardMs': 123000},
          now: original,
          state: state,
        );
      }
      // A different account must never be included in this account's backfill.
      await store.put(
        owner: 'netease:8',
        id: 'another-owner',
        kind: 'netease-scrobble',
        payload: {'id': '19', 'time': 999, 'heardMs': 999000},
        now: original,
      );
      final logs = <Map>[];
      final api = NeteaseApi(
        MockClient((r) async {
          expect(r.url.host, 'clientlog.music.163.com');
          logs.addAll(
            (jsonDecode(eapiBody(r)['logs'] as String) as List).cast<Map>(),
          );
          return http.Response('{"code":200}', 200);
        }),
      )..configure(session);
      final reporter = NeteaseListeningReporter(
        feed: FakeFeed(),
        music: NeteaseMusicRepository(api),
        store: store,
        current: () => true,
        clock: FakeClock(),
        observeLifecycle: false,
        automaticTimers: false,
      );
      await reporter.settle();
      expect(logs, hasLength(2));
      for (final log in logs) {
        expect(log['json']['realtime'], 123);
        expect(log['json']['time'], 123);
        expect(
          log['json']['startlogtime'],
          original.millisecondsSinceEpoch ~/ 1000,
        );
      }
      await reporter.recoverPending();
      expect(logs, hasLength(2));
      expect(
        (await store.entry('netease:7', 'old-unknown'))!.state,
        ListeningSyncState.unknown,
      );
      reporter.dispose();
      await reporter.settle();
    },
  );
  test(
    'new play logs preserve audible start time and speed-weighted duration',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final logs = <Map>[];
      final api = NeteaseApi(
        MockClient((r) async {
          logs.addAll(
            (jsonDecode(eapiBody(r)['logs'] as String) as List).cast<Map>(),
          );
          return http.Response('{"code":200}', 200);
        }),
      )..configure(session);
      final feed = FakeFeed(), clock = FakeClock();
      feed.setTrack(song);
      feed.setState(true, true, speed: 2);
      final original = clock.now;
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: NeteaseMusicRepository(api),
        store: ListeningSyncStore(db),
        current: () => true,
        clock: clock,
        observeLifecycle: false,
        automaticTimers: false,
      );
      clock.elapse(60000);
      reporter.checkpoint();
      feed.setTrack(null);
      await reporter.settle();
      final duration =
          logs.singleWhere((l) => l['action'] == 'play')['json'] as Map;
      expect(duration['realtime'], 60);
      expect(duration['time'], 120);
      expect(duration['startlogtime'], original.millisecondsSinceEpoch ~/ 1000);
      reporter.dispose();
      await reporter.settle();
    },
  );
  test(
    'footprint is read from official calendar route, not recent-song indexing',
    () async {
      final api = NeteaseApi(
        MockClient((r) async {
          expect(r.url.path, '/eapi/music/multi/terminal/widget/listen/data');
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': jsonEncode({
                'monthDate': '2026-11',
                'hourDuration': 12,
                'minuteDuration': 23,
              }),
            }),
            200,
          );
        }),
      )..configure(session);
      final result = await NeteaseMusicRepository(api).footprint();
      expect(result!.month, '2026-11');
      expect(result.label, '12 小时');
      expect(
        NeteaseFootprint.parse({
          'data': {
            'monthDate': '2026-10',
            'hourDuration': 0,
            'minuteDuration': 683,
          },
        })!.label,
        '683 分钟',
      );
      expect(
        NeteaseFootprint.parse({
          'data': {'monthDate': '2026-11'},
        }),
        isNull,
      );
      expect(NeteaseFootprint.parse('invalid'), isNull);
    },
  );
  test(
    'protocol builder never invents monthly playback or negative intervals',
    () {
      expect(
        () => neteasePlaybackLog(
          id: 'not-song',
          started: false,
          mediaSeconds: 10,
          realSeconds: 10,
          startedAt: DateTime(2026),
        ),
        throwsArgumentError,
      );
      expect(
        () => neteasePlaybackLog(
          id: '17',
          started: false,
          mediaSeconds: 10,
          realSeconds: -1,
          startedAt: DateTime(2026),
        ),
        throwsArgumentError,
      );
    },
  );
}
