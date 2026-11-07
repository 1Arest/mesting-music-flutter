import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_listening_reporter.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'release_107_listening_sync_test.dart' show FakeClock, FakeFeed;

const session = NeteaseSession(
  userId: '7',
  deviceId: 'fixture',
  cookies: {'MUSIC_U': 'synthetic-test-only'},
);
const song = Track(
  id: 'netease_17',
  title: '测试歌曲',
  artist: '测试歌手',
  album: '测试专辑',
  duration: Duration(minutes: 4),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
  platformSongId: '17',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reports only real ready, non-seeking elapsed time and sends one event',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      final feed = FakeFeed(), clock = FakeClock();
      var requests = 0;
      final api = NeteaseApi(
        MockClient((req) async {
          requests++;
          expect(req.url.path, endsWith('/feedback/weblog'));
          return http.Response('{"code":200}', 200);
        }),
      )..configure(session);
      feed.setTrack(song);
      feed.setState(true, true);
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: NeteaseMusicRepository(api),
        store: store,
        current: () => true,
        clock: clock,
        observeLifecycle: false,
        automaticTimers: false,
      );
      clock.elapse(5000);
      feed.setState(false, true);
      clock.elapse(2000);
      feed.setState(true, false);
      clock.elapse(3000);
      feed.setState(true, true);
      feed.seek(true);
      clock.elapse(4000);
      feed.seek(false);
      clock.elapse(1000);
      feed.setTrack(null);
      await reporter.settle();
      final rows = await store.entries('netease:7');
      final duration = rows.singleWhere((r) => r.kind == 'netease-scrobble');
      expect(duration.number('time'), 6);
      expect(duration.state, ListeningSyncState.accepted);
      expect(rows.where((r) => r.kind == 'netease-startplay'), hasLength(1));
      expect(requests, 2);
      reporter.dispose();
      await reporter.settle();
      expect(requests, 2);
    },
  );
  test(
    'switching accounts checkpoints under the original owner without sending',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      final feed = FakeFeed(), clock = FakeClock();
      var current = true, requests = 0;
      final api = NeteaseApi(
        MockClient((_) async {
          requests++;
          return http.Response('{"code":200}', 200);
        }),
      )..configure(session);
      feed.setTrack(song);
      feed.setState(false, true);
      final reporter = NeteaseListeningReporter(
        feed: feed,
        music: NeteaseMusicRepository(api),
        store: store,
        current: () => current,
        clock: clock,
        observeLifecycle: false,
        automaticTimers: false,
      );
      await reporter.settle();
      feed.setState(true, true);
      clock.elapse(4000);
      current = false;
      api.configure(null);
      reporter.dispose();
      await reporter.settle();
      final rows = await store.entries('netease:7');
      expect(rows.single.number('time'), 4);
      expect(rows.single.state, ListeningSyncState.queued);
      expect(requests, 0);
    },
  );
  test(
    'uncertain writes are not automatically replayed after restart',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = ListeningSyncStore(db);
      var requests = 0;
      final api = NeteaseApi(
        MockClient((_) async {
          requests++;
          throw http.ClientException('interrupted');
        }),
      )..configure(session);
      await store.put(
        owner: 'netease:7',
        id: 'crash',
        kind: 'netease-scrobble',
        payload: {'id': '17', 'time': 5, 'heardMs': 5000},
        now: DateTime(2026, 10, 29),
      );
      NeteaseListeningReporter reporter() => NeteaseListeningReporter(
        feed: FakeFeed(),
        music: NeteaseMusicRepository(api),
        store: store,
        current: () => true,
        observeLifecycle: false,
        automaticTimers: false,
      );
      final first = reporter();
      await first.settle();
      first.dispose();
      await first.settle();
      expect(
        (await store.entry('netease:7', 'crash'))!.state,
        ListeningSyncState.unknown,
      );
      final second = reporter();
      await second.settle();
      second.dispose();
      await second.settle();
      expect(requests, 1);
    },
  );
  test('never reports Kugou or local tracks to NetEase', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = ListeningSyncStore(db);
    final feed = FakeFeed(), clock = FakeClock();
    var requests = 0;
    final api = NeteaseApi(
      MockClient((_) async {
        requests++;
        return http.Response('{"code":200}', 200);
      }),
    )..configure(session);
    feed.setTrack(
      const Track(
        id: 'local',
        title: '本地',
        artist: '',
        album: '',
        duration: Duration(minutes: 1),
        audioAsset: 'file:///music',
        coverAsset: '',
        lyricsAsset: '',
      ),
    );
    feed.setState(true, true);
    final reporter = NeteaseListeningReporter(
      feed: feed,
      music: NeteaseMusicRepository(api),
      store: store,
      current: () => true,
      clock: clock,
      observeLifecycle: false,
      automaticTimers: false,
    );
    clock.elapse(10000);
    feed.setTrack(null);
    await reporter.settle();
    reporter.dispose();
    await reporter.settle();
    expect(await store.entries('netease:7'), isEmpty);
    expect(requests, 0);
  });
}
