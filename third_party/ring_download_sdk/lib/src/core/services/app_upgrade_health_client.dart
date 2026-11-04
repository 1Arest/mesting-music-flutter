import 'dart:io';

import 'package:dio/dio.dart';

import '../models/app_upgrade_models.dart';
import 'app_upgrade_p2p_diagnostics.dart';
import 'app_upgrade_p2p_protocol.dart';

/// Public APK identity transport, independent of account/API authentication.
/// Health is fetched for each preparation; no previous SHA/size is a fallback.
class AppUpgradeHealthClient {
  AppUpgradeHealthClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              followRedirects: false,
            ),
          );

  static const endpoint = 'https://download.csnas.asia/api/app/lifering/health';
  static const _hosts = {'download.csnas.asia', 'download1.csnas.asia'};
  final Dio _dio;

  Future<AppUpgradeInfo> refresh(AppUpgradeInfo selected) async {
    AppUpgradeP2PDiagnostics.record(
      const AppUpgradeP2PDiagnostic(stage: 'health', code: 'request_started'),
    );
    // Do not send the App API's bearer token, identity, or session headers.
    late final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.get<Map<String, dynamic>>(
        endpoint,
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache, no-store',
          },
        ),
      );
    } on DioException catch (error) {
      AppUpgradeP2PDiagnostics.record(
        AppUpgradeP2PDiagnostic(
          stage: 'health',
          code: 'health_unavailable',
          status: error.response?.statusCode,
        ),
      );
      rethrow;
    }
    final data = response.data;
    int? artifactBuild;
    try {
      artifactBuild = data == null
          ? null
          : AppUpgradeP2PManifest.readAndroidVersionCode(data);
    } on AppUpgradeP2PFailure {
      AppUpgradeP2PDiagnostics.record(
        AppUpgradeP2PDiagnostic(
          stage: 'health',
          code: 'health_metadata_invalid',
          status: response.statusCode,
        ),
      );
      throw const HttpException('app_upgrade_health_metadata_invalid');
    }
    String field(String key) => data?[key]?.toString().trim() ?? '';
    final size = data?['file_size'];
    final sha = field('sha256').toLowerCase();
    final url =
        _downloadUrl(field('primary_url')) ??
        _downloadUrl(field('canonical_download_url'));
    if (response.statusCode != 200 ||
        field('status') != 'ok' ||
        field('app_slug') != 'lifering' ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}$',
        ).hasMatch(field('version')) ||
        field('filename').isEmpty ||
        size is! num ||
        size <= 0 ||
        size != size.toInt() ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
        field('etag').isEmpty ||
        url == null) {
      AppUpgradeP2PDiagnostics.record(
        AppUpgradeP2PDiagnostic(
          stage: 'health',
          code: 'health_metadata_invalid',
          status: response.statusCode,
        ),
      );
      throw const HttpException('app_upgrade_health_metadata_invalid');
    }
    AppUpgradeP2PDiagnostics.record(
      AppUpgradeP2PDiagnostic(
        stage: 'health',
        code: 'metadata_refreshed',
        status: response.statusCode,
        expectedBytes: selected.fileSize,
        actualBytes: size.toInt(),
      ),
    );
    // Keep server-selected release/account/build qualification intact. Only
    // artifact fields change together, avoiding a new URL with an old digest.
    return AppUpgradeInfo(
      releaseId: selected.releaseId,
      versionCode: selected.versionCode,
      downloadVersionCode: artifactBuild,
      versionName: field('version'),
      releaseNotes: selected.releaseNotes,
      forceUpdate: selected.forceUpdate,
      requiresEligibilityCheck: selected.requiresEligibilityCheck,
      audienceUserId: selected.audienceUserId,
      downloadUrl: url,
      fileSize: size.toInt(),
      sha256: sha,
      downloadEtag: field('etag'),
      downloadProtocol: 'APK_SERVICE_V40',
      downloadSlug: 'lifering',
      downloadBackupUrl: _downloadUrl(field('backup_url')) ?? '',
    );
  }

  String? _downloadUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.scheme == 'https' &&
            _hosts.contains(uri.host.toLowerCase()) &&
            uri.userInfo.isEmpty &&
            (!uri.hasPort || uri.port == 443) &&
            uri.fragment.isEmpty &&
            uri.path == '/lifering/download'
        ? uri.toString()
        : null;
  }
}
