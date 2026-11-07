import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../core/models/app_upgrade_models.dart';
import '../core/services/app_upgrade_p2p_diagnostics.dart';
import '../core/services/app_upgrade_v40_download_client.dart';
import '../core/services/app_upgrade_v40_p2p_client.dart';
import '../core/services/app_upgrade_upload_budget.dart';
import 'models.dart';
import 'network.dart';
import 'direct_https.dart';
import 'receive_buffer.dart';
import 'sharing_resources.dart';

/// Internal seam for meaningful SDK contract tests without WebRTC mocks leaking
/// into the public enterprise integration API.
abstract interface class RingTransferEngine {
  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) onProgress,
    CancelToken cancelToken,
  );
  void setForeground(bool foreground);
  void setSharingEnabled(bool enabled);
  Future<void> dispose();
}

/// Optional capability: installation remains host-owned. External downloads
/// produce no hosted installation telemetry and require no service connection.
abstract interface class RingInstallationEvents {
  Future<void> reconcileInstalledBuild(int build);
  Future<void> rememberInstallation(RingDownloadRequest request);
  Future<void> reportInstallationFailure(RingDownloadRequest request);
}

/// Hosts retain business authorization and the persisted artifact receipt.
/// No download or installation is initiated by this optional capability.
abstract interface class RingCachedSharing {
  Future<bool> restoreSharing(RingDownloadRequest request, File file);
  Future<void> stopSharing();
}

abstract interface class RingSharingResourceEvents {
  bool get sharingResourcesAllowed;
  Stream<bool> get sharingResourceAvailability;
}

class DefaultRingTransferEngine
    implements
        RingTransferEngine,
        RingInstallationEvents,
        RingCachedSharing,
        RingSharingResourceEvents {
  DefaultRingTransferEngine(this.config, {Dio? http}) {
    _http =
        http ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(minutes: 15),
          ),
        );
    _signal = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
      ),
    );
    _p2p = AppUpgradeV40P2PClient(
      dio: _signal,
      networkReader: RingNetwork.read,
      networkEvents: RingNetwork.events,
      isAndroid: config.enableP2P && Platform.isAndroid,
      uploadBudget: config.enableP2P && Platform.isAndroid
          ? AppUpgradeUploadBudget.mobile
          : null,
      receiveBufferFactory: config.enableP2P && Platform.isAndroid
          ? () => RingRtcReceiveBufferOwner(
              onResult: (code) {
                config.onDiagnostic?.call(
                  RingDownloadDiagnostic(stage: 'rtc', code: code),
                );
              },
            )
          : null,
      allowSharing: config.allowSharing,
      enableP8P: config.enableP8P,
      // Foreground only; heartbeat renews the server lease while Wi-Fi permits.
      sharingDuration: null,
      diagnostic: (event) {
        AppUpgradeP2PDiagnostics.record(event);
        try {
          config.onDiagnostic?.call(
            RingDownloadDiagnostic(
              stage: AppUpgradeP2PDiagnostic.safeCode(event.stage),
              code: AppUpgradeP2PDiagnostic.safeCode(event.code),
              source: event.source == null
                  ? null
                  : AppUpgradeP2PDiagnostic.safeCode(event.source!),
              httpStatus: event.status,
              verified: event.verified,
              peerBytes: event.peerBytes,
              seedBytes: event.seedBytes,
              elapsedMs: event.elapsedMs,
            ),
          );
        } catch (_) {
          // Application telemetry must never affect data transfer or cleanup.
        }
      },
      hybridStartup: true,
      fastSignaling: true,
      // Keep shared-deadline capability server-controlled, as in LifeRing.
      preferredPeerBatchPieces: 4,
    );
    _client = AppUpgradeV40DownloadClient(
      dio: _http,
      p2pClient: _p2p,
      httpsHeadStart: true,
      allowExternalHttps: true,
      supportDirectoryLoader: () async {
        final parent =
            config.storageDirectory ?? await getApplicationSupportDirectory();
        return Directory(
          path.join(parent.path, 'ring_download_sdk', config.appId),
        );
      },
    );
    if (config.enableP2P && Platform.isAndroid) {
      _p2p.setResourcesAllowed(false);
      _sharingResources = RingSharingResourcesOwner(
        onAllowedChanged: _p2p.setResourcesAllowed,
      );
      _sharingResources!.setEnabled(config.allowSharing);
    }
  }

  final RingDownloadConfig config;
  // Internal integration seam: use the real clients with controlled transports
  // to verify disposal ordering. This class is not exported by the public SDK.
  DefaultRingTransferEngine.forTesting(
    this.config, {
    required Dio http,
    required Dio signal,
    required AppUpgradeV40P2PClient p2p,
    required AppUpgradeV40DownloadClient downloadClient,
  }) {
    _http = http;
    _signal = signal;
    _p2p = p2p;
    _client = downloadClient;
  }

  Future<void>? _disposing;
  bool _disposed = false;
  RingSharingResourcesOwner? _sharingResources;
  late final Dio _http, _signal;
  late final AppUpgradeV40P2PClient _p2p;
  late final AppUpgradeV40DownloadClient _client;

  AppUpgradeInfo _metadata(RingDownloadRequest request) => AppUpgradeInfo(
    releaseId: 'ring:${config.appId}:${request.releaseId}',
    versionName: request.version,
    versionCode: request.androidVersionCode ?? 0,
    releaseNotes: '',
    forceUpdate: false,
    downloadUrl: request.url.toString(),
    fileSize: request.fileSize,
    sha256: request.sha256.toLowerCase(),
    downloadProtocol: 'APK_SERVICE_V40',
    downloadSlug: config.appId,
    downloadBackupUrl: request.backupUrl?.toString() ?? '',
    downloadEtag: request.etag,
    downloadVersionCode: request.androidVersionCode,
  );

  @override
  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) onProgress,
    CancelToken cancelToken,
  ) {
    if (_disposed) {
      return Future<File>.error(
        const RingDownloadException(RingDownloadError.disposed),
      );
    }
    if (!request.usesHostedService) {
      // External URLs never discover hosted metadata, peers, or seed sessions.
      // Their optional identity must not become a dependency on our uptime.
      _diagnostic(
        const RingDownloadDiagnostic(
          stage: 'routing',
          code: 'direct_https',
          source: 'https',
        ),
      );
      return DirectHttpsDownload(
        config,
        _http,
      ).download(request, onProgress, cancelToken);
    }
    return _client.download(
      info: _metadata(request),
      url: request.url.toString(),
      backupUrl: request.backupUrl?.toString(),
      refreshRelease: () async {
        final next = await config.refreshRelease?.call(request);
        if (next == null) return null;
        next.validate(appId: config.appId);
        // An update to another release belongs to a NEW task. Do not silently
        // switch identity under a caller's existing verification receipt.
        if (next.releaseId != request.releaseId ||
            next.sha256.toLowerCase() != request.sha256.toLowerCase() ||
            next.fileSize != request.fileSize ||
            next.version != request.version ||
            next.androidVersionCode != request.androidVersionCode) {
          return null;
        }
        return _metadata(next);
      },
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  void _diagnostic(RingDownloadDiagnostic event) {
    try {
      config.onDiagnostic?.call(event);
    } catch (_) {
      // Telemetry cannot block downloads.
    }
  }

  @override
  Future<void> reconcileInstalledBuild(int build) =>
      _client.serviceEvents.reconcileInstalledBuild(build);

  @override
  Future<void> rememberInstallation(RingDownloadRequest request) async {
    if (request.usesHostedService) {
      await _client.rememberVerifiedInstallation(_metadata(request));
    }
  }

  @override
  Future<void> reportInstallationFailure(RingDownloadRequest request) async {
    if (request.usesHostedService) {
      await _client.reportInstallationFailure(_metadata(request));
    }
  }

  @override
  void setForeground(bool foreground) {
    _client.setForeground(foreground);
    _sharingResources?.setForeground(foreground);
  }

  @override
  void setSharingEnabled(bool enabled) {
    _p2p.setSharingEnabled(enabled);
    _sharingResources?.setEnabled(enabled);
  }

  @override
  bool get sharingResourcesAllowed => _sharingResources?.allowed ?? true;
  @override
  Stream<bool> get sharingResourceAvailability =>
      _sharingResources?.changes ?? const Stream.empty();

  @override
  Future<bool> restoreSharing(RingDownloadRequest request, File file) async {
    if (_disposed || !config.enableP2P || !request.usesHostedService) {
      return false;
    }
    final resources = _sharingResources;
    if (resources != null && !await resources.ensureCurrent()) return false;
    if (_disposed) return false;
    return _p2p.restoreSharingFromCache(
      file: file,
      downloadUrl: request.url.toString(),
      expectedSlug: config.appId,
      expectedVersion: request.version,
      expectedFileSize: request.fileSize,
      expectedSha256: request.sha256.toLowerCase(),
      expectedVersionCode: request.androidVersionCode,
    );
  }

  @override
  Future<void> stopSharing() => _p2p.stopSharing();

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _p2p.setForeground(false);
    _p2p.setSharingEnabled(false);
    _sharingResources?.setForeground(false);
    await _client.cancelAndWait();
    await _p2p.close();
    await _sharingResources?.close();
    _http.close(force: true);
    _signal.close(force: true);
  }
}
