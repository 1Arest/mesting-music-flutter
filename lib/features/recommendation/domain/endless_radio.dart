import '../../../shared/models/track.dart';
import 'personalized_recommendation.dart';

const int endlessRadioBatchSize = 72;

const _explorationQueries = <String>[
  '华语流行',
  'indie pop',
  '摇滚 live',
  '民谣 acoustic',
  '电子音乐',
  'R&B soul',
  '说唱 hip hop',
  '爵士 blues',
  '轻音乐 ambient',
  '电影原声',
  '治愈音乐',
  'lofi study',
  'piano instrumental',
  'alternative music',
  'dance music',
  'singer songwriter',
  'world music',
  '新歌推荐',
  'city pop',
  'synthwave',
  'post rock',
  'neo soul',
  'classical crossover',
  'chillout',
  'bedroom pop',
  'dream pop',
  'funk groove',
  'bossa nova',
  'latin pop',
  'afrobeat',
  'reggae music',
  'metal music',
  'punk rock',
  'blues guitar',
  'orchestral music',
  'game soundtrack',
  'anime music',
  '粤语流行',
  '华语独立',
  '经典老歌',
  '现场音乐',
  '通勤音乐',
  '夜晚音乐',
  '清晨音乐',
  '运动音乐',
];

const _styleQueries = <String, String>{
  'pop': '流行音乐',
  'rnb': 'R&B soul',
  'rock': '摇滚 live',
  'folk': '民谣 acoustic',
  'electronic': '电子音乐',
  'rap': '说唱 hip hop',
  'instrumental': '轻音乐 instrumental',
  'soundtrack': '电影原声 soundtrack',
  'jazz': '爵士 blues',
  'lofi': 'lofi study',
  'ballad': '治愈情歌',
};

/// Produces a small rotating set of discovery seeds. At most one seed is a
/// specific artist; the remaining slots always rotate across styles so a
/// strong favorite cannot collapse the radio into a single genre.
List<String> endlessRadioDiscoveryQueries({
  List<Track> preferenceTracks = const <Track>[],
  int round = 0,
  int maxQueries = 5,
}) {
  if (maxQueries <= 0) return const <String>[];
  final safeRound = round < 0 ? 0 : round;
  final queries = <String>[];
  final seen = <String>{};

  void add(String raw) {
    if (queries.length >= maxQueries) return;
    final value = raw.trim();
    if (value.isEmpty || !seen.add(value.toLowerCase())) return;
    queries.add(value);
  }

  if (preferenceTracks.isNotEmpty) {
    final preference = preferenceTracks[safeRound % preferenceTracks.length];
    final artist = preference.artist.trim();
    if (_isUsefulArtist(artist)) add(artist);

    final styles = recommendationStyleTagsForTrack(
      preference,
    ).where((style) => style != 'general').toList(growable: false);
    if (styles.isNotEmpty) {
      add(_styleQueries[styles[safeRound % styles.length]] ?? styles.first);
    }
  }

  var offset = 0;
  while (queries.length < maxQueries && offset < _explorationQueries.length) {
    final index = (safeRound * 7 + offset * 11) % _explorationQueries.length;
    add(_explorationQueries[index]);
    offset += 1;
  }
  return List<String>.unmodifiable(queries);
}

List<Track> rankEndlessRadioBatch({
  required DateTime now,
  required int round,
  List<Track> discoveredTracks = const <Track>[],
  List<Track> hotTracks = const <Track>[],
  List<ListeningSignal> listeningSignals = const <ListeningSignal>[],
  List<Track> favoriteTracks = const <Track>[],
  Set<String> excludedTrackKeys = const <String>{},
  int limit = endlessRadioBatchSize,
}) {
  if (limit <= 0) return const <Track>[];
  final candidates = <Track>[];
  final seen = <String>{...excludedTrackKeys};
  for (final track in <Track>[...discoveredTracks, ...hotTracks]) {
    final key = recommendationTrackKey(track);
    if (!track.isPlayable || !seen.add(key)) continue;
    candidates.add(track);
  }
  if (candidates.isEmpty) return const <Track>[];

  // Advancing the deterministic date seed per refill prevents a stable daily
  // sort from repeatedly returning the same head of a large remote catalogue.
  final rankingDate = now.toLocal().add(Duration(days: round < 0 ? 0 : round));
  return personalizedRecommendationTracksForDate(
    rankingDate,
    localTracks: const <Track>[],
    onlineTracks: candidates,
    listeningSignals: listeningSignals,
    favoriteTracks: favoriteTracks,
    limit: limit.clamp(0, candidates.length),
  );
}

bool _isUsefulArtist(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return normalized.isNotEmpty &&
      normalized != '未知音乐人' &&
      normalized != 'unknown' &&
      normalized != 'variousartists';
}
