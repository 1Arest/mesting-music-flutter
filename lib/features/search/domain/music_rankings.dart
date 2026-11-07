import 'dart:math';

import '../../../shared/models/track.dart';
import '../../recommendation/domain/personalized_recommendation.dart';

enum ArtistSuggestionSource { personalized, trending, fallback }

class ArtistSuggestions {
  const ArtistSuggestions({required this.artists, required this.source});

  final List<String> artists;
  final ArtistSuggestionSource source;

  String get label => switch (source) {
    ArtistSuggestionSource.personalized => '根据播放与收藏',
    ArtistSuggestionSource.trending => '近期热门歌手',
    ArtistSuggestionSource.fallback => '热门歌手推荐',
  };
}

const _fallbackArtistSuggestions = <String>[
  '周杰伦',
  '林俊杰',
  '邓紫棋',
  '薛之谦',
  '陈粒',
  '五月天',
  '陈奕迅',
  '李荣浩',
  '海洋Bo',
  '虚拟',
];

/// Builds search shortcuts from private listening signals and fresh charts.
///
/// A user with meaningful playback or favorites gets a hybrid list: their
/// strongest artists first, followed by current chart artists for discovery.
/// With no usable profile, the three fresh charts become the cold-start model.
ArtistSuggestions artistSuggestionsForUser({
  required List<ListeningSignal> listeningSignals,
  required List<Track> favoriteTracks,
  List<Track> hotTracks = const [],
  List<Track> popularTracks = const [],
  List<Track> risingTracks = const [],
  DateTime? now,
  int limit = 10,
}) {
  if (limit <= 0) {
    return const ArtistSuggestions(
      artists: <String>[],
      source: ArtistSuggestionSource.fallback,
    );
  }

  final referenceTime = now ?? DateTime.now();
  final scores = <String, _ArtistScore>{};
  var trendOrder = 0;

  void addTrendingRanking(List<Track> tracks, double weight) {
    for (var index = 0; index < tracks.length; index += 1) {
      for (final artist in _individualArtists(tracks[index].artist)) {
        final entry = _artistScore(scores, artist);
        entry.trending += weight / (1 + index * .28);
        entry.firstTrendingOrder = min(entry.firstTrendingOrder, trendOrder);
        trendOrder += 1;
      }
    }
  }

  addTrendingRanking(hotTracks, 3.2);
  addTrendingRanking(popularTracks, 2.6);
  addTrendingRanking(risingTracks, 2.2);

  for (final signal in listeningSignals) {
    final durationMs = max(1, signal.track.duration.inMilliseconds);
    final possibleMs = max(1, signal.playCount) * durationMs;
    final completion = (signal.totalListened.inMilliseconds / possibleMs).clamp(
      0.0,
      1.2,
    );
    // A brief accidental preview should not become an artist preference.
    if (completion < .12) continue;
    final ageDays = max(
      0,
      referenceTime.difference(signal.lastPlayedAt).inDays,
    );
    final recency = exp(-ageDays / 45);
    final strength =
        log(max(1, signal.playCount) + 1) * 1.45 +
        completion * 3.4 +
        recency * 2.3;
    for (final artist in _individualArtists(signal.track.artist)) {
      final entry = _artistScore(scores, artist);
      entry.preference += strength;
      if (signal.lastPlayedAt.isAfter(entry.lastInteractionAt)) {
        entry.lastInteractionAt = signal.lastPlayedAt;
      }
    }
  }

  for (var index = 0; index < favoriteTracks.length; index += 1) {
    for (final artist in _individualArtists(favoriteTracks[index].artist)) {
      _artistScore(scores, artist).preference += 7.2 - min(index, 20) * .04;
    }
  }

  final preferred =
      scores.values
          .where((entry) => entry.preference > 0)
          .toList(growable: false)
        ..sort((a, b) {
          final score = (b.preference + b.trending * .35).compareTo(
            a.preference + a.trending * .35,
          );
          if (score != 0) return score;
          return b.lastInteractionAt.compareTo(a.lastInteractionAt);
        });
  final trending =
      scores.values.where((entry) => entry.trending > 0).toList(growable: false)
        ..sort((a, b) {
          final score = b.trending.compareTo(a.trending);
          if (score != 0) return score;
          return a.firstTrendingOrder.compareTo(b.firstTrendingOrder);
        });

  final source = preferred.isNotEmpty
      ? ArtistSuggestionSource.personalized
      : trending.isNotEmpty
      ? ArtistSuggestionSource.trending
      : ArtistSuggestionSource.fallback;
  final result = <String>[];
  final emitted = <String>{};

  void addArtists(Iterable<_ArtistScore> candidates, {int? maximum}) {
    var added = 0;
    for (final entry in candidates) {
      if (result.length >= limit || (maximum != null && added >= maximum)) {
        break;
      }
      if (emitted.add(_normalize(entry.name))) {
        result.add(entry.name);
        added += 1;
      }
    }
  }

  if (preferred.isNotEmpty) {
    addArtists(preferred, maximum: min(6, limit));
  }
  addArtists(trending);
  if (result.length < limit) {
    for (final artist in _fallbackArtistSuggestions) {
      if (result.length >= limit) break;
      if (emitted.add(_normalize(artist))) result.add(artist);
    }
  }

  return ArtistSuggestions(
    artists: List<String>.unmodifiable(result),
    source: source,
  );
}

List<Track> personalHotRanking({
  required List<ListeningSignal> listeningSignals,
  required List<Track> favoriteTracks,
  List<Track> freshTracks = const [],
  DateTime? now,
  int limit = 9,
}) {
  if (limit <= 0) return const [];
  final referenceTime = now ?? DateTime.now();
  final freshByKey = <String, Track>{
    for (final track in freshTracks.where((track) => track.isPlayable))
      _trackKey(track): track,
  };
  final favorites = <String>{
    for (final track in favoriteTracks) _trackKey(track),
  };
  final ranked = <String, _PersonalRankEntry>{};

  for (final signal in listeningSignals) {
    final key = _trackKey(signal.track);
    final track = freshByKey[key] ?? signal.track;
    if (!track.isPlayable) continue;
    final durationMs = max(1, signal.track.duration.inMilliseconds);
    final possibleMs = max(1, signal.playCount) * durationMs;
    final completion = (signal.totalListened.inMilliseconds / possibleMs).clamp(
      0.0,
      1.2,
    );
    final ageHours = max(
      0,
      referenceTime.difference(signal.lastPlayedAt).inHours,
    );
    final recency = exp(-ageHours / (24 * 21));
    final score =
        log(signal.playCount + 1) * 4.2 +
        completion * 3.4 +
        recency * 3.1 +
        (favorites.contains(key) ? 5.5 : 0);
    ranked[key] = _PersonalRankEntry(
      track: track,
      score: score,
      lastPlayedAt: signal.lastPlayedAt,
    );
  }

  for (var index = 0; index < favoriteTracks.length; index++) {
    final favorite = favoriteTracks[index];
    final key = _trackKey(favorite);
    final track = freshByKey[key] ?? favorite;
    if (!track.isPlayable || ranked.containsKey(key)) continue;
    ranked[key] = _PersonalRankEntry(
      track: track,
      score: 5.5 - index * .02,
      lastPlayedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final result = ranked.values.toList(growable: false)
    ..sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final recency = b.lastPlayedAt.compareTo(a.lastPlayedAt);
      if (recency != 0) return recency;
      return a.track.title.compareTo(b.track.title);
    });
  return List<Track>.unmodifiable(
    result.take(limit).map((entry) => entry.track),
  );
}

String _trackKey(Track track) =>
    '${_normalize(track.title)}|${_normalize(track.artist)}';

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^]]*\]'), '')
    .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

class _PersonalRankEntry {
  const _PersonalRankEntry({
    required this.track,
    required this.score,
    required this.lastPlayedAt,
  });

  final Track track;
  final double score;
  final DateTime lastPlayedAt;
}

_ArtistScore _artistScore(Map<String, _ArtistScore> scores, String artist) {
  final key = _normalize(artist);
  return scores.putIfAbsent(key, () => _ArtistScore(artist));
}

Iterable<String> _individualArtists(String rawArtist) sync* {
  final normalizedRaw = rawArtist.trim();
  if (normalizedRaw.isEmpty) return;
  final artists = normalizedRaw.split(
    RegExp(r'\s*(?:、|,|，|&|＆|/|\+|feat\.?|ft\.?)\s*', caseSensitive: false),
  );
  final emitted = <String>{};
  for (final artist in artists) {
    final cleaned = artist.trim();
    final key = _normalize(cleaned);
    if (cleaned.isEmpty ||
        key.isEmpty ||
        key == '未知歌手' ||
        key == '群星' ||
        key == 'variousartists' ||
        !emitted.add(key)) {
      continue;
    }
    yield cleaned;
  }
}

class _ArtistScore {
  _ArtistScore(this.name);

  final String name;
  double preference = 0;
  double trending = 0;
  int firstTrendingOrder = 1 << 30;
  DateTime lastInteractionAt = DateTime.fromMillisecondsSinceEpoch(0);
}
