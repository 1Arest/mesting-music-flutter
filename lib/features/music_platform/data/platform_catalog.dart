import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import 'embedded_kugou_music_source.dart';
import 'music_platform_api.dart';
import 'kugou_playlist_paging.dart';
import 'package:flutter/foundation.dart';

/// Shared response parsing for the upstream discovery and cloud-list APIs.
/// No UI page constructs signed URLs or guesses cloud playlist identifiers.
class PlatformCatalog {
  PlatformCatalog(this.api);
  final MusicPlatformApi api;
  late final _playlists = KugouPlaylistPaging(
    read: (path, query) => api.get(path, query: query),
    rows: rows,
  );

  static List<Map<String, dynamic>> rows(Object? value) {
    if (value is List) {
      return value.whereType<Map>().map(MusicPlatformApi.objectMap).toList();
    }
    if (value is Map) {
      for (final key in [
        'data',
        'info',
        'songs',
        'song_list',
        // Upstream rank/audio and top/playlist use these distinct envelopes.
        'songlist',
        'special_list',
        'plist',
        'list',
        'lists',
        'tracks',
        'items',
      ]) {
        if (value[key] is List) return rows(value[key]);
      }
      if (value['data'] is Map) return rows(value['data']);
    }
    return const [];
  }

  static List<Track> tracks(Object? value) => rows(value)
      .map(EmbeddedKugouMusicSource.platformTrack)
      .whereType<Track>()
      // The audio handler resolves this private marker immediately before
      // loading each active song. Listing 10,000 favorites needs no 10,000 URL
      // requests; signed media URLs never become a persistent cloud cache.
      .map(
        (track) =>
            track.copyWith(audioAsset: 'mesting-platform://kugou/${track.id}'),
      )
      .toList(growable: false);

  static Future<List<Track>> tracksAsync(Object? value) {
    final values = rows(value);
    return values.length < 100
        ? Future.value(tracks(values))
        : compute(tracks, values, debugLabel: 'kugou-track-metadata');
  }

  Future<List<Track>> daily() async {
    final payload = await api.get('/everyday/recommend');
    return tracksAsync(payload);
  }

  /// Public new-song chart, separate from account-based daily recommendations.
  Future<List<Track>> newSongs() async => tracksAsync(
    await api.get(
      '/top/song',
      query: const {'type': '21608', 'pagesize': '30'},
    ),
  );

  Future<List<Track>> discovery() async => tracks(
    await api.get(
      '/home/discover',
      query: const {'pagesize': '20', 'recall_type': 'song'},
    ),
  );

  Future<List<Map<String, dynamic>>> featured() async =>
      rows(await api.get('/top/playlist', query: const {'page': '1'}));

  Future<List<Track>> publicPlaylist(String globalId) async {
    final result = <Track>[];
    final seen = <String>{};
    for (var page = 1; page <= 50; page++) {
      final payload = await api.get(
        '/playlist/track/all',
        query: {
          'global_collection_id': globalId,
          'page': '$page',
          'pagesize': '200',
        },
      );
      final batch = rows(payload);
      var added = 0;
      for (final track in tracks(batch)) {
        if (seen.add(track.id)) {
          result.add(track);
          added++;
        }
      }
      if (batch.length < 200) return result;
      if (added == 0) throw const MusicPlatformException('平台歌单分页未前进，请重新加载');
    }
    throw const MusicPlatformException('歌单超过本次加载上限，请在平台客户端查看完整内容');
  }

  Future<TrackPage> publicPlaylistPage(
    String globalId, {
    int offset = 0,
    int limit = 30,
  }) async {
    final page = await _playlists.page(
      '/playlist/track/all',
      {'global_collection_id': globalId},
      offset: offset,
      limit: limit,
    );
    return TrackPage(
      tracks(page.items),
      offset: page.offset,
      nextOffset: page.nextOffset,
      total: page.total,
      hasMore: page.hasMore,
    );
  }
}
