import '../../../shared/utils/media_uri.dart';
import '../../../core/diagnostics/local_music_diagnostics.dart';
import '../data/cloud_library_repository.dart';
import 'dart:async';
import '../../../core/cache/browse_response_cache.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import '../data/track_page_utils.dart';
import '../../library/data/playlist_directory_window.dart';
import '../data/music_platform_api.dart';
import '../domain/platform_session.dart';
import 'netease_music_repository.dart';

/// Cloud library for one retained NetEase identity. Never writes NetEase songs
/// into Kugou/local playlists. Remote writes are serialized and not retried.
class NeteaseLibraryRepository extends CloudLibraryRepository {
  NeteaseLibraryRepository(
    super.database, {
    required this.music,
    required this.identity,
  }) : super(ownerId: identity.ownerId);
  final NeteaseMusicRepository music;
  final PlatformSession identity;
  final _changes = StreamController<void>.broadcast();
  Future<List<Map<String, dynamic>>>? _lists;
  Future<void> _pending = Future.value();
  bool _closed = false;
  List<Map<String, dynamic>> _snapshot = const [];
  Future<Set<String>>? _favoriteIds;
  int _revision = 0;

  Future<T> _write<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void refresh() {
    _revision++;
    _lists = null;
    _favoriteIds = null;
    music.invalidatePlaylists();
    if (!_closed) _changes.add(null);
  }

  Stream<T> _watch<T>(Future<T> Function() load) => Stream<T>.multi((sink) {
    var generation = 0;
    var active = true;
    late final BrowseCacheWatch cacheWatch;
    Future<void> emit() async {
      final next = ++generation;
      try {
        final value = await cacheWatch.run(load);
        if (active && !_closed && !sink.isClosed && next == generation) {
          sink.add(value);
        }
      } catch (e, s) {
        if (active && !_closed && !sink.isClosed && next == generation) {
          sink.addError(e, s);
        }
      }
    }

    cacheWatch = BrowseCacheWatch(() {
      if (active && !_closed) unawaited(emit());
    });
    final sub = _changes.stream.listen((_) => unawaited(emit()));
    sink.onCancel = () async {
      active = false;
      generation++;
      cacheWatch.dispose();
      await sub.cancel();
    };
    unawaited(emit());
  });
  Future<List<Map<String, dynamic>>> _loadLists() =>
      BrowseResponseCache.observing
      ? _fetchLists()
      : (_lists ??= _fetchLists().catchError((Object error) {
          _lists = null;
          throw error;
        }));
  Future<List<Map<String, dynamic>>> _fetchLists() async {
    final revision = _revision;
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (var offset = 0; offset < 10000; offset += 100) {
      final payload = await music.call('/user/playlist', {
        'uid': identity.userId,
        'limit': 100,
        'offset': offset,
      });
      final rows = NeteaseMusicRepository.rows(payload['playlist']);
      for (final row in rows.take(6)) {
        LocalMusicDiagnostics.record('playlist.cover_schema', {
          'fields': {
            for (final key in [
              'coverImgUrl',
              'picUrl',
              'coverUrl',
              'coverImgId_str',
            ])
              key: row[key]?.runtimeType.toString(),
          },
          'image': LocalMusicDiagnostics.artwork(
            firstArtworkUri([
              row['coverImgUrl'],
              row['picUrl'],
              row['coverUrl'],
            ]),
          ),
        });
      }
      var added = 0;
      for (final row in rows) {
        if (seen.add('${row['id']}')) {
          result.add(row);
          ++added;
        }
      }
      if (payload['more'] != true || rows.length < 100) {
        if (revision == _revision) _snapshot = result;
        return result;
      }
      if (added == 0) throw const MusicPlatformException('网易云歌单分页未前进，请重试');
    }
    throw const MusicPlatformException('网易云歌单数量超过本次加载上限');
  }

  String _id(Map<String, dynamic> row) => 'ne:${row['id']}';
  String _remoteId(String id) {
    if (!id.startsWith('ne:') || !RegExp(r'^\d+$').hasMatch(id.substring(3))) {
      throw const MusicPlatformException('网易云歌单标识无效');
    }
    return id.substring(3);
  }

  bool _owned(Map<String, dynamic> row) =>
      '${NeteaseMusicRepository.object(row['creator'])['userId']}' ==
      identity.userId;
  bool _likes(Map<String, dynamic> row) =>
      _owned(row) && '${row['specialType']}' == '5';
  String? get likedPlaylistId => _snapshot.where(_likes).map(_id).firstOrNull;
  @override
  bool canManage(String id) =>
      _snapshot.any((r) => _id(r) == id && _owned(r) && !_likes(r));
  @override
  Future<String> commentId(String id) async => '${(await _row(id))['id']}';
  UserPlaylist _playlist(Map<String, dynamic> row) => UserPlaylist(
    ownerId: ownerId,
    id: _id(row),
    name: '${row['name'] ?? '网易云歌单'}',
    description: '${row['description'] ?? ''}',
    coverAsset: firstArtworkUri([
      row['coverImgUrl'],
      row['picUrl'],
      row['coverUrl'],
    ]),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      int.tryParse('${row['createTime']}') ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      int.tryParse('${row['updateTime']}') ?? 0,
    ),
  );
  Future<Map<String, dynamic>> _row(String id) async =>
      _snapshot.where((row) => _id(row) == id).firstOrNull ??
      (await _loadLists()).firstWhere(
        (r) => _id(r) == id,
        orElse: () => throw const MusicPlatformException('网易云歌单不存在，请刷新'),
      );
  Future<Map<String, dynamic>> _favoriteRow() async =>
      (await _loadLists()).firstWhere(
        _likes,
        orElse: () =>
            throw const MusicPlatformException('未找到网易云「我喜欢的音乐」，请在网易云初始化账号'),
      );

  @override
  Stream<List<UserPlaylist>> watchPlaylists() =>
      _watch(() async => (await _loadLists()).map(_playlist).toList());
  @override
  Stream<PlaylistDirectoryPage> watchPlaylistDirectory() =>
      _watch(() => playlistDirectoryPage());
  @override
  Future<PlaylistDirectoryPage> playlistDirectoryPage({
    int offset = 0,
    int limit = 30,
  }) async {
    final revision = _revision;
    final payload = await music.call('/user/playlist', {
      'uid': identity.userId,
      'limit': limit,
      'offset': offset,
    });
    final rows = NeteaseMusicRepository.rows(payload['playlist']);
    if (revision == _revision) {
      final merged = {for (final row in _snapshot) _id(row): row};
      for (final row in rows) {
        merged[_id(row)] = row;
      }
      _snapshot = merged.values.toList();
    }
    return PlaylistDirectoryPage(
      rows.map(_playlist).toList(),
      nextOffset: offset + rows.length,
      hasMore: payload['more'] == true && rows.length >= limit,
    );
  }

  @override
  Future<UserPlaylist?> getPlaylist(String id) async =>
      _playlist(await _row(id));
  @override
  Stream<List<Track>> watchPlaylistTracks(String playlistId) =>
      _watch(() => music.playlist(_remoteId(playlistId)));
  @override
  Stream<List<Track>> watchFavorites() =>
      _watch(() async => music.playlist('${(await _favoriteRow())['id']}'));
  @override
  Stream<TrackPage> watchFavoritePreview() => _watch(() => favoritePage());
  @override
  Stream<TrackPage> watchPlaylistPreview(String id) =>
      _watch(() => playlistPage(id));
  @override
  Future<TrackPage> playlistPage(String id, {int offset = 0, int limit = 30}) =>
      music.playlistPage(_remoteId(id), offset: offset, limit: limit);
  @override
  Future<TrackPage> favoritePage({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async {
    final id = '${(await _favoriteRow())['id']}';
    if (query.trim().isEmpty) {
      return music.playlistPage(id, offset: offset, limit: limit);
    }
    // Full-collection search is an explicit operation. It must never quietly
    // limit matches to the metadata pages already painted by the preview.
    return sliceTrackPageAsync(
      await music.playlist(id),
      offset: offset,
      limit: limit,
      query: query,
    );
  }

  @override
  Future<Set<String>> favoriteIds() {
    Future<Set<String>> load() async {
      final payload = await music.call('/likelist', {'uid': identity.userId});
      return (payload['ids'] as List? ?? const [])
          .map((id) => 'netease_$id')
          .toSet();
    }

    if (BrowseResponseCache.observing) return load();
    return _favoriteIds ??= load().catchError((Object error) {
      _favoriteIds = null;
      throw error;
    });
  }

  @override
  Future<bool> isFavorite(String trackId) async {
    final id = NeteaseMusicRepository.songId(trackId);
    return (await favoriteIds()).contains('netease_$id');
  }

  @override
  Future<void> setFavorite(Track track, {required bool favorite}) =>
      _write(() async {
        if (track.source != TrackSource.netease) {
          throw const MusicPlatformException('网易云收藏仅支持网易云歌曲');
        }
        await music.call('/like', {
          'id': NeteaseMusicRepository.songId(track.id),
          'like': favorite,
        });
        refresh();
      });
  @override
  Future<bool> toggleFavorite(Track track) => _write(() async {
    if (track.source != TrackSource.netease) {
      throw const MusicPlatformException('网易云收藏仅支持网易云歌曲');
    }
    final next = !await isFavorite(track.id);
    await music.call('/like', {
      'id': NeteaseMusicRepository.songId(track.id),
      'like': next,
    });
    refresh();
    return next;
  });
  @override
  Future<void> createPlaylist({
    required String id,
    required String name,
    String description = '',
    String? coverAsset,
    String? coverCloudId,
  }) => _write(() async {
    final payload = await music.call('/playlist/create', {'name': name});
    final createdId =
        '${NeteaseMusicRepository.object(payload['playlist'])['id'] ?? payload['id'] ?? ''}';
    if (createdId.isEmpty) {
      throw const MusicPlatformException('网易云未返回新歌单标识，请刷新列表确认');
    }
    if (description.isNotEmpty) {
      await music.call('/playlist/update', {
        'id': createdId,
        'name': name,
        'description': description,
      });
    }
    refresh();
  });
  @override
  Future<void> updatePlaylist({
    required String id,
    required String name,
    required String description,
    required String? coverAsset,
    String? coverCloudId,
  }) => _write(() async {
    await _requireOwned(id);
    await music.call('/playlist/update', {
      'id': _remoteId(id),
      'name': name,
      'description': description,
    });
    refresh();
  });
  Future<void> _requireOwned(String id) async {
    final row = await _row(id);
    if (!_owned(row) || _likes(row)) {
      throw const MusicPlatformException('请在自己创建的网易云歌单中操作');
    }
  }

  @override
  Future<void> deletePlaylist(String id) => _write(() async {
    await _requireOwned(id);
    await music.call('/playlist/delete', {'id': _remoteId(id)});
    refresh();
  });
  @override
  Future<void> addTrackToPlaylist(String playlistId, Track track) =>
      _write(() async {
        await _requireOwned(playlistId);
        if (track.source != TrackSource.netease) {
          throw const MusicPlatformException('网易云歌单仅支持网易云歌曲');
        }
        await music.call('/playlist/tracks', {
          'id': _remoteId(playlistId),
          'op': 'add',
          'ids': [NeteaseMusicRepository.songId(track.id)],
        });
        refresh();
      });
  @override
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) =>
      _write(() async {
        await _requireOwned(playlistId);
        await music.call('/playlist/tracks', {
          'id': _remoteId(playlistId),
          'op': 'del',
          'ids': [NeteaseMusicRepository.songId(trackId)],
        });
        refresh();
      });
  @override
  Future<void> reorderPlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) => _write(() async {
    await _requireOwned(playlistId);
    await music.call('/playlist/tracks', {
      'id': _remoteId(playlistId),
      'op': 'update',
      'ids': trackIds.map(NeteaseMusicRepository.songId).toList(),
    });
    refresh();
  });
  Future<void> subscribe(String id, {required bool subscribe}) =>
      _write(() async {
        await music.call('/playlist/subscribe', {
          'id': id,
          'subscribe': subscribe,
        });
        refresh();
      });
  @override
  Future<int> countLegacyFavorites() async => 0;
  @override
  Future<void> importLegacyLibrary() async {}
  @override
  Future<bool> synchronize({bool forcePull = false}) async {
    refresh();
    return true;
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_changes.close());
    super.dispose();
  }
}
