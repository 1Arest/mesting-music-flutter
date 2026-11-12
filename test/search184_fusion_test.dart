import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/search/data/fused_song_search.dart';
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/cross_platform_music_scope.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: '184',
    token: 'synthetic-owner',
    platform: MusicPlatform.netease,
  );
  void select(PlatformSession value) => state = AsyncData(value);
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18400');
}

MusicPlatformApi _api() => MusicPlatformApi(
  server: _Server(),
  client: MockClient((_) async => http.Response('{}', 200)),
);
Track song(
  String id,
  TrackSource source, {
  String title = '晴天',
  String artist = '周杰伦',
  int seconds = 269,
}) => Track(
  id: id,
  source: source,
  title: title,
  artist: artist,
  album: '叶惠美',
  duration: Duration(seconds: seconds),
  audioAsset: 'mesting-platform://${source.name}/$id',
  coverAsset: '',
  lyricsAsset: '',
);

class _Source extends PlatformSearchRepository {
  _Source(this.load) : super(_api());
  final Future<PlatformSearchPage> Function(String, int) load;
  @override
  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) => load(query, page);
}

class _NeteaseSource extends NeteaseMusicRepository {
  _NeteaseSource(this.track)
    : super(NeteaseApi(MockClient((_) async => throw StateError('fixture'))));
  final Track track;
  @override
  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abort,
  }) async => PlatformSearchPage([track], 1, false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final n = song('netease_1', TrackSource.netease);
  final k = song('kugou_1', TrackSource.kugou, seconds: 270);
  test(
    'production provider fuses both source adapters under the same NetEase owner',
    () async {
      if (!DistributionChannel.isBeta) return;
      SharedPreferences.setMockInitialValues({});
      final sourceApi = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          expect(request.url.path, '/search');
          return http.Response(
            '{"status":1,"data":{"total":1,"lists":[{"FileHash":"1","SongName":"晴天","SingerName":"周杰伦","TimeLength":270}]}}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final scope = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Account.new),
          musicPlatformApiProvider.overrideWithValue(_api()),
          neteaseMusicRepositoryProvider.overrideWithValue(_NeteaseSource(n)),
          supplementaryKugouApiProvider.overrideWith((_) async => sourceApi),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(scope.dispose);
      await scope.read(platformAccountProvider.future);
      expect(
        scope.read(platformSearchRepositoryProvider),
        isA<FusedSongSearchRepository>(),
      );
      await scope.read(musicSearchControllerProvider.notifier).submit('晴天');
      final result = scope.read(musicSearchControllerProvider);
      expect(result.onlineTracks.single.id, n.id);
      expect(result.sourceChoices[n.id]!.map((t) => t.source), [
        TrackSource.netease,
        TrackSource.kugou,
      ]);
      expect(result.hasMore, false);
      expect(
        scope.read(platformAccountProvider).value!.platform,
        MusicPlatform.netease,
      );
    },
  );
  test(
    'same recording is one row with current source preferred in either direction',
    () {
      final merged = groupSongSearchResults([n], [k], hasMore: false);
      expect(merged.tracks.map((t) => t.id), ['netease_1']);
      expect(merged.sources[n.id]!.map((t) => t.id), ['netease_1', 'kugou_1']);
      expect(merged.sources[k.id], same(merged.sources[n.id]));
      expect(
        groupSongSearchResults([k], [n], hasMore: false).tracks.single.id,
        k.id,
      );
    },
  );
  test('other source unique songs, covers and versions are not hidden', () {
    final cover = song('kugou_cover', TrackSource.kugou, artist: '翻唱歌手');
    final live = song('kugou_live', TrackSource.kugou, title: '晴天 (Live)');
    final differentTake = song('kugou_take', TrackSource.kugou, seconds: 310);
    final unknown = song('kugou_unknown', TrackSource.kugou, seconds: 0);
    final merged = groupSongSearchResults(
      [n],
      [k, cover, live, differentTake, unknown],
      hasMore: false,
    );
    expect(merged.tracks.map((t) => t.id), [
      n.id,
      cover.id,
      live.id,
      differentTake.id,
      unknown.id,
    ]);
  });
  test(
    'same-platform distinct IDs survive even inside a cross-source group',
    () {
      final second = song('kugou_2', TrackSource.kugou);
      final merged = groupSongSearchResults([n], [k, second], hasMore: false);
      expect(merged.tracks.map((t) => t.id), [n.id, second.id]);
      expect(merged.sources[n.id], hasLength(2));
      expect(merged.sources[second.id], hasLength(1));
    },
  );
  test(
    'one repeating source stops while the other source can finish',
    () async {
      final calls = <String>[];
      final repo = FusedSongSearchRepository(
        _api(),
        primary: _Source((_, page) async {
          calls.add('n$page');
          return PlatformSearchPage([n], null, true);
        }),
        secondary: () async => _Source((_, page) async {
          calls.add('k$page');
          return PlatformSearchPage(
            [song('kugou_$page', TrackSource.kugou, title: '独有$page')],
            null,
            page < 3,
          );
        }),
        primaryLabel: '网易云',
        secondaryLabel: '酷狗',
      );
      await repo.search('晴天');
      await repo.search('晴天', page: 2);
      final last = await repo.search('晴天', page: 3);
      expect(calls, ['n1', 'k1', 'n2', 'k2', 'k3']);
      expect(last.tracks, hasLength(4));
      expect(last.hasMore, false);
    },
  );
  test(
    'controller keeps chosen source after paging and clears it for next owner',
    () async {
      if (!DistributionChannel.isBeta) return;
      SharedPreferences.setMockInitialValues({});
      final api = _api();
      final repo = FusedSongSearchRepository(
        api,
        primary: _Source(
          (_, page) async => PlatformSearchPage(
            page == 1
                ? [n]
                : [song('netease_2', TrackSource.netease, title: '后来')],
            2,
            page == 1,
          ),
        ),
        secondary: () async =>
            _Source((_, _) async => PlatformSearchPage([k], 1, false)),
        primaryLabel: '网易云',
        secondaryLabel: '酷狗',
      );
      final scope = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Account.new),
          musicPlatformApiProvider.overrideWithValue(api),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          platformSearchRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(scope.dispose);
      await scope.read(platformAccountProvider.future);
      final controller = scope.read(musicSearchControllerProvider.notifier);
      await controller.submit('晴天');
      expect(
        scope.read(musicSearchControllerProvider).onlineTracks.single.id,
        n.id,
      );
      controller.chooseSongSource(n.id, k);
      await controller.loadMore();
      expect(
        scope.read(musicSearchControllerProvider).onlineTracks.map((t) => t.id),
        [k.id, 'netease_2'],
      );
      expect(
        scope.read(platformAccountProvider).value!.platform,
        MusicPlatform.netease,
      );
      (scope.read(platformAccountProvider.notifier) as _Account).select(
        const PlatformSession(
          userId: 'new',
          token: 'new-owner',
          platform: MusicPlatform.netease,
        ),
      );
      expect(scope.read(musicSearchControllerProvider).sourceChoices, isEmpty);
      expect(scope.read(musicSearchControllerProvider).onlineTracks, isEmpty);
    },
  );
  test(
    'failed supplementary page retries same cursor without hiding primary results',
    () async {
      final pages = <int>[];
      var attempts = 0;
      final primary = _Source(
        (_, _) async => PlatformSearchPage([n], 1, false),
      );
      final other = _Source((_, page) async {
        pages.add(page);
        if (attempts++ == 0) throw StateError('synthetic temporary failure');
        return PlatformSearchPage([k], 1, false);
      });
      final repo = FusedSongSearchRepository(
        _api(),
        primary: primary,
        secondary: () async => other,
        primaryLabel: '网易云',
        secondaryLabel: '酷狗',
      );
      final first = await repo.search('晴天') as FusedSongSearchPage;
      expect(first.tracks.single.id, n.id);
      expect(first.hasMore, true);
      expect(first.warnings, hasLength(1));
      final second = await repo.search('晴天', page: 2) as FusedSongSearchPage;
      expect(pages, [1, 1]);
      expect(second.tracks, hasLength(1));
      expect(second.sources[n.id], hasLength(2));
      expect(second.hasMore, false);
    },
  );
  test(
    'late old query cannot publish into the next query or mutate its cursor',
    () async {
      final pending = Completer<PlatformSearchPage>();
      final primary = _Source(
        (query, _) => query == 'old'
            ? pending.future
            : Future.value(PlatformSearchPage([n], 1, false)),
      );
      final other = _Source(
        (_, _) async => const PlatformSearchPage([], 0, false),
      );
      final repo = FusedSongSearchRepository(
        _api(),
        primary: primary,
        secondary: () async => other,
        primaryLabel: '网易云',
        secondaryLabel: '酷狗',
      );
      final old = repo.search('old');
      final rejected = expectLater(
        old,
        throwsA(isA<http.RequestAbortedException>()),
      );
      expect((await repo.search('new')).tracks.single.id, n.id);
      pending.complete(PlatformSearchPage([k], 1, false));
      await rejected;
      expect((await repo.search('new', page: 2)).tracks.single.id, n.id);
    },
  );
}
