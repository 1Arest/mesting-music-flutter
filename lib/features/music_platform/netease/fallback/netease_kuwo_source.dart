// SPDX-License-Identifier: LGPL-3.0-only
// Native adaptation of the pinned upstream kuwo provider. See the corresponding
// source, license and modifications in third_party/unblock_netease/.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../shared/models/track.dart';
import 'netease_fallback_source.dart';
import 'netease_source_transport.dart';

/// The desktop HTML search page is not an anonymous API: it currently returns
/// HTTP 500 and no CSRF token. Use the upstream's anonymous mobile search
/// contract directly instead of treating a missing HTML cookie as zero songs.
class KuwoPublicSource implements NeteaseFallbackSource {
  KuwoPublicSource(this.client);
  final http.Client client;
  static const _headers = {'User-Agent': 'okhttp/3.10.0'};
  @override
  String get label => '酷我公开音源';

  @override
  Future<List<Track>> search(Track original) async {
    final response = await client.get(
      Uri.https('search.kuwo.cn', '/r.s', {
        'correct': '1',
        'vipver': '1',
        'stype': 'comprehensive',
        'encoding': 'utf8',
        'rformat': 'json',
        'mobi': '1',
        'show_copyright_off': '1',
        'searchapi': '6',
        'all': '${original.title} ${original.artist}',
      }),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw NeteaseSourceFailure(
        'search_http_error',
        httpStatus: response.statusCode,
      );
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map || data['content'] is! List) {
      throw const NeteaseSourceFailure('search_response_invalid');
    }
    final songs = <Track>[];
    for (final section in (data['content'] as List).whereType<Map>()) {
      final page = section['musicpage'];
      final rows = page is Map ? page['abslist'] : null;
      if (rows is! List) continue;
      for (final row in rows.whereType<Map>().take(20)) {
        final id = '${row['MUSICRID'] ?? ''}'.replaceFirst('MUSIC_', '');
        if (!RegExp(r'^\d+$').hasMatch(id)) continue;
        songs.add(
          Track(
            id: 'kuwo_$id',
            title: '${row['SONGNAME'] ?? ''}',
            artist: '${row['ARTIST'] ?? ''}',
            album: '${row['ALBUM'] ?? ''}',
            duration: Duration(
              milliseconds: ((num.tryParse('${row['DURATION']}') ?? 0) * 1000)
                  .round(),
            ),
            audioAsset: id,
            coverAsset: '',
            lyricsAsset: '',
            source: TrackSource.netease,
          ),
        );
      }
    }
    return songs;
  }

  @override
  Future<Track?> resolve(Track candidate) async {
    if (!RegExp(r'^\d+$').hasMatch(candidate.audioAsset)) return null;
    final response = await client.get(
      Uri.https('antiserver.kuwo.cn', '/anti.s', {
        'type': 'convert_url',
        'format': 'mp3',
        'response': 'url',
        'rid': 'MUSIC_${candidate.audioAsset}',
      }),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw NeteaseSourceFailure(
        'resolve_http_error',
        httpStatus: response.statusCode,
      );
    }
    final text = utf8.decode(response.bodyBytes).trim();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        !uri.host.endsWith('.kuwo.cn')) {
      return null;
    }
    // This endpoint only returns an address. It does not confirm bitrate or
    // lossless, so do not inherit the previously requested quality/bitrate.
    return candidate.copyWith(
      audioAsset: uri.replace(scheme: 'https').toString(),
      audioHeaders: const {},
      audioBitrate: 0,
      playbackQuality: '',
      isPreview: false,
    );
  }
}
