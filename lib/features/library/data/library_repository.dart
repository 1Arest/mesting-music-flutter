import 'dart:convert';
import 'package:drift/drift.dart' show OrderingTerm;
import '../../../core/performance/track_snapshots.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import 'retired_bundled_tracks.dart';
import 'playlist_directory_window.dart';

class PlaylistDetail {
  const PlaylistDetail({required this.playlist, required this.tracks});

  final UserPlaylist playlist;
  final List<Track> tracks;
}

class FavoriteTrackRequiredException implements Exception {
  const FavoriteTrackRequiredException();
}

class LibraryRepository {
  LibraryRepository(
    this._database, {
    required this.ownerId,
    bool Function()? canWrite,
  }) : _canWrite = canWrite;

  final AppDatabase _database;
  final String ownerId;
  final bool Function()? _canWrite;

  /// Guard every mutation, including non-widget notification/media actions.
  /// Existing guest rows remain readable; playback history uses its own owner.
  void _requireWriteAccess() {
    if (_canWrite != null && (_disposed || !_canWrite())) {
      throw StateError('登录后才能管理收藏和自己的歌单');
    }
  }

  bool _disposed = false;

  Stream<List<Track>> watchFavorites() {
    return _database
        .watchFavorites(ownerId)
        .asyncMap(
          (rows) async => (await decodeTrackSnapshots(
            rows.map((row) => row.trackSnapshot).toList(),
          )).where((track) => !isRetiredBundledTrackId(track.id)).toList(),
        );
  }

  /// Browsing uses one page; explicit whole-collection operations keep their
  /// existing stream. Membership is an ID-only index, independent of details.
  Future<TrackPage> favoritePage({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async {
    final rows = await _database.favoriteSlice(
      ownerId,
      offset: offset,
      limit: limit,
      query: query,
    );
    final total = await _database.favoriteCount(ownerId, query: query);
    return TrackPage(
      rows
          .map((row) => _decodeTrack(row.trackSnapshot))
          .where((t) => !isRetiredBundledTrackId(t.id))
          .toList(),
      offset: offset,
      nextOffset: offset + rows.length,
      total: total,
      hasMore: offset + rows.length < total,
    );
  }

  Stream<TrackPage> watchFavoritePreview() =>
      _database.watchFavoriteSlice(ownerId).asyncMap((_) => favoritePage());

  Stream<TrackPage> watchPlaylistPreview(String id) => _database
      .watchPlaylistTracks(ownerId, id)
      .asyncMap((_) => playlistPage(id));

  Future<Set<String>> favoriteIds() async => (await _database.favoriteIds(
    ownerId,
  )).where((id) => !isRetiredBundledTrackId(id)).toSet();

  Future<TrackPage> playlistPage(
    String id, {
    int offset = 0,
    int limit = 30,
  }) async {
    final rows = await _database.playlistTrackSlice(
      ownerId,
      id,
      offset: offset,
      limit: limit,
    );
    final total = await _database.playlistTrackCount(ownerId, id);
    return TrackPage(
      rows
          .map((row) => _decodeTrack(row.trackSnapshot))
          .where((t) => !isRetiredBundledTrackId(t.id))
          .toList(),
      offset: offset,
      nextOffset: offset + rows.length,
      total: total,
      hasMore: offset + rows.length < total,
    );
  }

  Future<bool> isFavorite(String trackId) =>
      _database.isFavorite(ownerId, trackId);

  Future<void> setFavorite(Track track, {required bool favorite}) async {
    _requireWriteAccess();
    await _database.setFavorite(ownerId, track, favorite: favorite);
  }

  Future<bool> toggleFavorite(Track track) async {
    _requireWriteAccess();
    final favorite = await _database.toggleFavorite(ownerId, track);
    return favorite;
  }

  Stream<List<UserPlaylist>> watchPlaylists() =>
      _database.watchPlaylists(ownerId);

  Future<PlaylistDirectoryPage> playlistDirectoryPage({
    int offset = 0,
    int limit = 30,
  }) async {
    final rows =
        await (_database.select(_database.userPlaylists)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
              ..limit(limit, offset: offset))
            .get();
    return PlaylistDirectoryPage(
      rows,
      nextOffset: offset + rows.length,
      hasMore: rows.length >= limit,
    );
  }

  Stream<PlaylistDirectoryPage> watchPlaylistDirectory() =>
      (_database.select(_database.userPlaylists)
            ..where((row) => row.ownerId.equals(ownerId))
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
            ..limit(30))
          .watch()
          .map(
            (rows) => PlaylistDirectoryPage(
              rows,
              nextOffset: rows.length,
              hasMore: rows.length >= 30,
            ),
          );

  Future<UserPlaylist?> getPlaylist(String id) =>
      _database.getPlaylist(ownerId, id);

  Stream<List<Track>> watchPlaylistTracks(String playlistId) {
    return _database
        .watchPlaylistTracks(ownerId, playlistId)
        .asyncMap(
          (rows) async => (await decodeTrackSnapshots(
            rows.map((row) => row.trackSnapshot).toList(),
          )).where((track) => !isRetiredBundledTrackId(track.id)).toList(),
        );
  }

  Future<void> createPlaylist({
    required String id,
    required String name,
    String description = '',
    String? coverAsset,
    String? coverCloudId,
  }) async {
    _requireWriteAccess();
    await _database.createPlaylist(
      ownerId: ownerId,
      id: id,
      name: name,
      description: description,
      coverAsset: coverAsset,
      coverCloudId: coverCloudId,
    );
  }

  Future<void> updatePlaylist({
    required String id,
    required String name,
    required String description,
    required String? coverAsset,
    String? coverCloudId,
  }) async {
    _requireWriteAccess();
    await _database.updatePlaylist(
      ownerId: ownerId,
      id: id,
      name: name,
      description: description,
      coverAsset: coverAsset,
      coverCloudId: coverCloudId,
    );
  }

  Future<void> deletePlaylist(String id) async {
    _requireWriteAccess();
    await _database.deletePlaylist(ownerId, id);
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    _requireWriteAccess();
    if (!await isFavorite(track.id)) {
      throw const FavoriteTrackRequiredException();
    }
    await _database.addTrackToPlaylist(ownerId, playlistId, track);
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    _requireWriteAccess();
    await _database.removeTrackFromPlaylist(ownerId, playlistId, trackId);
  }

  Future<void> reorderPlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    _requireWriteAccess();
    await _database.reorderPlaylistTracks(ownerId, playlistId, trackIds);
  }

  Future<int> countLegacyFavorites() => _database.countLegacyFavorites();

  Future<void> importLegacyLibrary() async {
    _requireWriteAccess();
    await _database.importLegacyLibraryTo(ownerId);
  }

  /// Local storage has no remote synchronization. Platform repositories
  /// override this interface with their own authenticated protocol.
  Future<bool> synchronize({bool forcePull = false}) async => true;

  void dispose() {
    _disposed = true;
  }

  Track _decodeTrack(String snapshot) {
    return Track.fromJson(jsonDecode(snapshot) as Map<String, Object?>);
  }
}
