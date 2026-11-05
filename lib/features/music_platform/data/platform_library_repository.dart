import 'cloud_library_repository.dart';
import 'dart:async';
import 'dart:io';
import '../../../core/cache/browse_response_cache.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import '../domain/platform_session.dart';
import 'music_platform_api.dart';
import 'platform_catalog.dart';
import 'kugou_favorite_playlist.dart';
import 'kugou_playlist_paging.dart';
import 'track_page_utils.dart';
import 'kugou_favorite_index.dart';
import '../../library/data/playlist_directory_window.dart';

/// Implements the existing library boundary with the active Kugou cloud.
/// Nothing is copied into the guest/CloudBase database or uploaded implicitly.
/// Every operation is pinned to its original credential, including after awaits.
class PlatformLibraryRepository extends CloudLibraryRepository {
  PlatformLibraryRepository(
    super.database, {
    required this.api,
    required this.identity,
  }) : super(ownerId: 'kugou:${identity.userId}');

  final MusicPlatformApi api;
  final PlatformSession identity;
  final _changes = StreamController<void>.broadcast();
  Future<List<Map<String, dynamic>>>? _lists;
  final _trackLoads = <String, Future<List<Track>>>{};
  final _fileIds = <String, Map<String, String>>{};
  Future<KugouFavoriteIndex>? _favorites;
  bool _closed = false;
  List<Map<String, dynamic>> _snapshot = const [];
  Future<void> _pendingWrite = Future<void>.value();
  int _revision = 0;
  final _createdDrafts = <String, String>{};
  final _creationBaselines = <String, Set<String>>{};
  late final _trackPager = KugouPlaylistPaging(
    read: _get,
    rows: PlatformCatalog.rows,
  );
  late final _favoritePager = KugouPlaylistPaging(
    read: _get,
    rows: PlatformCatalog.rows,
    pageSize: 200,
  );

  /// Serialize writes once, without retrying remote mutations automatically.
  Future<T> _write<T>(Future<T> Function() operation) {
    final result = _pendingWrite.then((_) => operation());
    _pendingWrite = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  bool canManage(String id) => _snapshot.any(
    (row) => _id(row) == id && _owned(row) && !_systemPlaylist(row),
  );

  @override
  Future<String> commentId(String id) async {
    final row = await _row(id);
    return '${row['global_collection_id'] ?? row['list_create_gid'] ?? ''}';
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> query = const {},
  ]) => api.get(path, query: query, expectedSession: identity);

  /// Subscribe before the first read so an overlapping mutation is not lost.
  Stream<T> _watch<T>(Future<T> Function() load) => Stream<T>.multi((sink) {
    var generation = 0;
    var active = true;
    late final BrowseCacheWatch cacheWatch;
    Future<void> emit() async {
      final requestGeneration = ++generation;
      try {
        final value = await cacheWatch.run(load);
        if (active &&
            !_closed &&
            !sink.isClosed &&
            generation == requestGeneration) {
          sink.add(value);
        }
      } catch (error, stack) {
        if (active &&
            !_closed &&
            !sink.isClosed &&
            generation == requestGeneration) {
          sink.addError(error, stack);
        }
      }
    }

    cacheWatch = BrowseCacheWatch(() {
      if (active && !_closed) {
        _lists = null;
        _trackLoads.clear();
        _favorites = null;
        _trackPager.clear();
        _favoritePager.clear();
        unawaited(emit());
      }
    });
    final subscription = _changes.stream.listen((_) => unawaited(emit()));
    sink.onCancel = () async {
      active = false;
      generation++;
      cacheWatch.dispose();
      await subscription.cancel();
    };
    unawaited(emit());
  });

  void _invalidate() {
    _revision++;
    _lists = null;
    _trackLoads.clear();
    _fileIds.clear();
    _favorites = null;
    _trackPager.clear();
    _favoritePager.clear();
    if (!_closed) _changes.add(null);
  }

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
    for (var page = 1; page <= 100; page++) {
      final payload = await _get('/user/playlist', {
        'page': '$page',
        'pagesize': '30',
        'userid': identity.userId,
      });
      final batch = PlatformCatalog.rows(payload);
      var added = 0;
      for (final row in batch) {
        final id = '${row['listid'] ?? row['global_collection_id'] ?? ''}';
        if (id.isNotEmpty && seen.add(id)) {
          result.add(row);
          added++;
        }
      }
      if (batch.length < 30) {
        if (_revision == revision) _snapshot = result;
        return result;
      }
      if (added == 0) throw const MusicPlatformException('平台歌单分页未前进，请重试');
    }
    throw const MusicPlatformException('歌单数量超过本次加载上限');
  }

  bool _likes(Map<String, dynamic> row) =>
      KugouFavoritePlaylist.priority(row, identity.userId) > 0;

  // Default collection keeps its existing system-list protection, while no
  // longer being selected as the destination of the liked-song heart button.
  bool _systemPlaylist(Map<String, dynamic> row) =>
      _likes(row) || row['name'] == '默认收藏';
  bool _owned(Map<String, dynamic> row) {
    final creator = '${row['list_create_userid'] ?? ''}';
    if (creator.isNotEmpty) return creator == identity.userId;
    return '${row['type'] ?? 0}' == '0' && '${row['source'] ?? 1}' != '2';
  }

  String _id(Map<String, dynamic> row) =>
      'kg:${row['listid'] ?? row['global_collection_id']}';

  UserPlaylist _playlist(Map<String, dynamic> row) => UserPlaylist(
    ownerId: ownerId,
    id: _id(row),
    name: '${row['name'] ?? row['specialname'] ?? '酷狗歌单'}',
    description: '${row['intro'] ?? row['description'] ?? ''}',
    coverAsset: '${row['sizable_cover'] ?? row['imgurl'] ?? row['pic'] ?? ''}'
        .replaceAll('{size}', '400'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.now(),
  );

  Future<Map<String, dynamic>> _row(String id) async {
    final known = _snapshot.where((row) => _id(row) == id).firstOrNull;
    if (known != null) return known;
    final rows = await _loadLists();
    for (final row in rows) {
      if (_id(row) == id) return row;
    }
    throw const MusicPlatformException('云端歌单不存在，请刷新列表');
  }

  Future<Map<String, dynamic>> _favoriteRow() async {
    final candidates = KugouFavoritePlaylist.candidates(
      await _loadLists(),
      identity.userId,
    );
    if (candidates.length == 1) return candidates.single;
    if (candidates.length > 1) {
      throw const MusicPlatformException('未能确认唯一的酷狗「我喜欢」歌单，请刷新音乐库后重试');
    }
    throw const MusicPlatformException('未找到酷狗「我喜欢」歌单，请先在酷狗客户端初始化');
  }

  Future<List<Track>> _loadTracks(Map<String, dynamic> row) {
    if (BrowseResponseCache.observing) return _fetchTracks(row);
    final id = _id(row);
    return _trackLoads[id] ??= _fetchTracks(row).catchError((Object error) {
      _trackLoads.remove(id);
      throw error;
    });
  }

  Future<List<Track>> _fetchTracks(Map<String, dynamic> row) async {
    final revision = _revision;
    final all = <Track>[];
    final records = <String, String>{};
    final seen = <String>{};
    for (var page = 1; page <= 50; page++) {
      final listId = '${row['listid'] ?? ''}';
      final payload = await _get(
        listId.isEmpty ? '/playlist/track/all' : '/playlist/track/all/new',
        {
          if (listId.isNotEmpty) 'listid': listId,
          if (listId.isEmpty)
            'global_collection_id': '${row['global_collection_id'] ?? ''}',
          'page': '$page',
          'pagesize': '200',
        },
      );
      final batch = PlatformCatalog.rows(payload);
      final tracks = PlatformCatalog.tracks(batch);
      for (var index = 0; index < batch.length; index++) {
        final parsed = PlatformCatalog.tracks([batch[index]]);
        if (parsed.isNotEmpty && batch[index]['fileid'] != null) {
          records[parsed.first.id] = '${batch[index]['fileid']}';
        }
      }
      var added = 0;
      for (final track in tracks) {
        if (seen.add(track.id)) {
          all.add(track);
          added++;
        }
      }
      if (batch.length < 200) {
        if (revision == _revision) _fileIds[_id(row)] = records;
        return all;
      }
      if (added == 0) throw const MusicPlatformException('平台歌曲分页未前进，请重试');
    }
    throw const MusicPlatformException('歌曲超过本次加载上限，请在平台客户端查看完整内容');
  }

  @override
  Stream<List<UserPlaylist>> watchPlaylists() => _watch(
    () async => (await _loadLists())
        .where((row) => !('${row['type']}' == '1' && '${row['source']}' == '2'))
        .map(_playlist)
        .toList(),
  );
  @override
  Stream<PlaylistDirectoryPage> watchPlaylistDirectory() =>
      _watch(() => playlistDirectoryPage());
  @override
  Future<PlaylistDirectoryPage> playlistDirectoryPage({
    int offset = 0,
    int limit = 30,
  }) async {
    final revision = _revision;
    final payload = await _get('/user/playlist', {
      'page': '${offset ~/ 30 + 1}',
      'pagesize': '30',
      'userid': identity.userId,
    });
    final rows = PlatformCatalog.rows(payload);
    if (revision == _revision) {
      final merged = {for (final row in _snapshot) _id(row): row};
      for (final row in rows) {
        merged[_id(row)] = row;
      }
      _snapshot = merged.values.toList();
    }
    return PlaylistDirectoryPage(
      rows
          .where(
            (row) => !('${row['type']}' == '1' && '${row['source']}' == '2'),
          )
          .map(_playlist)
          .toList(),
      nextOffset: offset + rows.length,
      hasMore: rows.length >= 30,
    );
  }

  @override
  Future<UserPlaylist?> getPlaylist(String id) async =>
      _playlist(await _row(id));
  @override
  Stream<List<Track>> watchPlaylistTracks(String playlistId) =>
      _watch(() async => _loadTracks(await _row(playlistId)));
  @override
  Stream<List<Track>> watchFavorites() =>
      _watch(() async => (await _favoriteIndex()).tracks);
  @override
  Stream<TrackPage> watchFavoritePreview() => _watch(() => favoritePage());
  @override
  Stream<TrackPage> watchPlaylistPreview(String id) =>
      _watch(() => playlistPage(id));
  @override
  Future<TrackPage> playlistPage(
    String id, {
    int offset = 0,
    int limit = 30,
  }) async => _pageForRow(await _row(id), offset: offset, limit: limit);

  Future<TrackPage> _pageForRow(
    Map<String, dynamic> row, {
    int offset = 0,
    int limit = 30,
  }) async {
    final revision = _revision;
    final listId = '${row['listid'] ?? ''}';
    final page = await _trackPager.page(
      listId.isEmpty ? '/playlist/track/all' : '/playlist/track/all/new',
      {
        if (listId.isNotEmpty) 'listid': listId,
        if (listId.isEmpty)
          'global_collection_id': '${row['global_collection_id'] ?? ''}',
      },
      offset: offset,
      limit: limit,
    );
    if (revision == _revision) {
      final records = _fileIds.putIfAbsent(_id(row), () => {});
      for (final record in page.items) {
        final parsed = PlatformCatalog.tracks([record]);
        if (parsed.isNotEmpty && record['fileid'] != null) {
          records[parsed.first.id] = '${record['fileid']}';
        }
      }
    }
    return TrackPage(
      PlatformCatalog.tracks(page.items),
      offset: page.offset,
      nextOffset: page.nextOffset,
      total: page.total,
      hasMore: page.hasMore,
    );
  }

  @override
  Future<TrackPage> favoritePage({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async {
    return sliceTrackPageAsync(
      (await _favoriteIndex()).tracks,
      offset: offset,
      limit: limit,
      query: query,
    );
  }

  Future<KugouFavoriteIndex> _favoriteIndex() {
    Future<KugouFavoriteIndex> load() async {
      final revision = _revision;
      final row = await _favoriteRow();
      final records = <Map<String, dynamic>>[];
      var offset = 0;
      // This endpoint cannot return newest-first pages. Fetch the index once,
      // checking list_ver between pages; transport snapshots remain privately
      // cached by the original credential. Ordinary playlists stay paginated.
      while (true) {
        final listId = '${row['listid'] ?? ''}';
        final page = await _favoritePager.page(
          listId.isEmpty ? '/playlist/track/all' : '/playlist/track/all/new',
          {
            if (listId.isNotEmpty) 'listid': listId,
            if (listId.isEmpty)
              'global_collection_id': '${row['global_collection_id'] ?? ''}',
          },
          offset: offset,
          limit: 200,
        );
        if (_closed || revision != _revision) throw StateError('收藏已变化，请重试');
        records.addAll(page.items);
        if (!page.hasMore) break;
        if (page.nextOffset <= offset || page.nextOffset > 100000) {
          throw const MusicPlatformException('收藏索引未前进，请刷新后重试');
        }
        offset = page.nextOffset;
      }
      final index = await buildKugouFavoriteIndex(records);
      if (_closed || revision != _revision) throw StateError('收藏已变化，请重试');
      _fileIds[_id(row)] = index.fileIds;
      return index;
    }

    final existing = _favorites;
    if (!BrowseResponseCache.observing && existing != null) return existing;
    return _favorites = load().catchError((Object error) {
      _favorites = null;
      throw error;
    });
  }

  @override
  Future<Set<String>> favoriteIds() async =>
      (await _favoriteIndex()).tracks.map((track) => track.id).toSet();

  @override
  Future<bool> isFavorite(String trackId) async =>
      (await favoriteIds()).contains(trackId);
  @override
  Future<void> setFavorite(Track track, {required bool favorite}) async {
    await _write(() => _setFavorite(track, favorite));
  }

  Future<void> _setFavorite(Track track, bool favorite) async {
    final row = await _favoriteRow();
    if (await isFavorite(track.id) == favorite) return;
    if (favorite) {
      await _add(row, track);
    } else {
      await _remove(row, track.id);
    }
  }

  @override
  Future<bool> toggleFavorite(Track track) => _write(() async {
    final next = !await isFavorite(track.id);
    await _setFavorite(track, next);
    return next;
  });

  /// Upstream writes use a delimiter format, not JSON. Resolve album IDs via
  /// /audio rather than dropping them or trusting a display name as an ID.
  Future<void> _add(Map<String, dynamic> row, Track track) async {
    _requireOwned(row);
    if (track.source != TrackSource.kugou || !track.id.startsWith('kugou_')) {
      throw const MusicPlatformException('酷狗云端歌单仅支持酷狗歌曲');
    }
    final hash = track.id.substring(6);
    final detail = await _get('/audio', {'hash': hash});
    final data = detail['data'];
    final record = MusicPlatformApi.objectMap(
      data is List && data.isNotEmpty ? data.first : data,
    );
    final album = MusicPlatformApi.objectMap(record['album_info']);
    final base = MusicPlatformApi.objectMap(record['base']);
    final albumId =
        '${record['album_id'] ?? album['id'] ?? base['album_id'] ?? 0}';
    final mixId =
        '${record['album_audio_id'] ?? record['mixsongid'] ?? base['album_audio_id'] ?? 0}';
    final name = track.title.replaceAll(RegExp(r'[|,]'), ' ');
    await _get('/playlist/tracks/add', {
      'listid': '${row['listid']}',
      'data': '$name|$hash|$albumId|$mixId',
    });
    _invalidate();
  }

  Future<void> _remove(Map<String, dynamic> row, String trackId) async {
    _requireOwned(row);
    // Already loaded pages retain their record IDs. The documented hash
    // fallback lets a direct action avoid fetching an entire large collection.
    final fileId = _fileIds[_id(row)]?[trackId];
    // The endpoint accepts a hash fallback; never send a global mixsongid as
    // the per-playlist record fileid, which could delete the wrong record.
    final target =
        fileId ?? (trackId.startsWith('kugou_') ? trackId.substring(6) : '');
    if (target.isEmpty) throw const MusicPlatformException('缺少云端歌曲标识，请刷新歌单');
    await _get('/playlist/tracks/del', {
      'listid': '${row['listid']}',
      'fileids': target,
    });
    _invalidate();
  }

  void _requireOwned(Map<String, dynamic> row) {
    if (!_owned(row) || '${row['listid'] ?? ''}'.isEmpty) {
      throw const MusicPlatformException('此歌单只支持查看，请操作自己创建的歌单');
    }
  }

  @override
  Future<void> addTrackToPlaylist(String playlistId, Track track) async =>
      _write(() async => _add(await _row(playlistId), track));

  /// Save the user-requested chart edition as an ordinary cloud playlist.
  /// The name identifies the captured date/edition; it is never a subscription
  /// to tomorrow's rank. A retry first reconciles the cloud, without creating
  /// a second list or resending an uncertain batch in the same repository.
  final _uncertainRankingWrites = <String>{};
  Future<String?> findRankingSnapshot(String name) async {
    final matches = (await _loadLists())
        .where((r) => _owned(r) && r['name'] == name)
        .toList();
    if (matches.length > 1) {
      throw const MusicPlatformException('发现同名收藏歌单，请在音乐库核对');
    }
    return matches.isEmpty ? null : _id(matches.single);
  }

  Future<String> saveRankingSnapshot({
    required String draftId,
    required String name,
    required List<Track> tracks,
  }) async {
    if (tracks.isEmpty) throw const MusicPlatformException('榜单暂无可收藏歌曲');
    var id = await findRankingSnapshot(name);
    if (id == null) {
      await createPlaylist(id: draftId, name: name);
      id = _createdDrafts[draftId];
    }
    if (id == null) throw const MusicPlatformException('收藏歌单尚未确认，请在音乐库核对');
    final savedId = id;
    return _write(() async {
      final row = await _row(savedId);
      _requireOwned(row);
      final existing = (await _fetchTracks(row)).map((t) => t.id).toSet();
      final wanted = {for (final t in tracks) t.id: t};
      if (wanted.keys.every(existing.contains)) return savedId;
      if (_uncertainRankingWrites.contains(savedId)) {
        throw const MusicPlatformException('部分收藏结果尚未确认，请稍后在音乐库核对，暂不重复发送');
      }
      final remaining = wanted.values
          .where((t) => !existing.contains(t.id))
          .toList();
      for (var i = 0; i < remaining.length; i += 10) {
        final batch = remaining.skip(i).take(10).toList();
        final values = <String>[];
        for (final track in batch) {
          if (track.source != TrackSource.kugou ||
              !RegExp(r'^kugou_[a-fA-F0-9]{32}$').hasMatch(track.id)) {
            throw const MusicPlatformException('榜单中包含非酷狗录音，未继续收藏');
          }
          // This existing cloud contract permits an omitted album as 0. Use
          // the authoritative mixsongid where present, never a title match.
          values.add(
            '${track.title.replaceAll(RegExp(r'[|,]'), ' ')}|${track.id.substring(6)}|0|${int.tryParse(track.platformSongId) ?? 0}',
          );
        }
        _uncertainRankingWrites.add(savedId);
        final result = await api.post(
          '/playlist/tracks/add',
          expectedSession: identity,
          query: {'listid': '${row['listid']}', 'data': values.join(',')},
        );
        if ('${result['status']}' != '1' ||
            ['error_code', 'errcode', 'err_code'].any(
              (key) => result.containsKey(key) && '${result[key]}' != '0',
            )) {
          throw const MusicPlatformException('酷狗未确认这批收藏，已保留云歌单，请稍后核对');
        }
        _uncertainRankingWrites.remove(savedId);
      }
      _invalidate();
      final observed = (await _fetchTracks(row)).map((t) => t.id).toSet();
      if (!wanted.keys.every(observed.contains)) {
        _uncertainRankingWrites.add(savedId);
        throw const MusicPlatformException('收藏尚未全部读回，请在音乐库核对，暂不重复发送');
      }
      return savedId;
    });
  }

  @override
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async => _write(() async => _remove(await _row(playlistId), trackId));
  @override
  Future<void> createPlaylist({
    required String id,
    required String name,
    String description = '',
    String? coverAsset,
    String? coverCloudId,
  }) => _write(() async {
    final draftId = id.isEmpty
        ? 'draft:${DateTime.now().microsecondsSinceEpoch}'
        : id;
    var createdId = _createdDrafts[draftId];
    // A failed/timed-out create may already have reached the cloud. A manual
    // retry of this draft only reconciles the difference; it never repeats add.
    final attempted = _creationBaselines[draftId];
    if (createdId == null && attempted != null) {
      _invalidate();
      final candidates = (await _loadLists())
          .where(
            (row) =>
                !attempted.contains(_id(row)) &&
                _owned(row) &&
                row['name'] == name,
          )
          .toList();
      if (candidates.length != 1) {
        throw const MusicPlatformException('新建结果尚未确认，请刷新音乐库核对歌单，避免重复创建');
      }
      createdId = _id(candidates.single);
    }
    if (createdId == null) {
      final baseline = (await _loadLists()).map(_id).toSet();
      _creationBaselines[draftId] = baseline;
      await _get('/playlist/add', {
        'name': name,
        'type': '0',
        'source': '1',
        'list_create_userid': identity.userId,
        'is_pri': '1',
      });
      _invalidate();
      final candidates = (await _loadLists())
          .where(
            (row) =>
                !baseline.contains(_id(row)) &&
                _owned(row) &&
                row['name'] == name,
          )
          .toList();
      if (candidates.length != 1) {
        throw const MusicPlatformException('歌单已提交，平台暂未返回唯一标识，请刷新后核对');
      }
      createdId = _id(candidates.single);
    }
    _createdDrafts[draftId] = createdId;
    if (description.isNotEmpty || (coverAsset?.isNotEmpty ?? false)) {
      await _updateMetadata(
        id: createdId,
        name: name,
        description: description,
        coverAsset: coverAsset,
      );
    }
    _invalidate();
  });

  @override
  Future<void> deletePlaylist(String id) => _write(() async {
    final row = await _row(id);
    _requireOwned(row);
    if (_systemPlaylist(row)) {
      throw const MusicPlatformException('系统收藏歌单不能在此删除');
    }
    await _get('/playlist/del', {'listid': '${row['listid']}', 'type': '1'});
    _invalidate();
  });

  @override
  Future<void> updatePlaylist({
    required String id,
    required String name,
    required String description,
    required String? coverAsset,
    String? coverCloudId,
  }) => _write(() async {
    await _updateMetadata(
      id: id,
      name: name,
      description: description,
      coverAsset: coverAsset,
    );
  });

  Future<String?> _uploadCover(String? path, Map<String, dynamic> row) async {
    if (path == null || path.isEmpty || path == _playlist(row).coverAsset) {
      return null;
    }
    final uri = Uri.tryParse(path);
    if (uri?.scheme == 'http' || uri?.scheme == 'https') {
      throw const MusicPlatformException('请从相册或模板选择新封面');
    }
    final file = File(path);
    if (!await file.exists() || await file.length() > 10 * 1024 * 1024) {
      throw const MusicPlatformException('封面文件不存在或超过 10 MB，请重新选择');
    }
    final result = await api.post(
      '/playlist/pic/upload',
      expectedSession: identity,
      query: {'file': path, 'type': 'custom', 'extendName': '.png'},
      timeout: const Duration(seconds: 35),
    );
    final filename = '${result['FileName'] ?? ''}';
    if ('${result['status']}' != '1' ||
        filename.isEmpty ||
        filename.contains('..') ||
        filename.contains('://')) {
      throw const MusicPlatformException('酷狗未能接收封面，请换一张图片或稍后重试');
    }
    return 'custom/$filename';
  }

  Future<void> _updateMetadata({
    required String id,
    required String name,
    required String description,
    required String? coverAsset,
  }) async {
    final row = await _row(id);
    _requireOwned(row);
    if (_systemPlaylist(row)) {
      throw const MusicPlatformException('系统收藏歌单不能在此修改封面');
    }
    final picture = await _uploadCover(coverAsset, row);
    final snapshot = await _get('/user/playlist', {
      'page': '1',
      'pagesize': '30',
      'userid': identity.userId,
    });
    final data = MusicPlatformApi.objectMap(snapshot['data']);
    final version = data['total_ver'] ?? snapshot['total_ver'];
    if (version == null || int.tryParse('$version') == null) {
      throw const MusicPlatformException('未能读取歌单版本，请刷新后重试，输入已保留');
    }
    await _get('/playlist/update', {
      'listid': '${row['listid']}',
      'name': name,
      'intro': description,
      'pic': ?picture,
      'total_ver': '$version',
      'type': '0',
      'sort': '${row['sort'] ?? 0}',
      'tags': '${row['tags'] ?? ''}',
      'is_pri': '${row['is_pri'] ?? 1}',
    });
    _invalidate();
  }

  @override
  Future<void> reorderPlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) => Future.error(const MusicPlatformException('酷狗云歌单暂不支持在此调整歌曲顺序'));
  @override
  Future<bool> synchronize({bool forcePull = false}) async {
    _invalidate();
    return true;
  }

  @override
  Future<int> countLegacyFavorites() async => 0;
  @override
  Future<void> importLegacyLibrary() =>
      Future.error(const MusicPlatformException('本机曲库不会自动上传到酷狗'));
  @override
  void dispose() {
    _closed = true;
    unawaited(_changes.close());
    super.dispose();
  }
}
