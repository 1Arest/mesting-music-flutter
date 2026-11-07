import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/recommendation/domain/personalized_recommendation.dart';
import 'package:mesting_music/features/search/domain/music_rankings.dart';
import 'package:mesting_music/shared/models/track.dart';

const _historyTrack = Track(
  id: 'history-old-url',
  title: '常听歌曲',
  artist: '熟悉歌手',
  album: '播放记录',
  duration: Duration(minutes: 4),
  audioAsset: 'https://expired.example.com/history.mp3',
  coverAsset: 'https://expired.example.com/history.jpg',
  lyricsAsset: '',
  source: TrackSource.kugou,
);

const _freshHistoryTrack = Track(
  id: 'history-fresh-url',
  title: '常听歌曲',
  artist: '熟悉歌手',
  album: '实时榜单',
  duration: Duration(minutes: 4),
  audioAsset: 'https://fresh.example.com/history.mp3',
  coverAsset: 'https://fresh.example.com/history.jpg',
  lyricsAsset: '',
  source: TrackSource.kugou,
);

const _favoriteTrack = Track(
  id: 'favorite',
  title: '收藏歌曲',
  artist: '收藏歌手',
  album: '我的收藏',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/favorite.mp3',
  coverAsset: 'https://example.com/favorite.jpg',
  lyricsAsset: '',
  source: TrackSource.kugou,
);

const _hotArtistATrack = Track(
  id: 'hot-artist-a',
  title: '热门歌曲 A',
  artist: '近期歌手 A',
  album: '热搜榜',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/hot-a.mp3',
  coverAsset: 'https://example.com/hot-a.jpg',
  lyricsAsset: '',
  source: TrackSource.kugou,
);

const _hotArtistBTrack = Track(
  id: 'hot-artist-b',
  title: '热门歌曲 B',
  artist: '近期歌手 B',
  album: '热歌榜',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/hot-b.mp3',
  coverAsset: 'https://example.com/hot-b.jpg',
  lyricsAsset: '',
  source: TrackSource.kugou,
);

const _hotArtistCTrack = Track(
  id: 'hot-artist-c',
  title: '热门歌曲 C',
  artist: '近期歌手 C',
  album: '飙升榜',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/hot-c.mp3',
  coverAsset: 'https://example.com/hot-c.jpg',
  lyricsAsset: '',
  source: TrackSource.kugou,
);

void main() {
  test('我的热榜结合播放频次、最近播放和收藏，并优先使用新鲜播放地址', () {
    final ranking = personalHotRanking(
      listeningSignals: [
        ListeningSignal(
          track: _historyTrack,
          playCount: 8,
          totalListened: const Duration(minutes: 28),
          lastPlayedAt: DateTime(2026, 7, 23, 20),
        ),
      ],
      favoriteTracks: const [_favoriteTrack],
      freshTracks: const [_freshHistoryTrack],
      now: DateTime(2026, 7, 23, 23),
    );

    expect(ranking, hasLength(2));
    expect(ranking.first.id, _freshHistoryTrack.id);
    expect(ranking.first.audioAsset, contains('fresh.example.com'));
    expect(ranking.last.id, _favoriteTrack.id);
  });

  test('没有播放和收藏记录时我的热榜为空', () {
    expect(
      personalHotRanking(listeningSignals: const [], favoriteTracks: const []),
      isEmpty,
    );
  });

  test('首次使用时从近期三张榜单生成热门歌手推荐', () {
    final suggestions = artistSuggestionsForUser(
      listeningSignals: const [],
      favoriteTracks: const [],
      hotTracks: const [_hotArtistATrack, _hotArtistBTrack],
      popularTracks: const [_hotArtistBTrack, _hotArtistATrack],
      risingTracks: const [_hotArtistCTrack],
    );

    expect(suggestions.source, ArtistSuggestionSource.trending);
    expect(suggestions.label, '近期热门歌手');
    expect(
      suggestions.artists.take(3),
      containsAll(const ['近期歌手 A', '近期歌手 B', '近期歌手 C']),
    );
    expect(suggestions.artists, hasLength(10));
  });

  test('有用户画像时猜你喜欢优先结合播放和收藏歌手', () {
    final suggestions = artistSuggestionsForUser(
      listeningSignals: [
        ListeningSignal(
          track: _historyTrack,
          playCount: 8,
          totalListened: const Duration(minutes: 28),
          lastPlayedAt: DateTime(2026, 7, 23, 20),
        ),
      ],
      favoriteTracks: const [_favoriteTrack],
      hotTracks: const [_hotArtistATrack, _hotArtistBTrack],
      now: DateTime(2026, 7, 23, 23),
    );

    expect(suggestions.source, ArtistSuggestionSource.personalized);
    expect(suggestions.label, '根据播放与收藏');
    expect(suggestions.artists.first, '熟悉歌手');
    expect(suggestions.artists.take(2), contains('收藏歌手'));
    expect(suggestions.artists, contains('近期歌手 A'));
  });

  test('误触式短播放不会污染首次使用的热门推荐', () {
    final suggestions = artistSuggestionsForUser(
      listeningSignals: [
        ListeningSignal(
          track: _historyTrack,
          playCount: 1,
          totalListened: const Duration(seconds: 2),
          lastPlayedAt: DateTime(2026, 7, 23, 20),
        ),
      ],
      favoriteTracks: const [],
      hotTracks: const [_hotArtistATrack],
      now: DateTime(2026, 7, 23, 23),
    );

    expect(suggestions.source, ArtistSuggestionSource.trending);
    expect(suggestions.artists.first, '近期歌手 A');
    expect(suggestions.artists, isNot(contains('熟悉歌手')));
  });
}
