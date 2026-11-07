import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/app_update_models.dart';
import '../domain/release_history.dart';
import 'public_apk_release_notes.dart';

/// Release discovery is independent of download state and Android installation.
abstract interface class AppUpdateReleaseSource {
  Future<AppUpdateManifest> latest();
}

/// Public Ring Download metadata only. No administrator account, publishing
/// credential, user login or P2P SDK belongs in this read-only client.
class CsnasUpdateReleaseSource implements AppUpdateReleaseSource {
  CsnasUpdateReleaseSource({required this.client, required this.packageName});
  final http.Client client;
  final String packageName;
  static final healthUrl = Uri.parse(
    'https://download.csnas.asia/api/app/music/health',
  );

  static bool isDownloadUrl(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      const {
        'download.csnas.asia',
        'download1.csnas.asia',
      }.contains(uri.host) &&
      uri.path == '/music/download';

  @override
  Future<AppUpdateManifest> latest() async {
    try {
      final response = await client
          .get(
            healthUrl.replace(
              queryParameters: {
                't': '${DateTime.now().millisecondsSinceEpoch}',
              },
            ),
            headers: const {
              'accept': 'application/json',
              'cache-control': 'no-cache, no-store',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw AppUpdateException(
          '更新服务暂时不可用（${response.statusCode}）',
          code: 'manifest_http',
        );
      }
      if (response.bodyBytes.length > 1024 * 1024) {
        throw const FormatException();
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> ||
          data['status'] != 'ok' ||
          data['app_slug'] != 'music') {
        throw const FormatException();
      }
      final code = data['android_version_code'];
      final size = data['file_size'];
      final name = data['version'];
      final hash = data['sha256'];
      final primary = Uri.tryParse(
        '${data['primary_url'] ?? data['canonical_download_url'] ?? ''}',
      );
      final backupText = data['backup_url'];
      final backup = backupText is String && backupText.isNotEmpty
          ? Uri.tryParse(backupText)
          : null;
      if (code is! int ||
          code <= 0 ||
          size is! int ||
          size <= 0 ||
          size > 350 * 1024 * 1024 ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 40 ||
          hash is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
          primary == null ||
          !isDownloadUrl(primary) ||
          (backupText is String &&
              backupText.isNotEmpty &&
              (backup == null || !isDownloadUrl(backup)))) {
        throw const FormatException();
      }
      final etag = data['etag'];
      if (etag != null &&
          (etag is! String ||
              etag.length > 512 ||
              etag.contains(RegExp(r'[\r\n]')))) {
        throw const FormatException();
      }
      // Version labels may be renamed for public releases (1.0.0 versus the
      // historical Beta label). Ordering always uses the APK's real build code.
      final manifest = AppUpdateManifest(
        packageName: packageName,
        versionName: name.trim(),
        versionCode: code,
        minimumVersionCode: 1,
        mandatory: false,
        title: '发现新版本',
        releaseNotes: const [],
        apkUrl: primary,
        apkBackupUrl: backup,
        downloadEtag: etag as String?,
        sha256: hash.toLowerCase(),
        sizeBytes: size,
        publishedAt:
            DateTime.tryParse('${data['release_created_at'] ?? ''}')?.toUtc() ??
            DateTime.now().toUtc(),
      );
      // Prefer publisher metadata, then the target APK's version-bound asset.
      // Bundled history remains an offline fallback for exact known releases.
      var notes = PublicApkReleaseNotes.parse(
        data['releaseNotes'] ?? data['release_notes'],
      );
      final bundled = notesForMusicVersion(name);
      if (notes.isEmpty && bundled.isNotEmpty) notes = bundled;
      if (notes.isEmpty) {
        notes = await PublicApkReleaseNotes(client)
            .load(manifest)
            .timeout(const Duration(seconds: 10), onTimeout: () => const []);
      }
      return AppUpdateManifest(
        packageName: manifest.packageName,
        versionName: manifest.versionName,
        versionCode: manifest.versionCode,
        minimumVersionCode: manifest.minimumVersionCode,
        mandatory: manifest.mandatory,
        title: manifest.title,
        releaseNotes: notes,
        apkUrl: manifest.apkUrl,
        apkBackupUrl: manifest.apkBackupUrl,
        downloadEtag: manifest.downloadEtag,
        sha256: manifest.sha256,
        sizeBytes: manifest.sizeBytes,
        publishedAt: manifest.publishedAt,
      );
    } on AppUpdateException {
      rethrow;
    } on FormatException {
      throw const AppUpdateException('发布信息不完整，请稍后重试', code: 'manifest');
    } on Object {
      throw const AppUpdateException('无法连接更新服务，请检查网络', code: 'network');
    }
  }
}
