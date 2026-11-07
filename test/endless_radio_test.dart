import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/recommendation/data/endless_radio_repository.dart';
import 'package:mesting_music/features/recommendation/domain/endless_radio.dart';
import 'package:mesting_music/features/recommendation/domain/personalized_recommendation.dart';
import 'package:mesting_music/features/recommendation/recommendation_providers.dart';
import 'package:mesting_music/features/search/domain/music_source.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  group('endless radio discovery', () {
    test('uses one preference seed and keeps rotating exploration styles', () {
      final favorite = _track(
        'favorite',
        title: 'Favorite Rock Live',
        artist: 'Favorite Artist',
        album: 'Rock',
      );

      final first = endlessRadioDiscoveryQueries(
        preferenceTracks: [favorite],
        round: 0,
      );
      final next = endlessRadioDiscoveryQueries(
        preferenceTracks: [favorite],
        round: 1,
      );

      expect(first, hasLength(5));
      expect(first.first, 'Favorite Artist');
      expect(first, contains('摇滚 live'));
      expect(next, hasLength(5));
      expect(next, isNot(equals(first)));
    });

    test(
      'many refill rounds keep rotating through a broad query catalogue',
      () {
        final rounds = <String>{};
        final allQueries = <String>{};
        for (var round = 0; round < 12; round += 1) {
          final queries = endlessRadioDiscoveryQueries(round: round);
          expect(queries, hasLength(5));
          rounds.add(queries.join('|'));
          allQueries.addAll(queries);
        }

        expect(rounds, hasLength(12));
        expect(allQueries.length, greaterThanOrEqualTo(35));
      },
    );

    test('filters the whole session history before personalized ranking', () {
      final excluded = _track(
        'excluded',
        title: 'Already Played',
        artist: 'Known Artist',
      );
      final candidates = <Track>[
        excluded,
        for (var index = 0; index < 20; index += 1)
          _track(
            'candidate_$index',
            title: index.isEven ? 'Pop Song $index' : 'Jazz Song $index',
            artist: 'Artist ${index ~/ 2}',
            album: index.isEven ? 'Pop' : 'Jazz',
          ),
      ];

      final result = rankEndlessRadioBatch(
        now: DateTime(2026, 7, 26),
        round: 3,
        discoveredTracks: candidates,
        favoriteTracks: [
          _track(
            'favorite',
            title: 'Favorite Pop',
            artist: 'Favorite Artist',
            album: 'Pop',
          ),
        ],
        excludedTrackKeys: {recommendationTrackKey(excluded)},
        limit: 12,
      );

      expect(result, hasLength(12));
      expect(
        result.map(recommendationTrackKey),
        isNot(contains(recommendationTrackKey(excluded))),
      );
      final counts = <String, int>{};
      for (final track in result) {
        counts.update(track.artist, (value) => value + 1, ifAbsent: () => 1);
      }
      expect(counts.values.every((count) => count <= 2), isTrue);
      expect(
        result.any(
          (track) => recommendationStyleTagsForTrack(track).contains('jazz'),
        ),
        isTrue,
      );
    });

    test(
      'queries every configured source and semantic-deduplicates results',
      () async {
        final first = _FakeSource('first', [
          _track('one', title: '甲乙丙丁（你我怎么两清）', artist: 'Same Artist'),
          _track('unique', title: 'Unique Song', artist: 'Other Artist'),
        ]);
        final second = _FakeSource('second', [
          _track('duplicate', title: '甲乙丙丁', artist: 'Same Artist'),
          _track(
            'not_playable',
            title: 'No Audio',
            artist: 'Other Artist',
            playable: false,
          ),
        ]);
        final disabled = _FakeSource('disabled', const [], configured: false);
        final repository = EndlessRadioRepository(
          sources: [first, second, disabled],
        );

        final result = await repository.discover(const [
          'rock',
          'jazz',
        ], limitPerQuery: 5);

        expect(first.queries, ['rock', 'jazz']);
        expect(second.queries, ['rock', 'jazz']);
        expect(disabled.queries, isEmpty);
        expect(result.map((track) => track.title), [
          '甲乙丙丁（你我怎么两清）',
          'Unique Song',
        ]);
      },
    );

    test('a newly favorited track changes the next refill seeds', () async {
      var favorites = <Track>[];
      final repository = _RecordingRadioRepository([
        for (var index = 0; index < 12; index += 1)
          _track(
            'radio_$index',
            title: 'Radio Song $index',
            artist: 'Radio Artist $index',
          ),
      ]);
      final controller = EndlessRadioController(
        repository: repository,
        favoriteTracks: () => favorites,
        listeningSignals: () => const <ListeningSignal>[],
        hotTracks: () => const <Track>[],
        now: () => DateTime(2026, 7, 26),
      );

      await controller.loadMore(const <String>{});
      await Future<void>.delayed(Duration.zero);
      favorites = [
        _track(
          'new_favorite',
          title: 'New Favorite Rock Live',
          artist: 'New Favorite Artist',
          album: 'Rock',
        ),
      ];
      await controller.loadMore(const <String>{});

      expect(repository.queryRounds, hasLength(2));
      expect(repository.queryRounds.last, contains('New Favorite Artist'));
      expect(repository.queryRounds.last, contains('摇滚 live'));
    });

    test(
      'controller requests a wider batch and can rank beyond 34 tracks',
      () async {
        final repository = _RecordingRadioRepository([
          for (var index = 0; index < 90; index += 1)
            _track(
              'wide_$index',
              title: 'Wide Song $index',
              artist: 'Wide Artist $index',
              album: index.isEven ? 'Pop' : 'Jazz',
            ),
        ]);
        final controller = EndlessRadioController(
          repository: repository,
          favoriteTracks: () => const <Track>[],
          listeningSignals: () => const <ListeningSignal>[],
          hotTracks: () => const <Track>[],
          now: () => DateTime(2026, 7, 26),
        );

        final result = await controller.loadMore(const <String>{});

        expect(repository.queryRounds.single, hasLength(5));
        expect(repository.limits.single, 12);
        expect(result, hasLength(endlessRadioBatchSize));
        expect(result.length, greaterThan(34));
      },
    );

    test('successive batches stay disjoint beyond the rolling pool size', () {
      final excluded = <String>{};
      for (var round = 0; round < 6; round += 1) {
        final discovered = [
          for (var index = 0; index < 72; index += 1)
            _track(
              'session_${round}_$index',
              title: 'Session Song ${round}_$index',
              artist: 'Session Artist ${round}_$index',
            ),
        ];
        final batch = rankEndlessRadioBatch(
          now: DateTime(2026, 7, 26),
          round: round,
          discoveredTracks: discovered,
          excludedTrackKeys: excluded,
        );
        expect(batch, hasLength(72));
        expect(
          batch.map(recommendationTrackKey).toSet().intersection(excluded),
          isEmpty,
        );
        excluded.addAll(batch.map(recommendationTrackKey));
      }

      expect(excluded.length, 432);
    });
  });
}

Track _track(
  String id, {
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  bool playable = true,
}) {
  return Track(
    id: 'audius_$id',
    title: title,
    artist: artist,
    album: album,
    duration: const Duration(minutes: 3),
    audioAsset: playable ? 'https://example.com/$id.mp3' : '',
    coverAsset: '',
    lyricsAsset: '',
    source: TrackSource.audius,
    provider: 'Audius',
  );
}

class _FakeSource implements MusicSource {
  _FakeSource(this.id, this.tracks, {this.configured = true});

  @override
  final String id;
  final List<Track> tracks;
  final bool configured;
  final List<String> queries = <String>[];

  @override
  bool get isConfigured => configured;

  @override
  String get label => id;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    queries.add(query);
    return tracks.take(limit).toList(growable: false);
  }
}

class _RecordingRadioRepository extends EndlessRadioRepository {
  _RecordingRadioRepository(this.result) : super(sources: const []);

  final List<Track> result;
  final List<List<String>> queryRounds = <List<String>>[];
  final List<int> limits = <int>[];

  @override
  Future<List<Track>> discover(
    Iterable<String> rawQueries, {
    int limitPerQuery = 8,
  }) async {
    queryRounds.add(rawQueries.toList(growable: false));
    limits.add(limitPerQuery);
    return result;
  }
}
