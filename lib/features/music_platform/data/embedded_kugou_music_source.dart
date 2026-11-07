import '../../../shared/models/track.dart';
import '../../search/data/kugou_music_source.dart';
import 'music_platform_api.dart';
import 'platform_playback_resolver.dart';
import 'platform_song_identity.dart';
import 'platform_artwork.dart';
import 'platform_track_duration.dart';
import '../domain/platform_audio_quality.dart';

/// Translates md3Music data into existing Mesting tracks and uses its one audio
/// handler. Other distribution channels keep their existing source selection.
class EmbeddedKugouMusicSource extends KugouMusicSource {
  EmbeddedKugouMusicSource(super.client, this.api)
    : resolver = PlatformPlaybackResolver(api);
  final MusicPlatformApi api;
  final PlatformPlaybackResolver resolver;

  /// Refresh only the selected song at playback time. Stored library rows may
  /// outlive a signed URL or have been saved under a different platform login.
  Future<Track> resolveTrack(
    Track track, {
    Future<void>? abortTrigger,
    PlatformAudioQuality quality = PlatformAudioQuality.standard,
    bool requireRequestedQuality = false,
  }) async {
    if (track.source != TrackSource.kugou || !track.id.startsWith('kugou_')) {
      return track;
    }
    return resolver.resolve(
      track,
      abortTrigger: abortTrigger,
      quality: quality,
      requireRequestedQuality: requireRequestedQuality,
    );
  }

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    final result = await api.get(
      '/search',
      query: {
        'keywords': query,
        'page': '1',
        'pagesize': '$limit',
        'type': 'song',
      },
      abortTrigger: abortTrigger,
    );
    return _resolveRows(result, limit, abortTrigger);
  }

  @override
  Future<List<Track>> ranking({
    required String rankId,
    required String sourceLabel,
    int limit = 9,
    Future<void>? abortTrigger,
  }) async {
    final result = await api.get(
      '/rank/audio',
      query: {'rankid': rankId, 'page': '1', 'pagesize': '$limit'},
      abortTrigger: abortTrigger,
    );
    return _resolveRows(result, limit, abortTrigger);
  }

  Future<List<Track>> _resolveRows(
    Map<String, dynamic> result,
    int limit,
    Future<void>? abortTrigger,
  ) async {
    final raw = result['data'];
    final data = MusicPlatformApi.objectMap(raw);
    final rows = raw is List
        ? raw
        : data['lists'] ??
              data['songs'] ??
              data['info'] ??
              data['songlist'] ??
              data['list'];
    if (rows is! List) return const [];
    final candidates = rows.whereType<Map>().take(limit).toList();
    // Metadata is not a license decision. Resolve on explicit playback, rather
    // than locking the whole search page after a temporary URL failure.
    return candidates
        .map((row) => platformTrack(MusicPlatformApi.objectMap(row)))
        .whereType<Track>()
        .map(
          (track) => track.copyWith(
            audioAsset: 'mesting-platform://kugou/${track.id}',
            availabilityMessage: '点击获取播放地址',
          ),
        )
        .toList(growable: false);
  }

  /// Response shapes differ by endpoint; preserve provider IDs for later
  /// account/playlist adapters and strip highlight markup from search results.
  static Track? platformTrack(Map<String, dynamic> row) {
    // Cloud lists and discovery responses put metadata into nested records.
    // Top-level fields win, matching the upstream model contract.
    row = {
      for (final key in [
        'album_info',
        'audio_info',
        'song_info',
        'base',
        'audio',
        'rec_song_info',
      ])
        ...MusicPlatformApi.objectMap(row[key]),
      ...row,
    };
    String text(List<String> keys) {
      for (final key in keys) {
        final value = '${row[key] ?? ''}'
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final hash = text([
      'hash',
      'FileHash',
      'filehash',
      'audio_hash',
      'hash_128',
      'Hash128',
      'sd_hash',
    ]);
    if (hash.isEmpty) return null;
    final singers = row['singerinfo'] ?? row['authors'] ?? row['singers'];
    final singerNames = singers is List
        ? singers
              .whereType<Map>()
              .map(
                (item) =>
                    '${item['name'] ?? item['author_name'] ?? item['singername'] ?? ''}',
              )
              .where((name) => name.isNotEmpty)
              .join(' / ')
        : '';
    return Track(
      id: 'kugou_$hash',
      title: text([
        'songname',
        'SongName',
        'audio_name',
        'name',
        'filename',
        'ori_audio_name',
        'FileName',
      ]),
      artist: singerNames.isNotEmpty
          ? singerNames
          : text([
              'singername',
              'SingerName',
              'author_name',
              'singer',
              'author',
            ]),
      album: text(['album_name', 'AlbumName', 'albumname']),
      duration: PlatformTrackDuration.fromFields(row) ?? Duration.zero,
      audioAsset: '',
      coverAsset: PlatformArtwork.fromPayload(row),
      lyricsAsset: '',
      source: TrackSource.kugou,
      provider: '酷狗概念版',
      platformSongId: PlatformSongIdentity.fromPayload(row),
      availabilityMessage: '需要联网获取播放地址',
    );
  }
}
