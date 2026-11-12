/// Validate a resumed response before appending a single byte. A server that
/// ignores Range, changes its entity or returns an unrelated interval must not
/// turn two recordings into one apparently successful music file.
int resumedDownloadTotal({
  required int offset,
  required int status,
  required Map<String, String> headers,
  required String validator,
}) {
  final current = downloadValidator(headers);
  if (validator.isNotEmpty && current.isNotEmpty && current != validator) {
    throw const FormatException('下载资源已变化，请重新下载');
  }
  // Pause can arrive after the final bytes have flushed but before the source
  // closes. An authoritative 416 for that exact length means no bytes remain.
  if (status == 416 && headers['content-range'] == 'bytes */$offset') {
    return offset;
  }
  final range = RegExp(
    r'^bytes (\d+)-(\d+)/(\d+)$',
  ).firstMatch(headers['content-range'] ?? '');
  if (status != 206 || range == null || int.parse(range[1]!) != offset) {
    throw const FormatException('服务器未接受断点续传，请重新下载');
  }
  final end = int.parse(range[2]!), total = int.parse(range[3]!);
  if (end < offset || end >= total || total > 512 * 1024 * 1024) {
    throw const FormatException('续传文件范围无效，请重新下载');
  }
  return total;
}

String downloadValidator(Map<String, String> headers) {
  final etag = headers['etag'] ?? '';
  return etag.isNotEmpty && !etag.startsWith('W/')
      ? etag
      : headers['last-modified'] ?? '';
}
