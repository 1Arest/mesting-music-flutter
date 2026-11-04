import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import 'track_page_utils.dart';
import '../../../core/cache/browse_response_cache.dart';
import 'music_platform_api.dart';
import 'platform_catalog.dart';
import 'platform_artwork.dart';

enum PlatformExploreKind {
  theme('主题歌单', '/theme/playlist'),
  // Labels come from the scene catalogue. /scene/music returns recommended
  // tracks; it does not define the catalogue of named scene categories.
  scene('场景音乐', '/scene/lists'),
  playlist('热门歌单', '/top/playlist'),
  rank('排行榜', '/rank/list'),
  album('新碟上架', '/top/album');

  const PlatformExploreKind(this.label, this.path);
  final String label, path;
}

/// Scene tags declare either audio rows (6) or collections (1). They require
/// different provider routes; preserving this type prevents false load errors.
enum PlatformSceneContent { tracks, collections }

class PlatformExploreItem {
  const PlatformExploreItem({
    required this.id,
    required this.title,
    required this.cover,
    required this.kind,
    this.rankCid = '',
    this.subtitle = '',
    this.moduleId = '',
    this.tag = '',
    this.sceneContent = PlatformSceneContent.tracks,
  });
  final String id, title, cover, rankCid;
  final String subtitle, moduleId, tag;
  final PlatformExploreKind kind;
  final PlatformSceneContent sceneContent;
}

/// Mirrors md3Music's MusicExploreSections and provider field parsing. No
/// personalized local ranking is applied to public discovery catalogues.
class PlatformExploreRepository {
  const PlatformExploreRepository(this.api);
  final MusicPlatformApi api;
  Future<List<PlatformExploreItem>> list(
    PlatformExploreKind kind, {
    int page = 1,
  }) async {
    final payload = await api.get(
      kind.path,
      query: {
        if (kind == PlatformExploreKind.rank) 'withsong': '1',
        if (kind == PlatformExploreKind.playlist ||
            kind == PlatformExploreKind.album)
          'page': '$page',
      },
    );
    var rows = PlatformCatalog.rows(payload);
    if (kind == PlatformExploreKind.theme && rows.isEmpty) {
      final themeData = MusicPlatformApi.objectMap(payload['data']);
      rows = PlatformCatalog.rows(
        themeData['themes'] ?? themeData['theme_list'],
      );
    }
    if (kind == PlatformExploreKind.scene) rows = _sceneRows(payload);
    final data = MusicPlatformApi.objectMap(payload['data']);
    if (kind == PlatformExploreKind.rank && rows.isEmpty) {
      rows = PlatformCatalog.rows(data['ranks']);
    }
    if (kind == PlatformExploreKind.album && rows.isEmpty) {
      rows = [
        for (final key in ['chn', 'eur', 'jpn', 'kor'])
          ...PlatformCatalog.rows(data[key]),
      ];
      if (rows.isEmpty) rows = PlatformCatalog.rows(data['albums']);
    }
    return rows
        .map((row) {
          String text(List<String> keys) {
            for (final key in keys) {
              if ('${row[key] ?? ''}'.isNotEmpty) return '${row[key]}';
            }
            return '';
          }

          // The live scene catalogue already carries its first audio module.
          // Keep this server-provided seed instead of discarding it and then
          // guessing which module/tag belongs to the named scene on opening.
          final sceneSeed = kind == PlatformExploreKind.scene
              ? _sceneSeed(MusicPlatformApi.objectMap(row['music_tag']))
              : null;
          var cover = PlatformArtwork.fromPayload(row);
          if (kind == PlatformExploreKind.scene && cover.isEmpty) {
            // Some real scenes have an empty `pic` and a valid official icon.
            // Do not replace them with artwork from an unrelated song/module.
            for (final key in ['icon', 'bg_pic', 'title_pic']) {
              cover = PlatformArtwork.normalize(row[key]);
              if (cover.isNotEmpty) break;
            }
          }

          return PlatformExploreItem(
            id: text(switch (kind) {
              PlatformExploreKind.playlist => [
                'global_collection_id',
                'gid',
                'specialid',
                'id',
              ],
              PlatformExploreKind.album => [
                'albumid',
                'album_id',
                'AlbumID',
                'id',
              ],
              PlatformExploreKind.rank => [
                'rankid',
                'rank_id',
                'id',
                'classify',
              ],
              _ => ['id', 'theme_id', 'scene_id'],
            }),
            title: text([
              'name',
              'specialname',
              'rankname',
              'album_name',
              'albumname',
              'title',
              'scene_name',
              'theme_name',
            ]),
            cover: cover,
            kind: kind,
            rankCid: text(['rank_cid']),
            subtitle: text([
              'singername',
              'author_name',
              'intro',
              'description',
            ]),
            moduleId: sceneSeed?.moduleId ?? text(['module_id']),
            tag: sceneSeed?.tag ?? text(['tag']),
            sceneContent: sceneSeed?.content ?? PlatformSceneContent.tracks,
          );
        })
        .where((item) => item.title.isNotEmpty && item.id.isNotEmpty)
        .toList();
  }

  /// Keep the established audio-first view where available. A scene declaring
  /// only collections must open those real playlists rather than fabricating
  /// tracks or sending its collection tag to the audio endpoint.
  static ({String moduleId, String tag, PlatformSceneContent content})?
  _sceneSeed(Map<String, dynamic> module) {
    final id = '${module['module_id'] ?? module['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final tags = PlatformCatalog.rows(
      module['module_extra'] ?? module['extra'],
    );
    for (final type in ['6', '1']) {
      for (final tag in tags) {
        if ('${tag['content_type'] ?? tag['types'] ?? ''}' != type) continue;
        final tagId = '${tag['tag_id'] ?? tag['id'] ?? ''}'.trim();
        if (tagId.isNotEmpty) {
          return (
            moduleId: id,
            tag: tagId,
            content: type == '6'
                ? PlatformSceneContent.tracks
                : PlatformSceneContent.collections,
          );
        }
      }
    }
    return null;
  }

  /// Scene catalogues use both flat and grouped envelopes. Only real named
  /// scene records become labels; recommendation tracks are not substitutes.
  static List<Map<String, dynamic>> _sceneRows(Object? value) {
    if (value is List) return [for (final item in value) ..._sceneRows(item)];
    if (value is! Map) return const [];
    final row = MusicPlatformApi.objectMap(value);
    for (final key in [
      'data',
      'scene_list',
      'scenes',
      'list',
      'lists',
      'info',
      'children',
    ]) {
      final nested = _sceneRows(row[key]);
      if (nested.isNotEmpty) return nested;
    }
    final id = row['scene_id'] ?? row['id'];
    final name = row['scene_name'] ?? row['name'] ?? row['title'];
    return id != null &&
            '$id'.isNotEmpty &&
            name != null &&
            '$name'.trim().isNotEmpty
        ? [row]
        : const [];
  }

  /// A named scene is a catalogue, not a generic recommendation seed. Resolve
  /// the server's first music module/tag in its own order; skip video, books
  /// and discussion modules instead of guessing parameters for audio_list.
  Future<PlatformExploreItem> resolveScene(PlatformExploreItem item) async {
    if (item.kind != PlatformExploreKind.scene ||
        (item.moduleId.isNotEmpty && item.tag.isNotEmpty)) {
      return item;
    }
    final payload = await api.get('/scene/module', query: {'id': item.id});
    final data = MusicPlatformApi.objectMap(payload['data']);
    final content = data['content'];
    // Current /scene/module groups music/discuss/banner beneath `content`.
    // Older responses used a flat list. Only enter the explicit music branch;
    // recursively scanning `info` would mistake scene metadata for a module.
    final modules = content is Map
        ? PlatformCatalog.rows(content['music'])
        : PlatformCatalog.rows(content);
    for (final module in modules) {
      if ('${module['module_type'] ?? ''}' != '2') continue;
      final seed = _sceneSeed(module);
      if (seed != null) {
        return PlatformExploreItem(
          id: item.id,
          title: item.title,
          cover: item.cover,
          kind: item.kind,
          subtitle: item.subtitle,
          rankCid: item.rankCid,
          moduleId: seed.moduleId,
          tag: seed.tag,
          sceneContent: seed.content,
        );
      }
    }
    throw const MusicPlatformException('此场景暂未提供可播放的音乐内容');
  }

  static final _fixedSnapshots = Expando<Map<String, Future<List<Track>>>>('fixed-collection-pages');
  Map<String, Future<List<Track>>> get _fixedTrackSnapshots => _fixedSnapshots[this] ??= {};
  Future<TrackPage> tracksPage(
    PlatformExploreItem item, {
    int offset = 0,
    int limit = 30,
  }) async {
    if (item.kind == PlatformExploreKind.theme) {
      if (BrowseResponseCache.observing) {
        final current = tracks(item);
        _fixedTrackSnapshots[item.id] = current;
        return sliceTrackPageAsync(await current, offset: offset, limit: limit);
      }
      final values = await (_fixedTrackSnapshots[item.id] ??= tracks(item)
          .catchError((Object error) {
            _fixedTrackSnapshots.remove(item.id);
            throw error;
          }));
      return sliceTrackPageAsync(values, offset: offset, limit: limit);
    }
    final values = await tracks(item, page: offset ~/ 30 + 1);
    return TrackPage(
      values,
      offset: offset,
      nextOffset: offset + values.length,
      hasMore: values.length >= 30,
    );
  }

  Future<List<Track>> tracks(PlatformExploreItem item, {int page = 1}) async {
    item = await resolveScene(item);
    if (item.kind == PlatformExploreKind.scene &&
        item.sceneContent == PlatformSceneContent.collections) {
      throw const MusicPlatformException('此专区提供歌单，请先选择歌单');
    }
    final path = switch (item.kind) {
      PlatformExploreKind.rank => '/rank/audio',
      PlatformExploreKind.album => '/album/songs',
      PlatformExploreKind.playlist => '/playlist/track/all',
      PlatformExploreKind.theme => '/theme/playlist/track',
      PlatformExploreKind.scene => '/scene/audio/list',
    };
    return PlatformCatalog.tracksAsync(
      await api.get(
        path,
        query: {
          if (item.kind == PlatformExploreKind.rank) ...{
            'rankid': item.id,
            'rank_cid': item.rankCid.isEmpty ? '0' : item.rankCid,
          },
          if (item.kind == PlatformExploreKind.album) 'album_id': item.id,
          if (item.kind == PlatformExploreKind.playlist)
            'global_collection_id': item.id,
          // The theme endpoint requires theme_id, not the generic scene id.
          if (item.kind == PlatformExploreKind.theme) 'theme_id': item.id,
          if (item.kind == PlatformExploreKind.scene) ...{
            'id': item.id,
            if (item.moduleId.isNotEmpty) 'module_id': item.moduleId,
            if (item.tag.isNotEmpty) 'tag': item.tag,
          },
          'page': '$page',
          'pagesize': '30',
        },
      ),
    );
  }

  /// Scene collection IDs are already global `collection_*` identifiers.
  /// Preserve them verbatim; the unrelated numeric specialid is not a global
  /// collection ID and cannot replace it when opening the playlist's songs.
  Future<List<PlatformExploreItem>> sceneCollections(
    PlatformExploreItem scene, {
    int page = 1,
  }) async {
    scene = await resolveScene(scene);
    if (scene.kind != PlatformExploreKind.scene ||
        scene.sceneContent != PlatformSceneContent.collections) {
      throw const MusicPlatformException('此场景未提供歌单');
    }
    final payload = await api.get(
      '/scene/collection/list',
      query: {'tag_id': scene.tag, 'page': '$page', 'pagesize': '30'},
    );
    return PlatformCatalog.rows(payload)
        .where(
          (row) =>
              '${row['content_type'] ?? 1}' == '1' &&
              '${row['is_publish'] ?? 1}' != '0',
        )
        .map(
          (row) => PlatformExploreItem(
            id: '${row['global_collection_id'] ?? row['content_id'] ?? row['id'] ?? ''}',
            title: '${row['title'] ?? row['name'] ?? ''}',
            cover: PlatformArtwork.fromPayload(row),
            kind: PlatformExploreKind.playlist,
            subtitle:
                '${MusicPlatformApi.objectMap(row['author_info'])['user_name'] ?? ''}',
          ),
        )
        .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
        .toList();
  }
}
