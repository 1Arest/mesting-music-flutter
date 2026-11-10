import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_upgrade_models.dart';
import '../../p8p/sources.dart';
import 'app_upgrade_v40_p2p_client.dart';
import 'app_upgrade_p2p_diagnostics.dart';
import 'app_upgrade_p2p_identity.dart';
import 'app_upgrade_service_events.dart';
import 'app_upgrade_p2p_protocol.dart';
import 'app_upgrade_file_io.dart';

/// Implements the external v40 HTTP session contract for explicit v40 updates only.
class AppUpgradeV40DownloadClient {
  AppUpgradeV40DownloadClient({
    required Dio dio,
    AppUpgradeV40P2PClient? p2pClient,
    Future<Directory> Function()? supportDirectoryLoader,
    AppUpgradeServiceEvents? serviceEvents,
    this.httpsHeadStart = false,
    this.allowExternalHttps = false,
  }) : _dio = dio,
       serviceEvents = serviceEvents ?? AppUpgradeServiceEvents(),
       _p2pClient =
           p2pClient ??
           AppUpgradeV40P2PClient(
             hybridStartup: httpsHeadStart,
             fastSignaling: httpsHeadStart,
             preferredPeerBatchPieces: 4,
           ),
       _supportDirectoryLoader =
           supportDirectoryLoader ?? getApplicationSupportDirectory;

  static const _taskPrefix = 'app_upgrade.v40.task.';
  static const _maxAttempts = 3;
  static const _allowedHosts = <String>{
    'download.csnas.asia',
    'download1.csnas.asia',
  };

  final AppUpgradeServiceEvents serviceEvents;
  final Dio _dio;
  final bool httpsHeadStart;
  final bool allowExternalHttps;
  int _lastHttpsBodyBytes = 0, _lastBootstrapBodyBytes = 0;
  int get lastHttpsBodyBytes => _lastHttpsBodyBytes;
  int get lastBootstrapBodyBytes => _lastBootstrapBodyBytes;
  int get lastBootstrapUsedBytes => _p2pClient.lastBootstrapUsedBytes;
  Stopwatch? _activeWatch;
  int _savedActiveMs = 0;
  final AppUpgradeV40P2PClient _p2pClient;
  final Future<Directory> Function() _supportDirectoryLoader;
  CancelToken? _activeCancel;
  bool _foreground = true;
  Future<File>? _flight;
  String? _flightKey;

  void setForeground(bool foreground) {
    _foreground = foreground;
    _p2pClient.setForeground(foreground);
  }

  void cancelDownload() {
    _activeCancel?.cancel('client_interrupted');
    _p2pClient.cancelDownload();
  }

  /// Let cancellation finish persistence and queue the immutable final report
  /// before the engine retires the P2P/signaling owners.
  Future<void> cancelAndWait() async {
    cancelDownload();
    try {
      await _flight;
    } catch (_) {
      // The transfer caller receives its original failure or cancellation.
    }
  }

  /// Resumes only v40 service URLs; callers keep the legacy downloader for all other sources.
  Future<File> download({
    required AppUpgradeInfo info,
    required String url,
    required String? backupUrl,
    required Future<AppUpgradeInfo?> Function() refreshRelease,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) {
    final key = '${info.downloadSlug}|${info.sha256}|$url';
    final current = _flight;
    if (current != null) {
      if (key == _flightKey) return current;
      return Future.error(StateError('download_already_active'));
    }
    _flightKey = key;
    _lastHttpsBodyBytes = 0;
    _lastBootstrapBodyBytes = 0;
    late Future<File> flight;
    flight =
        _runDownload(
          info: info,
          url: url,
          backupUrl: backupUrl,
          refreshRelease: refreshRelease,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ).whenComplete(() {
          if (identical(_flight, flight)) {
            _flight = null;
            _flightKey = null;
          }
        });
    _flight = flight;
    return flight;
  }

  Future<File> _runDownload({
    required AppUpgradeInfo info,
    required String url,
    required String? backupUrl,
    required Future<AppUpgradeInfo?> Function() refreshRelease,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final token = cancelToken ?? CancelToken();
    _activeCancel = token;
    final prefs = await SharedPreferences.getInstance();
    final durationKey = "$_taskPrefix${info.releaseId}.active_ms";
    _savedActiveMs = prefs.getInt(durationKey) ?? 0;
    _activeWatch = Stopwatch()..start();
    // Abrupt process death does not run finally. Checkpoint the active interval
    // without blocking transfer; serialize writes before final cleanup.
    Future<void> checkpoint = Future.value();
    final checkpointTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final duration =
          (_savedActiveMs + (_activeWatch?.elapsedMilliseconds ?? 0)).clamp(
            0,
            604800000,
          );
      checkpoint = checkpoint
          .then((_) async {
            await prefs.setInt(durationKey, duration);
          })
          .catchError((_) {});
    });
    var verifiedDownload = false;
    try {
      final file = await _download(
        info: info,
        url: url,
        backupUrl: backupUrl,
        refreshRelease: refreshRelease,
        onProgress: onProgress,
        cancelToken: token,
      );
      if (token.isCancelled) throw token.cancelError!;
      verifiedDownload = true;
      _p2pClient.recordDownloadDiagnostic(
        'final',
        'apk_verified',
        verified: true,
      );
      if (_foreground) {
        // Best effort cache sharing must never delay installation.
        unawaited(_p2pClient.shareVerifiedFile(file, url).catchError((_) {}));
      }
      return file;
    } catch (error) {
      // Freeze this task before releasing single-flight ownership. Only local
      // persistence is awaited; the public sender performs network I/O separately.
      _activeWatch?.stop();
      await _reportFailure(info, token.isCancelled, error).catchError((_) {});
      _p2pClient.recordDownloadDiagnostic(
        'final',
        token.isCancelled ? 'client_interrupted' : 'download_failed',
        verified: false,
      );
      rethrow;
    } finally {
      _p2pClient.reportFinalTraffic(
        httpsBodyBytes: _lastHttpsBodyBytes,
        verified: verifiedDownload,
      );
      checkpointTimer.cancel();
      await checkpoint;
      final duration =
          _savedActiveMs + (_activeWatch?.elapsedMilliseconds ?? 0);
      _activeWatch?.stop();
      try {
        if (verifiedDownload) {
          await prefs.remove(durationKey);
        } else {
          await prefs.setInt(durationKey, duration.clamp(0, 604800000));
        }
      } catch (_) {}
      if (identical(_activeCancel, token)) _activeCancel = null;
    }
  }

  Future<File> _download({
    required AppUpgradeInfo info,
    required String url,
    required String? backupUrl,
    required Future<AppUpgradeInfo?> Function() refreshRelease,
    required void Function(int received, int total) onProgress,
    required CancelToken cancelToken,
    bool metadataRefreshed = false,
  }) async {
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    if (httpsHeadStart) {
      final publish = onProgress;
      var displayed = 0;
      onProgress = (received, total) {
        if (received > displayed) displayed = received;
        publish(displayed.clamp(0, total), total);
      };
    }
    var currentInfo = info;
    var currentUrl = url;
    var currentBackupUrl = backupUrl;
    var refreshedAfterInvalidSession = false;
    var resetAfterRangeError = false;
    String? redirectedHttpsSource;

    final deviceId = await _loadOrCreateDeviceId();
    final directory = await _supportDirectoryLoader();
    final downloadDirectory = Directory(
      path.join(directory.path, 'app-upgrades'),
    );
    await downloadDirectory.create(recursive: true);

    final digest = currentInfo.sha256.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        currentInfo.fileSize <= 0 ||
        currentInfo.downloadSlug.trim().isEmpty) {
      throw const HttpException(
        'v40 release is missing valid size or SHA-256 metadata',
      );
    }
    final fileStem = _safeFileStem(currentInfo.releaseId);
    final partFile = File(
      path.join(
        downloadDirectory.path,
        '$fileStem-${digest.substring(0, 12)}.apk.part',
      ),
    );
    final targetFile = File(
      partFile.path.substring(0, partFile.path.length - 5),
    );
    final taskKey = '$_taskPrefix${currentInfo.releaseId}';

    await _discardMismatchedTask(
      taskKey: taskKey,
      partFile: partFile,
      releaseId: currentInfo.releaseId,
      slug: currentInfo.downloadSlug,
      sha256: digest,
      fileSize: currentInfo.fileSize,
    );

    final preferences = await SharedPreferences.getInstance();
    final savedTask = _readTask(preferences.getString(taskKey));
    await _saveTask(
      taskKey: taskKey,
      task: _V40Task(
        releaseId: currentInfo.releaseId,
        slug: currentInfo.downloadSlug,
        sha256: digest,
        fileSize: currentInfo.fileSize,
        etag: savedTask?.etag.isNotEmpty == true
            ? savedTask!.etag
            : currentInfo.downloadEtag,
        sessionId: savedTask?.sessionId ?? '',
        httpOrigin: savedTask?.httpOrigin ?? '',
        p2pContributed: savedTask?.p2pContributed ?? false,
        nonServiceContributed: savedTask?.nonServiceContributed ?? false,
      ),
    );
    File? bootstrapFile;
    CancelToken? bootstrapCancel;
    Future<bool>? bootstrapFlight;
    var bootstrapInitialBytes = 0;
    var bootstrapComplete = false, handoffRequested = false;
    final p2pCancel = CancelToken();
    unawaited(
      cancelToken.whenCancel.then((_) => p2pCancel.cancel('user_cancelled')),
    );
    if (httpsHeadStart &&
        isV40DownloadUrl(currentUrl, expectedSlug: currentInfo.downloadSlug)) {
      bootstrapFile = File('${partFile.path}.https-bootstrap');
      await _deleteIfExists(bootstrapFile);
      if (partFile.existsSync()) {
        await partFile.copy(bootstrapFile.path);
        final length = await partFile.length();
        bootstrapInitialBytes = length;
        if (length < currentInfo.fileSize) {
          final handle = await partFile.open(mode: FileMode.append);
          try {
            await handle.truncate(
              length ~/
                  AppUpgradeP2PManifest.chunkSize *
                  AppUpgradeP2PManifest.chunkSize,
            );
          } finally {
            await handle.close();
          }
        }
      }
      bootstrapCancel = CancelToken();
      final bootstrapToken = bootstrapCancel;
      unawaited(
        cancelToken.whenCancel.then(
          (_) => bootstrapToken.cancel('user_cancelled'),
        ),
      );
      bootstrapFlight =
          _downloadHttpsBootstrap(
            info: currentInfo,
            url: currentUrl,
            file: bootstrapFile,
            taskKey: taskKey,
            deviceId: deviceId,
            cancelToken: bootstrapToken,
            onProgress: onProgress,
            shouldHandoff: () => handoffRequested,
          ).then((complete) {
            bootstrapComplete = complete;
            if (complete) p2pCancel.cancel('https_completed');
            return complete;
          });
    }
    Future<void> stopBootstrap() async {
      if (handoffRequested) {
        await bootstrapFlight;
        return;
      }
      handoffRequested = true;
      if (bootstrapFile?.existsSync() == true &&
          await bootstrapFile!.length() % AppUpgradeP2PManifest.chunkSize ==
              0) {
        bootstrapCancel?.cancel('handoff_boundary');
      }
      // Finish the in-flight piece when the HTTP path is healthy. A stalled
      // HTTP stream must not hold an already open P2P channel indefinitely.
      final deadline = Timer(
        const Duration(seconds: 1),
        () => bootstrapCancel?.cancel('handoff_deadline'),
      );
      try {
        await bootstrapFlight;
      } finally {
        deadline.cancel();
      }
    }

    var httpsRejected = false;
    var p2pFileVerified = false;
    var httpsFileVerified = false;
    final contentionClock = Stopwatch()..start();
    int? p8pContentionWaitUntil;
    Future<bool> recoverP8PContention(
      Response<ResponseBody> response,
      String source,
      bool serviceHeaders,
      CancelToken token,
      String errorCode, {
      bool deferReservation = false,
    }) async {
      // This is OUR just-closed bootstrap, not permission to bypass a quota or
      // another task's live transfer. A P8P piece yields its reservation after
      // this bodyless rejection; regular HTTPS fallback keeps its own wait.
      if ((p8pContentionWaitUntil != null &&
              contentionClock.elapsedMicroseconds >= p8pContentionWaitUntil!) ||
          !handoffRequested ||
          _lastBootstrapBodyBytes == 0 ||
          !serviceHeaders ||
          Uri.parse(source).origin != Uri.parse(currentUrl).origin ||
          response.headers.value('x-download-deduplicated') != '1' ||
          response.headers.value('x-ratelimit-reason') !=
              'duplicate-in-flight' ||
          errorCode != 'duplicate_in_flight') {
        return false;
      }
      final seconds = _retryAfterSeconds(response.headers);
      if (seconds < 1 || seconds > 5) return false;
      final prefs = await SharedPreferences.getInstance();
      final task = _readTask(prefs.getString(taskKey));
      final session = response.headers.value('x-download-session-id')?.trim();
      if (task == null ||
          task.sessionId.isEmpty ||
          session != task.sessionId ||
          task.httpOrigin != Uri.parse(source).origin ||
          task.sha256 != digest ||
          task.fileSize != currentInfo.fileSize ||
          task.etag != currentInfo.downloadEtag) {
        return false;
      }
      if (p8pContentionWaitUntil != null &&
          contentionClock.elapsedMicroseconds >= p8pContentionWaitUntil!) {
        return false;
      }
      if (p8pContentionWaitUntil == null) {
        // Both bounded HTTP slots can meet the same just-closed bootstrap.
        // Share one bounded retry opportunity. Each rejected slot releases its
        // piece and honors its own full Retry-After. Rejections after the first
        // wait completes still fail; this is not a retry loop.
        p8pContentionWaitUntil =
            contentionClock.elapsedMicroseconds +
            Duration(seconds: seconds).inMicroseconds;
        _p2pClient.recordDownloadDiagnostic('https', 'p8p_contention_wait');
      }
      if (deferReservation) {
        throw P8PSourceDeferred(Duration(seconds: seconds));
      }
      await Future.any<void>([
        // A sibling may join a few milliseconds later. Each request still
        // honors its own full Retry-After before using the shared retry budget.
        Future<void>.delayed(Duration(seconds: seconds)),
        token.whenCancel.then<void>((_) {}),
      ]);
      if (token.isCancelled) throw token.cancelError!;
      return true;
    }

    Future<Uint8List> readP8PRange(
      int index,
      CancelToken token, [
      void Function(int)? receivedBytes,
    ]) => _readP8PPiece(
      info: currentInfo,
      url: currentUrl,
      deviceId: deviceId,
      index: index,
      cancelToken: token,
      recoverContention: (response, source, serviceHeaders, token, errorCode) =>
          recoverP8PContention(
            response,
            source,
            serviceHeaders,
            token,
            errorCode,
            deferReservation: true,
          ),
      onReceived: receivedBytes,
    );

    try {
      await _p2pClient.downloadVerifiedPrefix(
        downloadUrl: currentUrl,
        expectedSlug: currentInfo.downloadSlug,
        expectedVersion: currentInfo.versionName,
        expectedVersionCode: currentInfo.downloadVersionCode,
        expectedFileSize: currentInfo.fileSize,
        expectedSha256: digest,
        partFile: partFile,
        onProgress: onProgress,
        cancelToken: p2pCancel,
        beforeP2PWrite: () => _markP2PContribution(taskKey),
        bootstrapReceivedBytes: httpsHeadStart
            ? () => _lastBootstrapBodyBytes
            : null,
        bootstrapPiece: bootstrapFlight == null
            ? null
            : (index) async {
                await stopBootstrap();
                if (cancelToken.isCancelled ||
                    httpsRejected ||
                    !bootstrapFile!.existsSync()) {
                  return null;
                }
                final start = index * AppUpgradeP2PManifest.chunkSize;
                final end = (start + AppUpgradeP2PManifest.chunkSize).clamp(
                  0,
                  currentInfo.fileSize,
                );
                if (await bootstrapFile.length() < end) return null;
                // Dart 3.11 promotes this value after the length check above;
                // retain the upstream read while avoiding a redundant bang.
                final bytes = await bootstrapFile
                    .openRead(start, end)
                    .fold<BytesBuilder>(
                      BytesBuilder(copy: false),
                      (builder, chunk) => builder..add(chunk),
                    );
                return bytes.takeBytes();
              },
        bootstrapRejected: () => httpsRejected = true,
        bootstrapInitialBytes: bootstrapInitialBytes,
        bootstrapHandoff: bootstrapFlight == null ? null : stopBootstrap,
        p8pRangePiece: readP8PRange,
        p8pProgressRangePiece: readP8PRange,
        onFileVerified: () => p2pFileVerified = true,
      );
    } on DioException {
      if (!bootstrapComplete || cancelToken.isCancelled) rethrow;
    } finally {
      if (cancelToken.isCancelled) bootstrapCancel?.cancel('user_cancelled');
      // Without a usable channel, keep the SAME HTTPS stream running. If the
      // channel fails after handoff, normal HTTPS resumes from the P2P prefix.
      await bootstrapFlight;
      if (!cancelToken.isCancelled &&
          !httpsRejected &&
          bootstrapFile?.existsSync() == true &&
          !_p2pClient.lastDownloadUsedP2P) {
        final length = await bootstrapFile!.length();
        final current = partFile.existsSync() ? await partFile.length() : 0;
        if (length > current ||
            (bootstrapComplete && length == currentInfo.fileSize)) {
          // Both writers have returned; P2P never writes the bootstrap file.
          // Rename the same closed, verified file rather than copying it and
          // immediately hashing it again. A copy fallback earns no receipt.
          final moved = await promoteAppUpgradeHttpsFile(
            bootstrapFile,
            partFile,
          );
          httpsFileVerified =
              moved && bootstrapComplete && length == currentInfo.fileSize;
          _p2pClient.recordDownloadDiagnostic(
            'https',
            moved ? 'https_file_promoted' : 'https_file_copied',
          );
        }
      }
      if (bootstrapFile != null) await _deleteIfExists(bootstrapFile);
      if (_p2pClient.lastDownloadUsedP2P) await _markP2PContribution(taskKey);
    }
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    if (!metadataRefreshed && _p2pClient.lastDownloadMetadataMismatch) {
      // The coordinator callback reauthorizes the business release, then reads
      // fresh public health. A changing APK cannot be inferred from manifest
      // alone, and a failed refresh never adopts unverified manifest metadata.
      AppUpgradeInfo? refreshed;
      try {
        refreshed = await refreshRelease().timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      if (refreshed != null &&
          refreshed.releaseId == currentInfo.releaseId &&
          refreshed.versionCode == currentInfo.versionCode &&
          refreshed.downloadProtocol == 'APK_SERVICE_V40' &&
          refreshed.downloadSlug == currentInfo.downloadSlug &&
          isV40DownloadUrl(
            refreshed.downloadUrl,
            expectedSlug: currentInfo.downloadSlug,
          ) &&
          refreshed.fileSize > 0 &&
          RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(refreshed.sha256) &&
          (refreshed.fileSize != currentInfo.fileSize ||
              refreshed.sha256.toLowerCase() != digest ||
              refreshed.versionName != currentInfo.versionName ||
              refreshed.downloadVersionCode !=
                  currentInfo.downloadVersionCode)) {
        await _clearTask(taskKey, partFile);
        _p2pClient.recordDownloadDiagnostic(
          'metadata',
          'release_metadata_refreshed',
        );
        return _download(
          info: refreshed,
          url: refreshed.downloadUrl,
          backupUrl: refreshed.downloadBackupUrl.isEmpty
              ? null
              : refreshed.downloadBackupUrl,
          refreshRelease: refreshRelease,
          onProgress: onProgress,
          cancelToken: cancelToken,
          metadataRefreshed: true,
        );
      }
    }
    if (partFile.existsSync() &&
        await partFile.length() == currentInfo.fileSize) {
      // P2P closes its writer before the full-file hash. This branch never
      // adopts bootstrap bytes over a P2P-contributed file. A full HTTPS receipt
      // belongs only to the exact closed file renamed above in this call.
      // Partial files, copies and every resumed/new task still need a full hash;
      // the coordinator independently hashes again before installation.
      final reuseP2PHash = p2pFileVerified && _p2pClient.lastDownloadUsedP2P;
      if (reuseP2PHash ||
          httpsFileVerified ||
          await _matchesSha256(partFile, digest)) {
        if (reuseP2PHash) {
          _p2pClient.recordDownloadDiagnostic('final', 'verified_hash_reused');
        } else if (httpsFileVerified) {
          _p2pClient.recordDownloadDiagnostic(
            'final',
            'verified_https_hash_reused',
          );
        }
        await _reportVerified(info, currentUrl);
        await _deleteIfExists(targetFile);
        await partFile.rename(targetFile.path);
        await SharedPreferences.getInstance().then(
          (prefs) => prefs.remove(taskKey),
        );
        return targetFile;
      }
      await _clearTask(taskKey, partFile);
    }

    Object? lastError;
    String? releasedTransferOrigin;
    var contentionRecoveryUsed = false;
    attemptLoop:
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final preferences = await SharedPreferences.getInstance();
      final task = _readTask(preferences.getString(taskKey));
      final offset = partFile.existsSync() ? await partFile.length() : 0;
      if (currentInfo.fileSize > 0 && offset > currentInfo.fileSize) {
        await _clearTask(taskKey, partFile);
      }

      final sessionId = task?.sessionId ?? '';
      final candidates = redirectedHttpsSource != null
          ? [redirectedHttpsSource]
          : _sourceCandidates(
              currentUrl,
              currentBackupUrl,
              currentInfo.downloadSlug,
            );
      var requestSucceeded = false;

      for (final candidate in candidates) {
        final external = !isV40DownloadUrl(
          candidate,
          expectedSlug: currentInfo.downloadSlug,
        );
        final origin = Uri.parse(candidate).origin;
        final diagnosticSource = external
            ? 'cos'
            : Uri.parse(candidate).host == 'download1.csnas.asia'
            ? 'service_backup'
            : 'service_main';
        // ETags belong to an HTTP origin. A COS object can have the same APK
        // digest and a different ETag; never send a service ETag to COS.
        final sameSource =
            task?.httpOrigin == origin ||
            (!external && (task?.httpOrigin.isEmpty ?? true));
        final etag = sameSource
            ? task?.etag ?? currentInfo.downloadEtag
            : external
            ? ''
            : currentInfo.downloadEtag;
        final requestedOffset = partFile.existsSync()
            ? await partFile.length()
            : 0;
        Response<ResponseBody> response;
        final requestCancel = CancelToken();
        unawaited(
          cancelToken.whenCancel.then((reason) {
            if (!requestCancel.isCancelled) requestCancel.cancel(reason);
          }),
        );
        try {
          response = await _request(
            url: candidate,
            offset: requestedOffset,
            etag: etag,
            deviceId: deviceId,
            sessionId: external ? "" : sessionId,
            attachServiceHeaders: !external,
            cancelToken: requestCancel,
          );
        } on DioException catch (error) {
          requestCancel.cancel('request_failed');
          if (CancelToken.isCancel(error)) rethrow;
          _p2pClient.recordDownloadDiagnostic(
            'https',
            'network_error',
            source: diagnosticSource,
          );
          lastError = error;
          continue;
        }

        final status = response.statusCode ?? 0;
        try {
          _p2pClient.recordDownloadDiagnostic(
            'https',
            'http_response',
            status: status,
            source: diagnosticSource,
          );
          if (_isRedirect(status)) {
            final location = response.headers.value(HttpHeaders.locationHeader);
            final redirected = location == null
                ? null
                : Uri.tryParse(candidate)?.resolve(location).toString();
            await _discardResponse(response);
            if (redirected != null &&
                isV40DownloadUrl(
                  redirected,
                  expectedSlug: currentInfo.downloadSlug,
                )) {
              currentUrl = redirected;
              requestSucceeded = true;
              break;
            }
            final target = Uri.tryParse(redirected ?? '');
            if (target != null &&
                target.scheme == 'https' &&
                target.host.isNotEmpty &&
                target.userInfo.isEmpty &&
                target.port == 443) {
              // The service can explicitly select its COS fallback. Resume only
              // with this origin's ETag and no service identity/session headers;
              // final size/SHA checks still use the backend's selected release.
              redirectedHttpsSource = target.toString();
              currentUrl = redirectedHttpsSource;
              requestSucceeded = true;
              break;
            }
            lastError = const HttpException(
              'download redirect is not a safe HTTPS URL',
            );
            continue;
          }
          if (status >= 500) {
            await _discardResponse(response);
            lastError = HttpException(
              'v40 download service returned HTTP $status',
            );
            continue;
          }
          if (status == 429) {
            final retryAfter = _retryAfterSeconds(response.headers);
            final errorCode = await _readErrorCode(response);
            if (await recoverP8PContention(
              response,
              candidate,
              !external,
              requestCancel,
              errorCode,
            )) {
              requestCancel.cancel('contention_response_finished');
              redirectedHttpsSource = candidate;
              continue attemptLoop;
            }
            final transient =
                errorCode == 'duplicate_in_flight' ||
                errorCode == 'concurrent_download_limit';
            _p2pClient.recordDownloadDiagnostic(
              'https',
              transient ? 'transient_download_limit' : 'download_quota_limit',
            );
            // Only recover once after OUR preceding transfer has been released,
            // preserving its persisted prefix. A first-request 429 may belong to
            // another device: waiting alone does not prove its in-flight task ended.
            // Do not switch origins or repeatedly probe an occupied connection slot.
            if (transient &&
                !external &&
                !contentionRecoveryUsed &&
                requestedOffset > 0 &&
                releasedTransferOrigin == origin &&
                retryAfter <= 5 &&
                attempt < _maxAttempts) {
              contentionRecoveryUsed = true;
              requestCancel.cancel('contention_response_finished');
              await Future.any<void>([
                Future<void>.delayed(
                  Duration(seconds: retryAfter > 0 ? retryAfter : 2),
                ),
                cancelToken.whenCancel.then<void>((_) {}),
              ]);
              if (cancelToken.isCancelled) throw cancelToken.cancelError!;
              redirectedHttpsSource = candidate;
              continue attemptLoop;
            }
            throw AppUpgradeV40RateLimitException(
              retryAfterSeconds: retryAfter,
            );
          }
          if (status == 416) {
            await _discardResponse(response);
            if (resetAfterRangeError) {
              throw const HttpException(
                'v40 server rejected a clean download range',
              );
            }
            resetAfterRangeError = true;
            await _clearTask(taskKey, partFile);
            requestSucceeded = true;
            break;
          }
          if (status == 409) {
            final errorCode = await _readErrorCode(response);
            if (errorCode == 'application_package_conflict') {
              throw const HttpException('application_package_conflict');
            }
            if (errorCode == 'download_session_invalid' &&
                !refreshedAfterInvalidSession) {
              refreshedAfterInvalidSession = true;
              final refreshed = await refreshRelease();
              if (refreshed == null ||
                  refreshed.releaseId != currentInfo.releaseId ||
                  refreshed.sha256.toLowerCase() !=
                      currentInfo.sha256.toLowerCase()) {
                throw const HttpException(
                  'app upgrade release changed during resume',
                );
              }
              currentInfo = refreshed;
              currentUrl = _absoluteUrl(refreshed.downloadUrl);
              currentBackupUrl = refreshed.downloadBackupUrl.trim().isEmpty
                  ? null
                  : _absoluteUrl(refreshed.downloadBackupUrl);
              await _clearTask(taskKey, partFile);
              requestSucceeded = true;
              break;
            }
            throw HttpException('v40 download rejected: $errorCode');
          }
          if (status != 200 && status != 206) {
            final errorCode = await _readErrorCode(response);
            throw HttpException(
              'v40 download returned HTTP $status: $errorCode',
            );
          }

          try {
            await _consumeSuccessResponse(
              response: response,
              partFile: partFile,
              taskKey: taskKey,
              releaseId: currentInfo.releaseId,
              slug: currentInfo.downloadSlug,
              sha256: currentInfo.sha256.toLowerCase(),
              expectedBytes: currentInfo.fileSize,
              expectedEtag: etag,
              requestedOffset: requestedOffset,
              onProgress: onProgress,
            );
            requestSucceeded = true;
            break;
          } on Object catch (error) {
            if (error is DioException && CancelToken.isCancel(error)) rethrow;
            _p2pClient.recordDownloadDiagnostic(
              'https',
              _responseFailureCode(error),
              source: diagnosticSource,
            );
            lastError = error;
          }
        } finally {
          // Includes header, state persistence and file-open failures that occur
          // before listening to the response body. Close the transport before
          // another source is attempted; cancelling only a subscription misses
          // those paths. Never cancel the user's token for recoverable errors.
          requestCancel.cancel('response_finished');
          if (status == 200 || status == 206) releasedTransferOrigin = origin;
        }
      }

      if (requestSucceeded) {
        if (!partFile.existsSync()) {
          continue;
        }
        final actualBytes = await partFile.length();
        onProgress(actualBytes, currentInfo.fileSize);
        if (currentInfo.fileSize > 0 && actualBytes < currentInfo.fileSize) {
          lastError = HttpException(
            'incomplete v40 package: $actualBytes/${currentInfo.fileSize}',
          );
          if (attempt < _maxAttempts) {
            await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
            continue;
          }
          break;
        }
        if (currentInfo.fileSize > 0 && actualBytes > currentInfo.fileSize) {
          await _clearTask(taskKey, partFile);
          throw HttpException(
            'v40 package size exceeded: $actualBytes/${currentInfo.fileSize}',
          );
        }
        if (await _matchesSha256(partFile, currentInfo.sha256)) {
          await _reportVerified(currentInfo, currentUrl);
          await _deleteIfExists(targetFile);
          await partFile.rename(targetFile.path);
          await SharedPreferences.getInstance().then(
            (prefs) => prefs.remove(taskKey),
          );
          return targetFile;
        }
        final context = await _eventContext(currentInfo, currentUrl);
        if (context != null) {
          unawaited(
            serviceEvents.enqueue(
              context,
              'checksum_fail',
              errorCode: 'checksum_mismatch',
            ),
          );
        }
        await _clearTask(taskKey, partFile);
        throw const HttpException('v40 package checksum mismatch');
      }

      if (attempt < _maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    throw HttpException('v40 APK download failed after retries: $lastError');
  }

  String _eventContextKey(String releaseId) =>
      "$_taskPrefix$releaseId.event_context";

  Future<bool> _downloadHttpsBootstrap({
    required AppUpgradeInfo info,
    required String url,
    required File file,
    required String taskKey,
    required String deviceId,
    required CancelToken cancelToken,
    required void Function(int, int) onProgress,
    required bool Function() shouldHandoff,
  }) async {
    final offset = file.existsSync() ? await file.length() : 0;
    if (offset == info.fileSize) return await _matchesSha256(file, info.sha256);
    var currentUrl = url;
    var serviceHeaders = true;
    try {
      // Follow the service's selected source, retaining Range but never sending
      // service identity or an origin's ETag to external object storage.
      for (var hop = 0; hop <= 5; hop++) {
        if (cancelToken.isCancelled) return false;
        final etag = serviceHeaders ? info.downloadEtag : '';
        final source = serviceHeaders
            ? Uri.parse(currentUrl).host == 'download1.csnas.asia'
                  ? 'service_backup'
                  : 'service_main'
            : 'cos';
        final response = await _request(
          url: currentUrl,
          offset: offset,
          endOffset: info.fileSize - 1,
          etag: etag,
          deviceId: deviceId,
          sessionId: '',
          attachServiceHeaders: serviceHeaders,
          cancelToken: cancelToken,
        );
        final status = response.statusCode ?? 0;
        _p2pClient.recordDownloadDiagnostic(
          'https',
          'http_response',
          status: status,
          source: source,
        );
        if (_isRedirect(status)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          final target = location == null
              ? null
              : Uri.tryParse(currentUrl)?.resolve(location);
          await _discardResponse(response);
          if (hop == 5 ||
              target == null ||
              target.scheme != 'https' ||
              target.host.isEmpty ||
              target.userInfo.isNotEmpty ||
              target.port != 443) {
            throw const HttpException('unsafe or excessive HTTPS redirects');
          }
          currentUrl = target.toString();
          serviceHeaders =
              serviceHeaders &&
              isV40DownloadUrl(currentUrl, expectedSlug: info.downloadSlug);
          continue;
        }
        final range = parseContentRange(
          response.headers.value(HttpHeaders.contentRangeHeader),
        );
        // A full 200 is safe only for a clean start. For a saved prefix keep
        // exact 206 validation so old bytes cannot be spliced into a full body.
        final validPartial =
            status == 206 &&
            range != null &&
            range.start == offset &&
            range.end == info.fileSize - 1 &&
            range.total == info.fileSize;
        if (!validPartial && !(status == 200 && offset == 0)) {
          await _discardResponse(response);
          throw const HttpException('HTTPS bootstrap response rejected');
        }
        await _consumeSuccessResponse(
          response: response,
          partFile: file,
          taskKey: taskKey,
          releaseId: info.releaseId,
          slug: info.downloadSlug,
          sha256: info.sha256.toLowerCase(),
          expectedBytes: info.fileSize,
          expectedEtag: etag,
          requestedOffset: offset,
          onProgress: onProgress,
          progressFlushBytes: 64 * 1024,
          onBodyBytes: (count) => _lastBootstrapBodyBytes += count,
          bodyCancelToken: cancelToken,
          shouldHandoff: shouldHandoff,
        );
        return await file.length() == info.fileSize &&
            await _matchesSha256(file, info.sha256);
      }
      return false;
    } catch (error) {
      if (!cancelToken.isCancelled) {
        _p2pClient.recordDownloadDiagnostic(
          'https',
          _responseFailureCode(error),
        );
      }
      return false; // Regular P2P/HTTPS recovery retains its existing policy.
    } finally {
      cancelToken.cancel('https_stream_finished');
    }
  }

  Future<Uint8List> _readP8PPiece({
    required AppUpgradeInfo info,
    required String url,
    required String deviceId,
    required int index,
    required CancelToken cancelToken,
    void Function(int)? onReceived,
    required Future<bool> Function(
      Response<ResponseBody>,
      String,
      bool,
      CancelToken,
      String,
    )
    recoverContention,
  }) async {
    if (!isV40DownloadUrl(url, expectedSlug: info.downloadSlug) || index < 0) {
      throw const HttpException('P8P requires a trusted hosted release');
    }
    final start = index * AppUpgradeP2PManifest.chunkSize;
    final end =
        (start + AppUpgradeP2PManifest.chunkSize).clamp(0, info.fileSize) - 1;
    if (start > end) throw const HttpException('Invalid P8P piece index');
    var current = url;
    var serviceHeaders = true;
    for (var hop = 0; hop <= 5;) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final etag = serviceHeaders ? info.downloadEtag : '';
      final response = await _request(
        url: current,
        offset: start,
        endOffset: end,
        etag: etag,
        deviceId: deviceId,
        sessionId: '',
        attachServiceHeaders: serviceHeaders,
        cancelToken: cancelToken,
      );
      final status = response.statusCode ?? 0;
      if (status == 429 &&
          await recoverContention(
            response,
            current,
            serviceHeaders,
            cancelToken,
            await _readErrorCode(response),
          )) {
        continue;
      }
      if (_isRedirect(status)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final target = location == null
            ? null
            : Uri.parse(current).resolve(location);
        await _discardResponse(response);
        if (hop == 5 ||
            target == null ||
            target.scheme != 'https' ||
            target.host.isEmpty ||
            target.userInfo.isNotEmpty ||
            target.port != 443 ||
            target.fragment.isNotEmpty) {
          throw const HttpException('Unsafe P8P HTTPS redirect');
        }
        current = target.toString();
        serviceHeaders =
            serviceHeaders &&
            isV40DownloadUrl(current, expectedSlug: info.downloadSlug);
        hop++;
        continue;
      }
      final range = parseContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      final contentLength = response.headers.value(
        HttpHeaders.contentLengthHeader,
      );
      final coding = response.headers.value(HttpHeaders.contentEncodingHeader);
      if (status != 206 ||
          range == null ||
          range.start != start ||
          range.end != end ||
          range.total != info.fileSize ||
          (contentLength != null &&
              int.tryParse(contentLength) != end - start + 1) ||
          (coding != null && coding.toLowerCase() != 'identity') ||
          (etag.isNotEmpty &&
              response.headers.value(HttpHeaders.etagHeader)?.trim() != etag)) {
        await _discardResponse(response);
        throw const HttpException('P8P Content-Range or identity mismatch');
      }
      final body = response.data;
      if (body == null) throw const HttpException('Empty P8P response');
      final bytes = Uint8List(end - start + 1);
      final iterator = StreamIterator<Uint8List>(body.stream);
      var received = 0;
      try {
        while (await Future.any<bool>([
          iterator.moveNext(),
          cancelToken.whenCancel.then<bool>((error) => throw error),
        ]).timeout(const Duration(seconds: 8))) {
          if (cancelToken.isCancelled) throw cancelToken.cancelError!;
          final frame = iterator.current;
          _lastHttpsBodyBytes += frame.length;
          if (received + frame.length > bytes.length) {
            throw const HttpException('P8P body exceeded piece');
          }
          bytes.setRange(received, received + frame.length, frame);
          received += frame.length;
          onReceived?.call(received);
        }
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        if (received != bytes.length) {
          throw const HttpException('P8P body length mismatch');
        }
        return bytes;
      } finally {
        await iterator.cancel();
      }
    }
    throw const HttpException('P8P HTTPS redirect limit');
  }

  String _responseFailureCode(Object error) {
    if (error is FileSystemException) return 'local_storage_error';
    if (error is DioException) return 'network_error';
    if (error is HttpException) {
      if (error.message.contains('ETag changed')) return 'https_etag_mismatch';
      if (error.message.contains('Content-Range')) {
        return 'https_range_mismatch';
      }
      if (error.message.contains('exceeded')) return 'https_body_oversized';
      if (error.message.contains('body length mismatch')) {
        return 'https_body_incomplete';
      }
    }
    return 'https_response_rejected';
  }

  Future<Map<String, Object?>?> _eventContext(
    AppUpgradeInfo info,
    String url,
  ) async {
    if (!isV40DownloadUrl(url, expectedSlug: info.downloadSlug)) return null;
    final prefs = await SharedPreferences.getInstance();
    final task = _readTask(prefs.getString('$_taskPrefix${info.releaseId}'));
    if (task == null ||
        task.sessionId.isEmpty ||
        task.p2pContributed ||
        task.nonServiceContributed ||
        !isV40DownloadUrl(
          '${task.httpOrigin}/${task.slug}/download',
          expectedSlug: task.slug,
        )) {
      return null;
    }
    return {
      // The saved HTTP source owns the session, even when a backup took over.
      'origin': task.httpOrigin,
      'slug': task.slug,
      'sha256': task.sha256,
      'session_id': task.sessionId,
    };
  }

  Future<void> _reportVerified(AppUpgradeInfo info, String url) async {
    try {
      final context = await _eventContext(info, url);
      final prefs = await SharedPreferences.getInstance();
      if (context == null) {
        // Clear a context left by an earlier HTTP-only attempt. The server's
        // byte-coverage proof cannot include any peer/seed-supplied bytes.
        await prefs.remove(_eventContextKey(info.releaseId));
        return;
      }
      await prefs.setString(
        _eventContextKey(info.releaseId),
        jsonEncode(context),
      );
      final duration =
          (_savedActiveMs + (_activeWatch?.elapsedMilliseconds ?? 0)).clamp(
            1,
            604800000,
          );
      // Disk persistence is bounded; network transmission is never awaited here.
      await serviceEvents.enqueue(
        context,
        'download_complete',
        bytes: info.fileSize,
        durationMs: duration,
      );
      await serviceEvents.enqueue(context, 'checksum_pass');
    } catch (_) {}
  }

  Future<void> _markP2PContribution(String taskKey) async {
    final prefs = await SharedPreferences.getInstance();
    final task = _readTask(prefs.getString(taskKey));
    if (task == null || task.p2pContributed) return;
    await _saveTask(
      taskKey: taskKey,
      task: _V40Task(
        releaseId: task.releaseId,
        slug: task.slug,
        sha256: task.sha256,
        fileSize: task.fileSize,
        etag: task.etag,
        sessionId: task.sessionId,
        httpOrigin: task.httpOrigin,
        p2pContributed: true,
        nonServiceContributed: task.nonServiceContributed,
      ),
    );
  }

  Future<void> _reportFailure(
    AppUpgradeInfo info,
    bool cancelled,
    Object error,
  ) async {
    final context = await _eventContext(info, info.downloadUrl);
    if (context == null) return;
    final checksum =
        error is HttpException && error.message.contains('checksum mismatch');
    int? persistedBytes;
    int? durationMs;
    if (!checksum) {
      try {
        final directory = await _supportDirectoryLoader();
        final digest = info.sha256.trim().toLowerCase();
        final partFile = File(
          path.join(
            directory.path,
            'app-upgrades',
            '${_safeFileStem(info.releaseId)}-${digest.substring(0, 12)}.apk.part',
          ),
        );
        persistedBytes = (await partFile.exists() ? await partFile.length() : 0)
            .clamp(0, info.fileSize);
        durationMs = (_savedActiveMs + (_activeWatch?.elapsedMilliseconds ?? 0))
            .clamp(0, 604800000);
      } catch (_) {
        // Telemetry must not mask the download error if storage is unavailable.
      }
    }
    await serviceEvents.enqueue(
      context,
      cancelled
          ? 'user_cancelled'
          : checksum
          ? 'checksum_fail'
          : 'download_failed',
      bytes: persistedBytes,
      durationMs: durationMs,
      errorCode: cancelled
          ? null
          : checksum
          ? 'checksum_mismatch'
          : error is FileSystemException
          ? 'local_storage_error'
          : 'network_error',
    );
  }

  Future<void> rememberVerifiedInstallation(AppUpgradeInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_eventContextKey(info.releaseId));
      if (raw == null) return;
      await serviceEvents.rememberInstall(
        Map<String, Object?>.from(jsonDecode(raw)),
        info.downloadVersionCode ?? info.versionCode,
      );
    } catch (_) {}
  }

  Future<void> reportInstallationFailure(AppUpgradeInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_eventContextKey(info.releaseId));
      if (raw == null) return;
      await serviceEvents.enqueue(
        Map<String, Object?>.from(jsonDecode(raw)),
        'install_fail',
        errorCode: 'install_blocked',
      );
    } catch (_) {}
  }

  /// Validates a service endpoint before attaching its device or session headers.
  static bool isV40DownloadUrl(String rawUrl, {required String expectedSlug}) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !_allowedHosts.contains(uri.host.toLowerCase()) ||
        (uri.hasPort && uri.port != 443) ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/$expectedSlug/download') {
      return false;
    }
    return expectedSlug.isNotEmpty &&
        RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(expectedSlug);
  }

  Future<Response<ResponseBody>> _request({
    required String url,
    required int offset,
    required String etag,
    required String deviceId,
    required String sessionId,
    required CancelToken cancelToken,
    bool attachServiceHeaders = true,
    int? endOffset,
  }) async {
    final headers = <String, Object?>{
      HttpHeaders.acceptHeader:
          'application/vnd.android.package-archive, application/json',
      if (attachServiceHeaders) ...{
        'X-Device-Id': deviceId,
        'X-Client-App-Version': await AppUpgradeP2PDiagnostics.clientVersion(),
      },
    };
    if (offset > 0 || sessionId.isNotEmpty || endOffset != null) {
      headers[HttpHeaders.rangeHeader] = 'bytes=$offset-${endOffset ?? ''}';
      if (etag.isNotEmpty) headers[HttpHeaders.ifRangeHeader] = etag;
      if (sessionId.isNotEmpty) headers['X-Download-Session-Id'] = sessionId;
    }
    return _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: false,
        validateStatus: (_) => true,
        headers: headers,
      ),
    );
  }

  Future<void> _consumeSuccessResponse({
    required Response<ResponseBody> response,
    required File partFile,
    required String taskKey,
    required String releaseId,
    required String slug,
    required String sha256,
    required int expectedBytes,
    required String expectedEtag,
    required int requestedOffset,
    required void Function(int received, int total) onProgress,
    int progressFlushBytes = 1024 * 1024,
    void Function(int count)? onBodyBytes,
    CancelToken? bodyCancelToken,
    bool Function()? shouldHandoff,
  }) async {
    final status = response.statusCode ?? 0;
    final responseEtag =
        response.headers.value(HttpHeaders.etagHeader)?.trim() ?? '';
    final responseOrigin = response.requestOptions.uri.origin;
    final serviceResponse = isV40DownloadUrl(
      response.requestOptions.uri.toString(),
      expectedSlug: slug,
    );
    final sessionId = serviceResponse
        ? response.headers.value('x-download-session-id')?.trim() ?? ''
        : '';
    var writeOffset = requestedOffset;
    var append = status == 206;

    if (status == 206) {
      final range = parseContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      if (range == null ||
          range.start != requestedOffset ||
          (expectedBytes > 0 && range.total != expectedBytes) ||
          range.end < range.start) {
        await _discardResponse(response);
        throw const HttpException(
          'v40 Content-Range does not match the saved prefix',
        );
      }
      if (expectedEtag.isNotEmpty && responseEtag != expectedEtag) {
        await _discardResponse(response);
        throw const HttpException('v40 ETag changed during resume');
      }
      writeOffset = requestedOffset;
      append = true;
    } else {
      // A 200 response always starts a new full-file write, even if a part already exists.
      writeOffset = 0;
      append = false;
      if (expectedEtag.isNotEmpty && responseEtag != expectedEtag) {
        await _discardResponse(response);
        throw const HttpException(
          'v40 ETag changed; recheck the published release',
        );
      }
    }

    final previousTask = _readTask(
      (await SharedPreferences.getInstance()).getString(taskKey),
    );
    final body = response.data;
    if (body == null) {
      throw const HttpException('v40 download response has no body');
    }
    // A successful 200 truncation removes all previous contributions. Persist
    // its new provenance only afterwards. For 206, retain every prior source.
    final handle = await partFile.open(
      mode: append ? FileMode.append : FileMode.write,
    );
    final range = status == 206
        ? parseContentRange(
            response.headers.value(HttpHeaders.contentRangeHeader),
          )
        : null;
    final responseBytes = range == null
        ? expectedBytes
        : range.end - range.start + 1;
    var bytesSinceFlush = 0;
    var bytesWritten = 0;
    final chunks = StreamIterator(body.stream);
    try {
      await _saveTask(
        taskKey: taskKey,
        task: _V40Task(
          releaseId: releaseId,
          slug: slug,
          sha256: sha256,
          fileSize: expectedBytes,
          etag: responseEtag.isNotEmpty ? responseEtag : expectedEtag,
          sessionId: sessionId.isNotEmpty
              ? sessionId
              : previousTask?.sessionId ?? '',
          httpOrigin: responseOrigin,
          p2pContributed: append && (previousTask?.p2pContributed ?? false),
          nonServiceContributed:
              !serviceResponse ||
              (append && (previousTask?.nonServiceContributed ?? false)),
        ),
      );
      while (await (bodyCancelToken == null
          ? chunks.moveNext()
          : Future.any<bool>([
              chunks.moveNext(),
              bodyCancelToken.whenCancel.then<bool>(
                (_) => throw bodyCancelToken.cancelError!,
              ),
            ]).timeout(const Duration(seconds: 5)))) {
        if (bodyCancelToken?.isCancelled == true) {
          throw bodyCancelToken!.cancelError!;
        }
        final chunk = chunks.current;
        _lastHttpsBodyBytes += chunk.length;
        onBodyBytes?.call(chunk.length);
        if (bytesWritten + chunk.length > responseBytes ||
            writeOffset + bytesWritten + chunk.length > expectedBytes) {
          throw const HttpException(
            'v40 response exceeded the advertised APK range',
          );
        }
        var cursor = 0;
        while (cursor < chunk.length) {
          final position = writeOffset + bytesWritten;
          final boundary =
              AppUpgradeP2PManifest.chunkSize -
              position % AppUpgradeP2PManifest.chunkSize;
          final count = (chunk.length - cursor).clamp(0, boundary);
          await handle.writeFrom(chunk, cursor, cursor + count);
          cursor += count;
          bytesWritten += count;
          bytesSinceFlush += count;
          final received = writeOffset + bytesWritten;
          if (bytesSinceFlush >= progressFlushBytes) {
            await handle.flush();
            bytesSinceFlush = 0;
            onProgress(received, expectedBytes);
          }
          if (shouldHandoff?.call() == true &&
              received % AppUpgradeP2PManifest.chunkSize == 0) {
            await handle.flush();
            return;
          }
        }
      }
      await handle.flush();
      onProgress(writeOffset + bytesWritten, expectedBytes);
    } finally {
      try {
        await chunks.cancel();
      } finally {
        await handle.close();
      }
    }

    if (status == 206) {
      final range = parseContentRange(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      final expectedChunkBytes = range == null
          ? -1
          : range.end - range.start + 1;
      if (expectedChunkBytes >= 0 && bytesWritten != expectedChunkBytes) {
        throw HttpException(
          'v40 range body length mismatch: $bytesWritten/$expectedChunkBytes',
        );
      }
    }
  }

  Future<void> _discardMismatchedTask({
    required String taskKey,
    required File partFile,
    required String releaseId,
    required String slug,
    required String sha256,
    required int fileSize,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final existing = _readTask(preferences.getString(taskKey));
    if (existing == null ||
        existing.releaseId != releaseId ||
        existing.slug != slug ||
        existing.sha256 != sha256 ||
        existing.fileSize != fileSize) {
      // The new digest uses a new filename. Delete only the previous task's
      // validated local filename, never a server-provided path or another release.
      if (existing != null &&
          existing.releaseId == releaseId &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(existing.sha256)) {
        final oldPart = File(
          path.join(
            partFile.parent.path,
            '${_safeFileStem(releaseId)}-${existing.sha256.substring(0, 12)}.apk.part',
          ),
        );
        if (oldPart.path != partFile.path) await _deleteIfExists(oldPart);
      }
      await preferences.remove('$taskKey.event_context');
      await _clearTask(taskKey, partFile);
    }
  }

  Future<String> _loadOrCreateDeviceId() => AppUpgradeP2PIdentity.deviceId();

  Future<void> _saveTask({
    required String taskKey,
    required _V40Task task,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(taskKey, jsonEncode(task.toJson()))) {
      throw const FileSystemException('download task persistence failed');
    }
  }

  _V40Task? _readTask(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return _V40Task.fromJson(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> _clearTask(String taskKey, File partFile) async {
    await SharedPreferences.getInstance().then(
      (prefs) => prefs.remove(taskKey),
    );
    await _deleteIfExists(partFile);
  }

  Future<void> _discardResponse(Response<ResponseBody> response) async {
    try {
      // Error/redirect bodies are not APK data. Cancel them immediately so a
      // slow or oversized error page cannot hold up the next download source.
      await response.data?.stream.listen((_) {}).cancel();
    } catch (_) {}
  }

  Future<String> _readErrorCode(Response<ResponseBody> response) async {
    try {
      final bytes = <int>[];
      final stream = response.data?.stream;
      if (stream != null) {
        final done = Completer<void>();
        void finish() {
          if (!done.isCompleted) done.complete();
        }

        final timer = Timer(const Duration(seconds: 2), finish);
        final subscription = stream.listen(
          (chunk) {
            if (done.isCompleted) return;
            bytes.addAll(chunk.take(2048 - bytes.length));
            if (bytes.length >= 2048) finish();
          },
          onDone: finish,
          onError: (Object _) => finish(),
        );
        try {
          await done.future;
        } finally {
          timer.cancel();
          // Cancelling an ill-behaved response must itself remain bounded.
          await subscription.cancel().timeout(const Duration(seconds: 2));
        }
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) {
        return (decoded['error'] ?? decoded['code'] ?? decoded['message'] ?? '')
            .toString();
      }
    } catch (_) {}
    return '';
  }

  List<String> _sourceCandidates(String primary, String? backup, String slug) {
    final candidates = <String>[];
    bool allowed(String value) {
      if (isV40DownloadUrl(value, expectedSlug: slug)) return true;
      final uri = Uri.tryParse(value);
      return allowExternalHttps &&
          uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          uri.port == 443 &&
          uri.fragment.isEmpty;
    }

    if (allowed(primary)) candidates.add(primary);
    if (backup != null && backup != primary && allowed(backup)) {
      candidates.add(backup);
    }
    if (candidates.isEmpty) {
      throw const HttpException(
        'v40 download URL is outside the configured hosts',
      );
    }
    return candidates;
  }

  bool _isRedirect(int status) =>
      status == 301 || status == 302 || status == 307 || status == 308;

  int _retryAfterSeconds(Headers headers) {
    final raw = headers.value(HttpHeaders.retryAfterHeader)?.trim();
    if (raw == null || raw.isEmpty) return 0;
    final seconds = int.tryParse(raw);
    if (seconds != null) return seconds.clamp(0, 24 * 60 * 60);
    try {
      final date = HttpDate.parse(raw);
      return date.difference(DateTime.now()).inSeconds.clamp(0, 24 * 60 * 60);
    } catch (_) {
      return 0;
    }
  }

  String _absoluteUrl(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl);
    if (parsed != null && parsed.hasScheme) return rawUrl;
    throw const HttpException('v40 refresh returned a relative download URL');
  }

  String _safeFileStem(String releaseId) {
    final safe = releaseId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'app-upgrade' : safe;
  }

  Future<bool> _matchesSha256(File file, String expectedSha256) async {
    final expected = expectedSha256.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) return false;
    final watch = Stopwatch()..start();
    final actual = await appUpgradeFileSha256(
      file.path,
      cancelSignal: _activeCancel?.whenCancel,
    );
    _p2pClient.recordDownloadDiagnostic(
      'performance',
      'file_hash_profile',
      metrics: {'full_sha_us': watch.elapsedMicroseconds, 'full_sha_scans': 1},
    );
    return actual == expected;
  }

  Future<void> _deleteIfExists(File file) async {
    if (file.existsSync()) await file.delete();
  }

  @visibleForTesting
  static AppUpgradeV40ContentRange? parseContentRange(String? raw) {
    if (raw == null) return null;
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+)$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null ||
        end == null ||
        total == null ||
        start > end ||
        end >= total) {
      return null;
    }
    return AppUpgradeV40ContentRange(start: start, end: end, total: total);
  }
}

class AppUpgradeV40RateLimitException implements Exception {
  const AppUpgradeV40RateLimitException({required this.retryAfterSeconds});

  final int retryAfterSeconds;

  @override
  String toString() =>
      'v40 download rate limited; retry after $retryAfterSeconds seconds';
}

class AppUpgradeV40ContentRange {
  const AppUpgradeV40ContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;
}

class _V40Task {
  const _V40Task({
    required this.releaseId,
    required this.slug,
    required this.sha256,
    required this.fileSize,
    required this.etag,
    required this.sessionId,
    this.httpOrigin = '',
    this.p2pContributed = false,
    this.nonServiceContributed = false,
  });

  final String releaseId;
  final String slug;
  final String sha256;
  final int fileSize;
  final String etag;
  final String sessionId;
  final String httpOrigin;
  final bool p2pContributed;
  // Also fences legacy prefixes with no persisted provenance. Size/SHA-256
  // still permit installation, but HTTP telemetry cannot prove their source.
  final bool nonServiceContributed;

  Map<String, Object?> toJson() => <String, Object?>{
    'releaseId': releaseId,
    'slug': slug,
    'sha256': sha256,
    'fileSize': fileSize,
    'etag': etag,
    'sessionId': sessionId,
    'httpOrigin': httpOrigin,
    'p2pContributed': p2pContributed,
    'nonServiceContributed': nonServiceContributed,
  };

  factory _V40Task.fromJson(Map<dynamic, dynamic> json) => _V40Task(
    releaseId: (json['releaseId'] ?? '').toString(),
    slug: (json['slug'] ?? '').toString(),
    sha256: (json['sha256'] ?? '').toString(),
    fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
    etag: (json['etag'] ?? '').toString(),
    sessionId: (json['sessionId'] ?? '').toString(),
    httpOrigin: (json['httpOrigin'] ?? '').toString(),
    p2pContributed: json['p2pContributed'] == true,
    nonServiceContributed:
        json['nonServiceContributed'] == true ||
        !json.containsKey('p2pContributed') ||
        (json['httpOrigin'] is String &&
            (json['httpOrigin'] as String).isNotEmpty &&
            !AppUpgradeV40DownloadClient._allowedHosts.contains(
              Uri.tryParse(json['httpOrigin'] as String)?.host,
            )),
  );
}
