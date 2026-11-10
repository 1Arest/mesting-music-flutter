import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../core/services/app_upgrade_file_io.dart';
import 'engine.dart';
import 'models.dart';
import 'network.dart';
import 'release_source.dart';

class RingDownloadTask {
  RingDownloadTask._(this.request)
    : _latest = RingDownloadProgress(
        RingDownloadState.queued,
        0,
        request.fileSize,
      ) {
    _result.future.ignore();
  }
  final RingDownloadRequest request;
  final _events = StreamController<RingDownloadProgress>.broadcast();
  final _result = Completer<RingDownloadResult>();
  final _cancel = CancelToken();
  RingDownloadProgress _latest;
  bool _terminal = false;
  Stream<RingDownloadProgress> get progress => _events.stream;
  RingDownloadProgress get latest => _latest;
  Future<RingDownloadResult> get completed => _result.future;

  /// Cancels transfer, retaining resume data. Completion waits for writer cleanup.
  void cancel() {
    if (!_terminal) _cancel.cancel('client_interrupted');
  }

  void _publish(RingDownloadState state, int received, {int? total}) {
    if (_terminal) return;
    final knownTotal = request.fileSize > 0
        ? request.fileSize
        : total ?? _latest.totalBytes;
    final displayed = max(_latest.receivedBytes, received);
    _latest = RingDownloadProgress(
      state,
      knownTotal > 0 ? displayed.clamp(0, knownTotal) : displayed,
      knownTotal,
    );
    _events.add(_latest);
  }
}

class RingDownloadSdk with WidgetsBindingObserver {
  factory RingDownloadSdk(RingDownloadConfig config) {
    config.validate();
    return RingDownloadSdk.withEngine(
      config,
      DefaultRingTransferEngine(config),
    );
  }

  @visibleForTesting
  RingDownloadSdk.withEngine(
    this.config,
    this._engine, {
    RingReleaseSource? releaseSource,
  }) : _releaseSource = releaseSource ?? HostedRingReleaseSource(),
       _sharingEnabled = config.allowSharing {
    config.validate();
    if (config.observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      final state = WidgetsBinding.instance.lifecycleState;
      // An unobserved startup state is not foreground authorization. Receiving
      // still works; sharing waits for the real resumed lifecycle callback.
      setForeground(state == AppLifecycleState.resumed);
    }
  }

  final RingDownloadConfig config;
  final RingTransferEngine _engine;
  final RingReleaseSource _releaseSource;
  bool _sharingEnabled;
  static final _busyApps = <String>{};
  RingDownloadTask? _active;
  bool _disposed = false;
  Future<void>? _disposing;

  /// Fetch an immutable current APK snapshot for this app. Does not decide
  /// account eligibility, show UI, or start an installation.
  Future<RingDownloadRequest> latestRelease() async {
    if (_disposed) {
      throw const RingDownloadException(RingDownloadError.disposed);
    }
    try {
      final resolver = config.resolveRelease;
      final request =
          await (resolver == null
                  ? _releaseSource.resolve(config.appId)
                  : resolver(config.appId))
              .timeout(const Duration(seconds: 10));
      if (_disposed) {
        throw const RingDownloadException(RingDownloadError.disposed);
      }
      request.validate(appId: config.appId);
      return request;
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
    }
  }

  /// Convenience for public applications whose policy permits the latest APK.
  /// Business-gated apps call download() with their already selected release.
  Future<RingDownloadTask> downloadLatest() async =>
      download(await latestRelease());

  /// Explicit runtime opt-in/revocation. Network/lifecycle rules still apply.
  /// Revocation closes local upload paths immediately; server cleanup is best effort.
  void setSharingEnabled(bool enabled) {
    if (_disposed) {
      throw const RingDownloadException(RingDownloadError.disposed);
    }
    _engine.setSharingEnabled(enabled);
    _sharingEnabled = enabled;
  }

  /// Restore only a host-authorized hosted artifact. The engine revalidates the
  /// actual cache and current manifest. False means no cache was admitted;
  /// true retains verified sharing intent, still gated by foreground/Wi-Fi.
  Future<bool> restoreSharing(RingDownloadRequest request, File file) async {
    if (_disposed) {
      throw const RingDownloadException(RingDownloadError.disposed);
    }
    request.validate(appId: config.appId);
    if (!_sharingEnabled ||
        !request.usesHostedService ||
        _active != null ||
        _busyApps.contains(config.appId)) {
      return false;
    }
    final engine = _engine;
    if (engine is! RingCachedSharing) return false;
    return (engine as RingCachedSharing).restoreSharing(request, file);
  }

  /// Revoke immediately and forget the retained artifact before admitting a
  /// different authorization. Receiving and its HTTP owner remain active.
  Future<void> stopSharing() async {
    if (_disposed) return;
    setSharingEnabled(false);
    final engine = _engine;
    if (engine is RingCachedSharing) {
      await (engine as RingCachedSharing).stopSharing();
    }
  }

  /// Resource/network eligibility only; it is not a registration or file receipt.
  bool get sharingResourcesAllowed {
    final engine = _engine;
    return !_disposed &&
        (engine is! RingSharingResourceEvents ||
            (engine as RingSharingResourceEvents).sharingResourcesAllowed);
  }

  Stream<bool> get sharingResourceAvailability {
    final engine = _engine;
    return engine is RingSharingResourceEvents
        ? (engine as RingSharingResourceEvents).sharingResourceAvailability
        : const Stream.empty();
  }

  RingDownloadTask download(RingDownloadRequest request) {
    if (_disposed) {
      throw const RingDownloadException(RingDownloadError.disposed);
    }
    request.validate(appId: config.appId);
    if (_active != null || !_busyApps.add(config.appId)) {
      throw const RingDownloadException(RingDownloadError.busy);
    }
    final task = _active = RingDownloadTask._(request);
    // A listener can attach before the first event and a caller can cancel
    // before any network or file operation starts.
    unawaited(Future<void>(() => _run(task)));
    return task;
  }

  Future<void> _run(RingDownloadTask task) async {
    final clock = Stopwatch()..start();
    RingDownloadResult? result;
    RingDownloadException? failure;
    try {
      if (task._cancel.isCancelled) {
        throw const RingDownloadException(RingDownloadError.cancelled);
      }
      task._publish(RingDownloadState.transferring, 0);
      final file = await _engine.download(task.request, (received, total) {
        if (task._cancel.isCancelled) return;
        task._publish(
          total > 0 && received >= total
              ? RingDownloadState.verifying
              : RingDownloadState.transferring,
          received,
          total: total,
        );
      }, task._cancel);
      if (task._cancel.isCancelled) {
        throw const RingDownloadException(RingDownloadError.cancelled);
      }
      final actualSize = await file.length();
      task._publish(RingDownloadState.verifying, actualSize, total: actualSize);
      // Public success has an independent receipt boundary. Never trust an
      // engine adapter returning an unverified/mutated file as SDK success.
      if (actualSize <= 0 ||
          actualSize > RingDownloadRequest.maxFileSize ||
          (task.request.fileSize > 0 && actualSize != task.request.fileSize)) {
        throw const RingDownloadException(RingDownloadError.integrity);
      }
      final actualSha = await appUpgradeFileSha256(
        file.path,
        cancelSignal: task._cancel.whenCancel,
      );
      if (task.request.hasExpectedSha256 &&
          actualSha != task.request.sha256.trim().toLowerCase()) {
        throw const RingDownloadException(RingDownloadError.integrity);
      }
      if (task._cancel.isCancelled) {
        throw const RingDownloadException(RingDownloadError.cancelled);
      }
      result = RingDownloadResult(
        file: file,
        sha256: actualSha,
        fileSize: actualSize,
        elapsed: clock.elapsed,
        verification: task.request.hasExpectedSha256
            ? RingDownloadVerification.sha256
            : task.request.fileSize > 0
            ? RingDownloadVerification.sizeOnly
            : RingDownloadVerification.transportOnly,
      );
      try {
        config.onDiagnostic?.call(
          RingDownloadDiagnostic(
            stage: 'complete',
            code: task.request.hasExpectedSha256
                ? 'sha256_verified'
                : task.request.fileSize > 0
                ? 'size_verified'
                : 'https_downloaded',
            verified: task.request.hasExpectedSha256 ? true : null,
          ),
        );
      } catch (_) {
        // Observers never change download results.
      }
    } catch (error) {
      failure = task._cancel.isCancelled
          ? const RingDownloadException(RingDownloadError.cancelled)
          : error is RingDownloadException
          ? error
          : error is FileSystemException
          ? const RingDownloadException(RingDownloadError.storage)
          : error is DioException ||
                error is HttpException ||
                error is TimeoutException
          ? const RingDownloadException(RingDownloadError.network)
          : const RingDownloadException(RingDownloadError.internal);
    } finally {
      if (identical(_active, task)) _active = null;
      _busyApps.remove(config.appId);
    }
    final terminal = failure == null
        ? RingDownloadState.completed
        : failure.code == RingDownloadError.cancelled
        ? RingDownloadState.cancelled
        : RingDownloadState.failed;
    task._publish(
      terminal,
      failure == null ? result!.fileSize : task.latest.receivedBytes,
      total: failure == null ? result!.fileSize : null,
    );
    task._terminal = true;
    if (failure != null) {
      task._result.completeError(failure);
    } else {
      task._result.complete(result!);
    }
    unawaited(task._events.close());
  }

  /// Reconcile a real package-manager build on the next app start. Telemetry
  /// failure never changes update eligibility, transfer or installation.
  Future<void> reconcileInstalledBuild(int build) async {
    if (_disposed || build <= 0) return;
    final events = _engine;
    if (events is RingInstallationEvents) {
      try {
        await (events as RingInstallationEvents).reconcileInstalledBuild(build);
      } catch (_) {}
    }
  }

  /// Host calls this only after its own receipt and eligibility checks pass.
  Future<void> rememberInstallation(RingDownloadRequest request) async {
    if (_disposed || !request.usesHostedService) return;
    request.validate(appId: config.appId);
    final events = _engine;
    if (events is RingInstallationEvents) {
      try {
        await (events as RingInstallationEvents).rememberInstallation(request);
      } catch (_) {}
    }
  }

  Future<void> reportInstallationFailure(RingDownloadRequest request) async {
    if (_disposed || !request.usesHostedService) return;
    request.validate(appId: config.appId);
    final events = _engine;
    if (events is RingInstallationEvents) {
      try {
        await (events as RingInstallationEvents).reportInstallationFailure(
          request,
        );
      } catch (_) {}
    }
  }

  Future<RingSdkStatus> inspect() async {
    if (_disposed) {
      throw const RingDownloadException(RingDownloadError.disposed);
    }
    final network = await RingNetwork.read();
    return RingSdkStatus(
      appId: config.appId,
      platform: Platform.operatingSystem,
      networkType: network.wireName,
      p2pEnabled: config.enableP2P && Platform.isAndroid,
      sharingOptIn: _sharingEnabled,
    );
  }

  void setForeground(bool foreground) {
    if (!_disposed) _engine.setForeground(foreground);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      setForeground(state == AppLifecycleState.resumed);

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _releaseSource.dispose();
    if (config.observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    final task = _active;
    task?.cancel();
    try {
      await task?.completed;
    } catch (_) {
      /* Cancellation is expected. */
    }
    await _engine.dispose();
  }
}
