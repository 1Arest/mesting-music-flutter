import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/search/data/hot_music_repository.dart';
import 'package:mesting_music/features/search/data/kugou_music_source.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localSong = Track(
  id: 'local_hot',
  title: '晴天',
  artist: '周杰伦',
  album: '本地音乐',
  duration: Duration(minutes: 4),
  audioAsset: 'assets/audio/sunny.mp3',
  coverAsset: 'assets/images/sunny.jpg',
  lyricsAsset: 'assets/lyrics/sunny.lrc',
);

const _remoteSong = Track(
  id: 'kugou_hot',
  title: '晴天 (Live)',
  artist: '周杰伦',
  album: '实时榜',
  duration: Duration(minutes: 4),
  audioAsset: 'https://example.com/sunny.mp3',
  coverAsset: 'https://example.com/sunny.jpg',
  lyricsAsset: 'mesting-lyrics://kugou/hash',
  source: TrackSource.kugou,
  provider: '酷狗概念版',
);

const _popularSong = Track(
  id: 'kugou_popular',
  title: '网络热歌',
  artist: '热歌歌手',
  album: '热歌榜',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/popular.mp3',
  coverAsset: 'https://example.com/popular.jpg',
  lyricsAsset: 'mesting-lyrics://kugou/popular',
  source: TrackSource.kugou,
  provider: '酷狗概念版',
);

const _risingSong = Track(
  id: 'kugou_rising',
  title: '正在飙升',
  artist: '新晋歌手',
  album: '飙升榜',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/rising.mp3',
  coverAsset: 'https://example.com/rising.jpg',
  lyricsAsset: 'mesting-lyrics://kugou/rising',
  source: TrackSource.kugou,
  provider: '酷狗概念版',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('实时榜优先使用匹配的本地完整歌曲并复用半小时缓存', () async {
    final preferences = await SharedPreferences.getInstance();
    var calls = 0;
    final repository = HotMusicRepository(
      rankingLoader: ({int limit = 9}) async {
        calls += 1;
        return const [_remoteSong];
      },
      preferences: preferences,
      localTracks: const [_localSong],
      now: () => DateTime(2026, 7, 23, 10),
    );

    final first = await repository.load();
    final second = await repository.load();

    expect(first.tracks.first, _localSong);
    expect(first.sourceLabel, '酷狗实时榜');
    expect(second.fromCache, isTrue);
    expect(calls, 1);
  });

  test('网络失败时读取最近榜单并标记为离线缓存', () async {
    final preferences = await SharedPreferences.getInstance();
    final firstRepository = HotMusicRepository(
      rankingLoader: ({int limit = 9}) async => const [_remoteSong],
      preferences: preferences,
      localTracks: const [],
      now: () => DateTime(2026, 7, 23, 10),
    );
    await firstRepository.load();

    final offlineRepository = HotMusicRepository(
      rankingLoader: ({int limit = 9}) => throw StateError('offline'),
      preferences: preferences,
      localTracks: const [],
      now: () => DateTime(2026, 7, 23, 12),
    );
    final snapshot = await offlineRepository.load();

    expect(snapshot.tracks.single.id, _remoteSong.id);
    expect(snapshot.fromCache, isTrue);
    expect(snapshot.isStale, isTrue);
    expect(snapshot.statusLabel, '离线缓存');
  });

  test('热搜、热歌与飙升榜分别加载并一起缓存', () async {
    final preferences = await SharedPreferences.getInstance();
    var searchCalls = 0;
    var popularCalls = 0;
    var risingCalls = 0;
    final repository = HotMusicRepository(
      rankingLoader: ({int limit = 9}) async {
        searchCalls += 1;
        return const [_remoteSong];
      },
      popularRankingLoader: ({int limit = 9}) async {
        popularCalls += 1;
        return const [_popularSong];
      },
      risingRankingLoader: ({int limit = 9}) async {
        risingCalls += 1;
        return const [_risingSong];
      },
      preferences: preferences,
      localTracks: const [],
      now: () => DateTime(2026, 7, 23, 10),
    );

    final first = await repository.load();
    final cached = await repository.load();

    expect(first.tracks.single.id, _remoteSong.id);
    expect(first.popularTracks.single.id, _popularSong.id);
    expect(first.risingTracks.single.id, _risingSong.id);
    expect(
      first.recommendationTracks.map((track) => track.id),
      containsAll([_remoteSong.id, _popularSong.id, _risingSong.id]),
    );
    expect(cached.fromCache, isTrue);
    expect(cached.popularTracks.single.id, _popularSong.id);
    expect(cached.risingTracks.single.id, _risingSong.id);
    expect(cached.recommendationTracks, hasLength(3));
    expect((searchCalls, popularCalls, risingCalls), (1, 1, 1));
  });

  test('解析酷狗实时榜字段中的歌手、封面和歌曲标识', () {
    final candidates = KugouMusicSource.parseRankingCandidates({
      'songs': {
        'list': [
          {
            'hash': 'ABC123',
            'songname': '当下热门歌曲',
            'h5_author_name': '热门歌手',
            'duration': 215,
            'album_id': 88,
            'album_audio_id': 99,
            'album_sizable_cover':
                'http://imge.kugou.com/stdmusic/{size}/cover.jpg',
          },
        ],
      },
    });

    expect(candidates, hasLength(1));
    expect(candidates.single.title, '当下热门歌曲');
    expect(candidates.single.artist, '热门歌手');
    expect(candidates.single.hash, 'abc123');
    expect(candidates.single.coverUrl, contains('/400/cover.jpg'));
  });
}
