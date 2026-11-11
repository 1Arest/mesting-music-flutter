import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'app_upgrade_p2p_diagnostics.dart';
import 'app_upgrade_seed_candidates.dart';
import 'app_upgrade_p2p_piece_receiver.dart';
import 'app_upgrade_p2p_piece_store.dart';
import 'app_upgrade_p2p_protocol.dart';
import 'app_upgrade_p2p_identity.dart';
import 'app_upgrade_p2p_timeouts.dart';
import 'app_upgrade_receive_buffer.dart';
import 'app_upgrade_upload_budget.dart';
import 'app_upgrade_cache_verifier.dart';
import '../../p8p/window.dart';
import '../../p8p/source_diversity.dart';
import '../../p8p/leases.dart';
import '../../p8p/lifecycle_trace.dart';
import '../../p8p/ordered_writer.dart';
import '../../p8p/sources.dart';
import '../../p8p/coordinator.dart';
import '../../p8p/transfer_protocol.dart';
import '../../p8p/transfer_receiver.dart';
import '../../p8p/transfer_sender.dart';
import '../../sdk/models.dart' show RingSdkStatus;

typedef AppUpgradeP2PNetworkReader = Future<AppUpgradeP2PNetwork> Function();
typedef AppUpgradeP2PPeerFactory =
    Future<RTCPeerConnection> Function(Map<String, dynamic>);

/// Optional Android acceleration for the backend-selected service URL. Each
/// task owns its session, polling and credentials; cleanup from an old task
/// cannot change a new task. Network policy restricts uploading, not receiving.
class AppUpgradeV40P2PClient {
  AppUpgradeV40P2PClient({
    Dio? dio,
    AppUpgradeP2PNetworkReader? networkReader,
    Stream<dynamic>? networkEvents,
    AppUpgradeP2PPeerFactory? peerFactory,
    this.receiveBufferFactory,
    this.uploadBudget,
    void Function(AppUpgradeP2PDiagnostic)? diagnostic,
    bool? isAndroid,
    this.timeouts = const AppUpgradeP2PTimeouts(),
    this.sharingDuration = const Duration(minutes: 3),
    this.preferredSeedBatchPieces = 4,
    this.preferredPeerBatchPieces = 4,
    this.prewarmSeed = false,
    this.fastSignaling = false,
    this.sharedStartupDeadline = false,
    this.hybridStartup = false,
    this.allowSharing = true,
    this.enableP8P = false,
    this.p8pPeerRaceLimit = 2,
    this.p8pSourcePortDiversity = false,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 4),
               receiveTimeout: const Duration(seconds: 5),
               sendTimeout: const Duration(seconds: 5),
             ),
           ),
       _networkReader = networkReader ?? _readNativeNetwork,
       _networkEvents = networkEvents,
       _peerFactory = peerFactory ?? createPeerConnection,
       _diagnosticObserver = diagnostic ?? AppUpgradeP2PDiagnostics.record,
       _isAndroid = isAndroid ?? Platform.isAndroid {
    if (p8pPeerRaceLimit < 2 || p8pPeerRaceLimit > 4) {
      throw RangeError.range(p8pPeerRaceLimit, 2, 4, 'p8pPeerRaceLimit');
    }
  }

  static const _networkChannel = MethodChannel('auralink/app_upgrade_network');
  static const _eventsChannel = EventChannel(
    'auralink/app_upgrade_network_events',
  );
  final Dio _dio;
  final AppUpgradeP2PNetworkReader _networkReader;
  final Stream<dynamic>? _networkEvents;
  final AppUpgradeP2PPeerFactory _peerFactory;
  final AppUpgradeReceiveBufferFactory? receiveBufferFactory;
  final AppUpgradeUploadBudget? uploadBudget;
  final _cacheVerifier = AppUpgradeCacheVerifier();
  final _candidateHistory = _P2PCandidateHistory();
  final void Function(AppUpgradeP2PDiagnostic) _diagnosticObserver;
  void _diagnostic(AppUpgradeP2PDiagnostic event) {
    try {
      _diagnosticObserver(event);
    } catch (_) {
      // Optional host observation cannot change downloads or physical cleanup.
    }
  }

  final bool _isAndroid;
  final AppUpgradeP2PTimeouts timeouts;
  // Null keeps a verified cache available for the current foreground lifetime.
  // Compatibility callers retain the existing finite window by default.
  final Duration? sharingDuration;
  // Bounded transport options; the downloader enables concurrent startup.
  // Standalone P2P callers retain the sequential policy by default.
  final int preferredSeedBatchPieces;
  final int preferredPeerBatchPieces;
  final bool prewarmSeed;
  final bool fastSignaling;
  final bool sharedStartupDeadline;
  final bool hybridStartup;
  final bool enableP8P;
  final int p8pPeerRaceLimit;
  final bool p8pSourcePortDiversity;
  bool allowSharing;
  _P2PDownloadSession? _downloadSession;
  _P2PDownloadSession? _sharingSession;
  AppUpgradeP2PManifest? _lastManifest;
  String? _lastOrigin;
  int _generation = 0;
  bool _foreground = true;
  bool _resourcesAllowed = true;
  File? _shareFile;
  Future<void>? _shareFlight;
  Future<bool>? _cacheRestore;
  final _shareRetirements = <Future<void>>{};
  final _receiveRetirements = <Future<void>>{};
  final _trafficFlights = <Future<void>>{};
  Future<void>? _closing;
  bool _closed = false;
  int _shareRevision = 0;
  StreamSubscription<dynamic>? _shareNetworkSubscription;
  Timer? _shareRetry;
  Future<int>? _flight;
  String? _flightKey;
  _P2PDownloadSession? _diagnosticSession;
  bool _lastDownloadUsedP2P = false;
  int _lastBootstrapUsedBytes = 0;
  int get lastBootstrapUsedBytes => _lastBootstrapUsedBytes;

  /// True when the latest receive session appended bytes from a peer or seed.
  /// The server's HTTP coverage log cannot attest to those bytes.
  bool get lastDownloadUsedP2P => _lastDownloadUsedP2P;
  bool get lastDownloadMetadataMismatch => const {
    'manifest_version_mismatch',
    'manifest_build_mismatch',
    'manifest_size_mismatch',
    'manifest_sha_mismatch',
  }.contains(_diagnosticSession?._reason);

  /// Repeated requests for the same artifact reuse the active download; no
  /// second session/token/piece writer can race the first one.
  Future<int> downloadVerifiedPrefix({
    required String downloadUrl,
    required String expectedSlug,
    required String expectedVersion,
    int? expectedVersionCode,
    required int expectedFileSize,
    required String expectedSha256,
    required File partFile,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
    Future<void> Function()? beforeP2PWrite,
    Future<Uint8List?> Function(int index)? bootstrapPiece,
    Future<void> Function()? bootstrapHandoff,
    P8PRangeReader? p8pRangePiece,
    P8PProgressRangeReader? p8pProgressRangePiece,
    int Function()? bootstrapReceivedBytes,
    void Function()? bootstrapRejected,
    int bootstrapInitialBytes = 0,
    void Function()? onFileVerified,
  }) {
    final key = '$downloadUrl|$expectedSlug|$expectedSha256|${partFile.path}';
    final current = _flight;
    if (current != null) {
      if (_flightKey == key) return current;
      return Future.error(StateError('download_already_active'));
    }
    _flightKey = key;
    _lastDownloadUsedP2P = false;
    _lastBootstrapUsedBytes = 0;
    late Future<int> flight;
    flight =
        _downloadVerifiedPrefix(
          downloadUrl: downloadUrl,
          expectedSlug: expectedSlug,
          expectedVersion: expectedVersion,
          expectedVersionCode: expectedVersionCode,
          expectedFileSize: expectedFileSize,
          expectedSha256: expectedSha256,
          partFile: partFile,
          onProgress: onProgress,
          cancelToken: cancelToken,
          beforeP2PWrite: beforeP2PWrite,
          bootstrapPiece: bootstrapPiece,
          bootstrapHandoff: bootstrapHandoff,
          p8pRangePiece: p8pRangePiece,
          p8pProgressRangePiece: p8pProgressRangePiece,
          bootstrapReceivedBytes: bootstrapReceivedBytes,
          bootstrapRejected: bootstrapRejected,
          bootstrapInitialBytes: bootstrapInitialBytes,
          onFileVerified: onFileVerified,
        ).whenComplete(() {
          if (identical(_flight, flight)) {
            _flight = null;
            _flightKey = null;
          }
        });
    _flight = flight;
    return flight;
  }

  /// A separate, session-scoped receipt survives P2P leave. This optional
  /// final report cannot delay download completion or change its outcome.
  void reportFinalTraffic({
    required int httpsBodyBytes,
    required bool verified,
  }) {
    final session = _diagnosticSession;
    if (session == null ||
        session._trafficReceipt.isEmpty ||
        session.manifest == null) {
      return;
    }
    final receipt = session._trafficReceipt;
    final endpoint = '${session.manifest!.apiBase}/traffic';
    final body = {
      'https_body_bytes': httpsBodyBytes,
      'peer_body_bytes': session._peerBodyBytes,
      'seed_body_bytes': session._seedBodyBytes,
      'peer_verified_bytes': session._peerBytes,
      'seed_verified_bytes': session._seedBytes,
      'final_verified': verified,
    };
    late final Future<void> reporting;
    reporting = () async {
      try {
        await session.cleanup.timeout(const Duration(seconds: 25));
      } catch (_) {}
      for (var attempt = 0; attempt < 2; attempt++) {
        final cancel = CancelToken();
        try {
          final response = await _dio
              .post<Object?>(
                endpoint,
                data: body,
                cancelToken: cancel,
                options: Options(
                  followRedirects: false,
                  sendTimeout: const Duration(seconds: 3),
                  receiveTimeout: const Duration(seconds: 3),
                  headers: {'Authorization': 'Bearer $receipt'},
                  validateStatus: (_) => true,
                ),
              )
              .timeout(
                const Duration(seconds: 3),
                onTimeout: () {
                  cancel.cancel('traffic_report_timeout');
                  throw TimeoutException('traffic_report_timeout');
                },
              );
          if ((response.statusCode ?? 500) < 500) break;
        } catch (_) {}
      }
    }().whenComplete(() => _trafficFlights.remove(reporting));
    _trafficFlights.add(reporting);
    unawaited(reporting);
  }

  /// HTTPS and final integrity logs retain the receiving task's local sequence;
  /// the subsequent cache-sharing session has its own sequence.
  void recordDownloadDiagnostic(
    String stage,
    String code, {
    int? status,
    bool? verified,
    String? source,
    Map<String, int> metrics = const {},
  }) {
    final session = _diagnosticSession;
    if (session != null) {
      session._emit(
        stage,
        code,
        status: status,
        verified: verified,
        source: source,
        metrics: metrics,
      );
    } else {
      _diagnostic(
        AppUpgradeP2PDiagnostic(
          stage: stage,
          code: code,
          status: status,
          verified: verified,
          source: source,
          metrics: metrics,
        ),
      );
    }
  }

  Future<int> _downloadVerifiedPrefix({
    required String downloadUrl,
    required String expectedSlug,
    required String expectedVersion,
    int? expectedVersionCode,
    required int expectedFileSize,
    required String expectedSha256,
    required File partFile,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
    Future<void> Function()? beforeP2PWrite,
    Future<Uint8List?> Function(int index)? bootstrapPiece,
    Future<void> Function()? bootstrapHandoff,
    P8PRangeReader? p8pRangePiece,
    P8PProgressRangeReader? p8pProgressRangePiece,
    int Function()? bootstrapReceivedBytes,
    void Function()? bootstrapRejected,
    int bootstrapInitialBytes = 0,
    void Function()? onFileVerified,
  }) async {
    if (_closed) throw const AppUpgradeP2PFailure('session_stopped');
    final generation = ++_generation;
    await stopSharing();
    if (_closed) throw const AppUpgradeP2PFailure('session_stopped');
    _lastManifest = null;
    _lastOrigin = null;
    _diagnosticSession = null;
    final length = partFile.existsSync() ? await partFile.length() : 0;
    final origin = AppUpgradeP2PManifest.originForDownload(
      downloadUrl,
      expectedSlug,
    );
    if (!_isAndroid || origin == null) {
      _diagnostic(
        AppUpgradeP2PDiagnostic(
          stage: 'routing',
          code: !_isAndroid ? 'platform_unsupported' : 'source_not_p2p',
        ),
      );
      return length;
    }
    final session = _newSession(partFile);
    _diagnosticSession = session;
    _downloadSession = session;
    if (cancelToken != null) {
      if (cancelToken.isCancelled) session.interrupt();
      unawaited(
        cancelToken.whenCancel.then((_) {
          if (identical(_downloadSession, session)) {
            if (cancelToken.cancelError?.error == 'https_completed') {
              session.finish('https_fallback', 'https_completed', false);
            } else {
              session.interrupt();
            }
          }
        }),
      );
    }
    try {
      final result = await session.download(
        origin: origin,
        slug: expectedSlug,
        version: expectedVersion,
        versionCode: expectedVersionCode,
        size: expectedFileSize,
        sha: expectedSha256,
        onProgress: onProgress,
        beforeP2PWrite: beforeP2PWrite,
        bootstrapPiece: bootstrapPiece,
        bootstrapHandoff: bootstrapHandoff,
        p8pRangePiece: p8pRangePiece,
        p8pProgressRangePiece: p8pProgressRangePiece,
        bootstrapReceivedBytes: bootstrapReceivedBytes,
        bootstrapRejected: bootstrapRejected,
        bootstrapInitialBytes: bootstrapInitialBytes,
        onFileVerified: onFileVerified,
      );
      if (generation == _generation) {
        _lastManifest = session.manifest;
        _lastOrigin = origin;
      }
      return result;
    } finally {
      late final Future<void> retirement;
      retirement = () async {
        try {
          await session.cleanup;
        } catch (_) {
          // Receiving completion stays independent of best-effort reports.
        }
      }().whenComplete(() => _receiveRetirements.remove(retirement));
      _receiveRetirements.add(retirement);
      unawaited(retirement);
      _lastDownloadUsedP2P = session._peerBytes + session._seedBytes > 0;
      _lastBootstrapUsedBytes = session._httpsBootstrapBytes;
      if (identical(_downloadSession, session)) _downloadSession = null;
    }
  }

  _P2PDownloadSession _newSession(File file) => _P2PDownloadSession(
    dio: _dio,
    file: file,
    networkReader: _networkReader,
    networkEvents: _networkEvents ?? _eventsChannel.receiveBroadcastStream(),
    peerFactory: _peerFactory,
    receiveBufferFactory: receiveBufferFactory,
    uploadBudget: uploadBudget,
    cacheVerifier: _cacheVerifier,
    candidateHistory: _candidateHistory,
    diagnostic: _diagnostic,
    timeouts: timeouts,
    preferredSeedBatchPieces: preferredSeedBatchPieces.clamp(1, 6),
    preferredPeerBatchPieces: preferredPeerBatchPieces.clamp(1, 4),
    prewarmSeed: prewarmSeed,
    fastSignaling: fastSignaling,
    sharedStartupDeadline: sharedStartupDeadline,
    hybridStartup: hybridStartup,
    enableP8P: enableP8P,
    p8pPeerRaceLimit: p8pPeerRaceLimit,
    p8pSourcePortDiversity: p8pSourcePortDiversity,
    allowSharing: allowSharing && _foreground && _resourcesAllowed,
  );

  /// Share only verified cache, with the same Wi-Fi policy as reception sessions.
  /// Null duration permits foreground sharing and recovery after a network change;
  /// explicit stop, the next artifact, revocation or disposal forgets the cache.
  Future<void> shareVerifiedFile(File file, String downloadUrl) async {
    final manifest = _lastManifest;
    final origin = _lastOrigin;
    final generation = _generation;
    if (_closed ||
        !_isAndroid ||
        manifest == null ||
        origin == null ||
        sharingDuration == Duration.zero) {
      return;
    }
    final slug = Uri.parse(manifest.apiBase).pathSegments[2];
    if (AppUpgradeP2PManifest.originForDownload(downloadUrl, slug) != origin) {
      return;
    }
    final stopping = stopSharing();
    final revision = _shareRevision;
    await stopping;
    if (_closed ||
        revision != _shareRevision ||
        generation != _generation ||
        !identical(manifest, _lastManifest)) {
      return;
    }
    _shareFile = file;
    _watchSharingNetwork();
    await _resumeSharing();
  }

  void _watchSharingNetwork() {
    if (sharingDuration == null && _shareNetworkSubscription == null) {
      // Keep one watcher while paused, so returning to Wi-Fi can rejoin without
      // another download. Unknown/metered/cellular events never grant uploading.
      _shareNetworkSubscription =
          (_networkEvents ?? _eventsChannel.receiveBroadcastStream()).listen((
            value,
          ) {
            if (!AppUpgradeP2PNetwork.fromNative(value).mayShare) {
              _pauseSharing();
            } else {
              unawaited(_resumeSharing());
            }
          }, onError: (_) => _pauseSharing());
    }
  }

  /// A host may restore its persisted, authorized receipt after a process restart.
  /// This fetches only bounded manifest/signaling JSON; it never downloads a body
  /// or repairs the caller's file. Consent, lifecycle and network still gate it.
  Future<bool> restoreSharingFromCache({
    required File file,
    required String downloadUrl,
    required String expectedSlug,
    required String expectedVersion,
    required int expectedFileSize,
    required String expectedSha256,
    int? expectedVersionCode,
  }) {
    final origin = AppUpgradeP2PManifest.originForDownload(
      downloadUrl,
      expectedSlug,
    );
    if (_closed ||
        !_isAndroid ||
        !_foreground ||
        !allowSharing ||
        !_resourcesAllowed ||
        sharingDuration == Duration.zero ||
        origin == null ||
        _flight != null ||
        _cacheRestore != null ||
        _shareFlight != null) {
      return Future.value(false);
    }
    if (_shareFile?.path == file.path &&
        _lastManifest?.sha256 == expectedSha256 &&
        _lastManifest?.fileSize == expectedFileSize) {
      return Future.value(true);
    }
    final generation = ++_generation;
    final stopping = stopSharing();
    final revision = _shareRevision;
    bool owns() =>
        !_closed && generation == _generation && revision == _shareRevision;
    late final Future<bool> restoring;
    restoring =
        () async {
          await stopping;
          if (!owns() || !_foreground || !allowSharing || !_resourcesAllowed) {
            return false;
          }
          final network = await _networkReader();
          if (!owns() ||
              !_foreground ||
              !allowSharing ||
              !_resourcesAllowed ||
              !network.mayShare) {
            return false;
          }
          final session = _newSession(file);
          _sharingSession = session;
          try {
            final json = await session._request(
              'manifest',
              '${AppUpgradeP2PManifest.serviceOrigin}/api/app/$expectedSlug/p2p/manifest',
              auth: false,
            );
            final manifest = AppUpgradeP2PManifest.parse(
              json,
              origin: origin,
              slug: expectedSlug,
              version: expectedVersion,
              versionCode: expectedVersionCode,
              fileSize: expectedFileSize,
              sha256: expectedSha256,
            );
            if (!owns() ||
                !_foreground ||
                !allowSharing ||
                !_resourcesAllowed ||
                !identical(_sharingSession, session)) {
              return false;
            }
            _lastManifest = manifest;
            _lastOrigin = origin;
            _shareFile = file;
            _watchSharingNetwork();
            await session.shareCache(manifest, sharingDuration);
            return owns() && session.cacheVerified;
          } catch (_) {
            // A lifecycle/network pause may retire a verified cache while retaining
            // its intent. The existing watcher can resume it on allowed Wi-Fi.
            if (owns() &&
                session.cacheVerified &&
                identical(_shareFile, file)) {
              return true;
            }
            if (owns()) {
              _shareFile = null;
              final subscription = _shareNetworkSubscription;
              _shareNetworkSubscription = null;
              await subscription?.cancel();
            }
            _diagnostic(
              const AppUpgradeP2PDiagnostic(
                stage: 'sharing',
                code: 'cache_restore_failed',
              ),
            );
            return false;
          } finally {
            if (!owns() || !session.cacheVerified || !session._active) {
              session.finish(
                'local_cache_complete',
                'sharing_stopped',
                session.cacheVerified,
              );
              await session.cleanup;
              if (identical(_sharingSession, session)) _sharingSession = null;
            }
            _scheduleSharingRetry();
          }
        }().catchError((Object _) {
          _diagnostic(
            const AppUpgradeP2PDiagnostic(
              stage: 'sharing',
              code: 'cache_restore_failed',
            ),
          );
          return false;
        });
    _cacheRestore = restoring;
    final flight = restoring.then<void>((_) {});
    _shareFlight = flight;
    unawaited(
      flight.whenComplete(() {
        if (identical(_shareFlight, flight)) _shareFlight = null;
        if (identical(_cacheRestore, restoring)) _cacheRestore = null;
      }),
    );
    return restoring;
  }

  void _scheduleSharingRetry() {
    if (sharingDuration == null &&
        _shareFile != null &&
        _foreground &&
        allowSharing &&
        _resourcesAllowed &&
        !_closed) {
      _shareRetry ??= Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(_resumeSharing());
      });
    }
  }

  Future<void> _resumeSharing() => _shareFlight ??= _runResumeSharing()
      .whenComplete(() => _shareFlight = null);

  Future<void> _runResumeSharing() async {
    if (_closed ||
        !_foreground ||
        !allowSharing ||
        !_resourcesAllowed ||
        _shareFile == null ||
        _sharingSession?._active == true) {
      return;
    }
    final file = _shareFile!;
    final generation = _generation;
    try {
      await _diagnosticSession?.cleanup;
      final network = await _networkReader();
      if (!network.mayShare ||
          _closed ||
          generation != _generation ||
          !identical(file, _shareFile) ||
          !_foreground ||
          !allowSharing ||
          !_resourcesAllowed) {
        return;
      }
      final session = _newSession(file);
      _sharingSession = session;
      try {
        await session.shareCache(_lastManifest!, sharingDuration);
      } catch (_) {
        session.finish(
          'local_cache_complete',
          'sharing_unavailable',
          session.cacheVerified,
        );
      }
    } catch (_) {
      // Sharing failure is independent of installation and receiving.
    } finally {
      _scheduleSharingRetry();
    }
  }

  void _pauseSharing() {
    _shareRetry?.cancel();
    _shareRetry = null;
    final session = _sharingSession;
    _sharingSession = null;
    if (session == null) return;
    session.setSharingEnabled(false);
    session.finish(
      'local_cache_complete',
      'sharing_stopped',
      session.cacheVerified,
    );
    // HTTP is owned by the engine. Retain this session after synchronous
    // revocation so stop/dispose cannot close that HTTP owner before leave.
    // A late start reply may replace cleanup, so read it after start finishes.
    final starting = _shareFlight;
    late final Future<void> retiring;
    retiring = () async {
      try {
        await starting;
      } catch (_) {}
      try {
        await session.cleanup;
      } catch (_) {
        // Cleanup retains its existing bounded best-effort HTTP policy.
      }
    }().whenComplete(() => _shareRetirements.remove(retiring));
    _shareRetirements.add(retiring);
    unawaited(retiring);
  }

  /// Effective upload permission includes foreground state even while receiving.
  /// Revoke synchronously before any asynchronous withdrawal or lease cleanup.
  void setSharingEnabled(bool enabled) {
    allowSharing = enabled;
    _downloadSession?.setSharingEnabled(
      enabled && _foreground && _resourcesAllowed,
    );
    _sharingSession?.setSharingEnabled(
      enabled && _foreground && _resourcesAllowed,
    );
    if (!enabled) {
      _pauseSharing();
    } else if (sharingDuration == null) {
      unawaited(_resumeSharing());
    }
  }

  void cancelDownload() => _downloadSession?.interrupt();
  void setResourcesAllowed(bool allowed) {
    _resourcesAllowed = allowed;
    _downloadSession?.setSharingEnabled(allowSharing && _foreground && allowed);
    _sharingSession?.setSharingEnabled(allowSharing && _foreground && allowed);
    if (!allowed) {
      _pauseSharing();
    } else if (sharingDuration == null) {
      unawaited(_resumeSharing());
    }
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    _downloadSession?.setSharingEnabled(
      allowSharing && foreground && _resourcesAllowed,
    );
    if (!foreground) {
      _pauseSharing();
    } else if (sharingDuration == null) {
      unawaited(_resumeSharing());
    }
  }

  Future<void> stopSharing() async {
    // Capture the owner before the first await. A replacement operation may
    // publish its own flight while the old watcher is retiring.
    final starting = _shareFlight;
    ++_shareRevision;
    _pauseSharing();
    _shareFile = null;
    final subscription = _shareNetworkSubscription;
    _shareNetworkSubscription = null;
    await subscription?.cancel();
    // File verification may still be reading. Do not return disposal while a
    // paused attempt holds the cache open or could create a late session.
    await starting;
    await Future.wait(_shareRetirements.toList());
  }

  /// Retire all HTTP owners before the engine closes its signal client. Keep
  /// this separate from stopSharing, which must not cancel a receive task.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    setForeground(false);
    setSharingEnabled(false);
    cancelDownload();
    await stopSharing();
    try {
      await _flight;
    } catch (_) {
      // Cancellation/failure was already delivered to the receiving caller.
    }
    await Future.wait(_receiveRetirements.toList());
    await Future.wait(_trafficFlights.toList());
  }

  static Future<AppUpgradeP2PNetwork> _readNativeNetwork() async {
    try {
      return AppUpgradeP2PNetwork.fromNative(
        await _networkChannel
            .invokeMethod<String>('getNetworkType')
            .timeout(const Duration(seconds: 1)),
      );
    } catch (_) {
      return AppUpgradeP2PNetwork.unknown;
    } // Unknown never uploads.
  }
}

class _P2PDownloadSession {
  _P2PDownloadSession({
    required this.dio,
    required this.file,
    required this.networkReader,
    required this.networkEvents,
    required this.peerFactory,
    required this.receiveBufferFactory,
    required this.uploadBudget,
    required this.cacheVerifier,
    required this.candidateHistory,
    required this.diagnostic,
    required this.timeouts,
    required this.preferredSeedBatchPieces,
    required this.preferredPeerBatchPieces,
    required this.prewarmSeed,
    required this.fastSignaling,
    required this.sharedStartupDeadline,
    required this.hybridStartup,
    required this.allowSharing,
    required this.enableP8P,
    required this.p8pPeerRaceLimit,
    required this.p8pSourcePortDiversity,
  });
  final Dio dio;
  final File file;
  final AppUpgradeP2PNetworkReader networkReader;
  final Stream<dynamic> networkEvents;
  final AppUpgradeP2PPeerFactory peerFactory;
  final AppUpgradeReceiveBufferFactory? receiveBufferFactory;
  final AppUpgradeUploadBudget? uploadBudget;
  final AppUpgradeCacheVerifier cacheVerifier;
  final _P2PCandidateHistory candidateHistory;
  final void Function(AppUpgradeP2PDiagnostic) diagnostic;
  final AppUpgradeP2PTimeouts timeouts;
  final int preferredSeedBatchPieces;
  final int preferredPeerBatchPieces;
  final bool prewarmSeed;
  final bool fastSignaling;
  final bool sharedStartupDeadline;
  final bool hybridStartup;
  bool allowSharing;
  final bool enableP8P;
  bool get _p8p => enableP8P && manifest?.p8pAdaptiveWindow == true;
  final int p8pPeerRaceLimit;
  final bool p8pSourcePortDiversity;
  int get _ordinaryPeerRaceLimit =>
      _p8p &&
          _multiCoordinator != null &&
          manifest?.peerCandidateReplacement == true &&
          !_cacheSharing
      ? p8pPeerRaceLimit
      : 2;
  int _peakOrdinaryPeerOwners = 0;
  P8POrderedWriter? _multiWriter;
  P8PCoordinator? _multiCoordinator;
  bool _multiHandoff = false;
  bool get _hybrid =>
      hybridStartup && (_bootstrapPiece != null || _hybridWinner != null);
  Duration? _backgroundBudget;
  Duration get _connectBudget => _backgroundBudget ?? manifest!.connectTimeout;
  _P2PPeer? _hybridWinner;
  Uint8List? _hybridProbe;
  int? _hybridProbeIndex;
  static final _recentPeerFailures = <String, DateTime>{};
  Future<({_P2PPeer peer, String sdp})?>? _seedPreparation;
  static int _nextTask = 0;
  final int _task = ++_nextTask;
  final Stopwatch _elapsed = Stopwatch()..start();
  Stopwatch? _connectWatch;
  Timer? _startupTimer;
  bool _firstPiecePersisted = false;
  int? _iceConnectMs, _dataChannelMs, _firstPieceMs;
  bool _sessionTrickle = false;
  bool _sessionServerTrickle = false;
  final _serverCandidates = AppUpgradeSeedCandidates();
  final _apiRoundtripMs = <String, int>{};
  final _apiServerMs = <String, int>{};
  final _iceCounts = <String, int>{'host': 0, 'srflx': 0, 'relay': 0};
  int _iceGatherMs = 0;
  String _iceGatherState = 'unknown';
  bool _serverOfferAttempted = false;
  bool _seedReconnectBlocked = false;
  static const _timedEndpoints = {
    'manifest',
    'session',
    'peers',
    'signals',
    'signal',
    'candidate',
    'heartbeat',
    'server_offer',
    'server_candidate',
  };
  String _appVersion = 'unknown';
  AppUpgradeP2PSessionRequest? _sessionRequest;
  String _deviceId = '';
  final _httpCancel = CancelToken();
  final Map<String, _P2PPeer> _peers = {};
  // Removing a closed peer from signaling does not free its native owner.
  // Pending creation or failed native disposal keeps this slot occupied.
  final Set<_P2PPeer> _ordinaryPeerOwners = {};
  // Counters belong to a receiver session, including a later RTC reconnect.
  // Bound long-lived cache sessions rather than evicting counters and reporting
  // a smaller total to the server's idempotent MAX-based endpoint.
  static const _maxUploadReceivers = 256;
  final _uploadLedgers = <String, _P2PUploadLedger>{};
  final _uploadRetirements = <Future<void>>{};
  final _transportRetirements = <Future<void>>{};
  final _nativeReleases = Expando<Future<void>>();
  final _releasedNativePeers = Expando<bool>();
  final Map<String, List<Map>> _earlyCandidates = {};
  final Set<String> _loggedSuccess = {};
  final Set<String> _failedPeers = {};
  final Set<String> _outboundPeerIds = {};
  final Set<String> _attemptedCandidateKeys = {};
  int? _p8pCandidateAttemptLimit;
  final List<Map<String, Object?>> _attempts = [];
  int _peerAlias = 0;

  void _peerEvent(_P2PPeer peer, String code) {
    if (!_active || peer.closed || !peer.diagnosticStages.add(code)) return;
    _emit(
      'attempt',
      code,
      source: _source(peer),
      attempt: peer.attempt?['alias'] as String?,
    );
  }

  void _attemptStage(_P2PPeer peer, String stage) {
    final attempt = peer.attempt;
    if (attempt == null || peer.closed || attempt.containsKey(stage)) return;
    attempt.putIfAbsent(stage, () => _sessionElapsed() ?? 0);
    if (stage == 'first_piece_ms' && peer.id != 'server' && peer.leased) {
      candidateHistory.record(
        manifest!.apiBase,
        peer.id,
        firstPieceMs: peer.connectWatch.elapsedMilliseconds,
      );
    }
    _emit(
      'attempt',
      stage == 'first_piece_ms'
          ? 'piece_verified'
          : stage == 'answer_ms'
          ? 'answer_received'
          : stage == 'channel_ms'
          ? 'channel_open'
          : 'ice_connected',
      source: _source(peer),
      attempt: attempt['alias'] as String,
    );
  }

  Future<void>? _withdrawal;
  Future<void> cleanup = Future<void>.value();
  AppUpgradeP2PManifest? manifest;
  late AppUpgradeP2PPieceStore _store;
  bool _storeReady = false;
  AppUpgradeP2PNetwork _network = AppUpgradeP2PNetwork.unknown;
  StreamSubscription<dynamic>? _subscription;
  Timer? _signalTimer, _heartbeatTimer, _heartbeatSoon, _sharingTimer;
  _P2PPeer? _server;
  List<Map> _candidates = [];
  DateTime? _peerFetchedAt;
  String _token = '', _selfId = '', _reason = 'sources_unavailable';
  String _trafficReceipt = '';
  int _peerBodyBytes = 0, _seedBodyBytes = 0;
  bool _active = true, _ended = false, _interrupted = false;
  bool _shareGranted = false, _heartbeatBusy = false, _cacheSharing = false;
  bool cacheVerified = false;
  int _serverAttempts = 0,
      _peerBytes = 0,
      _seedBytes = 0,
      _emptySignalPolls = 0;
  bool get _mayUpload =>
      allowSharing && _active && _network.mayShare && _shareGranted;

  Map<String, Object?> _sharingHeartbeat(
    AppUpgradeP2PNetwork network,
    Iterable<int> pieces,
  ) => <String, Object?>{
    ...(allowSharing
        ? network.heartbeat(pieces)
        : <String, Object?>{
            'network': network.wireName,
            'share_enabled': false,
            'pieces': <int>[],
          }),
    if (enableP8P && manifest?.p8pTransfer == true)
      'p8p_transfer': P8PTransferProtocol.capability,
    if (uploadBudget != null) 'max_connections': 1,
  };
  Future<Uint8List?> Function(int index)? _bootstrapPiece;
  bool _piecesFromHttps = false, _bootstrapHandoffStarted = false;
  void Function()? _bootstrapRejected;
  int _httpsBootstrapBytes = 0, _bootstrapInitialBytes = 0;
  int Function()? _bootstrapReceivedBytes;
  bool _supportsBootstrapTelemetry = false;

  Future<int> download({
    required String origin,
    required String slug,
    required String version,
    int? versionCode,
    required int size,
    required String sha,
    required void Function(int, int) onProgress,
    Future<void> Function()? beforeP2PWrite,
    Future<Uint8List?> Function(int index)? bootstrapPiece,
    Future<void> Function()? bootstrapHandoff,
    P8PRangeReader? p8pRangePiece,
    P8PProgressRangeReader? p8pProgressRangePiece,
    int Function()? bootstrapReceivedBytes,
    void Function()? bootstrapRejected,
    int bootstrapInitialBytes = 0,
    void Function()? onFileVerified,
  }) async {
    _bootstrapPiece = bootstrapPiece;
    _bootstrapReceivedBytes = bootstrapReceivedBytes;
    _bootstrapRejected = bootstrapRejected;
    _bootstrapInitialBytes = bootstrapInitialBytes;
    var prefix = file.existsSync() ? await file.length() : 0;
    var sourceWaitUs = 0, steadySourceWaitUs = 0;
    try {
      _checkActive();
      _appVersion = await AppUpgradeP2PDiagnostics.clientVersion();
      final json = await _request(
        'manifest',
        '${AppUpgradeP2PManifest.serviceOrigin}/api/app/$slug/p2p/manifest',
        auth: false,
      );
      diagnostic(
        AppUpgradeP2PDiagnostic(
          stage: 'manifest',
          code: 'metadata_compared',
          expectedBytes: size,
          actualBytes: json['file_size'] is num
              ? (json['file_size'] as num).toInt()
              : null,
        ),
      );
      manifest = AppUpgradeP2PManifest.parse(
        json,
        origin: origin,
        slug: slug,
        version: version,
        versionCode: versionCode,
        fileSize: size,
        sha256: sha,
      );
      if (_hybrid && json['p2p_background_connect_timeout_ms'] is int) {
        final ms = json['p2p_background_connect_timeout_ms'] as int;
        if (ms >= manifest!.connectTimeout.inMilliseconds && ms <= 15000) {
          _backgroundBudget = Duration(milliseconds: ms);
        }
      }
      _emit('manifest', 'validated');
      _supportsBootstrapTelemetry =
          json['https_bootstrap_diagnostics_supported'] == true;
      _store = AppUpgradeP2PPieceStore(file, manifest!, bufferedWrites: true);
      prefix = await _store.verifyPrefix();
      _storeReady = true;
      onProgress(prefix, size);
      await _startSession();
      if (prefix == size && await _store.completeAndVerified()) {
        onFileVerified?.call();
        finish('local_cache_complete', 'cache_verified', true);
        return prefix;
      }
      if (prefix % AppUpgradeP2PManifest.chunkSize != 0) {
        _reason = 'partial_https_prefix'; // Preserve partial HTTPS bytes.
        return prefix;
      }
      var multisource =
          enableP8P &&
          manifest!.p8pTransfer &&
          _hybrid &&
          p8pRangePiece != null &&
          bootstrapHandoff != null;
      if (multisource && _active) {
        prefix = await _downloadMultiSource(
          prefix,
          onProgress: onProgress,
          beforeP2PWrite: beforeP2PWrite,
          handoff: bootstrapHandoff,
          rangePiece: p8pRangePiece,
          progressRangePiece: p8pProgressRangePiece,
        );
        multisource = _multiHandoff || !_active;
      }
      if (!multisource && prewarmSeed && _active) {
        // Local preparation overlaps discovery; hybrid mode starts the seed
        // offer immediately alongside user peers within the same budget.
        _seedPreparation = _prepareSeed();
      }
      while (!multisource && _active && prefix < size) {
        _piecesFromHttps = false;
        List<Uint8List>? pieces;
        bool fromPeer;
        final index = prefix ~/ AppUpgradeP2PManifest.chunkSize;
        final wait = Stopwatch()..start();
        if (_hybrid) {
          pieces = await _tryHybridPieces(index);
          fromPeer = _hybridWinner?.id != 'server';
        } else {
          final cached = _bootstrapHandoffStarted
              ? await _takeBootstrapPiece(index)
              : null;
          final peerBytes = cached != null
              ? [cached]
              : await _tryPeerPieces(index);
          fromPeer = peerBytes != null;
          pieces = peerBytes;
          if (pieces == null && _active) pieces = await _trySeedPieces(index);
        }
        sourceWaitUs += wait.elapsedMicroseconds;
        if (_firstPiecePersisted) {
          steadySourceWaitUs += wait.elapsedMicroseconds;
        }
        if (pieces == null || !_active) break;
        for (final bytes in pieces) {
          // A crash after the write must not turn peer bytes into HTTP coverage.
          if (!_piecesFromHttps) await beforeP2PWrite?.call();
          _checkActive();
          await _store.append(
            prefix,
            prefix ~/ AppUpgradeP2PManifest.chunkSize,
            bytes,
          );
          if (!_piecesFromHttps) _firstPieceMs ??= _sessionElapsed();
          _firstPiecePersisted = true;
          _startupTimer?.cancel();
          prefix += bytes.length;
          if (_piecesFromHttps) {
            // HTTPS is counted by its HTTP session, never as peer/seed traffic.
            _httpsBootstrapBytes +=
                (prefix - max(prefix - bytes.length, _bootstrapInitialBytes))
                    .clamp(0, bytes.length)
                    .toInt();
          } else if (fromPeer) {
            _peerBytes += bytes.length;
          } else {
            _seedBytes += bytes.length;
          }
          onProgress(prefix, size);
          _scheduleHeartbeat();
        }
      }
      if (prefix == size) {
        if (!await _store.completeAndVerified()) {
          throw const AppUpgradeP2PFailure('file_checksum_mismatch');
        }
        // The writer is closed and the full file has just passed SHA-256.
        // The exclusive owner may reuse this task-local result only while it
        // performs no further writes. Standalone callers keep full verification.
        onFileVerified?.call();
        finish(
          _peerBytes + _seedBytes > 0 ? 'p2p_complete' : 'local_cache_complete',
          'file_verified',
          true,
        );
      }
    } catch (error) {
      if (!_ended && _reason != 'p2p_budget_exhausted') {
        _reason = _failureCode(error);
      }
    } finally {
      if (_storeReady) {
        try {
          await _store.close();
        } catch (_) {
          // Release the handle even on disk failure. The HTTPS path retains
          // final SHA verification and must not inherit active RTC resources.
          _reason = 'file_write_failed';
        }
        _emit(
          'performance',
          'transfer_profile',
          metrics: {
            ..._store.metrics,
            'source_wait_us': sourceWaitUs,
            'steady_source_wait_us': steadySourceWaitUs,
          },
        );
      }
      if (!_ended) {
        finish(
          _interrupted ? 'client_interrupted' : 'https_fallback',
          _reason,
          false,
        );
      }
    }
    if (_interrupted) {
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.cancel,
        message: 'client_interrupted',
      );
    }
    return prefix;
  }

  Future<void> shareCache(
    AppUpgradeP2PManifest value,
    Duration? duration,
  ) async {
    manifest = value;
    _store = AppUpgradeP2PPieceStore(file, value);
    await cacheVerifier.verify(file, value);
    if (!_active || !allowSharing) return;
    _store.verifiedPieces.addAll(
      List.generate(value.pieceHashes.length, (i) => i),
    );
    cacheVerified = true;
    _storeReady = true;
    _network = await networkReader();
    if (!allowSharing || !_network.mayShare || !_active) {
      finish('local_cache_complete', 'sharing_network_disallowed', true);
      return;
    }
    _cacheSharing = true;
    await _startSession();
    _checkActive();
    if (duration != null) {
      _sharingTimer = Timer(
        duration,
        () => finish('local_cache_complete', 'sharing_expired', true),
      );
    }
    _emit('sharing', 'cache_available');
  }

  Future<void> _startSession() async {
    _checkActive();
    _network = await networkReader();
    _subscription = networkEvents.listen(
      (value) => _networkChanged(AppUpgradeP2PNetwork.fromNative(value)),
      onError: (_) => _networkChanged(AppUpgradeP2PNetwork.unknown),
    );
    final payload = _sharingHeartbeat(_network, _store.verifiedPieces);
    _deviceId = await AppUpgradeP2PIdentity.deviceId();
    _appVersion = await AppUpgradeP2PDiagnostics.clientVersion();
    final request = await AppUpgradeP2PIdentity.sessionRequest(
      apiBase: manifest!.apiBase,
      sha: manifest!.sha256,
      sharing: _cacheSharing,
      body: {
        ...payload,
        'role': 'download',
        'sha256': manifest!.sha256,
        'sdk_version': RingSdkStatus.sdkVersion,
        if (manifest!.trickleIce) 'trickle_ice_supported': true,
        if (enableP8P && manifest!.serverTrickle)
          'server_trickle_supported': true,
        // Match the server seed deadline to background negotiation only while
        // HTTPS is already making progress; foreground clients retain 8s.
        if (_hybrid && !_cacheSharing) 'https_downloading': true,
      },
    );
    _sessionRequest = request;
    _sessionTrickle = request.body['trickle_ice_supported'] == true;
    Map<String, dynamic> session;
    _connectWatch = Stopwatch()..start();
    if (!_cacheSharing) {
      // The first verified piece, rather than an open but silent channel, ends
      // startup. Session retries and discovery share this same deadline.
      _startupTimer = Timer(_connectBudget, () {
        if (_active && !_firstPiecePersisted) {
          finish('https_fallback', 'p2p_budget_exhausted', false);
        }
      });
    }
    try {
      session = await _request(
        'session',
        '${manifest!.apiBase}/session',
        body: request.body,
        auth: false,
      );
    } on AppUpgradeP2PFailure catch (error) {
      if (!_active || !_retryableReport(error.code)) rethrow;
      // One uncertain transport retry, with the exact persisted body/key.
      _emit('session', 'retry');
      session = await _request(
        'session',
        '${manifest!.apiBase}/session',
        body: request.body,
        auth: false,
      );
    }
    _token = session['token'] is String ? session['token'] as String : '';
    _trafficReceipt = session['traffic_receipt'] is String
        ? session['traffic_receipt'] as String
        : '';
    _selfId = session['session_id'] is String
        ? session['session_id'] as String
        : '';
    if (_token.isEmpty || !_isPeerId(_selfId)) {
      throw const AppUpgradeP2PFailure('session_response_invalid');
    }
    if (!_active) {
      cleanup = _reportAndLeave('client_interrupted', 'session_stopped', false);
      unawaited(cleanup);
      _checkActive();
    }
    _sessionServerTrickle =
        request.body['server_trickle_supported'] == true &&
        session['server_trickle_supported'] == true;
    // Reconcile network changes during session creation before permitting uploads.
    _shareGranted =
        allowSharing &&
        request.body['share_enabled'] == true &&
        _network.mayShare &&
        session['share_enabled'] != false;
    if (_cacheSharing && enableP8P && manifest!.p8pTransfer) {
      // Existing services timestamp lease capability on heartbeat, not on
      // registration. Publish it before declaring this cache available; waiting
      // for the first periodic heartbeat hides a new phone for up to20s.
      await _heartbeat();
    } else if (request.body['network'] != _network.wireName ||
        request.body['share_enabled'] != (allowSharing && _network.mayShare) ||
        jsonEncode(request.body['pieces']) != jsonEncode(payload['pieces']) ||
        request.body['share_enabled'] != payload['share_enabled']) {
      unawaited(_heartbeat());
    }
    unawaited(_pollSignals());
    final interval = session['heartbeat_interval'];
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: interval is int ? interval.clamp(5, 20) : 20),
      (_) => unawaited(_heartbeat()),
    );
    _emit('session', 'started');
  }

  bool get _httpsNearlyComplete {
    final received = _bootstrapReceivedBytes?.call() ?? 0;
    return received > 0 &&
        manifest!.fileSize - _bootstrapInitialBytes - received <=
            2 * AppUpgradeP2PManifest.chunkSize;
  }

  Future<int> _downloadMultiSource(
    int prefix, {
    required void Function(int, int) onProgress,
    required Future<void> Function()? beforeP2PWrite,
    required Future<void> Function() handoff,
    required P8PRangeReader rangePiece,
    P8PProgressRangeReader? progressRangePiece,
  }) async {
    if (_httpsNearlyComplete) return prefix;
    final clock = Stopwatch()..start();
    final book = P8PLeaseBook(
      contentKey: '$_selfId|${manifest!.sha256}|${manifest!.fileSize}',
      fileSha256: manifest!.sha256,
      generation: Random.secure().nextInt(0x7ffffffe) + 1,
      fileBytes: manifest!.fileSize,
      pieceBytes: AppUpgradeP2PManifest.chunkSize,
      clockMicros: () => clock.elapsedMicroseconds,
      persistedPieces: prefix ~/ AppUpgradeP2PManifest.chunkSize,
      repeatBudgetBytes: 2 * AppUpgradeP2PManifest.chunkSize,
    );
    final cachedIndices = <int>{};
    final writer = _multiWriter = await P8POrderedWriter.open(
      book,
      _store,
      paused: true,
      beforeWrite: (lease) async {
        _checkActive();
        if (lease.source != 'https') await beforeP2PWrite?.call();
        _checkActive();
      },
      onPersisted: (lease) {
        _firstPiecePersisted = true;
        _startupTimer?.cancel();
        if (lease.source == 'https') {
          if (cachedIndices.remove(lease.index)) {
            final start = lease.index * AppUpgradeP2PManifest.chunkSize;
            _httpsBootstrapBytes +=
                (start + lease.bytes - max(start, _bootstrapInitialBytes))
                    .clamp(0, lease.bytes)
                    .toInt();
          }
        } else {
          _firstPieceMs ??= _sessionElapsed();
          final peer = lease.source == 'server'
              ? _server
              : _peers[lease.source];
          if (peer != null) _attemptStage(peer, 'first_piece_ms');
          if (lease.source == 'server') {
            _seedBytes += lease.bytes;
          } else {
            _peerBytes += lease.bytes;
          }
        }
        onProgress(book.persistedBytes, book.fileBytes);
        _scheduleHeartbeat();
      },
    );
    void Function(String)? onBodySourceFailed;
    final coordinator = _multiCoordinator = P8PCoordinator(
      writer,
      clockMicros: () => clock.elapsedMicroseconds,
      requestTimeout: timeouts.transfer,
      onSourceFailed: (id) => onBodySourceFailed?.call(id),
      onLifecycle: (event) => _emitLifecycle(event),
      onDiagnostic: (event) => _emit(
        'transfer',
        event.reason.code,
        source: event.alias == 'https'
            ? 'https'
            : event.alias == 'seed'
            ? 'seed'
            : 'peer',
        attempt: event.alias == 'https' ? null : event.alias,
        actualBytes: event.actualBytes,
        expectedBytes: event.expectedBytes,
      ),
    );
    final ready = <P8PRtcPieceSource>[];
    var branches = 0;
    var startupPieceProven = false;
    final discoveredPeerIds = <String>{};
    final admittedPeerIds = <String>{};
    final admittedPeers = <String, _P2PPeer>{};
    final retiringPeers = <String, Future<void>>{};
    final candidateLimit = manifest!.peerCandidateReplacement ? 4 : 2;
    if (manifest!.peerCandidateReplacement) {
      _p8pCandidateAttemptLimit = candidateLimit;
    }
    final discoveryCancel = CancelToken();
    final yieldInitialDiscovery = Completer<void>();
    final initialSelectionStopped = Completer<void>();
    Timer? discoveryTimer;
    Completer<void>? discoveryWait;
    var bodyReplacementPending = false;
    Future<void>? lateDiscovery;
    unawaited(
      _httpCancel.whenCancel.then((_) {
        discoveryCancel.cancel('session_stopped');
        discoveryTimer?.cancel();
        if (discoveryWait?.isCompleted == false) discoveryWait!.complete();
      }),
    );
    final replaceUnprovenStartupPeers =
        manifest!.peerCandidateReplacement && _ordinaryPeerRaceLimit < 4;
    Completer<void>? changed, discoveryChanged;
    void notify() {
      if (changed?.isCompleted == false) changed!.complete();
      if (discoveryChanged?.isCompleted == false) discoveryChanged!.complete();
    }

    void retireFailedPeers([String? failedId]) {
      if (!manifest!.peerCandidateReplacement ||
          !_active ||
          book.closed ||
          book.complete ||
          discoveryCancel.isCancelled) {
        return;
      }
      for (final entry in admittedPeers.entries.toList()) {
        if ((failedId != null && entry.key != failedId) ||
            retiringPeers.containsKey(entry.key)) {
          continue;
        }
        late final Future<void> retiring;
        retiring = () async {
          if (!await coordinator.retireFailedSource(entry.key)) return;
          _closePeer(entry.value);
          await _retireOrdinaryPeer(entry.value);
          if (!_ordinaryPeerOwners.contains(entry.value)) {
            admittedPeerIds.remove(entry.key);
            admittedPeers.remove(entry.key);
            notify();
            if (_multiHandoff && !discoveryCancel.isCancelled) {
              bodyReplacementPending = true;
              if (!yieldInitialDiscovery.isCompleted) {
                yieldInitialDiscovery.complete();
              }
              if (discoveryWait?.isCompleted == false) {
                discoveryWait!.complete();
              }
            }
          }
        }().whenComplete(() => retiringPeers.remove(entry.key));
        retiringPeers[entry.key] = retiring;
        unawaited(retiring.catchError((Object _) {}));
      }
    }

    onBodySourceFailed = (id) {
      if (_multiHandoff && admittedPeers.containsKey(id)) {
        // Let the coordinator finish recording the failure and owning close
        // before retirement checks its request and native transport state.
        scheduleMicrotask(() => retireFailedPeers(id));
      }
    };

    Future<void> add(_P2PPeer peer, Set<int>? pieces) async {
      try {
        final receiver = peer.transfer;
        if (receiver == null) {
          throw const AppUpgradeP2PFailure('channel_closed');
        }
        await receiver.connect(_remaining(peer));
        _checkPeer(peer);
        if (_ordinaryPeerRaceLimit > 2 && peer.id != 'server') {
          final standby = Stopwatch()..start();
          final standbyBudget =
              coordinator.requestTimeout + coordinator.stopGrace;
          while (admittedPeerIds.length >= 2) {
            _checkPeer(peer);
            if (book.closed ||
                book.complete ||
                discoveryCancel.isCancelled ||
                admittedPeerIds.every(coordinator.hasVerifiedSource) ||
                standby.elapsed >= standbyBudget) {
              _closePeer(peer, reason: 'race_lost');
              await _closeTransport(peer);
              return;
            }
            // Keep a bounded, control-ready reserve until body health is
            // proven. Admission waits for actual failed-owner disposal.
            retireFailedPeers();
            await Future.any([
              _httpCancel.whenCancel,
              Future<void>.delayed(const Duration(milliseconds: 25)),
            ]);
          }
          _checkPeer(peer);
          if (book.closed || book.complete || discoveryCancel.isCancelled) {
            _closePeer(peer, reason: 'race_lost');
            await _closeTransport(peer);
            return;
          }
        }
        final source = P8PRtcPieceSource(receiver, pieces: pieces);
        if (!coordinator.add(
          source,
          diagnosticAlias: peer.id == 'server'
              ? 'seed'
              : peer.attempt?['alias'] as String?,
        )) {
          await source.close();
          return;
        }
        ready.add(source);
        if (peer.id != 'server') {
          admittedPeerIds.add(peer.id);
          admittedPeers[peer.id] = peer;
        }
        notify();
      } catch (_) {
        // A channel can open but fail its transfer identity handshake. Retire
        // signaling and the native owner before trying a different candidate.
        _closePeer(peer);
        await _closeTransport(peer);
        rethrow;
      }
    }

    final opening = <Future<void>>[];
    opening.add(() async {
      try {
        await add(await _openSeed(leased: true), null);
      } catch (_) {
      } finally {
        branches++;
        notify();
      }
    }());
    Future<void> discoverPeers({bool late = false}) async {
      final connecting = <Future<void>>{};
      // The explicit three-owner mode starts with two attempts. An extra
      // candidate may race after a short delay if no source has verified a
      // piece. A control-ready channel can still stall before useful data.
      final stagger = !late && _ordinaryPeerRaceLimit == 3;
      final hedgeDelay = const Duration(seconds: 2);
      Stopwatch? raceWatch;
      var hedgeStarted = false;
      bool canHedge() =>
          stagger &&
          !hedgeStarted &&
          !startupPieceProven &&
          !_httpsNearlyComplete;
      bool canReplaceStartupPeer() =>
          !late &&
          replaceUnprovenStartupPeers &&
          !startupPieceProven &&
          !_httpsNearlyComplete;
      try {
        if (!_active ||
            book.closed ||
            book.complete ||
            discoveryCancel.isCancelled) {
          return;
        }
        await _refreshPeers(operationCancel: discoveryCancel);
        if (!_active ||
            book.closed ||
            book.complete ||
            discoveryCancel.isCancelled) {
          return;
        }
        while (_active &&
            !book.closed &&
            !book.complete &&
            !discoveryCancel.isCancelled &&
            (late || !yieldInitialDiscovery.isCompleted) &&
            (admittedPeerIds.length < 2 ||
                canHedge() ||
                canReplaceStartupPeer()) &&
            discoveredPeerIds.length < candidateLimit) {
          // A verified source has already handed off startup. Replacements
          // use the existing bounded late-discovery clock, not the remainder
          // of the original startup batch. HTTPS never waits for this clock.
          final background =
              late || manifest!.peerCandidateReplacement && _multiHandoff;
          if (!background &&
              (_connectWatch?.elapsed ?? Duration.zero) >= _connectBudget) {
            break;
          }
          final untilHedge = hedgeDelay - (raceWatch?.elapsed ?? Duration.zero);
          final allowHedge =
              canHedge() && raceWatch != null && untilHedge <= Duration.zero;
          final raceLimit = stagger && !allowHedge ? 2 : _ordinaryPeerRaceLimit;
          final available = min(
            raceLimit - admittedPeerIds.length,
            raceLimit - _ordinaryPeerOwners.length,
          );
          if (available <= 0) {
            final waitForHedge =
                canHedge() && raceWatch != null && untilHedge > Duration.zero;
            final waitForProbe =
                canReplaceStartupPeer() && admittedPeerIds.isNotEmpty;
            if (connecting.isEmpty && !waitForHedge && !waitForProbe) break;
            final waiting = <Future<void>>[
              ...connecting,
              discoveryCancel.whenCancel.then<void>((_) {}),
              if (!late) yieldInitialDiscovery.future,
            ];
            if (waitForProbe) {
              // An open channel can still fail its first piece. Keep the
              // current candidate list available until the probe succeeds or
              // the failed owner actually frees a slot.
              discoveryChanged = Completer<void>();
              waiting.add(discoveryChanged!.future);
            }
            Timer? timer;
            if (waitForHedge) {
              final alarm = Completer<void>();
              timer = Timer(untilHedge, alarm.complete);
              waiting.add(alarm.future);
            }
            try {
              await Future.any(waiting);
            } finally {
              timer?.cancel();
              discoveryChanged = null;
            }
            continue;
          }
          final seen = <String>{};
          final candidates = candidateHistory
              .order(manifest!.apiBase, _candidates)
              .where(
                (candidate) =>
                    _canUsePeer(candidate['peer_id']) &&
                    candidate['peer_id'] != _selfId &&
                    !discoveredPeerIds.contains(candidate['peer_id']) &&
                    seen.add(_candidateKey(candidate['peer_id'] as String)) &&
                    candidate['pieces'] is List &&
                    (candidate['pieces'] as List).contains(
                      book.persistedPieces,
                    ) &&
                    P8PTransferProtocol.advertised({
                      'version': 1,
                      'transfer': candidate['p8p_transfer'],
                    }),
              )
              .take(min(available, candidateLimit - discoveredPeerIds.length))
              .toList();
          if (candidates.isEmpty) {
            if (connecting.isEmpty) break;
            await Future.any([
              ...connecting,
              if (!late) yieldInitialDiscovery.future,
            ]);
            continue;
          }
          discoveredPeerIds.addAll(
            candidates.map((candidate) => candidate['peer_id'] as String),
          );
          raceWatch ??= Stopwatch()..start();
          if (allowHedge && _ordinaryPeerOwners.length >= 2) {
            hedgeStarted = true;
            _emit('p8p', 'peer_staggered_probe', peerCount: 3);
          }
          for (final candidate in candidates) {
            late final Future<void> connection;
            connection = () async {
              try {
                final peer = await _openPeer(
                  candidate['peer_id'] as String,
                  trickle: candidate['trickle_ice_supported'] == true,
                  leased: true,
                  lateDiscovery: background,
                );
                await add(
                  peer,
                  (candidate['pieces'] as List).whereType<int>().toSet(),
                );
              } catch (_) {
                // A failed signaling attempt can still own a native close.
                // Observe that owner before considering a different identity.
                final retiring = _ordinaryPeerOwners
                    .where((peer) => peer.id == candidate['peer_id'])
                    .toList();
                try {
                  await Future.wait(retiring.map(_closeTransport));
                  for (final peer in retiring) {
                    // A returned factory is already bounded by native close.
                    // Wait for its slot retirement too, so a free slot cannot
                    // be mistaken for a still occupied one on this iteration.
                    if (peer.pc != null) await _retireOrdinaryPeer(peer);
                  }
                } catch (_) {
                  // Failed native disposal still retains its physical slot.
                }
              }
            }().whenComplete(() => connecting.remove(connection));
            connecting.add(connection);
          }
        }
      } catch (_) {
        // Discovery is optional and cannot stop HTTPS or existing sources.
      } finally {
        // Hand the single discovery loop to the body phase before joining
        // unrelated ICE attempts. Opening still owns them through cleanup.
        if (!late) initialSelectionStopped.complete();
        await Future.wait(connecting.toList());
      }
    }

    final initialPeers = () async {
      try {
        await discoverPeers();
      } finally {
        branches++;
        notify();
      }
    }();
    opening.add(initialPeers);
    var cursor = 0, pendingProbes = 0;
    final probes = <Future<void>>[];
    P8PRtcPieceSource? selected;
    void probe(P8PRtcPieceSource source) {
      if (source.closed) return;
      final httpPrefix =
          (_bootstrapInitialBytes + (_bootstrapReceivedBytes?.call() ?? 0)) ~/
          AppUpgradeP2PManifest.chunkSize;
      final end = min(book.pieceCount, book.persistedPieces + 4);
      final preferred = min(end - 1, max(book.persistedPieces, httpPrefix));
      // Prefer bytes beyond the cached HTTP prefix, then any unclaimed piece
      // in the bounded lookahead. Concurrent probes never request one piece
      // twice and remain owned by the coordinator after the first proof wins.
      final indices = [
        for (var index = preferred; index < end; index++) index,
        for (var index = book.persistedPieces; index < preferred; index++)
          index,
      ];
      for (final index in indices) {
        final request = coordinator.probe(index, source.id);
        if (request == null) continue;
        pendingProbes++;
        probes.add(() async {
          try {
            await request.verified;
            if (_active && !source.closed) {
              final peer = source.id == 'server' ? _server : _peers[source.id];
              if (peer != null) _attemptStage(peer, 'first_piece_ms');
              if (selected == null) {
                selected = source;
                startupPieceProven = true;
                _emit(
                  'hybrid',
                  'probe_verified',
                  source: source.id == 'server' ? 'seed' : 'peer',
                );
              }
            }
          } catch (_) {
            // Coordinator owns source retirement and physical cleanup.
            if ((_ordinaryPeerRaceLimit > 2 || replaceUnprovenStartupPeers) &&
                source.id != 'server' &&
                _active &&
                !book.closed) {
              coordinator.rejectUnprovenSource(source.id);
              if (replaceUnprovenStartupPeers) retireFailedPeers();
            }
          } finally {
            pendingProbes--;
            notify();
          }
        }());
        return;
      }
    }

    try {
      while (_active && !book.closed && selected == null) {
        if (_httpsNearlyComplete) break;
        coordinator.poll();
        while (cursor < ready.length) {
          probe(ready[cursor++]);
        }
        if (selected != null || branches == 2 && pendingProbes == 0) break;
        changed = Completer<void>();
        await Future.any([
          changed.future,
          _httpCancel.whenCancel,
          Future<void>.delayed(const Duration(milliseconds: 25)),
        ]);
      }
      if (selected == null || !_active) return book.persistedBytes;
      if (_httpsNearlyComplete) {
        finish('https_fallback', 'https_nearly_complete', false);
        return book.persistedBytes;
      }
      // Only a SHA-verified peer/seed piece can stop the independent HTTP
      // bootstrap. It remains paused in the writer until that stream quiesces.
      await handoff();
      _checkActive();
      _multiHandoff = true;
      // The stopped HTTP prefix can extend beyond the startup lookahead.
      // Drain it through the same four-slot writer before scheduling network
      // work, so later cached pieces cannot lose a race to an RTC request.
      // A live probe still owns its lease; do not overwrite or refund it.
      writer.resume();
      var cacheUnavailable = false;
      while (_active && !book.closed && !book.complete && !cacheUnavailable) {
        coordinator.poll();
        await writer.idle;
        final prefixBefore = book.persistedPieces;
        for (
          var index = book.persistedPieces;
          index < min(book.pieceCount, book.persistedPieces + 4) &&
              book.reservations < 4;
          index++
        ) {
          if (book.phase(index) != P8PPiecePhase.missing) continue;
          final cached = await _bootstrapPiece?.call(index);
          if (cached == null) {
            cacheUnavailable = true;
            break;
          }
          if (!_store.validPiece(index, cached)) {
            _bootstrapRejected?.call();
            _bootstrapPiece = null;
            cacheUnavailable = true;
            break;
          }
          final lease = book.request(
            index,
            'https',
            timeout: timeouts.transfer,
          );
          if (lease == null) break;
          cachedIndices.add(index);
          if (!writer.submit(lease, cached)) {
            book.cancel(lease);
            book.acknowledgeStopped(lease);
            cacheUnavailable = true;
            break;
          }
        }
        await writer.idle;
        // A different in-flight probe may own the missing prefix. Let normal
        // scheduling and physical-stop handling resolve it instead of spinning.
        if (book.persistedPieces == prefixBefore) break;
      }
      Future<Uint8List> readHttp(
        int index,
        CancelToken token, [
        void Function(int)? receivedBytes,
      ]) async {
        _checkActive();
        if (token.isCancelled) throw token.cancelError!;
        final cached = await _bootstrapPiece?.call(index);
        if (cached != null) {
          if (_store.validPiece(index, cached)) {
            cachedIndices.add(index);
            return cached;
          }
          _bootstrapRejected?.call();
          _bootstrapPiece = null;
        }
        if (receivedBytes != null && progressRangePiece != null) {
          return progressRangePiece(index, token, receivedBytes);
        }
        return rangePiece(index, token);
      }

      final http = P8PHttpPieceSource(
        writer,
        readHttp,
        readWithProgress: readHttp,
      );
      coordinator.add(http, diagnosticAlias: 'https');
      _emit('p8p', 'multisource_started');
      // A newly published APK can reach permanent nodes after startup. Keep
      // one bounded discovery task beside the running writer, with no extra
      // startup wait or overlapping GETs. Two live admitted peers remain the
      // limit; a failed body's slot is reusable only after physical disposal.
      // Negotiated replacements still spend at most four distinct identities.
      lateDiscovery = () async {
        await Future.any([initialPeers, yieldInitialDiscovery.future]);
        await initialSelectionStopped.future;
        for (final seconds in const [2, 4, 6, 8, 10, 10, 10, 10]) {
          if (!_active ||
              book.closed ||
              book.complete ||
              discoveryCancel.isCancelled ||
              (!manifest!.peerCandidateReplacement &&
                  admittedPeerIds.length >= 2) ||
              discoveredPeerIds.length >= candidateLimit ||
              book.fileBytes - book.persistedBytes <=
                  2 * AppUpgradeP2PManifest.chunkSize) {
            break;
          }
          if (!bodyReplacementPending) {
            final wait = discoveryWait = Completer<void>();
            discoveryTimer = Timer(Duration(seconds: seconds), () {
              if (!wait.isCompleted) wait.complete();
            });
            await wait.future;
            discoveryTimer?.cancel();
          }
          discoveryWait = null;
          bodyReplacementPending = false;
          if (!_active ||
              book.closed ||
              book.complete ||
              discoveryCancel.isCancelled) {
            break;
          }
          retireFailedPeers();
          // Already stopped owners can finish their bookkeeping now. An
          // unrelated pending native close must not hold a reusable slot.
          await Future<void>.delayed(Duration.zero);
          if (admittedPeerIds.length < 2) await discoverPeers(late: true);
        }
      }();
      final complete = await coordinator.run(active: () => _active);
      if (!complete && _active) _reason = 'source_timeout';
    } catch (error) {
      if (!_ended) _reason = _failureCode(error);
    } finally {
      discoveryCancel.cancel('multisource_stopped');
      discoveryTimer?.cancel();
      if (discoveryWait?.isCompleted == false) discoveryWait!.complete();
      try {
        await coordinator.close();
      } catch (_) {
        if (!_ended) _reason = 'channel_closed';
      }
      for (final peer in [..._peers.values, ?_server]) {
        if (peer.leased) _closePeer(peer);
      }
      await lateDiscovery;
      await Future.wait(retiringPeers.values.toList());
      await Future.wait(probes);
      await Future.wait(opening);
      _multiWriter = null;
      if (_ordinaryPeerRaceLimit > 2) {
        _emit(
          'performance',
          'peer_race_profile',
          metrics: {
            'peer_race_limit': _ordinaryPeerRaceLimit,
            'peak_ordinary_peer_owners': _peakOrdinaryPeerOwners,
            'admitted_peer_limit': 2,
          },
        );
      }
      final profile = coordinator.metrics;
      _emit(
        'performance',
        'multisource_profile',
        metrics: {
          for (final entry in profile.entries)
            if (!entry.key.startsWith('source_') ||
                const {
                  'source_failures',
                  'source_deferred',
                  'source_recoveries',
                  'source_rejoins',
                }.contains(entry.key))
              entry.key: entry.value,
        },
      );
      // At most six fixed local records. A single combined profile can
      // exceed OEM logcat line limits and hide precisely the evidence needed.
      for (final alias in const [
        'peer1',
        'peer2',
        'peer3',
        'peer4',
        'seed',
        'https',
      ]) {
        final prefix = 'source_${alias}_';
        final values = {
          for (final entry in profile.entries)
            if (entry.key.startsWith(prefix)) entry.key: entry.value,
        };
        if (values.isEmpty) continue;
        _emit(
          'performance',
          'source_profile',
          source: alias.startsWith('peer') ? 'peer' : alias,
          attempt: alias == 'https' ? null : alias,
          metrics: values,
        );
      }
    }
    return book.persistedBytes;
  }

  Future<void> _probeHybridSource(int index) async {
    final settled = Completer<void>();
    var completed = 0;
    void done() {
      completed++;
      if (completed == 2 && !settled.isCompleted) settled.complete();
    }

    void select(_P2PPeer peer, Uint8List bytes) {
      if (!_active || settled.isCompleted) return;
      _checkPeer(peer);
      _attemptStage(peer, 'first_piece_ms');
      _hybridWinner = peer;
      _hybridProbe = bytes;
      _hybridProbeIndex = index;
      _emit('hybrid', 'probe_verified', source: _source(peer));
      settled.complete();
    }

    unawaited(() async {
      try {
        await _refreshPeers();
        final now = DateTime.now();
        _recentPeerFailures.removeWhere((_, until) => !until.isAfter(now));
        final seen = <String>{};
        final candidates = _candidates
            .where(
              (candidate) =>
                  _canUsePeer(candidate['peer_id']) &&
                  candidate['peer_id'] != _selfId &&
                  candidate['pieces'] is List &&
                  (candidate['pieces'] as List).contains(index) &&
                  !_recentPeerFailures.containsKey(candidate['peer_id']) &&
                  seen.add(candidate['peer_id'] as String),
            )
            .take(2)
            .toList();
        // Both users negotiate immediately. Each source requests at most one
        // probe; the first verified piece chooses the sole download owner.
        await Future.wait(
          candidates.map((candidate) async {
            if (!_active || settled.isCompleted) return;
            final id = candidate['peer_id'] as String;
            try {
              final peer = await _openPeer(
                id,
                trickle: candidate['trickle_ice_supported'] == true,
              );
              final bytes = await _receivePiece(peer, index);
              select(peer, bytes);
            } catch (error) {
              if (!_active || settled.isCompleted) return;
              _reason = _sourceFailure(error, seed: false);
              _peers[id]?.failure = _reason;
              _emit('peer', _reason);
              if (_recentPeerFailures.length >= 64) {
                _recentPeerFailures.remove(_recentPeerFailures.keys.first);
              }
              _recentPeerFailures[id] = DateTime.now().add(
                const Duration(seconds: 30),
              );
              _closePeer(_peers[id]);
            }
          }),
        );
      } catch (error) {
        if (_active && !settled.isCompleted) _emit('peer', _failureCode(error));
      } finally {
        done();
      }
    }());
    unawaited(() async {
      try {
        // Race the seed immediately; discovery and native peer creation overlap.
        if (!_active || settled.isCompleted) return;
        final peer = await _openSeed();
        final bytes = await _receivePiece(peer, index);
        select(peer, bytes);
      } catch (error) {
        if (_active && !settled.isCompleted) {
          _reason = _sourceFailure(error, seed: true);
          _server?.failure = _reason;
          _emit('seed', _reason);
          _closePeer(_server);
        }
      } finally {
        done();
      }
    }());
    await settled.future;
    for (final peer in _peers.values.toList()) {
      if (!identical(peer, _hybridWinner)) {
        _closePeer(peer, reason: 'race_lost');
      }
    }
    if (!identical(_server, _hybridWinner)) {
      _closePeer(_server, reason: 'race_lost');
    }
  }

  Future<List<Uint8List>?> _tryHybridPieces(int index) async {
    if (_hybridWinner == null) {
      if (!_httpsNearlyComplete) await _probeHybridSource(index);
      if (!_active) return null;
      if (_httpsNearlyComplete) {
        finish('https_fallback', 'https_nearly_complete', false);
        return null;
      }
      if (_hybridWinner == null) return null;
      _emit('hybrid', 'source_selected', source: _source(_hybridWinner!));
    }
    try {
      final cached = await _takeBootstrapPiece(index);
      if (cached != null) return [cached];
      final peer = _hybridWinner!;
      _checkPeer(peer);
      if (_hybridProbeIndex == index && _hybridProbe != null) {
        final bytes = _hybridProbe!;
        _hybridProbe = null;
        return [bytes];
      }
      _hybridProbe = null;
      if (peer.id == 'server') return await _trySeedPieces(index);
      final available =
          _candidates.firstWhere((c) => c['peer_id'] == peer.id)['pieces']
              as List;
      if (!available.contains(index)) return null;
      if (peer.pipelineSupported) {
        return [await _receiveWindowPiece(peer, index, available)];
      }
      final indices = <int>[index];
      for (
        var next = index + 1;
        indices.length < preferredPeerBatchPieces &&
            next < manifest!.pieceHashes.length &&
            available.contains(next);
        next++
      ) {
        indices.add(next);
      }
      return indices.length == 1
          ? [await _receivePiece(peer, index)]
          : await _receivePeerBatch(peer, indices);
    } catch (error) {
      if (!_ended) {
        _reason = _sourceFailure(error, seed: _hybridWinner?.id == 'server');
      }
      return null;
    }
  }

  Future<List<Uint8List>?> _tryPeerPieces(int index) async {
    if (_peerFetchedAt == null ||
        DateTime.now().difference(_peerFetchedAt!).inSeconds >= 10) {
      try {
        await _refreshPeers();
      } catch (_) {
        if (!_active) return null;
        _candidates = [];
      }
    }
    final attempted = <String>{};
    for (var batch = 0; batch < 2 && _active; batch++) {
      final candidates = _candidates
          .where(
            (peer) =>
                _canUsePeer(peer['peer_id']) &&
                peer['peer_id'] != _selfId &&
                !_failedPeers.contains(peer['peer_id']) &&
                peer['pieces'] is List &&
                (peer['pieces'] as List).contains(index) &&
                !attempted.contains(peer['peer_id']),
          )
          .toList();
      if (batch == 0) {
        _emit(
          'peers',
          _candidates.isEmpty
              ? 'no_peer_available'
              : candidates.isEmpty
              ? 'no_matching_piece'
              : 'eligible_peers',
          peerCount: _candidates.length,
          eligiblePeerCount: candidates.length,
        );
      }
      var found = false;
      for (final candidate in candidates) {
        if (attempted.length >= 2 || !_active) break;
        found = true;
        final id = candidate['peer_id'] as String;
        attempted.add(id);
        try {
          final peer = await _openPeer(
            id,
            trickle: candidate['trickle_ice_supported'] == true,
          );
          final bootstrap = await _takeBootstrapPiece(index);
          if (bootstrap != null) return [bootstrap];
          final available = (candidate['pieces'] as List).toSet();
          if (_firstPiecePersisted && peer.pipelineSupported) {
            return [await _receiveWindowPiece(peer, index, available.toList())];
          }
          final indices = <int>[index];
          if (_firstPiecePersisted) {
            for (
              var next = index + 1;
              indices.length < preferredPeerBatchPieces &&
                  next < manifest!.pieceHashes.length &&
                  available.contains(next);
              next++
            ) {
              indices.add(next);
            }
          }
          final List<Uint8List> bytes;
          if (indices.length == 1) {
            bytes = [await _receivePiece(peer, index)];
          } else {
            _emit('peer', 'batch_four_selected', once: true);
            bytes = await _receivePeerBatch(peer, indices);
          }
          if (!_active) return null;
          _emit('peer', 'piece_verified', once: true);
          return bytes;
        } catch (error) {
          _reason = _sourceFailure(error, seed: false);
          _failedPeers.add(id);
          _emit('peer', _reason);
          _closePeer(_peers[id]);
        }
      }
      // Empty peers immediately tries the seed; failed peers permit one extra
      // discovery query with deduplication and a total of two source attempts.
      if (!found || attempted.length >= 2 || !_active) break;
      if (batch == 0) {
        try {
          await _refreshPeers();
        } catch (_) {
          break;
        }
      }
    }
    return null;
  }

  Future<Uint8List> _receiveWindowPiece(
    _P2PPeer peer,
    int index,
    List available,
  ) async {
    _checkPeer(peer);
    if (peer.window == null) {
      final indices = <int>[];
      for (
        var next = index;
        next < manifest!.pieceHashes.length && available.contains(next);
        next++
      ) {
        indices.add(next);
      }
      peer.window = AppUpgradeP2PWindowReceiver(
        _store,
        indices,
        (values) => _control(peer, {
          'type': 'get-pieces',
          'indices': values,
          if (peer.p8pWindow != null)
            'p8p': P8PWindowProtocol.request(peer.p8pWindow!.window),
        }),
        controller: _p8p && peer.p8pSupported
            ? (peer.p8pWindow = P8PWindowController())
            : null,
        onWindowChanged: (window) => _emit(
          'p8p',
          'window_changed',
          source: _source(peer),
          metrics: {'p8p_window': window},
        ),
      );
      _emit(
        'transfer',
        peer.p8pWindow == null
            ? 'pipeline_four_selected'
            : 'p8p_window_selected',
        source: _source(peer),
        once: true,
      );
    }
    return peer.window!.take(index, timeouts.transfer);
  }

  Future<List<Uint8List>> _receivePeerBatch(
    _P2PPeer peer,
    List<int> indices,
  ) async {
    _checkPeer(peer);
    if (peer.piece != null || peer.batch != null) {
      throw const AppUpgradeP2PFailure('busy');
    }
    Timer? deadline;
    late AppUpgradeP2PBatchReceiver batch;
    void renewDeadline() {
      deadline?.cancel();
      deadline = Timer(
        timeouts.transfer,
        () => batch.fail(const AppUpgradeP2PFailure('peer_transfer_timeout')),
      );
    }

    batch = AppUpgradeP2PBatchReceiver(
      _store,
      indices,
      maxPieces: 4,
      onPieceVerified: renewDeadline,
    );
    peer.batch = batch;
    renewDeadline();
    final received = batch.completed.future;
    unawaited(received.then<void>((_) {}, onError: (Object _) {}));
    try {
      await _control(peer, {'type': 'get-pieces', 'indices': indices});
      final bytes = await received;
      _checkPeer(peer);
      return bytes;
    } finally {
      deadline?.cancel();
      peer.batch = null;
    }
  }

  Future<void> _refreshPeers({CancelToken? operationCancel}) async {
    final p8p =
        enableP8P && (manifest!.p8pAdaptiveWindow || manifest!.p8pTransfer);
    final identity =
        p8p &&
        manifest!.peerCandidateReplacement &&
        manifest!.peerCandidateIdentity;
    final json = await _request(
      'peers',
      '${manifest!.apiBase}/peers${p8p ? '?p8p=1${identity ? '&candidate_identity=1' : ''}${p8pSourcePortDiversity && manifest!.p8pTransfer && _sessionTrickle ? '&ice_diversity=1' : ''}' : ''}',
      operationCancel: operationCancel,
    );
    final values = json['peers'];
    if (values is! List) {
      throw const AppUpgradeP2PFailure('peers_response_invalid');
    }
    _candidates = values.whereType<Map>().take(16).toList();
    _peerFetchedAt = DateTime.now();
    _emit('peers', 'discovered', peerCount: _candidates.length);
  }

  Future<Uint8List?> _trySeedPiece(int index) async {
    try {
      final peer = await _openSeed();
      final bootstrap = await _takeBootstrapPiece(index);
      if (bootstrap != null) return bootstrap;
      final bytes = await _receivePiece(peer, index);
      if (!_active) return null;
      _emit('seed', 'piece_verified', once: true);
      return bytes;
    } catch (error) {
      if (!_ended) _reason = _sourceFailure(error, seed: true);
      _emit('seed', _reason);
      _closePeer(_server);
      return null;
    }
  }

  Future<Uint8List?> _takeBootstrapPiece(int index) async {
    if (_bootstrapPiece == null) return null;
    _bootstrapHandoffStarted = true;
    final bytes = await _bootstrapPiece!(index);
    _checkActive();
    if (bytes == null) return null;
    Uint8List owned;
    try {
      owned = _store.verifyOwnedPiece(index, bytes);
    } on AppUpgradeP2PFailure {
      _bootstrapRejected?.call();
      _bootstrapPiece = null;
      return null;
    }
    _piecesFromHttps = true;
    return owned;
  }

  Future<List<Uint8List>?> _trySeedPieces(int index) async {
    // Keep the first piece on the original startup deadline. After it is
    // persisted, request a bounded batch instead of a network round trip
    // after every disk flush. User peers keep their own bounded batch receiver.
    if (!_firstPiecePersisted) {
      final bytes = await _trySeedPiece(index);
      return bytes == null ? null : [bytes];
    }
    try {
      final peer = await _openSeed();
      final bootstrap = await _takeBootstrapPiece(index);
      if (bootstrap != null) return [bootstrap];
      _checkPeer(peer);
      if (peer.pipelineSupported) {
        return [
          await _receiveWindowPiece(
            peer,
            index,
            List<int>.generate(
              manifest!.pieceHashes.length - index,
              (offset) => index + offset,
            ),
          ),
        ];
      }
      if (peer.piece != null || peer.batch != null) {
        throw const AppUpgradeP2PFailure('busy');
      }
      final indices = List<int>.generate(
        min(
          min(preferredSeedBatchPieces, peer.maxBatchPieces),
          manifest!.pieceHashes.length - index,
        ),
        (offset) => index + offset,
      );
      Timer? deadline;
      late AppUpgradeP2PBatchReceiver batch;
      void renewDeadline() {
        deadline?.cancel();
        deadline = Timer(
          timeouts.transfer,
          () => batch.fail(
            const AppUpgradeP2PFailure('server_seed_transfer_timeout'),
          ),
        );
      }

      batch = AppUpgradeP2PBatchReceiver(
        _store,
        indices,
        maxPieces: min(preferredSeedBatchPieces, peer.maxBatchPieces),
        onPieceVerified: renewDeadline,
      );
      peer.batch = batch;
      // Preserve the existing per-piece timeout, rather than forcing four
      // healthy pieces to finish within the time allowance for one piece.
      renewDeadline();
      final received = batch.completed.future;
      unawaited(received.then<void>((_) {}, onError: (Object _) {}));
      try {
        await _control(peer, {'type': 'get-pieces', 'indices': indices});
        final bytes = await received;
        _checkPeer(peer);
        return bytes;
      } finally {
        deadline?.cancel();
        peer.batch = null;
      }
    } catch (error) {
      if (!_ended) _reason = _sourceFailure(error, seed: true);
      _emit('seed', _reason);
      _closePeer(_server);
      return null;
    }
  }

  void _armPeerDeadline(_P2PPeer peer) {
    if (_hybrid && !peer.inbound && !peer.lateDiscovery) return;
    peer.deadline?.cancel();
    peer.deadline = Timer(_remaining(peer), () {
      if (_active &&
          !peer.closed &&
          peer.channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
        peer.failure = _hybrid && peer.id != 'server'
            ? 'peer_connect_timeout'
            : 'p2p_budget_exhausted';
        _closePeer(peer);
      }
    });
  }

  Future<_P2PPeer> _makePeer(
    String id, {
    bool inbound = false,
    bool trickle = false,
    bool leased = false,
    Duration? startupLimit,
    bool lateDiscovery = false,
    AppUpgradeUploadSlot? uploadSlot,
  }) async {
    _checkActive();
    if (id != 'server' &&
        _ordinaryPeerOwners.length >= (inbound ? 2 : _ordinaryPeerRaceLimit)) {
      throw const AppUpgradeP2PFailure('peer_capacity');
    }
    final peer = _P2PPeer(id, inbound);
    if (id != 'server') _ordinaryPeerOwners.add(peer);
    _peakOrdinaryPeerOwners = max(
      _peakOrdinaryPeerOwners,
      _ordinaryPeerOwners.length,
    );
    peer.uploadSlot = uploadSlot;
    peer.startupLimit = startupLimit;
    peer.lateDiscovery = lateDiscovery;
    peer.leased = leased;
    final attemptLimit = _p8p && manifest!.peerCandidateReplacement
        ? 6
        : manifest!.serverOfferCancel
        ? 4
        : 3;
    if (!inbound && _attempts.length < attemptLimit) {
      peer.attempt = {
        'alias': id == 'server'
            ? manifest!.serverOfferCancel && _serverAttempts > 1
                  ? 'seed2'
                  : 'seed'
            : 'peer${++_peerAlias}',
        'started_ms': _sessionElapsed() ?? 0,
      };
      _attempts.add(peer.attempt!);
    }
    peer.trickle =
        manifest!.trickleIce &&
        (id == 'server' || (_sessionTrickle && trickle));
    if (id == 'server') {
      _server = peer;
    } else {
      _peers[id] = peer;
    }
    _armPeerDeadline(peer);
    try {
      final creation =
          peerFactory({
            'iceServers': manifest!.stunUrls
                .map((url) => <String, dynamic>{'urls': url})
                .toList(),
          }).then((pc) {
            // Register the native owner before _rtc can reject an interrupted
            // negotiation. A factory that finishes after retirement still owns
            // its native connection and must release it here.
            peer.pc = pc;
            if (peer.closed || !_active) {
              unawaited(_trackTransportRetirement(_releaseNativePeer(pc)));
            }
            return pc;
          });
      peer.creation = creation;
      // Keep factory rejection observed even if _rtc exits before awaiting it.
      unawaited(creation.then<void>((_) {}, onError: (Object _) {}));
      final pc = await _rtc(peer, () => creation);
      for (final candidate in _earlyCandidates.remove(id) ?? <Map>[]) {
        _queueRemoteCandidate(candidate);
      }
      if (!_active || peer.closed) {
        unawaited(_trackTransportRetirement(_releaseNativePeer(pc)));
        throw const AppUpgradeP2PFailure('session_stopped');
      }
      pc.onDataChannel = (channel) => _bindChannel(peer, channel);
      if (!peer.inbound && !_cacheSharing && receiveBufferFactory != null) {
        try {
          peer.receiveBuffer = receiveBufferFactory!();
        } catch (_) {}
      }
      if (peer.trickle || peer.receiveBuffer != null) {
        pc.onIceCandidate = (candidate) {
          if (peer.trickle) _queueLocalCandidate(peer, candidate);
          if (_active && !peer.closed) {
            try {
              peer.receiveBuffer?.addCandidate(candidate.candidate);
            } catch (_) {}
          }
        };
      }
      pc.onIceGatheringState = (state) {
        if (!_active || peer.closed) return;
        _emit(
          'ice_gather',
          switch (state) {
            RTCIceGatheringState.RTCIceGatheringStateNew => 'ice_new',
            RTCIceGatheringState.RTCIceGatheringStateGathering =>
              'ice_gathering',
            RTCIceGatheringState.RTCIceGatheringStateComplete => 'ice_complete',
          },
          source: _source(peer),
          durationMs: peer.gatherWatch?.elapsedMilliseconds,
        );
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !peer.iceComplete.isCompleted) {
          peer.iceComplete.complete();
        }
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            peer.trickle) {
          _queueLocalCandidate(peer, null);
        }
      };
      pc.onIceConnectionState = (state) {
        if (!_active || peer.closed) return;
        peer.iceState = state;
        if (state == RTCIceConnectionState.RTCIceConnectionStateChecking &&
            !peer.inbound &&
            peer.iceStatsAttempts == 0 &&
            peer.iceStatsTimer == null) {
          peer.iceStatsTimer = Timer(
            const Duration(milliseconds: 400),
            () => unawaited(_sampleIceChecks(peer)),
          );
        }
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _iceConnectMs ??= _sessionElapsed();
          _attemptStage(peer, 'ice_connect_ms');
        }
        _emit(
          'ice_connection',
          switch (state) {
            RTCIceConnectionState.RTCIceConnectionStateNew => 'ice_new',
            RTCIceConnectionState.RTCIceConnectionStateChecking =>
              'ice_checking',
            RTCIceConnectionState.RTCIceConnectionStateConnected =>
              'ice_connected',
            RTCIceConnectionState.RTCIceConnectionStateCompleted =>
              'ice_completed',
            RTCIceConnectionState.RTCIceConnectionStateDisconnected =>
              'ice_disconnected',
            RTCIceConnectionState.RTCIceConnectionStateFailed => 'ice_failed',
            RTCIceConnectionState.RTCIceConnectionStateClosed => 'ice_closed',
            _ => 'unknown_error',
          },
          source: _source(peer),
          attempt: peer.attempt?['alias'] as String?,
        );
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          peer.failure = 'ice_failed';
          _closePeer(peer);
        }
      };
      return peer;
    } catch (_) {
      _closePeer(peer);
      rethrow;
    }
  }

  String _candidateKey(String id) {
    if (_p8pCandidateAttemptLimit != null && manifest!.peerCandidateIdentity) {
      for (final candidate in _candidates) {
        if (candidate['peer_id'] != id) continue;
        final key = candidate['candidate_key'];
        if (key is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
          return 'installation:$key';
        }
      }
    }
    return 'session:$id';
  }

  bool _canUsePeer(Object? id) {
    if (!_isPeerId(id)) return false;
    final peer = _peers[id];
    if (peer != null &&
        !peer.closed &&
        peer.channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      return true;
    }
    return !_outboundPeerIds.contains(id) &&
        !_attemptedCandidateKeys.contains(_candidateKey(id as String)) &&
        _outboundPeerIds.length < (_p8pCandidateAttemptLimit ?? 64);
  }

  Future<_P2PPeer> _openPeer(
    String id, {
    bool trickle = false,
    bool leased = false,
    bool lateDiscovery = false,
  }) async {
    final existing = _peers[id];
    if (existing != null &&
        !existing.closed &&
        existing.channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      if (_outboundPeerIds.length < 64) _outboundPeerIds.add(id);
      return existing;
    }
    // Peer signaling has one ICE generation per authenticated peer pair.
    // Unlike the seed's negotiated Offer identity/cancel protocol, it cannot
    // reset an end marker or distinguish delayed candidates for a fresh RTC.
    // Keep a live channel reusable, but never reopen a consumed peer identity
    // when P8P falls back to the v1 path. Fresh registrations remain eligible.
    if (_outboundPeerIds.contains(id) ||
        _attemptedCandidateKeys.contains(_candidateKey(id))) {
      throw const AppUpgradeP2PFailure('peer_not_available');
    }
    if (_outboundPeerIds.length >= (_p8pCandidateAttemptLimit ?? 64)) {
      throw const AppUpgradeP2PFailure('peer_capacity');
    }
    _closePeer(existing);
    if (_peers.length >= _ordinaryPeerRaceLimit) {
      throw const AppUpgradeP2PFailure('peer_capacity');
    }
    _outboundPeerIds.add(id);
    _attemptedCandidateKeys.add(_candidateKey(id));
    final peer = await _makePeer(
      id,
      trickle: trickle,
      leased: leased,
      lateDiscovery: lateDiscovery,
    );
    if (lateDiscovery) {
      // Resume prompt Answer polling from the previous transfer's idle cadence.
      // The in-flight guard still permits only one physical signals request.
      _signalTimer?.cancel();
      _emptySignalPolls = 0;
      unawaited(_pollSignals());
    }
    try {
      return await _connect(peer, () async {
        final sdp = await _localOffer(peer);
        Map<String, Object>? diversity;
        if (p8pSourcePortDiversity &&
            enableP8P &&
            peer.leased &&
            peer.trickle) {
          for (final candidate in _candidates) {
            if (candidate['peer_id'] == id) {
              diversity = P8PSourceDiversity.offer(
                candidate['ice_diversity'],
                sdp,
              );
              break;
            }
          }
        }
        _peerEvent(peer, 'offer_post_started');
        // The existing service and nodes buffer pre-SDP candidates. In the
        // candidate policy, do not spend an extra Offer HTTP RTT before trickle.
        if (_fastCandidateSignaling) _startCandidates(peer);
        await _request(
          'signal',
          '${manifest!.apiBase}/signal',
          body: {
            'peer_id': id,
            'type': 'offer',
            'sdp': sdp,
            'ice_diversity': ?diversity,
            if (manifest!.attemptDiagnostics && peer.attempt != null)
              'attempt_alias': peer.attempt!['alias'],
            if (peer.trickle) 'trickle_ice': true,
          },
          owner: peer,
        );
        _peerEvent(peer, 'offer_accepted');
        _startCandidates(peer);
        await peer.answer.future.timeout(
          _hybrid ? _remaining(peer) : timeouts.answer,
          onTimeout: () =>
              throw const AppUpgradeP2PFailure('peer_connect_timeout'),
        );
        _checkPeer(peer);
        await _waitOpen(peer);
        return peer;
      });
    } catch (error) {
      peer.failure = _sourceFailure(error, seed: peer.id == 'server');
      _closePeer(peer);
      rethrow;
    }
  }

  Future<_P2PPeer> _openSeed({bool leased = false}) async {
    // Opt-in P8P uses the original session clock for both attempts. HTTPS is
    // still independent, and a fresh peer cannot own a slot before both sides
    // have acknowledged closure of the first one.
    if (!_p8p || !_hybrid || !manifest!.serverOfferCancel) {
      return _openSeedAttempt(leased: leased);
    }
    _P2PPeer? previous;
    final left = _connectBudget - (_connectWatch?.elapsed ?? Duration.zero);
    final split = _serverAttempts == 0 && left >= const Duration(seconds: 2)
        ? Duration(
            milliseconds: (left.inMilliseconds * .6).floor().clamp(1, 8000),
          )
        : null;
    try {
      return await _openSeedAttempt(
        leased: leased,
        startupLimit: split,
        onPeer: (peer) => previous = peer,
      );
    } on AppUpgradeP2PFailure catch (error) {
      final peer = previous;
      final offerId = peer?.offerId;
      final connection = peer?.pc;
      if (split == null ||
          peer == null ||
          !peer.offerSubmitted ||
          offerId == null ||
          connection == null ||
          !_active ||
          _serverAttempts >= 2 ||
          _httpsNearlyComplete ||
          !const {
            'ice_failed',
            'channel_closed',
            'server_seed_connect_timeout',
            'seed_connect_retry_timeout',
          }.contains(error.code)) {
        rethrow;
      }
      _closePeer(peer);
      try {
        // Both operations retire the old offer, so they can share the time
        // remaining. A new offer still requires both owners to be released.
        final [localReleased, serverClosed] = await Future.wait([
          _closeTransport(peer)
              .timeout(_remainingConnectBudget())
              .then((_) => _releasedNativePeers[connection] == true),
          _cancelSeedOffer(offerId),
        ]);
        if (!localReleased ||
            !serverClosed ||
            _remainingConnectBudget() < const Duration(seconds: 1) ||
            _httpsNearlyComplete) {
          rethrow;
        }
        _checkActive();
        _seedReconnectBlocked = false;
      } catch (_) {
        // A missing, failed or pending ACK never authorizes another slot.
        throw error;
      }
      _emit('seed', 'seed_connect_retry');
      return _openSeedAttempt(leased: leased);
    }
  }

  Future<bool> _cancelSeedOffer(String offerId) async {
    for (var poll = 0; ; poll++) {
      _checkActive();
      try {
        final reply = await _request(
          'server_cancel',
          '${manifest!.apiBase}/server-cancel',
          body: {'offer_id': offerId},
        );
        return reply['ok'] == true &&
            reply['state'] == 'closed' &&
            reply['offer_id'] == offerId;
      } on AppUpgradeP2PFailure catch (pending) {
        if (pending.code != 'server_offer_cancel_pending' || poll == 2) rethrow;
        await Future<void>.delayed(
          const Duration(milliseconds: 100),
        ).timeout(_remainingConnectBudget());
      }
    }
  }

  Duration _remainingConnectBudget() {
    final left = _connectBudget - (_connectWatch?.elapsed ?? Duration.zero);
    if (left <= Duration.zero) {
      throw const AppUpgradeP2PFailure('p2p_budget_exhausted');
    }
    return left;
  }

  Future<_P2PPeer> _openSeedAttempt({
    bool leased = false,
    Duration? startupLimit,
    void Function(_P2PPeer)? onPeer,
  }) async {
    if (_seedReconnectBlocked) {
      throw const AppUpgradeP2PFailure('server_offer_attempt_limit');
    }
    if (_server != null &&
        !_server!.closed &&
        _server!.channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      return _server!;
    }
    if (_seedPreparation == null) _closePeer(_server);
    if (_serverAttempts >= 2) {
      throw const AppUpgradeP2PFailure('server_offer_attempt_limit');
    }
    _serverAttempts++;
    final preparation = _seedPreparation;
    _seedPreparation = null;
    final prepared = preparation == null ? null : await preparation;
    final reusable = prepared != null && !prepared.peer.closed && _active;
    final peer = reusable
        ? prepared.peer
        : await _makePeer('server', leased: leased, startupLimit: startupLimit);
    if (reusable) peer.startupLimit = startupLimit;
    onPeer?.call(peer);
    try {
      return await _connect(peer, () async {
        if ((manifest!.trickleIce || manifest!.serverOfferCancel) &&
            peer.offerId == null) {
          final random = Random.secure();
          peer.offerId = List.generate(
            16,
            (_) => random.nextInt(256),
          ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
        }
        final sdp = reusable ? prepared.sdp : await _localOffer(peer);
        if (_sessionServerTrickle && peer.offerId != null) {
          _serverCandidates.register(peer.offerId!);
        }
        // Candidate posts run alongside the offer; the server buffers by offer ID.
        _startCandidates(peer);
        _peerEvent(peer, 'offer_post_started');
        peer.offerSubmitted = true;
        final answer = await _request(
          'server_offer',
          manifest!.serverSeedUrl,
          owner: peer,
          body: {
            'sdp': sdp,
            if (peer.offerId != null) 'offer_id': peer.offerId,
          },
        );
        _checkPeer(peer);
        _peerEvent(peer, 'offer_accepted');
        // Never send six pieces to an old seed. Capability is advertised by
        // the authenticated answer for this connection, not assumed from UI.
        final cap = answer['max_batch_pieces'];
        peer.maxBatchPieces = cap is int && cap >= 1 && cap <= 6 ? cap : 4;
        _emit(
          'seed',
          min(preferredSeedBatchPieces, peer.maxBatchPieces) == 6
              ? 'batch_six_selected'
              : 'batch_four_selected',
          once: true,
        );
        if (answer['type'] != 'answer' ||
            answer['sdp'] is! String ||
            (answer['sdp'] as String).isEmpty) {
          throw const AppUpgradeP2PFailure('server_answer_invalid');
        }
        await _rtc(
          peer,
          () => peer.pc!.setRemoteDescription(
            RTCSessionDescription(answer['sdp'] as String, 'answer'),
          ),
        );
        peer.remoteIceTypes |= _iceCandidateTypes(answer['sdp'] as String);
        peer.remoteReady = true;
        _drainRemoteCandidates(peer);
        _peerEvent(peer, 'remote_description_applied');
        _attemptStage(peer, 'answer_ms');
        _emit('rtc', 'answer_received', source: 'seed');
        await _waitOpen(peer);
        return peer;
      });
    } catch (error) {
      peer.failure = _sourceFailure(error, seed: peer.id == 'server');
      _closePeer(peer);
      rethrow;
    }
  }

  Future<({_P2PPeer peer, String sdp})?> _prepareSeed() async {
    _P2PPeer? peer;
    try {
      peer = await _makePeer('server');
      if (manifest!.trickleIce) {
        final random = Random.secure();
        peer.offerId = List.generate(
          16,
          (_) => random.nextInt(256),
        ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }
      final sdp = await _localOffer(peer);
      _checkPeer(peer);
      return (peer: peer, sdp: sdp);
    } catch (_) {
      _closePeer(peer);
      // Consume preparation errors here: a cancelled/discarded warm-up must
      // not produce an unhandled future or prevent the normal HTTPS fallback.
      return null;
    }
  }

  Future<String> _localOffer(_P2PPeer peer) async {
    _checkPeer(peer);
    _bindChannel(
      peer,
      await _rtc(
        peer,
        () => peer.pc!.createDataChannel(
          peer.leased
              ? P8PTransferProtocol.channel
              : AppUpgradeP2PManifest.channelLabel,
          RTCDataChannelInit()..ordered = true,
        ),
      ),
    );
    // flutter_webrtc defaults to receiving audio and video even for a file
    // channel. Negotiate only SCTP; unused media adds transports/candidates and
    // prevents the seed from using its unused data-channel ICE preparation.
    final offer = await _rtc(
      peer,
      () => peer.pc!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': false,
          'OfferToReceiveVideo': false,
        },
        'optional': <Map<String, dynamic>>[],
      }),
    );
    _checkPeer(peer);
    peer.gatherWatch = Stopwatch()..start();
    _emit('ice_gather', 'started', source: _source(peer));
    await _rtc(peer, () => peer.pc!.setLocalDescription(offer));
    final sdp = await _localSdp(peer);
    peer.localIceTypes |= _iceCandidateTypes(sdp);
    _emit('rtc', 'offer_ready', source: _source(peer));
    return sdp;
  }

  String _source(_P2PPeer peer) => peer.inbound
      ? 'sharing'
      : peer.id == 'server'
      ? 'seed'
      : 'peer';

  static Duration _shorter(Duration first, Duration second) =>
      first < second ? first : second;

  int? _sessionElapsed() => _connectWatch?.elapsedMilliseconds.clamp(0, 120000);

  Duration _remaining(_P2PPeer peer) {
    final watch = peer.inbound || peer.lateDiscovery
        ? peer.connectWatch
        : _connectWatch;
    final budget = peer.lateDiscovery
        ? manifest!.connectTimeout
        : _connectBudget;
    var left = budget - (watch?.elapsed ?? Duration.zero);
    if (left <= Duration.zero) {
      throw AppUpgradeP2PFailure(
        peer.lateDiscovery ? 'peer_connect_timeout' : 'p2p_budget_exhausted',
      );
    }
    if (peer.startupLimit != null &&
        peer.channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      final attemptLeft = peer.startupLimit! - peer.connectWatch.elapsed;
      if (attemptLeft <= Duration.zero) {
        throw const AppUpgradeP2PFailure('seed_connect_retry_timeout');
      }
      left = _shorter(left, attemptLeft);
    }
    if (!peer.inbound &&
        peer.id != 'server' &&
        peer.channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      if (_hybrid) return left;
      // Native creation belongs to the peer attempt too. Otherwise it could
      // consume the seed reserve before _connect starts its shorter timer.
      final reserve = Duration(
        milliseconds: (_connectBudget.inMilliseconds * .4).round().clamp(
          1,
          3000,
        ),
      );
      left = _shorter(
        left - reserve,
        const Duration(seconds: 3) - peer.connectWatch.elapsed,
      );
      if (left <= Duration.zero) {
        throw const AppUpgradeP2PFailure('peer_connect_timeout');
      }
    }
    return left;
  }

  Future<T> _connect<T>(_P2PPeer peer, Future<T> Function() operation) async {
    try {
      final remaining = _remaining(peer);
      final userPeer = !peer.inbound && peer.id != 'server';
      final limit = remaining;
      return await operation().timeout(
        limit,
        onTimeout: () {
          throw AppUpgradeP2PFailure(
            userPeer
                ? 'peer_connect_timeout'
                : peer.startupLimit != null
                ? 'seed_connect_retry_timeout'
                : 'p2p_budget_exhausted',
          );
        },
      );
    } catch (error) {
      peer.failure = _sourceFailure(error, seed: peer.id == 'server');
      _closePeer(peer);
      rethrow;
    }
  }

  Future<String> _localSdp(_P2PPeer peer) async {
    if (!peer.trickle) return _gatherLocalSdp(peer);
    final local = await _rtc(peer, () => peer.pc!.getLocalDescription());
    final sdp = local?.sdp ?? '';
    if (sdp.isEmpty) throw const AppUpgradeP2PFailure('local_sdp_invalid');
    return sdp;
  }

  void _queueLocalCandidate(_P2PPeer peer, RTCIceCandidate? candidate) {
    if (!_active ||
        peer.closed ||
        peer.candidateFailed ||
        (peer.gatherWatch?.elapsed ?? Duration.zero) >
            manifest!.iceGatherTimeout) {
      return;
    }
    final value = candidate?.candidate;
    // Keep bounded queues and never log SDP/candidate addresses.
    final payload = value == null || value.isEmpty
        ? null
        : <String, Object?>{
            'candidate': value,
            'sdpMid': candidate!.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          };
    final key = jsonEncode(payload);
    if (peer.localCandidatesSeen.contains(key) ||
        (payload != null && peer.localCandidatesSeen.length >= 32)) {
      return;
    }
    peer.localCandidatesSeen.add(key);
    if (value != null) peer.localIceTypes |= _iceCandidateTypes(value);
    if (value != null && value.isNotEmpty) {
      final kind = RegExp(
        r'\btyp (host|srflx|relay)\b',
      ).firstMatch(value)?.group(1);
      if (kind != null) {
        _iceCounts[kind] = ((_iceCounts[kind] ?? 0) + 1).clamp(0, 64);
      }
    }
    peer.localCandidates.add(payload);
    if (peer.candidatesStarted) _startCandidates(peer);
  }

  bool get _fastCandidateSignaling =>
      fastSignaling || (manifest!.fastSignalPollMs ?? 250) < 250;

  void _startCandidates(_P2PPeer peer) {
    if (!peer.trickle || !_active || peer.closed) return;
    peer.candidatesStarted = true;
    // One ordered writer posts bounded waves. End-of-candidates is a barrier:
    // it never overtakes any prior candidate request.
    if (peer.candidatesBusy || peer.candidateFailed) return;
    peer.candidatesBusy = true;
    unawaited(() async {
      try {
        while (_active && !peer.closed && peer.localCandidates.isNotEmpty) {
          if (manifest!.candidateBatch &&
              (peer.firstLocalCandidatePosted || !_fastCandidateSignaling) &&
              peer.localCandidates.length < 8 &&
              !peer.localCandidates.contains(null)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          if (!_active || peer.closed) break;
          if (!peer.inbound) _remaining(peer);
          final seed = peer.id == 'server';
          final wave = <Map<String, Object?>?>[];
          final limit = manifest!.candidateBatch ? 8 : 1;
          while (wave.length < limit && peer.localCandidates.isNotEmpty) {
            if (peer.localCandidates.first == null && wave.isNotEmpty) break;
            final candidate = peer.localCandidates.removeAt(0);
            wave.add(candidate);
            if (candidate == null) break;
          }
          final body = Map<String, Object?>.unmodifiable({
            if (seed) 'offer_id': peer.offerId else 'peer_id': peer.id,
            if (manifest!.candidateBatch)
              'candidates': List<Map<String, Object?>?>.unmodifiable(wave)
            else
              'candidate': wave.single,
          });
          for (var attempt = 0; ; attempt++) {
            _checkPeer(peer);
            if (!peer.inbound) _remaining(peer);
            try {
              await _request(
                seed ? 'server_candidate' : 'candidate',
                '${manifest!.apiBase}/${seed ? 'server-candidate' : 'candidate'}',
                body: body,
                owner: peer,
              );
              break;
            } on AppUpgradeP2PFailure catch (error) {
              // The negotiated batch contract de-duplicates even after inbox
              // delivery. Replay the same immutable wave once after a lost ACK
              // or temporary queue pressure. Invalid payloads and limits stay
              // final, and every replay shares the owner's original budget.
              if (attempt != 0 ||
                  !manifest!.candidateBatch ||
                  !(_retryableReport(error.code) ||
                      error.code == 'candidate_queue_full' ||
                      error.code == 'candidate_processing_timeout')) {
                rethrow;
              }
              _emit('candidate', 'retry', source: _source(peer));
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
          peer.firstLocalCandidatePosted = true;
          _peerEvent(peer, 'first_local_candidate_posted');
        }
      } catch (error) {
        peer.candidateFailed = true;
        peer.localCandidates.clear();
        if (_active && !peer.closed) {
          // This is a signaling HTTP/API failure, not a native ICE
          // candidate-error event (for example WebRTC error 701).
          _emit('candidate', _failureCode(error), source: _source(peer));
        }
      } finally {
        peer.candidatesBusy = false;
      }
    }());
  }

  void _queueRemoteCandidate(Map message) {
    final id = message['from_peer_id'];
    if (!_isPeerId(id) || id == _selfId || !message.containsKey('candidate')) {
      return;
    }
    final peer = _peers[id];
    if (peer == null) {
      // Candidate HTTP requests can overtake the offer. Preserve a bounded
      // pre-SDP inbox; it never creates a connection or authorizes sharing.
      if (!_earlyCandidates.containsKey(id) && _earlyCandidates.length >= 16) {
        return;
      }
      final queued = _earlyCandidates.putIfAbsent(id as String, () => []);
      if (queued.length < 33) queued.add(message);
      return;
    }
    if (peer.closed) return;
    final raw = message['candidate'];
    if (raw != null && raw is! Map) return;
    if (raw is Map &&
        (raw['candidate'] is! String ||
            (raw['candidate'] as String).length > 2048 ||
            raw['sdpMid'] != null && raw['sdpMid'] is! String ||
            raw['sdpMLineIndex'] != null && raw['sdpMLineIndex'] is! int)) {
      return;
    }
    final key = jsonEncode(raw);
    if (peer.remoteCandidatesSeen.contains(key) ||
        (raw != null && peer.remoteCandidatesSeen.length >= 32)) {
      return;
    }
    peer.remoteCandidatesSeen.add(key);
    peer.remoteCandidates.add(
      raw == null
          ? null
          : RTCIceCandidate(
              raw['candidate'] as String,
              raw['sdpMid'] as String?,
              raw['sdpMLineIndex'] as int?,
            ),
    );
    _drainRemoteCandidates(peer);
  }

  void _drainRemoteCandidates(_P2PPeer peer) {
    if (!peer.remoteReady || peer.remoteBusy || peer.closed || !_active) return;
    peer.remoteBusy = true;
    unawaited(() async {
      try {
        while (_active && !peer.closed && peer.remoteCandidates.isNotEmpty) {
          final candidate = peer.remoteCandidates.removeAt(0);
          // Android's native adapter does not expose addIceCandidate(null).
          // End markers terminate our queue; ICE can connect with the candidates
          // already added and must not fail on a synthetic empty candidate.
          if (candidate == null) continue;
          await _rtc(peer, () => peer.pc!.addCandidate(candidate));
          peer.remoteTrickleApplied++;
          peer.remoteIceTypes |= _iceCandidateTypes(candidate.candidate ?? '');
          _peerEvent(peer, 'remote_candidate_applied');
          if (_iceCandidateTypes(candidate.candidate ?? '') != 0) {
            peer.remoteIceProgress?.call();
          }
        }
      } catch (error) {
        if (_active && !peer.closed) {
          peer.failure = _failureCode(error);
          _emit('candidate', peer.failure, source: _source(peer));
          _closePeer(peer);
        }
      } finally {
        peer.remoteBusy = false;
      }
    }());
  }

  /// Every native operation is bounded separately. Recheck ownership after the
  /// await so a late result cannot advance an abandoned negotiation.
  Future<T> _rtc<T>(_P2PPeer peer, Future<T> Function() operation) async {
    _checkPeer(peer);
    final remaining =
        peer.channel?.state != RTCDataChannelState.RTCDataChannelOpen
        ? _remaining(peer)
        : timeouts.rtcOperation;
    final limit = remaining < timeouts.rtcOperation
        ? remaining
        : timeouts.rtcOperation;
    late T value;
    try {
      value = await operation().timeout(
        limit,
        onTimeout: () => throw AppUpgradeP2PFailure(
          limit < timeouts.rtcOperation
              ? (!peer.inbound && peer.id != 'server'
                    ? 'peer_connect_timeout'
                    : 'p2p_budget_exhausted')
              : 'rtc_operation_timeout',
        ),
      );
    } catch (_) {
      // Closing native WebRTC can reject an outstanding call. Preserve the
      // established timeout/ownership reason instead of calling it protocol_error.
      _checkPeer(peer);
      rethrow;
    }
    _checkPeer(peer);
    return value;
  }

  Future<String> _gatherLocalSdp(_P2PPeer peer) async {
    final watch = peer.gatherWatch ??= Stopwatch()..start();
    try {
      return await (() async {
        while (true) {
          _checkPeer(peer);
          // Callback is registered before setLocalDescription; query also
          // handles completion before awaiting or a lost native event.
          final state = peer.iceComplete.isCompleted
              ? RTCIceGatheringState.RTCIceGatheringStateComplete
              : await Future.any<RTCIceGatheringState?>([
                  _rtc(peer, () => peer.pc!.getIceGatheringState()).catchError((
                    Object error,
                  ) {
                    // A stalled status query must not shorten the gathering
                    // deadline. The native completion event may still arrive;
                    // keep waiting for it until the dedicated ICE deadline.
                    if (error is AppUpgradeP2PFailure &&
                        error.code == 'rtc_operation_timeout') {
                      _emit(
                        'ice_gather',
                        'rtc_operation_timeout',
                        source: _source(peer),
                      );
                      return null;
                    }
                    throw error;
                  }),
                  peer.iceComplete.future.then(
                    (_) => RTCIceGatheringState.RTCIceGatheringStateComplete,
                  ),
                ]);
          if (peer.iceComplete.isCompleted ||
              state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
            // createOffer's SDP has no gathered candidates. Always reread the
            // native local description after completion; never send that copy.
            final local = await _rtc(
              peer,
              () => peer.pc!.getLocalDescription(),
            );
            final sdp = local?.sdp ?? '';
            if (sdp.isEmpty) {
              throw const AppUpgradeP2PFailure('local_sdp_invalid');
            }
            _emit(
              'ice_gather',
              'ice_complete',
              source: _source(peer),
              durationMs: watch.elapsedMilliseconds,
            );
            return sdp;
          }
          await Future.any<void>([
            peer.iceComplete.future,
            Future<void>.delayed(const Duration(milliseconds: 200)),
          ]);
        }
      })().timeout(
        timeouts.iceGathering < manifest!.iceGatherTimeout
            ? timeouts.iceGathering
            : manifest!.iceGatherTimeout,
        onTimeout: () => throw const AppUpgradeP2PFailure('ice_gather_timeout'),
      );
    } catch (error) {
      _emit(
        'ice_gather',
        _failureCode(error),
        source: _source(peer),
        durationMs: watch.elapsedMilliseconds,
      );
      _closePeer(peer);
      rethrow;
    }
  }

  // Keep startup phases on the original shared clock, never reset on Answer.
  Duration _channelWaitLimit(_P2PPeer peer) =>
      _hybrid &&
          !peer.inbound &&
          (sharedStartupDeadline || manifest!.sharedDeadline)
      ? _remaining(peer)
      : timeouts.channel;

  Future<void> _waitOpen(_P2PPeer peer) async {
    _checkPeer(peer);
    final channel = peer.channel;
    if (channel == null) throw const AppUpgradeP2PFailure('channel_missing');
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      _peerEvent(peer, 'channel_wait_started');
      // Capture which clock limits this wait. A stream timeout and the outer
      // connect/task timers can race on the same deadline; callback order must
      // not turn a depleted shared budget into a shorter source timeout.
      final sharedSeedDeadline =
          peer.id == 'server' &&
          _hybrid &&
          !peer.inbound &&
          (sharedStartupDeadline || manifest!.sharedDeadline);
      final attemptLimited =
          peer.startupLimit != null &&
          peer.startupLimit! - peer.connectWatch.elapsed <
              _connectBudget - (_connectWatch?.elapsed ?? Duration.zero);
      final timeoutCode = peer.id != 'server'
          ? 'peer_connect_timeout'
          : !sharedSeedDeadline
          ? 'server_seed_connect_timeout'
          : attemptLimited
          ? 'seed_connect_retry_timeout'
          : 'p2p_budget_exhausted';
      final states = channel.stateChangeStream.firstWhere(
        (state) =>
            state == RTCDataChannelState.RTCDataChannelOpen ||
            state == RTCDataChannelState.RTCDataChannelClosed,
      );
      final expired = Completer<RTCDataChannelState>();
      final watch = Stopwatch()..start();
      var softLimit = _channelWaitLimit(peer);
      final allowCandidateGrace =
          _p8p && peer.leased && peer.trickle && peer.id != 'server';
      final hardLimit = allowCandidateGrace ? _remaining(peer) : softLimit;
      Timer? timer;
      void arm(Duration left) {
        timer?.cancel();
        timer = Timer(left, () {
          if (!expired.isCompleted) {
            expired.completeError(AppUpgradeP2PFailure(timeoutCode));
          }
        });
      }

      arm(softLimit);
      var graceUsed = false;
      if (allowCandidateGrace) {
        // Only a newly applied candidate can renew the shorter channel wait,
        // once. The original startup clock and outer connect timeout still win.
        peer.remoteIceProgress = () {
          if (graceUsed ||
              expired.isCompleted ||
              !_active ||
              peer.closed ||
              channel.state == RTCDataChannelState.RTCDataChannelOpen) {
            return;
          }
          final elapsed = watch.elapsed;
          final next = _shorter(
            elapsed + const Duration(seconds: 1),
            hardLimit,
          );
          if (next <= softLimit || next <= elapsed) return;
          graceUsed = true;
          softLimit = next;
          arm(next - elapsed);
          _emit(
            'attempt',
            'ice_candidate_grace',
            source: _source(peer),
            attempt: peer.attempt?['alias'] as String?,
          );
        };
      }
      try {
        await Future.any([states, expired.future]);
      } finally {
        timer?.cancel();
        peer.remoteIceProgress = null;
      }
    }
    _checkPeer(peer);
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw const AppUpgradeP2PFailure('channel_closed');
    }
    _attemptStage(peer, 'channel_ms');
    _dataChannelMs ??= _sessionElapsed();
    _emit('channel', 'channel_open', source: _source(peer));
    peer.deadline?.cancel();
  }

  bool get _hasPendingNegotiation {
    final outboundBudget =
        !_cacheSharing &&
        (_connectWatch?.elapsed ?? _connectBudget) < _connectBudget;
    bool waiting(_P2PPeer peer) =>
        !peer.closed &&
        (peer.inbound || peer.lateDiscovery || outboundBudget) &&
        peer.channel?.state != RTCDataChannelState.RTCDataChannelOpen;
    // Polling starts before discovery creates the first peer. Keep startup
    // polling fast through this gap and until a piece has been verified.
    // Otherwise an empty first response installs a 1.1s idle timer.
    return (outboundBudget && !_firstPiecePersisted) ||
        (_server != null && waiting(_server!)) ||
        _peers.values.any(waiting);
  }

  bool _signalsInFlight = false;

  Future<void> _pollSignals() async {
    if (!_active || _signalsInFlight) return;
    _signalsInFlight = true;
    try {
      final json = await _request(
        'signals',
        '${manifest!.apiBase}/signals${manifest!.trickleIce ? '?include_candidates=1' : ''}'
            '${_sessionServerTrickle ? '&include_server_candidates=1&server_candidate_ack=${_serverCandidates.acknowledged}' : ''}',
      );
      final messages = json['signals'];
      if (messages is! List) {
        throw const AppUpgradeP2PFailure('signals_response_invalid');
      }
      _emptySignalPolls = messages.isEmpty ? _emptySignalPolls + 1 : 0;
      // Handle every drained signal immediately; an incoming offer cannot hold
      // up answers in the same batch. Each peer owns its negotiation state.
      for (final message in messages.whereType<Map>()) {
        unawaited(
          _handleSignal(message).catchError((Object error) {
            _emit('signal', _failureCode(error));
            final id = message['from_peer_id'];
            if (id is String) _closePeer(_peers[id]);
          }),
        );
      }
      if (manifest!.trickleIce && json['candidates'] is List) {
        for (final candidate in (json['candidates'] as List).whereType<Map>()) {
          _queueRemoteCandidate(candidate);
        }
      }
      if (_sessionServerTrickle) {
        final peer = _server;
        final values = _serverCandidates.accept(
          json['server_candidates'],
          currentOffer: peer != null && !peer.closed ? peer.offerId : null,
        );
        if (peer != null && !peer.closed && identical(_server, peer)) {
          if (peer.remoteCandidates.length + values.length > 33) {
            throw const AppUpgradeP2PFailure('server_candidates_invalid');
          }
          peer.remoteCandidates.addAll(values);
          _drainRemoteCandidates(peer);
        }
      }
    } catch (error) {
      if (_active) _emit('signals', _failureCode(error));
      if (error is AppUpgradeP2PFailure &&
          error.code == 'server_candidates_invalid') {
        final peer = _server;
        if (peer != null) {
          peer.failure = error.code;
          _closePeer(peer);
        }
      }
    } finally {
      _signalsInFlight = false;
    }
    if (_active) {
      _signalTimer = Timer(
        Duration(
          milliseconds: manifest!.trickleIce && _hasPendingNegotiation
              ? (fastSignaling ? 100 : manifest!.fastSignalPollMs ?? 250)
              : (900 + _emptySignalPolls * 200).clamp(900, 3000),
        ),
        () => unawaited(_pollSignals()),
      );
    }
  }

  Future<void> _handleSignal(Map signal) async {
    if (!_active) return;
    final id = signal['from_peer_id'], sdp = signal['sdp'];
    if (!_isPeerId(id) || id == _selfId || sdp is! String || sdp.isEmpty) {
      throw const AppUpgradeP2PFailure('signal_invalid');
    }
    final filtered = sdp;
    if (signal['type'] == 'answer') {
      final peer = _peers[id];
      if (peer == null ||
          peer.closed ||
          peer.answerReceived ||
          peer.answer.isCompleted) {
        return;
      }
      peer.answerReceived = true;
      if (_hybrid && !peer.inbound) _armPeerDeadline(peer);
      _attemptStage(peer, 'answer_ms');
      _emit('rtc', 'answer_received', source: 'peer');
      await _rtc(
        peer,
        () => peer.pc!.setRemoteDescription(
          RTCSessionDescription(filtered, 'answer'),
        ),
      );
      peer.remoteIceTypes |= _iceCandidateTypes(filtered);
      _peerEvent(peer, 'remote_description_applied');
      peer.remoteReady = true;
      _drainRemoteCandidates(peer);
      if (!peer.answer.isCompleted) peer.answer.complete();
      return;
    }
    if (signal['type'] != 'offer' || !_mayUpload) return;
    if (!_uploadLedgers.containsKey(id) &&
        _uploadLedgers.length >= _maxUploadReceivers) {
      _emit('sharing', 'peer_capacity');
      if (_cacheSharing) {
        // The existing foreground cache retry creates a fresh authenticated
        // session; never reset cumulative counters under the old credentials.
        finish('local_cache_complete', 'peer_capacity', cacheVerified);
      }
      return;
    }
    if (_peers.containsKey(id) || _peers.length >= 2) {
      _emit('sharing', 'peer_capacity');
      return;
    }
    final slot = uploadBudget?.tryAcquire();
    if (uploadBudget != null && slot == null) {
      _emit('sharing', 'peer_capacity');
      return;
    }
    final peer = await _makePeer(
      id as String,
      inbound: true,
      trickle: signal['trickle_ice'] == true,
      uploadSlot: slot,
    );
    try {
      await _rtc(
        peer,
        () => peer.pc!.setRemoteDescription(
          RTCSessionDescription(filtered, 'offer'),
        ),
      );
      peer.remoteReady = true;
      _drainRemoteCandidates(peer);
      _checkPeer(peer);
      final answer = await _rtc(peer, () => peer.pc!.createAnswer());
      peer.gatherWatch = Stopwatch()..start();
      _emit('ice_gather', 'started', source: _source(peer));
      await _rtc(peer, () => peer.pc!.setLocalDescription(answer));
      final localSdp = await _localSdp(peer);
      _emit('rtc', 'answer_ready', source: _source(peer));
      if (!_mayUpload) {
        throw const AppUpgradeP2PFailure('sharing_network_disallowed');
      }
      await _request(
        'signal',
        '${manifest!.apiBase}/signal',
        body: {
          'peer_id': id,
          'type': 'answer',
          'sdp': localSdp,
          if (peer.trickle) 'trickle_ice': true,
        },
      );
      _startCandidates(peer);
    } catch (_) {
      _closePeer(peer);
      rethrow;
    }
  }

  void _bindChannel(_P2PPeer peer, RTCDataChannel channel) {
    if (peer.inbound &&
        enableP8P &&
        manifest?.p8pTransfer == true &&
        channel.label == P8PTransferProtocol.channel) {
      peer.leased = true;
    }
    if (peer.closed ||
        !_active ||
        peer.channel != null ||
        channel.label !=
            (peer.leased
                ? P8PTransferProtocol.channel
                : AppUpgradeP2PManifest.channelLabel)) {
      unawaited(channel.close().catchError((_) {}));
      _closePeer(peer);
      return;
    }
    peer.channel = channel;
    if (peer.leased && peer.inbound) {
      final ledger = _uploadLedgers.putIfAbsent(
        peer.id,
        () => _P2PUploadLedger(peer.id),
      );
      peer.uploadLedger = ledger;
      peer.sender = P8PTransferSender(
        sha256: manifest!.sha256,
        fileBytes: manifest!.fileSize,
        sourceCapacity: uploadBudget == null ? 2 : 1,
        requireCapacitySupport: uploadBudget != null,
        onCapacityRejected: () =>
            _emit('sharing', 'receiver_capacity_unsupported', once: true),
        readPiece: (index) async {
          await _checkUpload(peer);
          return _store.readVerified(index);
        },
        sendControl: (body) async {
          _checkUploadNow(peer);
          await _control(peer, body);
        },
        sendBinary: (bytes, active) => _sendUploadPayload(
          peer,
          bytes,
          bytes.length - P8PTransferProtocol.headerBytes,
          active: active,
        ),
        allowed: () => _mayUpload && !peer.closed,
        onFailure: () => _closePeer(peer),
        onPayloadQueued: (bytes) => ledger.sentBytes += bytes,
        onPieceCompleted: () {
          _emit('sharing', 'batch_sent', once: true);
          if (_active && !peer.closed) unawaited(_reportUpload(ledger));
        },
      );
    } else if (peer.leased) {
      final writer = _multiWriter;
      if (writer == null) {
        _closePeer(peer);
        return;
      }
      peer.transfer = P8PTransferReceiver(
        source: peer.id,
        writer: writer,
        send: (body) => _control(peer, body),
        onLifecycle: (event) => _emitLifecycle(event, peer: peer),
        onDiagnostic: (event) => _emit(
          'transfer',
          event.reason.code,
          source: _source(peer),
          attempt: peer.attempt?['alias'] as String?,
          actualBytes: event.actualBytes,
          expectedBytes: event.expectedBytes,
        ),
        closeTransport: () async {
          _closePeer(peer);
          await _closeTransport(peer);
        },
      );
    }
    channel.bufferedAmountLowThreshold = uploadBudget == null
        ? 1024 * 1024
        : 128 * 1024;
    channel.onBufferedAmountLow = (_) {
      final waiter = peer.bufferLow;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    };
    channel.onDataChannelState = (state) {
      if (!_active || peer.closed) return;
      _emit('channel', switch (state) {
        RTCDataChannelState.RTCDataChannelConnecting => 'channel_connecting',
        RTCDataChannelState.RTCDataChannelOpen => 'channel_open',
        RTCDataChannelState.RTCDataChannelClosing => 'channel_closing',
        RTCDataChannelState.RTCDataChannelClosed => 'channel_closed',
      }, source: _source(peer));
      if (state == RTCDataChannelState.RTCDataChannelClosed ||
          state == RTCDataChannelState.RTCDataChannelClosing) {
        _closePeer(peer);
      }
    };
    channel.onMessage = (message) {
      if (!_active || peer.closed) return;
      if (message.isBinary) _peerEvent(peer, 'first_payload_received');
      if (peer.sender != null) {
        if (message.isBinary) {
          _closePeer(peer);
        } else {
          peer.sender!.acceptControl(message.text);
        }
        return;
      }
      if (peer.leased) {
        if (message.isBinary) {
          final count = max(
            0,
            message.binary.length - P8PTransferProtocol.headerBytes,
          );
          if (peer.id == 'server') {
            _seedBodyBytes += count;
          } else {
            _peerBodyBytes += count;
          }
          peer.transfer!.acceptBinary(message.binary);
        } else {
          peer.transfer!.acceptControl(message.text);
        }
        return;
      }
      try {
        if (message.isBinary) {
          if (peer.receiver != null ||
              peer.batch != null ||
              peer.window != null) {
            if (identical(peer, _server)) {
              _seedBodyBytes += message.binary.length;
            } else {
              _peerBodyBytes += message.binary.length;
            }
          }
          if (peer.window != null) {
            peer.window!.add(message.binary);
            return;
          }
          if (peer.batch != null) {
            peer.batch!.add(message.binary);
            return;
          }
          if (peer.receiver == null) {
            throw const AppUpgradeP2PFailure('unexpected_binary');
          }
          peer.receiver!.add(message.binary);
          return;
        }
        final decoded = jsonDecode(message.text);
        if (decoded is! Map<String, dynamic>) {
          throw const AppUpgradeP2PFailure('invalid_message');
        }
        final type = decoded['type'];
        // Old senders omit this echo. Signaling capability alone never enables
        // pipelining against an old sender that would reject requests as busy.
        if (type == 'piece-start' && decoded['pipeline_window'] == 4) {
          peer.pipelineSupported = true;
          if (_p8p && P8PWindowProtocol.acknowledged(decoded['p8p'])) {
            peer.p8pSupported = true;
          }
        }
        if (type == 'get-piece' || type == 'get-pieces') {
          if (!_claimUpload(peer)) {
            unawaited(
              _control(peer, {
                'type': 'error',
                'code': 'busy',
              }).catchError((_) {}),
            );
            return;
          }
          final indices = manifest!.requestedIndices(decoded);
          final p8pWindow = P8PWindowProtocol.requested(
            decoded['p8p'],
            enabled: _p8p,
          );
          final pipeline =
              peer.pipelineUpload ||
              p8pWindow != null ||
              (!peer.uploading && decoded['pipeline_window'] == 4);
          if (pipeline) {
            if (peer.uploadOutstanding.length + indices.length >
                    (p8pWindow ?? peer.p8pUploadWindow ?? 4) ||
                indices.any(peer.uploadOutstanding.contains)) {
              unawaited(
                _control(peer, {
                  'type': 'error',
                  'code': 'busy',
                }).catchError((_) {}),
              );
              return;
            }
            peer.pipelineUpload = true;
            if (p8pWindow != null) peer.p8pUploadWindow = p8pWindow;
            peer.uploadOutstanding.addAll(indices);
            peer.uploadQueue.addAll(indices);
            if (!peer.uploading) {
              peer.uploading = true;
              _startUpload(peer);
            }
          } else if (peer.uploading) {
            unawaited(
              _control(peer, {
                'type': 'error',
                'code': 'busy',
              }).catchError((_) {}),
            );
          } else {
            peer.uploading = true;
            _startUpload(peer, indices: indices);
          }
          return;
        }
        if (type == 'error') {
          throw AppUpgradeP2PFailure(_serverCode(decoded['code']));
        }
        if (peer.window != null) {
          if (type == 'piece-start') {
            peer.window!.start(decoded);
          } else if (type == 'piece-end') {
            peer.window!.end(decoded);
          } else {
            throw const AppUpgradeP2PFailure('invalid_message');
          }
          return;
        }
        if (peer.batch != null) {
          if (type == 'piece-start') {
            peer.batch!.start(decoded);
          } else if (type == 'piece-end') {
            peer.batch!.end(decoded);
          } else {
            throw const AppUpgradeP2PFailure('invalid_message');
          }
          return;
        }
        final receiver = peer.receiver;
        if (receiver == null) {
          throw const AppUpgradeP2PFailure('unexpected_control');
        }
        if (type == 'piece-start') {
          receiver.start(decoded);
        } else if (type == 'piece-end') {
          final bytes = receiver.end(decoded);
          if (peer.piece != null && !peer.piece!.isCompleted) {
            peer.piece!.complete(bytes);
          }
        } else {
          throw const AppUpgradeP2PFailure('invalid_message');
        }
      } catch (error) {
        _emit('channel', _failureCode(error));
        _failPiece(
          peer,
          error is AppUpgradeP2PFailure
              ? error
              : const AppUpgradeP2PFailure('invalid_message'),
        );
        _closePeer(peer);
        if (error is AppUpgradeP2PFailure &&
            (error.code == 'p2p_disabled' || error.code == 'release_changed')) {
          finish(
            _cacheSharing ? 'local_cache_complete' : 'https_fallback',
            error.code,
            cacheVerified,
          );
        }
      }
    };
  }

  Future<Uint8List> _receivePiece(_P2PPeer peer, int index) async {
    _checkPeer(peer);
    if (peer.piece != null || peer.batch != null) {
      throw const AppUpgradeP2PFailure('busy');
    }
    final pending = Completer<Uint8List>();
    peer.piece = pending;
    peer.receiver = AppUpgradeP2PPieceReceiver(_store, index);
    final watch = Stopwatch()..start();
    final startupRemaining = !_firstPiecePersisted && !_cacheSharing
        ? _remaining(peer)
        : null;
    final startupLimited =
        startupRemaining != null && startupRemaining <= timeouts.transfer;
    final received = pending.future.timeout(
      startupRemaining == null
          ? timeouts.transfer
          : _shorter(timeouts.transfer, startupRemaining),
      onTimeout: () => throw AppUpgradeP2PFailure(
        startupLimited
            ? 'p2p_budget_exhausted'
            : peer.id == 'server'
            ? 'server_seed_transfer_timeout'
            : 'peer_transfer_timeout',
      ),
    );
    unawaited(received.then<void>((_) {}, onError: (Object _) {}));
    try {
      await _control(peer, {
        'type': 'get-piece',
        'index': index,
        'pipeline_window': 4,
        if (_p8p) 'p8p': P8PWindowProtocol.request(4),
      });
      final bytes = await received;
      _checkPeer(peer);
      _emit(
        'transfer',
        'piece_verified',
        source: _source(peer),
        durationMs: watch.elapsedMilliseconds,
        once: true,
      );
      return bytes;
    } finally {
      peer.piece = null;
      peer.receiver = null;
    }
  }

  void _startUpload(_P2PPeer peer, {List<int>? indices}) {
    // Publish ownership before invoking code that can start a file read or
    // synchronously retire this peer. Native transport close alone does not
    // settle the file operation which produced its next payload.
    final settled = Completer<void>();
    peer.uploadWork = settled.future;
    unawaited(() async {
      try {
        if (indices == null) {
          await _serveQueue(peer);
        } else {
          await _serveBatch(peer, indices);
        }
      } finally {
        settled.complete();
        if (identical(peer.uploadWork, settled.future)) peer.uploadWork = null;
      }
    }());
  }

  Future<void> _serveQueue(_P2PPeer peer) async {
    try {
      while (!peer.closed && peer.uploadQueue.isNotEmpty) {
        final index = peer.uploadQueue.removeAt(0);
        await _serveBatch(peer, [index]);
        peer.uploadOutstanding.remove(index);
      }
    } finally {
      peer.uploading = false;
    }
  }

  Future<void> _serveBatch(_P2PPeer peer, List<int> indices) async {
    try {
      var ledger = _uploadLedgers[peer.id];
      if (ledger == null) {
        if (_uploadLedgers.length >= _maxUploadReceivers) {
          throw const AppUpgradeP2PFailure('peer_capacity');
        }
        ledger = _P2PUploadLedger(peer.id);
        _uploadLedgers[peer.id] = ledger;
      }
      peer.uploadLedger = ledger;
      for (final index in indices) {
        await _checkUpload(peer);
        final bytes = await _store.readVerified(index);
        await _checkUpload(peer);
        await _control(peer, {
          'type': 'piece-start',
          'index': index,
          'size': bytes.length,
          if (peer.pipelineUpload) 'pipeline_window': 4,
          if (peer.p8pUploadWindow != null)
            'p8p': P8PWindowProtocol.echo(peer.p8pUploadWindow!),
        });
        for (
          var offset = 0;
          offset < bytes.length;
          offset += AppUpgradeP2PManifest.maxFrameBytes
        ) {
          final end = (offset + AppUpgradeP2PManifest.maxFrameBytes).clamp(
            0,
            bytes.length,
          );
          await _sendUploadPayload(
            peer,
            Uint8List.sublistView(bytes, offset, end),
            end - offset,
          );
          // Successfully queued payload only; exclude control frames and
          // failed/unknown sends. This is not receiver verification.
          ledger.sentBytes += end - offset;
        }
        peer.uploadOutstanding.remove(index);
        await _control(peer, {'type': 'piece-end', 'index': index});
      }
      _emit('sharing', 'batch_sent', once: true);
      if (_active && !peer.closed) unawaited(_reportUpload(ledger));
    } catch (error) {
      final code = _failureCode(error);
      _emit('sharing', code);
      try {
        await _control(peer, {'type': 'error', 'code': code});
      } catch (_) {}
      _closePeer(peer);
    } finally {
      if (!peer.pipelineUpload) peer.uploading = false;
    }
  }

  bool _claimUpload(_P2PPeer peer) {
    if (uploadBudget == null) return true;
    peer.uploadSlot ??= uploadBudget!.tryAcquire();
    return peer.uploadSlot?.active == true;
  }

  Future<void> _sendUploadPayload(
    _P2PPeer peer,
    Uint8List bytes,
    int payloadBytes, {
    bool Function()? active,
  }) async {
    await _checkUpload(peer);
    if (!_claimUpload(peer)) throw const AppUpgradeP2PFailure('busy');
    await _waitUploadCapacity(peer);
    await peer.uploadSlot?.take(
      payloadBytes,
      () => _mayUpload && !peer.closed && (active?.call() ?? true),
    );
    // A platform network event may be delayed while pacing yields. Query the
    // actual route again after that wait before allowing a phone payload.
    if (peer.uploadSlot != null) await _checkUpload(peer);
    _checkUploadNow(peer);
    if (active != null && !active()) throw StateError('upload_cancelled');
    // No await from the final owner/policy check to native enqueue.
    final settled = Completer<void>();
    peer.uploadSend = settled.future;
    try {
      await peer.channel!
          .send(RTCDataChannelMessage.fromBinary(bytes))
          .timeout(
            timeouts.rtcOperation,
            onTimeout: () {
              _emit('sharing', 'upload_send_timeout');
              throw const AppUpgradeP2PFailure('upload_timeout');
            },
          );
    } finally {
      settled.complete();
      peer.uploadSend = null;
    }
  }

  Future<void> _waitUploadCapacity(_P2PPeer peer) async {
    // The plugin's getter is an event cache. A lagging cache can either queue
    // megabytes above the limit or time out after the native queue has drained.
    // Query the native queue serially, within the original fixed drain budget.
    final watch = Stopwatch()..start();
    const budget = Duration(seconds: 3);
    while (true) {
      _checkPeer(peer);
      final channel = peer.channel;
      if (channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
        throw const AppUpgradeP2PFailure('channel_closed');
      }
      final remaining = budget - watch.elapsed;
      if (remaining <= Duration.zero) {
        _emit('sharing', 'upload_queue_timeout');
        throw const AppUpgradeP2PFailure('upload_timeout');
      }
      late final int amount;
      try {
        amount = await channel!.getBufferedAmount().timeout(
          _shorter(timeouts.rtcOperation, remaining),
          onTimeout: () {
            _emit('sharing', 'upload_buffer_query_timeout');
            throw const AppUpgradeP2PFailure('upload_timeout');
          },
        );
      } on AppUpgradeP2PFailure {
        rethrow;
      } catch (_) {
        throw const AppUpgradeP2PFailure('upload_buffer_unavailable');
      }
      // A late read-only result must never authorize work after revocation,
      // network change or physical channel closure.
      await _checkUpload(peer);
      if (watch.elapsed >= budget) {
        _emit('sharing', 'upload_queue_timeout');
        throw const AppUpgradeP2PFailure('upload_timeout');
      }
      if (amount < 0) {
        throw const AppUpgradeP2PFailure('upload_buffer_unavailable');
      }
      // Keep one bounded delay-bandwidth product in flight. Refilling at an
      // empty queue used to leave high-latency links idle between frames.
      if (amount + AppUpgradeP2PManifest.maxFrameBytes <=
          (uploadBudget == null ? 2 * 1024 * 1024 : 256 * 1024)) {
        return;
      }
      final drained = Completer<void>();
      peer.bufferLow = drained;
      try {
        // Low-water callbacks can wake early. Query again even if no event
        // arrives; an event-cached value is never sufficient to admit a frame.
        final pause = _shorter(
          const Duration(milliseconds: 50),
          budget - watch.elapsed,
        );
        if (pause > Duration.zero) {
          await drained.future.timeout(pause, onTimeout: () {});
        }
      } finally {
        if (identical(peer.bufferLow, drained)) peer.bufferLow = null;
      }
    }
  }

  Future<void> _reportUpload(
    _P2PUploadLedger ledger, {
    bool finalReport = false,
  }) async {
    while (ledger.reporting != null) {
      if (!finalReport) return;
      await ledger.reporting;
    }
    if (ledger.unavailable ||
        ledger.sentBytes <= ledger.reportedBytes ||
        _token.isEmpty ||
        (!finalReport &&
            ledger.lastReport != null &&
            _elapsed.elapsed - ledger.lastReport! <
                const Duration(seconds: 5))) {
      return;
    }
    ledger.lastReport = _elapsed.elapsed;
    final body = Map<String, Object?>.unmodifiable({
      'peer_id': ledger.peerId,
      'uploaded_bytes': ledger.sentBytes,
    });
    late final Future<void> reporting;
    reporting = () async {
      for (var attempt = 0; attempt < (finalReport ? 2 : 1); attempt++) {
        final cancel = CancelToken();
        try {
          await _request(
            'peer_upload_report',
            '${manifest!.apiBase}/peer-upload-report',
            cleanup: true,
            cleanupCancel: cancel,
            body: body,
          ).timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              cancel.cancel('upload_report_timeout');
              throw const AppUpgradeP2PFailure('http_timeout');
            },
          );
          ledger.reportedBytes = body['uploaded_bytes'] as int;
          return;
        } on AppUpgradeP2PFailure catch (error) {
          if (!_retryableReport(error.code)) {
            // Old servers may omit this optional endpoint. No upload or
            // download is failed, and later batches do not hammer that route.
            ledger.unavailable = true;
            return;
          }
        } catch (_) {
          return;
        }
      }
    }().whenComplete(() => ledger.reporting = null);
    ledger.reporting = reporting;
    await reporting;
  }

  void _retireUpload(_P2PPeer peer) {
    final ledger = peer.uploadLedger;
    final work = peer.uploadWork;
    final sender = peer.sender;
    final slot = peer.uploadSlot;
    if (ledger == null && work == null && sender == null && slot == null) {
      return;
    }
    slot?.cancel();
    final senderClosing = sender?.close();
    final send = peer.uploadSend;
    late final Future<void> retiring;
    retiring = () async {
      // Revocation already closed admission and native transport. Keep the
      // bearer/HTTP owner until the same in-flight file read and send finish;
      // their post-read policy check prevents any payload after retirement.
      await work;
      await send;
      await senderClosing;
      // A timed-out creation can still return a native connection later.
      // Keep the single receiver slot until that same connection is disposed.
      RTCPeerConnection? pc;
      try {
        pc = await peer.creation;
      } catch (_) {}
      if (pc != null) await _releaseNativePeer(pc);
      await _closeTransport(peer);
      if (pc == null || _releasedNativePeers[pc] == true) slot?.release();
      if (ledger != null) await _reportUpload(ledger, finalReport: true);
    }().whenComplete(() => _uploadRetirements.remove(retiring));
    _uploadRetirements.add(retiring);
    unawaited(retiring);
  }

  Future<void> _checkUpload(_P2PPeer peer) async {
    _checkPeer(peer);
    final network = await networkReader();
    if (network != _network) _networkChanged(network);
    _checkUploadNow(peer);
  }

  void _checkUploadNow(_P2PPeer peer) {
    _checkPeer(peer);
    if (!_mayUpload) {
      throw const AppUpgradeP2PFailure('sharing_network_disallowed');
    }
  }

  void _networkChanged(AppUpgradeP2PNetwork network) {
    if (!_active || network == _network) return;
    _network = network;
    _shareGranted = false;
    if (!network.mayShare) {
      for (final peer in _peers.values.toList()) {
        if (peer.inbound || peer.uploading || peer.uploadSlot != null) {
          _closePeer(peer);
        }
      }
    }
    _emit(
      'network',
      network.mayShare ? 'sharing_wifi_available' : 'sharing_disabled',
    );
    if (_token.isNotEmpty) {
      if (network.mayShare) {
        unawaited(_heartbeat());
      } else {
        // A withdrawal is independent of the receive transport. Finishing the
        // download must not cancel it before the server sees empty pieces.
        _withdrawal = _request(
          'heartbeat',
          '${manifest!.apiBase}/heartbeat',
          cleanup: true,
          body: _sharingHeartbeat(network, const <int>[]),
        ).then<void>((_) {}, onError: (Object _) {});
      }
    }
    if (_cacheSharing && !network.mayShare) {
      finish('local_cache_complete', 'sharing_network_disallowed', true);
    }
  }

  void _scheduleHeartbeat() {
    if (!_active || _heartbeatSoon != null) return;
    _heartbeatSoon = Timer(const Duration(seconds: 2), () {
      _heartbeatSoon = null;
      unawaited(_heartbeat());
    });
  }

  void setSharingEnabled(bool enabled) {
    allowSharing = enabled;
    _shareGranted = false;
    if (!enabled) {
      for (final peer in _peers.values.toList()) {
        if (peer.inbound || peer.uploading || peer.uploadSlot != null) {
          _closePeer(peer);
        }
      }
    }
    if (_active && _token.isNotEmpty && _storeReady) unawaited(_heartbeat());
  }

  Future<void> _heartbeat() async {
    if (!_active || _token.isEmpty || _heartbeatBusy) return;
    _heartbeatBusy = true;
    final network = await networkReader();
    if (network != _network) _networkChanged(network);
    final sentNetwork = _network;
    final sentSharing = allowSharing;
    try {
      final response = await _request(
        'heartbeat',
        '${manifest!.apiBase}/heartbeat',
        body: _sharingHeartbeat(sentNetwork, _store.verifiedPieces),
      );
      if (_active && sentNetwork == _network) {
        _shareGranted =
            allowSharing &&
            sentSharing &&
            sentNetwork.mayShare &&
            response['share_enabled'] != false;
        if (!_shareGranted) {
          for (final peer in _peers.values.toList()) {
            if (peer.inbound || peer.uploading || peer.uploadSlot != null) {
              _closePeer(peer);
            }
          }
        }
      }
    } catch (error) {
      _shareGranted = false;
      for (final peer in _peers.values.toList()) {
        if (peer.inbound || peer.uploading || peer.uploadSlot != null) {
          _closePeer(peer);
        }
      }
      _emit('heartbeat', _failureCode(error));
    } finally {
      _heartbeatBusy = false;
      if (_active && (sentNetwork != _network || sentSharing != allowSharing)) {
        unawaited(_heartbeat());
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    String stage,
    String url, {
    Map<String, Object?>? body,
    bool auth = true,
    bool cleanup = false,
    CancelToken? cleanupCancel,
    _P2PPeer? owner,
    CancelToken? operationCancel,
  }) {
    if (cleanup) {
      final cancel = cleanupCancel ?? CancelToken();
      return _performRequest(
        stage,
        url,
        body: body,
        auth: auth,
        cleanup: true,
        cleanupCancel: cancel,
        owner: owner,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          cancel.cancel('cleanup_timeout');
          throw const AppUpgradeP2PFailure('http_timeout');
        },
      );
    }
    return _performRequest(
      stage,
      url,
      body: body,
      auth: auth,
      owner: owner,
      operationCancel: operationCancel,
    );
  }

  Future<Map<String, dynamic>> _performRequest(
    String stage,
    String url, {
    Map<String, Object?>? body,
    bool auth = true,
    bool cleanup = false,
    CancelToken? cleanupCancel,
    _P2PPeer? owner,
    CancelToken? operationCancel,
  }) async {
    final watch = Stopwatch()..start();
    var timingRecorded = false;
    try {
      if (!cleanup) _checkActive();
      if (stage == 'server_offer') _serverOfferAttempted = true;
      _emit(
        stage,
        'request_started',
        once: stage == 'signals' || stage == 'heartbeat',
      );
      var requestTimedOut = false;
      final request = dio.request<dynamic>(
        url,
        data: body,
        cancelToken: cleanup
            ? cleanupCancel
            : owner?.signalingCancel ?? operationCancel ?? _httpCancel,
        options: Options(
          method: body == null ? 'GET' : 'POST',
          responseType: ResponseType.json,
          contentType: Headers.jsonContentType,
          followRedirects: false,
          validateStatus: (_) => true,
          receiveTimeout: cleanup
              ? const Duration(seconds: 2)
              : stage == 'server_offer'
              ? const Duration(seconds: 15)
              : const Duration(seconds: 5),
          sendTimeout: cleanup
              ? const Duration(seconds: 2)
              : const Duration(seconds: 5),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'LifeRing-Android/P2P-v1 Dart',
            'X-Client-App-Version':
                await AppUpgradeP2PDiagnostics.clientVersion(),
            if (auth && _token.isNotEmpty) 'Authorization': 'Bearer $_token',
            if (stage == 'session') ...{
              'X-Device-Id': _deviceId,
              'Idempotency-Key': _sessionRequest!.key,
            },
          },
        ),
      );
      // Native cancellation is best effort. Bound the Future too, including
      // session creation and peer discovery before a PeerConnection exists.
      final remaining =
          !cleanup &&
              !_cacheSharing &&
              !_firstPiecePersisted &&
              _connectWatch != null
          ? _connectBudget - _connectWatch!.elapsed
          : null;
      if (stage == 'session' && !cleanup) {
        unawaited(
          request.then<void>((lateResponse) {
            if (!requestTimedOut || !_ended || _token.isNotEmpty) return;
            final lateData = lateResponse.data;
            if (lateData is! Map ||
                lateData['token'] is! String ||
                !_isPeerId(lateData['session_id'])) {
              return;
            }
            _token = lateData['token'] as String;
            _selfId = lateData['session_id'] as String;
            // Late credentials belong only to this closed task.
            unawaited(_reportAndLeave('https_fallback', _reason, false));
          }, onError: (Object _) {}),
        );
      }
      final peerRequest = owner == null
          ? request
          : Future.any([
              request,
              owner.signalingCancel.whenCancel.then<Response<dynamic>>((_) {
                // A deadline or ICE failure may close this owner before
                // the task timer or an uncancellable HTTP reply arrives.
                // Preserve its established reason whichever future wins.
                _checkPeer(owner);
                throw const AppUpgradeP2PFailure('channel_closed');
              }),
            ]);
      final ownedRequest = operationCancel == null
          ? peerRequest
          : Future.any([
              peerRequest,
              operationCancel.whenCancel.then<Response<dynamic>>(
                (_) => throw const AppUpgradeP2PFailure('request_cancelled'),
              ),
            ]);
      final response = remaining == null
          ? await ownedRequest
          : await ownedRequest.timeout(
              remaining > Duration.zero ? remaining : Duration.zero,
              onTimeout: () {
                requestTimedOut = true;
                finish('https_fallback', 'p2p_budget_exhausted', false);
                throw const AppUpgradeP2PFailure('p2p_budget_exhausted');
              },
            );
      if (owner != null) _checkPeer(owner);
      final status = response.statusCode ?? 0;
      if (!_ended && _timedEndpoints.contains(stage)) {
        _apiRoundtripMs[stage] =
            ((_apiRoundtripMs[stage] ?? 0) + watch.elapsedMilliseconds).clamp(
              0,
              120000,
            );
        timingRecorded = true;
      }
      final serverMs = int.tryParse(
        response.headers.value('x-p2p-server-time-ms') ?? '',
      );
      if (!_ended &&
          _timedEndpoints.contains(stage) &&
          serverMs != null &&
          serverMs >= 0 &&
          serverMs <= 120000) {
        _apiServerMs[stage] = ((_apiServerMs[stage] ?? 0) + serverMs).clamp(
          0,
          120000,
        );
      }
      final data = response.data;
      if (status < 200 || status >= 300 || data is! Map) {
        final code = status == 401
            ? 'session_unauthorized'
            : data is Map
            ? _serverCode(data['error'] ?? data['code'])
            : 'http_error';
        _emit(
          stage,
          code,
          status: status,
          durationMs: watch.elapsedMilliseconds,
        );
        if (!cleanup && (status == 401 || code == 'p2p_disabled')) {
          finish(
            _cacheSharing ? 'local_cache_complete' : 'https_fallback',
            code,
            cacheVerified,
          );
        }
        throw AppUpgradeP2PFailure(code);
      }
      _emit(
        stage,
        'http_ok',
        status: status,
        durationMs: watch.elapsedMilliseconds,
        once: stage == 'signals' || stage == 'heartbeat',
      );
      return data.map((key, value) => MapEntry(key.toString(), value));
    } on AppUpgradeP2PFailure {
      rethrow;
    } catch (error) {
      // Native HTTP cancellation can win before the explicit owner future.
      if (owner != null && owner.closed) {
        _checkPeer(owner);
      }
      final code = _failureCode(error);
      _emit(stage, code, durationMs: watch.elapsedMilliseconds);
      throw AppUpgradeP2PFailure(code);
    } finally {
      if (!timingRecorded && !_ended && _timedEndpoints.contains(stage)) {
        _apiRoundtripMs[stage] =
            ((_apiRoundtripMs[stage] ?? 0) + watch.elapsedMilliseconds).clamp(
              0,
              120000,
            );
      }
    }
  }

  void interrupt() {
    _interrupted = true;
    finish('client_interrupted', 'client_interrupted', false);
  }

  /// Transport closes immediately. Bounded outcome/leave I/O is best effort and
  /// independent of HTTPS, integrity verification and Android installation.
  void finish(String outcome, String reason, bool verified) {
    if (_ended) return;
    _ended = true;
    _active = false;
    _shareGranted = false;
    _reason = reason;
    _httpCancel.cancel('session_stopped');
    _signalTimer?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatSoon?.cancel();
    _sharingTimer?.cancel();
    _startupTimer?.cancel();
    _earlyCandidates.clear();
    if (_multiCoordinator != null) {
      unawaited(_multiCoordinator!.close().catchError((Object _) {}));
    }
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    for (final peer in _peers.values.toList()) {
      _closePeer(peer, reason: reason);
    }
    _closePeer(_server, reason: reason);
    _emit('result', outcome, verified: verified);
    _emit('result_reason', reason);
    if (_token.isNotEmpty && manifest != null) {
      cleanup = _reportAndLeave(outcome, reason, verified);
      unawaited(cleanup);
    }
  }

  Future<void> _reportAndLeave(
    String outcome,
    String reason,
    bool verified,
  ) async {
    // Freeze before any await: late transport callbacks and future HTTPS
    // verification cannot change the first accepted P2P outcome or byte count.
    var body = Map<String, Object?>.unmodifiable({
      'outcome': outcome,
      'peer_bytes': _peerBytes,
      'verified': verified,
      'reason_code': AppUpgradeP2PDiagnostic.safeCode(reason),
      'diagnostics': {
        if (_supportsBootstrapTelemetry && _bootstrapReceivedBytes != null) ...{
          'https_bootstrap_received_bytes': _bootstrapReceivedBytes!().clamp(
            0,
            1 << 40,
          ),
          'https_bootstrap_used_bytes': _httpsBootstrapBytes.clamp(0, 1 << 40),
        },
        // Match the server's single P2P budget clock, which starts immediately
        // before the idempotent session request rather than at manifest fetch.
        'elapsed_ms':
            (_connectWatch?.elapsedMilliseconds ?? _elapsed.elapsedMilliseconds)
                .clamp(0, 120000),
        'ice_gather_ms': _iceGatherMs.clamp(0, 120000),
        if (_iceConnectMs != null) 'ice_connect_ms': _iceConnectMs,
        if (_dataChannelMs != null) 'data_channel_ms': _dataChannelMs,
        if (_firstPieceMs != null) 'first_piece_ms': _firstPieceMs,
        'ice_gather_state': _iceGatherState,
        'peer_count': _candidates.length.clamp(0, 16),
        if (manifest!.attemptDiagnostics)
          'attempts': _attempts.map((a) => Map<String, Object?>.of(a)).toList(),
        'server_offer_attempted': _serverOfferAttempted,
        'host_candidates': _iceCounts['host'],
        'srflx_candidates': _iceCounts['srflx'],
        'relay_candidates': _iceCounts['relay'],
        // flutter_webrtc in the supported branch has no native
        // onIceCandidateError callback. Keep this as 0 (unobserved); never
        // count candidate signaling HTTP failures as ICE server errors.
        'candidate_error_count': 0,
        'api_roundtrip_ms': Map<String, int>.unmodifiable(_apiRoundtripMs),
        'api_server_ms': Map<String, int>.unmodifiable(_apiServerMs),
      },
    });
    await _withdrawal;
    // Closing/revoking transports above is synchronous. Keep their optional
    // reports and in-flight send owners alive before retiring the bearer.
    await Future.wait(_uploadRetirements.toList());
    await Future.wait(_transportRetirements.toList());
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _request(
          'outcome',
          '${manifest!.apiBase}/outcome',
          cleanup: true,
          body: body,
        );
        break;
      } on AppUpgradeP2PFailure catch (error) {
        if (attempt == 0 && error.code == 'invalid_p2p_diagnostics') {
          // A rejected optional diagnostic is not an accepted outcome; retry
          // once with the same terminal result, leaving old services compatible.
          body = Map<String, Object?>.unmodifiable(
            Map<String, Object?>.of(body)..remove('diagnostics'),
          );
          continue;
        }
        if (attempt != 0 || !_retryableReport(error.code)) break;
        _emit('outcome', 'retry');
      } catch (_) {
        break;
      }
    }
    try {
      await _request(
        'leave',
        '${manifest!.apiBase}/leave',
        cleanup: true,
        // Outcome is already reported above. Leave only releases the session;
        // terminal success values are not accepted by the leave endpoint.
        body: const {},
      );
      final request = _sessionRequest;
      if (request != null) await AppUpgradeP2PIdentity.release(request);
    } catch (_) {}
    _token = '';
  }

  Future<void> _control(_P2PPeer peer, Map<String, Object?> body) async {
    _checkPeer(peer);
    if (peer.channel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw const AppUpgradeP2PFailure('channel_closed');
    }
    await peer.channel!
        .send(RTCDataChannelMessage(jsonEncode(body)))
        .timeout(
          timeouts.rtcOperation,
          onTimeout: () =>
              throw const AppUpgradeP2PFailure('rtc_operation_timeout'),
        );
  }

  Future<void> _sampleIceChecks(_P2PPeer peer) async {
    peer.iceStatsTimer = null;
    final pc = peer.pc;
    if (!_active ||
        peer.closed ||
        pc == null ||
        peer.iceState != RTCIceConnectionState.RTCIceConnectionStateChecking) {
      return;
    }
    // Sample at most twice during checking. Never join this optional platform
    // call from a transfer, cancellation or native transport retirement.
    peer.iceStatsAttempts++;
    try {
      final reports = await pc.getStats().timeout(
        const Duration(milliseconds: 150),
      );
      if (!_active || peer.closed || !identical(pc, peer.pc)) return;
      peer.iceStats = _iceCheckMetrics(reports);
      peer.iceStatsAt = peer.connectWatch.elapsedMilliseconds;
    } catch (_) {
      // Optional platform statistics cannot delay negotiation or disposal.
    } finally {
      if (_active &&
          !peer.closed &&
          peer.iceStatsAttempts < 2 &&
          peer.iceState ==
              RTCIceConnectionState.RTCIceConnectionStateChecking) {
        peer.iceStatsTimer = Timer(
          const Duration(milliseconds: 1500),
          () => unawaited(_sampleIceChecks(peer)),
        );
      }
    }
  }

  static Map<String, int> _iceCheckMetrics(List<StatsReport> reports) {
    final pairs = reports
        .where((report) => report.type == 'candidate-pair')
        .take(65)
        .toList();
    final retained = pairs.take(64).toList();
    final result = <String, int>{
      'ice_stats_sampled': 1,
      'ice_pair_count': retained.length,
      'ice_pairs_truncated': pairs.length > 64 ? 1 : 0,
      'ice_pairs_succeeded': retained
          .where((pair) => pair.values['state'] == 'succeeded')
          .length,
    };
    for (final field in const {
      'requestsSent': 'ice_requests_sent',
      'requestsReceived': 'ice_requests_received',
      'responsesSent': 'ice_responses_sent',
      'responsesReceived': 'ice_responses_received',
    }.entries) {
      var total = 0;
      var complete = retained.isNotEmpty && pairs.length <= 64;
      for (final pair in retained) {
        final raw = pair.values[field.key];
        final value = raw is num
            ? raw
            : raw is String && RegExp(r'^[0-9]{1,15}$').hasMatch(raw)
            ? int.tryParse(raw)
            : null;
        if (value == null ||
            !value.isFinite ||
            value < 0 ||
            value != value.truncateToDouble()) {
          complete = false;
          break;
        }
        total = (total + value.toInt()).clamp(0, 1000000);
      }
      // Missing fields mean unknown, including on older platform adapters.
      // A partial or truncated sum must never look like a proven zero.
      if (complete) result[field.value] = total;
    }
    return result;
  }

  void _closePeer(_P2PPeer? peer, {String? reason}) {
    if (peer == null || peer.closed) return;
    peer.iceStatsTimer?.cancel();
    peer.remoteIceProgress = null;
    if (peer.attempt != null) {
      peer.attempt!['ended_ms'] = _sessionElapsed() ?? 0;
      peer.attempt!['reason'] = AppUpgradeP2PDiagnostic.safeCode(
        reason ?? peer.failure,
      );
      final failure = reason ?? peer.failure;
      _emit(
        'attempt',
        failure,
        source: _source(peer),
        attempt: peer.attempt!['alias'] as String,
      );
      if (!peer.attempt!.containsKey('first_piece_ms') &&
          const {
            'peer_connect_timeout',
            'p2p_budget_exhausted',
            'ice_failed',
            'channel_wait_timeout',
            'source_timeout',
            'network_error',
            'http_timeout',
            'rtc_operation_timeout',
          }.contains(failure)) {
        if (peer.id != 'server' && peer.leased) {
          candidateHistory.record(manifest!.apiBase, peer.id);
        }
        _emit(
          'attempt',
          'peer_failure_detail',
          source: _source(peer),
          attempt: peer.attempt!['alias'] as String,
          durationMs: peer.connectWatch.elapsedMilliseconds,
          metrics: {
            'ice_stats_sampled': 0,
            ...peer.iceStats,
            if (peer.iceStatsAt != null)
              'ice_stats_age_ms':
                  (peer.connectWatch.elapsedMilliseconds - peer.iceStatsAt!)
                      .clamp(0, 120000),
            'attempt_native_ready': peer.pc == null ? 0 : 1,
            'attempt_offer_accepted':
                peer.diagnosticStages.contains('offer_accepted') ? 1 : 0,
            'attempt_answer_seen': peer.attempt!.containsKey('answer_ms')
                ? 1
                : 0,
            'attempt_remote_sdp_applied': peer.remoteReady ? 1 : 0,
            'attempt_local_trickle_posted': peer.firstLocalCandidatePosted
                ? 1
                : 0,
            'attempt_remote_trickle_applied': peer.remoteTrickleApplied,
            'attempt_local_candidate_types': peer.localIceTypes,
            'attempt_remote_candidate_types': peer.remoteIceTypes,
            'attempt_ice_state': switch (peer.iceState) {
              RTCIceConnectionState.RTCIceConnectionStateChecking => 1,
              RTCIceConnectionState.RTCIceConnectionStateConnected ||
              RTCIceConnectionState.RTCIceConnectionStateCompleted => 2,
              RTCIceConnectionState.RTCIceConnectionStateDisconnected => 3,
              RTCIceConnectionState.RTCIceConnectionStateFailed => 4,
              RTCIceConnectionState.RTCIceConnectionStateClosed => 5,
              _ => 0,
            },
            'attempt_channel_opened': peer.attempt!.containsKey('channel_ms')
                ? 1
                : 0,
            'attempt_first_body_seen':
                peer.diagnosticStages.contains('first_payload_received')
                ? 1
                : 0,
          },
        );
      }
    }
    peer.closed = true;
    _retireUpload(peer);
    if (peer.id == 'server' &&
        peer.offerSubmitted &&
        _p8p &&
        manifest!.serverOfferCancel) {
      _seedReconnectBlocked = true;
    }
    peer.signalingCancel.cancel('peer_closed');
    if (peer.bufferLow != null && !peer.bufferLow!.isCompleted) {
      peer.bufferLow!.complete();
    }
    peer.uploadQueue.clear();
    peer.uploadOutstanding.clear();
    peer.deadline?.cancel();
    _earlyCandidates.remove(peer.id);
    peer.localCandidates.clear();
    peer.remoteCandidates.clear();
    if (identical(_peers[peer.id], peer)) _peers.remove(peer.id);
    if (identical(_server, peer)) _server = null;
    if (!peer.answer.isCompleted) peer.answer.complete();
    if (!peer.iceComplete.isCompleted) peer.iceComplete.complete();
    _failPiece(peer, const AppUpgradeP2PFailure('channel_closed'));
    unawaited(_closeTransport(peer).catchError((_) {}));
    unawaited(_retireOrdinaryPeer(peer));
    if (peer.transfer != null) {
      unawaited(peer.transfer!.close().catchError((_) {}));
    }
  }

  Future<void> _retireOrdinaryPeer(_P2PPeer peer) {
    if (peer.ordinaryRetirement != null) return peer.ordinaryRetirement!;
    if (!_ordinaryPeerOwners.contains(peer)) return Future<void>.value();
    final creation = peer.creation;
    if (creation == null) {
      _ordinaryPeerOwners.remove(peer);
      return Future<void>.value();
    }
    return peer.ordinaryRetirement = creation
        .then<void>(
          (pc) async {
            await _closeTransport(peer);
            await _releaseNativePeer(pc);
            if (_releasedNativePeers[pc] == true) {
              _ordinaryPeerOwners.remove(peer);
            }
          },
          onError: (Object _, StackTrace _) {
            // A rejected factory returned no native object to retain.
            _ordinaryPeerOwners.remove(peer);
          },
        )
        .catchError((_) {});
  }

  Future<void> _trackTransportRetirement(Future<void> closing) {
    late final Future<void> owned;
    owned = closing.whenComplete(() => _transportRetirements.remove(owned));
    _transportRetirements.add(owned);
    return owned;
  }

  Future<void> _closeTransport(_P2PPeer peer) =>
      peer.transportClosing ??= _trackTransportRetirement(() async {
        final receiveBuffer = peer.receiveBuffer;
        if (receiveBuffer != null) {
          try {
            await receiveBuffer.close().timeout(
              const Duration(milliseconds: 250),
            );
          } catch (_) {
            // Optional local optimization must never prevent RTC disposal.
          }
        }
        final pc = peer.pc;
        if (pc != null) {
          // dispose owns channel/event subscriptions as well as the platform
          // observer. Do not race a separate channel.close against that owner.
          await _releaseNativePeer(pc);
        } else if (peer.channel != null) {
          try {
            await peer.channel!.close().timeout(timeouts.rtcOperation);
          } catch (_) {
            _nativeCleanupEvent('native_close_failed');
          }
        }
      }());

  Future<void> _releaseNativePeer(RTCPeerConnection pc) =>
      _nativeReleases[pc] ??= () async {
        try {
          await pc.close().timeout(timeouts.rtcOperation);
        } catch (error) {
          _nativeCleanupEvent(
            error is TimeoutException
                ? 'native_close_timeout'
                : 'native_close_failed',
          );
        }
        try {
          // close alone leaves native Android observers and event handlers
          // registered. Always attempt dispose, even after close failed.
          await pc.dispose().timeout(timeouts.rtcOperation);
          _releasedNativePeers[pc] = true;
          _nativeCleanupEvent('native_transport_released');
        } catch (error) {
          _nativeCleanupEvent(
            error is TimeoutException
                ? 'native_dispose_timeout'
                : 'native_dispose_failed',
          );
        }
      }();

  void _nativeCleanupEvent(String code) {
    try {
      _emit('rtc', code);
    } catch (_) {
      // A host's diagnostic callback must not prevent native disposal.
    }
  }

  void _failPiece(_P2PPeer peer, Object error) {
    peer.window?.fail(error);
    peer.batch?.fail(error);
    if (peer.piece != null && !peer.piece!.isCompleted) {
      peer.piece!.completeError(error);
    }
  }

  void _checkActive() {
    if (!_active) {
      throw AppUpgradeP2PFailure(
        _interrupted
            ? 'client_interrupted'
            : _reason == 'p2p_budget_exhausted'
            ? _reason
            : 'session_stopped',
      );
    }
  }

  void _checkPeer(_P2PPeer peer) {
    _checkActive();
    if (peer.closed) throw AppUpgradeP2PFailure(peer.failure);
  }

  void _emitLifecycle(P8PLifecycleEvent event, {_P2PPeer? peer}) {
    final alias = peer?.attempt?['alias'] as String? ?? event.alias;
    _emit(
      'transfer',
      event.code.code,
      source: peer != null
          ? _source(peer)
          : alias == 'https'
          ? 'https'
          : alias == 'seed'
          ? 'seed'
          : 'peer',
      attempt: alias == 'https' ? null : alias,
      metrics: event.metrics,
    );
  }

  void _emit(
    String stage,
    String code, {
    int? status,
    int? peerCount,
    int? eligiblePeerCount,
    int? durationMs,
    String? source,
    String? attempt,
    bool? verified,
    bool once = false,
    int? actualBytes,
    int? expectedBytes,
    Map<String, int> metrics = const {},
  }) {
    if (stage == 'ice_gather') {
      if (durationMs != null) _iceGatherMs = max(_iceGatherMs, durationMs);
      if (code == 'ice_complete') _iceGatherState = 'complete';
      if (code == 'ice_gather_timeout') _iceGatherState = 'timeout';
    }
    if (once && !_loggedSuccess.add('$stage:$code:${source ?? ''}')) return;
    diagnostic(
      AppUpgradeP2PDiagnostic(
        stage: stage,
        code: code,
        status: status,
        peerCount: peerCount,
        peerBytes: stage == 'result' ? _peerBytes : null,
        seedBytes: stage == 'result' ? _seedBytes : null,
        verified: verified,
        task: _task,
        elapsedMs: _elapsed.elapsedMilliseconds,
        durationMs: durationMs,
        metrics: metrics,
        source: source,
        attempt: attempt,
        appVersion: _appVersion,
        eligiblePeerCount: eligiblePeerCount,
        actualBytes: actualBytes,
        expectedBytes: expectedBytes,
        verifiedPieces: stage == 'result' && _storeReady
            ? _store.verifiedPieces.length
            : null,
        verifiedBytes: stage == 'result' && _storeReady
            ? _store.verifiedPieces.fold<int>(
                0,
                (total, index) => total + manifest!.pieceSize(index),
              )
            : null,
      ),
    );
  }

  static final _iceType = RegExp(
    r'(?:^|\n)(?:a=)?candidate:[^\r\n]*?\btyp (host|srflx|prflx|relay)\b',
  );

  static int _iceCandidateTypes(String sdpOrCandidate) {
    var types = 0;
    for (final match in _iceType.allMatches(sdpOrCandidate)) {
      types |= switch (match.group(1)) {
        'host' => 1,
        'srflx' => 2,
        'prflx' => 4,
        'relay' => 8,
        _ => 0,
      };
    }
    return types;
  }

  static bool _isPeerId(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
  static bool _retryableReport(String code) =>
      code == 'http_timeout' || code == 'network_error';
  static String _sourceFailure(Object error, {required bool seed}) {
    final code = _failureCode(error);
    if (code == 'piece_checksum_mismatch') {
      return seed ? 'server_seed_integrity_error' : 'peer_integrity_error';
    }
    return code;
  }

  static String _failureCode(Object error) {
    if (error is AppUpgradeP2PFailure) return error.code;
    if (error is TimeoutException) return 'source_timeout';
    if (error is FileSystemException) return 'local_storage_error';
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'http_timeout',
        DioExceptionType.cancel => 'request_cancelled',
        _ => 'network_error',
      };
    }
    return 'protocol_error';
  }

  static String _serverCode(Object? value) {
    const allowed = {
      'p2p_disabled',
      'release_changed',
      'release_not_available',
      'application_package_conflict',
      'p2p_app_client_required',
      'peer_not_shareable',
      'peer_not_available',
      'signal_queue_full',
      'server_offer_attempt_limit',
      'server_seed_busy',
      'server_seed_unavailable',
      'invalid_offer',
      'busy',
      'invalid_request',
      'invalid_piece',
      'piece_unavailable',
      'seed_send_failed',
      'sharing_disabled',
      'session_capacity_exceeded',
      'rate_limited',
      'invalid_session',
      'network_not_allowed',
      'invalid_network',
      'invalid_sha256',
      'outcome_conflict',
      'idempotency_conflict',
      'p2p_session_already_active',
      'invalid_idempotency_key',
      'p2p_budget_exhausted',
      'server_offer_timeout',
      'server_offer_cancel_pending',
      'server_offer_cancel_capacity',
      'server_offer_cancel_unavailable',
      'offer_cancelled',
      'candidate_queue_full',
      'candidate_too_large',
      'invalid_candidate',
      'invalid_offer_id',
      'candidate_processing_timeout',
      'server_candidate_offer_limit',
      'p2p_session_invalid',
      'invalid_p2p_diagnostics',
    };
    return allowed.contains(value) ? value as String : 'http_error';
  }
}

/// Short-lived observations of the exact live peer registration, local to
/// this SDK instance. No stable device identifiers, disk or telemetry.
class _P2PCandidateHistory {
  static const _lifetimeMs = 120000;
  final _clock = Stopwatch()..start();
  final _scores = <(String, String), ({int expires, int? firstPieceMs})>{};

  void record(String scope, String id, {int? firstPieceMs}) {
    final key = (scope, id);
    _scores.remove(key);
    if (_scores.length >= 32) _scores.remove(_scores.keys.first);
    _scores[key] = (
      expires: _clock.elapsedMilliseconds + _lifetimeMs,
      firstPieceMs: firstPieceMs,
    );
  }

  Iterable<Map> order(String scope, List<Map> candidates) {
    final now = _clock.elapsedMilliseconds;
    _scores.removeWhere((_, observation) => observation.expires <= now);
    if (_scores.isEmpty) return candidates;
    (int, int) priority(Map candidate) {
      final id = candidate['peer_id'];
      final score = id is String ? _scores[(scope, id)] : null;
      if (score == null) return (1, 0);
      final elapsed = score.firstPieceMs;
      return elapsed == null ? (2, 0) : (0, elapsed);
    }

    final ranked = candidates.indexed.toList();
    ranked.sort((a, b) {
      final pa = priority(a.$2), pb = priority(b.$2);
      final group = pa.$1.compareTo(pb.$1);
      if (group != 0) return group;
      final time = pa.$2.compareTo(pb.$2);
      return time != 0 ? time : a.$1.compareTo(b.$1);
    });
    return ranked.map((entry) => entry.$2);
  }
}

class _P2PPeer {
  _P2PPeer(this.id, this.inbound);
  final String id;
  final bool inbound;
  final answer = Completer<void>();
  final iceComplete = Completer<void>();
  final connectWatch = Stopwatch()..start();
  Duration? startupLimit;
  final signalingCancel = CancelToken();
  Timer? deadline;
  Timer? iceStatsTimer;
  int iceStatsAttempts = 0;
  int? iceStatsAt;
  Map<String, int> iceStats = const {};
  void Function()? remoteIceProgress;
  final localCandidates = <Map<String, Object?>?>[];
  final localCandidatesSeen = <String>{};
  final remoteCandidates = <RTCIceCandidate?>[];
  final remoteCandidatesSeen = <String>{};
  Map<String, Object?>? attempt;
  String? offerId;
  bool offerSubmitted = false;
  final Set<String> diagnosticStages = {};
  bool firstLocalCandidatePosted = false;
  bool candidatesStarted = false,
      candidatesBusy = false,
      candidateFailed = false;
  bool remoteReady = false, remoteBusy = false;
  bool answerReceived = false;
  RTCIceConnectionState? iceState;
  int remoteTrickleApplied = 0, localIceTypes = 0, remoteIceTypes = 0;
  bool trickle = false;
  Stopwatch? gatherWatch;
  RTCPeerConnection? pc;
  RTCDataChannel? channel;
  Completer<Uint8List>? piece;
  AppUpgradeP2PPieceReceiver? receiver;
  AppUpgradeP2PBatchReceiver? batch;
  AppUpgradeP2PWindowReceiver? window;
  Completer<void>? bufferLow;
  bool pipelineSupported = false, pipelineUpload = false;
  bool p8pSupported = false;
  bool leased = false;
  bool lateDiscovery = false;
  P8PTransferReceiver? transfer;
  Future<void>? transportClosing;
  Future<void>? ordinaryRetirement;
  Future<RTCPeerConnection>? creation;
  AppUpgradeUploadSlot? uploadSlot;
  P8PTransferSender? sender;
  AppUpgradeReceiveBufferOwner? receiveBuffer;
  int? p8pUploadWindow;
  P8PWindowController? p8pWindow;
  final uploadQueue = <int>[];
  final uploadOutstanding = <int>{};
  bool uploading = false, closed = false;
  _P2PUploadLedger? uploadLedger;
  Future<void>? uploadSend;
  Future<void>? uploadWork;
  int maxBatchPieces = 4;
  String failure = 'channel_closed';
}

class _P2PUploadLedger {
  _P2PUploadLedger(this.peerId);
  final String peerId;
  int sentBytes = 0, reportedBytes = 0;
  bool unavailable = false;
  Duration? lastReport;
  Future<void>? reporting;
}
