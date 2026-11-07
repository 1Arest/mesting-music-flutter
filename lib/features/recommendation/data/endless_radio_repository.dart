import '../../../shared/models/track.dart';
import '../../search/domain/music_source.dart';
import '../domain/personalized_recommendation.dart';

/// Expands the empty-queue radio catalogue without sharing cancellation state
/// with the user-facing search page.
class EndlessRadioRepository {
  EndlessRadioRepository({required List<MusicSource> sources})
    : _sources = List<MusicSource>.unmodifiable(sources);

  final List<MusicSource> _sources;

  Future<List<Track>> discover(
    Iterable<String> rawQueries, {
    int limitPerQuery = 8,
  }) async {
    final queries = <String>[];
    final seenQueries = <String>{};
    for (final rawQuery in rawQueries) {
      final query = rawQuery.trim();
      if (query.isEmpty || !seenQueries.add(query.toLowerCase())) continue;
      queries.add(query);
    }
    if (queries.isEmpty || limitPerQuery <= 0) return const <Track>[];

    final sources = _sources
        .where((source) => source.isConfigured)
        .toList(growable: false);
    if (sources.isEmpty) return const <Track>[];

    final batches = await Future.wait(<Future<List<Track>>>[
      for (final source in sources)
        for (final query in queries)
          _safeSearch(source, query, limit: limitPerQuery),
    ]);

    final result = <Track>[];
    final seenTracks = <String>{};
    for (final track in batches.expand((batch) => batch)) {
      if (!track.isRemote || !track.isPlayable) continue;
      if (!seenTracks.add(recommendationTrackKey(track))) continue;
      result.add(track);
    }
    return List<Track>.unmodifiable(result);
  }

  Future<List<Track>> _safeSearch(
    MusicSource source,
    String query, {
    required int limit,
  }) async {
    try {
      return await source.search(query, limit: limit);
    } on Object {
      // One unavailable provider must not stop radio discovery through the
      // remaining open music sources.
      return const <Track>[];
    }
  }
}
