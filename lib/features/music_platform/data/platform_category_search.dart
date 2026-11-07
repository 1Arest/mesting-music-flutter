import '../../../shared/models/track.dart';
import 'embedded_kugou_music_source.dart';
import 'music_platform_api.dart';
import 'platform_artwork.dart';
import 'platform_catalog.dart';
import '../domain/platform_search_user.dart';

enum PlatformSearchKind {
  songs('歌曲', '/search'),
  albums('专辑', '/search/album'),
  artists('歌手', '/search/artist'),
  playlists('歌单', '/search/special'),
  lyrics('歌词', '/search'),
  users('用户', '/search');

  const PlatformSearchKind(this.label, this.path);
  final String label, path;
}

class PlatformSearchHit {
  const PlatformSearchHit({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.cover = '',
    this.globalId = '',
    this.count,
    this.track,
    this.lyric = '',
    this.user,
  });
  final PlatformSearchKind kind;
  final String id, title, subtitle, cover, globalId, lyric;
  final int? count;
  final Track? track;
  final PlatformSearchUser? user;
}

class PlatformCategoryPage {
  const PlatformCategoryPage(this.items, this.total, this.hasMore);
  final List<PlatformSearchHit> items;
  final int? total;
  final bool hasMore;
}

/// Typed adaptation of the five upstream search contracts. Lyric *content*
/// search is /search?type=lyric; /search/lyric retrieves download candidates.
class PlatformCategorySearchRepository {
  const PlatformCategorySearchRepository(this.api);
  final MusicPlatformApi api;
  static String clean(Object? value) => '${value ?? ''}'
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .trim();
  static String field(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = clean(row[key]);
      if (value.isNotEmpty && value != '0') return value;
    }
    return '';
  }

  Future<PlatformCategoryPage> search(
    String query,
    PlatformSearchKind kind, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    if (kind == PlatformSearchKind.users) {
      throw const MusicPlatformException('用户搜索仅支持网易云');
    }
    final identity = api.session;
    const size = 30;
    final result = await api.get(
      kind.path,
      query: {
        'keywords': query,
        'page': '$page',
        'pagesize': '$size',
        if (kind == PlatformSearchKind.lyrics) 'type': 'lyric',
      },
      expectedSession: identity,
      abortTrigger: abortTrigger,
    );
    final payload = result['data'] ?? result;
    final data = MusicPlatformApi.objectMap(payload);
    final rows = PlatformCatalog.rows(payload);
    final items = <PlatformSearchHit>[];
    for (final row in rows) {
      String get(List<String> keys) => field(row, keys);
      final cover = PlatformArtwork.fromPayload(row);
      final track =
          kind == PlatformSearchKind.lyrics || kind == PlatformSearchKind.songs
          ? EmbeddedKugouMusicSource.platformTrack(row)
          : null;
      if (track != null) {
        final value = Track.fromJson({
          ...track.toJson(),
          'title': clean(track.title),
          'artist': clean(track.artist),
          'album': clean(track.album),
          'audioAsset': 'mesting-platform://kugou/${track.id}',
        });
        items.add(
          PlatformSearchHit(
            kind: kind,
            id: value.id,
            title: value.title,
            subtitle: value.artist,
            cover: value.coverAsset,
            track: value,
            lyric: get(['Lyric', 'lyric', 'lyrics', 'content']),
          ),
        );
      } else if (kind == PlatformSearchKind.albums) {
        final id = get(['albumid', 'album_id', 'AlbumID']);
        if (id.isEmpty) continue;
        items.add(
          PlatformSearchHit(
            kind: kind,
            id: id,
            title: get(['albumname', 'album_name', 'AlbumName', 'name']),
            cover: cover,
            subtitle: get(['singername', 'author_name', 'SingerName']),
          ),
        );
      } else if (kind == PlatformSearchKind.artists) {
        final id = get(['singerid', 'author_id', 'singer_id', 'SingerId']);
        if (id.isEmpty) continue;
        items.add(
          PlatformSearchHit(
            kind: kind,
            id: id,
            title: get([
              'singername',
              'author_name',
              'singer_name',
              'SingerName',
              'name',
            ]),
            cover: cover,
            subtitle: '歌手',
          ),
        );
      } else if (kind == PlatformSearchKind.playlists) {
        final id = get([
          'specialid',
          'special_id',
          'global_collection_id',
          'gid',
        ]);
        if (id.isEmpty) continue;
        items.add(
          PlatformSearchHit(
            kind: kind,
            id: id,
            globalId: get([
              'global_specialid',
              'global_collection_id',
              'gid',
              'GlobalCollectionId',
            ]),
            title: get(['specialname', 'special_name', 'name', 'title']),
            cover: cover,
            count: int.tryParse(get(['songcount', 'song_count', 'count'])),
          ),
        );
      }
    }
    final total = int.tryParse(
      '${data['total'] ?? data['total_count'] ?? data['totalcount'] ?? ''}',
    );
    return PlatformCategoryPage(
      items,
      total,
      rows.isNotEmpty &&
          (total == null ? rows.length >= size : page * size < total),
    );
  }
}
