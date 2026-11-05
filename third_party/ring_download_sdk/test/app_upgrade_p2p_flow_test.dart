import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ring_download_sdk/compat.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_receive_buffer.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_upload_budget.dart';
import 'package:ring_download_sdk/src/p8p/transfer_protocol.dart';

// Private real-file owner fixture; transport remains the existing deterministic test seam.
// ignore: avoid_relative_lib_imports
import '../example/lib/p8p_lifecycle_file_io.dart';

const _url = 'https://download.csnas.asia/lifering/download';
const _self = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _other = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Harness harness;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('auralink-p2p-test-');
    harness = _Harness(directory);
  });
  tearDown(() async {
    await harness.client.stopSharing();
    await harness.events.close();
    await _settle();
    await AppUpgradeP2PDiagnostics.read();
    await directory.delete(recursive: true);
  });

  Future<bool> restoreCache() => harness.client.restoreSharingFromCache(
    file: harness.part,
    downloadUrl: _url,
    expectedSlug: 'lifering',
    expectedVersion: 'test',
    expectedFileSize: harness.bytes.length,
    expectedSha256: sha256.convert(harness.bytes).toString(),
  );

  test(
    'cold leased sharing publishes capability in an immediate heartbeat',
    () async {
      harness.manifestOverride['p8p'] = {
        'version': 1,
        'transfer': P8PTransferProtocol.capability,
      };
      harness.client = harness.makeClient(
        enableP8P: true,
        sharingDuration: null,
      );
      await harness.part.writeAsBytes(harness.bytes);
      expect(await restoreCache(), true);
      await _settle();
      final heartbeats = harness.requests
          .where((r) => r.uri.pathSegments.last == 'heartbeat')
          .toList();
      expect(
        heartbeats,
        isNotEmpty,
        reason:
            'The existing service marks lease capability freshness only on heartbeat',
      );
      expect(
        (heartbeats.last.data as Map)['p8p_transfer'],
        P8PTransferProtocol.capability,
      );
      expect((heartbeats.last.data as Map)['pieces'], isNotEmpty);
    },
  );

  test('metered change during phone pacing permits no late payload', () async {
    harness.client = harness.makeClient(
      sharingDuration: null,
      uploadBudget: AppUpgradeUploadBudget(),
    );
    harness.incomingOffer = true;
    await harness.part.writeAsBytes(harness.bytes);
    expect(await restoreCache(), true);
    await _waitUntil(() => harness.peers.isNotEmpty);
    await _settle();
    final channel = harness.peers.single.channel;
    Timer? transition;
    try {
      channel.onNativeBufferQuery = () {
        if (channel.nativeBufferQueries == 6) {
          transition = Timer(const Duration(milliseconds: 20), () {
            // Omit the event: a fresh native read must independently guard a
            // platform callback which is delayed during the rate wait.
            harness.network = AppUpgradeP2PNetwork.cellular;
          });
        }
      };
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await _waitUntil(() => harness.peers.single.closed);
      expect(channel.binaryBytes, 5 * AppUpgradeP2PManifest.maxFrameBytes);
    } finally {
      transition?.cancel();
    }
  });

  test(
    'phone cache advertises and delivers leased frames within the original deadline',
    () async {
      harness.manifestOverride['p8p'] = {
        'version': 1,
        'transfer': P8PTransferProtocol.capability,
      };
      harness.channelLabel = P8PTransferProtocol.channel;
      harness.incomingOffer = true;
      harness.client = harness.makeClient(
        enableP8P: true,
        sharingDuration: null,
        uploadBudget: AppUpgradeUploadBudget(),
      );
      await harness.part.writeAsBytes(harness.bytes);
      expect(await restoreCache(), true);
      await _waitUntil(() => harness.peers.isNotEmpty);
      await _settle();
      expect(
        harness.body('session')['p8p_transfer'],
        P8PTransferProtocol.capability,
      );
      expect(harness.body('session')['max_connections'], 1);
      final channel = harness.peers.single.channel;
      final clock = Stopwatch()..start();
      var bodyBytes = 0;
      channel.onQueued = (message) {
        if (!message.isBinary) return;
        bodyBytes += P8PTransferProtocol.frame(message.binary).body.length;
        expect(
          bodyBytes,
          lessThanOrEqualTo(
            256 * 1024 +
                clock.elapsedMicroseconds * 256 * 1024 / 1000000 +
                2048,
          ),
        );
      };
      channel.receiveText({
        'type': 'hello',
        'version': 1,
        'generation': 7,
        'source_capacity_supported': true,
        'sha256': sha256.convert(harness.bytes).toString(),
      });
      for (var index = 0; index < 2; index++) {
        channel.receiveText({
          'type': 'get',
          'version': 1,
          'generation': 7,
          'request_id': index + 1,
          'index': index,
        });
      }
      await _waitUntil(() => channel.pieceEnds == 2, attempts: 700);
      expect(clock.elapsed, lessThan(const Duration(seconds: 8)));
      final controls = channel.sent
          .where((m) => !m.isBinary)
          .map((m) => jsonDecode(m.text) as Map)
          .toList();
      expect(controls.first['max_inflight'], 4);
      expect(controls.first['source_capacity'], 1);
      final actual = BytesBuilder(copy: false);
      for (final message in channel.sent.where((m) => m.isBinary)) {
        actual.add(P8PTransferProtocol.frame(message.binary).body);
      }
      expect(
        sha256.convert(actual.takeBytes()).toString(),
        sha256.convert(harness.bytes).toString(),
      );
      await harness.client.stopSharing();
      expect(harness.reportedUploadBytes, harness.bytes.length);
    },
  );

  test(
    'phone receiver slot survives revocation until native retirement',
    () async {
      final budget = AppUpgradeUploadBudget();
      harness.client = harness.makeClient(
        sharingDuration: null,
        uploadBudget: budget,
      );
      harness.incomingOffer = true;
      await harness.part.writeAsBytes(harness.bytes);
      expect(await restoreCache(), true);
      await _waitUntil(() => harness.peers.isNotEmpty);
      await _settle();
      final native = Completer<void>();
      harness.peers.single.closeGate = native.future;
      try {
        expect(budget.tryAcquire(), null);
        harness.client.setResourcesAllowed(false);
        var stopped = false;
        final stopping = harness.client.stopSharing().then(
          (_) => stopped = true,
        );
        await _settle();
        expect(stopped, false);
        expect(budget.tryAcquire(), null);
        native.complete();
        await stopping;
        final next = budget.tryAcquire();
        expect(next, isNotNull);
        next!.release();
      } finally {
        if (!native.isCompleted) native.complete();
      }
    },
  );

  test(
    'cold cache restore registers sharing without any receiving/body request',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.part.writeAsBytes(harness.bytes);
      expect(await restoreCache(), true);
      // Android cache shares retain the existing download role; the explicit
      // opt-in and verified pieces distinguish this from a receiving task.
      expect(harness.body('session')['role'], 'download');
      expect(harness.body('session')['share_enabled'], true);
      expect(harness.body('session')['pieces'], isNotEmpty);
      expect(harness.paths, isNot(contains('server-offer')));
      expect(harness.paths, isNot(contains('peers')));
      expect(harness.peers, isEmpty);
      expect(await harness.part.readAsBytes(), harness.bytes);
      final before = harness.paths.where((p) => p == 'session').length;
      harness.client.setForeground(false);
      await _settle();
      harness.client.setForeground(true);
      await _waitUntil(
        () => harness.paths.where((p) => p == 'session').length == before + 1,
      );
      expect(harness.paths.where((p) => p == 'manifest').length, 1);
    },
  );

  test(
    'a fresh client can explicitly restore the retained checked file',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.part.writeAsBytes(harness.bytes);
      expect(await restoreCache(), true);
      await harness.client.close();
      harness.client = harness.makeClient(sharingDuration: null);
      expect(await restoreCache(), true);
      expect(harness.paths.where((p) => p == 'session').length, 2);
      expect(harness.paths.where((p) => p == 'manifest').length, 2);
      expect(harness.paths, isNot(contains('server-offer')));
    },
  );

  test(
    'cold restore refuses corrupt bytes without modifying the cache',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      final corrupt = List<int>.filled(harness.bytes.length, 0);
      await harness.part.writeAsBytes(corrupt);
      expect(await restoreCache(), false);
      expect(harness.paths, isNot(contains('session')));
      expect(await harness.part.readAsBytes(), corrupt);
    },
  );

  test(
    'sharing never truncates a cache when piece hashes disagree with full SHA',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.part.writeAsBytes(harness.bytes);
      harness.manifestOverride['piece_hashes'] = [
        for (final _ in harness.manifestJson['piece_hashes'] as List) '0' * 64,
      ];
      expect(await restoreCache(), false);
      expect(harness.paths, isNot(contains('session')));
      expect(await harness.part.readAsBytes(), harness.bytes);
    },
  );

  test(
    'cold restore does no HTTP when consent, foreground or Wi-Fi denies sharing',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.part.writeAsBytes(harness.bytes);
      harness.client.setSharingEnabled(false);
      expect(await restoreCache(), false);
      harness.client.setSharingEnabled(true);
      harness.client.setForeground(false);
      expect(await restoreCache(), false);
      harness.client.setForeground(true);
      for (final network in [
        AppUpgradeP2PNetwork.cellular,
        AppUpgradeP2PNetwork.wifiMetered,
        AppUpgradeP2PNetwork.unknown,
      ]) {
        harness.network = network;
        expect(await restoreCache(), false);
      }
      expect(harness.paths, isEmpty);
    },
  );

  test(
    'revocation while restoring manifest cannot register a late seed',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.part.writeAsBytes(harness.bytes);
      final entered = Completer<void>(), release = Completer<void>();
      harness.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            if (request.uri.path.endsWith('/manifest')) {
              entered.complete();
              await release.future;
            }
            handler.next(request);
          },
        ),
      );
      final restoring = restoreCache();
      await entered.future;
      harness.client.setSharingEnabled(false);
      release.complete();
      expect(await restoring, false);
      await harness.client.stopSharing();
      expect(harness.paths, isNot(contains('session')));
      expect(await harness.part.readAsBytes(), harness.bytes);
    },
  );

  test('main HTTPS source uses backup P2P endpoints and STUN', () async {
    expect(await harness.downloadPrefix(), harness.bytes.length);
    await _settle();
    expect(harness.part.readAsBytesSync(), harness.bytes);
    expect(
      harness.paths,
      containsAll(['manifest', 'session', 'server-offer', 'outcome', 'leave']),
    );
    expect(
      harness.requests.every(
        (r) => r.uri.origin == 'https://download1.csnas.asia',
      ),
      isTrue,
    );
    final manifest = harness.parsedManifest();
    expect(
      manifest.apiBase,
      'https://download1.csnas.asia/api/app/lifering/p2p',
    );
    expect(
      manifest.serverSeedUrl,
      'https://download1.csnas.asia/api/app/lifering/p2p/server-offer',
    );
    expect(manifest.stunUrls, [
      'stun:download.csnas.asia:3479',
      'stun:download1.csnas.asia:3479',
    ]);
    expect(harness.peerConfigurations.single['iceServers'], [
      {'urls': 'stun:download.csnas.asia:3479'},
      {'urls': 'stun:download1.csnas.asia:3479'},
    ]);
    expect(harness.info.downloadUrl, _url);
    expect(
      AppUpgradeP2PManifest.originForDownload(_url, 'lifering'),
      'https://download.csnas.asia',
    );
  });

  test(
    'receive buffer ownership does not await signalling and retires before native RTC reuse',
    () async {
      final gate = Completer<void>();
      final owner = _BufferOwner(closeGate: gate);
      harness.localIceCandidates = [
        RTCIceCandidate(
          'candidate:123 1 udp 2122260223 192.0.2.10 45000 typ host',
          '0',
          0,
        ),
      ];
      harness.client = harness.makeClient(receiveBufferFactory: () => owner);
      try {
        expect(await harness.downloadPrefix(), harness.bytes.length);
        expect(owner.candidates, hasLength(1));
        expect(owner.closeCalls, 1);
        expect(harness.peers.single.closeCalls, 0);
        final previous = owner.candidates.length;
        harness.peers.single.onIceCandidate?.call(
          harness.localIceCandidates.single,
        );
        expect(owner.candidates, hasLength(previous));
      } finally {
        gate.complete();
      }
      await _waitUntil(() => harness.peers.single.disposeCalls == 1);
      expect(harness.part.readAsBytesSync(), harness.bytes);
    },
  );

  test(
    'optional receive buffer factory failure preserves verified download',
    () async {
      harness.client = harness.makeClient(
        receiveBufferFactory: () => throw StateError('optional'),
      );
      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _waitUntil(() => harness.peers.single.disposeCalls == 1);
      expect(harness.part.readAsBytesSync(), harness.bytes);
    },
  );

  test(
    'optional candidate and close failures cannot prevent signalling or native disposal',
    () async {
      final owner = _BufferOwner(fail: true);
      harness.localIceCandidates = [
        RTCIceCandidate(
          'candidate:123 1 udp 2122260223 192.0.2.10 45000 typ host',
          '0',
          0,
        ),
      ];
      harness.client = harness.makeClient(receiveBufferFactory: () => owner);
      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _waitUntil(() => harness.peers.single.disposeCalls == 1);
      expect(owner.candidates, hasLength(1));
      expect(owner.closeCalls, 1);
      expect(harness.part.readAsBytesSync(), harness.bytes);
    },
  );

  test(
    'backup download source remains eligible and accepts backup API metadata',
    () async {
      harness.manifestOverride['peer_api_base'] =
          'https://download1.csnas.asia/api/app/lifering/p2p';
      harness.manifestOverride['server_seed_url'] =
          'https://download1.csnas.asia/api/app/lifering/p2p/server-offer';
      expect(
        await harness.downloadPrefix(
          url: 'https://download1.csnas.asia/lifering/download',
        ),
        harness.bytes.length,
      );
      await _settle();
      expect(
        harness.requests.every(
          (r) => r.uri.origin == 'https://download1.csnas.asia',
        ),
        isTrue,
      );
      expect(harness.body('outcome')['verified'], isTrue);
    },
  );

  test(
    'peer four-piece mode keeps startup single and verifies short tail',
    () async {
      harness.advertisePeer = true;
      harness.advertisedPieces = List.generate(7, (i) => i);
      harness.bytes = Uint8List.fromList(
        List.generate(AppUpgradeP2PManifest.chunkSize * 6 + 79, (i) => i % 251),
      );
      harness.client = harness.makeClient();
      expect(await harness.downloadPrefix(), harness.bytes.length);
      expect(await harness.part.readAsBytes(), harness.bytes);
      final controls = harness.peers.single.channel.sent
          .where((m) => !m.isBinary)
          .map((m) => jsonDecode(m.text) as Map)
          .toList();
      expect(
        controls.where((m) => m['type'] == 'get-piece').map((m) => m['index']),
        [0],
      );
      expect(
        controls
            .where((m) => m['type'] == 'get-pieces')
            .map((m) => m['indices'])
            .toList(),
        [
          [1, 2, 3, 4],
          [5, 6],
        ],
      );
      expect(harness.body('outcome')['peer_bytes'], harness.bytes.length);
      // Check the exported representation: a raw event can pass while the
      // closed-schema serializer accidentally replaces its code with unknown.
      expect(
        harness.logs.map((event) => event.toJson()['code']),
        contains('batch_four_selected'),
      );
      expect(harness.paths, isNot(contains('server-offer')));
    },
  );

  test(
    'peer corrupt batch preserves only the persisted verified prefix',
    () async {
      harness.advertisePeer = true;
      harness.advertisedPieces = List.generate(6, (i) => i);
      harness.seedBusy = true;
      harness.bytes = Uint8List.fromList(
        List.generate(AppUpgradeP2PManifest.chunkSize * 5 + 79, (i) => i % 251),
      );
      harness.corruptIndex = 2;
      harness.client = harness.makeClient();
      expect(await harness.downloadPrefix(), AppUpgradeP2PManifest.chunkSize);
      expect(await harness.part.length(), AppUpgradeP2PManifest.chunkSize);
      await _settle();
      expect(
        harness.body('outcome')['peer_bytes'],
        AppUpgradeP2PManifest.chunkSize,
      );
    },
  );

  test(
    'peer batch timeout resumes HTTPS with full final SHA verification',
    () async {
      harness.advertisePeer = true;
      harness.advertisedPieces = List.generate(8, (i) => i);
      harness.seedBusy = true;
      harness.enableTrickle();
      harness.bytes = Uint8List.fromList(
        List.generate(
          AppUpgradeP2PManifest.chunkSize * 7 + 79,
          (index) => index % 251,
        ),
      );
      harness.dropIndex = 2;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(milliseconds: 500),
      );
      final https = Dio();
      final telemetry = Dio();
      final reportedEvents = <RequestOptions>[];
      telemetry.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            reportedEvents.add(request);
            handler.resolve(Response(requestOptions: request, statusCode: 201));
          },
        ),
      );
      final serviceEvents = AppUpgradeServiceEvents(dio: telemetry);
      RequestOptions? rangeRequest;
      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            rangeRequest = request;
            final offset = AppUpgradeP2PManifest.chunkSize;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 206,
                headers: Headers.fromMap({
                  'content-range': [
                    'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                  ],
                  'etag': ['"release-test"'],
                  'x-download-session-id': ['0123456789abcdef'],
                }),
                data: ResponseBody.fromBytes(
                  harness.bytes.sublist(offset),
                  206,
                  headers: {
                    'content-range': [
                      'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                    ],
                    'etag': ['"release-test"'],
                    'x-download-session-id': ['0123456789abcdef'],
                  },
                ),
              ),
            );
          },
        ),
      );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        serviceEvents: serviceEvents,
        supportDirectoryLoader: () async => directory,
      );
      final file = await downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: null,
        refreshRelease: () async => harness.info,
        onProgress: (_, _) {},
      );
      expect(
        rangeRequest?.headers['range'],
        'bytes=${AppUpgradeP2PManifest.chunkSize}-',
      );
      expect(rangeRequest?.headers['if-range'], '"release-test"');
      expect(await file.readAsBytes(), harness.bytes);
      expect(harness.client.lastDownloadUsedP2P, isTrue);
      await downloader.rememberVerifiedInstallation(harness.info);
      await serviceEvents.reconcileInstalledBuild(harness.info.versionCode);
      await serviceEvents.flush();
      expect(
        reportedEvents,
        isEmpty,
        reason: 'HTTP coverage cannot attest to the P2P-supplied prefix',
      );
      await _settle();
      expect(harness.body('outcome')['outcome'], 'https_fallback');
      expect(harness.body('outcome')['verified'], false);
      expect(
        harness.logs.any((event) => event.code == 'peer_transfer_timeout'),
        isTrue,
      );
    },
  );

  test('standard opaque STUN URI accepts the production manifest grammar', () {
    expect(
      AppUpgradeP2PManifest.isStunUrl('stun:stun.l.google.com:19302'),
      isTrue,
    );
    expect(AppUpgradeP2PManifest.isStunUrl('stuns:example.com:5349'), isTrue);
    expect(AppUpgradeP2PManifest.isStunUrl('stun:[2001:db8::1]:3478'), isTrue);
    for (final value in [
      'https://example.com',
      'stun:user@host:3478',
      'stun:host:65536',
      'stun:host:0',
      'stun:host/path',
      'stun:',
    ]) {
      expect(AppUpgradeP2PManifest.isStunUrl(value), isFalse, reason: value);
    }
    harness.manifestOverride['stun_urls'] = [
      'stun:download.csnas.asia:3479',
      'stun:download1.csnas.asia:3479',
      'stun:[2001:db8::1]:3479',
    ];
    expect(harness.parsedManifest().stunUrls, [
      'stun:download.csnas.asia:3479',
      'stun:download1.csnas.asia:3479',
      'stun:[2001:db8::1]:3479',
    ]);
  });

  test('seed uses one startup piece then bounded four-piece batches', () async {
    harness.bytes = Uint8List.fromList(
      List.generate(
        AppUpgradeP2PManifest.chunkSize * 9 + 79,
        (index) => index % 251,
      ),
    );
    expect(await harness.downloadPrefix(), harness.bytes.length);
    expect(await harness.part.readAsBytes(), harness.bytes);
    final controls = harness.peers.single.channel.sent
        .where((message) => !message.isBinary)
        .map((message) => jsonDecode(message.text) as Map)
        .where(
          (message) =>
              message['type'] == 'get-piece' || message['type'] == 'get-pieces',
        )
        .toList();
    expect(controls, [
      {'type': 'get-piece', 'index': 0, 'pipeline_window': 4},
      {
        'type': 'get-pieces',
        'indices': [1, 2, 3, 4],
      },
      {
        'type': 'get-pieces',
        'indices': [5, 6, 7, 8],
      },
      {
        'type': 'get-pieces',
        'indices': [9],
      },
    ]);
    await _settle();
    expect(harness.body('leave'), isEmpty);
    expect(
      harness.logs.firstWhere((event) => event.stage == 'result').seedBytes,
      harness.bytes.length,
    );
  });

  test('corrupt batch preserves only the persisted prefix for HTTPS', () async {
    harness.bytes = Uint8List.fromList(
      List.generate(
        AppUpgradeP2PManifest.chunkSize * 5 + 79,
        (index) => index % 251,
      ),
    );
    harness.corruptIndex = 3;
    expect(await harness.downloadPrefix(), AppUpgradeP2PManifest.chunkSize);
    expect(await harness.part.length(), AppUpgradeP2PManifest.chunkSize);
    expect(
      await harness.part.readAsBytes(),
      harness.bytes.sublist(0, AppUpgradeP2PManifest.chunkSize),
    );
    await _settle();
    expect(harness.body('outcome')['outcome'], 'https_fallback');
    expect(harness.body('leave'), isEmpty);
  });

  test('healthy batch renews the timeout after each verified piece', () async {
    harness.bytes = Uint8List.fromList(
      List.generate(
        AppUpgradeP2PManifest.chunkSize * 5 + 79,
        (index) => index % 251,
      ),
    );
    harness.pieceDelay = const Duration(milliseconds: 180);
    harness.client = harness.makeClient(
      sourceTimeout: const Duration(milliseconds: 500),
    );
    expect(await harness.downloadPrefix(), harness.bytes.length);
    expect(await harness.part.readAsBytes(), harness.bytes);
  });

  test(
    'cancellation during a batch releases it without persisting later pieces',
    () async {
      harness.bytes = Uint8List.fromList(
        List.generate(
          AppUpgradeP2PManifest.chunkSize * 5 + 79,
          (index) => index % 251,
        ),
      );
      harness.dropIndex = 2;
      final cancel = CancelToken();
      final task = harness.downloadPrefix(cancelToken: cancel);
      final assertion = expectLater(task, throwsA(isA<DioException>()));
      var batchStarted = false;
      for (var i = 0; i < 200; i++) {
        batchStarted = harness.peers.any(
          (peer) => peer.channel.sent.any(
            (message) =>
                !message.isBinary &&
                (jsonDecode(message.text) as Map)['type'] == 'get-pieces',
          ),
        );
        if (batchStarted) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(batchStarted, isTrue);
      cancel.cancel();
      await assertion;
      expect(await harness.part.length(), AppUpgradeP2PManifest.chunkSize);
      await _settle();
      expect(harness.body('outcome')['outcome'], 'client_interrupted');
      expect(harness.body('leave'), isEmpty);
    },
  );

  test(
    'batch timeout preserves the first piece and releases the session',
    () async {
      harness.bytes = Uint8List.fromList(
        List.generate(
          AppUpgradeP2PManifest.chunkSize * 5 + 79,
          (index) => index % 251,
        ),
      );
      harness.dropIndex = 2;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(milliseconds: 500),
      );
      expect(await harness.downloadPrefix(), AppUpgradeP2PManifest.chunkSize);
      await _settle();
      expect(harness.body('outcome')['outcome'], 'https_fallback');
      expect(harness.body('leave'), isEmpty);
    },
  );

  test(
    'manifest mismatch and disabled auto-start never create a session',
    () async {
      for (final change in [
        {'version': 'other'},
        {'sha256': '0' * 64},
        {'protocol_version': 2},
        {'app_slug': 'other'},
        {'auto_start': false},
        {'status': 'disabled'},
        {'piece_hashes': <String>[]},
        {
          'stun_urls': ['stun:invalid@host'],
        },
      ]) {
        harness.manifestOverride = change;
        harness.requests.clear();
        await harness.downloadPrefix();
        expect(harness.paths, ['manifest']);
        expect(harness.logs.last.code, isNot('p2p_complete'));
      }
    },
  );

  test(
    'cellular creates download-only session and receives verified seed pieces',
    () async {
      harness.network = AppUpgradeP2PNetwork.cellular;
      final prefix = await harness.downloadPrefix();
      await _settle();
      expect(prefix, harness.bytes.length);
      expect(await harness.part.readAsBytes(), harness.bytes);
      final body = harness.body('session');
      expect(body['network'], 'cellular');
      expect(body['share_enabled'], false);
      expect(body['pieces'], isEmpty);
      expect(body['role'], 'download');
      expect(
        harness.paths,
        containsAllInOrder([
          'manifest',
          'session',
          'peers',
          'server-offer',
          'outcome',
          'leave',
        ]),
      );
      expect(
        harness.requests.any(
          (request) => request.uri.path == '/lifering/download',
        ),
        isFalse,
      );
      expect(harness.body('outcome'), containsPair('peer_bytes', 0));
      expect(harness.body('outcome'), containsPair('verified', true));
      expect(harness.body('outcome'), containsPair('outcome', 'p2p_complete'));
      expect(harness.body('leave'), isEmpty);
      final diagnostics = harness.body('outcome')['diagnostics'] as Map;
      for (final key in [
        'ice_connect_ms',
        'data_channel_ms',
        'first_piece_ms',
      ]) {
        expect(diagnostics[key], isA<int>(), reason: key);
        expect(diagnostics[key] as int, inInclusiveRange(0, 120000));
      }
      final result = harness.logs.firstWhere(
        (event) => event.stage == 'result',
      );
      expect(result.seedBytes, harness.bytes.length);
      expect(result.peerBytes, 0);
    },
  );

  test('Wi-Fi metered also receives without publishing share pieces', () async {
    harness.network = AppUpgradeP2PNetwork.wifiMetered;
    expect(await harness.downloadPrefix(), harness.bytes.length);
    expect(harness.body('session'), containsPair('share_enabled', false));
  });

  test(
    'Trickle submits seed offer and candidates before ICE completes',
    () async {
      harness.enableTrickle();
      harness.iceNeverCompletes = true;
      harness.localIceCandidates = [
        RTCIceCandidate(
          'candidate:1 1 udp 1 192.168.1.99 1234 typ host',
          '0',
          0,
        ),
        RTCIceCandidate(
          'candidate:1 1 udp 1 192.168.1.99 1234 typ host',
          '0',
          0,
        ),
      ];
      final gate = Completer<void>();
      final candidatePosted = Completer<void>();
      harness.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            if (request.uri.pathSegments.last == 'server-offer') {
              await candidatePosted.future;
            }
            handler.next(request);
          },
        ),
      );
      harness.seedGate = gate.future;
      final download = harness.downloadPrefix();
      unawaited(download.then<void>((_) {}, onError: (Object _) {}));
      try {
        // Trickle posts run concurrently and the server buffers by offer ID.
        // Either post can arrive first; both must precede ICE completion.
        await harness.waitForPath('server-candidate');
        candidatePosted.complete();
        await harness.waitForPath('server-offer');
        expect(
          harness.paths.indexOf('server-candidate'),
          lessThan(harness.paths.indexOf('server-offer')),
        );
        expect(harness.peers.single.gatherComplete, false);
        expect(harness.body('server-offer')['sdp'], contains('partial'));
        final offerId = harness.body('server-offer')['offer_id'];
        expect(offerId, matches(RegExp(r'^[a-f0-9]{32}$')));
        expect(harness.body('server-candidate')['offer_id'], offerId);
        expect(harness.paths.where((p) => p == 'server-candidate').length, 1);
        gate.complete();
        expect(await download, harness.bytes.length);
        await harness.waitForPath('outcome');
        expect(harness.body('outcome')['verified'], true);
      } finally {
        if (!candidatePosted.isCompleted) candidatePosted.complete();
        if (!gate.isCompleted) gate.complete();
        await download.then<void>((_) {}, onError: (Object _) {});
      }
    },
  );

  test('Trickle remote candidates wait for SDP and are deduplicated', () async {
    harness.enableTrickle();
    harness.advertisePeer = true;
    harness.iceNeverCompletes = true;
    harness.signalRemoteCandidates = true;
    harness.localIceCandidates = [
      RTCIceCandidate(
        'candidate:v6 1 udp 1 2001:db8::99 1234 typ host',
        '0',
        0,
      ),
    ];
    harness.remoteCandidates.add({
      'from_peer_id': _other,
      'candidate': {
        'candidate': 'candidate:9 1 udp 1 192.168.1.98 4321 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      },
    });
    harness.remoteCandidates.add({
      'from_peer_id': _other,
      'candidate': {
        'candidate': 'candidate:10 1 udp 1 2001:db8::98 4322 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      },
    });
    harness.remoteDescriptionDelay = const Duration(milliseconds: 40);
    expect(await harness.downloadPrefix(), harness.bytes.length);
    await _settle();
    expect(harness.peers.single.addedCandidates.length, 2);
    expect(
      harness.peers.single.addedCandidates.any(
        (candidate) => candidate.candidate!.contains('2001:db8::98'),
      ),
      isTrue,
    );
    expect(harness.peers.single.candidateBeforeDescription, false);
    expect(
      harness.requests
          .where((r) => r.uri.path.endsWith('/signals'))
          .every((r) => r.uri.queryParameters['include_candidates'] == '1'),
      true,
    );
    expect(harness.paths, isNot(contains('server-offer')));
    expect(
      harness.body('candidate')['candidate']['candidate'],
      contains('2001:db8::99'),
    );
  });

  test('Trickle caps candidate posts and preserves IPv6', () async {
    harness.enableTrickle();
    harness.localIceCandidates = [
      RTCIceCandidate('candidate:v6 1 udp 1 2001:db8::1 1234 typ host', '0', 0),
      ...List.generate(
        40,
        (i) => RTCIceCandidate(
          'candidate:$i 1 udp 1 192.168.1.99 ${1234 + i} typ host',
          '0',
          0,
        ),
      ),
    ];
    final gate = Completer<void>();
    harness.seedGate = gate.future;
    final download = harness.downloadPrefix();
    for (
      var i = 0;
      i < 100 &&
          harness.paths.where((p) => p == 'server-candidate').length < 33;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final posts = harness.requests
        .where((r) => r.uri.path.endsWith('/server-candidate'))
        .toList();
    expect(posts.length, 33);
    expect(posts.where((r) => (r.data as Map)['candidate'] != null).length, 32);
    expect((posts.last.data as Map)['candidate'], isNull);
    expect(posts.any((r) => jsonEncode(r.data).contains('2001:db8')), true);
    expect(harness.body('server-offer')['sdp'], contains('2001:db8::99'));
    gate.complete();
    expect(await download, harness.bytes.length);
  });

  test(
    'candidate signaling HTTP failures are not counted as ICE candidate errors',
    () async {
      harness.enableTrickle();
      harness.failCandidatePosts = true;
      harness.localIceCandidates = [
        RTCIceCandidate(
          'candidate:1 1 udp 1 192.168.1.99 1234 typ host',
          '0',
          0,
        ),
      ];

      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _settle();

      expect(
        harness.body('outcome')['diagnostics']['candidate_error_count'],
        0,
      );
      expect(
        harness.logs.any(
          (event) =>
              event.stage == 'candidate' &&
              event.code == 'server_seed_unavailable',
        ),
        isTrue,
      );
    },
  );

  test(
    'seed trickle queues before Answer and acknowledges repeated delivery once',
    () async {
      harness.enableTrickle();
      harness.manifestOverride.addAll({
        'server_trickle_candidates_supported': true,
        'server_trickle_protocol_version': 1,
      });
      harness.serverTrickleSession = true;
      harness.client = harness.makeClient(enableP8P: true);
      harness.pieceDelay = const Duration(milliseconds: 200);
      final gate = Completer<void>();
      harness.seedGate = gate.future;
      final download = harness.downloadPrefix();
      await harness.waitForPath('server-offer');
      final offer = harness.body('server-offer')['offer_id'];
      harness.seedCandidates.addAll([
        {
          'sequence': 1,
          'offer_id': offer,
          'candidate': {
            'candidate': 'candidate:late 1 udp 1 192.0.2.25 5000 typ srflx',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          },
        },
        {'sequence': 2, 'offer_id': offer, 'candidate': null},
      ]);
      try {
        for (
          var n = 0;
          n < 100 &&
              !harness.requests.any(
                (r) => r.uri.queryParameters['server_candidate_ack'] == '2',
              );
          n++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(harness.body('session')['server_trickle_supported'], true);
        expect(
          harness.requests.any(
            (r) => r.uri.queryParameters['server_candidate_ack'] == '2',
          ),
          true,
        );
        expect(harness.peers.single.addedCandidates, isEmpty);
      } finally {
        gate.complete();
      }
      expect(await download, harness.bytes.length);
      expect(harness.peers.single.candidateBeforeDescription, false);
      expect(harness.peers.single.addedCandidates, hasLength(1));
      expect(harness.part.readAsBytesSync(), harness.bytes);
    },
  );

  test(
    'seed trickle ignores an unsupported manifest protocol version',
    () async {
      harness.enableTrickle();
      harness.manifestOverride.addAll({
        'server_trickle_candidates_supported': true,
        'server_trickle_protocol_version': 2,
      });
      harness.serverTrickleSession = true;
      harness.client = harness.makeClient(enableP8P: true);
      expect(await harness.downloadPrefix(), harness.bytes.length);
      expect(
        harness.body('session').containsKey('server_trickle_supported'),
        false,
      );
      expect(
        harness.requests.any(
          (r) => r.uri.queryParameters.containsKey('include_server_candidates'),
        ),
        false,
      );
      expect(harness.part.readAsBytesSync(), harness.bytes);
    },
  );

  test(
    'seed trickle stays disabled when the session refuses capability',
    () async {
      harness.enableTrickle();
      harness.manifestOverride.addAll({
        'server_trickle_candidates_supported': true,
        'server_trickle_protocol_version': 1,
      });
      harness.client = harness.makeClient(enableP8P: true);
      expect(await harness.downloadPrefix(), harness.bytes.length);
      expect(harness.body('session')['server_trickle_supported'], true);
      expect(
        harness.requests.any(
          (r) => r.uri.queryParameters.containsKey('include_server_candidates'),
        ),
        false,
      );
      expect(harness.part.readAsBytesSync(), harness.bytes);
    },
  );

  for (final userPeer in [false, true]) {
    test(
      'candidate replay recovers one lost ${userPeer ? 'peer' : 'seed'} ACK without reordering',
      () async {
        harness.enableTrickle();
        harness.manifestOverride['candidate_batch_supported'] = true;
        harness.advertisePeer = userPeer;
        harness.pieceDelay = const Duration(milliseconds: 200);
        harness.localIceCandidates = [
          RTCIceCandidate(
            'candidate:1 1 udp 1 192.168.1.99 1234 typ host',
            '0',
            0,
          ),
        ];
        final endpoint = userPeer ? 'candidate' : 'server-candidate';
        final attempts = <String>[];
        harness.dio.interceptors.insert(
          0,
          InterceptorsWrapper(
            onRequest: (request, handler) {
              if (request.uri.pathSegments.last == endpoint) {
                attempts.add(jsonEncode(request.data));
                if (attempts.length == 1) {
                  handler.reject(
                    DioException(
                      requestOptions: request,
                      type: DioExceptionType.receiveTimeout,
                    ),
                  );
                  return;
                }
              }
              handler.next(request);
            },
          ),
        );
        expect(await harness.downloadPrefix(), harness.bytes.length);
        await _settle();
        expect(attempts, hasLength(3));
        expect(attempts[0], attempts[1]);
        expect((jsonDecode(attempts.last) as Map)['candidates'], [null]);
        expect(
          harness.paths.where(
            (p) => p == (userPeer ? 'signal' : 'server-offer'),
          ),
          hasLength(1),
        );
        expect(harness.part.readAsBytesSync(), harness.bytes);
      },
    );
  }

  for (final variant in ['bounded', 'legacy', 'semantic', 'cancelled']) {
    test('candidate replay respects $variant failure boundary', () async {
      harness.enableTrickle();
      harness.manifestOverride['candidate_batch_supported'] =
          variant != 'legacy';
      harness.pieceDelay = const Duration(milliseconds: 200);
      harness.localIceCandidates = [
        RTCIceCandidate(
          'candidate:1 1 udp 1 192.168.1.99 1234 typ host',
          '0',
          0,
        ),
      ];
      var attempts = 0;
      harness.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.uri.pathSegments.last == 'server-candidate') {
              attempts++;
              if (variant == 'semantic') {
                handler.resolve(
                  Response(
                    requestOptions: request,
                    statusCode: 400,
                    data: {'error': 'invalid_candidate'},
                  ),
                );
              } else {
                if (variant == 'cancelled') harness.client.cancelDownload();
                handler.reject(
                  DioException(
                    requestOptions: request,
                    type: DioExceptionType.connectionError,
                  ),
                );
              }
              return;
            }
            handler.next(request);
          },
        ),
      );
      if (variant == 'cancelled') {
        await expectLater(
          harness.downloadPrefix(),
          throwsA(isA<DioException>()),
        );
      } else {
        expect(await harness.downloadPrefix(), harness.bytes.length);
      }
      await _settle();
      expect(attempts, variant == 'bounded' ? 2 : 1);
      expect(
        harness.paths.where((p) => p == 'server-offer').length,
        lessThanOrEqualTo(1),
      );
      expect(
        harness.body('outcome')['diagnostics']['candidate_error_count'],
        0,
      );
    });
  }

  test('candidate replay binds pending request to closed peer owner', () async {
    harness.enableTrickle();
    harness.manifestOverride['candidate_batch_supported'] = true;
    harness.advertisePeer = true;
    harness.pieceDelay = const Duration(milliseconds: 200);
    harness.localIceCandidates = [
      RTCIceCandidate('candidate:1 1 udp 1 192.168.1.99 1234 typ host', '0', 0),
    ];
    final posted = Completer<RequestOptions>();
    final gate = Completer<void>();
    var attempts = 0;
    harness.dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          if (request.uri.pathSegments.last == 'candidate') {
            attempts++;
            if (!posted.isCompleted) posted.complete(request);
            await gate.future;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 202,
                data: {'ok': true},
              ),
            );
            return;
          }
          handler.next(request);
        },
      ),
    );
    final download = harness.downloadPrefix();
    unawaited(download.then<void>((_) {}, onError: (Object _) {}));
    try {
      final request = await posted.future.timeout(const Duration(seconds: 2));
      final peer = harness.peers.first;
      peer.onIceConnectionState?.call(
        RTCIceConnectionState.RTCIceConnectionStateFailed,
      );
      await _waitUntil(() => peer.closed);
      expect(request.cancelToken!.isCancelled, true);
      gate.complete();
      expect(await download, harness.bytes.length);
      await _settle();
      expect(attempts, 1);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await download.then<void>((_) {}, onError: (Object _) {});
    }
  });

  test(
    'Trickle shared deadline falls back once and ignores late answer',
    () async {
      harness.enableTrickle(budgetMs: 100);
      final gate = Completer<void>();
      harness.seedGate = gate.future;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(seconds: 2),
      );
      expect(await harness.downloadPrefix(), 0);
      gate.complete();
      await _settle();
      expect(harness.body('outcome')['reason_code'], 'p2p_budget_exhausted');
      expect(harness.paths.where((p) => p == 'outcome').length, 1);
      expect(harness.paths.where((p) => p == 'leave').length, 1);
      expect(harness.peers.every((p) => p.closed), true);
      expect(harness.part.existsSync() ? await harness.part.length() : 0, 0);
    },
  );

  test(
    'Trickle owner deadline wins delayed task timers and freezes late answer',
    () async {
      var ownerTimers = 0, delayedTimers = 0;
      var ownerFired = false;
      await runZoned(
        () async {
          harness.enableTrickle(budgetMs: 100);
          final reply = Completer<void>();
          harness.seedGate = reply.future;
          harness.client = harness.makeClient(
            sourceTimeout: const Duration(seconds: 2),
          );
          expect(await harness.downloadPrefix(), 0);
          expect(ownerTimers, 1);
          expect(ownerFired, true);
          expect(delayedTimers, greaterThan(0));
          await _settle();
          expect(
            harness.body('outcome')['reason_code'],
            'p2p_budget_exhausted',
          );
          final accepted = jsonEncode(harness.body('outcome'));
          reply.complete();
          await _settle();
          expect(jsonEncode(harness.body('outcome')), accepted);
          expect(
            harness.paths.where((path) => path == 'outcome'),
            hasLength(1),
          );
          expect(harness.paths.where((path) => path == 'leave'), hasLength(1));
          expect(
            harness.peers.every((peer) => peer.closed && !peer.remoteSet),
            true,
          );
          expect(
            harness.part.existsSync() ? await harness.part.length() : 0,
            0,
          );
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            // A deadline callback now starts bounded native teardown. Its
            // timeout timers inherit _armPeerDeadline farther up the stack;
            // classify by the allocating SDK frame, not any ancestor frame.
            final allocation = StackTrace.current
                .toString()
                .split('\n')
                .firstWhere(
                  (line) => line.contains('app_upgrade_v40_p2p_client.dart'),
                  orElse: () => '',
                );
            if (allocation.contains('_armPeerDeadline') &&
                !allocation.contains('<anonymous closure>')) {
              ownerTimers++;
              return parent.createTimer(zone, duration, () {
                ownerFired = true;
                callback();
              });
            }
            // Keep task dispatch intact. Delay sibling timeout delivery while
            // the peer retains its actual remaining deadline; its callback must
            // win this injected ordering before any HTTP reply is released.
            if (duration > Duration.zero &&
                duration <= const Duration(milliseconds: 100)) {
              delayedTimers++;
              return parent.createTimer(
                zone,
                duration + const Duration(milliseconds: 300),
                callback,
              );
            }
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
    },
  );

  for (final iceFailure in [true, false]) {
    test(
      'pending seed request preserves ${iceFailure ? 'ICE failure' : 'channel closure'} ownership reason',
      () async {
        harness.enableTrickle();
        final reply = Completer<void>();
        harness.seedGate = reply.future;
        final download = harness.downloadPrefix();
        await harness.waitForPath('server-offer');
        expect(harness.peers, hasLength(1));
        final peer = harness.peers.single;
        if (iceFailure) {
          peer.onIceConnectionState?.call(
            RTCIceConnectionState.RTCIceConnectionStateFailed,
          );
        } else {
          await peer.channel.close();
        }
        // A late HTTP implementation need not acknowledge token cancellation.
        // The owner's cancellation must settle the download without its reply.
        expect(await download.timeout(const Duration(seconds: 2)), 0);
        await _settle();
        expect(
          harness.body('outcome')['reason_code'],
          iceFailure ? 'ice_failed' : 'channel_closed',
        );
        final signalsBeforeReply = harness.paths
            .where((path) => path == 'server-candidate')
            .length;
        final acceptedOutcome = jsonEncode(harness.body('outcome'));
        reply.complete();
        await _settle();
        expect(jsonEncode(harness.body('outcome')), acceptedOutcome);
        expect(harness.paths.where((path) => path == 'outcome'), hasLength(1));
        expect(harness.paths.where((path) => path == 'leave'), hasLength(1));
        expect(
          harness.paths.where((path) => path == 'server-candidate'),
          hasLength(signalsBeforeReply),
        );
        expect(peer.remoteSet, false);
        expect(peer.closed, true);
        expect(harness.part.existsSync() ? await harness.part.length() : 0, 0);
      },
    );
  }

  test(
    'unsupported Trickle version retains complete SDP negotiation',
    () async {
      harness.enableTrickle();
      harness.manifestOverride['trickle_ice_protocol_version'] = 2;
      harness.iceDelay = const Duration(milliseconds: 30);
      expect(await harness.downloadPrefix(), harness.bytes.length);
      expect(harness.body('server-offer')['sdp'], contains('a=candidate:'));
      expect(harness.body('server-offer').containsKey('offer_id'), false);
      expect(harness.paths, isNot(contains('server-candidate')));
    },
  );

  test(
    'Trickle provider sends an answer without waiting for gathering',
    () async {
      harness.enableTrickle();
      await harness.part.writeAsBytes(harness.bytes);
      harness.client = harness.makeClient(
        sharingDuration: const Duration(seconds: 2),
      );
      expect(await harness.downloadPrefix(), harness.bytes.length);
      harness.iceNeverCompletes = true;
      harness.incomingOffer = true;
      await harness.client.shareVerifiedFile(harness.part, _url);
      await harness.waitForPath('signal');
      expect(harness.body('signal')['type'], 'answer');
      expect(harness.peers.single.gatherComplete, false);
    },
  );

  test(
    'Trickle cancellation stops candidate posts and releases one session',
    () async {
      harness.enableTrickle();
      harness.iceNeverCompletes = true;
      final gate = Completer<void>();
      harness.seedGate = gate.future;
      final token = CancelToken();
      final download = harness.downloadPrefix(cancelToken: token);
      await harness.waitForPath('server-offer');
      token.cancel();
      await expectLater(download, throwsA(isA<DioException>()));
      gate.complete();
      harness.peers.single.onIceCandidate?.call(
        RTCIceCandidate(
          'candidate:1 1 udp 1 192.168.1.99 1234 typ host',
          '0',
          0,
        ),
      );
      await _settle();
      expect(harness.paths, isNot(contains('server-candidate')));
      expect(harness.paths.where((p) => p == 'outcome').length, 1);
      expect(harness.body('outcome')['outcome'], 'client_interrupted');
      expect(harness.peers.single.closed, true);
    },
  );

  test(
    'optional diagnostics rejection retries the terminal result without it',
    () async {
      harness.rejectDiagnostics = true;
      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _settle();
      expect(harness.paths.where((p) => p == 'outcome').length, 2);
      expect(harness.body('outcome').containsKey('diagnostics'), false);
      expect(harness.body('outcome')['outcome'], 'p2p_complete');
      expect(harness.paths.where((p) => p == 'leave').length, 1);
    },
  );

  test(
    'legacy user peer receives complete SDP without candidate posts',
    () async {
      harness.enableTrickle();
      harness.advertisePeer = true;
      harness.legacyPeer = true;
      harness.iceDelay = const Duration(milliseconds: 40);
      expect(await harness.downloadPrefix(), harness.bytes.length);
      expect(harness.body('signal')['sdp'], contains('a=candidate:'));
      expect(harness.body('signal').containsKey('trickle_ice'), false);
      expect(harness.paths, isNot(contains('candidate')));
    },
  );

  // These cases deliberately stall different startup stages. They protect the
  // shared deadline, rather than checking only the server-offer timeout.
  for (final stage in ['session', 'peers']) {
    test('$stage delay consumes the original startup budget', () async {
      harness.enableTrickle(budgetMs: 100);
      final gate = Completer<void>();
      if (stage == 'session') {
        harness.sessionGate = gate.future;
      } else {
        harness.peersGate = gate.future;
      }
      final watch = Stopwatch()..start();
      expect(await harness.downloadPrefix(), 0);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      gate.complete();
      await _settle();
      expect(harness.paths, isNot(contains('server-offer')));
      if (stage == 'session') {
        // The cancelled HTTP Future has never delivered credentials. Do not
        // invent an authenticated outcome or retry a second session to send it.
        expect(harness.paths.where((p) => p == 'session').length, 1);
        expect(harness.paths, isNot(contains('outcome')));
        expect(
          harness.logs.any((log) => log.code == 'p2p_budget_exhausted'),
          isTrue,
        );
      } else {
        expect(harness.paths.where((p) => p == 'outcome').length, 1);
        expect(harness.body('outcome')['reason_code'], 'p2p_budget_exhausted');
      }
    });
  }

  test('open channel without first piece cannot extend startup', () async {
    harness.enableTrickle(budgetMs: 100);
    harness.dropIndex = 0;
    final watch = Stopwatch()..start();
    expect(await harness.downloadPrefix(), 0);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    await _settle();
    expect(harness.body('outcome')['reason_code'], 'p2p_budget_exhausted');
    expect(harness.peers.every((p) => p.closed), isTrue);
  });

  test('complete SDP also obeys manifest startup and gather limits', () async {
    harness.manifestOverride.addAll({
      'p2p_connect_timeout_ms': 200,
      'p2p_ice_gather_timeout_ms': 50,
    });
    harness.iceNeverCompletes = true;
    final watch = Stopwatch()..start();
    expect(await harness.downloadPrefix(), 0);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(harness.paths, isNot(contains('server-offer')));
  });

  test(
    'peer provenance is saved before the first piece reaches disk',
    () async {
      var callbacks = 0;
      expect(
        await harness.client.downloadVerifiedPrefix(
          downloadUrl: _url,
          expectedSlug: 'lifering',
          expectedVersion: 'test',
          expectedFileSize: harness.bytes.length,
          expectedSha256: harness.info.sha256,
          partFile: harness.part,
          onProgress: (_, _) {},
          beforeP2PWrite: () async {
            final length = await harness.part.exists()
                ? await harness.part.length()
                : 0;
            expect(length, callbacks * AppUpgradeP2PManifest.chunkSize);
            callbacks++;
          },
        ),
        harness.bytes.length,
      );
      expect(callbacks, 2);
    },
  );

  test('user peer is preferred and only verified peer bytes count', () async {
    harness.advertisePeer = true;
    expect(await harness.downloadPrefix(), harness.bytes.length);
    await _settle();
    expect(harness.paths, isNot(contains('server-offer')));
    expect(harness.body('outcome')['peer_bytes'], harness.bytes.length);
    expect(
      harness.logs.firstWhere((event) => event.stage == 'result').seedBytes,
      0,
    );
    expect(harness.body('session')['share_enabled'], true);
    for (final request in harness.requests.where(
      (value) => !['manifest', 'session'].contains(value.uri.pathSegments.last),
    )) {
      expect(
        request.headers['Authorization'],
        'Bearer $_self.secret_not_logged',
      );
    }
  });

  test('failed user peer is deduplicated, then tries the seed', () async {
    harness.advertisePeer = true;
    harness.rejectSignal = true;
    expect(await harness.downloadPrefix(), harness.bytes.length);
    await _settle();
    expect(harness.paths.where((path) => path == 'signal').length, 1);
    expect(harness.paths.where((path) => path == 'peers').length, 2);
    expect(harness.paths, contains('server-offer'));
    expect(harness.body('outcome')['peer_bytes'], 0);
  });

  test(
    'batch timeout after a verified prefix resumes HTTPS at the exact offset',
    () async {
      harness.bytes = Uint8List.fromList(
        List.generate(
          AppUpgradeP2PManifest.chunkSize * 5 + 79,
          (index) => index % 251,
        ),
      );
      harness.dropIndex = 2;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(milliseconds: 500),
      );
      final https = Dio();
      final telemetry = Dio();
      final reportedEvents = <RequestOptions>[];
      telemetry.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            reportedEvents.add(request);
            handler.resolve(Response(requestOptions: request, statusCode: 201));
          },
        ),
      );
      final serviceEvents = AppUpgradeServiceEvents(dio: telemetry);
      RequestOptions? rangeRequest;
      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            rangeRequest = request;
            final offset = AppUpgradeP2PManifest.chunkSize;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 206,
                headers: Headers.fromMap({
                  'content-range': [
                    'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                  ],
                  'etag': ['"release-test"'],
                  'x-download-session-id': ['0123456789abcdef'],
                }),
                data: ResponseBody.fromBytes(
                  harness.bytes.sublist(offset),
                  206,
                  headers: {
                    'content-range': [
                      'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                    ],
                    'etag': ['"release-test"'],
                    'x-download-session-id': ['0123456789abcdef'],
                  },
                ),
              ),
            );
          },
        ),
      );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        serviceEvents: serviceEvents,
        supportDirectoryLoader: () async => directory,
      );
      final file = await downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: null,
        refreshRelease: () async => harness.info,
        onProgress: (_, _) {},
      );
      expect(
        rangeRequest?.headers['range'],
        'bytes=${AppUpgradeP2PManifest.chunkSize}-',
      );
      expect(rangeRequest?.headers['if-range'], '"release-test"');
      expect(await file.readAsBytes(), harness.bytes);
      expect(harness.client.lastDownloadUsedP2P, isTrue);
      await downloader.rememberVerifiedInstallation(harness.info);
      await serviceEvents.reconcileInstalledBuild(harness.info.versionCode);
      await serviceEvents.flush();
      expect(
        reportedEvents,
        isEmpty,
        reason: 'HTTP coverage cannot attest to the P2P-supplied prefix',
      );
      await _settle();
      expect(harness.body('outcome')['outcome'], 'https_fallback');
      expect(harness.body('outcome')['verified'], false);
      expect(
        harness.logs.any(
          (event) => event.code == 'server_seed_transfer_timeout',
        ),
        isTrue,
      );
    },
  );

  test(
    'Trickle transfer timeout resumes HTTPS at the exact verified offset',
    () async {
      harness.enableTrickle();
      harness.dropIndex = 1;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(milliseconds: 500),
      );
      final https = Dio();
      RequestOptions? rangeRequest;
      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            rangeRequest = request;
            final offset = AppUpgradeP2PManifest.chunkSize;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 206,
                headers: Headers.fromMap({
                  'content-range': [
                    'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                  ],
                  'etag': ['"release-test"'],
                  'x-download-session-id': ['https-session'],
                }),
                data: ResponseBody.fromBytes(
                  harness.bytes.sublist(offset),
                  206,
                  headers: {
                    'content-range': [
                      'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                    ],
                    'etag': ['"release-test"'],
                    'x-download-session-id': ['https-session'],
                  },
                ),
              ),
            );
          },
        ),
      );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        supportDirectoryLoader: () async => directory,
      );
      final file = await downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: null,
        refreshRelease: () async => harness.info,
        onProgress: (_, _) {},
      );
      expect(
        rangeRequest?.headers['range'],
        'bytes=${AppUpgradeP2PManifest.chunkSize}-',
      );
      expect(rangeRequest?.headers['if-range'], '"release-test"');
      expect(await file.readAsBytes(), harness.bytes);
      await _settle();
      expect(harness.body('outcome')['outcome'], 'https_fallback');
      expect(harness.body('outcome')['verified'], false);
      expect(
        harness.logs.any(
          (event) => event.code == 'server_seed_transfer_timeout',
        ),
        isTrue,
      );
    },
  );

  test(
    'active download duration is checkpointed before a process can exit',
    () async {
      harness.manifestOverride = {'status': 'disabled'};
      final body = StreamController<Uint8List>();
      final https = Dio();
      final telemetry = Dio();
      final reportedEvents = <RequestOptions>[];
      telemetry.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            reportedEvents.add(request);
            handler.resolve(Response(requestOptions: request, statusCode: 201));
          },
        ),
      );
      final serviceEvents = AppUpgradeServiceEvents(dio: telemetry);
      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                headers: Headers.fromMap({
                  'etag': ['"release-test"'],
                }),
                data: ResponseBody(
                  body.stream,
                  200,
                  headers: {
                    'etag': [harness.info.downloadEtag],
                    'x-download-session-id': ['0123456789abcdef'],
                  },
                ),
              ),
            );
          },
        ),
      );
      final token = CancelToken();
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        supportDirectoryLoader: () async => directory,
        serviceEvents: serviceEvents,
      );
      final download = downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: null,
        refreshRelease: () async => harness.info,
        onProgress: (_, _) {},
        cancelToken: token,
      );
      final cancelled = expectLater(download, throwsA(isA<DioException>()));
      body.add(Uint8List.fromList(harness.bytes.sublist(0, 10)));
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(
          'app_upgrade.v40.task.${harness.info.releaseId}.active_ms',
        ),
        greaterThanOrEqualTo(4000),
      );
      token.cancel('test cancellation');
      await body.close();
      await cancelled;
      for (var attempt = 0; reportedEvents.isEmpty && attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await serviceEvents.flush();
      }
      await serviceEvents.flush();
      final event = reportedEvents.single.data as Map;
      expect(event['event_type'], 'user_cancelled');
      expect(event['persisted_bytes'], 10);
      expect(event['download_duration_ms'], greaterThanOrEqualTo(4000));
    },
  );

  test('Trickle seed negotiation timeout downloads full APK over HTTPS', () async {
    harness.enableTrickle(budgetMs: 100);
    harness.seedGate = Completer<void>().future;
    harness.client = harness.makeClient(
      sourceTimeout: const Duration(milliseconds: 500),
    );
    final https = Dio();
    RequestOptions? rangeRequest;
    https.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          rangeRequest = request;
          final offset = 0;
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              headers: Headers.fromMap({
                'content-range': [
                  'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                ],
                'etag': ['"release-test"'],
                'x-download-session-id': ['https-session'],
              }),
              data: ResponseBody.fromBytes(
                harness.bytes.sublist(offset),
                200,
                headers: {
                  'content-range': [
                    'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                  ],
                  'etag': ['"release-test"'],
                  'x-download-session-id': ['https-session'],
                },
              ),
            ),
          );
        },
      ),
    );
    final downloader = AppUpgradeV40DownloadClient(
      dio: https,
      p2pClient: harness.client,
      supportDirectoryLoader: () async => directory,
    );
    final file = await downloader.download(
      info: harness.info,
      url: _url,
      backupUrl: null,
      refreshRelease: () async => harness.info,
      onProgress: (_, _) {},
    );
    expect(rangeRequest?.headers['range'], isNull);
    expect(rangeRequest?.headers['if-range'], isNull);
    expect(await file.readAsBytes(), harness.bytes);
    await _settle();
    expect(harness.body('outcome')['outcome'], 'https_fallback');
    expect(harness.body('outcome')['verified'], false);
    expect(
      harness.logs.any((event) => event.code == 'p2p_budget_exhausted'),
      isTrue,
    );
  });

  test(
    'HTTPS fallback follows explicit COS redirect without leaking service headers',
    () async {
      harness.enableTrickle(budgetMs: 100);
      harness.seedGate = Completer<void>().future;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(milliseconds: 500),
      );
      final https = Dio();
      RequestOptions? rangeRequest;
      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            rangeRequest = request;
            if (request.uri.host == 'download.csnas.asia') {
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': [
                      'https://cos.example.com/apk.apk?signature=test',
                    ],
                  }),
                  data: ResponseBody.fromBytes(
                    [],
                    302,
                    headers: {
                      'location': [
                        'https://cos.example.com/apk.apk?signature=test',
                      ],
                    },
                  ),
                ),
              );
              return;
            }
            final offset = 0;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                headers: Headers.fromMap({
                  'content-range': [
                    'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                  ],
                  'etag': ['"release-test"'],
                  'x-download-session-id': ['https-session'],
                }),
                data: ResponseBody.fromBytes(
                  harness.bytes.sublist(offset),
                  200,
                  headers: {
                    'content-range': [
                      'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                    ],
                    'etag': ['"release-test"'],
                    'x-download-session-id': ['https-session'],
                  },
                ),
              ),
            );
          },
        ),
      );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        supportDirectoryLoader: () async => directory,
      );
      final file = await downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: null,
        refreshRelease: () async => harness.info,
        onProgress: (_, _) {},
      );
      expect(rangeRequest?.uri.host, 'cos.example.com');
      expect(rangeRequest?.headers.containsKey('X-Device-Id'), false);
      expect(rangeRequest?.headers.containsKey('X-Download-Session-Id'), false);
      expect(rangeRequest?.headers['range'], isNull);
      expect(rangeRequest?.headers['if-range'], isNull);
      expect(await file.readAsBytes(), harness.bytes);
      await _settle();
      expect(harness.body('outcome')['outcome'], 'https_fallback');
      expect(harness.body('outcome')['verified'], false);
      expect(
        harness.logs.any((event) => event.code == 'p2p_budget_exhausted'),
        isTrue,
      );
    },
  );

  test(
    'COS interrupted transfer resumes with its own ETag and no service identity',
    () async {
      harness.manifestOverride['auto_start'] = false;
      final https = Dio();
      var serviceCalls = 0, cosCalls = 0;
      const prefix = 4096;
      var laterRun = false;
      Stream<Uint8List> interrupted(int start) async* {
        yield Uint8List.sublistView(harness.bytes, start, start + prefix);
        throw const HttpException('simulated transport interruption');
      }

      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.uri.host == 'download.csnas.asia') {
              serviceCalls++;
              if (laterRun) {
                expect(request.headers['range'], 'bytes=${prefix * 2}-');
                expect(request.headers['if-range'], '"release-test"');
              }
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 302,
                  data: ResponseBody.fromBytes(
                    [],
                    302,
                    headers: {
                      'location': [
                        'https://cos.example.com/apk.apk?signature=test',
                      ],
                    },
                  ),
                ),
              );
              return;
            }
            cosCalls++;
            final offset = cosCalls == 1
                ? 0
                : cosCalls == 2
                ? prefix
                : prefix * 2;
            final status = offset == 0 ? 200 : 206;
            if (offset > 0) {
              expect(request.headers['range'], 'bytes=$offset-');
              expect(request.headers['if-range'], '"cos-etag"');
            } else {
              expect(request.headers['if-range'], isNull);
            }
            expect(request.headers.containsKey('X-Device-Id'), false);
            expect(request.headers.containsKey('X-Download-Session-Id'), false);
            final headers = <String, List<String>>{
              'etag': ['"cos-etag"'],
              'x-download-session-id': ['foreign-session'],
              if (status == 206)
                'content-range': [
                  'bytes $offset-${harness.bytes.length - 1}/${harness.bytes.length}',
                ],
            };
            final body = laterRun
                ? ResponseBody.fromBytes(
                    harness.bytes.sublist(offset),
                    status,
                    headers: headers,
                  )
                : ResponseBody(interrupted(offset), status, headers: headers);
            handler.resolve(
              Response(requestOptions: request, statusCode: status, data: body),
            );
          },
        ),
      );
      AppUpgradeV40DownloadClient makeDownloader() =>
          AppUpgradeV40DownloadClient(
            dio: https,
            p2pClient: harness.client,
            supportDirectoryLoader: () async => directory,
          );
      Future<File> download(AppUpgradeV40DownloadClient client) =>
          client.download(
            info: harness.info,
            url: _url,
            backupUrl: null,
            refreshRelease: () async => harness.info,
            onProgress: (_, _) {},
          );
      await expectLater(
        download(makeDownloader()),
        throwsA(isA<HttpException>()),
      );
      laterRun = true;
      final file = await download(makeDownloader());
      expect(await file.readAsBytes(), harness.bytes);
      expect(serviceCalls, 2);
      expect(cosCalls, 3);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(
          'app_upgrade.v40.task.${harness.info.releaseId}.active_ms',
        ),
        isNull,
      );
    },
  );

  test(
    'oversized APK response is stopped before writing beyond release size',
    () async {
      harness.manifestOverride['auto_start'] = false;
      final https = Dio();
      var requests = 0;
      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests++;
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: ResponseBody.fromBytes(
                  [...harness.bytes, 1],
                  200,
                  headers: {
                    'etag': ['"release-test"'],
                  },
                ),
              ),
            );
          },
        ),
      );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        supportDirectoryLoader: () async => directory,
      );
      await expectLater(
        downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async => harness.info,
          onProgress: (_, _) {},
        ),
        throwsA(isA<HttpException>()),
      );
      expect(requests, 3);
      final parts = Directory(
        '${directory.path}/app-upgrades',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.part'));
      expect(parts, isNotEmpty);
      expect(parts.every((f) => f.lengthSync() <= harness.bytes.length), true);
    },
  );

  test('unfinished redirect body cannot block HTTPS fallback', () async {
    harness.manifestOverride['auto_start'] = false;
    final https = Dio();
    final slowBody = StreamController<Uint8List>();
    var cancelled = false;
    slowBody.onCancel = () {
      cancelled = true;
    };
    https.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.uri.host == 'download.csnas.asia') {
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 302,
                data: ResponseBody(
                  slowBody.stream,
                  302,
                  headers: {
                    'location': ['https://cos.example.com/apk.apk'],
                  },
                ),
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: ResponseBody.fromBytes(
                  harness.bytes,
                  200,
                  headers: {
                    'etag': ['"cos-etag"'],
                  },
                ),
              ),
            );
          }
        },
      ),
    );
    final downloader = AppUpgradeV40DownloadClient(
      dio: https,
      p2pClient: harness.client,
      supportDirectoryLoader: () async => directory,
    );
    try {
      final file = await downloader
          .download(
            info: harness.info,
            url: _url,
            backupUrl: null,
            refreshRelease: () async => harness.info,
            onProgress: (_, _) {},
          )
          .timeout(const Duration(seconds: 2));
      expect(await file.readAsBytes(), harness.bytes);
      expect(cancelled, true);
    } finally {
      await slowBody.close();
    }
  });

  test('health build is independent of the business offer threshold', () async {
    harness.artifactBuild = 8903;
    harness.manifestOverride['android_version_code'] = 8903;
    final downloader = AppUpgradeV40DownloadClient(
      dio: Dio(),
      p2pClient: harness.client,
      supportDirectoryLoader: () async => directory,
    );
    final file = await downloader.download(
      info: harness.info,
      url: _url,
      backupUrl: null,
      refreshRelease: () async => harness.info,
      onProgress: (_, _) {},
    );
    expect(harness.info.versionCode, 8900);
    expect(harness.paths, contains('session'));
    expect(await file.readAsBytes(), harness.bytes);
    expect(harness.body('leave'), isEmpty);
  });

  test('health and manifest build mismatch never starts P2P', () async {
    harness.artifactBuild = 8900;
    harness.manifestOverride['android_version_code'] = 8901;
    final downloader = AppUpgradeV40DownloadClient(
      dio: Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: ResponseBody.fromBytes(
                    harness.bytes,
                    200,
                    headers: {
                      'etag': ['"release-test"'],
                    },
                  ),
                ),
              );
            },
          ),
        ),
      p2pClient: harness.client,
      supportDirectoryLoader: () async => directory,
    );
    final file = await downloader.download(
      info: harness.info,
      url: _url,
      backupUrl: null,
      refreshRelease: () async => harness.info,
      onProgress: (_, _) {},
    );
    expect(await file.readAsBytes(), harness.bytes);
    expect(harness.paths, isNot(contains('session')));
    expect(harness.logs.any((e) => e.code == 'manifest_build_mismatch'), true);
  });

  test(
    'stale size refreshes same-build metadata once before retrying P2P',
    () async {
      harness.manifestOverride['android_version_code'] = 8900;
      final stale = AppUpgradeInfo.fromJson({
        'releaseId': harness.info.releaseId,
        'versionName': 'test',
        'versionCode': 8900,
        'fileSize': harness.bytes.length - 1,
        'sha256': harness.info.sha256,
        'downloadUrl': _url,
        'downloadProtocol': 'APK_SERVICE_V40',
        'downloadSlug': 'lifering',
      });
      var refreshed = 0;
      final downloader = AppUpgradeV40DownloadClient(
        dio: Dio(),
        p2pClient: harness.client,
        supportDirectoryLoader: () async => directory,
      );
      final file = await downloader.download(
        info: stale,
        url: _url,
        backupUrl: null,
        refreshRelease: () async {
          refreshed++;
          return harness.info;
        },
        onProgress: (_, _) {},
      );
      expect(await file.readAsBytes(), harness.bytes);
      expect(refreshed, 1);
      // Installation is freshly reauthorized and health-checked by the
      // coordinator; the donor's in-memory metadata shortcut is not adopted.
      expect(harness.paths.where((p) => p == 'manifest').length, 2);
      expect(harness.paths.where((p) => p == 'session').length, 1);
    },
  );

  test(
    'fresh health may change version name without changing business selection',
    () async {
      harness.manifestOverride['version'] = 'current-health-version';
      var refreshes = 0;
      final downloader = AppUpgradeV40DownloadClient(
        dio: Dio(),
        p2pClient: harness.client,
        supportDirectoryLoader: () async => directory,
      );
      final file = await downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: null,
        refreshRelease: () async {
          refreshes++;
          return AppUpgradeInfo.fromJson({
            'releaseId': harness.info.releaseId,
            'versionCode': harness.info.versionCode,
            'versionName': 'current-health-version',
            'fileSize': harness.bytes.length,
            'sha256': harness.info.sha256,
            'downloadUrl': _url,
            'downloadProtocol': 'APK_SERVICE_V40',
            'downloadSlug': 'lifering',
          });
        },
        onProgress: (_, _) {},
      );
      expect(refreshes, 1);
      expect(await file.readAsBytes(), harness.bytes);
      expect(harness.paths.where((p) => p == 'session').length, 1);
      expect(harness.paths.where((p) => p == 'manifest').length, 2);
    },
  );

  test(
    'rejected HTTP 200 transport is cancelled before requesting backup',
    () async {
      harness.manifestOverride['auto_start'] = false;
      CancelToken? firstToken;
      var requests = 0;
      final userCancel = CancelToken();
      final https = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              requests++;
              if (requests == 1) {
                firstToken = r.cancelToken;
              } else {
                expect(firstToken?.isCancelled, isTrue);
                expect(userCancel.isCancelled, isFalse);
                expect(r.uri.host, 'download1.csnas.asia');
              }
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: ResponseBody.fromBytes(
                    harness.bytes,
                    200,
                    headers: {
                      'etag': [
                        requests == 1 ? '"wrong-etag"' : '"release-test"',
                      ],
                      'x-download-session-id': ['http-session'],
                    },
                  ),
                ),
              );
            },
          ),
        );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        supportDirectoryLoader: () async => directory,
      );
      final result = await downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: 'https://download1.csnas.asia/lifering/download',
        refreshRelease: () async => harness.info,
        onProgress: (_, _) {},
        cancelToken: userCancel,
      );
      expect(await result.readAsBytes(), harness.bytes);
      expect(requests, 2);
      expect(harness.logs.any((e) => e.code == 'https_etag_mismatch'), isTrue);
    },
  );

  for (final reason in ['duplicate_in_flight', 'concurrent_download_limit']) {
    test(
      'temporary $reason preserves HTTPS prefix and resumes after waiting',
      () async {
        harness.manifestOverride['auto_start'] = false;
        final https = Dio();
        var requests = 0;
        final offsets = <Object?>[];
        https.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              requests++;
              offsets.add(request.headers['Range']);
              final status = requests == 1
                  ? 200
                  : requests == 2
                  ? 429
                  : 206;
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: status,
                  data: ResponseBody.fromBytes(
                    requests == 1
                        ? harness.bytes.sublist(0, 20)
                        : requests == 2
                        ? utf8.encode(jsonEncode({'error': reason}))
                        : harness.bytes.sublist(20),
                    status,
                    headers: {
                      'etag': ['"release-test"'],
                      'x-download-session-id': ['http-session'],
                      if (status == 429) 'retry-after': ['1'],
                      if (status == 206)
                        'content-range': [
                          'bytes 20-${harness.bytes.length - 1}/${harness.bytes.length}',
                        ],
                    },
                  ),
                ),
              );
            },
          ),
        );
        final downloader = AppUpgradeV40DownloadClient(
          dio: https,
          p2pClient: harness.client,
          supportDirectoryLoader: () async => directory,
        );
        final file = await downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async => harness.info,
          onProgress: (_, _) {},
        );
        expect(await file.readAsBytes(), harness.bytes);
        expect(requests, 3);
        expect(offsets.skip(1), everyElement('bytes=20-'));
      },
    );
  }

  test(
    'cancelling during temporary 429 wait sends no second request',
    () async {
      harness.manifestOverride['auto_start'] = false;
      final token = CancelToken();
      var requests = 0;
      final https = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              requests++;
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: requests == 1 ? 200 : 429,
                  data: ResponseBody.fromBytes(
                    requests == 1
                        ? harness.bytes.sublist(0, 20)
                        : utf8.encode('{"error":"duplicate_in_flight"}'),
                    requests == 1 ? 200 : 429,
                    headers: {
                      'etag': ['"release-test"'],
                      if (requests == 2) 'retry-after': ['2'],
                    },
                  ),
                ),
              );
              if (requests == 2) {
                Timer(
                  const Duration(milliseconds: 50),
                  () => token.cancel('test'),
                );
              }
            },
          ),
        );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        supportDirectoryLoader: () async => directory,
      );
      await expectLater(
        downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async => harness.info,
          onProgress: (_, _) {},
          cancelToken: token,
        ),
        throwsA(isA<DioException>()),
      );
      expect(requests, 2);
    },
  );

  test('first-request contention does not poll or switch sources', () async {
    harness.manifestOverride['auto_start'] = false;
    var requests = 0;
    final https = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests++;
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 429,
                data: ResponseBody.fromString(
                  '{"error":"duplicate_in_flight"}',
                  429,
                  headers: {
                    'retry-after': ['1'],
                  },
                ),
              ),
            );
          },
        ),
      );
    final downloader = AppUpgradeV40DownloadClient(
      dio: https,
      p2pClient: harness.client,
      supportDirectoryLoader: () async => directory,
    );
    await expectLater(
      downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: null,
        refreshRelease: () async => harness.info,
        onProgress: (_, _) {},
      ),
      throwsA(isA<AppUpgradeV40RateLimitException>()),
    );
    expect(requests, 1);
  });

  for (final firstStatus in [409, 416, 429]) {
    test(
      'HTTPS handles $firstStatus with bounded recovery and final integrity',
      () async {
        harness.manifestOverride['auto_start'] = false;
        final https = Dio();
        var requests = 0, refreshes = 0;
        https.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              requests++;
              final status = requests == 1 ? firstStatus : 200;
              final headers = <String, List<String>>{
                'etag': ['"release-test"'],
                if (status == 429) 'retry-after': ['60'],
              };
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: status,
                  data: ResponseBody.fromBytes(
                    status == 200
                        ? harness.bytes
                        : utf8.encode(
                            jsonEncode({
                              'error': status == 409
                                  ? 'download_session_invalid'
                                  : 'ip_window_limit',
                            }),
                          ),
                    status,
                    headers: headers,
                  ),
                ),
              );
            },
          ),
        );
        final downloader = AppUpgradeV40DownloadClient(
          dio: https,
          p2pClient: harness.client,
          supportDirectoryLoader: () async => directory,
        );
        final task = downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async {
            refreshes++;
            return harness.info;
          },
          onProgress: (_, _) {},
        );
        if (firstStatus == 429) {
          await expectLater(
            task,
            throwsA(isA<AppUpgradeV40RateLimitException>()),
          );
          expect(requests, 1);
        } else {
          final file = await task;
          expect(await file.readAsBytes(), harness.bytes);
          expect(requests, 2);
          expect(refreshes, firstStatus == 409 ? 1 : 0);
        }
      },
    );
  }

  test(
    'corrupt piece is not persisted or advertised as a shareable prefix',
    () async {
      harness.corruptIndex = 1;
      expect(await harness.downloadPrefix(), AppUpgradeP2PManifest.chunkSize);
      expect(await harness.part.length(), AppUpgradeP2PManifest.chunkSize);
      await _settle();
      expect(harness.body('outcome')['verified'], false);
      expect(
        harness.logs.any((event) => event.code == 'piece_checksum_mismatch'),
        isTrue,
      );
    },
  );

  test('disabled service closes P2P immediately rather than polling', () async {
    harness.peersDisabled = true;
    expect(await harness.downloadPrefix(), 0);
    await _settle();
    expect(harness.paths, isNot(contains('server-offer')));
    expect(harness.paths.where((value) => value == 'peers').length, 1);
    expect(harness.body('outcome')['reason_code'], 'p2p_disabled');
  });

  test('COS source never queries manifest, session or WebRTC', () async {
    expect(
      await harness.downloadPrefix(url: 'https://business-cos.example/apk.apk'),
      0,
    );
    expect(harness.requests, isEmpty);
    expect(harness.peers, isEmpty);
    expect(harness.logs.single.code, 'source_not_p2p');
  });

  test(
    'outcome failure never delays HTTPS fallback and still attempts leave',
    () async {
      harness.seedBusy = true;
      final outcome = Completer<void>();
      harness.outcomeGate = outcome.future;
      final timer = Stopwatch()..start();
      expect(await harness.downloadPrefix(), 0);
      expect(timer.elapsed, lessThan(const Duration(seconds: 1)));
      outcome.complete();
      await _settle();
      expect(harness.paths, contains('leave'));
    },
  );

  test('cancel keeps verified prefix and reports client_interrupted', () async {
    final cancel = CancelToken();
    await expectLater(
      harness.downloadPrefix(
        cancelToken: cancel,
        onProgress: (received, _) {
          if (received == AppUpgradeP2PManifest.chunkSize) cancel.cancel();
        },
      ),
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    await _settle();
    expect(await harness.part.length(), AppUpgradeP2PManifest.chunkSize);
    expect(harness.body('outcome')['outcome'], 'client_interrupted');
    expect(harness.body('outcome')['verified'], false);
  });

  test(
    'complete cache verifies the short last piece; partial HTTPS tail is retained',
    () async {
      final store = AppUpgradeP2PPieceStore(
        harness.part,
        harness.parsedManifest(),
      );
      await harness.part.writeAsBytes(harness.bytes);
      expect(await store.verifyPrefix(), harness.bytes.length);
      expect(store.verifiedPieces, {0, 1});
      expect(await store.completeAndVerified(), isTrue);
      await harness.part.writeAsBytes(
        harness.bytes.sublist(0, harness.bytes.length - 1),
      );
      expect(await store.verifyPrefix(), harness.bytes.length - 1);
      expect(store.verifiedPieces, {0});
    },
  );

  test('receiver requires start, exact index/end/length and checksum', () {
    final store = AppUpgradeP2PPieceStore(
      harness.part,
      harness.parsedManifest(),
    );
    expect(
      () => AppUpgradeP2PPieceReceiver(store, 1).add(Uint8List(2)),
      throwsA(isA<AppUpgradeP2PFailure>()),
    );
    final receiver = AppUpgradeP2PPieceReceiver(store, 1);
    receiver.start({'index': 1, 'size': 79});
    receiver.add(
      Uint8List.fromList(
        harness.bytes.sublist(AppUpgradeP2PManifest.chunkSize),
      ),
    );
    expect(
      receiver.end({'index': 1}),
      harness.bytes.sublist(AppUpgradeP2PManifest.chunkSize),
    );
    expect(
      () => receiver.end({'index': 1}),
      throwsA(isA<AppUpgradeP2PFailure>()),
    );
  });

  test(
    'batch parser rejects duplicates, fractions, overflow and invalid indices',
    () {
      final manifest = harness.parsedManifest();
      expect(
        manifest.requestedIndices({
          'type': 'get-pieces',
          'indices': [0, 1],
        }),
        [0, 1],
      );
      for (final indices in [
        [],
        [0, 0],
        [0.5],
        [-1],
        [2],
        [0, 1, 0, 1, 0],
      ]) {
        expect(
          () => manifest.requestedIndices({
            'type': 'get-pieces',
            'indices': indices,
          }),
          throwsA(isA<AppUpgradeP2PFailure>()),
        );
      }
    },
  );

  test(
    'verified cache provides ordered batches and switching to cellular withdraws sharing',
    () async {
      harness.client = harness.makeClient(
        sharingDuration: const Duration(minutes: 3),
      );
      expect(await harness.downloadPrefix(), harness.bytes.length);
      harness.incomingOffer = true;
      await harness.client.shareVerifiedFile(harness.part, _url);
      await _settle();
      final provider = harness.peers.last;
      provider.channel.receiveText({
        'type': 'get-pieces',
        'indices': [0, 1],
      });
      // Wait for the actual second piece, rather than assuming file IO finishes
      // in 100ms on a busy Windows build host.
      for (var i = 0; i < 200; i++) {
        final ended = provider.channel.sent
            .where((message) => !message.isBinary)
            .map((message) => jsonDecode(message.text) as Map)
            .any(
              (message) =>
                  message['type'] == 'piece-end' && message['index'] == 1,
            );
        if (ended) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final controls = provider.channel.sent
          .where((message) => !message.isBinary)
          .map((message) => jsonDecode(message.text) as Map)
          .toList();
      expect(controls.map((message) => message['type']), [
        'piece-start',
        'piece-end',
        'piece-start',
        'piece-end',
      ]);
      expect(controls.map((message) => message['index']), [0, 0, 1, 1]);
      expect(
        provider.channel.sent
            .where((message) => message.isBinary)
            .every((message) => message.binary.length <= 48 * 1024),
        isTrue,
      );
      harness.network = AppUpgradeP2PNetwork.cellular;
      harness.events.add('cellular');
      await _settle();
      expect(provider.closed, isTrue);
      final heartbeat = harness.body('heartbeat');
      expect(heartbeat['network'], 'cellular');
      expect(heartbeat['share_enabled'], false);
      expect(heartbeat['pieces'], isEmpty);
    },
  );

  test(
    'runtime consent revocation closes an existing cache upload immediately',
    () async {
      harness.client = harness.makeClient(
        sharingDuration: const Duration(minutes: 3),
      );
      expect(await harness.downloadPrefix(), harness.bytes.length);
      harness.incomingOffer = true;
      await harness.client.shareVerifiedFile(harness.part, _url);
      await _settle();
      final provider = harness.peers.last;
      expect(provider.closed, false);
      final before = provider.channel.sent.where((m) => m.isBinary).length;
      harness.client.setSharingEnabled(false);
      expect(provider.closed, true);
      provider.channel.receiveText({'type': 'get-piece', 'index': 0});
      await _settle();
      expect(provider.channel.sent.where((m) => m.isBinary).length, before);
      expect(harness.client.allowSharing, false);
      await harness.client.shareVerifiedFile(harness.part, _url);
      expect(harness.peers.last, same(provider));
    },
  );

  Future<_FakeChannel> cacheUploadChannel({Duration? operation}) async {
    harness.client = harness.makeClient(
      sharingDuration: const Duration(minutes: 3),
      sourceTimeout: operation ?? const Duration(seconds: 3),
    );
    expect(await harness.downloadPrefix(), harness.bytes.length);
    harness.incomingOffer = true;
    await harness.client.shareVerifiedFile(harness.part, _url);
    await _settle();
    return harness.peers.last.channel;
  }

  test(
    'native upload backpressure ignores a stale low cached amount',
    () async {
      final channel = await cacheUploadChannel();
      channel.cachedBufferedBytes = 0;
      channel.nativeBufferedBytes = 3 * 1024 * 1024;
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(channel.binaryBytes, 0);
      expect(channel.nativeBufferQueries, greaterThan(0));
      channel.nativeBufferedBytes = 0;
      await _waitUntil(() => channel.pieceEnds == 1);
      expect(channel.binaryBytes, AppUpgradeP2PManifest.chunkSize);
      expect(
        channel.maxNativeBufferedBytes,
        lessThanOrEqualTo(
          2 * 1024 * 1024 + AppUpgradeP2PManifest.maxFrameBytes,
        ),
      );
    },
  );

  test(
    'native upload backpressure ignores a stale high cached amount',
    () async {
      final channel = await cacheUploadChannel();
      channel.cachedBufferedBytes = 500 * 1024;
      channel.nativeBufferedBytes = 0;
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await _waitUntil(() => channel.pieceEnds == 1);
      expect(channel.nativeBufferQueries, greaterThan(0));
      expect(channel.binaryBytes, AppUpgradeP2PManifest.chunkSize);
    },
  );

  test(
    'native upload backpressure bounds a burst without cached events',
    () async {
      final channel = await cacheUploadChannel();
      channel.nativeDrainPerQuery = 16 * 1024;
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await _waitUntil(() => channel.pieceEnds == 1);
      expect(channel.binaryBytes, AppUpgradeP2PManifest.chunkSize);
      expect(
        channel.maxNativeBufferedBytes,
        lessThanOrEqualTo(
          2 * 1024 * 1024 + AppUpgradeP2PManifest.maxFrameBytes,
        ),
      );
      expect(
        channel.nativeBufferQueries,
        greaterThanOrEqualTo(channel.binarySendAttempts),
      );
    },
  );

  test(
    'native upload backpressure retains one fixed three second drain budget',
    () async {
      final channel = await cacheUploadChannel();
      channel.nativeBufferedBytes = 4 * 1024 * 1024;
      final watch = Stopwatch()..start();
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await _waitUntil(() => harness.peers.last.closed, attempts: 400);
      expect(watch.elapsedMilliseconds, inInclusiveRange(2900, 3800));
      expect(channel.binaryBytes, 0);
      expect(
        harness.logs.map((e) => e.toJson()['code']),
        contains('upload_queue_timeout'),
      );
    },
  );

  test(
    'native upload backpressure query times out without queuing payload',
    () async {
      final channel = await cacheUploadChannel(
        operation: const Duration(milliseconds: 200),
      );
      final query = Completer<int>();
      channel.nativeBufferGate = query.future;
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await _waitUntil(() => harness.peers.last.closed);
      expect(channel.nativeBufferQueries, 1);
      expect(channel.binaryBytes, 0);
      expect(
        harness.logs.map((e) => e.toJson()['code']),
        contains('upload_buffer_query_timeout'),
      );
      query.complete(0);
      await _settle();
      expect(channel.binaryBytes, 0);
    },
  );

  test(
    'native upload backpressure revocation blocks a late query result',
    () async {
      final channel = await cacheUploadChannel();
      final query = Completer<int>();
      channel.nativeBufferGate = query.future;
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await _waitUntil(() => channel.nativeBufferQueries == 1);
      harness.client.setSharingEnabled(false);
      expect(harness.peers.last.closed, isTrue);
      query.complete(0);
      await _settle();
      expect(channel.binaryBytes, 0);
      expect(channel.nativeBufferQueries, 1);
    },
  );

  test(
    'native upload backpressure closure during policy read blocks the next send',
    () async {
      final channel = await cacheUploadChannel();
      final gate = Completer<void>();
      var readAtQuery = -1;
      channel.onNativeBufferQuery = () {
        if (readAtQuery >= 0) return;
        readAtQuery = harness.networkReadCount;
        harness.networkReadGate = gate.future;
      };
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await _waitUntil(
        () => readAtQuery >= 0 && harness.networkReadCount > readAtQuery,
      );
      await channel.close();
      expect(harness.peers.last.closed, isTrue);
      gate.complete();
      harness.networkReadGate = null;
      await _settle();
      expect(channel.binaryBytes, 0);
    },
  );

  for (final invalid in ['negative', 'error']) {
    test(
      'native upload backpressure rejects $invalid queue observation',
      () async {
        final channel = await cacheUploadChannel();
        channel.nativeBufferedBytes = invalid == 'negative' ? -1 : 0;
        channel.nativeBufferError = invalid == 'error';
        channel.receiveText({'type': 'get-piece', 'index': 0});
        await _waitUntil(() => harness.peers.last.closed);
        expect(channel.binaryBytes, 0);
        expect(channel.nativeBufferQueries, 1);
        expect(
          harness.logs.map((e) => e.toJson()['code']),
          contains('upload_buffer_unavailable'),
        );
      },
    );
  }

  test(
    'revocation during session creation preserves receiving and advertises zero pieces',
    () async {
      final gate = Completer<void>();
      harness.sessionGate = gate.future;
      final flight = harness.downloadPrefix();
      for (var n = 0; n < 200 && !harness.paths.contains('session'); n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(harness.paths, contains('session'));
      harness.client.setSharingEnabled(false);
      gate.complete();
      expect(await flight, harness.bytes.length);
      await _settle();
      final heartbeat = harness.body('heartbeat');
      expect(heartbeat['share_enabled'], false);
      expect(heartbeat['pieces'], isEmpty);
    },
  );

  test(
    'diagnostics contain no tokens, SDP, addresses or identifiers',
    () async {
      harness.advertisePeer = true;
      await harness.downloadPrefix();
      await _settle();
      final encoded = jsonEncode(
        harness.logs.map((event) => event.toJson()).toList(),
      );
      for (final secret in [
        _self,
        _other,
        'secret_not_logged',
        'v=0',
        '192.168.1.99',
        'Authorization',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
      expect(AppUpgradeP2PDiagnostic.safeCode('192.168.1.99'), 'unknown_error');
      expect(
        AppUpgradeP2PDiagnostic.safeCode('Bearer secret'),
        'unknown_error',
      );
      expect(
        harness.logs.any(
          (event) => event.stage == 'manifest' && event.status == 200,
        ),
        isTrue,
      );
      expect(
        harness.logs.any(
          (event) => event.stage == 'session' && event.status == 201,
        ),
        isTrue,
      );
      expect(harness.logs.any((event) => event.peerCount == 1), isTrue);
    },
  );
  // Business-coordinator routing stays in LifeRing's original regression suite.

  test(
    'expired bearer authorization ends P2P before seed negotiation',
    () async {
      harness.sessionUnauthorized = true;
      expect(await harness.downloadPrefix(), 0);
      await _settle();
      expect(harness.paths, isNot(contains('server-offer')));
      expect(harness.body('outcome')['reason_code'], 'session_unauthorized');
    },
  );

  test(
    'unknown server error text cannot escape into diagnostic logs',
    () async {
      harness.serverError = 'token=$_self.secret_not_logged ip=192.168.1.99';
      expect(await harness.downloadPrefix(), 0);
      await _settle();
      final encoded = jsonEncode(
        harness.logs.map((event) => event.toJson()).toList(),
      );
      expect(encoded, isNot(contains(_self)));
      expect(encoded, isNot(contains('192.168.1.99')));
      expect(harness.body('outcome')['reason_code'], 'http_error');
      expect(AppUpgradeP2PDiagnostic.safeCode(_self), 'unknown_error');
    },
  );

  test(
    'batch busy guard prevents concurrent uploads from interleaving',
    () async {
      harness.client = harness.makeClient(
        sharingDuration: const Duration(minutes: 3),
      );
      await harness.downloadPrefix();
      harness.incomingOffer = true;
      await harness.client.shareVerifiedFile(harness.part, _url);
      await _settle();
      final channel = harness.peers.last.channel;
      channel.receiveText({
        'type': 'get-pieces',
        'indices': [0, 1],
      });
      channel.receiveText({'type': 'get-piece', 'index': 1});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final controls = channel.sent
          .where((message) => !message.isBinary)
          .map((message) => jsonDecode(message.text) as Map)
          .toList();
      expect(
        controls.where((message) => message['type'] == 'error').single['code'],
        'busy',
      );
      expect(
        controls
            .where((message) => message['type'] == 'piece-start')
            .map((message) => message['index']),
        [0, 1],
      );
    },
  );

  test(
    'negotiated upload window accepts refill at piece-end without interleaving',
    () async {
      harness.bytes = Uint8List.fromList(
        List.generate(5 * AppUpgradeP2PManifest.chunkSize + 79, (i) => i % 251),
      );
      harness.client = harness.makeClient(
        sharingDuration: const Duration(minutes: 3),
      );
      expect(await harness.downloadPrefix(), harness.bytes.length);
      harness.incomingOffer = true;
      await harness.client.shareVerifiedFile(harness.part, _url);
      await _settle();
      final channel = harness.peers.last.channel;
      channel.onControlSent = (control) {
        if (control['type'] == 'piece-end' && (control['index'] as int) < 2) {
          channel.receiveText({
            'type': 'get-piece',
            'index': (control['index'] as int) + 4,
          });
        }
      };
      channel.receiveText({
        'type': 'get-pieces',
        'indices': [0, 1, 2, 3],
        'pipeline_window': 4,
      });
      channel.receiveText({'type': 'get-piece', 'index': 4}); // Window is full.
      channel.receiveText({
        'type': 'get-piece',
        'index': 3,
      }); // Duplicate in flight.
      for (var i = 0; i < 600; i++) {
        if (channel.sent
            .where((m) => !m.isBinary)
            .map((m) => jsonDecode(m.text) as Map)
            .any((m) => m['type'] == 'piece-end' && m['index'] == 5)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final controls = channel.sent
          .where((m) => !m.isBinary)
          .map((m) => jsonDecode(m.text) as Map)
          .toList();
      expect(
        controls.where((m) => m['type'] == 'piece-end').map((m) => m['index']),
        [0, 1, 2, 3, 4, 5],
      );
      expect(
        controls.where((m) => m['type'] == 'error').map((m) => m['code']),
        ['busy', 'busy'],
      );
      expect(
        controls
            .where((m) => m['type'] == 'piece-start')
            .every((m) => m['pipeline_window'] == 4),
        true,
      );
      final actual = BytesBuilder(copy: false);
      for (final message in channel.sent.where((m) => m.isBinary)) {
        actual.add(message.binary);
      }
      expect(actual.takeBytes(), harness.bytes);
    },
  );

  Future<_FakeChannel> startUploadAccounting() async {
    harness.client = harness.makeClient(sharingDuration: null);
    await harness.downloadPrefix();
    await _settle();
    harness.incomingOffer = true;
    await harness.client.shareVerifiedFile(harness.part, _url);
    await _waitUntil(() => harness.peers.length == 2);
    await _settle();
    return harness.peers.last.channel;
  }

  Future<void> uploadIndices(_FakeChannel channel, List<int> indices) async {
    final before = channel.pieceEnds;
    channel.receiveText({'type': 'get-pieces', 'indices': indices});
    await _waitUntil(() => channel.pieceEnds == before + indices.length);
    await _settle();
  }

  test(
    'upload accounting reports payload and retransmission cumulatively',
    () async {
      final channel = await startUploadAccounting();
      await uploadIndices(channel, [0, 1]);
      await harness.waitForPath('peer-upload-report');
      expect(harness.body('peer-upload-report'), {
        'peer_id': _other,
        'uploaded_bytes': harness.bytes.length,
      });
      await uploadIndices(channel, [1]);
      await harness.client.stopSharing();
      expect(channel.binaryBytes, harness.bytes.length + 79);
      expect(
        harness.body('peer-upload-report')['uploaded_bytes'],
        channel.binaryBytes,
      );
      expect(harness.reportedUploadBytes, channel.binaryBytes);
      expect(harness.paths.where((p) => p == 'peer-upload-report').length, 2);
      final logs = jsonEncode(
        harness.logs.map((event) => event.toJson()).toList(),
      );
      expect(logs, isNot(contains(_other)));
      expect(logs, isNot(contains('secret_not_logged')));
      expect(logs, isNot(contains('unknown_error')));
    },
  );

  test(
    'upload accounting revokes immediately and joins report before leave',
    () async {
      final channel = await startUploadAccounting();
      final gate = Completer<void>();
      harness.uploadReportGate = gate.future;
      await uploadIndices(channel, [1]);
      await harness.waitForPath('peer-upload-report');
      final leaves = harness.paths.where((p) => p == 'leave').length;
      harness.client.setForeground(false);
      var stopped = false;
      final stopping = harness.client.stopSharing().then((_) => stopped = true);
      try {
        expect(channel.state, RTCDataChannelState.RTCDataChannelClosed);
        final sent = channel.binaryBytes;
        channel.receiveText({'type': 'get-piece', 'index': 0});
        await _settle();
        expect(channel.binaryBytes, sent);
        expect(stopped, false);
        expect(harness.paths.where((p) => p == 'leave').length, leaves);
      } finally {
        gate.complete();
        await stopping;
      }
      final report = harness.requests.lastWhere(
        (r) => r.uri.path.endsWith('/peer-upload-report'),
      );
      final leave = harness.requests.lastWhere(
        (r) => r.uri.path.endsWith('/leave'),
      );
      expect(report.headers['Authorization'], leave.headers['Authorization']);
      expect(
        harness.paths.lastIndexOf('peer-upload-report'),
        lessThan(harness.paths.lastIndexOf('outcome')),
      );
      expect(harness.paths.last, 'leave');
      expect(harness.reportedUploadBytes, 79);
    },
  );

  test(
    'upload accounting joins an accepted in-flight send on revocation',
    () async {
      final channel = await startUploadAccounting();
      final gate = Completer<void>();
      channel.binarySendGate = gate.future;
      channel.receiveText({'type': 'get-piece', 'index': 0});
      await _waitUntil(() => channel.binarySendAttempts == 1);
      harness.client.setSharingEnabled(false);
      var stopped = false;
      final stopping = harness.client.stopSharing().then((_) => stopped = true);
      try {
        expect(channel.state, RTCDataChannelState.RTCDataChannelClosed);
        await _settle();
        expect(stopped, false);
      } finally {
        gate.complete();
        await stopping;
      }
      expect(channel.binarySendAttempts, 1);
      expect(channel.binaryBytes, AppUpgradeP2PManifest.maxFrameBytes);
      expect(harness.reportedUploadBytes, channel.binaryBytes);
      expect(harness.paths.last, 'leave');
    },
  );

  test('upload accounting excludes rejected native payload sends', () async {
    final channel = await startUploadAccounting();
    channel.rejectBinarySendAt = 2;
    channel.receiveText({'type': 'get-piece', 'index': 0});
    await _waitUntil(
      () => channel.state == RTCDataChannelState.RTCDataChannelClosed,
    );
    await harness.client.stopSharing();
    expect(channel.binarySendAttempts, 2);
    expect(channel.binaryBytes, AppUpgradeP2PManifest.maxFrameBytes);
    expect(harness.reportedUploadBytes, channel.binaryBytes);
  });

  test(
    'upload accounting optional 404 keeps subsequent batches working',
    () async {
      final channel = await startUploadAccounting();
      harness.uploadReportStatus = 404;
      await uploadIndices(channel, [1]);
      await harness.waitForPath('peer-upload-report');
      await _settle();
      expect(channel.state, RTCDataChannelState.RTCDataChannelOpen);
      await uploadIndices(channel, [0]);
      expect(channel.binaryBytes, harness.bytes.length);
      expect(channel.state, RTCDataChannelState.RTCDataChannelOpen);
      await harness.client.stopSharing();
      expect(harness.paths.where((p) => p == 'peer-upload-report').length, 1);
      expect(harness.paths.last, 'leave');
    },
  );

  test(
    'upload accounting retries the final snapshot without adding twice',
    () async {
      final channel = await startUploadAccounting();
      harness.uploadReportTimeouts = 2;
      await uploadIndices(channel, [1]);
      await harness.waitForPath('peer-upload-report');
      await _settle();
      await harness.client.stopSharing();
      final reports = harness.requests
          .where((r) => r.uri.path.endsWith('/peer-upload-report'))
          .toList();
      expect(reports.length, 3);
      expect(
        reports.map((r) => r.data),
        everyElement({'peer_id': _other, 'uploaded_bytes': 79}),
      );
      expect(harness.reportedUploadBytes, 79);
      expect(harness.paths.last, 'leave');
    },
  );

  test(
    'upload accounting retains the same receiver total across RTC reconnect',
    () async {
      final channel = await startUploadAccounting();
      await uploadIndices(channel, [1]);
      await channel.close();
      await _settle();
      harness.incomingOffer = true;
      await _waitUntil(() => harness.peers.length == 3, attempts: 600);
      await _settle();
      final reconnected = harness.peers.last.channel;
      await uploadIndices(reconnected, [1]);
      await harness.client.stopSharing();
      expect(
        harness.reportedUploadBytes,
        channel.binaryBytes + reconnected.binaryBytes,
      );
      expect(harness.reportedUploadBytes, 158);
    },
  );

  test(
    'upload accounting bounds stalled reports and still retires credentials',
    () async {
      final channel = await startUploadAccounting();
      final gate = Completer<void>();
      harness.uploadReportGate = gate.future;
      await uploadIndices(channel, [1]);
      await harness.waitForPath('peer-upload-report');
      final watch = Stopwatch()..start();
      try {
        await harness.client.stopSharing().timeout(const Duration(seconds: 12));
        expect(watch.elapsed, lessThan(const Duration(seconds: 11)));
        final reports = harness.requests
            .where((r) => r.uri.path.endsWith('/peer-upload-report'))
            .toList();
        expect(reports.length, 3);
        expect(reports.every((r) => r.cancelToken?.isCancelled == true), true);
        expect(harness.paths.last, 'leave');
        expect(channel.state, RTCDataChannelState.RTCDataChannelClosed);
      } finally {
        gate.complete();
        await _settle();
      }
    },
  );

  test(
    'continuous cache stops immediately in background and rejoins in foreground',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.downloadPrefix();
      harness.incomingOffer = true;
      await harness.client.shareVerifiedFile(harness.part, _url);
      await _settle();
      final provider = harness.peers.last;
      expect(provider.closed, false);
      final sessions = harness.paths.where((p) => p == 'session').length;
      harness.client.setForeground(false);
      expect(provider.closed, true);
      final sent = provider.channel.sent.length;
      provider.channel.receiveText({'type': 'get-piece', 'index': 0});
      await _settle();
      expect(provider.channel.sent.length, sent);
      expect(harness.paths.where((p) => p == 'session').length, sessions);
      harness.client.setForeground(true);
      await _settle();
      await _waitUntil(
        () => harness.paths.where((p) => p == 'session').length == sessions + 1,
      );
      expect(harness.paths.where((p) => p == 'session').length, sessions + 1);
      expect(harness.body('session')['share_enabled'], true);
    },
  );

  test(
    'continuous cache resumes only on unmetered Wi-Fi and explicit stop forgets it',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.downloadPrefix();
      await harness.client.shareVerifiedFile(harness.part, _url);
      final sessions = harness.paths.where((p) => p == 'session').length;
      for (final network in [
        AppUpgradeP2PNetwork.cellular,
        AppUpgradeP2PNetwork.wifiMetered,
        AppUpgradeP2PNetwork.unknown,
      ]) {
        harness.network = network;
        harness.events.add(network.wireName);
        await _settle();
        harness.client.setForeground(true);
        await _settle();
        expect(harness.paths.where((p) => p == 'session').length, sessions);
      }
      harness.network = AppUpgradeP2PNetwork.wifiUnmetered;
      harness.events.add('wifi_unmetered');
      await _settle();
      await _waitUntil(
        () => harness.paths.where((p) => p == 'session').length == sessions + 1,
      );
      expect(harness.paths.where((p) => p == 'session').length, sessions + 1);
      await harness.client.stopSharing();
      harness.events.add('wifi_unmetered');
      harness.client.setForeground(false);
      harness.client.setForeground(true);
      await _settle();
      expect(harness.paths.where((p) => p == 'session').length, sessions + 1);
    },
  );

  for (final pipelined in [false, true]) {
    test(
      'upload file-read retirement joins actual IO before stop ($pipelined)',
      () async {
        final gate = NativeFileIoGate();
        await IOOverrides.runWithIOOverrides(() async {
          final channel = await startUploadAccounting();
          gate.armRead(harness.part.path);
          final outcomes = harness.paths.where((p) => p == 'outcome').length;
          final leaves = harness.paths.where((p) => p == 'leave').length;
          channel.receiveText({
            'type': 'get-pieces',
            'indices': [0],
            if (pipelined) 'pipeline_window': 4,
          });
          await gate.entered.timeout(const Duration(seconds: 5));
          expect(gate.snapshot()['target_handles'], 1);
          expect(gate.snapshot()['pending_operations'], 1);
          expect(gate.snapshot()['native_bytes'], greaterThan(0));
          gate.retire();
          var stopped = false;
          final stopping = harness.client.stopSharing().then((_) {
            // Observe at the stop Future's completion: later fixture waits
            // must not hide a return while the real file close is pending.
            final atReturn = gate.snapshot();
            expect(atReturn['target_handles'], 0);
            expect(atReturn['pending_operations'], 0);
            stopped = true;
          });
          try {
            final stoppedBeforeRead = await Future.any<bool>([
              stopping.then((_) => true),
              gate.released.then((_) => false),
            ]);
            expect(
              stoppedBeforeRead,
              false,
              reason: 'A native channel close must not retire a live file read',
            );
            expect(harness.paths.where((p) => p == 'outcome').length, outcomes);
            expect(harness.paths.where((p) => p == 'leave').length, leaves);
          } finally {
            await gate.released;
            await stopping;
            await _settle();
          }
          expect(stopped, true);
          final io = gate.snapshot();
          expect(io['valid'], true);
          expect(io['target_handles'], 0);
          expect(io['pending_operations'], 0);
          expect(io['new_read_streams_after_retire'], 0);
          expect(channel.binaryBytes, 0);
          expect(
            channel.sent
                .where((m) => !m.isBinary)
                .where((m) => jsonDecode(m.text)['type'] == 'piece-start'),
            isEmpty,
          );
          expect(harness.paths.where((p) => p == 'leave').length, leaves + 1);
        }, gate);
      },
    );
  }

  test('native lifetime stop joins dispose before outcome and leave', () async {
    final channel = await startUploadAccounting();
    final peer = harness.peers.last;
    final gate = Completer<void>();
    peer.disposeGate = gate.future;
    final outcomes = harness.paths.where((p) => p == 'outcome').length;
    var stopped = false;
    final stopping = harness.client.stopSharing().then((_) => stopped = true);
    try {
      await _waitUntil(() => peer.disposeCalls == 1);
      expect(channel.state, RTCDataChannelState.RTCDataChannelClosed);
      expect(stopped, false);
      expect(harness.paths.where((p) => p == 'outcome').length, outcomes);
    } finally {
      gate.complete();
      await stopping;
    }
    expect(peer.disposed, true);
    expect(peer.closeCalls, 1);
    expect(peer.disposeCalls, 1);
    await harness.client.stopSharing();
    expect(peer.disposeCalls, 1);
    expect(harness.paths.last, 'leave');
  });

  test(
    'native lifetime dispose runs even after native close rejects',
    () async {
      final channel = await startUploadAccounting();
      final peer = harness.peers.last;
      peer.failClose = true;
      await harness.client.stopSharing();
      expect(peer.disposeCalls, 1);
      expect(peer.disposed, true);
      expect(channel.state, RTCDataChannelState.RTCDataChannelClosed);
      expect(harness.logs.any((e) => e.code == 'native_close_failed'), true);
      expect(harness.paths.last, 'leave');
    },
  );

  test(
    'native lifetime stalled close cannot prevent bounded disposal',
    () async {
      await startUploadAccounting();
      final peer = harness.peers.last;
      final gate = Completer<void>();
      peer.closeGate = gate.future;
      final watch = Stopwatch()..start();
      try {
        await harness.client.stopSharing().timeout(const Duration(seconds: 5));
        expect(peer.disposed, true);
        expect(peer.disposeCalls, 1);
        expect(harness.logs.any((e) => e.code == 'native_close_timeout'), true);
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      } finally {
        gate.complete();
        await _settle();
      }
    },
  );

  test(
    'native lifetime dispose failure stays visible and permits leave',
    () async {
      await startUploadAccounting();
      final peer = harness.peers.last;
      peer.failDispose = true;
      harness.logs.clear();
      await harness.client.stopSharing();
      expect(peer.disposeCalls, 1);
      expect(peer.disposed, false);
      expect(harness.logs.any((e) => e.code == 'native_dispose_failed'), true);
      expect(
        harness.logs.any((e) => e.code == 'native_transport_released'),
        false,
      );
      expect(harness.paths.last, 'leave');
      // Complete the fake native owner's cleanup even in the failed case.
      peer.failDispose = false;
      await peer.dispose();
    },
  );

  test(
    'native lifetime stalled disposal is bounded and stays visible',
    () async {
      await startUploadAccounting();
      final peer = harness.peers.last;
      final gate = Completer<void>();
      peer.disposeGate = gate.future;
      try {
        await harness.client.stopSharing().timeout(const Duration(seconds: 5));
        expect(peer.disposeCalls, 1);
        expect(peer.disposed, false);
        expect(
          harness.logs.any((e) => e.code == 'native_dispose_timeout'),
          true,
        );
        expect(harness.paths.last, 'leave');
      } finally {
        gate.complete();
        await _settle();
      }
      expect(peer.disposed, true);
    },
  );

  test('cache sharing stop waits for its final outcome and leave', () async {
    harness.client = harness.makeClient(sharingDuration: null);
    await harness.downloadPrefix();
    await _settle();
    await harness.client.shareVerifiedFile(harness.part, _url);
    final before = harness.paths.where((p) => p == 'outcome').length;
    final leaves = harness.paths.where((p) => p == 'leave').length;
    final gate = Completer<void>();
    harness.outcomeGate = gate.future;
    var stopped = false;
    final stopping = harness.client.stopSharing().then((_) => stopped = true);
    try {
      await _waitUntil(
        () => harness.paths.where((p) => p == 'outcome').length > before,
      );
      await _settle();
      expect(
        stopped,
        false,
        reason: 'The HTTP owner must remain available for leave',
      );
      expect(harness.paths.where((p) => p == 'leave').length, leaves);
    } finally {
      gate.complete();
      await stopping;
    }
    expect(harness.paths.where((p) => p == 'leave').length, leaves + 1);
  });

  test('cache sharing stop joins an already paused session cleanup', () async {
    harness.client = harness.makeClient(sharingDuration: null);
    await harness.downloadPrefix();
    await _settle();
    await harness.client.shareVerifiedFile(harness.part, _url);
    final before = harness.paths.where((p) => p == 'outcome').length;
    final gate = Completer<void>();
    harness.outcomeGate = gate.future;
    harness.client.setForeground(false);
    var stopped = false;
    final stopping = harness.client.stopSharing().then((_) => stopped = true);
    try {
      await _waitUntil(
        () => harness.paths.where((p) => p == 'outcome').length > before,
      );
      await _settle();
      expect(
        stopped,
        false,
        reason: 'Background pause must retain cleanup ownership',
      );
    } finally {
      gate.complete();
      await stopping;
    }
  });

  test(
    'cache sharing stop during pending session cannot rejoin later',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.downloadPrefix();
      await _settle();
      await harness.client.shareVerifiedFile(harness.part, _url);
      await harness.client.stopSharing();
      await _settle();
      final before = harness.paths.where((p) => p == 'session').length;
      final session = Completer<void>();
      harness.sessionGate = session.future;
      final sharing = harness.client.shareVerifiedFile(harness.part, _url);
      await _waitUntil(
        () => harness.paths.where((p) => p == 'session').length > before,
      );
      final stopping = harness.client.stopSharing();
      try {
        session.complete();
        await sharing;
        await stopping;
        // Dio may cancel before a token is acquired. Do not demand a cleanup
        // outcome for credentials this fixture never delivered to the client.
        harness.client.setForeground(true);
        harness.events.add('wifi_unmetered');
        await _settle();
        expect(harness.paths.where((p) => p == 'session').length, before + 1);
        expect(harness.peers.every((peer) => peer.closed), true);
      } finally {
        if (!session.isCompleted) session.complete();
        await stopping;
      }
    },
  );

  test(
    'background during receive-session creation revokes upload without cancelling receive',
    () async {
      final gate = Completer<void>();
      harness.sessionGate = gate.future;
      final flight = harness.downloadPrefix();
      for (var i = 0; i < 200 && !harness.paths.contains('session'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(harness.paths, contains('session'));
      harness.client.setForeground(false);
      gate.complete();
      expect(await flight, harness.bytes.length);
      await _settle();
      expect(harness.body('heartbeat')['share_enabled'], false);
      expect(harness.body('heartbeat')['pieces'], isEmpty);
    },
  );

  test(
    'explicit stop during cache handoff cannot rejoin a late sharing session',
    () async {
      harness.client = harness.makeClient(sharingDuration: null);
      await harness.downloadPrefix();
      final before = harness.paths.where((p) => p == 'session').length;
      final sharing = harness.client.shareVerifiedFile(harness.part, _url);
      await harness.client.stopSharing();
      await sharing;
      harness.client.setForeground(true);
      harness.events.add('wifi_unmetered');
      await _settle();
      expect(harness.paths.where((p) => p == 'session').length, before);
    },
  );

  test('background lifecycle prevents completed-cache sharing', () async {
    harness.client = harness.makeClient(
      sharingDuration: const Duration(minutes: 3),
    );
    await harness.downloadPrefix();
    await _settle();
    final sessions = harness.paths.where((path) => path == 'session').length;
    harness.client.setForeground(false);
    await harness.client.shareVerifiedFile(harness.part, _url);
    expect(harness.paths.where((path) => path == 'session').length, sessions);
  });

  test(
    'mixed peer and seed transfer reports only verified user bytes',
    () async {
      harness.advertisePeer = true;
      harness.advertisedPieces = [0];
      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _settle();
      expect(
        harness.body('outcome')['peer_bytes'],
        AppUpgradeP2PManifest.chunkSize,
      );
      final result = harness.logs.firstWhere(
        (event) => event.stage == 'result',
      );
      expect(result.seedBytes, 79);
      expect(result.verified, true);
    },
  );

  test(
    'receiving continues across Wi-Fi to cellular while sharing is withdrawn',
    () async {
      harness.switchToCellularAtIndex = 1;
      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _settle();
      expect(harness.body('heartbeat')['network'], 'cellular');
      expect(harness.body('heartbeat')['share_enabled'], false);
      expect(harness.body('heartbeat')['pieces'], isEmpty);
      expect(harness.body('outcome')['verified'], true);
    },
  );

  test(
    'incomplete ICE never submits SDP and quickly preserves HTTPS fallback',
    () async {
      harness.iceNeverCompletes = true;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(milliseconds: 100),
      );
      expect(await harness.downloadPrefix(), 0);
      await _settle();
      expect(harness.paths, isNot(contains('server-offer')));
      expect(harness.peers.every((peer) => peer.closed), true);
      expect(harness.body('outcome')['reason_code'], 'ice_gather_timeout');
    },
  );
  test(
    'server may revoke sharing without disabling reception on Wi-Fi',
    () async {
      harness.sessionShareDenied = true;
      harness.incomingOffer = true;
      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _settle();
      expect(harness.paths, isNot(contains('signal')));
      expect(harness.peers.length, 1); // Only the receiving seed connection.
      expect(harness.body('outcome')['verified'], true);
    },
  );

  test(
    'ICE finishing after four seconds sends the complete seed offer',
    () async {
      harness.iceDelay = const Duration(milliseconds: 4300);
      harness.stateQueryNeverReturns = true;
      harness.client = harness.makeClient(
        timeouts: const AppUpgradeP2PTimeouts(),
      );
      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _settle();
      expect(harness.paths, contains('server-offer'));
      expect(harness.body('server-offer')['sdp'], contains('a=candidate:'));
      expect(harness.body('server-offer')['sdp'], isNot(contains('partial')));
      final complete = harness.logs.firstWhere(
        (e) =>
            e.stage == 'ice_gather' &&
            e.code == 'ice_complete' &&
            e.durationMs != null,
      );
      expect(complete.durationMs, greaterThanOrEqualTo(4000));
      expect(harness.body('outcome')['verified'], true);
      expect(harness.logs.any((e) => e.code == 'unknown_error'), false);
    },
  );

  test('completion callback wakes ICE even if state query lags', () async {
    harness.iceDelay = const Duration(milliseconds: 70);
    harness.callbackOnly = true;
    expect(await harness.downloadPrefix(), harness.bytes.length);
    expect(harness.body('server-offer')['sdp'], contains('a=candidate:'));
  });

  test(
    'state query recovers an ICE completion whose callback was lost',
    () async {
      harness.iceDelay = const Duration(milliseconds: 60);
      harness.emitGatherCallbacks = false;
      expect(await harness.downloadPrefix(), harness.bytes.length);
      expect(harness.body('server-offer')['sdp'], contains('a=candidate:'));
    },
  );

  test('ICE callback wakes a stalled native state query', () async {
    harness.iceDelay = const Duration(milliseconds: 60);
    harness.stateQueryNeverReturns = true;
    harness.client = harness.makeClient(
      sourceTimeout: const Duration(milliseconds: 300),
    );
    expect(await harness.downloadPrefix(), harness.bytes.length);
    expect(harness.body('server-offer')['sdp'], contains('a=candidate:'));
  });

  test(
    'cancel during ICE closes connection without publishing any offer',
    () async {
      harness.iceNeverCompletes = true;
      final token = CancelToken();
      final download = harness.downloadPrefix(cancelToken: token);
      for (
        var i = 0;
        i < 100 && !harness.logs.any((e) => e.stage == 'ice_gather');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(harness.logs.any((e) => e.stage == 'ice_gather'), true);
      token.cancel();
      await expectLater(download, throwsA(isA<DioException>()));
      await _settle();
      expect(harness.paths, isNot(contains('server-offer')));
      expect(harness.body('outcome')['outcome'], 'client_interrupted');
      expect(harness.peers.every((p) => p.closed), true);
    },
  );

  test(
    'native lifetime late connection creation is disposed after its deadline',
    () async {
      final gate = Completer<void>();
      harness.creationGate = gate.future;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(milliseconds: 80),
      );
      expect(await harness.downloadPrefix(), 0);
      gate.complete();
      await _settle();
      expect(harness.peers.every((p) => p.closed), true);
      await _waitUntil(() => harness.peers.every((p) => p.disposed));
      expect(harness.paths, isNot(contains('server-offer')));
      expect(harness.body('outcome')['reason_code'], 'rtc_operation_timeout');
    },
  );

  test(
    'provider answer waits for its own ICE and uses complete local SDP',
    () async {
      await harness.part.writeAsBytes(harness.bytes);
      await harness.downloadPrefix();
      harness.incomingOffer = true;
      harness.iceDelay = const Duration(milliseconds: 250);
      harness.client = harness.makeClient(
        sharingDuration: const Duration(seconds: 3),
      );
      // Initialize this client with a verified cache before offering it.
      await harness.downloadPrefix();
      harness.incomingOffer = true;
      await harness.client.shareVerifiedFile(harness.part, _url);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final answer = harness.requests.lastWhere(
        (r) =>
            r.uri.pathSegments.last == 'signal' &&
            (r.data as Map)['type'] == 'answer',
      );
      expect((answer.data as Map)['sdp'], contains('a=candidate:'));
      expect(harness.logs.any((e) => e.code == 'answer_ready'), true);
    },
  );

  test(
    'ICE timeout has one immutable outcome; late completion cannot send offer',
    () async {
      harness.iceNeverCompletes = true;
      harness.client = harness.makeClient(
        sourceTimeout: const Duration(milliseconds: 80),
      );
      expect(await harness.downloadPrefix(), 0);
      await _settle();
      for (final peer in harness.peers) {
        peer.onIceGatheringState?.call(
          RTCIceGatheringState.RTCIceGatheringStateComplete,
        );
      }
      await _settle();
      expect(harness.paths, isNot(contains('server-offer')));
      expect(harness.paths.where((p) => p == 'outcome').length, 1);
      expect(harness.body('outcome')['reason_code'], 'ice_gather_timeout');
    },
  );

  test('duplicate download calls share one session and file writer', () async {
    harness.iceDelay = const Duration(milliseconds: 100);
    final first = harness.downloadPrefix();
    final second = harness.downloadPrefix();
    expect(identical(first, second), true);
    expect(await first, harness.bytes.length);
    expect(await second, harness.bytes.length);
    expect(harness.paths.where((p) => p == 'session').length, 1);
  });

  test(
    'session transport retry reuses body, installation identity and key',
    () async {
      harness.sessionTimeouts = 1;
      expect(await harness.downloadPrefix(), harness.bytes.length);
      await _settle();
      final requests = harness.requests
          .where((r) => r.uri.pathSegments.last == 'session')
          .toList();
      expect(requests.length, 2);
      expect(requests[0].data, requests[1].data);
      expect(
        requests[0].headers['Idempotency-Key'],
        requests[1].headers['Idempotency-Key'],
      );
      expect(
        requests[0].headers['Idempotency-Key'],
        matches(RegExp(r'^[a-f0-9]{32}$')),
      );
      expect(
        requests[0].headers['X-Device-Id'],
        await AppUpgradeP2PIdentity.deviceId(),
      );
      final logs = jsonEncode(harness.logs.map((e) => e.toJson()).toList());
      expect(logs, isNot(contains(requests[0].headers['Idempotency-Key'])));
      expect(logs, isNot(contains(requests[0].headers['X-Device-Id'])));
    },
  );

  test(
    'pending session metadata retains original body across network changes',
    () async {
      final request = await AppUpgradeP2PIdentity.sessionRequest(
        apiBase: 'test',
        sha: 'a' * 64,
        sharing: false,
        body: {
          'network': 'wifi_unmetered',
          'pieces': [0],
        },
      );
      final retry = await AppUpgradeP2PIdentity.sessionRequest(
        apiBase: 'test',
        sha: 'a' * 64,
        sharing: false,
        body: {'network': 'cellular', 'pieces': []},
      );
      expect(retry.key, request.key);
      expect(retry.body, request.body);
      await AppUpgradeP2PIdentity.release(request);
      final next = await AppUpgradeP2PIdentity.sessionRequest(
        apiBase: 'test',
        sha: 'a' * 64,
        sharing: false,
        body: {'network': 'cellular'},
      );
      expect(next.key, isNot(request.key));
    },
  );

  test(
    'outcome timeout retries exact snapshot and conflict stops retries',
    () async {
      harness.seedBusy = true;
      harness.outcomeTimeouts = 1;
      expect(await harness.downloadPrefix(), 0);
      await _settle();
      final outcomes = harness.requests
          .where((r) => r.uri.pathSegments.last == 'outcome')
          .toList();
      expect(outcomes.length, 2);
      expect(outcomes[0].data, outcomes[1].data);
      expect((outcomes[1].data as Map)['reason_code'], 'server_seed_busy');
      expect(harness.paths.last, 'leave');
      harness.requests.clear();
      harness.outcomeConflict = true;
      expect(await harness.downloadPrefix(), 0);
      await _settle();
      expect(harness.paths.where((p) => p == 'outcome').length, 1);
      expect(
        harness.logs.any(
          (e) =>
              e.stage == 'outcome' &&
              e.code == 'outcome_conflict' &&
              e.status == 409,
        ),
        true,
      );
      expect(harness.paths.last, 'leave');
    },
  );
}

Future<void> _waitUntil(bool Function() ready, {int attempts = 200}) async {
  for (var i = 0; i < attempts && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    ready(),
    true,
    reason: 'Wait for the actual session after async file verification',
  );
}

Future<void> _settle() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Simulated signaling/service responses plus framed DataChannels verify the
/// production scheduler. They intentionally do not claim real ICE/NAT success.
class _Harness {
  _Harness(this.directory) {
    bytes = Uint8List.fromList(
      List.generate(
        AppUpgradeP2PManifest.chunkSize + 79,
        (index) => index % 251,
      ),
    );
    dio.interceptors.add(InterceptorsWrapper(onRequest: _http));
    client = makeClient();
  }
  final Directory directory;
  final Dio dio = Dio();
  final events = StreamController<dynamic>.broadcast();
  final List<RequestOptions> requests = [];
  final List<AppUpgradeP2PDiagnostic> logs = [];
  final List<_FakePeer> peers = [];
  final List<Map<String, dynamic>> peerConfigurations = [];
  final List<Map<String, dynamic>> signals = [];
  final List<Map<String, dynamic>> remoteCandidates = [];
  List<RTCIceCandidate> localIceCandidates = [];
  bool signalRemoteCandidates = false;
  bool serverTrickleSession = false;
  final seedCandidates = <Map<String, dynamic>>[];
  bool legacyPeer = false;
  String channelLabel = AppUpgradeP2PManifest.channelLabel;
  Future<void>? seedGate, sessionGate, peersGate;
  Duration remoteDescriptionDelay = Duration.zero;
  void enableTrickle({int budgetMs = 8000}) {
    manifestOverride.addAll({
      'trickle_ice_supported': true,
      'trickle_ice_protocol_version': 1,
      'p2p_connect_timeout_ms': budgetMs,
      'p2p_ice_gather_timeout_ms': 6000,
    });
  }

  Future<void> waitForPath(String path) async {
    for (var i = 0; i < 200 && !paths.contains(path); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(paths, contains(path));
  }

  late Uint8List bytes;
  late AppUpgradeV40P2PClient client;
  AppUpgradeP2PNetwork network = AppUpgradeP2PNetwork.wifiUnmetered;
  Future<void>? networkReadGate;
  int networkReadCount = 0;
  Map<String, dynamic> manifestOverride = {};
  int? artifactBuild;
  bool advertisePeer = false,
      rejectSignal = false,
      seedBusy = false,
      failCandidatePosts = false,
      peersDisabled = false,
      incomingOffer = false;
  int? dropIndex, corruptIndex;
  Duration pieceDelay = Duration.zero;
  Future<void>? outcomeGate;
  Future<void>? uploadReportGate;
  int uploadReportStatus = 200, uploadReportTimeouts = 0;
  int reportedUploadBytes = 0;
  bool sessionUnauthorized = false;
  String? serverError;
  List<int> advertisedPieces = [0, 1];
  int? switchToCellularAtIndex;
  bool iceNeverCompletes = false;
  bool sessionShareDenied = false;
  Duration iceDelay = Duration.zero;
  bool callbackOnly = false;
  bool emitGatherCallbacks = true, stateQueryNeverReturns = false;
  Future<void>? creationGate;
  int sessionTimeouts = 0, outcomeTimeouts = 0;
  bool outcomeConflict = false;
  bool rejectDiagnostics = false;
  File get part => File('${directory.path}/test.apk.part');
  List<String> get paths =>
      requests.map((request) => request.uri.pathSegments.last).toList();
  Map<String, dynamic> get manifestJson => {
    'status': 'ok',
    'auto_start': true,
    'protocol_version': 1,
    'app_slug': 'lifering',
    'version': 'test',
    'file_size': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'chunk_size': AppUpgradeP2PManifest.chunkSize,
    'piece_hashes': [
      for (
        var offset = 0;
        offset < bytes.length;
        offset += AppUpgradeP2PManifest.chunkSize
      )
        sha256
            .convert(
              bytes.sublist(
                offset,
                (offset + AppUpgradeP2PManifest.chunkSize).clamp(
                  0,
                  bytes.length,
                ),
              ),
            )
            .toString(),
    ],
    'stun_urls': [
      'stun:download.csnas.asia:3479',
      'stun:download1.csnas.asia:3479',
    ],
    'peer_api_base': '/api/app/lifering/p2p',
    'server_seed_url':
        'https://download.csnas.asia/api/app/lifering/p2p/server-offer',
    'fallback_url': _url,
    ...manifestOverride,
  };
  AppUpgradeInfo get info => AppUpgradeInfo(
    releaseId: 'test-release',
    versionName: 'test',
    versionCode: 8900,
    downloadVersionCode: artifactBuild,
    releaseNotes: '',
    forceUpdate: false,
    downloadUrl: _url,
    fileSize: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    downloadProtocol: 'APK_SERVICE_V40',
    downloadSlug: 'lifering',
    downloadEtag: '"release-test"',
  );
  AppUpgradeP2PManifest parsedManifest() => AppUpgradeP2PManifest.parse(
    manifestJson,
    origin: 'https://download.csnas.asia',
    slug: 'lifering',
    version: 'test',
    fileSize: bytes.length,
    sha256: sha256.convert(bytes).toString(),
  );
  Map body(String path) =>
      requests
              .lastWhere((request) => request.uri.pathSegments.last == path)
              .data
          as Map;
  AppUpgradeV40P2PClient makeClient({
    AppUpgradeReceiveBufferFactory? receiveBufferFactory,
    AppUpgradeUploadBudget? uploadBudget,
    bool enableP8P = false,
    Duration sourceTimeout = const Duration(seconds: 3),
    Duration? sharingDuration = Duration.zero,
    AppUpgradeP2PTimeouts? timeouts,
  }) => AppUpgradeV40P2PClient(
    dio: dio,
    isAndroid: true,
    receiveBufferFactory: receiveBufferFactory,
    uploadBudget: uploadBudget,
    enableP8P: enableP8P,
    networkReader: () async {
      networkReadCount++;
      await networkReadGate;
      return network;
    },
    networkEvents: events.stream,
    diagnostic: logs.add,
    timeouts:
        timeouts ??
        AppUpgradeP2PTimeouts(
          rtcOperation: sourceTimeout,
          iceGathering: sourceTimeout,
          answer: sourceTimeout,
          channel: sourceTimeout,
          transfer: sourceTimeout,
        ),
    sharingDuration: sharingDuration,
    peerFactory: (configuration) async {
      peerConfigurations.add(configuration);
      final peer = _FakePeer(this);
      peers.add(peer);
      await creationGate;
      return peer;
    },
  );
  Future<int> downloadPrefix({
    String url = _url,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) => client.downloadVerifiedPrefix(
    downloadUrl: url,
    expectedSlug: 'lifering',
    expectedVersion: 'test',
    expectedFileSize: bytes.length,
    expectedSha256: sha256.convert(bytes).toString(),
    partFile: part,
    onProgress: onProgress ?? (_, _) {},
    cancelToken: cancelToken,
  );

  Future<void> _http(
    RequestOptions request,
    RequestInterceptorHandler handler,
  ) async {
    requests.add(request);
    final endpoint = request.uri.pathSegments.last;
    Object data = {'ok': true};
    var status = 200;
    switch (endpoint) {
      case 'manifest':
        data = manifestJson;
      case 'session':
        await sessionGate;
        if (sessionTimeouts-- > 0) {
          handler.reject(
            DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            ),
          );
          return;
        }
        status = sessionTimeouts < -1 ? 200 : 201;
        data = {
          'session_id': _self,
          'token': '$_self.secret_not_logged',
          'heartbeat_interval': 20,
          if (sessionShareDenied) 'share_enabled': false,
          if (serverTrickleSession) 'server_trickle_supported': true,
        };
      case 'peers':
        await peersGate;
        if (sessionUnauthorized) {
          status = 401;
          data = {'error': 'invalid_session'};
        } else if (peersDisabled) {
          status = 503;
          data = {'error': 'p2p_disabled'};
        } else {
          data = {
            'peers': advertisePeer
                ? [
                    {
                      'peer_id': _other,
                      'pieces': advertisedPieces,
                      if (manifestOverride['trickle_ice_supported'] == true &&
                          !legacyPeer)
                        'trickle_ice_supported': true,
                    },
                  ]
                : [],
          };
        }
      case 'signals':
        if (incomingOffer) {
          incomingOffer = false;
          signals.add({
            'from_peer_id': _other,
            'type': 'offer',
            'sdp': 'v=0\r\nc=IN IP4 192.168.1.99',
            if (manifestOverride['trickle_ice_supported'] == true &&
                !legacyPeer)
              'trickle_ice': true,
          });
        }
        data = {
          'signals': List<Map<String, dynamic>>.from(signals),
          'candidates': List<Map<String, dynamic>>.from(remoteCandidates),
          if (serverTrickleSession)
            'server_candidates': List<Map<String, dynamic>>.from(
              seedCandidates,
            ),
        };
        signals.clear();
        remoteCandidates.clear();
      case 'signal':
        if (rejectSignal) {
          status = 404;
          data = {'error': 'peer_not_available'};
        } else {
          status = 202;
          if ((request.data as Map)['type'] == 'offer') {
            signals.add({
              'from_peer_id': _other,
              'type': 'answer',
              'sdp': 'v=0',
            });
            if (signalRemoteCandidates) {
              final candidate = {
                'from_peer_id': _other,
                'candidate': {
                  'candidate': 'candidate:9 1 udp 1 192.168.1.98 4321 typ host',
                  'sdpMid': '0',
                  'sdpMLineIndex': 0,
                },
              };
              remoteCandidates.addAll([
                candidate,
                candidate,
                {'from_peer_id': _other, 'candidate': null},
              ]);
            }
          }
        }
      case 'server-offer':
        await seedGate;
        if (serverError != null) {
          status = 503;
          data = {'error': serverError};
        } else if (seedBusy) {
          status = 503;
          data = {'error': 'server_seed_busy'};
        } else {
          data = {
            'type': 'answer',
            'sdp': 'v=0',
            'data_channel': 'lifering-apk-p2p-v1',
          };
        }
      case 'candidate':
      case 'server-candidate':
        if (failCandidatePosts) {
          status = 503;
          data = {'error': 'server_seed_unavailable'};
        }
      case 'peer-upload-report':
        await uploadReportGate;
        if (uploadReportTimeouts-- > 0) {
          handler.reject(
            DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            ),
          );
          return;
        }
        status = uploadReportStatus;
        if (status == 200) {
          final count = (request.data as Map)['uploaded_bytes'] as int;
          if (count > reportedUploadBytes) reportedUploadBytes = count;
        } else {
          data = {'error': 'optional_route_unavailable'};
        }
      case 'outcome':
        if (rejectDiagnostics &&
            (request.data as Map).containsKey('diagnostics')) {
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 400,
              data: {'error': 'invalid_p2p_diagnostics'},
            ),
          );
          return;
        }
        if (outcomeTimeouts-- > 0) {
          handler.reject(
            DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            ),
          );
          return;
        }
        if (outcomeGate != null) await outcomeGate;
        status = outcomeConflict
            ? 409
            : outcomeTimeouts < -1
            ? 200
            : 201;
        if (outcomeConflict) data = {'error': 'outcome_conflict'};
      case 'leave':
        final outcome = (request.data as Map)['outcome'];
        if (outcome != null &&
            outcome != 'client_interrupted' &&
            outcome != 'https_fallback') {
          status = 400;
          data = {'error': 'invalid_outcome'};
        }
    }
    handler.resolve(
      Response(requestOptions: request, statusCode: status, data: data),
    );
  }
}

class _BufferOwner implements AppUpgradeReceiveBufferOwner {
  _BufferOwner({this.closeGate, this.fail = false});
  final Completer<void>? closeGate;
  final bool fail;
  final candidates = <String?>[];
  int closeCalls = 0;
  @override
  void addCandidate(String? candidate) {
    candidates.add(candidate);
    if (fail) throw StateError('optional');
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (fail) throw StateError('optional');
    await closeGate?.future;
  }
}

class _FakePeer extends RTCPeerConnection {
  _FakePeer(this.harness) : channel = _FakeChannel(harness);
  final _Harness harness;
  final _FakeChannel channel;
  RTCSessionDescription? local;
  bool closed = false, disposed = false;
  bool failClose = false, failDispose = false;
  int closeCalls = 0, disposeCalls = 0;
  Future<void>? closeGate, disposeGate;
  bool gatherComplete = false;
  Timer? gatherTimer;
  bool remoteSet = false, candidateBeforeDescription = false;
  final List<RTCIceCandidate> addedCandidates = [];
  @override
  Future<RTCDataChannel> createDataChannel(
    String label,
    RTCDataChannelInit init,
  ) async {
    expect(label, 'lifering-apk-p2p-v1');
    expect(init.ordered, true);
    expect(init.maxRetransmits, -1);
    return channel;
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('v=0\r\na=partial', 'offer');
  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('v=0', 'answer');
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    local = description;
    for (final candidate in harness.localIceCandidates) {
      onIceCandidate?.call(candidate);
    }
    if (harness.emitGatherCallbacks) {
      onIceGatheringState?.call(
        RTCIceGatheringState.RTCIceGatheringStateGathering,
      );
    }
    if (!harness.iceNeverCompletes) {
      void complete() {
        gatherComplete = true;
        if (harness.emitGatherCallbacks) {
          onIceGatheringState?.call(
            RTCIceGatheringState.RTCIceGatheringStateComplete,
          );
        }
      }

      if (harness.iceDelay == Duration.zero) {
        complete();
      } else {
        gatherTimer = Timer(harness.iceDelay, complete);
      }
    }
  }

  @override
  Future<RTCSessionDescription?> getLocalDescription() async => gatherComplete
      ? RTCSessionDescription(
          'v=0\r\na=candidate:1 1 udp 1 192.168.1.99 1234 typ host\r\na=candidate:2 1 udp 1 2001:db8::99 1234 typ host\r\n',
          local?.type,
        )
      : local;
  @override
  Future<RTCIceGatheringState?> getIceGatheringState() async =>
      harness.stateQueryNeverReturns
      ? await Completer<RTCIceGatheringState?>().future
      : !gatherComplete || harness.callbackOnly
      ? RTCIceGatheringState.RTCIceGatheringStateGathering
      : RTCIceGatheringState.RTCIceGatheringStateComplete;
  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await Future<void>.delayed(harness.remoteDescriptionDelay);
    remoteSet = true;
    onIceConnectionState?.call(
      RTCIceConnectionState.RTCIceConnectionStateConnected,
    );
    channel.open();
    if (description.type == 'offer') onDataChannel?.call(channel);
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    candidateBeforeDescription |= !remoteSet;
    addedCandidates.add(candidate);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
    gatherTimer?.cancel();
    if (closeGate != null) await closeGate;
    if (failClose) throw StateError('Native close rejected');
    await channel.close();
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (disposeGate != null) await disposeGate;
    if (failDispose) throw StateError('Native dispose rejected');
    disposed = closed = true;
    gatherTimer?.cancel();
    await channel.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChannel extends RTCDataChannel {
  _FakeChannel(this.harness) {
    stateChangeStream = _states.stream;
  }
  final _Harness harness;
  final _states = StreamController<RTCDataChannelState>.broadcast();
  final List<RTCDataChannelMessage> sent = [];
  void Function(Map)? onControlSent;
  void Function(RTCDataChannelMessage)? onQueued;
  Future<void>? binarySendGate;
  int? rejectBinarySendAt;
  int binarySendAttempts = 0;
  int cachedBufferedBytes = 0, nativeBufferedBytes = 0;
  int nativeBufferQueries = 0, maxNativeBufferedBytes = 0;
  int? nativeDrainPerQuery;
  bool nativeBufferError = false;
  Future<int>? nativeBufferGate;
  void Function()? onNativeBufferQuery;
  int get binaryBytes =>
      sent.where((m) => m.isBinary).fold(0, (n, m) => n + m.binary.length);
  int get pieceEnds => sent
      .where(
        (m) =>
            !m.isBinary && (jsonDecode(m.text) as Map)['type'] == 'piece-end',
      )
      .length;
  RTCDataChannelState _state = RTCDataChannelState.RTCDataChannelConnecting;
  @override
  RTCDataChannelState get state => _state;
  @override
  String get label => harness.channelLabel;
  @override
  int get id => 1;
  @override
  int get bufferedAmount => cachedBufferedBytes;
  @override
  Future<int> getBufferedAmount() async {
    nativeBufferQueries++;
    onNativeBufferQuery?.call();
    if (nativeBufferError) throw StateError('Native query unavailable');
    if (nativeBufferGate != null) return await nativeBufferGate!;
    final observed = nativeBufferedBytes;
    // Simulate independent native drainage; never update the event cache.
    if (nativeDrainPerQuery != null) {
      nativeBufferedBytes = (nativeBufferedBytes - nativeDrainPerQuery!).clamp(
        0,
        1 << 30,
      );
    } else if (observed > 0 && cachedBufferedBytes != 0) {
      nativeBufferedBytes = 0;
    }
    return observed;
  }

  void open() {
    _state = RTCDataChannelState.RTCDataChannelOpen;
    _states.add(_state);
  }

  void receiveText(Map<String, Object?> body) =>
      onMessage?.call(RTCDataChannelMessage(jsonEncode(body)));
  @override
  Future<void> send(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      binarySendAttempts++;
      if (binarySendGate != null) await binarySendGate;
      if (binarySendAttempts == rejectBinarySendAt) {
        throw StateError('Native payload send rejected');
      }
      nativeBufferedBytes += message.binary.length;
      if (nativeBufferedBytes > maxNativeBufferedBytes) {
        maxNativeBufferedBytes = nativeBufferedBytes;
      }
      // Normal test channels drain natively, without requiring event delivery.
      if (nativeBufferGate == null && nativeDrainPerQuery == null) {
        nativeBufferedBytes = 0;
      }
    }
    sent.add(message);
    onQueued?.call(message);
    if (message.isBinary) return;
    final control = jsonDecode(message.text) as Map;
    onControlSent?.call(control);
    if (control['type'] != 'get-piece' && control['type'] != 'get-pieces') {
      return;
    }
    final indices = control['type'] == 'get-pieces'
        ? (control['indices'] as List).cast<int>()
        : [control['index'] as int];
    if (harness.pieceDelay != Duration.zero) {
      // Sending a control message queues it; remote transfer happens later.
      unawaited(_respond(indices));
      return;
    }
    await _respond(indices);
  }

  Future<void> _respond(List<int> indices) async {
    for (final index in indices) {
      if (harness.pieceDelay != Duration.zero) {
        await Future<void>.delayed(harness.pieceDelay);
      }
      if (_state == RTCDataChannelState.RTCDataChannelClosed) return;
      if (harness.switchToCellularAtIndex == index) {
        harness.network = AppUpgradeP2PNetwork.cellular;
        harness.events.add('cellular');
        await _settle();
      }
      if (harness.dropIndex == index) return;
      final start = index * AppUpgradeP2PManifest.chunkSize;
      final end = (start + AppUpgradeP2PManifest.chunkSize).clamp(
        0,
        harness.bytes.length,
      );
      final bytes = Uint8List.fromList(harness.bytes.sublist(start, end));
      if (harness.corruptIndex == index) bytes[0] ^= 1;
      receiveText({
        'type': 'piece-start',
        'index': index,
        'size': bytes.length,
      });
      for (var offset = 0; offset < bytes.length; offset += 48 * 1024) {
        onMessage?.call(
          RTCDataChannelMessage.fromBinary(
            Uint8List.sublistView(
              bytes,
              offset,
              (offset + 48 * 1024).clamp(0, bytes.length),
            ),
          ),
        );
      }
      receiveText({'type': 'piece-end', 'index': index});
    }
  }

  @override
  Future<void> close() async {
    if (_state == RTCDataChannelState.RTCDataChannelClosed) return;
    _state = RTCDataChannelState.RTCDataChannelClosed;
    onDataChannelState?.call(_state);
    await _states.close();
  }
}
