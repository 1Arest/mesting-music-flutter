import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/recommendation/domain/personalized_recommendation.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  final date = DateTime(2026, 7, 23);

  test('新用户默认获得十四首推荐而活跃用户会动态增加', () {
    expect(dailyRecommendationTrackLimit(), 14);

    final lightSignals = [
      ListeningSignal(
        track: track('light', '轻听一首', '轻听歌手'),
        playCount: 1,
        totalListened: const Duration(minutes: 4),
        lastPlayedAt: date.subtract(const Duration(days: 1)),
      ),
    ];
    final activeSignals = List.generate(
      12,
      (index) => ListeningSignal(
        track: track('active_$index', '昨日常听$index', '歌手$index'),
        playCount: 2,
        totalListened: const Duration(minutes: 8),
        lastPlayedAt: date.subtract(const Duration(days: 1)),
      ),
    );

    final lightLimit = dailyRecommendationTrackLimit(
      previousDaySignals: lightSignals,
    );
    final activeLimit = dailyRecommendationTrackLimit(
      previousDaySignals: activeSignals,
    );
    expect(lightLimit, greaterThan(14));
    expect(activeLimit, greaterThan(lightLimit));
    expect(activeLimit, lessThanOrEqualTo(18));

    final candidates = List.generate(
      30,
      (index) =>
          track('candidate_$index', '候选歌曲$index', '候选歌手$index', remote: true),
    );
    final result = personalizedRecommendationTracksForDate(
      date,
      localTracks: const [],
      onlineTracks: candidates,
      limit: activeLimit,
    );
    expect(result, hasLength(activeLimit));
  });

  test('每日推荐只使用前一天的精确记录并兼容旧历史', () {
    final yesterday = ListeningSignal(
      track: track('yesterday', '昨天的摇滚', '昨日歌手'),
      playCount: 2,
      totalListened: const Duration(minutes: 7),
      lastPlayedAt: DateTime(2026, 7, 22, 23, 30),
    );
    final today = ListeningSignal(
      track: track('today', '今天试听', '今日歌手'),
      playCount: 1,
      totalListened: const Duration(minutes: 2),
      lastPlayedAt: DateTime(2026, 7, 23, 0, 5),
    );

    expect(recommendationPreferenceDate(date), DateTime(2026, 7, 22));
    expect(
      recommendationPreferenceSignalsForDate(
        date,
        legacySignals: [today, yesterday],
      ),
      [yesterday],
    );

    final precise = ListeningSignal(
      track: track('precise', '按日统计', '精准歌手'),
      playCount: 1,
      totalListened: const Duration(minutes: 4),
      lastPlayedAt: DateTime(2026, 7, 22, 12),
    );
    expect(
      recommendationPreferenceSignalsForDate(
        date,
        dailySignals: [precise],
        legacySignals: [yesterday],
      ),
      [precise],
      reason: '新按日记录存在时不应混入无法拆分日期的旧累计时长',
    );
  });

  test('昨天完整收听的风格会提高同风格候选歌曲顺位', () {
    final listened = track('rock_seed', '摇滚 Live 现场', '昨日乐队');
    final related = track('rock_related', '全新摇滚现场', '另一支乐队', remote: true);
    final unrelated = track('piano_unrelated', '安静钢琴纯音乐', '钢琴家', remote: true);
    final result = personalizedRecommendationTracksForDate(
      date,
      localTracks: const [],
      onlineTracks: [unrelated, related],
      listeningSignals: [
        ListeningSignal(
          track: listened,
          playCount: 3,
          totalListened: const Duration(minutes: 12),
          lastPlayedAt: date.subtract(const Duration(days: 1)),
        ),
      ],
      limit: 2,
    );

    expect(result.first.id, related.id);
  });

  test('重复听完与收藏会提高相同歌手和风格的推荐顺位', () {
    final liked = track('liked', '夜色故事', '偏爱歌手');
    final related = track('related', '新的旋律', '偏爱歌手', remote: true);
    final unrelated = track('unrelated', '陌生电音', '其他歌手', remote: true);
    final result = personalizedRecommendationTracksForDate(
      date,
      localTracks: [liked],
      onlineTracks: [unrelated, related],
      listeningSignals: [
        ListeningSignal(
          track: liked,
          playCount: 5,
          totalListened: const Duration(minutes: 18),
          lastPlayedAt: date.subtract(const Duration(days: 1)),
        ),
      ],
      favoriteTracks: [liked],
      limit: 3,
    );

    expect(result.indexOf(related), lessThan(result.indexOf(unrelated)));
  });

  test('个性化结果同一天稳定且跨天轮换探索歌曲', () {
    final candidates = List.generate(
      10,
      (index) => track('remote_$index', '歌曲$index', '歌手$index', remote: true),
    );
    final signalTrack = track('seed', '常听歌曲', '常听歌手');
    final signals = [
      ListeningSignal(
        track: signalTrack,
        playCount: 3,
        totalListened: const Duration(minutes: 9),
        lastPlayedAt: date,
      ),
    ];
    final first = personalizedRecommendationTracksForDate(
      date,
      localTracks: [signalTrack],
      onlineTracks: candidates,
      listeningSignals: signals,
      limit: 6,
    );
    final sameDay = personalizedRecommendationTracksForDate(
      DateTime(2026, 7, 23, 23, 59),
      localTracks: [signalTrack],
      onlineTracks: candidates,
      listeningSignals: signals,
      limit: 6,
    );
    final nextDay = personalizedRecommendationTracksForDate(
      DateTime(2026, 7, 24),
      localTracks: [signalTrack],
      onlineTracks: candidates,
      listeningSignals: signals,
      limit: 6,
    );

    expect(first.map((item) => item.id), sameDay.map((item) => item.id));
    expect(
      first.map((item) => item.id).join('|'),
      isNot(nextDay.map((item) => item.id).join('|')),
    );
  });

  test('有足够候选时兼顾在线、本地和歌手多样性', () {
    final local = List.generate(
      4,
      (index) => track('local_$index', '本地$index', '本地歌手$index'),
    );
    final online = List.generate(
      6,
      (index) => track(
        'online_$index',
        '在线$index',
        index < 4 ? '同一歌手' : '在线歌手$index',
        remote: true,
      ),
    );
    final result = personalizedRecommendationTracksForDate(
      date,
      localTracks: local,
      onlineTracks: online,
      favoriteTracks: [local.first],
      limit: 8,
    );

    expect(result.where((item) => item.isRemote), isNotEmpty);
    expect(result.where((item) => !item.isRemote), isNotEmpty);
    expect(
      result.where((item) => item.artist == '同一歌手').length,
      lessThanOrEqualTo(2),
    );
  });

  test('昨日与今日推荐严格不重复且默认各有十四首', () {
    final candidates = List.generate(
      40,
      (index) => track(
        'daily_$index',
        '每日候选$index',
        '歌手$index',
        remote: true,
        album: index.isEven ? '流行' : '轻音乐',
      ),
    );

    final recommendations = consecutiveDailyRecommendations(
      today: date,
      localTracks: const [],
      onlineTracks: candidates,
    );
    final yesterdayIds = recommendations.yesterday
        .map((item) => item.id)
        .toSet();
    final todayIds = recommendations.today.map((item) => item.id).toSet();

    expect(recommendations.yesterday, hasLength(14));
    expect(recommendations.today, hasLength(14));
    expect(yesterdayIds.intersection(todayIds), isEmpty);
  });

  test('有偏好时仍为用户未听过的风格保留四分之一探索位', () {
    final listened = track('rock_profile', '摇滚 Live', '常听乐队', album: '摇滚');
    final familiar = List.generate(
      12,
      (index) => track(
        'rock_$index',
        '摇滚新歌$index',
        '摇滚歌手$index',
        remote: true,
        album: '摇滚',
      ),
    );
    final discoveries = List.generate(
      6,
      (index) => track(
        'discovery_$index',
        index.isEven ? '电子新声$index' : '爵士新声$index',
        '探索歌手$index',
        remote: true,
        album: index.isEven ? '电子' : '爵士',
      ),
    );

    final result = personalizedRecommendationTracksForDate(
      date,
      localTracks: const [],
      onlineTracks: [...familiar, ...discoveries],
      listeningSignals: [
        ListeningSignal(
          track: listened,
          playCount: 8,
          totalListened: const Duration(minutes: 30),
          lastPlayedAt: date.subtract(const Duration(days: 1)),
        ),
      ],
      limit: 12,
    );

    expect(result.take(3).any((item) => item.id.startsWith('rock_')), isTrue);
    expect(
      result.where((item) => item.id.startsWith('discovery_')).length,
      greaterThanOrEqualTo(3),
    );
  });
}

Track track(
  String id,
  String title,
  String artist, {
  bool remote = false,
  String album = '流行治愈',
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    album: album,
    duration: const Duration(minutes: 4),
    audioAsset: remote ? 'https://example.com/$id.mp3' : 'assets/$id.mp3',
    coverAsset: 'assets/$id.jpg',
    lyricsAsset: '',
    source: remote ? TrackSource.kugou : TrackSource.local,
    provider: remote ? '在线' : '本地',
  );
}
