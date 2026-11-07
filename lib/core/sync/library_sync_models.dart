import '../../shared/models/track.dart';

class LibrarySyncMutation {
  const LibrarySyncMutation({
    required this.localId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
  });

  final int localId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, Object?> payload;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'mutation_id': localId,
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation,
    'payload': payload,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

class CloudFavoriteTrack {
  const CloudFavoriteTrack({
    required this.track,
    required this.createdAt,
    required this.updatedAt,
  });

  final Track track;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class CloudPlaylistTrack {
  const CloudPlaylistTrack({
    required this.track,
    required this.sortOrder,
    required this.addedAt,
  });

  final Track track;
  final int sortOrder;
  final DateTime addedAt;
}

class CloudPlaylist {
  const CloudPlaylist({
    required this.id,
    required this.name,
    required this.description,
    required this.coverAsset,
    this.coverCloudId,
    required this.createdAt,
    required this.updatedAt,
    required this.tracks,
  });

  final String id;
  final String name;
  final String description;
  final String? coverAsset;
  final String? coverCloudId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CloudPlaylistTrack> tracks;
}

class CloudPlaybackHistory {
  const CloudPlaybackHistory({
    required this.track,
    required this.playCount,
    required this.completedPlayCount,
    required this.totalPlayedMs,
    required this.lastPlayedAt,
  });

  final Track track;
  final int playCount;
  final int completedPlayCount;
  final int totalPlayedMs;
  final DateTime lastPlayedAt;
}

class CloudPlaybackDailyHistory {
  const CloudPlaybackDailyHistory({
    required this.dayKey,
    required this.track,
    required this.playCount,
    required this.totalPlayedMs,
    required this.lastPlayedAt,
  });

  final String dayKey;
  final Track track;
  final int playCount;
  final int totalPlayedMs;
  final DateTime lastPlayedAt;
}

class CloudLibrarySnapshot {
  const CloudLibrarySnapshot({
    required this.favorites,
    required this.playlists,
    this.playbackHistories = const [],
    this.playbackDailyHistories = const [],
    this.includesPlaybackHistories = false,
    this.includesPlaybackDailyHistories = false,
  });

  const CloudLibrarySnapshot.empty()
    : favorites = const [],
      playlists = const [],
      playbackHistories = const [],
      playbackDailyHistories = const [],
      includesPlaybackHistories = false,
      includesPlaybackDailyHistories = false;

  final List<CloudFavoriteTrack> favorites;
  final List<CloudPlaylist> playlists;
  final List<CloudPlaybackHistory> playbackHistories;
  final List<CloudPlaybackDailyHistory> playbackDailyHistories;
  final bool includesPlaybackHistories;
  final bool includesPlaybackDailyHistories;

  factory CloudLibrarySnapshot.fromJson(Map<String, Object?> json) {
    final favorites = <CloudFavoriteTrack>[];
    for (final value in _list(json['favorites'])) {
      final item = _map(value);
      final track = _track(item['track']);
      if (track == null) continue;
      favorites.add(
        CloudFavoriteTrack(
          track: track,
          createdAt: _date(item['created_at']),
          updatedAt: _date(item['updated_at']),
        ),
      );
    }

    final playlists = <CloudPlaylist>[];
    for (final value in _list(json['playlists'])) {
      final item = _map(value);
      final id = _text(item['id']);
      final name = _text(item['name']);
      if (id == null || name == null) continue;
      final tracks = <CloudPlaylistTrack>[];
      for (final trackValue in _list(item['tracks'])) {
        final trackItem = _map(trackValue);
        final track = _track(trackItem['track']);
        if (track == null) continue;
        tracks.add(
          CloudPlaylistTrack(
            track: track,
            sortOrder: _integer(trackItem['sort_order']) ?? tracks.length,
            addedAt: _date(trackItem['added_at']),
          ),
        );
      }
      tracks.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      playlists.add(
        CloudPlaylist(
          id: id,
          name: name,
          description: _text(item['description']) ?? '',
          coverAsset: _text(item['cover_asset']),
          coverCloudId: _text(item['cover_cloud_id']),
          createdAt: _date(item['created_at']),
          updatedAt: _date(item['updated_at']),
          tracks: tracks,
        ),
      );
    }

    final playbackHistories = <CloudPlaybackHistory>[];
    for (final value in _list(json['playback_histories'])) {
      final item = _map(value);
      final track = _track(item['track']);
      if (track == null) continue;
      playbackHistories.add(
        CloudPlaybackHistory(
          track: track,
          playCount: (_integer(item['play_count']) ?? 0)
              .clamp(0, 1 << 31)
              .toInt(),
          completedPlayCount: (_integer(item['completed_play_count']) ?? 0)
              .clamp(0, 1 << 31)
              .toInt(),
          totalPlayedMs: (_integer(item['total_played_ms']) ?? 0)
              .clamp(0, 1 << 53)
              .toInt(),
          lastPlayedAt: _date(item['last_played_at']),
        ),
      );
    }

    final playbackDailyHistories = <CloudPlaybackDailyHistory>[];
    for (final value in _list(json['playback_daily_histories'])) {
      final item = _map(value);
      final dayKey = _text(item['day_key']);
      final track = _track(item['track']);
      if (dayKey == null || track == null) continue;
      playbackDailyHistories.add(
        CloudPlaybackDailyHistory(
          dayKey: dayKey,
          track: track,
          playCount: (_integer(item['play_count']) ?? 0)
              .clamp(0, 1 << 31)
              .toInt(),
          totalPlayedMs: (_integer(item['total_played_ms']) ?? 0)
              .clamp(0, 1 << 53)
              .toInt(),
          lastPlayedAt: _date(item['last_played_at']),
        ),
      );
    }
    return CloudLibrarySnapshot(
      favorites: favorites,
      playlists: playlists,
      playbackHistories: playbackHistories,
      playbackDailyHistories: playbackDailyHistories,
      includesPlaybackHistories: json.containsKey('playback_histories'),
      includesPlaybackDailyHistories: json.containsKey(
        'playback_daily_histories',
      ),
    );
  }
}

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _integer(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');

DateTime _date(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

Track? _track(Object? value) {
  try {
    final json = _map(value);
    return json.isEmpty ? null : Track.fromJson(json);
  } on Object {
    return null;
  }
}
