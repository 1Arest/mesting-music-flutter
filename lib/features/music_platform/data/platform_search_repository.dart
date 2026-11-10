import '../../../shared/models/track.dart';
import 'embedded_kugou_music_source.dart';
import 'music_platform_api.dart';
import '../../../shared/models/song_search_facts.dart';
import 'platform_track_duration.dart';

class PlatformSearchPage {
  const PlatformSearchPage(
    this.tracks,
    this.total,
    this.hasMore, {
    this.facts = const {},
  });
  final List<Track> tracks;
  final int? total;
  final bool hasMore;
  final Map<String, SongSearchFacts> facts;
}

/// Direct adaptation of upstream KugouApiClient.search: 30 rows per page,
/// original server ranking and total/total_count. No Mesting fuzzy ranking or
/// title/artist deduplication: different recordings must remain selectable.
class PlatformSearchRepository {
  PlatformSearchRepository(this.api);
  final MusicPlatformApi api;
  static const pageSize = 30;

  /// Metadata-only normal-source check: no media download, device registration,
  /// listening report or account change may be triggered by showing results.
  Future<SongSearchFacts> inspectAvailability(
    Track track,
    SongSearchFacts facts, {
    Future<void>? abortTrigger,
  }) async {
    final payload = await api.get(
      '/song/url',
      query: {'hash': track.id.substring(6).toLowerCase(), 'quality': '128'},
      expectedSession: api.session,
      allowBusinessError: true,
      abortTrigger: abortTrigger,
    );
    final raw = payload['data'];
    final row = MusicPlatformApi.objectMap(
      raw is List && raw.isNotEmpty ? raw.first : raw ?? payload,
    );
    final url = row['url'] ?? row['play_url'];
    final candidates = url is List ? url : [url];
    if (!candidates.any((u) {
      final uri = Uri.tryParse('$u');
      return uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty;
    })) {
      // A registration/transient business error is not a rights verdict.
      // Search must not register a device or claim unavailable on that basis.
      return facts.withAccess(
        '${row['priv_status']}' == '0'
            ? SearchPlaybackAccess.restricted
            : SearchPlaybackAccess.unknown,
      );
    }
    final fail = row['fail_process'];
    final size =
        int.tryParse('${row['fileSize'] ?? row['file_size'] ?? 0}') ?? 0;
    final preview =
        (fail is List && fail.contains('buy')) || size > 0 && size < 200 * 1024;
    final duration = PlatformTrackDuration.fromFields(row);
    final short =
        duration != null &&
        track.duration > duration + const Duration(seconds: 3);
    return facts.withAccess(
      preview || short
          ? SearchPlaybackAccess.preview
          : duration != null && track.duration > Duration.zero
          ? SearchPlaybackAccess.full
          : SearchPlaybackAccess.unknown,
    );
  }

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
