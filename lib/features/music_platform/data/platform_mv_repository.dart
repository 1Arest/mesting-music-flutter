import '../../../shared/models/track.dart';
import 'music_platform_api.dart';
import 'platform_song_identity.dart';

class MusicMvQuality {
  const MusicMvQuality(this.hash, this.label);
  final String hash, label;
}

class MusicMv {
  const MusicMv({
    required this.id,
    required this.title,
    required this.qualities,
  });
  final String id, title;
  final List<MusicMvQuality> qualities;
}

/// md3Music v6.1.0's real lookup chain, using the existing embedded routes.
/// Audio hashes, album recording IDs, video IDs and video hashes stay distinct.
class PlatformMvRepository {
  const PlatformMvRepository(this.api);
  final MusicPlatformApi api;
  Future<MusicMv?> lookup(Track track) async {
    if (track.source != TrackSource.kugou) return null;
    final owner = api.session;
    var recording = track.platformSongId;
    if ((int.tryParse(recording) ?? 0) <= 0 && track.id.startsWith('kugou_')) {
      final metadata = await api.get(
        '/audio',
        query: {'hash': track.id.substring(6)},
        expectedSession: owner,
      );
      recording = PlatformSongIdentity.fromPayload(metadata);
    }
    if ((int.tryParse(recording) ?? 0) <= 0) return null;
    final response = await api.get(
      '/kmr/audio/mv',
      query: {'album_audio_id': recording, 'fields': ''},
      expectedSession: owner,
    );
    final videos = parseRecords(response);
    if (videos.isEmpty) return null;
    final video = videos.firstWhere(
      (row) => '${row['is_recommend']}' == '1',
      orElse: () => videos.first,
    );
    final id = '${video['video_id'] ?? video['id'] ?? ''}';
    final title =
        '${video['mv_name'] ?? video['video_name'] ?? video['title'] ?? track.title}';
    final qualities = parseQualities(video);
    if (id.isNotEmpty) {
      final detail = await api.get(
        '/video/detail',
        query: {'id': id},
        expectedSession: owner,
      );
      final rows = parseRecords(detail);
      if (rows.isNotEmpty) {
        final known = qualities.map((q) => q.hash.toLowerCase()).toSet();
        for (final quality in parseQualities(rows.first)) {
          if (known.add(quality.hash.toLowerCase())) qualities.add(quality);
        }
      }
    }
    if (qualities.isEmpty) return null;
    return MusicMv(
      id: id,
      title: title,
      qualities: List.unmodifiable(qualities),
    );
  }

  static List<Map<String, dynamic>> parseRecords(
    Map<String, dynamic> response,
  ) {
    final data = response['data'];
    if (data is List) {
      final rows = data.isNotEmpty && data.first is List
          ? data.first as List
          : data;
      return rows
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    }
    if (data is Map) return [Map<String, dynamic>.from(data)];
    return const [];
  }

  static List<MusicMvQuality> parseQualities(Map<String, dynamic> row) {
    final result = <MusicMvQuality>[], known = <String>{};
    void add(Object? value, String label) {
      final hash = '${value ?? ''}'.trim();
      if (hash.isNotEmpty && known.add(hash.toLowerCase())) {
        result.add(MusicMvQuality(hash, label));
      }
    }

    const definitions = {
      'fhd': '1080P',
      'hd': '720P',
      'qhd': '540P',
      'sd': '432P',
      'ld': '270P',
    };
    // Prefer H.264 for broad Android decoder compatibility. The user can select
    // another returned source; never manufacture a missing quality tier.
    for (final codec in ['h264', 'h265', 'mkv']) {
      final data = row[codec];
      if (data is! Map) continue;
      for (final entry in definitions.entries) {
        add(
          data['${entry.key}_hash'],
          '${entry.value} · ${codec == 'h264'
              ? 'H.264'
              : codec == 'h265'
              ? 'H.265'
              : 'MKV'}',
        );
      }
    }
    for (final entry in definitions.entries) {
      add(row['${entry.key}_hash'], entry.value);
    }
    add(row['hash'], '默认');
    return result;
  }

  Future<List<Uri>> urls(MusicMvQuality quality) async {
    final response = await api.get(
      '/video/url',
      query: {'hash': quality.hash},
      expectedSession: api.session,
    );
    return parseUrls(response, quality.hash);
  }

  static List<Uri> parseUrls(Map<String, dynamic> response, String hash) {
    final data = response['data'];
    if (data is! Map) return const [];
    Map? record;
    for (final entry in data.entries) {
      if ('${entry.key}'.toLowerCase() == hash.toLowerCase() &&
          entry.value is Map) {
        record = entry.value as Map;
        break;
      }
    }
    if (record == null &&
        (data.containsKey('downurl') || data.containsKey('url'))) {
      record = data;
    }
    if (record == null) return const [];
    final result = <Uri>[], known = <String>{};
    for (final key in ['downurl', 'backupdownurl', 'url', 'play_url']) {
      final raw = record[key];
      for (final value in raw is List ? raw : [raw]) {
        final uri = Uri.tryParse('${value ?? ''}');
        if (uri == null ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment) {
          continue;
        }
        final host = uri.host.toLowerCase();
        final allowedHttp =
            host == 'kugou.com' ||
            host.endsWith('.kugou.com') ||
            host == 'stream.tencentmusic.com' ||
            host.endsWith('.stream.tencentmusic.com');
        if (uri.scheme != 'https' && !(uri.scheme == 'http' && allowedHttp)) {
          continue;
        }
        if (known.add(uri.toString())) result.add(uri);
      }
    }
    return result;
  }
}
