import 'dart:math';

import '../../../shared/models/track.dart';
import '../data/daily_recommendations.dart';

/// A compact, privacy-friendly representation of implicit listening feedback.
///
/// The shape deliberately mirrors the inputs used by hybrid recommenders such
/// as LightFM: an item, interaction strength and recency. Keeping this model
/// independent from Drift also makes it possible to train a cloud model later
/// without changing the presentation layer.
class ListeningSignal {
  const ListeningSignal({
    required this.track,
    required this.playCount,
    required this.totalListened,
    required this.lastPlayedAt,
  });

  final Track track;
  final int playCount;
  final Duration totalListened;
  final DateTime lastPlayedAt;
}

const int defaultDailyRecommendationTrackCount = 14;
const int maximumDailyRecommendationTrackCount = 18;

class ConsecutiveDailyRecommendations {
  const ConsecutiveDailyRecommendations({
    required this.today,
    required this.yesterday,
  });

  final List<Track> today;
  final List<Track> yesterday;
}

DateTime recommendationPreferenceDate(DateTime recommendationDate) {
  final local = recommendationDate.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day,
  ).subtract(const Duration(days: 1));
}

List<ListeningSignal> recommendationPreferenceSignalsForDate(
  DateTime recommendationDate, {
  List<ListeningSignal> dailySignals = const [],
  List<ListeningSignal> legacySignals = const [],
}) {
  if (dailySignals.isNotEmpty) {
    return List<ListeningSignal>.unmodifiable(dailySignals);
  }

  final preferenceDate = recommendationPreferenceDate(recommendationDate);
  return List<ListeningSignal>.unmodifiable(
    legacySignals.where(
      (signal) => _isSameLocalDay(signal.lastPlayedAt, preferenceDate),
    ),
  );
}

int dailyRecommendationTrackLimit({
  List<ListeningSignal> previousDaySignals = const [],
}) {
  if (previousDaySignals.isEmpty) {
    return defaultDailyRecommendationTrackCount;
  }

  final uniqueTrackIds = <String>{};
  var meaningfulListenedMs = 0;
  var completedSignals = 0;
  for (final signal in previousDaySignals) {
    uniqueTrackIds.add(signal.track.id);
    final playCount = max(1, signal.playCount);
    final possibleMs = max(1, signal.track.duration.inMilliseconds * playCount);
    final listenedMs = signal.totalListened.inMilliseconds.clamp(0, possibleMs);
    final completion = listenedMs / possibleMs;
    if (completion >= .12) meaningfulListenedMs += listenedMs;
    if (completion >= .65) completedSignals += 1;
  }

  final varietyBonus = min(6, (uniqueTrackIds.length / 2).ceil());
  final listeningBonus = min(
    4,
    meaningfulListenedMs ~/ const Duration(minutes: 45).inMilliseconds,
  );
  final completionBonus =
      completedSignals / max(1, previousDaySignals.length) >= .6 ? 1 : 0;
  return (defaultDailyRecommendationTrackCount +
          varietyBonus +
          listeningBonus +
          completionBonus)
      .clamp(
        defaultDailyRecommendationTrackCount,
        maximumDailyRecommendationTrackCount,
      );
}

/// Generates yesterday first and explicitly excludes it from today's mix.
/// Both days share the available catalogue fairly, so consecutive lists stay
/// disjoint without starving today's recommendation when the pool is finite.
ConsecutiveDailyRecommendations consecutiveDailyRecommendations({
  required DateTime today,
  List<Track>? localTracks,
  List<Track> onlineTracks = const [],
  List<ListeningSignal> todayPreferenceSignals = const [],
  List<ListeningSignal> yesterdayPreferenceSignals = const [],
  List<Track> favoriteTracks = const [],
}) {
  final candidateCount = _playableUnique(<Track>[
    ...?localTracks,
    ...onlineTracks,
  ]).length;
  final balancedPerDayCapacity = candidateCount ~/ 2;
  final yesterdayLimit = min(
    dailyRecommendationTrackLimit(
      previousDaySignals: yesterdayPreferenceSignals,
    ),
    balancedPerDayCapacity,
  );
  final todayLimit = min(
    dailyRecommendationTrackLimit(previousDaySignals: todayPreferenceSignals),
    candidateCount - yesterdayLimit,
  );
  final yesterdayDate = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(const Duration(days: 1));
  final yesterdayTracks = personalizedRecommendationTracksForDate(
    yesterdayDate,
    localTracks: localTracks,
    onlineTracks: onlineTracks,
    listeningSignals: yesterdayPreferenceSignals,
    favoriteTracks: favoriteTracks,
    limit: yesterdayLimit,
  );
  final todayTracks = personalizedRecommendationTracksForDate(
    today,
    localTracks: localTracks,
    onlineTracks: onlineTracks,
    listeningSignals: todayPreferenceSignals,
    favoriteTracks: favoriteTracks,
    excludedTracks: yesterdayTracks,
    limit: todayLimit,
  );
  return ConsecutiveDailyRecommendations(
    today: todayTracks,
    yesterday: yesterdayTracks,
  );
}

/// Produces a deterministic daily mix from implicit feedback and track
/// metadata. It combines content affinity with exploration, so a small local
/// history can improve recommendations without trapping the listener in one
/// artist or requiring a server-side model.
List<Track> personalizedRecommendationTracksForDate(
  DateTime date, {
  List<Track>? localTracks,
  List<Track> onlineTracks = const [],
  List<ListeningSignal> listeningSignals = const [],
  List<Track> favoriteTracks = const [],
  List<Track> excludedTracks = const [],
  int limit = 8,
}) {
  final excludedKeys = excludedTracks.map(_trackKey).toSet();
  final eligibleLocalTracks = localTracks
      ?.where((track) => !excludedKeys.contains(_trackKey(track)))
      .toList(growable: false);
  final eligibleOnlineTracks = onlineTracks
      .where((track) => !excludedKeys.contains(_trackKey(track)))
      .toList(growable: false);
  if (listeningSignals.isEmpty && favoriteTracks.isEmpty) {
    return recommendationTracksForDate(
      date,
      localTracks: eligibleLocalTracks,
      onlineTracks: eligibleOnlineTracks,
      limit: limit,
    );
  }

  final candidates = _playableUnique(<Track>[
    ...?eligibleLocalTracks,
    ...eligibleOnlineTracks,
  ]);
  // `recommendationTracksForDate` owns the canonical demo-library fallback.
  // Reuse it when callers do not provide a local catalogue.
  final pool = candidates.isEmpty || eligibleLocalTracks == null
      ? _playableUnique(<Track>[
          ...recommendationTracksForDate(
            date,
            onlineTracks: eligibleOnlineTracks,
            limit: 1000,
          ),
          ...eligibleOnlineTracks,
        ])
      : candidates;
  if (pool.isEmpty || limit <= 0) return const <Track>[];

  final day = DateTime(date.year, date.month, date.day);
  final daySeed = day.difference(DateTime(2024)).inDays;
  final profile = <String, double>{};
  final recentTrackIds = <String, double>{};
  final preferredStyles = <String>{};

  for (final signal in listeningSignals) {
    final durationMs = max(1, signal.track.duration.inMilliseconds);
    final totalPossibleMs = max(1, signal.playCount) * durationMs;
    final completion = (signal.totalListened.inMilliseconds / totalPossibleMs)
        .clamp(0.0, 1.2);
    final ageDays = max(0, day.difference(signal.lastPlayedAt).inDays);
    final recency = exp(-ageDays / 45);
    final repeated = log(max(1, signal.playCount) + 1);
    // A very short listen is a weak negative signal; repeated and mostly
    // completed plays are strong positives.
    final strength = completion < .12
        ? -.85 * recency
        : (repeated * 1.15 + completion * 2.8) * (.45 + .55 * recency);
    _addTrackToProfile(profile, signal.track, strength);
    if (strength > 0) {
      preferredStyles.addAll(_styleTags(_trackText(signal.track)));
    }
    if (ageDays <= 2) {
      recentTrackIds[signal.track.id] = completion < .12 ? .35 : 1.0;
    }
  }
  for (final track in favoriteTracks) {
    _addTrackToProfile(profile, track, 5.5);
    preferredStyles.addAll(_styleTags(_trackText(track)));
  }

  final scored = <_ScoredTrack>[
    for (final track in pool)
      _ScoredTrack(
        track,
        _scoreTrack(
          track,
          profile: profile,
          recentPenalty: recentTrackIds[track.id] ?? 0,
          daySeed: daySeed,
        ),
        unfamiliarStyle: _styleTags(
          _trackText(track),
        ).every((style) => !preferredStyles.contains(style)),
      ),
  ]..sort((a, b) => b.score.compareTo(a.score));

  final remaining = scored.toList(growable: true);
  final result = <Track>[];
  final artistCounts = <String, int>{};
  final explorationAvailable = preferredStyles.isNotEmpty
      ? remaining.where((item) => item.unfamiliarStyle).length
      : 0;
  final explorationTarget = min(
    explorationAvailable,
    preferredStyles.isEmpty ? 0 : max(1, (limit * .25).round()),
  );
  var explorationCount = 0;
  var localCount = 0;
  var onlineCount = 0;

  while (result.length < limit && remaining.isNotEmpty) {
    final explorationNeeded = explorationTarget - explorationCount;
    final slotsLeft = limit - result.length;
    final shouldExplore =
        explorationNeeded > 0 &&
        ((result.length + 1) % 4 == 0 || slotsLeft <= explorationNeeded);
    final preferOnline = onlineCount <= localCount;
    var chosen = _findRecommendationCandidate(
      remaining,
      artistCounts: artistCounts,
      requireExploration: shouldExplore,
      preferredRemote: preferOnline,
      requirePreferredSource: true,
    );
    chosen = chosen >= 0
        ? chosen
        : _findRecommendationCandidate(
            remaining,
            artistCounts: artistCounts,
            requireExploration: shouldExplore,
            preferredRemote: preferOnline,
            requirePreferredSource: false,
          );
    if (chosen < 0 && shouldExplore) {
      chosen = _findRecommendationCandidate(
        remaining,
        artistCounts: artistCounts,
        requireExploration: true,
        preferredRemote: preferOnline,
        requirePreferredSource: false,
        enforceArtistLimit: false,
      );
    }
    chosen = chosen >= 0 ? chosen : 0;

    final item = remaining.removeAt(chosen);
    result.add(item.track);
    if (item.unfamiliarStyle) explorationCount += 1;
    if (item.track.isRemote) {
      onlineCount += 1;
    } else {
      localCount += 1;
    }
    final artist = _normalize(item.track.artist);
    artistCounts[artist] = (artistCounts[artist] ?? 0) + 1;
  }

  return List<Track>.unmodifiable(result);
}

void _addTrackToProfile(
  Map<String, double> profile,
  Track track,
  double strength,
) {
  final features = _featuresFor(track);
  for (final entry in features.entries) {
    profile.update(
      entry.key,
      (value) => value + strength * entry.value,
      ifAbsent: () => strength * entry.value,
    );
  }
}

double _scoreTrack(
  Track track, {
  required Map<String, double> profile,
  required double recentPenalty,
  required int daySeed,
}) {
  final features = _featuresFor(track);
  var affinity = 0.0;
  var totalWeight = 0.0;
  for (final entry in features.entries) {
    affinity += (profile[entry.key] ?? 0) * entry.value;
    totalWeight += entry.value;
  }
  if (totalWeight > 0) affinity /= sqrt(totalWeight);
  final discoveryJitter = _dailyJitter(track.id, daySeed) * .72;
  final remoteFreshness = track.isRemote ? .28 : 0.0;
  return affinity + discoveryJitter + remoteFreshness - recentPenalty * 1.35;
}

Map<String, double> _featuresFor(Track track) {
  final text = '${track.title} ${track.artist} ${track.album}'.toLowerCase();
  final features = <String, double>{
    'artist:${_normalize(track.artist)}': 3.0,
    'language:${_languageOf(text)}': 1.15,
    'source:${track.source.name}': .35,
    'duration:${track.duration.inMinutes.clamp(0, 6)}': .35,
  };
  for (final style in _styleTags(text)) {
    features['style:$style'] = 1.55;
  }
  return features;
}

Set<String> _styleTags(String text) {
  final tags = <String>{};
  const patterns = <String, List<String>>{
    'pop': ['流行', 'pop', '周杰伦', '陈粒', '薛之谦', '林俊杰'],
    'rnb': ['r&b', 'rnb', '节奏布鲁斯', '陶喆', '方大同'],
    'rock': ['摇滚', 'rock', 'live', '乐队'],
    'folk': ['民谣', 'folk', '故事', '公路'],
    'electronic': ['电子', 'electronic', 'edm', 'synth', 'dance'],
    'rap': ['说唱', 'rap', 'hip hop', 'hip-hop'],
    'instrumental': ['纯音乐', '轻音乐', '钢琴', 'piano', 'ambient'],
    'soundtrack': ['原声', 'soundtrack', '电影', 'anime'],
    'jazz': ['爵士', 'jazz', 'blues', '蓝调'],
    'lofi': ['lofi', 'lo-fi', 'study', '专注'],
    'ballad': ['慢歌', '情歌', '治愈', '深夜', '夜曲', '花海'],
  };
  for (final entry in patterns.entries) {
    if (entry.value.any(text.contains)) tags.add(entry.key);
  }
  if (tags.isEmpty) tags.add('general');
  return tags;
}

Set<String> recommendationStyleTagsForTrack(Track track) =>
    Set<String>.unmodifiable(_styleTags(_trackText(track)));

String recommendationTrackKey(Track track) => _trackKey(track);

String _languageOf(String value) {
  final chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(value).length;
  final latin = RegExp(r'[a-z]').allMatches(value).length;
  if (chinese > latin / 3) return 'zh';
  return latin > 0 ? 'foreign' : 'unknown';
}

int _findRecommendationCandidate(
  List<_ScoredTrack> candidates, {
  required Map<String, int> artistCounts,
  required bool requireExploration,
  required bool preferredRemote,
  required bool requirePreferredSource,
  bool enforceArtistLimit = true,
}) {
  for (var index = 0; index < candidates.length; index += 1) {
    final candidate = candidates[index];
    if (requireExploration && !candidate.unfamiliarStyle) continue;
    if (requirePreferredSource && candidate.track.isRemote != preferredRemote) {
      continue;
    }
    final artist = _normalize(candidate.track.artist);
    if (enforceArtistLimit && (artistCounts[artist] ?? 0) >= 2) continue;
    return index;
  }
  return -1;
}

String _trackText(Track track) =>
    '${track.title} ${track.artist} ${track.album}'.toLowerCase();

String _trackKey(Track track) =>
    '${_normalize(track.title)}|${_normalize(track.artist)}';

List<Track> _playableUnique(Iterable<Track> tracks) {
  final seen = <String>{};
  return tracks
      .where((track) {
        if (!track.isPlayable) return false;
        final key = '${_normalize(track.title)}|${_normalize(track.artist)}';
        return seen.add(key);
      })
      .toList(growable: true);
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^]]*\]'), '')
    .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

bool _isSameLocalDay(DateTime first, DateTime second) {
  final a = first.toLocal();
  final b = second.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

double _dailyJitter(String value, int daySeed) {
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final seed = (hash ^ (daySeed * 0x9E3779B9)) & 0xFFFFFFFF;
  return Random(seed).nextDouble();
}

class _ScoredTrack {
  const _ScoredTrack(this.track, this.score, {required this.unfamiliarStyle});

  final Track track;
  final double score;
  final bool unfamiliarStyle;
}
