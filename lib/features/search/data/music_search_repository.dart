import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/errors/user_facing_error.dart';
import '../../../shared/models/track.dart';
import '../domain/fuzzy_music_match.dart';
import '../domain/music_search_result.dart';
import '../domain/music_source.dart';

class MusicSearchRepository {
  MusicSearchRepository({
    required List<Track> localTracks,
    required List<MusicSource> sources,
    this.cacheDuration = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _localTracks = List.unmodifiable(localTracks),
       _sources = List.unmodifiable(sources),
       _clock = clock ?? DateTime.now;

  final List<Track> _localTracks;
  final List<MusicSource> _sources;
  final Duration cacheDuration;
  final DateTime Function() _clock;
  final Map<String, _CachedOnlineSearch> _cache = {};

  Completer<void>? _activeAbort;

  Future<MusicSearchResult> search(
    String rawQuery, {
    int limit = 20,
    bool allowCache = true,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      cancelActiveSearch();
      return const MusicSearchResult(
        query: '',
        localTracks: [],
        onlineTracks: [],
      );
    }

    final local = _searchLocal(query, limit);
    cancelActiveSearch();
    final cacheKey = '${query.toLowerCase()}::$limit';
    final cached = _cache[cacheKey];
    if (allowCache &&
        cached != null &&
        _clock().difference(cached.createdAt) < cacheDuration) {
      return MusicSearchResult(
        query: query,
        localTracks: local,
        onlineTracks: cached.tracks,
        warnings: cached.warnings,
        fromCache: true,
      );
    }
    if (allowCache) _cache.remove(cacheKey);

    final abort = Completer<void>();
    _activeAbort = abort;
    final configuredSources = _sources
        .where((source) => source.isConfigured)
        .toList(growable: false);

    final outcomes = await Future.wait(
      configuredSources.map(
        (source) => _searchSource(
          source,
          query,
          limit: limit,
          abortTrigger: abort.future,
        ),
      ),
    );

    if (identical(_activeAbort, abort)) {
      _activeAbort = null;
    }

    final tracksById = <String, Track>{};
    final trackIdBySemanticKey = <String, String>{};
    final warnings = <String>[];
    var successfulSources = 0;
    for (final outcome in outcomes) {
      if (outcome.wasAborted) {
        throw http.RequestAbortedException();
      }
      if (outcome.warning != null) {
        warnings.add(outcome.warning!);
        continue;
      }
      successfulSources += 1;
      for (final track in outcome.tracks) {
        final semanticKey = _semanticTrackKey(track);
        final existingId = trackIdBySemanticKey[semanticKey];
        if (existingId == null) {
          tracksById.putIfAbsent(track.id, () => track);
          trackIdBySemanticKey[semanticKey] = track.id;
          continue;
        }
        final existing = tracksById[existingId];
        if (existing != null && !existing.isPlayable && track.isPlayable) {
          tracksById.remove(existingId);
          tracksById[track.id] = track;
          trackIdBySemanticKey[semanticKey] = track.id;
        }
      }
    }

    if (configuredSources.isNotEmpty && successfulSources == 0) {
      throw MusicSearchException(
        warnings.isEmpty ? '在线音乐暂时不可用' : warnings.join('；'),
      );
    }

    final online = rankTracksForFuzzyQuery(query, tracksById.values);
    final immutableWarnings = List<String>.unmodifiable(warnings);
    _cache[cacheKey] = _CachedOnlineSearch(
      tracks: online,
      warnings: immutableWarnings,
      createdAt: _clock(),
    );
    return MusicSearchResult(
      query: query,
      localTracks: local,
      onlineTracks: online,
      warnings: immutableWarnings,
    );
  }

  String _semanticTrackKey(Track track) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[-_·•（）()\[\]]'), '');
    return '${normalize(track.title)}::${normalize(track.artist)}';
  }

  void cancelActiveSearch() {
    final activeAbort = _activeAbort;
    _activeAbort = null;
    if (activeAbort != null && !activeAbort.isCompleted) {
      activeAbort.complete();
    }
  }

  void clearCache() => _cache.clear();

  List<Track> _searchLocal(String query, int limit) {
    return rankTracksForFuzzyQuery(
      query,
      _localTracks,
      matchingOnly: true,
    ).take(limit).toList(growable: false);
  }

  Future<_SourceOutcome> _searchSource(
    MusicSource source,
    String query, {
    required int limit,
    required Future<void> abortTrigger,
  }) async {
    try {
      final tracks = await source.search(
        query,
        limit: limit,
        abortTrigger: abortTrigger,
      );
      return _SourceOutcome(tracks: tracks);
    } on http.RequestAbortedException {
      return const _SourceOutcome(wasAborted: true);
    } on MusicSourceException catch (error) {
      return _SourceOutcome(
        warning: userFacingErrorMessage(
          error,
          fallback: '${source.label}：暂时无法连接',
        ),
      );
    } on Object {
      return _SourceOutcome(warning: '${source.label}：暂时无法连接');
    }
  }
}

class MusicSearchException implements Exception {
  const MusicSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CachedOnlineSearch {
  const _CachedOnlineSearch({
    required this.tracks,
    required this.warnings,
    required this.createdAt,
  });

  final List<Track> tracks;
  final List<String> warnings;
  final DateTime createdAt;
}

class _SourceOutcome {
  const _SourceOutcome({
    this.tracks = const [],
    this.warning,
    this.wasAborted = false,
  });

  final List<Track> tracks;
  final String? warning;
  final bool wasAborted;
}
