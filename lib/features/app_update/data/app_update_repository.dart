import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../../core/platform/distribution_channel.dart';

import '../domain/app_update_models.dart';
import 'app_update_platform.dart';
import 'app_update_release_source.dart';

typedef UpdateDownloadProgress =
    void Function(int receivedBytes, int totalBytes);
typedef UpdateDirectoryProvider = Future<Directory> Function();

/// Cancels the active stream read while preserving the verified partial file.
///
/// The UI uses this for pause. A later download resumes from the same partial
/// file instead of treating cancellation as a failed or corrupted APK.
class UpdateDownloadCancellationToken {
  bool _cancelled = false;
  Future<void> Function()? _cancelActiveRead;

  bool get isCancelled => _cancelled;

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _cancelActiveRead?.call();
  }

  Future<void> attach(Future<void> Function() cancelActiveRead) async {
    _cancelActiveRead = cancelActiveRead;
    if (_cancelled) await cancelActiveRead();
  }

  void detach() => _cancelActiveRead = null;
}

class AppUpdateDownloadSnapshot {
  const AppUpdateDownloadSnapshot({
    required this.receivedBytes,
    required this.totalBytes,
    this.completedPath,
  });

  final int receivedBytes;
  final int totalBytes;
  final String? completedPath;

  bool get isComplete => completedPath != null;
}

/// Download-only seam: discovery, update policy and installation stay in Music.
/// Implementations own their private cache and must finish writers on cancel.
abstract class AppUpdateDownloadTransport {
  Future<File> download(
    AppUpdateManifest manifest, {
    required UpdateDownloadProgress onProgress,
    UpdateDownloadCancellationToken? cancellationToken,
  });
  Future<void> clearDownloads();
  Future<void> dispose();
  Future<void> reconcileInstalledBuild(int build) async {}
  Future<void> rememberInstallation(AppUpdateManifest manifest) async {}
  Future<void> reportInstallationFailure(AppUpdateManifest manifest) async {}
}

/// Validates, resumes and installs updates for one Android package/channel.
///
/// [defaultManifestUrl] and [expectedPackageName] are build-time settings, so
/// stable, Java/MySQL test and Beta packages never read one another's manifests
/// or accept one another's APK files.
class AppUpdateRepository {
  AppUpdateRepository({
    required http.Client client,
    required AppUpdatePlatform platform,
    Uri? manifestUrl,
    AppUpdateReleaseSource? releaseSource,
    AppUpdateDownloadTransport? downloadTransport,
    UpdateDirectoryProvider? directoryProvider,
  }) : _client = client,
       _platform = platform,
       _releaseSource = releaseSource,
       _downloadTransport = downloadTransport,
       _manifestUrl = manifestUrl ?? Uri.parse(defaultManifestUrl),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static String get defaultManifestUrl => DistributionChannel.isBeta
      ? DistributionChannel.updateManifestUrl
      : const String.fromEnvironment(
          'APP_UPDATE_MANIFEST_URL',
          defaultValue:
              'https://mesting-d5gm7tuhxacddccfb-1331507389.tcloudbaseapp.com/releases/android/latest.json',
        );
  static String get expectedPackageName => DistributionChannel.isBeta
      ? DistributionChannel.packageName
      : const String.fromEnvironment(
          'APP_UPDATE_PACKAGE_NAME',
          defaultValue: 'com.mesting.music',
        );
  static const _maxManifestBytes = 1024 * 1024;
  static const _maxApkBytes = 350 * 1024 * 1024;
  static const _progressFlushBytes = 256 * 1024;

  final http.Client _client;
  final AppUpdatePlatform _platform;
  final AppUpdateReleaseSource? _releaseSource;
  final AppUpdateDownloadTransport? _downloadTransport;
  final _transportReceived = <String, int>{};
  final _verifiedDownloads = <String, AppUpdateManifest>{};
  Future<String>? _deviceIdentity;
  final Uri _manifestUrl;
  final UpdateDirectoryProvider _directoryProvider;

  Future<AppVersionInfo> currentVersion() => _platform.currentVersion();

  Future<AppUpdateCheckResult> check() async {
    try {
      final current = await currentVersion();
      if (current.packageName != expectedPackageName) {
        throw const AppUpdateException('当前安装包标识不受支持', code: 'package');
      }
      final transport = _downloadTransport;
      if (transport != null) {
        // Best-effort installation telemetry must not delay release discovery.
        unawaited(transport.reconcileInstalledBuild(current.versionCode));
      }
      final source = _releaseSource;
      if (source != null) {
        final manifest = await source.latest();
        if (manifest.packageName != expectedPackageName) {
          throw const AppUpdateException('更新包与当前应用不匹配', code: 'package');
        }
        return AppUpdateCheckResult(
          currentVersion: current,
          manifest: manifest,
        );
      }
      // Static hosting can cache latest.json. The timestamp only bypasses that
      // cache; package identity and integrity are still verified below.
      final requestUrl = _manifestUrl.replace(
        queryParameters: {
          ..._manifestUrl.queryParameters,
          't': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      final response = await _client
          .get(requestUrl, headers: const {'accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw AppUpdateException(
          '更新服务暂时不可用（${response.statusCode}）',
          code: 'manifest_http',
        );
      }
      if (response.bodyBytes.length > _maxManifestBytes) {
        throw const AppUpdateException('更新清单大小异常', code: 'manifest_size');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('更新清单不是 JSON 对象');
      }
      final manifest = AppUpdateManifest.fromJson(decoded);
      if (manifest.packageName != expectedPackageName) {
        throw const AppUpdateException('更新包与当前应用不匹配', code: 'package');
      }
      if (manifest.sizeBytes > _maxApkBytes) {
        throw const AppUpdateException('更新包大小异常', code: 'apk_size');
      }
      return AppUpdateCheckResult(currentVersion: current, manifest: manifest);
    } on AppUpdateException {
      rethrow;
    } on FormatException {
      throw const AppUpdateException('更新清单格式无效', code: 'manifest');
    } on Object {
      throw const AppUpdateException('无法连接更新服务，请检查网络', code: 'network');
    }
  }

  /// Downloads an APK resumably and returns a path only after SHA-256 passes.
  ///
  /// Failed network reads leave the `.partial` file in place. Size, range and
  /// digest failures delete it because resuming untrusted bytes is unsafe.
  Future<String> download(
    AppUpdateManifest manifest, {
    required UpdateDownloadProgress onProgress,
    UpdateDownloadCancellationToken? cancellationToken,
  }) async {
    final transport = _downloadTransport;
    if (transport != null) {
      final files = await _filesFor(manifest);
      final snapshot = await inspectDownload(manifest);
      if (snapshot.completedPath case final completedPath?) {
        onProgress(manifest.sizeBytes, manifest.sizeBytes);
        return completedPath;
      }
      // Finish a pre-SDK partial with the original Range/session protocol once.
      // New downloads use SDK-owned resume data; never guess its file format.
      if (await _safeLength(files.partial) == 0) {
        _throwIfCancelled(cancellationToken);
        final file = await transport.download(
          manifest,
          onProgress: (received, total) {
            _transportReceived[files.target.path] = received;
            onProgress(received, total);
          },
          cancellationToken: cancellationToken,
        );
        _throwIfCancelled(cancellationToken);
        if (await file.length() != manifest.sizeBytes ||
            !await _matchesDigest(file, manifest.sha256)) {
          throw const AppUpdateException('安装包校验失败，请重新下载', code: 'sha256');
        }
        // Keep the established app_updates/ installer allowlist. A rename in
        // the same app-private filesystem avoids a second full APK copy.
        await _deleteIfPresent(files.target);
        await file.rename(files.target.path);
        _verifiedDownloads[files.target.path] = manifest;
        _transportReceived.remove(files.target.path);
        return files.target.path;
      }
    }
    try {
      return await _downloadFrom(
        manifest,
        manifest.apkUrl,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    } on AppUpdateException catch (error) {
      final backup = manifest.apkBackupUrl;
      // A single mirror attempt is allowed only for transport/server failures.
      // Rate limits, rejected identity and integrity failures require recovery
      // by the user; switching mirrors must not bypass those responses.
      if (backup == null ||
          backup == manifest.apkUrl ||
          !const {
            'interrupted',
            'download_http_transient',
          }.contains(error.code)) {
        rethrow;
      }
      _throwIfCancelled(cancellationToken);
      return _downloadFrom(
        manifest,
        backup,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }
  }

  Future<String> _downloadFrom(
    AppUpdateManifest manifest,
    Uri source, {
    required UpdateDownloadProgress onProgress,
    UpdateDownloadCancellationToken? cancellationToken,
  }) async {
    final files = await _filesFor(manifest);
    final snapshot = await inspectDownload(manifest);
    if (snapshot.completedPath case final completedPath?) {
      onProgress(manifest.sizeBytes, manifest.sizeBytes);
      return completedPath;
    }
    var receivedBytes = snapshot.receivedBytes;
    onProgress(receivedBytes, manifest.sizeBytes);
    _throwIfCancelled(cancellationToken);
    try {
      final response = await _sendDownloadRequest(
        source,
        manifest,
        files,
        receivedBytes,
      );
      if (cancellationToken?.isCancelled == true) {
        await response.stream.drain<void>();
      }
      _throwIfCancelled(cancellationToken);
      var append = false;
      var verifyFullResponsePrefix = false;
      if (receivedBytes > 0 && response.statusCode == 206) {
        if (!_validContentRange(
          response.headers['content-range'],
          receivedBytes,
          manifest.sizeBytes,
        )) {
          throw const AppUpdateException('更新服务返回的续传范围无效', code: 'range');
        }
        append = true;
      } else if (receivedBytes > 0 && response.statusCode == 200) {
        // Some static-hosting gateways advertise byte ranges but still return
        // the full object. Keep the persisted progress, verify the repeated
        // prefix byte-for-byte, then append only the unseen suffix.
        if (CsnasUpdateReleaseSource.isDownloadUrl(source)) {
          // Ring's 200 response is a full replacement, not a Range append.
          receivedBytes = 0;
          await _deleteIfPresent(files.partial);
          onProgress(0, manifest.sizeBytes);
        } else {
          append = true;
          verifyFullResponsePrefix = true;
        }
      } else if (response.statusCode == 200) {
        receivedBytes = 0;
        await _deleteIfPresent(files.partial);
        onProgress(0, manifest.sizeBytes);
      } else if (receivedBytes == 0 &&
          response.statusCode == 206 &&
          _validContentRange(
            response.headers['content-range'],
            0,
            manifest.sizeBytes,
          )) {
        receivedBytes = 0;
      } else {
        await response.stream.drain<void>();
        throw AppUpdateException(
          response.statusCode == 429
              ? '下载请求较多，请稍后重试'
              : '安装包下载失败（${response.statusCode}）',
          code: response.statusCode >= 500
              ? 'download_http_transient'
              : 'download_http',
        );
      }

      final advertisedBytes = response.contentLength;
      if (advertisedBytes != null &&
          (advertisedBytes > _maxApkBytes ||
              (response.statusCode == 206
                  ? receivedBytes + advertisedBytes > manifest.sizeBytes
                  : advertisedBytes > manifest.sizeBytes))) {
        throw const AppUpdateException('安装包大小异常', code: 'apk_size');
      }

      var lastReportedBytes = receivedBytes;
      var prefixBytesRemaining = verifyFullResponsePrefix ? receivedBytes : 0;
      RandomAccessFile? prefixReader = verifyFullResponsePrefix
          ? await files.partial.open()
          : null;
      RandomAccessFile? output = verifyFullResponsePrefix
          ? null
          : await files.partial.open(
              mode: append ? FileMode.append : FileMode.write,
            );
      final iterator = StreamIterator<List<int>>(
        response.stream.timeout(const Duration(seconds: 30)),
      );
      await cancellationToken?.attach(iterator.cancel);
      try {
        while (await iterator.moveNext()) {
          _throwIfCancelled(cancellationToken);
          final chunk = iterator.current;
          var payloadOffset = 0;
          if (prefixBytesRemaining > 0) {
            final compareLength = chunk.length < prefixBytesRemaining
                ? chunk.length
                : prefixBytesRemaining;
            final expected = await prefixReader!.read(compareLength);
            if (!_sameBytes(expected, chunk, compareLength)) {
              throw const AppUpdateException('更新包内容已变化，请重新下载', code: 'range');
            }
            prefixBytesRemaining -= compareLength;
            payloadOffset = compareLength;
            if (prefixBytesRemaining == 0) {
              await prefixReader.close();
              prefixReader = null;
              output = await files.partial.open(mode: FileMode.append);
            }
          }
          if (payloadOffset == chunk.length) continue;
          final payload = payloadOffset == 0
              ? chunk
              : chunk.sublist(payloadOffset);
          receivedBytes += payload.length;
          if (receivedBytes > _maxApkBytes ||
              receivedBytes > manifest.sizeBytes) {
            throw const AppUpdateException('安装包大小异常', code: 'apk_size');
          }
          await output!.writeFrom(payload);
          if (receivedBytes - lastReportedBytes >= _progressFlushBytes ||
              receivedBytes == manifest.sizeBytes) {
            await output.flush();
            lastReportedBytes = receivedBytes;
            onProgress(receivedBytes, manifest.sizeBytes);
          }
        }
      } finally {
        cancellationToken?.detach();
        await iterator.cancel();
        await prefixReader?.close();
        await output?.flush();
        await output?.close();
      }

      _throwIfCancelled(cancellationToken);
      final persistedBytes = await files.partial.length();
      if (persistedBytes < manifest.sizeBytes) {
        onProgress(persistedBytes, manifest.sizeBytes);
        throw const AppUpdateException('下载已中断，进度已保留', code: 'interrupted');
      }
      if (persistedBytes > manifest.sizeBytes) {
        await _deleteIfPresent(files.partial);
        throw const AppUpdateException('安装包大小异常', code: 'apk_size');
      }
      onProgress(persistedBytes, manifest.sizeBytes);
      return await _finalizeDownload(manifest, files);
    } on AppUpdateException catch (error) {
      if (error.code == 'sha256' ||
          error.code == 'apk_size' ||
          error.code == 'range') {
        await _deleteIfPresent(files.partial);
      }
      rethrow;
    } on Object {
      final persistedBytes = await _safeLength(files.partial);
      if (persistedBytes > 0) {
        onProgress(persistedBytes, manifest.sizeBytes);
      }
      throw const AppUpdateException('下载已中断，进度已保留，请稍后继续', code: 'interrupted');
    }
  }

  /// Redirects are bounded and session headers are rebuilt for each origin.
  /// A signed external CDN redirect never receives the platform's session ID.
  Future<http.StreamedResponse> _sendDownloadRequest(
    Uri initial,
    AppUpdateManifest manifest,
    _UpdateFiles files,
    int received,
  ) async {
    var url = initial;
    Map<String, dynamic> sessions = {};
    if (await files.httpState.exists()) {
      try {
        final saved = jsonDecode(await files.httpState.readAsString());
        if (saved is Map<String, dynamic>) sessions = saved;
      } on Object {
        /* An incomplete sidecar never authorizes a session. */
      }
    }
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (url.scheme != 'https' || url.userInfo.isNotEmpty || url.hasFragment) {
        throw const AppUpdateException('下载地址无效，请重新检查更新', code: 'download_http');
      }
      final request = http.Request('GET', url)
        ..followRedirects = false
        ..headers['accept'] = 'application/vnd.android.package-archive';
      if (received > 0) request.headers['range'] = 'bytes=$received-';
      if (CsnasUpdateReleaseSource.isDownloadUrl(url)) {
        final installed = await currentVersion();
        request.headers['x-device-id'] = await (_deviceIdentity ??=
            _loadDeviceIdentity(files.directory));
        request.headers['x-client-app-version'] =
            '${installed.versionName}+${installed.versionCode}'.replaceAll(
              RegExp(r'[\r\n]'),
              '',
            );
        final session = sessions[url.origin];
        if (session is Map) {
          final id = session['id'];
          final etag = session['etag'];
          if (_safeHeader(id)) {
            request.headers['x-download-session-id'] = id as String;
          }
          if (received > 0 && _safeHeader(etag)) {
            request.headers['if-range'] = etag as String;
          }
        }
        if (received > 0 &&
            !request.headers.containsKey('if-range') &&
            url.origin == manifest.apkUrl.origin &&
            _safeHeader(manifest.downloadEtag)) {
          request.headers['if-range'] = manifest.downloadEtag!;
        }
      }
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null || redirects == 3) {
          throw const AppUpdateException('下载地址跳转异常，请重试', code: 'download_http');
        }
        url = url.resolve(location);
        continue;
      }
      if (CsnasUpdateReleaseSource.isDownloadUrl(url) &&
          const {200, 206}.contains(response.statusCode)) {
        final sessionId = response.headers['x-download-session-id'];
        final etag = response.headers['etag'];
        sessions[url.origin] = {
          if (_safeHeader(sessionId)) 'id': sessionId,
          if (_safeHeader(etag)) 'etag': etag,
        };
        await files.httpState.writeAsString(jsonEncode(sessions), flush: true);
      }
      return response;
    }
    throw const AppUpdateException('下载地址跳转异常', code: 'download_http');
  }

  bool _safeHeader(Object? value) =>
      value is String &&
      value.isNotEmpty &&
      value.length <= 512 &&
      !value.contains(RegExp(r'[\r\n]'));

  Future<String> _loadDeviceIdentity(Directory directory) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}download-installation-id',
    );
    if (await file.exists()) {
      final saved = (await file.readAsString()).trim();
      if (RegExp(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      ).hasMatch(saved)) {
        return saved;
      }
    }
    final random = math.Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await file.writeAsString(id, flush: true);
    return id;
  }

  /// Inspects an existing target/partial file before a download or resume.
  ///
  /// A complete APK is reused only after verifying its digest again; a filename
  /// or matching byte count alone is never treated as an installed update.
  Future<AppUpdateDownloadSnapshot> inspectDownload(
    AppUpdateManifest manifest,
  ) async {
    final files = await _filesFor(manifest);
    await _clearOldDownloads(
      files.directory,
      keep: {files.target.path, files.partial.path, files.httpState.path},
    );

    if (await files.target.exists()) {
      final targetLength = await files.target.length();
      if (targetLength == manifest.sizeBytes &&
          await _matchesDigest(files.target, manifest.sha256)) {
        _verifiedDownloads[files.target.path] = manifest;
        return AppUpdateDownloadSnapshot(
          receivedBytes: manifest.sizeBytes,
          totalBytes: manifest.sizeBytes,
          completedPath: files.target.path,
        );
      }
      await _deleteIfPresent(files.target);
    }

    if (!await files.partial.exists()) {
      return AppUpdateDownloadSnapshot(
        // Display-only checkpoint for a paused SDK task. After process restart
        // SDK publishes its actual persisted progress when resume begins.
        receivedBytes: _transportReceived[files.target.path] ?? 0,
        totalBytes: manifest.sizeBytes,
      );
    }
    final partialLength = await files.partial.length();
    if (partialLength > manifest.sizeBytes) {
      await _deleteIfPresent(files.partial);
      return AppUpdateDownloadSnapshot(
        receivedBytes: 0,
        totalBytes: manifest.sizeBytes,
      );
    }
    if (partialLength == manifest.sizeBytes) {
      try {
        final completedPath = await _finalizeDownload(manifest, files);
        return AppUpdateDownloadSnapshot(
          receivedBytes: manifest.sizeBytes,
          totalBytes: manifest.sizeBytes,
          completedPath: completedPath,
        );
      } on AppUpdateException {
        return AppUpdateDownloadSnapshot(
          receivedBytes: 0,
          totalBytes: manifest.sizeBytes,
        );
      }
    }
    return AppUpdateDownloadSnapshot(
      receivedBytes: partialLength,
      totalBytes: manifest.sizeBytes,
    );
  }

  Future<void> clearDownloads() async {
    await _downloadTransport?.clearDownloads();
    _transportReceived.clear();
    _verifiedDownloads.clear();
    final baseDirectory = await _directoryProvider();
    final directory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}app_updates',
    );
    if (!await directory.exists()) return;
    await _clearOldDownloads(directory);
  }

  Future<bool> canRequestPackageInstalls() =>
      _platform.canRequestPackageInstalls();

  Future<void> openInstallPermission() => _platform.openInstallPermission();

  Future<void> installApk(String path) async {
    final manifest = _verifiedDownloads[path];
    if (manifest != null) {
      final file = File(path);
      if (!await file.exists() ||
          await file.length() != manifest.sizeBytes ||
          !await _matchesDigest(file, manifest.sha256)) {
        throw const AppUpdateException('安装包已变化，请重新下载', code: 'sha256');
      }
      await _downloadTransport?.rememberInstallation(manifest);
    }
    try {
      await _platform.installApk(path);
    } catch (_) {
      if (manifest != null) {
        await _downloadTransport?.reportInstallationFailure(manifest);
      }
      rethrow;
    }
  }

  /// Creates deterministic names that include a digest prefix.
  ///
  /// This lets a republished version code with different bytes coexist safely
  /// until stale downloads are removed, rather than resuming the wrong file.
  Future<_UpdateFiles> _filesFor(AppUpdateManifest manifest) async {
    final baseDirectory = await _directoryProvider();
    final directory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}app_updates',
    );
    await directory.create(recursive: true);
    final safeVersion = manifest.versionName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final digestPrefix = manifest.sha256.substring(0, 12);
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      'mesting-music-$safeVersion-${manifest.versionCode}-$digestPrefix.apk',
    );
    return _UpdateFiles(
      directory: directory,
      target: target,
      partial: File('${target.path}.partial'),
      httpState: File('${target.path}.http.json'),
    );
  }

  /// Promotes the partial file atomically only after its expected digest wins.
  Future<String> _finalizeDownload(
    AppUpdateManifest manifest,
    _UpdateFiles files,
  ) async {
    if (!await _matchesDigest(files.partial, manifest.sha256)) {
      await _deleteIfPresent(files.partial);
      throw const AppUpdateException('安装包校验失败，请重新下载', code: 'sha256');
    }
    await _deleteIfPresent(files.target);
    await files.partial.rename(files.target.path);
    _verifiedDownloads[files.target.path] = manifest;
    return files.target.path;
  }

  Future<bool> _matchesDigest(File file, String expected) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expected;
  }

  bool _validContentRange(String? value, int start, int total) {
    if (value == null) return false;
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    if (match == null) return false;
    final actualStart = int.tryParse(match.group(1)!);
    final actualEnd = int.tryParse(match.group(2)!);
    final actualTotal = int.tryParse(match.group(3)!);
    return actualStart == start &&
        actualEnd != null &&
        actualEnd >= start &&
        actualEnd < total &&
        actualTotal == total;
  }

  bool _sameBytes(List<int> expected, List<int> actual, int length) {
    if (expected.length != length || actual.length < length) return false;
    for (var index = 0; index < length; index++) {
      if (expected[index] != actual[index]) return false;
    }
    return true;
  }

  void _throwIfCancelled(UpdateDownloadCancellationToken? token) {
    if (token?.isCancelled == true) {
      throw const AppUpdateException('下载已暂停', code: 'paused');
    }
  }

  Future<int> _safeLength(File file) async {
    try {
      return await file.exists() ? await file.length() : 0;
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> _clearOldDownloads(
    Directory directory, {
    Set<String> keep = const {},
  }) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File &&
          !keep.contains(entity.path) &&
          entity.uri.pathSegments.last.startsWith('mesting-music-') &&
          (entity.path.endsWith('.apk') ||
              entity.path.endsWith('.partial') ||
              entity.path.endsWith('.http.json'))) {
        await _deleteIfPresent(entity);
      }
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }
}

class _UpdateFiles {
  const _UpdateFiles({
    required this.directory,
    required this.target,
    required this.partial,
    required this.httpState,
  });

  final Directory directory;
  final File target;
  final File partial;
  final File httpState;
}
