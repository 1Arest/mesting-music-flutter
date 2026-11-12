import 'dart:async';
import 'dart:io';

import 'package:ring_download_sdk/ring_download_sdk.dart';

import '../domain/app_update_models.dart';
import 'app_update_repository.dart';

/// One lifecycle-aware SDK instance for Music's update feature. No user login,
/// music playback, administrator credential or extra health lookup enters it.
class RingAppUpdateTransport extends AppUpdateDownloadTransport {
  RingAppUpdateTransport({
    required UpdateDirectoryProvider directoryProvider,
    RingDownloadSdk Function(RingDownloadConfig)? sdkFactory,
  }) : _directoryProvider = directoryProvider,
       _sdkFactory = sdkFactory ?? RingDownloadSdk.new;

  final UpdateDirectoryProvider _directoryProvider;
  final RingDownloadSdk Function(RingDownloadConfig) _sdkFactory;
  Future<RingDownloadSdk>? _sdkFuture;
  RingDownloadTask? _active;
  bool _disposed = false;
  bool _clearing = false;
  bool _downloading = false;

  Future<Directory> _storageDirectory() async {
    final base = await _directoryProvider();
    return Directory(
      '${base.path}${Platform.pathSeparator}app_updates'
      '${Platform.pathSeparator}.ring-sdk',
    );
  }

  Future<RingDownloadSdk> _sdk() {
    if (_disposed) {
      throw const RingDownloadException(RingDownloadError.disposed);
    }
    if (_clearing) {
      throw const RingDownloadException(RingDownloadError.busy);
    }
    return _sdkFuture ??= _createSdk();
  }

  Future<RingDownloadSdk> _createSdk() async {
    try {
      final directory = await _storageDirectory();
      if (_disposed) {
        throw const RingDownloadException(RingDownloadError.disposed);
      }
      return _sdkFactory(
        RingDownloadConfig(
          appId: 'music',
          enableP2P: true,
          enableP8P: true,
          // Music has not opted into user uploads. Nodes can still assist it.
          allowSharing: false,
          observeLifecycle: true,
          storageDirectory: directory,
        ),
      );
    } catch (_) {
      _sdkFuture = null; // A temporary storage failure remains retryable.
      rethrow;
    }
  }

  static RingDownloadRequest requestFor(AppUpdateManifest manifest) {
    final external = !RingDownloadRequest.hostedHosts.contains(
      manifest.apkUrl.host.toLowerCase(),
    );
    final backup = manifest.apkBackupUrl;
    return RingDownloadRequest(
      releaseId: 'music-${manifest.versionCode}-${manifest.sha256}',
      version: manifest.versionName,
      url: manifest.apkUrl,
      backupUrl:
          external &&
              backup != null &&
              RingDownloadRequest.hostedHosts.contains(
                backup.host.toLowerCase(),
              )
          ? null
          : backup,
      fileSize: manifest.sizeBytes,
      sha256: manifest.sha256,
      androidVersionCode: manifest.versionCode,
      etag: manifest.downloadEtag ?? '',
    );
  }

  @override
  Future<File> download(
    AppUpdateManifest manifest, {
    required UpdateDownloadProgress onProgress,
    UpdateDownloadCancellationToken? cancellationToken,
  }) async {
    StreamSubscription<RingDownloadProgress>? subscription;
    RingDownloadTask? task;
    var ownsDownload = false;
    try {
      if (_clearing || _downloading) {
        throw const RingDownloadException(RingDownloadError.busy);
      }
      _downloading = ownsDownload = true;
      final sdk = await _sdk();
      if (_disposed || cancellationToken?.isCancelled == true) {
        throw const RingDownloadException(RingDownloadError.cancelled);
      }
      task = sdk.download(requestFor(manifest));
      _active = task;
      subscription = task.progress.listen((progress) {
        if (cancellationToken?.isCancelled != true) {
          onProgress(progress.receivedBytes, progress.totalBytes);
        }
      });
      final activeTask = task;
      await cancellationToken?.attach(() async {
        activeTask.cancel();
        try {
          await activeTask.completed;
        } on Object {
          // Cancellation completion is a cleanup barrier, not a second error.
        }
      });
      final result = await task.completed;
      await result.revalidate();
      return result.file;
    } on RingDownloadException catch (error) {
      throw switch (error.code) {
        RingDownloadError.cancelled => const AppUpdateException(
          '下载已暂停',
          code: 'paused',
        ),
        RingDownloadError.integrity => const AppUpdateException(
          '安装包校验失败，请重新下载',
          code: 'sha256',
        ),
        RingDownloadError.storage => const AppUpdateException(
          '无法保存安装包，请检查可用空间',
          code: 'storage',
        ),
        RingDownloadError.invalidRequest ||
        RingDownloadError.invalidMetadata ||
        RingDownloadError.releaseUnavailable => const AppUpdateException(
          '发布信息已变化，请重新检查更新',
          code: 'manifest',
        ),
        RingDownloadError.rateLimited => const AppUpdateException(
          '下载请求过于频繁，请稍后重试',
          code: 'download_http',
        ),
        RingDownloadError.busy => const AppUpdateException(
          '已有更新正在下载',
          code: 'download_busy',
        ),
        _ => const AppUpdateException('下载已中断，进度已保留，请稍后继续', code: 'interrupted'),
      };
    } finally {
      // A rejected overlapping call must not detach another task's cancel hook.
      if (task != null) {
        // A queued progress event can race with cancel(). Preserve the SDK's
        // final display checkpoint after the writer cleanup barrier completes.
        onProgress(task.latest.receivedBytes, task.latest.totalBytes);
        cancellationToken?.detach();
        if (identical(_active, task)) _active = null;
      }
      await subscription?.cancel();
      if (ownsDownload) _downloading = false;
    }
  }

  @override
  Future<void> reconcileInstalledBuild(int build) async {
    try {
      await (await _sdk()).reconcileInstalledBuild(build);
    } catch (_) {}
  }

  @override
  Future<void> rememberInstallation(AppUpdateManifest manifest) async {
    try {
      await (await _sdk()).rememberInstallation(requestFor(manifest));
    } catch (_) {}
  }

  @override
  Future<void> reportInstallationFailure(AppUpdateManifest manifest) async {
    try {
      await (await _sdk()).reportInstallationFailure(requestFor(manifest));
    } catch (_) {}
  }

  @override
  Future<void> clearDownloads() async {
    if (_downloading || _clearing) {
      throw const AppUpdateException('请先暂停下载', code: 'download_busy');
    }
    _clearing = true;
    try {
      final previous = _sdkFuture;
      if (previous != null) {
        try {
          await (await previous).dispose();
        } finally {
          _sdkFuture = null;
        }
      }
      final directory = await _storageDirectory();
      if (await directory.exists()) await directory.delete(recursive: true);
    } finally {
      _clearing = false;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final pending = _sdkFuture;
    if (pending != null) {
      try {
        await (await pending).dispose();
      } catch (_) {}
    }
  }
}
