import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/track.dart';
import '../library/library_providers.dart';
import '../search/search_providers.dart';
import 'data/endless_radio_repository.dart';
import 'domain/endless_radio.dart';
import 'domain/personalized_recommendation.dart';

final listeningSignalsProvider = StreamProvider<List<ListeningSignal>>((ref) {
  final ownerId = ref.watch(activeLibraryOwnerProvider);
  return ref.watch(appDatabaseProvider).watchPlaybackHistory(ownerId).map((
    rows,
  ) {
    final signals = <ListeningSignal>[];
    for (final row in rows) {
      try {
        final snapshot = jsonDecode(row.trackSnapshot) as Map<String, Object?>;
        signals.add(
          ListeningSignal(
            track: Track.fromJson(snapshot),
            playCount: row.playCount,
            totalListened: Duration(milliseconds: row.totalPlayedMs),
            lastPlayedAt: row.lastPlayedAt,
          ),
        );
      } on Object {
        // One obsolete snapshot should not disable all personalisation.
      }
    }
    return List<ListeningSignal>.unmodifiable(signals);
  });
});

final listeningSignalsForDayProvider =
    StreamProvider.family<List<ListeningSignal>, DateTime>((ref, day) {
      final ownerId = ref.watch(activeLibraryOwnerProvider);
      return ref
          .watch(appDatabaseProvider)
          .watchPlaybackHistoryForDay(ownerId, day)
          .map((rows) {
            final signals = <ListeningSignal>[];
            for (final row in rows) {
              try {
                final snapshot =
                    jsonDecode(row.trackSnapshot) as Map<String, Object?>;
                signals.add(
                  ListeningSignal(
                    track: Track.fromJson(snapshot),
                    playCount: row.playCount,
                    totalListened: Duration(milliseconds: row.totalPlayedMs),
                    lastPlayedAt: row.lastPlayedAt,
                  ),
                );
              } on Object {
                // Ignore one obsolete snapshot without losing the whole day.
              }
            }
            return List<ListeningSignal>.unmodifiable(signals);
          });
    });

final endlessRadioRepositoryProvider = Provider<EndlessRadioRepository>((ref) {
  return EndlessRadioRepository(sources: ref.watch(onlineMusicSourcesProvider));
});

final endlessRadioControllerProvider = Provider<EndlessRadioController>((ref) {
  return EndlessRadioController(
    repository: ref.watch(endlessRadioRepositoryProvider),
    favoriteTracks: () =>
        ref.read(favoriteTracksProvider).value ?? const <Track>[],
    listeningSignals: () =>
        ref.read(listeningSignalsProvider).value ?? const <ListeningSignal>[],
    hotTracks: () =>
        ref.read(hotMusicControllerProvider).value?.recommendationTracks ??
        const <Track>[],
  );
});

class EndlessRadioController {
  EndlessRadioController({
    required EndlessRadioRepository repository,
    required List<Track> Function() favoriteTracks,
    required List<ListeningSignal> Function() listeningSignals,
    required List<Track> Function() hotTracks,
    DateTime Function()? now,
  }) : _repository = repository,
       _favoriteTracks = favoriteTracks,
       _listeningSignals = listeningSignals,
       _hotTracks = hotTracks,
       _now = now ?? DateTime.now;

  final EndlessRadioRepository _repository;
  final List<Track> Function() _favoriteTracks;
  final List<ListeningSignal> Function() _listeningSignals;
  final List<Track> Function() _hotTracks;
  final DateTime Function() _now;

  Future<List<Track>>? _inFlight;
  int _round = 0;

  Future<List<Track>> loadMore(Set<String> excludedTrackKeys) {
    final active = _inFlight;
    if (active != null) {
      return active.then(
        (tracks) => tracks
            .where(
              (track) =>
                  !excludedTrackKeys.contains(recommendationTrackKey(track)),
            )
            .toList(growable: false),
      );
    }

    final round = _round++;
    final request = _loadRound(
      round: round,
      excludedTrackKeys: Set<String>.of(excludedTrackKeys),
    );
    _inFlight = request;
    unawaited(
      request.then<void>(
        (_) {
          if (identical(_inFlight, request)) _inFlight = null;
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_inFlight, request)) _inFlight = null;
        },
      ),
    );
    return request;
  }

  Future<List<Track>> _loadRound({
    required int round,
    required Set<String> excludedTrackKeys,
  }) async {
    final favorites = _favoriteTracks();
    final signals = _listeningSignals();
    final preferenceTracks = _preferenceTracks(favorites, signals);
    final queries = endlessRadioDiscoveryQueries(
      preferenceTracks: preferenceTracks,
      round: round,
    );
    final discovered = await _repository.discover(queries, limitPerQuery: 12);
    return rankEndlessRadioBatch(
      now: _now(),
      round: round,
      discoveredTracks: discovered,
      hotTracks: _hotTracks(),
      listeningSignals: signals,
      favoriteTracks: favorites,
      excludedTrackKeys: excludedTrackKeys,
    );
  }

  static List<Track> _preferenceTracks(
    List<Track> favorites,
    List<ListeningSignal> signals,
  ) {
    final result = <Track>[];
    final seen = <String>{};

    void add(Track track) {
      if (track.isPlayable && seen.add(recommendationTrackKey(track))) {
        result.add(track);
      }
    }

    for (final track in favorites.reversed) {
      add(track);
    }
    final positiveSignals = [...signals]
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    for (final signal in positiveSignals) {
      final durationMs = signal.track.duration.inMilliseconds;
      final possibleMs = durationMs * signal.playCount;
      final completion = possibleMs <= 0
          ? 0.0
          : signal.totalListened.inMilliseconds / possibleMs;
      if (completion >= .3 || signal.playCount >= 2) add(signal.track);
    }
    return List<Track>.unmodifiable(result);
  }
}
