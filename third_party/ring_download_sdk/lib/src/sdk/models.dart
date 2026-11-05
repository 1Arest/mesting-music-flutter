import 'dart:io';
import '../core/services/app_upgrade_file_io.dart';

enum RingDownloadState {
  queued,
  transferring,
  verifying,
  completed,
  cancelled,
  failed,
}

enum RingDownloadError {
  invalidRequest,
  busy,
  disposed,
  cancelled,
  integrity,
  storage,
  network,
  internal,
  releaseUnavailable,
  invalidMetadata,
  rateLimited,
}

/// Stable, non-sensitive error surface. Transport exceptions and signed URLs
/// never cross this boundary or appear in toString().
class RingDownloadException implements Exception {
  const RingDownloadException(this.code);
  final RingDownloadError code;
  @override
  String toString() => 'RingDownloadException(${code.name})';
}

/// The application decides whether an update is eligible. This SDK only
/// Hosted downloads require an immutable artifact. External HTTPS downloads
/// accept the metadata the business API actually supplies, including URL only.
class RingDownloadRequest {
  const RingDownloadRequest({
    this.releaseId = '',
    this.version = '',
    required this.url,
    this.fileSize = 0,
    this.sha256 = '',
    this.androidVersionCode,
    this.backupUrl,
    this.etag = '',
  });

  final String releaseId, version, sha256, etag;
  final Uri url;
  final Uri? backupUrl;
  final int fileSize;
  final int? androidVersionCode;

  static const hostedHosts = {'download.csnas.asia', 'download1.csnas.asia'};
  static const maxFileSize = 1024 * 1024 * 1024;

  /// Routing follows the actual URL, never a stale downloadProtocol field.
  bool get usesHostedService => hostedHosts.contains(url.host.toLowerCase());
  bool get hasExpectedSha256 => sha256.trim().isNotEmpty;

  /// Adapt LifeRing's existing /v1/app-upgrades response after the host has
  /// checked hasUpdate and account eligibility. This performs no network I/O.
  factory RingDownloadRequest.fromLifeRing(Map<String, dynamic> data) {
    final size = data['fileSize'];
    final build = data['downloadVersionCode'];
    if ((size != null && (size is! int || size < 0)) ||
        (build != null && (build is! int || build <= 0))) {
      throw const RingDownloadException(RingDownloadError.invalidRequest);
    }
    final url = Uri.tryParse('${data['downloadUrl'] ?? ''}');
    final rawBackup = '${data['downloadBackupUrl'] ?? ''}'.trim();
    final backup = rawBackup.isEmpty ? null : Uri.tryParse(rawBackup);
    if (url == null || (rawBackup.isNotEmpty && backup == null)) {
      throw const RingDownloadException(RingDownloadError.invalidRequest);
    }
    final request = RingDownloadRequest(
      releaseId: '${data['releaseId'] ?? ''}',
      version: '${data['versionName'] ?? ''}',
      url: url,
      // A COS selection must not inherit a stale hosted backup dependency.
      backupUrl:
          !hostedHosts.contains(url.host.toLowerCase()) &&
              backup != null &&
              hostedHosts.contains(backup.host.toLowerCase())
          ? null
          : backup,
      fileSize: size as int? ?? 0,
      sha256: '${data['sha256'] ?? ''}',
      etag: '${data['downloadEtag'] ?? ''}',
      // Business versionCode is an update threshold, not proof of APK build.
      androidVersionCode: build as int?,
    );
    request.validate();
    return request;
  }

  void validate({String? appId}) {
    bool secure(Uri uri) =>
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty;
    bool matchesApplication(Uri uri) =>
        appId == null ||
        !hostedHosts.contains(uri.host.toLowerCase()) ||
        uri.path == '/$appId/download';
    if (!matchesApplication(url) ||
        (backupUrl != null && !matchesApplication(backupUrl!)) ||
        releaseId.length > 128 ||
        version.length > 40 ||
        fileSize < 0 ||
        fileSize > maxFileSize ||
        (hasExpectedSha256 &&
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256.trim())) ||
        (usesHostedService &&
            (releaseId.isEmpty ||
                version.isEmpty ||
                fileSize == 0 ||
                !hasExpectedSha256)) ||
        !secure(url) ||
        (backupUrl != null && !secure(backupUrl!)) ||
        (androidVersionCode != null && androidVersionCode! <= 0)) {
      throw const RingDownloadException(RingDownloadError.invalidRequest);
    }
  }
}

class RingDownloadConfig {
  const RingDownloadConfig({
    required this.appId,
    this.enableP2P = true,
    this.enableP8P = false,
    this.allowSharing = false,
    this.observeLifecycle = true,
    this.storageDirectory,
    this.refreshRelease,
    this.resolveRelease,
    this.onDiagnostic,
  });

  /// Public service application slug, never an administrator credential.
  final String appId;
  final bool enableP2P, allowSharing, observeLifecycle;

  /// Experimental additive P8P capabilities. Both remote capability and sender
  /// acknowledgement are required; old peers keep their original behavior.
  final bool enableP8P;
  final Directory? storageDirectory;
  final Future<RingDownloadRequest?> Function(RingDownloadRequest current)?
  refreshRelease;

  /// Optional business-owned metadata lookup. Account/gray-rollout decisions
  /// stay in the host; its HTTP credentials never enter SDK transports.
  final Future<RingDownloadRequest> Function(String appId)? resolveRelease;

  /// Closed-schema transport telemetry. Throwing observers cannot fail a task.
  final void Function(RingDownloadDiagnostic event)? onDiagnostic;

  void validate() {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(appId)) {
      throw const RingDownloadException(RingDownloadError.invalidRequest);
    }
  }
}

class RingDownloadProgress {
  const RingDownloadProgress(this.state, this.receivedBytes, this.totalBytes);
  final RingDownloadState state;
  final int receivedBytes, totalBytes;

  /// Zero means indeterminate; receivedBytes still reports real bytes.
  bool get hasKnownTotal => totalBytes > 0;
  double get fraction => totalBytes == 0 ? 0 : receivedBytes / totalBytes;
}

enum RingDownloadVerification { sha256, sizeOnly, transportOnly }

/// A receipt for the verified file at task completion, not a permanent promise
/// about a mutable path. Installers must recheck size/hash before installation.
class RingDownloadResult {
  const RingDownloadResult({
    required this.file,
    required this.sha256,
    required this.fileSize,
    required this.elapsed,
    this.verification = RingDownloadVerification.transportOnly,
  });
  final File file;
  final String sha256;
  final int fileSize;
  final Duration elapsed;

  /// sha256/fileSize always describe the local receipt. Only sha256 verification
  /// proves a match against a digest supplied independently by the business API.
  final RingDownloadVerification verification;

  /// Recheck immediately before a host-owned installer consumes the file.
  Future<void> revalidate() async {
    try {
      if (await file.length() != fileSize ||
          await appUpgradeFileSha256(file.path) != sha256) {
        throw const RingDownloadException(RingDownloadError.integrity);
      }
    } on FileSystemException {
      throw const RingDownloadException(RingDownloadError.storage);
    }
  }
}

/// Capability snapshot only; it does not assert that NAT traversal will succeed.
class RingSdkStatus {
  const RingSdkStatus({
    required this.appId,
    required this.platform,
    required this.networkType,
    required this.p2pEnabled,
    required this.sharingOptIn,
  });
  static const sdkVersion = '1.1.2';
  final String appId, platform, networkType;
  final bool p2pEnabled, sharingOptIn;
  Map<String, Object?> toJson() => {
    'sdkVersion': sdkVersion,
    'appId': appId,
    'platform': platform,
    'networkType': networkType,
    'p2pEnabled': p2pEnabled,
    'sharingOptIn': sharingOptIn,
  };
}

/// No URLs, headers, session IDs, SDP or ICE addresses cross this interface.
class RingDownloadDiagnostic {
  const RingDownloadDiagnostic({
    required this.stage,
    required this.code,
    this.httpStatus,
    this.verified,
    this.peerBytes,
    this.seedBytes,
    this.elapsedMs,
    this.source,
  });
  final String stage, code;
  final int? httpStatus, peerBytes, seedBytes, elapsedMs;
  final bool? verified;
  final String? source;
  Map<String, Object?> toJson() => {
    'stage': stage,
    'code': code,
    if (httpStatus != null) 'httpStatus': httpStatus,
    if (verified != null) 'verified': verified,
    if (peerBytes != null) 'peerBytes': peerBytes,
    if (seedBytes != null) 'seedBytes': seedBytes,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
    if (source != null) 'source': source,
  };
}
