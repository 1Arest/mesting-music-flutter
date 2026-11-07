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
import 'release_107_listening_sync_test.dart' show FakeClock, FakeFeed;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'release default sends new start and measured duration through weblog',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db),
          clock = FakeClock(),
          feed = FakeFeed();
      addTearDown(feed.close);
      final requests = <http.Request>[];
      final api = NeteaseApi(
        MockClient((request) async {
          requests.add(request);
          return http.Response('{"code":200}', 200);
        }),
      )..configure(session);
      final music = NeteaseMusicRepository(api);
      expect(music.nativeLogEnabled, false);
      feed.setTrack(song);
      feed.setState(true, true);
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: music,
        store: store,
        current: () => true,
        clock: clock,
        observeLifecycle: false,
        automaticTimers: false,
      );
      await reporter.settle();
      clock.elapse(65000);
      feed.setTrack(null);
      await reporter.settle();
      final rows = await store.entries('netease:7');
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.number('protocolVersion') == 2), true);
      expect(rows.every((r) => r.state == ListeningSyncState.accepted), true);
      expect(
        rows
            .singleWhere((r) => r.kind == 'netease-scrobble')
            .number('realtime'),
        65,
      );
      expect(requests, hasLength(2));
      expect(
        requests.every((r) => r.url.host == 'clientlog.music.163.com'),
        true,
      );
      expect(
        requests.every((r) => r.url.path.endsWith('/feedback/weblog')),
        true,
      );
      await reporter.recoverPending();
      reporter.dispose();
      await reporter.settle();
      expect(requests, hasLength(2));
    },
  );

  test(
    'disabled native transport preserves all old states and does not block legacy queue',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db), now = DateTime(2026, 11, 2);
      final states = [
        ListeningSyncState.open,
        ListeningSyncState.queued,
        ListeningSyncState.dispatched,
        ListeningSyncState.accepted,
        ListeningSyncState.unknown,
        ListeningSyncState.rejected,
        ListeningSyncState.verified,
      ];
      for (final state in states) {
        await store.put(
          owner: 'netease:7',
          id: 'native-${state.name}',
          kind: 'netease-startplay',
          payload: const {
            'id': '17',
            'protocolVersion': 3,
            'time': 30,
            'realtime': 30,
            'heardMs': 30000,
          },
          now: now,
          state: state,
        );
      }
      await store.put(
        owner: 'netease:7',
        id: 'legacy-pending',
        kind: 'netease-scrobble',
        payload: const {
          'id': '17',
          'protocolVersion': 2,
          'time': 20,
          'heardMs': 20000,
        },
        now: now,
      );
      var writes = 0;
      final api = NeteaseApi(
        MockClient((request) async {
          writes++;
          expect(request.url.path, endsWith('/feedback/weblog'));
          return http.Response('{"code":200}', 200);
        }),
      )..configure(session);
      final feed = FakeFeed();
      addTearDown(feed.close);
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: NeteaseMusicRepository(api),
        store: store,
        current: () => true,
        observeLifecycle: false,
        automaticTimers: false,
      );
      await reporter.settle();
      await reporter.recoverPending();
      reporter.checkpoint();
      await reporter.settle();
      reporter.dispose();
      await reporter.settle();
      expect(writes, 1);
      for (final state in states) {
        final row = (await store.entry('netease:7', 'native-${state.name}'))!;
        expect(row.state, state);
        expect(row.updatedAt, now);
        expect(row.payload, {
          'id': '17',
          'protocolVersion': 3,
          'time': 30,
          'realtime': 30,
          'heardMs': 30000,
        });
      }
      expect(
        (await store.entry('netease:7', 'legacy-pending'))!.state,
        ListeningSyncState.accepted,
      );
      expect(
        await store.entry('netease:7', 'netease-native-sequence:v1'),
        isNull,
      );
    },
  );

  test(
    'disabled repository rejects accidental explicit native dispatch',
    () async {
      var requests = 0;
      final api = NeteaseApi(
        MockClient((_) async {
          requests++;
          return http.Response('{"code":200}', 200);
        }),
      )..configure(session);
      await expectLater(
        NeteaseMusicRepository(
          api,
        ).reportPlayback(id: '17', started: true, nativeSequence: 0),
        throwsException,
      );
      expect(requests, 0);
    },
  );
}
