import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/persistence/app_preferences.dart';
import 'data/app_update_platform.dart';
import 'data/app_update_repository.dart';
import 'data/app_update_release_source.dart';
import 'data/ring_app_update_transport.dart';
import '../../core/platform/distribution_channel.dart';
import 'data/java_mysql_test_channel_repository.dart';
import 'domain/app_update_models.dart';

const _snoozedVersionPreference = 'app_update_snoozed_version';
const _snoozedUntilPreference = 'app_update_snoozed_until';

final appUpdateHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final appUpdatePlatformProvider = Provider<AppUpdatePlatform>(
  (ref) => AppUpdatePlatform(),
);

final appUpdateDownloadTransportProvider =
    Provider<AppUpdateDownloadTransport?>((ref) {
      if (!DistributionChannel.isBeta) return null;
      final transport = RingAppUpdateTransport(
        directoryProvider: getApplicationSupportDirectory,
      );
      ref.onDispose(() => unawaited(transport.dispose()));
      return transport;
    });

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  return AppUpdateRepository(
    downloadTransport: ref.watch(appUpdateDownloadTransportProvider),
    client: ref.watch(appUpdateHttpClientProvider),
    platform: ref.watch(appUpdatePlatformProvider),
    releaseSource: DistributionChannel.isBeta
        ? CsnasUpdateReleaseSource(
            client: ref.watch(appUpdateHttpClientProvider),
            packageName: DistributionChannel.packageName,
          )
        : null,
  );
});

final javaMysqlTestChannelRepositoryProvider =
    Provider<JavaMysqlTestChannelRepository>((ref) {
      return JavaMysqlTestChannelRepository(
        client: ref.watch(appUpdateHttpClientProvider),
        downloader: ref.watch(appUpdateRepositoryProvider),
      );
    });

final appVersionProvider = FutureProvider<AppVersionInfo>((ref) {
  return ref.watch(appUpdateRepositoryProvider).currentVersion();
});

final autoAppUpdateChecksEnabledProvider = Provider<bool>((ref) {
  return const bool.fromEnvironment(
    'ENABLE_APP_UPDATE_CHECKS',
    defaultValue: kReleaseMode,
  );
});

/// Installed notes work offline even when the remote update service is down.
/// Tests opt in explicitly; release builds show each installed build once.
final autoInstalledReleaseNotesEnabledProvider = Provider<bool>((ref) {
  return const bool.fromEnvironment(
    'ENABLE_RELEASE_NOTES',
    defaultValue: kReleaseMode,
  );
});

enum AppUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  paused,
  permissionRequired,
  readyToInstall,
  launchingInstaller,
  installLaunched,
  failed,
}

@immutable
class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.currentVersion,
    this.manifest,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.downloadedPath,
    this.errorMessage,
  });

  final AppUpdatePhase phase;
  final AppVersionInfo? currentVersion;
  final AppUpdateManifest? manifest;
  final int receivedBytes;
  final int totalBytes;
  final String? downloadedPath;
  final String? errorMessage;

  double? get progress {
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0, 1);
  }

  bool get busy =>
      phase == AppUpdatePhase.checking ||
      phase == AppUpdatePhase.downloading ||
      phase == AppUpdatePhase.verifying ||
      phase == AppUpdatePhase.launchingInstaller;

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    Object? currentVersion = _unset,
    Object? manifest = _unset,
    int? receivedBytes,
    int? totalBytes,
    Object? downloadedPath = _unset,
    Object? errorMessage = _unset,
  }) {
    return AppUpdateState(
      phase: phase ?? this.phase,
      currentVersion: identical(currentVersion, _unset)
          ? this.currentVersion
          : currentVersion as AppVersionInfo?,
      manifest: identical(manifest, _unset)
          ? this.manifest
          : manifest as AppUpdateManifest?,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedPath: identical(downloadedPath, _unset)
          ? this.downloadedPath
          : downloadedPath as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _unset = Object();

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );

class AppUpdateController extends Notifier<AppUpdateState> {
  AppUpdateRepository get _repository => ref.read(appUpdateRepositoryProvider);
  UpdateDownloadCancellationToken? _downloadCancellation;
  Future<void>? _activeDownload;
  bool _installInFlight = false;

  @override
  AppUpdateState build() {
    ref.onDispose(() {
      final cancellation = _downloadCancellation;
      if (cancellation != null) unawaited(cancellation.cancel());
    });
    return const AppUpdateState();
  }

  Future<AppUpdateCheckResult?> check({bool manual = false}) async {
    if (state.busy || _activeDownload != null) return null;
    state = state.copyWith(phase: AppUpdatePhase.checking, errorMessage: null);
    try {
      final result = await _repository.check();
      if (!result.updateAvailable) {
        await _repository.clearDownloads();
      }
      final download = result.updateAvailable
          ? await _repository.inspectDownload(result.manifest)
          : null;
      state = AppUpdateState(
        phase: !result.updateAvailable
            ? AppUpdatePhase.upToDate
            : download!.isComplete
            ? AppUpdatePhase.readyToInstall
            : download.receivedBytes > 0
            ? AppUpdatePhase.paused
            : AppUpdatePhase.available,
        currentVersion: result.currentVersion,
        manifest: result.manifest,
        receivedBytes: download?.receivedBytes ?? 0,
        totalBytes: download?.totalBytes ?? 0,
        downloadedPath: download?.completedPath,
      );
      ref.invalidate(appVersionProvider);
      if (!result.updateAvailable) return result;
      if (!manual && !result.mandatory && _isSnoozed(result.manifest)) {
        return null;
      }
      return result;
    } on AppUpdateException catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.failed,
        errorMessage: error.message,
      );
      return null;
    } on Object {
      state = state.copyWith(
        phase: AppUpdatePhase.failed,
        errorMessage: '暂时无法检查更新，请稍后重试',
      );
      return null;
    }
  }

  Future<void> downloadAndInstall() async {
    if (_activeDownload != null || state.busy) return;
    final manifest = state.manifest;
    if (manifest == null || state.busy) return;
    final task = _runDownload(manifest);
    _activeDownload = task;
    try {
      await task;
    } finally {
      if (identical(_activeDownload, task)) {
        _activeDownload = null;
      }
    }
  }

  Future<void> _runDownload(AppUpdateManifest manifest) async {
    final cancellation = UpdateDownloadCancellationToken();
    _downloadCancellation = cancellation;
    try {
      // Storage inspection belongs to the same recoverable operation as the
      // transfer: an unavailable directory must not escape the button callback.
      final existing = await _repository.inspectDownload(manifest);
      if (existing.completedPath case final completedPath?) {
        state = state.copyWith(
          phase: AppUpdatePhase.readyToInstall,
          receivedBytes: manifest.sizeBytes,
          totalBytes: manifest.sizeBytes,
          downloadedPath: completedPath,
          errorMessage: null,
        );
        await continueInstall();
        return;
      }
      state = state.copyWith(
        phase: AppUpdatePhase.downloading,
        receivedBytes: existing.receivedBytes,
        totalBytes: manifest.sizeBytes,
        downloadedPath: null,
        errorMessage: null,
      );
      final path = await _repository.download(
        manifest,
        cancellationToken: cancellation,
        onProgress: (receivedBytes, totalBytes) {
          if (state.phase != AppUpdatePhase.downloading) return;
          state = state.copyWith(
            phase: totalBytes > 0 && receivedBytes == totalBytes
                ? AppUpdatePhase.verifying
                : AppUpdatePhase.downloading,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes > 0 ? totalBytes : manifest.sizeBytes,
          );
        },
      );
      state = state.copyWith(
        phase: AppUpdatePhase.readyToInstall,
        receivedBytes: manifest.sizeBytes,
        totalBytes: manifest.sizeBytes,
        downloadedPath: path,
      );
      await continueInstall();
    } on AppUpdateException catch (error) {
      // A transfer error can coincide with a storage error. Preserve the last
      // known progress when the partial file cannot currently be inspected.
      AppUpdateDownloadSnapshot persisted;
      try {
        persisted = await _repository.inspectDownload(manifest);
      } on Object {
        persisted = AppUpdateDownloadSnapshot(
          receivedBytes: state.receivedBytes,
          totalBytes: manifest.sizeBytes,
        );
      }
      if (error.code == 'paused') {
        state = state.copyWith(
          phase: persisted.isComplete
              ? AppUpdatePhase.readyToInstall
              : AppUpdatePhase.paused,
          receivedBytes: persisted.receivedBytes,
          totalBytes: manifest.sizeBytes,
          downloadedPath: persisted.completedPath,
          errorMessage: null,
        );
      } else {
        state = state.copyWith(
          phase: persisted.isComplete
              ? AppUpdatePhase.readyToInstall
              : AppUpdatePhase.failed,
          receivedBytes: persisted.receivedBytes,
          totalBytes: manifest.sizeBytes,
          downloadedPath: persisted.completedPath,
          errorMessage: persisted.isComplete ? null : error.message,
        );
      }
    } on Object {
      state = state.copyWith(
        phase: AppUpdatePhase.failed,
        errorMessage: '无法保存更新包，请检查可用空间后重试',
      );
    } finally {
      if (identical(_downloadCancellation, cancellation)) {
        _downloadCancellation = null;
      }
    }
  }

  Future<void> pauseDownload() async {
    if (state.phase != AppUpdatePhase.downloading) return;
    state = state.copyWith(phase: AppUpdatePhase.paused, errorMessage: null);
    await _downloadCancellation?.cancel();
    final activeDownload = _activeDownload;
    if (activeDownload != null) {
      await activeDownload;
    }
  }

  Future<void> continueInstall() async {
    final path = state.downloadedPath;
    if (path == null ||
        _installInFlight ||
        state.phase == AppUpdatePhase.launchingInstaller) {
      return;
    }
    _installInFlight = true;
    try {
      if (!await _repository.canRequestPackageInstalls()) {
        state = state.copyWith(phase: AppUpdatePhase.permissionRequired);
        return;
      }
      state = state.copyWith(
        phase: AppUpdatePhase.launchingInstaller,
        errorMessage: null,
      );
      await _repository.installApk(path);
      state = state.copyWith(phase: AppUpdatePhase.installLaunched);
    } on PlatformException catch (error) {
      state = state.copyWith(
        phase: AppUpdatePhase.failed,
        errorMessage: _platformErrorMessage(error.code),
      );
    } on Object {
      state = state.copyWith(
        phase: AppUpdatePhase.failed,
        errorMessage: '无法打开系统安装页面，请稍后重试',
      );
    } finally {
      _installInFlight = false;
    }
  }

  Future<void> openInstallPermission() async {
    try {
      await _repository.openInstallPermission();
    } on Object {
      state = state.copyWith(
        phase: AppUpdatePhase.failed,
        errorMessage: '无法打开安装权限设置',
      );
    }
  }

  Future<void> snooze() async {
    final manifest = state.manifest;
    if (manifest == null) return;
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setInt(_snoozedVersionPreference, manifest.versionCode);
    await preferences.setInt(
      _snoozedUntilPreference,
      DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch,
    );
  }

  bool _isSnoozed(AppUpdateManifest manifest) {
    final preferences = ref.read(sharedPreferencesProvider);
    return preferences.getInt(_snoozedVersionPreference) ==
            manifest.versionCode &&
        (preferences.getInt(_snoozedUntilPreference) ?? 0) >
            DateTime.now().millisecondsSinceEpoch;
  }

  String _platformErrorMessage(String code) {
    return switch (code) {
      'apk_package_mismatch' => '安装包与当前应用不匹配',
      'apk_version_not_newer' => '安装包版本不高于当前版本',
      'apk_signature_mismatch' => '安装包签名校验失败，已阻止安装',
      'invalid_apk' => '安装包无效或已经损坏',
      'invalid_path' => '安装包路径不安全，已阻止安装',
      'installer_unavailable' => '系统安装程序不可用',
      _ => '无法打开系统安装页面，请稍后重试',
    };
  }
}
