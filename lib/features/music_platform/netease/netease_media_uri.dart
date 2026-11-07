/// Older MV responses still contain cleartext URLs although the same public
/// NetEase CDN serves TLS. Upgrade only known media hosts, retaining the exact
/// path/query signature; account credentials never accompany CDN playback.
Uri? neteaseMediaUri(String value) {
  final text = value.startsWith('//') ? 'https:$value' : value.trim();
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      !{'http', 'https'}.contains(uri.scheme)) {
    return null;
  }
  if (uri.scheme == 'http' &&
      [
        '.vod.126.net',
        '.vod.163.com',
        '.music.126.net',
      ].any((suffix) => uri.host.endsWith(suffix))) {
    return uri.replace(scheme: 'https', port: 443);
  }
  return uri;
}
