import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/app_update_models.dart';
import 'app_update_repository.dart';

class JavaMysqlTestChannelRepository {
  JavaMysqlTestChannelRepository({
    required http.Client client,
    required AppUpdateRepository downloader,
    Uri? manifestUrl,
  }) : _client = client,
       _downloader = downloader,
       _manifestUrl = manifestUrl ?? Uri.parse(defaultManifestUrl);

  static const packageName = 'com.mesting.music.javatest';
  static const defaultManifestUrl = String.fromEnvironment(
    'JAVA_MYSQL_TEST_MANIFEST_URL',
    defaultValue:
        'https://mesting-d5gm7tuhxacddccfb-1331507389.tcloudbaseapp.com/releases/android/java-mysql-test/latest.json',
  );
  static const _maxManifestBytes = 1024 * 1024;
  static const _maxApkBytes = 350 * 1024 * 1024;

  final http.Client _client;
  final AppUpdateRepository _downloader;
  final Uri _manifestUrl;

  Future<AppUpdateManifest> fetchManifest() async {
    try {
      final requestUrl = _manifestUrl.replace(
        queryParameters: {
          ..._manifestUrl.queryParameters,
          't': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      final response = await _client
          .get(requestUrl, headers: const {'accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 404) {
        throw const AppUpdateException('Java + MySQL 测试通道暂未开放');
      }
      if (response.statusCode != 200) {
        throw AppUpdateException('测试通道暂时不可用（${response.statusCode}）');
      }
      if (response.bodyBytes.length > _maxManifestBytes) {
        throw const AppUpdateException('测试通道清单大小异常');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('测试通道清单不是 JSON 对象');
      }
      final manifest = AppUpdateManifest.fromJson(decoded);
      if (manifest.packageName != packageName) {
        throw const AppUpdateException('测试安装包标识无效');
      }
      if (manifest.sizeBytes > _maxApkBytes) {
        throw const AppUpdateException('测试安装包大小异常');
      }
      return manifest;
    } on AppUpdateException {
      rethrow;
    } on FormatException {
      throw const AppUpdateException('测试通道清单格式无效');
    } on Object {
      throw const AppUpdateException('无法连接 Java + MySQL 测试通道');
    }
  }

  Future<String> download(
    AppUpdateManifest manifest, {
    required UpdateDownloadProgress onProgress,
  }) {
    return _downloader.download(manifest, onProgress: onProgress);
  }
}
