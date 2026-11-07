/// Upgrade known public artwork CDNs without changing local assets or private
/// hosts. Android blocks cleartext CDN URLs returned by older playlist DTOs.
String normalizeArtworkUri(String value) {
  var text = value.trim();
  if (text.startsWith('//')) text = 'https:$text';
  final uri = Uri.tryParse(text);
  // The official effects CDN currently serves valid PNGs over HTTP but its
  // HTTPS certificate does not match this hostname. Preserve that exact public
  // host's supplied scheme; never bypass TLS verification or rewrite it to a
  // different guessed asset. Android already permits Kugou's media domains.
  if (uri?.scheme == 'http' && uri!.host == 'mobileservice.bssdl.kugou.com') {
    return text;
  }
  if (uri?.scheme == 'http' &&
      (uri!.host.endsWith('.music.126.net') ||
          uri.host.endsWith('.music.163.com') ||
          uri.host.endsWith('.kugou.com') ||
          uri.host == 'imge.kugou.com')) {
    return uri.replace(scheme: 'https').toString();
  }
  return text;
}

/// An empty primary DTO field must not hide a valid fallback image URL.
String firstArtworkUri(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) {
      final normalized = normalizeArtworkUri(value);
      final uri = Uri.tryParse(normalized);
      // A filename/id in a primary DTO field must not mask the later CDN URL.
      if (uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty) {
        return normalized;
      }
    }
  }
  return '';
}

/// The public NetEase artwork CDN rejects Dart's default HTTP User-Agent with
/// 403 on some image hosts. Identify this client consistently for disk-cache
/// and direct image requests (which must replace, not append, this header);
/// never attach account credentials to artwork.
/// Other hosts retain their own HTTP/signature behavior.
Map<String, String>? artworkRequestHeaders(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.host.endsWith('.music.126.net')) return null;
  return const {'User-Agent': 'MestingMusic/1.0 (Artwork)'};
}

/// NetEase returns original photos (sometimes >10 MB) even for a 64px row.
/// Request the CDN thumbnail before disk validation/decode, rather than merely
/// decoding a full download at a smaller size. Other CDNs/signatures are intact.
String sizedArtworkUri(String value, {int width = 768, int height = 768}) {
  final normalized = normalizeArtworkUri(value);
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.host.endsWith('.music.126.net')) return normalized;
  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'param': '${width.clamp(32, 1024)}y${height.clamp(32, 1024)}',
        },
      )
      .toString();
}

String artworkContentIdentity(String source) {
  try {
    final uri = Uri.tryParse(normalizeArtworkUri(source));
    if (uri == null) return source;
    var path = uri.path.replaceAll('{size}', ':size');
    if (uri.host.contains('kgimg.com') || uri.host.endsWith('.kugou.com')) {
      path = path.replaceAllMapped(RegExp(r'/(?:\d{2,4}|\{size\})/'), (m) {
        final number = int.tryParse(m[0]!.replaceAll('/', ''));
        return number != null && number > 2048 ? m[0]! : '/:size/';
      });
    }
    const volatile = {
      'param',
      'width',
      'height',
      'size',
      'w',
      'h',
      'sign',
      'signature',
      'token',
      'expires',
      'expire',
      'e',
      'timestamp',
      'auth_key',
    };
    final publicCdn =
        uri.host.endsWith('.music.126.net') ||
        uri.host.endsWith('.kgimg.com') ||
        uri.host == 'imge.kugou.com';
    final keys =
        uri.queryParameters.keys
            .where(
              (k) =>
                  !volatile.contains(k.toLowerCase()) ||
                  !publicCdn &&
                      !{
                        'param',
                        'width',
                        'height',
                        'size',
                        'w',
                        'h',
                      }.contains(k.toLowerCase()),
            )
            .toList()
          ..sort();
    // Public NetEase p1/p2/... image shards serve the same immutable picture
    // path. Search and song-detail responses may choose different shards.
    final host = RegExp(r'^p[0-9]+\.music\.126\.net$').hasMatch(uri.host)
        ? 'artwork.music.126.net'
        : uri.host;
    return '$host$path?${Uri(queryParameters: {for (final k in keys) k: uri.queryParameters[k]!}).query}';
  } on FormatException {
    return source;
  }
}
