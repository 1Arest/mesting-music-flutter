import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import '../data/platform_catalog.dart';
import '../data/platform_category_search.dart';
import '../data/platform_explore.dart';
import '../data/platform_recommendations.dart';
import '../data/platform_search_repository.dart';
import 'netease_music_repository.dart';

/// Thin adapters retain the existing presentation interfaces. Protocol fields
/// and IDs remain in NeteaseMusicRepository; no widget imitates a Kugou payload.
class NeteaseSearchAdapter extends PlatformSearchRepository {
  NeteaseSearchAdapter(super.api, this.music);
  final NeteaseMusicRepository music;
  @override
  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) => music.search(query, page: page, abort: abortTrigger);
}

class NeteaseCategoryAdapter extends PlatformCategorySearchRepository {
  const NeteaseCategoryAdapter(super.api, this.music);
  final NeteaseMusicRepository music;
  @override
  Future<PlatformCategoryPage> search(
    String query,
    PlatformSearchKind kind, {
    int page = 1,
    Future<void>? abortTrigger,
  }) => music.category(query, kind, page: page, abort: abortTrigger);
}

class NeteaseCatalogAdapter extends PlatformCatalog {
  NeteaseCatalogAdapter(super.api, this.music);
  final NeteaseMusicRepository music;
  @override
  Future<List<Track>> daily() => music.daily();
  @override
  Future<List<Track>> newSongs() => music.newSongs();
  @override
  Future<List<Track>> discovery() => music.fm();
  @override
  Future<List<Map<String, dynamic>>> featured() => music.featured();
  @override
  Future<List<Track>> publicPlaylist(String globalId) =>
      music.playlist(globalId);
  @override
  Future<TrackPage> publicPlaylistPage(
    String globalId, {
    int offset = 0,
    int limit = 30,
  }) => music.playlistPage(globalId, offset: offset, limit: limit);
}

class NeteaseRecommendationsAdapter extends PlatformRecommendations {
  NeteaseRecommendationsAdapter(
    super.api,
    super.preferences,
    super.identity,
    this.music,
  );
  final NeteaseMusicRepository music;
  final List<Track> _songs = [];
  bool _closed = false;
  Future<List<Track>>? _pending;
  @override
  List<Track> get discoverySongs => List.unmodifiable(_songs);
  @override
  int get cursor => _songs.length;
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  @override
  Future<List<PlatformHotSearchBoard>> hotSearch() async {
    final payload = await music.call('/search/hot');
    final words = NeteaseMusicRepository.rows(payload['data'])
        .map((r) => '${r['searchWord'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    return [PlatformHotSearchBoard('网易云热搜', words)];
  }

  @override
  Future<List<Track>> personalFm(
    PlatformFmStation station, {
    bool first = true,
    Track? anchor,
    String? action,
  }) => music.fm();
  @override
  Future<List<Track>> discover({bool more = false}) =>
      _pending ??= _load().whenComplete(() => _pending = null);
  Future<List<Track>> _load() async {
    final fresh = await music.fm();
    if (_closed) return const [];
    final ids = _songs.map((t) => t.id).toSet();
    final added = fresh.where((t) => ids.add(t.id)).toList();
    _songs.addAll(added);
    return added;
  }

  @override
  Future<List<Track>> feedback(
    Track track,
    String action, {
    int? seconds,
    bool complete = false,
  }) async {
    // Favorites already have one authoritative write in the library adapter.
    if (action == 'garbage') {
      await music.call('/fm/trash', {
        'id': NeteaseMusicRepository.songId(track.id),
        'time': seconds ?? 0,
      });
      return music.fm();
    }
    return const [];
  }
}

class NeteaseExploreAdapter extends PlatformExploreRepository {
  NeteaseExploreAdapter(super.api, this.music);
  final NeteaseMusicRepository music;
  @override
  Future<TrackPage> tracksPage(
    PlatformExploreItem item, {
    int offset = 0,
    int limit = 30,
  }) => music.exploreTrackPage(item, offset: offset, limit: limit);
  @override
  Future<List<PlatformExploreItem>> list(
    PlatformExploreKind kind, {
    int page = 1,
  }) => music.explore(kind, page: page);
  @override
  Future<PlatformExploreItem> resolveScene(PlatformExploreItem item) async =>
      item;
  @override
  Future<List<Track>> tracks(PlatformExploreItem item, {int page = 1}) async {
    return (await music.exploreTrackPage(
      item,
      offset: (page - 1).clamp(0, 1 << 31) * 30,
      limit: 30,
    )).items;
  }

  @override
  Future<List<PlatformExploreItem>> sceneCollections(
    PlatformExploreItem scene, {
    int page = 1,
  }) => music.explore(PlatformExploreKind.playlist, page: page);
}
