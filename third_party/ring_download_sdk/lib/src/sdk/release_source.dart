import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/services/app_upgrade_p2p_protocol.dart';
import 'models.dart';

/// Internal transport seam; hosts supply config.resolveRelease for business APIs.
abstract interface class RingReleaseSource {
  Future<RingDownloadRequest> resolve(String appId);
  void dispose();
}

/// Public hosted-service discovery. No host authentication clients are reused.
/// Each lookup is fresh, bounded and validated as one immutable artifact.
class HostedRingReleaseSource implements RingReleaseSource {
  HostedRingReleaseSource({Dio? http})
    : _http =
          http ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
            ),
          );

  static const _maxBody = 64 * 1024;
  final Dio _http;
  final _pending = <CancelToken>{};
  bool _disposed = false;

  @override
  Future<RingDownloadRequest> resolve(String appId) async {
    RingDownloadConfig(appId: appId).validate();
    if (_disposed) {
      throw const RingDownloadException(RingDownloadError.disposed);
    }
    final token = CancelToken();
    _pending.add(token);
    final deadline = Timer(
      const Duration(seconds: 9),
      () => token.cancel('metadata_timeout'),
    );
    try {
      final response = await _http.get<ResponseBody>(
        'https://download.csnas.asia/api/app/$appId/health',
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache, no-store',
          },
        ),
      );
      // Always consume/cancel the stream, including HTTP errors. A capped body
      // prevents a broken endpoint from buffering an APK as JSON metadata.
      final bytes = BytesBuilder(copy: false);
      final body = response.data;
      if (body == null) {
        throw const RingDownloadException(RingDownloadError.invalidMetadata);
      }
      await for (final chunk in body.stream.timeout(
        const Duration(seconds: 5),
      )) {
        if (bytes.length + chunk.length > _maxBody) {
          throw const RingDownloadException(RingDownloadError.invalidMetadata);
        }
        bytes.add(chunk);
      }
      if (response.statusCode == 404) {
        throw const RingDownloadException(RingDownloadError.releaseUnavailable);
      }
      if (response.statusCode == 429) {
        throw const RingDownloadException(RingDownloadError.rateLimited);
      }
      if (response.statusCode != 200) {
        throw const RingDownloadException(RingDownloadError.network);
      }
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is! Map<String, dynamic>) {
        throw const RingDownloadException(RingDownloadError.invalidMetadata);
      }
      return parseHostedRelease(decoded, appId);
    } catch (error) {
      if (_disposed) {
        throw const RingDownloadException(RingDownloadError.disposed);
      }
      if (error is RingDownloadException) rethrow;
      throw RingDownloadException(
        error is DioException || error is TimeoutException
            ? RingDownloadError.network
            : RingDownloadError.invalidMetadata,
      );
    } finally {
      deadline.cancel();
      token.cancel('metadata_finished');
      _pending.remove(token);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final token in _pending) {
      token.cancel('sdk_disposed');
    }
    _http.close(force: true);
  }
}

/// Only the service's own application download routes are accepted here.
/// Direct CDN and authenticated business selection remain available through
/// download(request) or config.resolveRelease, never inferred from arbitrary JSON.
RingDownloadRequest parseHostedRelease(
  Map<String, dynamic> data,
  String appId,
) {
  Never invalid() =>
      throw const RingDownloadException(RingDownloadError.invalidMetadata);
  String text(String key) =>
      data[key] is String ? (data[key] as String).trim() : '';
  Uri? downloadUrl(String key) {
    final raw = text(key);
    return AppUpgradeP2PManifest.originForDownload(raw, appId) == null
        ? null
        : Uri.parse(raw);
  }

  final size = data['file_size'];
  final version = text('version');
  final sha = text('sha256').toLowerCase();
  final etag = text('etag');
  final primary =
      downloadUrl('primary_url') ?? downloadUrl('canonical_download_url');
  if (data['status'] != 'ok' ||
      data['app_slug'] != appId ||
      size is! int ||
      size <= 0 ||
      size > 1024 * 1024 * 1024 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.+_-]{0,39}$').hasMatch(version) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
      text('filename').isEmpty ||
      primary == null ||
      etag.length > 256 ||
      etag.contains('\r') ||
      etag.contains('\n')) {
    invalid();
  }
  int? build;
  try {
    build = AppUpgradeP2PManifest.readAndroidVersionCode(data);
    // Major/long values without a base build are malformed, not legacy absence.
    if (data['android_version_code'] == null &&
        (data['android_version_code_major'] != null ||
            data['android_long_version_code'] != null)) {
      invalid();
    }
  } on AppUpgradeP2PFailure {
    invalid();
  }
  final backup = downloadUrl('backup_url');
  if (text('backup_url').isNotEmpty && backup == null) invalid();
  final request = RingDownloadRequest(
    releaseId: 'hosted:$sha',
    version: version,
    url: primary,
    backupUrl: backup,
    fileSize: size,
    sha256: sha,
    androidVersionCode: build,
    etag: etag,
  );
  request.validate(appId: appId);
  return request;
}
