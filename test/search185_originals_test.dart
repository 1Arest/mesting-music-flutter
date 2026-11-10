import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/search/data/fused_song_search.dart';
import 'package:mesting_music/shared/models/song_search_facts.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'search184_fusion_test.dart' show song;

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:18500');
}

MusicPlatformApi api() => MusicPlatformApi(
  server: _Server(),
  client: MockClient((_) async => throw StateError('No live network')),
);

class _Music extends NeteaseMusicRepository {
  _Music({this.failDetail = false})
    : super(
        NeteaseApi(
          MockClient((_) async => throw StateError('No live transport')),
        ),
      );
  final bool failDetail;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async {
    calls.add(route);
    if (route == '/search') {
      return {
        'result': {
          'songCount': 1,
          'songs': [
            {
              'id': 7,
              'name': '晴天 (原唱 周杰伦)',
              'artists': [
                {'name': '翻唱歌手'},
              ],
              'duration': 269000,
              'fee': 1,
              'originCoverType': 2,
              'privilege': {'pl': 0, 'st': -100},
              'originSongSimpleData': {
                'songId': 186016,
                'name': '晴天',
                'artists': [
                  {'id': 6452, 'name': '周杰伦'},
                ],
              },
            },
          ],
        },
      };
    }
    if (route == '/song/detail') {
      expect(query['ids'], ['186016']);
      if (failDetail) throw StateError('synthetic detail failure');
      return {
        'songs': [
          {
            'id': 186016,
            'name': '晴天',
            'ar': [
              {'name': '周杰伦'},
            ],
            'al': {'name': '叶惠美'},
            'dt': 269000,
            'fee': 1,
          },
        ],
        'privileges': [
          {'id': 186016, 'pl': 0, 'st': -100},
        ],
      };
    }
    throw StateError('Unexpected path $route');
  }
}

class _Source extends PlatformSearchRepository {
  _Source(this.page, this.access) : super(api());
  final PlatformSearchPage page;
  final SearchPlaybackAccess access;
  int inspected = 0;
  @override
  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async => this.page;
  @override
  Future<SongSearchFacts> inspectAvailability(
    Track track,
    SongSearchFacts facts, {
    Future<void>? abortTrigger,
  }) async {
    inspected++;
    return facts.withAccess(access);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unknown permission cannot displace an already confirmed playable trial',
    () {
      final n = song('netease_trial', TrackSource.netease),
          k = song('kugou_unknown', TrackSource.kugou);
      final result = groupSongSearchResults(
        [n],
        [k],
        hasMore: false,
        query: '晴天',
        facts: {
          n.id: const SongSearchFacts(
            kind: SearchRecordingKind.original,
            access: SearchPlaybackAccess.preview,
          ),
          k.id: const SongSearchFacts(kind: SearchRecordingKind.original),
        },
      );
      expect(result.tracks.single.id, n.id);
      expect(result.facts[k.id]!.access, SearchPlaybackAccess.unknown);
    },
  );
  test(
    'bounded permission budget checks paired sources before more current-platform variants',
    () async {
      final originals = [
        for (var i = 0; i < 7; i++) song('netease_$i', TrackSource.netease),
      ];
      final other = song('kugou_original', TrackSource.kugou);
      final primary = _Source(
        PlatformSearchPage(
          originals,
          7,
          false,
          facts: {
            for (final n in originals)
              n.id: const SongSearchFacts(
                kind: SearchRecordingKind.original,
                originalTitle: '晴天',
                originalArtists: ['周杰伦'],
              ),
          },
        ),
        SearchPlaybackAccess.preview,
      );
      final secondary = _Source(
        PlatformSearchPage([other], 1, false),
        SearchPlaybackAccess.full,
      );
      final repo = FusedSongSearchRepository(
        api(),
        primary: primary,
        secondary: () async => secondary,
        primaryLabel: '网易云',
        secondaryLabel: '酷狗',
      );
      final result = await repo.search('晴天') as FusedSongSearchPage;
      expect(secondary.inspected, 1);
      expect(primary.inspected + secondary.inspected, 6);
      expect(result.tracks.first.id, other.id);
      expect(result.sources[other.id], hasLength(2));
    },
  );
  test(
    'upstream-linked original is recovered without filtering member/restricted songs',
    () async {
      final music = _Music();
      final page = await music.search('晴天');
      expect(page.tracks.map((t) => t.id), ['netease_7', 'netease_186016']);
      expect(page.facts['netease_7']!.kind, SearchRecordingKind.cover);
      expect(page.facts['netease_186016']!.kind, SearchRecordingKind.original);
      expect(page.facts['netease_186016']!.membership, true);
      expect(
        page.facts['netease_186016']!.access,
        SearchPlaybackAccess.unknown,
      );
      expect(music.calls, ['/search', '/song/detail']);
      expect(page.hasMore, false);
      expect((await _Music().search('晴天 周杰伦')).tracks, hasLength(2));
      final unrelated = _Music();
      expect((await unrelated.search('周杰伦')).tracks, hasLength(1));
      expect(unrelated.calls, ['/search']);
    },
  );
  test(
    'failed enrichment keeps all restricted covers and never invents original row',
    () async {
      final result = await _Music(failDetail: true).search('晴天');
      expect(result.tracks.single.id, 'netease_7');
    },
  );
  test(
    'original full source precedes current platform cover and combines same recording trial',
    () async {
      final n = song('netease_186016', TrackSource.netease);
      final k = song('kugou_full', TrackSource.kugou, seconds: 270);
      final cover = song('netease_cover', TrackSource.netease, artist: '翻唱歌手');
      final primary = _Source(
        PlatformSearchPage(
          [cover, n],
          2,
          false,
          facts: {
            cover.id: const SongSearchFacts(
              kind: SearchRecordingKind.cover,
              originalArtists: ['周杰伦'],
              originalTitle: '晴天',
            ),
            n.id: const SongSearchFacts(
              kind: SearchRecordingKind.original,
              membership: true,
            ),
          },
        ),
        SearchPlaybackAccess.preview,
      );
      final other = _Source(
        PlatformSearchPage([k], 1, false),
        SearchPlaybackAccess.full,
      );
      final repo = FusedSongSearchRepository(
        api(),
        primary: primary,
        secondary: () async => other,
        primaryLabel: '网易云',
        secondaryLabel: '酷狗',
      );
      final result = await repo.search('晴天') as FusedSongSearchPage;
      expect(result.tracks.map((t) => t.id), [k.id, cover.id]);
      expect(result.sources[k.id]!.map((t) => t.id), [k.id, n.id]);
      expect(result.facts[k.id]!.label, '原唱 · 完整版');
      expect(result.facts[n.id]!.label, '原唱 · 试听');
      expect(primary.inspected, 1);
      expect(other.inspected, 1);
      expect(result.tracks, hasLength(2));
    },
  );
  test(
    'full current-source originals win ties; unrelated originals and titled covers do not masquerade',
    () {
      final n = song('netease_original', TrackSource.netease);
      final k = song('kugou_original', TrackSource.kugou);
      final cover = song(
        'kugou_cover',
        TrackSource.kugou,
        title: '晴天 (原唱 周杰伦)',
        artist: '其他歌手',
      );
      final unrelated = song(
        'netease_else',
        TrackSource.netease,
        title: '可惜不是你',
        artist: '梁静茹',
      );
      final result = groupSongSearchResults(
        [unrelated, n],
        [k, cover],
        hasMore: false,
        query: '晴天',
        facts: {
          n.id: const SongSearchFacts(
            kind: SearchRecordingKind.original,
            access: SearchPlaybackAccess.full,
            membership: true,
          ),
          k.id: const SongSearchFacts(
            kind: SearchRecordingKind.original,
            access: SearchPlaybackAccess.full,
          ),
          unrelated.id: const SongSearchFacts(
            kind: SearchRecordingKind.original,
          ),
          cover.id: const SongSearchFacts(kind: SearchRecordingKind.cover),
        },
      );
      expect(result.tracks.first.id, n.id);
      expect(result.tracks.last.id, unrelated.id);
      expect(result.facts[cover.id]!.kind, SearchRecordingKind.cover);
      expect(result.sources[n.id], hasLength(2));
    },
  );
}
