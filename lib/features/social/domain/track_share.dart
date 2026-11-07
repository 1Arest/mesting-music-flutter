import 'dart:convert';

import '../../../shared/models/track.dart';

const trackShareUriPrefix = 'mesting-track://';

String encodeTrackShareMessage(Track track) {
  final payload = <String, Object?>{
    'v': 1,
    'i': track.id,
    't': track.title,
    'r': track.artist,
    'a': track.album,
    'd': track.duration.inMilliseconds,
    'u': track.audioAsset,
    'c': track.coverAsset,
    'l': track.resolvedLyricsAsset,
    's': track.source.name,
    'p': track.provider,
    'q': track.isPreview,
    'e': track.externalUrl,
    'm': track.availabilityMessage,
  };
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return '🎵 分享歌曲：《${track.title}》 · ${track.artist} '
      '$trackShareUriPrefix$encoded';
}

Track? decodeTrackShareMessage(String message) {
  final markerIndex = message.indexOf(trackShareUriPrefix);
  if (markerIndex < 0) return null;
  final encoded = message
      .substring(markerIndex + trackShareUriPrefix.length)
      .trim()
      .split(RegExp(r'\s'))
      .first;
  if (encoded.isEmpty) return null;

  try {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
    );
    if (decoded is! Map) return null;
    final payload = Map<String, Object?>.from(decoded);
    final id = payload['i']?.toString().trim() ?? '';
    final title = payload['t']?.toString().trim() ?? '';
    final artist = payload['r']?.toString().trim() ?? '';
    if (id.isEmpty || title.isEmpty || artist.isEmpty) return null;
    return Track(
      id: id,
      title: title,
      artist: artist,
      album: payload['a']?.toString() ?? '',
      duration: Duration(milliseconds: (payload['d'] as num?)?.toInt() ?? 0),
      audioAsset: payload['u']?.toString() ?? '',
      coverAsset: payload['c']?.toString() ?? '',
      lyricsAsset: payload['l']?.toString() ?? '',
      source: TrackSource.values.firstWhere(
        (source) => source.name == payload['s'],
        orElse: () => TrackSource.local,
      ),
      provider: payload['p']?.toString() ?? '本地',
      isPreview: payload['q'] == true,
      externalUrl: payload['e']?.toString() ?? '',
      availabilityMessage: payload['m']?.toString() ?? '',
    );
  } on Object {
    return null;
  }
}

String? trackShareRemoteUrl(String value) {
  final normalized = value.trim();
  if (normalized.startsWith('cloud://')) return normalized;
  final uri = Uri.tryParse(normalized);
  return uri?.scheme == 'https' ? normalized : null;
}
