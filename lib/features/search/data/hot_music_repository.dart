import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/track.dart';

typedef HotRankingLoader = Future<List<Track>> Function({int limit});

class HotMusicRepository {
  HotMusicRepository({
    required HotRankingLoader rankingLoader,
    HotRankingLoader? popularRankingLoader,
    HotRankingLoader? risingRankingLoader,
    required SharedPreferences preferences,
    required List<Track> localTracks,
    DateTime Function()? now,
    this.cacheLifetime = const Duration(minutes: 30),
    this.cacheNamespace = '',
    this.sourceLabel = '酷狗实时榜',
  }) : _rankingLoader = rankingLoader,
       _popularRankingLoader = popularRankingLoader,
       _risingRankingLoader = risingRankingLoader,
       _preferences = preferences,
       _localTracks = List.unmodifiable(localTracks),
       _now = now ?? DateTime.now;

  String get _cacheKey => 'music_hot_ranking_snapshot_v1$cacheNamespace';
  final String cacheNamespace, sourceLabel;

  final HotRankingLoader _rankingLoader;
  final HotRankingLoader? _popularRankingLoader;
  final HotRankingLoader? _risingRankingLoader;
  final SharedPreferences _preferences;
  final List<Track> _localTracks;
  final DateTime Function() _now;
  final Duration cacheLifetime;

  Future<HotMusicSnapshot> load({bool forceRefresh = false}) async {
    final cached = _readCache();
    final cacheHasAllRankings =
        (_popularRankingLoader == null ||
            cached?.popularTracks.isNotEmpty == true) &&
        (_risingRankingLoader == null ||
            cached?.risingTracks.isNotEmpty == true);
    if (!forceRefresh &&
        cached != null &&
        cacheHasAllRankings &&
        _now().difference(cached.updatedAt) < cacheLifetime) {
      return cached.copyWith(fromCache: true);
    }

    try {
      final rankings = await Future.wait<List<Track>>([
        _rankingLoader(limit: 12),
        _loadOptionalRanking(_popularRankingLoader),
        _loadOptionalRanking(_risingRankingLoader),
      ]);
      final ranked = rankings[0];
      final tracks = _mergePlayableTracks(ranked).take(9).toList();
      if (tracks.isEmpty) throw StateError('empty hot ranking');
      final popularTracks = _popularRankingLoader == null
          ? const <Track>[]
          : _mergePlayableTracks(rankings[1]).take(9).toList(growable: false);
      final risingTracks = _risingRankingLoader == null
          ? const <Track>[]
          : _mergePlayableTracks(rankings[2]).take(9).toList(growable: false);
      final recommendationTracks = _mergePlayableTracks(
        rankings.expand((ranking) => ranking).toList(growable: false),
      ).take(36).toList(growable: false);
      final snapshot = HotMusicSnapshot(
        tracks: tracks,
        popularTracks: popularTracks.isNotEmpty
            ? popularTracks
            : cached?.popularTracks ?? const [],
        risingTracks: risingTracks.isNotEmpty
            ? risingTracks
            : cached?.risingTracks ?? const [],
        recommendationTracks: recommendationTracks.isNotEmpty
            ? recommendationTracks
            : cached?.recommendationTracks ?? const [],
        updatedAt: _now(),
        sourceLabel: ranked.isNotEmpty ? sourceLabel : '本地热度',
      );
      await _saveCache(snapshot);
      return snapshot;
    } on Object {
      if (cached != null && cached.tracks.isNotEmpty) {
        return cached.copyWith(fromCache: true, isStale: true);
      }
      return HotMusicSnapshot(
        tracks: _localFallback(),
        recommendationTracks: _localFallback(),
        popularTracks: const [],
        risingTracks: const [],
        updatedAt: _now(),
        sourceLabel: '本地热度',
        isStale: true,
      );
    }
  }

  Future<List<Track>> _loadOptionalRanking(HotRankingLoader? loader) async {
    if (loader == null) return const [];
    try {
      return await loader(limit: 12);
    } on Object {
      return const [];
    }
  }

  Iterable<Track> _mergePlayableTracks(List<Track> ranked) sync* {
    final emitted = <String>{};
    for (final remote in ranked.where((track) => track.isPlayable)) {
      final preferred = _matchingLocalTrack(remote) ?? remote;
      final key = _trackKey(preferred);
      if (emitted.add(key)) yield preferred;
    }
    for (final local in _localFallback()) {
      if (emitted.add(_trackKey(local))) yield local;
    }
  }

  Track? _matchingLocalTrack(Track remote) {
    final remoteTitle = _normalized(remote.title);
    final remoteArtist = _normalized(remote.artist);
    for (final local in _localTracks.where((track) => track.isPlayable)) {
      if (_normalized(local.title) != remoteTitle) continue;
      final localArtist = _normalized(local.artist);
      if (remoteArtist.isEmpty ||
          localArtist.isEmpty ||
          remoteArtist.contains(localArtist) ||
          localArtist.contains(remoteArtist)) {
        return local;
      }
    }
    return null;
  }

  List<Track> _localFallback() => _localTracks
      .where((track) => track.isPlayable)
      .take(9)
      .toList(growable: false);

  static String _trackKey(Track track) =>
      '${_normalized(track.title)}|${_normalized(track.artist)}';

  static String _normalized(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^]]*\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

  HotMusicSnapshot? _readCache() {
    final raw = _preferences.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final map = json.map((key, value) => MapEntry(key.toString(), value));
      return HotMusicSnapshot.fromJson(map);
    } on Object {
      return null;
    }
  }

  Future<void> _saveCache(HotMusicSnapshot snapshot) async {
    await _preferences.setString(_cacheKey, jsonEncode(snapshot.toJson()));
  }
}

class HotMusicSnapshot {
  const HotMusicSnapshot({
    required this.tracks,
    required this.updatedAt,
    required this.sourceLabel,
    this.popularTracks = const [],
    this.risingTracks = const [],
    this.recommendationTracks = const [],
    this.fromCache = false,
    this.isStale = false,
  });

  final List<Track> tracks;
  final List<Track> popularTracks;
  final List<Track> risingTracks;
  final List<Track> recommendationTracks;
  final DateTime updatedAt;
  final String sourceLabel;
  final bool fromCache;
  final bool isStale;

  String get statusLabel {
    if (isStale && fromCache) return '离线缓存';
    if (sourceLabel == '本地热度') return sourceLabel;
    return '实时更新';
  }

  HotMusicSnapshot copyWith({bool? fromCache, bool? isStale}) {
    return HotMusicSnapshot(
      tracks: tracks,
      popularTracks: popularTracks,
      risingTracks: risingTracks,
      recommendationTracks: recommendationTracks,
      updatedAt: updatedAt,
      sourceLabel: sourceLabel,
      fromCache: fromCache ?? this.fromCache,
      isStale: isStale ?? this.isStale,
    );
  }

  Map<String, Object?> toJson() => {
    'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
    'popularTracks': popularTracks
        .map((track) => track.toJson())
        .toList(growable: false),
    'risingTracks': risingTracks
        .map((track) => track.toJson())
        .toList(growable: false),
    'recommendationTracks': recommendationTracks
        .map((track) => track.toJson())
        .toList(growable: false),
    'updatedAt': updatedAt.toIso8601String(),
    'sourceLabel': sourceLabel,
  };

  factory HotMusicSnapshot.fromJson(Map<String, Object?> json) {
    final rawTracks = json['tracks'];
    final tracks = rawTracks is List
        ? rawTracks
              .whereType<Map>()
              .map(
                (item) => Track.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((track) => track.isPlayable)
              .toList(growable: false)
        : const <Track>[];
    final popularTracks = _tracksFromJson(json['popularTracks']);
    final risingTracks = _tracksFromJson(json['risingTracks']);
    final storedRecommendationTracks = _tracksFromJson(
      json['recommendationTracks'],
    );
    final recommendationTracks = storedRecommendationTracks.isNotEmpty
        ? storedRecommendationTracks
        : _uniqueTracks([...tracks, ...popularTracks, ...risingTracks]);
    return HotMusicSnapshot(
      tracks: tracks,
      popularTracks: popularTracks,
      risingTracks: risingTracks,
      recommendationTracks: recommendationTracks,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceLabel: json['sourceLabel']?.toString() ?? '实时热度',
    );
  }

  static List<Track> _tracksFromJson(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (item) => Track.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((track) => track.isPlayable)
        .toList(growable: false);
  }

  static List<Track> _uniqueTracks(Iterable<Track> tracks) {
    final emitted = <String>{};
    return tracks
        .where((track) => emitted.add(HotMusicRepository._trackKey(track)))
        .toList(growable: false);
  }
}
