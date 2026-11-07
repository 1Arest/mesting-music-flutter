import 'package:flutter/foundation.dart';

@immutable
class AppVersionInfo {
  const AppVersionInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
  });

  final String packageName;
  final String versionName;
  final int versionCode;

  String get displayLabel => versionName;
}

@immutable
class AppUpdateManifest {
  const AppUpdateManifest({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minimumVersionCode,
    required this.mandatory,
    required this.title,
    required this.releaseNotes,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.publishedAt,
    this.apkBackupUrl,
    this.downloadEtag,
  });

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    final packageName = _requiredString(json, 'packageName', maxLength: 160);
    final versionName = _requiredString(json, 'versionName', maxLength: 40);
    final versionCode = _requiredInt(json, 'versionCode', minimum: 1);
    final minimumVersionCode = _optionalInt(
      json,
      'minimumVersionCode',
      fallback: 1,
      minimum: 1,
    );
    final title = _requiredString(json, 'title', maxLength: 80);
    final apkUrlText = _requiredString(json, 'apkUrl', maxLength: 2048);
    final apkUrl = Uri.tryParse(apkUrlText);
    if (apkUrl == null || apkUrl.scheme != 'https' || apkUrl.host.isEmpty) {
      throw const FormatException('apkUrl 必须是有效的 HTTPS 地址');
    }
    final digest = _requiredString(json, 'sha256', maxLength: 64).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('sha256 格式无效');
    }
    final sizeBytes = _requiredInt(json, 'sizeBytes', minimum: 1);
    final rawNotes = json['releaseNotes'];
    final releaseNotes = rawNotes is List
        ? rawNotes
              .whereType<String>()
              .map((note) => note.trim())
              .where((note) => note.isNotEmpty)
              .take(12)
              .toList(growable: false)
        : const <String>[];
    if (releaseNotes.isEmpty) {
      throw const FormatException('releaseNotes 不能为空');
    }
    final publishedText = _requiredString(json, 'publishedAt', maxLength: 80);
    final publishedAt = DateTime.tryParse(publishedText);
    if (publishedAt == null) {
      throw const FormatException('publishedAt 格式无效');
    }
    return AppUpdateManifest(
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      minimumVersionCode: minimumVersionCode,
      mandatory: json['mandatory'] == true,
      title: title,
      releaseNotes: releaseNotes,
      apkUrl: apkUrl,
      sha256: digest,
      sizeBytes: sizeBytes,
      publishedAt: publishedAt.toUtc(),
    );
  }

  final String packageName;
  final String versionName;
  final int versionCode;
  final int minimumVersionCode;
  final bool mandatory;
  final String title;
  final List<String> releaseNotes;
  final Uri apkUrl;
  final String sha256;
  final int sizeBytes;
  final DateTime publishedAt;

  /// Optional file-identical HTTPS mirror and Range identity from one release
  /// snapshot. The downloader must not combine metadata from different checks.
  final Uri? apkBackupUrl;
  final String? downloadEtag;

  bool isNewerThan(AppVersionInfo current) =>
      packageName == current.packageName && versionCode > current.versionCode;

  bool isMandatoryFor(AppVersionInfo current) =>
      mandatory || current.versionCode < minimumVersionCode;

  String get sizeLabel {
    final mebibytes = sizeBytes / (1024 * 1024);
    return '${mebibytes.toStringAsFixed(mebibytes >= 100 ? 0 : 1)} MB';
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.manifest,
  });

  final AppVersionInfo currentVersion;
  final AppUpdateManifest manifest;

  bool get updateAvailable => manifest.isNewerThan(currentVersion);
  bool get mandatory => manifest.isMandatoryFor(currentVersion);
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message, {this.code = 'update_failed'});

  final String message;
  final String code;

  @override
  String toString() => message;
}

String _requiredString(
  Map<String, Object?> json,
  String key, {
  required int maxLength,
}) {
  final value = json[key];
  if (value is! String) throw FormatException('$key 缺失');
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > maxLength) {
    throw FormatException('$key 格式无效');
  }
  return normalized;
}

int _requiredInt(
  Map<String, Object?> json,
  String key, {
  required int minimum,
}) {
  final value = json[key];
  if (value is! int || value < minimum) {
    throw FormatException('$key 格式无效');
  }
  return value;
}

int _optionalInt(
  Map<String, Object?> json,
  String key, {
  required int fallback,
  required int minimum,
}) {
  if (!json.containsKey(key)) return fallback;
  return _requiredInt(json, key, minimum: minimum);
}
