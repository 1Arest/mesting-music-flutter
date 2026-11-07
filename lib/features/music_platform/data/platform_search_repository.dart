import '../../../shared/models/track.dart';
import 'embedded_kugou_music_source.dart';
import 'music_platform_api.dart';

class PlatformSearchPage {
  const PlatformSearchPage(this.tracks, this.total, this.hasMore);
  final List<Track> tracks;
  final int? total;
  final bool hasMore;
}

/// Direct adaptation of upstream KugouApiClient.search: 30 rows per page,
/// original server ranking and total/total_count. No Mesting fuzzy ranking or
/// title/artist deduplication: different recordings must remain selectable.
class PlatformSearchRepository {
  PlatformSearchRepository(this.api);
  final MusicPlatformApi api;
  static const pageSize = 30;

  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    final identity = api.session;
    final result = await api.get(
      '/search',
      query: {
        'keywords': query,
        'page': '$page',
        'pagesize': '$pageSize',
        'type': 'song',
      },
      abortTrigger: abortTrigger,
      expectedSession: identity,
    );
    if (api.session?.userId != identity?.userId ||
        api.session?.token != identity?.token) {
      throw const MusicPlatformException('账号已变化，请重新搜索');
    }
    final data = MusicPlatformApi.objectMap(result['data'] ?? result);
    final rows = data['lists'] ?? data['songs'] ?? data['info'] ?? const [];
    if (rows is! List) throw const MusicPlatformException('搜索结果格式异常，请重试');
    final tracks = rows
        .whereType<Map>()
        .map(
          (row) => EmbeddedKugouMusicSource.platformTrack(
            MusicPlatformApi.objectMap(row),
          ),
        )
        .whereType<Track>()
        .map(
          (track) => track.copyWith(
            audioAsset: 'mesting-platform://kugou/${track.id}',
          ),
        )
        .toList(growable: false);
    final total = int.tryParse('${data['total'] ?? data['total_count'] ?? ''}');
    return PlatformSearchPage(
      tracks,
      total,
      rows.isNotEmpty &&
          (total == null ? rows.length >= pageSize : page * pageSize < total),
    );
  }
}
