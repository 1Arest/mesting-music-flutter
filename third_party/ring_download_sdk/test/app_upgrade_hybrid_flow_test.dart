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
import 'package:ring_download_sdk/src/p8p/transfer_protocol.dart';
import 'package:ring_download_sdk/src/p8p/source_diversity.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/sdk/engine.dart';
import 'support/loopback_payload.dart';
import 'support/real_route.dart';

const _url = 'https://download.csnas.asia/lifering/download';
const _self = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _other = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _second = 'cccccccccccccccccccccccccccccccc';
const _third = 'dddddddddddddddddddddddddddddddd';
const _fourth = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

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

  void multisourceFixture({bool peer = false}) {
    harness.enableTrickle();
    harness.bytes = Uint8List.fromList(
      List.generate(8 * 1048576 + 79, (i) => i % 251),
    );
    harness.advertisedPieces = List.generate(9, (i) => i);
    harness.pieceDelay = const Duration(milliseconds: 20);
    harness.leaseCapable = true;
    harness.leasePeerCapable = peer;
    harness.advertisePeer = peer;
    harness.manifestOverride['p8p'] = {
      'version': 1,
      'max_window': 4,
      'features': ['adaptive_window_v1', 'capacity_advice_v1'],
      'transfer': P8PTransferProtocol.capability,
    };
    harness.client = harness.makeClient(hybridStartup: true, enableP8P: true);
  }

  void seedRetryFixture() {
    multisourceFixture();
    harness.manifestOverride.addAll({
      'server_offer_cancel_supported': true,
      'server_offer_cancel_protocol_version': 1,
      'peer_shared_deadline_supported': true,
    });
    harness.failSeedConnections = 1;
  }

  Future<int> replacementDownload({
    CancelToken? cancelToken,
    Duration rangeDelay = Duration.zero,
  }) => harness.downloadPrefix(
    cancelToken: cancelToken,
    bootstrapPiece: (_) async => null,
    bootstrapHandoff: () async {},
    p8pRangePiece: (index, token) async {
      if (rangeDelay != Duration.zero) await Future<void>.delayed(rangeDelay);
      final start = index * 1048576;
      return Uint8List.sublistView(
        harness.bytes,
        start,
        (start + 1048576).clamp(0, harness.bytes.length),
      );
    },
  );

  void replacementFixture({bool supported = true}) {
    multisourceFixture(peer: true);
    harness.manifestOverride['peer_candidate_replacement_supported'] =
        supported;
    harness.seedBusy = true;
    harness.trackPeerOwners = true;
    harness.advertisedPeerIds = [_other, _second, _third, _fourth];
    harness.rejectedPeerIds.addAll([_other, _second]);
  }

  for (final mode in [
    'enabled',
    'default_off',
    'old_node',
    'unknown',
    'legacy',
  ]) {
    test('source diversity opt-in $mode preserves the real peer path', () async {
      multisourceFixture(peer: true);
      harness.seedBusy = true;
      harness.offerSdpOverride =
          'v=0\r\na=ice-ufrag:unitufrag\r\na=ice-pwd:abcdefghijklmnopqrstuvwx\r\n'
          'm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\na=sctp-port:5000\r\n';
      if (mode != 'old_node') {
        harness.diversityAdvice = {
          'version': mode == 'unknown' ? 99 : 1,
          'strategy': P8PSourceDiversity.strategy,
          'max_sockets': 4,
          'from_peer_id': 'untrusted',
          'attempt_id': 'untrusted',
          'targets': ['untrusted'],
        };
      }
      harness.client = harness.makeClient(
        hybridStartup: true,
        enableP8P: mode != 'legacy',
        p8pSourcePortDiversity: mode != 'default_off',
      );
      expect(await replacementDownload(), harness.bytes.length);
      final discovery = harness.requests.where(
        (r) => r.uri.pathSegments.last == 'peers',
      );
      expect(discovery, isNotEmpty);
      expect(
        discovery.any((r) => r.uri.queryParameters['ice_diversity'] == '1'),
        mode != 'default_off' && mode != 'legacy',
      );
      final offers = harness.requests.where(
        (r) =>
            r.uri.pathSegments.last == 'signal' &&
            (r.data as Map)['type'] == 'offer',
      );
      expect(offers, isNotEmpty);
      for (final request in offers) {
        final data = request.data as Map;
        if (mode == 'enabled') {
          expect(data['ice_diversity'], {
            'version': 1,
            'strategy': P8PSourceDiversity.strategy,
            'max_sockets': 4,
            'ice_generation': P8PSourceDiversity.iceGeneration(
              data['sdp'] as String,
            ),
          });
        } else {
          expect(data.containsKey('ice_diversity'), false);
        }
      }
      await harness.client.close();
      expect(harness.peers.every((peer) => peer.disposed), true);
    });
  }

  test(
    'three-peer mode tries the spare before two stalled offers expire',
    () async {
      replacementFixture();
      harness.rejectedPeerIds.clear();
      harness.seedBusy = true;
      harness.manifestOverride['p2p_connect_timeout_ms'] = 8000;
      harness.client = harness.makeClient(
        hybridStartup: true,
        enableP8P: true,
        p8pPeerRaceLimit: 3,
      );
      final gate = Completer<void>(), firstTwo = Completer<void>();
      final spare = Completer<void>();
      final offers = <String>[];
      harness.signalOfferHook = (request) async {
        final id = (request.data as Map)['peer_id'] as String;
        offers.add(id);
        if (id == _other || id == _second) {
          if (offers.length == 2) firstTwo.complete();
          await gate.future;
        } else if (id == _third) {
          spare.complete();
        }
      };
      final cancel = CancelToken();
      final download = replacementDownload(cancelToken: cancel);
      final result = download.then<Object>(
        (value) => value,
        onError: (Object error) => error,
      );
      try {
        await firstTwo.future.timeout(const Duration(seconds: 2));
        expect(offers, [_other, _second]);
        await spare.future.timeout(const Duration(seconds: 4));
        expect(offers, [_other, _second, _third]);
        final hedge = harness.logs.singleWhere(
          (e) => e.code == 'peer_staggered_probe',
        );
        expect(hedge.peerCount, 3);
        expect(harness.peakOrdinaryOwners, 3);
        gate.complete();
        expect(
          await result.timeout(const Duration(seconds: 12)),
          harness.bytes.length,
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
        cancel.cancel('fixture cleanup');
        await result;
        await harness.client.close();
      }
      expect(harness.peers.every((p) => p.disposed), true);
    },
  );

  test(
    'three-peer mode tries the spare when an open channel has no first piece',
    () async {
      replacementFixture();
      harness.rejectedPeerIds.clear();
      harness.advertisedPeerIds = [_other, _second, _third];
      harness.manifestOverride['p2p_connect_timeout_ms'] = 8000;
      harness.precomputedDigest = sha256.convert(harness.bytes).toString();
      harness.precomputedManifest = Map<String, dynamic>.from(
        harness.manifestJson,
      );
      harness.client = harness.makeClient(
        hybridStartup: true,
        enableP8P: true,
        p8pPeerRaceLimit: 3,
        sourceTimeout: const Duration(seconds: 7),
      );
      final firstRequested = Completer<void>();
      final spareRequested = Completer<void>();
      final secondGate = Completer<void>();
      harness.signalOfferHook = (request) async {
        if ((request.data as Map)['peer_id'] == _second) {
          await secondGate.future;
        }
      };
      harness.beforeLeasedPiece = (channel, _, stopped) async {
        final peer = harness.peers.singleWhere(
          (p) => identical(p.channel, channel),
        );
        if (peer.target == _other) {
          if (!firstRequested.isCompleted) firstRequested.complete();
          await stopped;
        } else if (peer.target == _third && !spareRequested.isCompleted) {
          spareRequested.complete();
        }
      };
      final cancel = CancelToken();
      final result = replacementDownload(
        cancelToken: cancel,
      ).then<Object>((value) => value, onError: (Object error) => error);
      try {
        await firstRequested.future.timeout(const Duration(seconds: 3));
        await spareRequested.future.timeout(const Duration(seconds: 4));
        expect(
          harness.logs.where((e) => e.code == 'peer_staggered_probe'),
          hasLength(1),
        );
        expect(harness.peakOrdinaryOwners, 3);
        final request = harness.requests.firstWhere(
          (r) => r.uri.pathSegments.last == 'session',
        );
        expect((request.data as Map)['sdk_version'], '1.1.8');
        secondGate.complete();
        expect(
          await result.timeout(const Duration(seconds: 15)),
          harness.bytes.length,
        );
      } finally {
        if (!secondGate.isCompleted) secondGate.complete();
        cancel.cancel('fixture cleanup');
        await result;
        await harness.client.close();
      }
      expect(harness.peers.every((peer) => peer.disposed), true);
    },
  );

  test(
    'a previously verified registration is tried before unknown peers',
    () async {
      replacementFixture();
      harness.advertisedPeerIds = [_third];
      final first = await replacementDownload();
      expect(first, harness.bytes.length);
      expect(
        harness.logs.any(
          (e) => e.code == 'piece_verified' && e.source == 'peer',
        ),
        true,
      );
      await harness.part.delete();
      await _settle();
      harness.rejectedPeerIds.clear();
      harness.advertisedPeerIds = [_other, _second, _third];
      final offers = <String>[];
      harness.signalOfferHook = (request) async {
        offers.add((request.data as Map)['peer_id'] as String);
      };
      expect(await replacementDownload(), harness.bytes.length);
      expect(offers.first, _third);
      expect(offers.take(2), containsAll([_third, _other]));
      await harness.client.close();
    },
  );

  test('four-peer trial starts four offers before any answer', () async {
    replacementFixture();
    harness.rejectedPeerIds.clear();
    harness.manifestOverride['p2p_connect_timeout_ms'] = 8000;
    harness.client = harness.makeClient(
      hybridStartup: true,
      enableP8P: true,
      p8pPeerRaceLimit: 4,
      sourceTimeout: const Duration(seconds: 8),
    );
    final offers = <String>{};
    final fourStarted = Completer<void>(), answerGate = Completer<void>();
    harness.signalOfferHook = (request) async {
      offers.add((request.data as Map)['peer_id'] as String);
      if (offers.length == 4 && !fourStarted.isCompleted) {
        fourStarted.complete();
      }
      await answerGate.future;
    };
    final download = replacementDownload(
      rangeDelay: const Duration(milliseconds: 150),
    );
    try {
      await fourStarted.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          fail(
            'offers=$offers peers=${harness.peers.length} '
            'events=${harness.logs.map((e) => '${e.source}/${e.code}').toList()}',
          );
        },
      );
      expect(offers, {_other, _second, _third, _fourth});
      expect(harness.peakOrdinaryOwners, 4);
      answerGate.complete();
      expect(
        await download.timeout(const Duration(seconds: 8)),
        harness.bytes.length,
      );
      final admitted = harness.logs
          .where(
            (e) => e.code == 'piece_request_allocated' && e.source == 'peer',
          )
          .toList();
      expect(admitted.length, 2);
      expect(
        harness.logs.singleWhere((e) => e.code == 'peer_race_profile').metrics,
        containsPair('peak_ordinary_peer_owners', 4),
      );
      await harness.client.close();
      expect(harness.peers.every((p) => p.disposed), true);
    } finally {
      if (!answerGate.isCompleted) answerGate.complete();
      harness.client.cancelDownload();
      try {
        await download;
      } catch (_) {}
      await harness.client.close();
    }
  });

  for (final supported in [true, false]) {
    test(
      'four-peer trial keeps two slots for ${supported ? 'default' : 'unnegotiated'} policy',
      () async {
        replacementFixture(supported: supported);
        harness.rejectedPeerIds.clear();
        harness.client = harness.makeClient(
          hybridStartup: true,
          enableP8P: true,
          p8pPeerRaceLimit: supported ? 2 : 4,
        );
        final gate = Completer<void>(), twoStarted = Completer<void>();
        final offers = <String>{};
        harness.signalOfferHook = (request) async {
          if ((request.data as Map)['type'] != 'offer') return;
          offers.add((request.data as Map)['peer_id'] as String);
          if (offers.length == 2 && !twoStarted.isCompleted) {
            twoStarted.complete();
          }
          await gate.future;
        };
        final download = replacementDownload();
        try {
          await twoStarted.future.timeout(const Duration(seconds: 2));
          await Future<void>.delayed(Duration.zero);
          expect(offers.length, 2);
          expect(harness.peakOrdinaryOwners, 2);
        } finally {
          harness.client.cancelDownload();
          gate.complete();
          try {
            await download;
          } catch (_) {}
          await harness.client.close();
        }
        expect(harness.peers.every((p) => p.disposed), true);
        expect(
          harness.logs.where((e) => e.code == 'peer_race_profile'),
          isEmpty,
        );
      },
    );
  }

  test(
    'four-peer trial cancellation owns all pending native factories',
    () async {
      replacementFixture();
      harness.client = harness.makeClient(
        hybridStartup: true,
        enableP8P: true,
        p8pPeerRaceLimit: 4,
        sourceTimeout: const Duration(seconds: 8),
      );
      final created = Completer<void>(), factoryGate = Completer<void>();
      harness.creationGate = factoryGate.future;
      harness.onPeerCreated = () {
        if (harness.peers.length == 5 && !created.isCompleted) {
          created.complete();
        }
      };
      final cancel = CancelToken();
      final download = replacementDownload(cancelToken: cancel);
      try {
        await created.future.timeout(const Duration(seconds: 2));
        cancel.cancel('trial_cancel');
        await Future<void>.delayed(Duration.zero);
        expect(harness.peers.length, 5); // One seed plus four ordinary owners.
        expect(harness.peers.every((p) => !p.disposed), true);
        expect(
          harness.requests.where((r) => r.uri.pathSegments.last == 'signal'),
          isEmpty,
        );
      } finally {
        factoryGate.complete();
        try {
          await download;
        } catch (_) {}
        await harness.client.close();
      }
      expect(harness.peers.length, 5);
      expect(harness.peers.every((p) => p.disposed), true);
      expect(
        harness.requests.where((r) => r.uri.pathSegments.last == 'signal'),
        isEmpty,
      );
    },
  );

  test(
    'four-peer trial failure keeps native ownership and stops at four identities',
    () async {
      replacementFixture();
      harness.client = harness.makeClient(
        hybridStartup: true,
        enableP8P: true,
        p8pPeerRaceLimit: 4,
      );
      harness.advertisedPeerIds!.add('ffffffffffffffffffffffffffffffff');
      harness.rejectedPeerIds.addAll(harness.advertisedPeerIds!);
      harness.failOrdinaryDispose = true;
      try {
        expect(await replacementDownload(), lessThan(harness.bytes.length));
        final offered = harness.requests
            .where(
              (r) =>
                  r.uri.pathSegments.last == 'signal' &&
                  (r.data as Map)['type'] == 'offer',
            )
            .toList();
        expect(offered.length, 4);
        expect(harness.peakOrdinaryOwners, 4);
        expect(
          harness.peers.where((p) => p.server != true && !p.disposed).length,
          4,
        );
        expect(
          harness.logs.any((e) => e.code == 'native_dispose_failed'),
          true,
        );
      } finally {
        harness.failOrdinaryDispose = false;
        for (final peer in harness.peers) {
          await peer.dispose();
        }
        await harness.client.close();
      }
    },
  );

  Future<void> standbyCase({
    bool holdDisposal = false,
    bool cancelDuringRetirement = false,
    bool failDisposal = false,
  }) async {
    replacementFixture();
    harness.rejectedPeerIds.clear();
    harness.precomputedDigest = sha256.convert(harness.bytes).toString();
    harness.precomputedManifest = Map<String, dynamic>.from(
      harness.manifestJson,
    );
    harness.client = harness.makeClient(
      hybridStartup: true,
      enableP8P: true,
      p8pPeerRaceLimit: 4,
      timeouts: const AppUpgradeP2PTimeouts(
        rtcOperation: Duration(seconds: 2),
        iceGathering: Duration(seconds: 2),
        answer: Duration(seconds: 2),
        channel: Duration(seconds: 2),
        transfer: Duration(milliseconds: 350),
      ),
    );
    final offers = <String>{},
        silentRequests = <String>{},
        healthyRequests = <String>{};
    final allOffers = Completer<void>(), healthyHello = Completer<void>();
    final disposing = Completer<void>(), disposeGate = Completer<void>();
    final cancel = CancelToken();
    harness.failOrdinaryDispose = failDisposal;
    if (holdDisposal) {
      harness.ordinaryDisposeGates[_other] = disposeGate.future;
      harness.ordinaryDisposeGates[_second] = disposeGate.future;
    }
    harness.ordinaryDisposeStarted = (id) {
      if ((id == _other || id == _second) && !disposing.isCompleted) {
        disposing.complete();
      }
    };
    harness.signalOfferHook = (request) async {
      if ((request.data as Map)['type'] != 'offer') return;
      offers.add((request.data as Map)['peer_id'] as String);
      if (offers.length == 4 && !allOffers.isCompleted) {
        allOffers.complete();
      }
      await allOffers.future;
    };
    String? target(_FakeChannel channel) =>
        harness.peers.singleWhere((p) => identical(p.channel, channel)).target;
    harness.beforeLeaseHello = (channel) async {
      if (target(channel) == _third || target(channel) == _fourth) {
        await healthyHello.future;
      }
    };
    harness.beforeLeasedPiece = (channel, _, stopped) async {
      final id = target(channel)!;
      if (id == _other || id == _second) {
        silentRequests.add(id);
        if (silentRequests.length == 2 && !healthyHello.isCompleted) {
          healthyHello.complete();
        }
        await stopped;
      } else {
        healthyRequests.add(id);
      }
    };
    Object? failure;
    var done = false;
    final download =
        replacementDownload(
              cancelToken: cancel,
              rangeDelay: const Duration(milliseconds: 50),
            )
            .then<int>(
              (value) => value,
              onError: (Object error) {
                failure = error;
                return -1;
              },
            )
            .whenComplete(() => done = true);
    try {
      if (holdDisposal) {
        await disposing.future.timeout(const Duration(seconds: 2));
        expect(
          harness.logs
              .where((e) => e.code == 'hello_ready' && e.source == 'peer')
              .length,
          4,
        );
        expect(healthyRequests, isEmpty);
        expect(
          harness.peers.where((p) => p.server != true && !p.disposed).length,
          4,
        );
        if (cancelDuringRetirement) cancel.cancel('cancel_while_standby_waits');
        disposeGate.complete();
      }
      final received = await download;
      expect(offers.length, 4);
      expect(silentRequests.length, 2);
      if (cancelDuringRetirement) {
        expect(failure, isA<DioException>());
        expect(CancelToken.isCancel(failure as DioException), true);
        expect(healthyRequests, isEmpty);
      } else if (failDisposal) {
        expect(received, lessThan(harness.bytes.length));
        expect(healthyRequests, isEmpty);
        expect(
          harness.logs.any((e) => e.code == 'native_dispose_failed'),
          true,
        );
      } else {
        expect(
          healthyRequests,
          isNotEmpty,
          reason:
              'Hello-ready 0B sources must not discard already connecting healthy candidates',
        );
        expect(received, harness.bytes.length);
      }
    } finally {
      if (!done) cancel.cancel('standby_fixture_teardown');
      if (!disposeGate.isCompleted) disposeGate.complete();
      if (!allOffers.isCompleted) allOffers.complete();
      if (!healthyHello.isCompleted) healthyHello.complete();
      await download;
      if (failDisposal) {
        harness.failOrdinaryDispose = false;
        for (final peer in harness.peers) {
          await peer.dispose();
        }
      }
      await harness.client.close();
    }
    expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(4));
    expect(harness.peers.every((p) => p.disposed), true);
  }

  test(
    'four-peer standby survives two hello-ready sources with zero body',
    () => standbyCase(),
  );
  test(
    'four-peer standby waits for real disposal before body admission',
    () => standbyCase(holdDisposal: true),
  );
  test(
    'four-peer standby cancellation during retirement admits no body',
    () => standbyCase(holdDisposal: true, cancelDuringRetirement: true),
  );
  test(
    'four-peer standby failed native disposal cannot grant admission',
    () => standbyCase(failDisposal: true),
  );

  Future<void> admittedBodyFailureCase({
    bool holdSecondClose = false,
    bool cancelDuringClose = false,
    bool supported = true,
  }) async {
    replacementFixture(supported: supported);
    harness.rejectedPeerIds.clear();
    harness.seedBusy = false;
    harness.bytes = Uint8List.fromList(
      List.generate(32 * 1048576 + 79, (i) => i % 251),
    );
    harness.advertisedPieces = List.generate(33, (i) => i);
    harness.pieceDelay = const Duration(milliseconds: 300);
    // This fixture's release is immutable. Hash it before starting clocks;
    // repeated synthetic hello hashing must not stall unrelated live leases.
    harness.precomputedDigest = sha256.convert(harness.bytes).toString();
    harness.precomputedManifest = Map<String, dynamic>.from(
      harness.manifestJson,
    );
    final secondClose = Completer<void>(), thirdOffer = Completer<void>();
    final secondFailed = Completer<void>(), cancel = CancelToken();
    if (holdSecondClose) {
      harness.ordinaryDisposeGates[_second] = secondClose.future;
      harness.signalOfferHook = (request) async {
        if ((request.data as Map)['peer_id'] == _third &&
            !thirdOffer.isCompleted) {
          thirdOffer.complete();
        }
      };
    }
    final reads = <String, int>{};
    harness.beforeLeasedPiece = (channel, index, stopped) async {
      final peer = harness.peers.singleWhere(
        (peer) => identical(peer.channel, channel),
      );
      final target = peer.target;
      if (target == _other || target == _second) {
        reads.update(target!, (count) => count + 1, ifAbsent: () => 1);
        if (reads[target]! > 1) {
          await channel.close();
          if (target == _second && !secondFailed.isCompleted) {
            secondFailed.complete();
          }
        }
      }
    };
    final download = harness.downloadPrefix(
      cancelToken: cancel,
      bootstrapPiece: (_) async => null,
      bootstrapHandoff: () async {},
      p8pRangePiece: (index, token) async {
        await Future.any([
          Future<void>.delayed(const Duration(milliseconds: 500)),
          token.whenCancel,
        ]);
        if (token.isCancelled) throw token.cancelError!;
        final start = index * 1048576;
        return Uint8List.sublistView(
          harness.bytes,
          start,
          (start + 1048576).clamp(0, harness.bytes.length),
        );
      },
    );
    Object? downloadError;
    final observedDownload = download.then<int>(
      (value) => value,
      onError: (Object error) {
        downloadError = error;
        return -1;
      },
    );
    var replacedBeforeOtherClose = false;
    if (holdSecondClose) {
      try {
        if (cancelDuringClose) {
          await secondFailed.future.timeout(const Duration(seconds: 6));
          cancel.cancel('fixture cancellation during actual retirement');
          await _settle();
        } else {
          await thirdOffer.future.timeout(const Duration(seconds: 6));
          replacedBeforeOtherClose = true;
        }
      } on TimeoutException {
        // Release the fixture gate and observe the actual download before failing.
      } finally {
        secondClose.complete();
      }
    }
    final result = await observedDownload;
    if (cancelDuringClose) {
      expect(downloadError, isA<DioException>());
      expect(CancelToken.isCancel(downloadError as DioException), true);
      expect(
        harness.peers.any((p) => p.target == _third || p.target == _fourth),
        false,
      );
      await harness.client.close();
      expect(harness.peers.every((p) => p.disposed), true);
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
      return;
    }
    expect(downloadError, isNull);
    if (holdSecondClose) {
      expect(
        replacedBeforeOtherClose,
        true,
        reason: 'One pending native close cannot block the other retired slot',
      );
    }
    expect(
      result,
      harness.bytes.length,
      reason: jsonEncode({
        'reads': reads,
        'events': harness.logs.map((e) => e.toJson()).toList(),
        'peers': harness.peers
            .map(
              (p) => {
                'target': p.target,
                'closed': p.closed,
                'disposed': p.disposed,
              },
            )
            .toList(),
      }),
    );
    expect(reads[_other], greaterThan(1));
    expect(reads[_second], greaterThan(1));
    final offered = harness.requests
        .where((r) => r.uri.pathSegments.last == 'signal')
        .map((r) => (r.data as Map)['peer_id'])
        .toList();
    if (!supported) {
      expect(offered, isNot(contains(_third)));
      expect(offered, isNot(contains(_fourth)));
    } else {
      expect(offered, contains(_third));
    }
    final profiles = harness.logs.where((e) => e.code == 'source_profile');
    expect(
      profiles.any(
        (e) =>
            e.attempt == 'peer3' &&
            (e.metrics['source_peer3_verified_bytes'] ?? 0) > 0,
      ),
      supported,
      reason: jsonEncode(profiles.map((e) => e.toJson()).toList()),
    );
    expect(
      sha256.convert(await harness.part.readAsBytes()).toString(),
      harness.info.sha256,
    );
    expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
    final profile = harness.logs.lastWhere(
      (e) => e.code == 'multisource_profile',
    );
    expect(profile.metrics['peak_reservations'], lessThanOrEqualTo(4));
    expect(
      profile.metrics['peak_reserved_bytes'],
      lessThanOrEqualTo(4 * 1048576),
    );
    await harness.client.close();
    expect(harness.peers.every((p) => p.disposed), true);
  }

  test(
    'P8P replaces admitted peers that fail during body transfer',
    () => admittedBodyFailureCase(),
  );
  test(
    'P8P replaces a failed admitted peer while another native close is pending',
    () => admittedBodyFailureCase(holdSecondClose: true),
  );
  test(
    'P8P cancellation during admitted source retirement starts no replacement',
    () =>
        admittedBodyFailureCase(holdSecondClose: true, cancelDuringClose: true),
  );
  test(
    'P8P body replacement requires the negotiated optional capability',
    () => admittedBodyFailureCase(supported: false),
  );

  test(
    'P8P fills a retired slot while another candidate is still negotiating',
    () async {
      replacementFixture();
      harness.rejectedPeerIds
        ..clear()
        ..add(_second);
      harness.suppressFirstAnswer = true;
      bool? firstStillAlive;
      harness.signalOfferHook = (request) async {
        if ((request.data as Map)['peer_id'] == _third) {
          firstStillAlive = harness.peers.any(
            (p) => p.target == _other && !p.closed,
          );
        }
      };
      expect(
        await replacementDownload(),
        harness.bytes.length,
        reason: jsonEncode({
          'events': harness.logs.map((e) => e.toJson()).toList(),
          'owners': harness.peers
              .map(
                (p) => {
                  'target': p.target,
                  'closed': p.closed,
                  'disposed': p.disposed,
                },
              )
              .toList(),
        }),
      );
      expect(firstStillAlive, true);
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
      await harness.client.close();
      expect(harness.peers.every((p) => p.disposed), true);
    },
  );

  Future<void> backgroundReplacementCase({
    required bool seedProof,
    bool cancelDuringHello = false,
  }) async {
    replacementFixture();
    harness.advertisedPeerIds = [_other, _second, _third];
    harness.seedBusy = !seedProof;
    if (!seedProof) harness.dropIndex = 0;
    harness.manifestOverride['p2p_connect_timeout_ms'] = 2000;
    harness.pieceDelay = const Duration(milliseconds: 80);
    // Keep deliberately gated body reads alive while testing the separate
    // two-second startup/connection clock, rather than their piece deadline.
    harness.client = harness.makeClient(
      hybridStartup: true,
      enableP8P: true,
      sourceTimeout: const Duration(seconds: 6),
    );
    final bodyGate = Completer<void>();
    final helloStarted = Completer<void>();
    final cancel = CancelToken();
    harness.signalOfferHook = (request) async {
      final id = (request.data as Map)['peer_id'];
      if (id == _other || id == _second) {
        await Future<void>.delayed(const Duration(milliseconds: 1450));
      }
    };
    harness.beforeLeasedPiece = (channel, index, stopped) async {
      if (index > 0 &&
          harness.peers.any(
            (p) => identical(p.channel, channel) && p.server == true,
          )) {
        await Future.any([bodyGate.future, stopped]);
      }
    };
    harness.beforeLeaseHello = (channel) async {
      if (harness.peers.any(
        (p) => identical(p.channel, channel) && p.target == _third,
      )) {
        if (!helloStarted.isCompleted) helloStarted.complete();
        await Future<void>.delayed(const Duration(milliseconds: 950));
      }
    };
    final download = harness.downloadPrefix(
      cancelToken: cancel,
      bootstrapPiece: (_) async => null,
      bootstrapHandoff: () async {},
      p8pRangePiece: (index, cancel) async {
        await Future.any([bodyGate.future, cancel.whenCancel]);
        if (cancel.isCancelled) throw cancel.cancelError!;
        final start = index * 1048576;
        return Uint8List.sublistView(
          harness.bytes,
          start,
          (start + 1048576).clamp(0, harness.bytes.length),
        );
      },
    );
    try {
      if (!seedProof) {
        expect(await download, lessThan(harness.bytes.length));
        expect(harness.logs.any((e) => e.code == 'probe_verified'), false);
        expect(
          harness.logs.any(
            (e) =>
                e.stage == 'result_reason' && e.code == 'p2p_budget_exhausted',
          ),
          true,
        );
        expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
        return;
      }
      await helloStarted.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          throw StateError(
            'fixture_no_third_hello:${jsonEncode(harness.logs.map((e) => e.toJson()).toList())}',
          );
        },
      );
      if (cancelDuringHello) {
        final offered = harness.requests
            .where((r) => r.uri.pathSegments.last == 'signal')
            .length;
        cancel.cancel('cancel_background_handshake');
        await expectLater(
          download,
          throwsA(
            isA<DioException>().having(
              (e) => e.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        await harness.client.close();
        expect(
          harness.requests
              .where((r) => r.uri.pathSegments.last == 'signal')
              .length,
          offered,
        );
        expect(harness.peers.every((p) => p.disposed), true);
        expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final third = harness.peers.singleWhere((p) => p.target == _third);
      expect(
        third.closed,
        !seedProof,
        reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
      );
      if (!bodyGate.isCompleted) bodyGate.complete();
      if (seedProof) {
        expect(await download, harness.bytes.length);
        expect(
          sha256.convert(await harness.part.readAsBytes()).toString(),
          harness.info.sha256,
        );
      } else {
        expect(await download, lessThan(harness.bytes.length));
      }
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
    } finally {
      if (!bodyGate.isCompleted) bodyGate.complete();
      try {
        await download;
      } catch (_) {}
      await harness.client.close();
    }
    expect(harness.peers.every((p) => p.disposed), true);
  }

  test(
    'P8P replacement after verified handoff uses the bounded background clock',
    () async {
      await backgroundReplacementCase(seedProof: true);
    },
  );

  test(
    'P8P replacement without a verified handoff retains the startup deadline',
    () async {
      await backgroundReplacementCase(seedProof: false);
    },
  );

  test(
    'P8P cancellation retires a background replacement awaiting its handshake',
    () async {
      await backgroundReplacementCase(seedProof: true, cancelDuringHello: true);
    },
  );

  test(
    'P8P replaces two failed candidates and verifies the full file',
    () async {
      replacementFixture();
      expect(await replacementDownload(), harness.bytes.length);
      expect(
        sha256.convert(await harness.part.readAsBytes()).toString(),
        harness.info.sha256,
      );
      final offered = harness.requests
          .where(
            (r) =>
                r.uri.pathSegments.last == 'signal' &&
                (r.data as Map)['type'] == 'offer',
          )
          .map((r) => (r.data as Map)['peer_id'])
          .toList();
      expect(offered.take(2), [_other, _second]);
      expect(offered, contains(_third));
      expect(offered.toSet().length, offered.length);
      expect(offered.length, lessThanOrEqualTo(4));
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
      expect(
        harness.logs.any(
          (e) => e.attempt == 'peer3' && e.code == 'piece_verified',
        ),
        true,
      );
      expect(
        harness.logs
            .lastWhere((e) => e.code == 'multisource_profile')
            .metrics['peak_reservations'],
        lessThanOrEqualTo(4),
      );
      expect(harness.peers.every((p) => p.disposed), true);
    },
  );

  test('P8P does not replace candidates without server capability', () async {
    replacementFixture(supported: false);
    // The old service retains its existing v1 fallback; only the new leased
    // candidate replacement requires the optional capability.
    expect(await replacementDownload(), harness.bytes.length);
    expect(
      harness.peers
          .where(
            (p) =>
                p.server != true &&
                p.channel.channelLabel == P8PTransferProtocol.channel,
          )
          .length,
      2,
    );
    expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
  });

  test(
    'P8P renewed registration cannot repeat an installation attempt',
    () async {
      replacementFixture();
      harness.manifestOverride['peer_candidate_identity_supported'] = true;
      harness.peerCandidateKeys.addAll({
        _other: '1' * 64,
        _second: '2' * 64,
        _third: '1' * 64,
        _fourth: '3' * 64,
      });
      harness.peersHook = () async {
        final offered = harness.requests
            .where((r) => r.uri.pathSegments.last == 'signal')
            .length;
        harness.advertisedPeerIds = offered < 2
            ? [_other, _second]
            : [_third, _fourth];
      };
      expect(await replacementDownload(), harness.bytes.length);
      final offered = harness.requests
          .where((r) => r.uri.pathSegments.last == 'signal')
          .map((r) => (r.data as Map)['peer_id'])
          .toList();
      expect(offered, [_other, _second, _fourth]);
      expect(
        harness.requests
            .where(
              (r) =>
                  r.uri.pathSegments.last == 'peers' &&
                  r.uri.queryParameters['candidate_identity'] == '1',
            )
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
      // The compatibility download can return before best-effort receive
      // cleanup. The public engine closes this client before retiring HTTP.
      await harness.client.close();
      expect(harness.peers.every((p) => p.disposed), true);
      expect(
        jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
        isNot(contains('installation:')),
      );
    },
  );

  test(
    'P8P duplicate candidate keys do not occupy both physical slots',
    () async {
      replacementFixture();
      harness.manifestOverride['peer_candidate_identity_supported'] = true;
      harness.peerCandidateKeys.addAll({
        _other: '1' * 64,
        _second: '1' * 64,
        _third: '2' * 64,
      });
      expect(await replacementDownload(), harness.bytes.length);
      final offered = harness.requests
          .where((r) => r.uri.pathSegments.last == 'signal')
          .map((r) => (r.data as Map)['peer_id'])
          .toList();
      expect(offered, contains(_other));
      expect(offered, contains(_third));
      expect(offered, isNot(contains(_second)));
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
    },
  );

  test(
    'P8P malformed identity hints preserve session-based fallback',
    () async {
      replacementFixture();
      harness.manifestOverride['peer_candidate_identity_supported'] = true;
      harness.peerCandidateKeys.addAll({
        _other: 'invalid',
        _second: 'invalid',
        _third: 123,
      });
      expect(await replacementDownload(), harness.bytes.length);
      expect(
        harness.requests
            .where((r) => r.uri.pathSegments.last == 'signal')
            .length,
        inInclusiveRange(3, 4),
      );
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
    },
  );

  test(
    'P8P replaces failed handshake candidates after actual disposal',
    () async {
      replacementFixture();
      harness.rejectedPeerIds.clear();
      harness.badPeerHellos = 2;
      expect(await replacementDownload(), harness.bytes.length);
      expect(
        sha256.convert(await harness.part.readAsBytes()).toString(),
        harness.info.sha256,
      );
      expect(harness.badPeerHellos, 0);
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
      expect(harness.peers.every((p) => p.disposed), true);
      expect(
        harness.logs.any(
          (e) => e.attempt == 'peer3' && e.code == 'piece_verified',
        ),
        true,
      );
    },
  );

  test(
    'P8P keeps failed native owners until actual disposal before replacement',
    () async {
      replacementFixture();
      final gate = Completer<void>();
      harness.ordinaryDisposeGate = gate.future;
      final download = replacementDownload();
      try {
        final until = Stopwatch()..start();
        while (harness.requests
                    .where((r) => r.uri.pathSegments.last == 'signal')
                    .length <
                2 &&
            until.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          harness.requests
              .where((r) => r.uri.pathSegments.last == 'signal')
              .length,
          2,
        );
        expect(
          harness.peers.where((p) => p.server != true && !p.disposed).length,
          2,
        );
        gate.complete();
        expect(await download, harness.bytes.length);
        expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
      } finally {
        if (!gate.isCompleted) gate.complete();
        try {
          await download;
        } catch (_) {}
      }
    },
  );

  test(
    'P8P candidate attempt budget stops after four failed identities',
    () async {
      replacementFixture();
      harness.advertisedPeerIds = [
        _other,
        _second,
        _third,
        _fourth,
        'ffffffffffffffffffffffffffffffff',
      ];
      harness.rejectedPeerIds.addAll(harness.advertisedPeerIds!);
      expect(await replacementDownload(), lessThan(harness.bytes.length));
      expect(
        harness.requests
            .where((r) => r.uri.pathSegments.last == 'signal')
            .length,
        4,
      );
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
    },
  );

  test('P8P failed native disposal cannot admit a replacement', () async {
    replacementFixture();
    harness.failOrdinaryDispose = true;
    try {
      expect(await replacementDownload(), lessThan(harness.bytes.length));
      expect(
        harness.requests
            .where((r) => r.uri.pathSegments.last == 'signal')
            .length,
        2,
      );
      expect(harness.peakOrdinaryOwners, lessThanOrEqualTo(2));
      expect(harness.logs.any((e) => e.code == 'native_dispose_failed'), true);
    } finally {
      harness.failOrdinaryDispose = false;
      for (final peer in harness.peers) {
        await peer.dispose();
      }
    }
  });

  test(
    'P8P pending native creation blocks fresh candidate replacement',
    () async {
      replacementFixture();
      final gate = Completer<void>();
      harness.creationGate = gate.future;
      try {
        expect(await replacementDownload(), lessThan(harness.bytes.length));
        // Two seed attempts are separately bounded. Pending ordinary factories
        // must retain both slots even after the Dart operation times out.
        expect(harness.peers.length, inInclusiveRange(3, 4));
        expect(
          harness.requests.where((r) => r.uri.pathSegments.last == 'signal'),
          isEmpty,
        );
        final created = harness.peers.length;
        gate.complete();
        final until = Stopwatch()..start();
        while (harness.peers.any((p) => !p.disposed) &&
            until.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(harness.peers.length, created);
        expect(harness.peers.every((p) => p.disposed), true);
        expect(
          harness.requests.where((r) => r.uri.pathSegments.last == 'signal'),
          isEmpty,
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
      }
    },
  );

  test(
    'P8P cancellation during candidate retirement starts no replacement',
    () async {
      replacementFixture();
      final gate = Completer<void>();
      final cancel = CancelToken();
      harness.ordinaryDisposeGate = gate.future;
      final download = replacementDownload(cancelToken: cancel);
      try {
        final until = Stopwatch()..start();
        while (harness.requests
                    .where((r) => r.uri.pathSegments.last == 'signal')
                    .length <
                2 &&
            until.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        cancel.cancel('candidate_cancel');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          harness.requests
              .where((r) => r.uri.pathSegments.last == 'signal')
              .length,
          2,
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
        try {
          await download;
        } catch (_) {}
      }
      expect(
        harness.requests
            .where((r) => r.uri.pathSegments.last == 'signal')
            .length,
        2,
      );
      expect(harness.peers.every((p) => p.disposed), true);
    },
  );

  test(
    'P8P adds a late peer after the initial connection budget expires',
    () async {
      multisourceFixture();
      harness.bytes = Uint8List.fromList(
        List.generate(12 * 1048576 + 79, (i) => i % 251),
      );
      harness.advertisedPieces = List.generate(13, (i) => i);
      harness.leasePeerCapable = true;
      harness.pieceDelay = const Duration(milliseconds: 300);
      harness.manifestOverride['p2p_connect_timeout_ms'] = 2000;
      var handedOff = false;
      final requested = <int>[];
      final result = await harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {
          handedOff = true;
          // The same release becomes available only after startup discovery.
          harness.advertisePeer = true;
        },
        p8pRangePiece: (index, token) async {
          requested.add(index);
          await Future.any([
            Future<void>.delayed(const Duration(milliseconds: 800)),
            token.whenCancel,
          ]);
          if (token.isCancelled) throw token.cancelError!;
          final start = index * 1048576;
          return Uint8List.sublistView(
            harness.bytes,
            start,
            (start + 1048576).clamp(0, harness.bytes.length),
          );
        },
      );
      expect(handedOff, true);
      expect(
        result,
        harness.bytes.length,
        reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
      );
      expect(
        sha256.convert(await harness.part.readAsBytes()).toString(),
        harness.info.sha256,
      );
      final peerAttempt = harness.logs.where(
        (event) => event.attempt == 'peer1' && event.code == 'piece_verified',
      );
      expect(
        peerAttempt,
        isNotEmpty,
        reason:
            'A same-release node that becomes ready after startup must be usable in the current P8P transfer: ${jsonEncode(harness.logs.where((e) => e.stage == 'peers' || e.stage == 'p8p' || e.source == 'peer' || e.stage == 'performance').map((e) => e.toJson()).toList())}',
      );
      expect(peerAttempt.first.elapsedMs, greaterThan(2000));
      expect(
        harness.paths.where((p) => p == 'peers').length,
        inInclusiveRange(2, 9),
      );
      expect(harness.peers.every((p) => p.closed), true);
      final profile = harness.logs
          .lastWhere((e) => e.code == 'multisource_profile')
          .metrics;
      expect(profile['peak_reservations'], lessThanOrEqualTo(4));
      expect(profile['peak_reserved_bytes'], lessThanOrEqualTo(4 * 1048576));
      final reads = harness.paths.where((p) => p == 'peers').length;
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(
        harness.paths.where((p) => p == 'peers').length,
        reads,
        reason: 'Completed downloads own no discovery timer',
      );
    },
  );

  test(
    'P8P cancellation stops a stalled late discovery without another RTC owner',
    () async {
      multisourceFixture();
      harness.pieceDelay = const Duration(milliseconds: 500);
      final pending = Completer<void>(), secondRead = Completer<void>();
      var reads = 0;
      harness.peersHook = () async {
        if (++reads > 1) {
          if (!secondRead.isCompleted) secondRead.complete();
          await pending.future;
        }
      };
      final cancel = CancelToken();
      final download = harness.downloadPrefix(
        cancelToken: cancel,
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {},
        p8pRangePiece: (index, token) async {
          await token.whenCancel;
          throw token.cancelError!;
        },
      );
      final outcome = expectLater(download, throwsA(isA<DioException>()));
      try {
        await secondRead.future.timeout(
          const Duration(seconds: 6),
          onTimeout: () =>
              fail(jsonEncode(harness.logs.map((e) => e.toJson()).toList())),
        );
        final owners = harness.peers.length;
        cancel.cancel('late discovery cancelled');
        await outcome.timeout(const Duration(seconds: 2));
        pending.complete();
        await _settle();
        expect(harness.peers.length, owners);
        expect(harness.peers.every((p) => p.closed), true);
        final count = reads;
        await Future<void>.delayed(const Duration(milliseconds: 2100));
        expect(reads, count);
      } finally {
        cancel.cancel('fixture cleanup');
        if (!pending.isCompleted) pending.complete();
        await outcome;
      }
    },
  );

  for (final iceStalled in [false, true]) {
    test(
      'P8P late peer timeout ($iceStalled) leaves HTTPS and the seed completing normally',
      () async {
        multisourceFixture();
        harness.bytes = Uint8List.fromList(
          List.generate(24 * 1048576 + 79, (i) => i % 251),
        );
        harness.advertisedPieces = List.generate(25, (i) => i);
        harness.leasePeerCapable = true;
        harness.pieceDelay = const Duration(milliseconds: 600);
        harness.manifestOverride['p2p_connect_timeout_ms'] = 2000;
        harness.suppressAnswer = !iceStalled;
        harness.trackPeerOwners = true;
        if (iceStalled) harness.stalledIcePeerIds.add(_other);
        // Prepare the fake sender's metadata before the connection clock starts.
        // Hashing 24 MiB inside hello can consume this test's 2s ICE budget.
        harness.precomputedDigest = sha256.convert(harness.bytes).toString();
        harness.precomputedManifest = harness.manifestJson;
        // Leave enough normal body work for the 2s late discovery plus its 2s
        // connect budget. Each individual piece keeps the existing timeout.
        final result = await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
          bootstrapHandoff: () async {
            harness.advertisePeer = true;
          },
          p8pRangePiece: (index, token) async {
            await Future.any([
              Future<void>.delayed(const Duration(milliseconds: 800)),
              token.whenCancel,
            ]);
            if (token.isCancelled) throw token.cancelError!;
            final start = index * 1048576;
            return Uint8List.sublistView(
              harness.bytes,
              start,
              (start + 1048576).clamp(0, harness.bytes.length),
            );
          },
        );
        expect(
          result,
          harness.bytes.length,
          reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
        );
        expect(
          sha256.convert(await harness.part.readAsBytes()).toString(),
          harness.info.sha256,
        );
        final failure = harness.logs.where(
          (e) => e.attempt == 'peer1' && e.code == 'peer_connect_timeout',
        );
        final detail = harness.logs.singleWhere(
          (e) => e.attempt == 'peer1' && e.code == 'peer_failure_detail',
        );
        expect(detail.durationMs, greaterThan(0));
        expect(
          detail.toJson()['metrics'],
          containsPair('attempt_answer_seen', iceStalled ? 1 : 0),
        );
        expect(
          detail.toJson()['metrics'],
          containsPair('attempt_channel_opened', 0),
        );
        expect(
          detail.toJson()['metrics'],
          containsPair('attempt_ice_state', iceStalled ? 1 : 0),
        );
        expect(jsonEncode(detail.toJson()), isNot(contains(_other)));

        expect(failure, isNotEmpty);
        final started = harness.logs.firstWhere(
          (e) => e.attempt == 'peer1' && e.code == 'offer_post_started',
        );
        expect(failure.first.elapsedMs! - started.elapsedMs!, lessThan(2600));
        expect(
          harness.requests
              .where(
                (r) =>
                    r.uri.pathSegments.last == 'signal' &&
                    (r.data as Map)['type'] == 'offer',
              )
              .length,
          1,
          reason:
              'A consumed signaling identity must not be reopened by a later scan',
        );
        expect(harness.peers.every((p) => p.closed), true);
      },
    );
  }

  test(
    'P8P imports the full stopped HTTPS prefix before assigning network pieces',
    () async {
      multisourceFixture(peer: true);
      harness.seedBusy = true;
      harness.bytes = Uint8List.fromList(
        List.generate(12 * 1048576 + 79, (i) => i % 251),
      );
      harness.advertisedPieces = List.generate(13, (i) => i);
      const cachedPieces = 7;
      var handedOff = false;
      final httpPieces = <int>[];
      Uint8List piece(int index) {
        final start = index * 1048576;
        return Uint8List.fromList(
          harness.bytes.sublist(
            start,
            (start + 1048576).clamp(0, harness.bytes.length),
          ),
        );
      }

      final length = await harness.downloadPrefix(
        bootstrapReceivedBytes: () => cachedPieces * 1048576,
        bootstrapHandoff: () async {
          expect(harness.part.existsSync(), false);
          handedOff = true;
        },
        bootstrapPiece: (index) async {
          expect(handedOff, true);
          return index < cachedPieces ? piece(index) : null;
        },
        p8pRangePiece: (index, _) async {
          httpPieces.add(index);
          return piece(index);
        },
      );
      expect(length, harness.bytes.length);
      expect(
        sha256.convert(await harness.part.readAsBytes()).toString(),
        harness.info.sha256,
      );
      final requested = harness.peers
          .expand((peer) => peer.channel.sent)
          .where((message) => !message.isBinary)
          .map((message) => jsonDecode(message.text) as Map)
          .where((message) => message['type'] == 'get')
          .map((message) => message['index'] as int)
          .toList();
      expect(
        requested.first,
        3,
        reason: 'The proof stays inside the original four-piece lookahead',
      );
      expect(
        requested.skip(1).where((index) => index < cachedPieces),
        isEmpty,
        reason:
            'Already downloaded pieces beyond the first window must not be fetched again',
      );
      expect(httpPieces.every((index) => index >= cachedPieces), true);
      final metrics = harness.logs
          .lastWhere((event) => event.code == 'multisource_profile')
          .metrics;
      expect(metrics['peak_reservations'], lessThanOrEqualTo(4));
      final sources = harness.logs
          .where((event) => event.code == 'source_profile')
          .toList();
      expect(sources, isNotEmpty);
      expect(sources.length, lessThanOrEqualTo(4));
      expect(sources.any((event) => event.attempt == 'peer1'), true);
      expect(sources.any((event) => event.source == 'https'), true);
      expect(sources.every((event) => event.metrics.length == 5), true);
      expect(
        sources.every(
          (event) =>
              utf8
                  .encode('[AppUpgradeP2P] ${jsonEncode(event.toJson())}')
                  .length <
              800,
        ),
        true,
      );
      expect(metrics.keys.any((key) => key.startsWith('source_peer')), false);

      expect(metrics['peak_reserved_bytes'], lessThanOrEqualTo(4 * 1048576));
      expect(
        harness.client.lastBootstrapUsedBytes,
        (cachedPieces - 1) * 1048576,
      );
      expect(harness.peers.every((peer) => peer.closed), true);
    },
  );

  test(
    'P8P rejects corrupt cached data after the initial import window',
    () async {
      multisourceFixture(peer: true);
      harness.seedBusy = true;
      harness.bytes = Uint8List.fromList(
        List.generate(12 * 1048576 + 79, (i) => i % 251),
      );
      harness.advertisedPieces = List.generate(13, (i) => i);
      final cacheReads = <int>[], networkReads = <int>[];
      var rejected = false, verified = false;
      Uint8List piece(int index) {
        final start = index * 1048576;
        return Uint8List.fromList(
          harness.bytes.sublist(
            start,
            (start + 1048576).clamp(0, harness.bytes.length),
          ),
        );
      }

      final length = await harness.downloadPrefix(
        bootstrapReceivedBytes: () => 7 * 1048576,
        bootstrapHandoff: () async {},
        bootstrapPiece: (index) async {
          cacheReads.add(index);
          if (index >= 7) return null;
          final cached = piece(index);
          if (index == 4) cached[0] ^= 1;
          return cached;
        },
        bootstrapRejected: () => rejected = true,
        p8pRangePiece: (index, _) async {
          networkReads.add(index);
          return piece(index);
        },
        onFileVerified: () => verified = true,
      );
      expect(length, harness.bytes.length);
      expect(verified, true);
      expect(rejected, true);
      expect(cacheReads, contains(4));
      expect(cacheReads.every((index) => index <= 4), true);
      expect(harness.client.lastBootstrapUsedBytes, 3 * 1048576);
      expect(
        sha256.convert(await harness.part.readAsBytes()).toString(),
        harness.info.sha256,
      );
      final remoteReads = harness.peers
          .expand((peer) => peer.channel.sent)
          .where((message) => !message.isBinary)
          .map((message) => jsonDecode(message.text) as Map)
          .where((message) => message['type'] == 'get')
          .map((message) => message['index'] as int);
      expect([...networkReads, ...remoteReads], contains(4));
      expect(harness.peers.every((peer) => peer.closed), true);
    },
  );

  test(
    'P8P cancellation while importing a later cached piece leaves the verified prefix',
    () async {
      multisourceFixture(peer: true);
      harness.seedBusy = true;
      harness.bytes = Uint8List.fromList(
        List.generate(12 * 1048576 + 79, (i) => i % 251),
      );
      harness.advertisedPieces = List.generate(13, (i) => i);
      final entered = Completer<void>(), release = Completer<void>();
      final cancel = CancelToken();
      final download = harness.downloadPrefix(
        cancelToken: cancel,
        bootstrapReceivedBytes: () => 7 * 1048576,
        bootstrapHandoff: () async {},
        bootstrapPiece: (index) async {
          if (index == 4) {
            entered.complete();
            await release.future;
          }
          if (index >= 7) return null;
          final start = index * 1048576;
          return Uint8List.fromList(
            harness.bytes.sublist(start, start + 1048576),
          );
        },
        p8pRangePiece: (_, _) async =>
            throw StateError('Network work must wait for cached import'),
      );
      unawaited(download.then<void>((_) {}, onError: (Object _) {}));
      try {
        await entered.future.timeout(const Duration(seconds: 10));
        expect(await harness.part.length(), 4 * 1048576);
        final cancelled = expectLater(download, throwsA(isA<DioException>()));
        cancel.cancel('fixture_cached_import_cancelled');
        release.complete();
        await cancelled;
        expect(
          await harness.part.readAsBytes(),
          harness.bytes.sublist(0, 4 * 1048576),
        );
        final requested = harness.peers
            .expand((peer) => peer.channel.sent)
            .where((message) => !message.isBinary)
            .map((message) => jsonDecode(message.text) as Map)
            .where((message) => message['type'] == 'get')
            .map((message) => message['index'] as int)
            .toList();
        expect(requested, [3]);
        expect(harness.peers.every((peer) => peer.closed), true);
      } finally {
        if (!release.isCompleted) release.complete();
        cancel.cancel('fixture_cleanup');
        await download.then<void>((_) {}, onError: (Object _) {});
      }
    },
  );

  test(
    'P8P completed multisource download preserves foreground user sharing',
    () async {
      multisourceFixture(peer: true);
      harness.client = harness.makeClient(
        hybridStartup: true,
        enableP8P: true,
        sharingDuration: null,
      );
      final origin = LoopbackPayload(harness.bytes);
      await origin.start();
      final http = Dio()..httpClientAdapter = LoopbackPayloadAdapter(origin);
      final telemetry = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) =>
                h.resolve(Response(requestOptions: r, statusCode: 201)),
          ),
        );
      final downloader = AppUpgradeV40DownloadClient(
        dio: http,
        p2pClient: harness.client,
        httpsHeadStart: true,
        supportDirectoryLoader: () async => directory,
        serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
      );
      Future<void> until(bool Function() ready) async {
        final watch = Stopwatch()..start();
        while (!ready() && watch.elapsed < const Duration(seconds: 10)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(ready(), true);
      }

      int sessions() => harness.paths.where((p) => p == 'session').length;
      try {
        final file = await downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async => harness.info,
          onProgress: (_, _) {},
        );
        expect(
          sha256.convert(await file.readAsBytes()).toString(),
          harness.info.sha256,
        );
        expect(harness.logs.any((e) => e.code == 'multisource_started'), true);
        // Exercise the downloader's automatic verified-cache handoff, rather
        // than calling shareVerifiedFile() directly from the fixture.
        await until(() => sessions() == 2);
        final count = harness.peers.length;
        harness.incomingOffer = true;
        await until(() => harness.peers.length == count + 1);
        final provider = harness.peers.last;
        await until(() => provider.channel.onMessage != null);
        expect(provider.channel.label, 'lifering-apk-p2p-v1');
        provider.channel.receiveText({
          'type': 'get-pieces',
          'indices': [0, 1],
        });
        await until(
          () => provider.channel.sent.where((m) => !m.isBinary).any((m) {
            final body = jsonDecode(m.text) as Map;
            return body['type'] == 'piece-end' && body['index'] == 1;
          }),
        );
        final bytes = BytesBuilder(copy: false);
        for (final message in provider.channel.sent.where((m) => m.isBinary)) {
          bytes.add(message.binary);
        }
        expect(bytes.takeBytes(), harness.bytes.sublist(0, 2 * 1048576));
        harness.client.setForeground(false);
        await until(() => provider.closed);
        final sent = provider.channel.sent.length;
        provider.channel.receiveText({'type': 'get-piece', 'index': 2});
        await _settle();
        expect(provider.channel.sent.length, sent);

        harness.incomingOffer = true;
        harness.client.setForeground(true);
        await until(() => sessions() == 3 && harness.peers.length == count + 2);
        final resumed = harness.peers.last;
        await until(() => resumed.channel.onMessage != null);
        harness.network = AppUpgradeP2PNetwork.cellular;
        harness.events.add('cellular');
        await until(() => resumed.closed);
        harness.client.setForeground(true);
        await _settle();
        expect(sessions(), 3);

        harness.incomingOffer = true;
        harness.network = AppUpgradeP2PNetwork.wifiUnmetered;
        harness.events.add('wifi_unmetered');
        await until(() => sessions() == 4 && harness.peers.length == count + 3);
        final wifi = harness.peers.last;
        await until(() => wifi.channel.onMessage != null);
        harness.client.setSharingEnabled(false);
        await until(() => wifi.closed);
        harness.client.setForeground(true);
        harness.events.add('wifi_unmetered');
        await _settle();
        expect(sessions(), 4);
        expect(harness.client.allowSharing, false);
      } finally {
        await harness.client.stopSharing();
        http.close(force: true);
        telemetry.close(force: true);
        await origin.close();
      }
    },
  );

  test(
    'P8P rejected peer generation is not reopened by legacy fallback',
    () async {
      multisourceFixture(peer: true);
      harness.seedBusy = true;
      harness.rejectSignal = true;
      var handedOff = false;
      final prefix = await harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async => handedOff = true,
        p8pRangePiece: (_, _) async => throw StateError('No verified handoff'),
      );
      final offers = harness.requests.where(
        (request) =>
            request.uri.pathSegments.last == 'signal' &&
            (request.data as Map)['type'] == 'offer' &&
            (request.data as Map)['peer_id'] == _other,
      );
      expect(offers, hasLength(1));
      expect(prefix, 0);
      expect(handedOff, false);
      expect(harness.peers.every((peer) => peer.closed), true);
    },
  );

  test('P8P closed probe cannot recreate the same peer generation', () async {
    multisourceFixture(peer: true);
    harness.seedBusy = true;
    harness.beforeLeasedPiece = (channel, _, _) async => channel.close();
    final prefix = await harness.downloadPrefix(
      bootstrapPiece: (_) async => null,
      bootstrapHandoff: () async {},
      p8pRangePiece: (_, _) async => throw StateError('No verified handoff'),
    );
    final offers = harness.requests.where(
      (request) =>
          request.uri.pathSegments.last == 'signal' &&
          (request.data as Map)['type'] == 'offer' &&
          (request.data as Map)['peer_id'] == _other,
    );
    expect(offers, hasLength(1));
    expect(prefix, 0);
    expect(harness.peers.every((peer) => peer.closed), true);
  });

  test(
    'P8P failed peer does not block a fresh registration or live channel reuse',
    () async {
      multisourceFixture(peer: true);
      harness.seedBusy = true;
      harness.signalPost = () async {
        final offer = harness.requests.lastWhere(
          (request) =>
              request.uri.pathSegments.last == 'signal' &&
              (request.data as Map)['type'] == 'offer',
        );
        final target = (offer.data as Map)['peer_id'];
        harness.rejectSignal = target == _other;
        if (target == _other) harness.firstPeerId = _second;
      };
      final prefix = await harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {},
        p8pRangePiece: (_, _) async => throw StateError('No P8P handoff'),
      );
      final targets = harness.requests
          .where(
            (request) =>
                request.uri.pathSegments.last == 'signal' &&
                (request.data as Map)['type'] == 'offer',
          )
          .map((request) => (request.data as Map)['peer_id'])
          .toList();
      expect(targets, [_other, _second]);
      expect(prefix, harness.bytes.length);
      expect(harness.part.readAsBytesSync(), harness.bytes);
      expect(harness.peers.every((peer) => peer.closed), true);
    },
  );

  test(
    'P8P seed retry waits for local and server close before fresh identity',
    () async {
      seedRetryFixture();
      final closing = Completer<void>(), ack = Completer<void>();
      harness.peerCloseGate = closing.future;
      harness.cancelGate = ack.future;
      final download = harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {},
        p8pRangePiece: (i, token) async {
          final start = i * 1048576;
          return Uint8List.fromList(
            harness.bytes.sublist(
              start,
              (start + 1048576).clamp(0, harness.bytes.length),
            ),
          );
        },
      );
      unawaited(download.then<void>((_) {}, onError: (Object _) {}));
      try {
        await harness.waitForPath('server-offer');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(harness.paths.where((p) => p == 'server-offer'), hasLength(1));
        expect(harness.paths, isNot(contains('server-cancel')));
        closing.complete();
        await harness.waitForPath('server-cancel');
        expect(harness.paths.where((p) => p == 'server-offer'), hasLength(1));
        ack.complete();
        expect(await download, harness.bytes.length);
        expect(harness.part.readAsBytesSync(), harness.bytes);
        final offers = harness.requests
            .where((r) => r.uri.pathSegments.last == 'server-offer')
            .toList();
        expect(offers, hasLength(2));
        expect(
          (offers[0].data as Map)['offer_id'],
          isNot((offers[1].data as Map)['offer_id']),
        );
        expect(
          harness.body('server-cancel')['offer_id'],
          (offers[0].data as Map)['offer_id'],
        );
        expect(
          harness.logs.where((e) => e.code == 'seed_connect_retry'),
          hasLength(1),
        );
        expect(harness.peers.every((p) => p.closed), true);
      } finally {
        if (!closing.isCompleted) closing.complete();
        if (!ack.isCompleted) ack.complete();
        await harness.client.stopSharing();
        await download;
      }
    },
  );

  for (final fault in [
    'pending',
    'wrong_identity',
    'unavailable',
    'old_server',
    'unknown_version',
  ]) {
    test(
      'P8P seed retry refuses unsafe or unsupported cancellation: $fault',
      () async {
        seedRetryFixture();
        if (fault == 'old_server') {
          harness.manifestOverride.remove('server_offer_cancel_supported');
        }
        if (fault == 'unknown_version') {
          harness.manifestOverride['server_offer_cancel_protocol_version'] = 2;
        }
        harness.cancelFault = fault;
        final bytes = await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
          bootstrapHandoff: () async {},
        );
        expect(bytes, 0);
        expect(harness.paths.where((p) => p == 'server-offer'), hasLength(1));
        expect(harness.logs.any((e) => e.code == 'seed_connect_retry'), false);
        expect(
          harness.paths.where((p) => p == 'server-cancel').length,
          fault == 'pending'
              ? 3
              : fault == 'old_server' || fault == 'unknown_version'
              ? 0
              : 1,
        );
      },
    );
  }

  test(
    'P8P seed retry is bounded to two offers when both ICE attempts fail',
    () async {
      seedRetryFixture();
      harness.failSeedConnections = 2;
      expect(
        await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
          bootstrapHandoff: () async {},
        ),
        0,
      );
      expect(harness.paths.where((p) => p == 'server-offer'), hasLength(2));
      expect(harness.paths.where((p) => p == 'server-cancel'), hasLength(1));
    },
  );

  test(
    'P8P seed retry cannot restart after task cancellation while awaiting ACK',
    () async {
      seedRetryFixture();
      final ack = Completer<void>(), cancel = CancelToken();
      harness.cancelGate = ack.future;
      final download = harness.downloadPrefix(
        cancelToken: cancel,
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {},
      );
      await harness.waitForPath('server-cancel');
      final cancelled = expectLater(
        download,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      cancel.cancel('fixture_cancelled');
      ack.complete();
      await cancelled;
      expect(harness.paths.where((p) => p == 'server-offer'), hasLength(1));
    },
  );

  test(
    'P8P seed retry polls pending closure once then uses its final ACK',
    () async {
      seedRetryFixture();
      harness.cancelPending = 1;
      expect(
        await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
          bootstrapHandoff: () async {},
        ),
        harness.bytes.length,
      );
      expect(harness.paths.where((p) => p == 'server-cancel'), hasLength(2));
      expect(harness.paths.where((p) => p == 'server-offer'), hasLength(2));
    },
  );

  test(
    'P8P seed retry shares the original deadline while ICE never opens',
    () async {
      seedRetryFixture();
      // This case never transfers a piece. Keep identity/file preparation small
      // so the unchanged wall-clock assertion measures negotiation and cleanup.
      harness.bytes = Uint8List.sublistView(harness.bytes, 0, 1048576 + 79);
      harness.advertisedPieces = [0, 1];
      harness.failSeedConnections = 0;
      harness.hangSeedConnections = 2;
      harness.manifestOverride['p2p_connect_timeout_ms'] = 4000;
      final watch = Stopwatch()..start();
      expect(
        await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
          bootstrapHandoff: () async {},
        ),
        0,
      );
      expect(harness.paths.where((p) => p == 'server-offer'), hasLength(2));
      expect(harness.paths.where((p) => p == 'server-cancel'), hasLength(1));
      expect(watch.elapsedMilliseconds, lessThan(5500));
      expect(harness.logs.any((e) => e.code == 'p2p_budget_exhausted'), true);
    },
  );

  test(
    'P8P seed channel deadline preserves budget reason before delayed task timers',
    () async {
      seedRetryFixture();
      harness.bytes = Uint8List.sublistView(harness.bytes, 0, 1048576 + 79);
      harness.advertisedPieces = [0, 1];
      harness.failSeedConnections = 0;
      harness.hangSeedConnections = 2;
      harness.manifestOverride['p2p_connect_timeout_ms'] = 4000;
      var delayedTimers = 0, channelTimers = 0;
      await runZoned(
        () async {
          final watch = Stopwatch()..start();
          expect(
            await harness.downloadPrefix(
              bootstrapPiece: (_) async => null,
              bootstrapHandoff: () async {},
            ),
            0,
          );
          // Only competing positive-duration task / outer connect timers are
          // deferred. The channel's actual wait expires on the original clock.
          expect(delayedTimers, greaterThanOrEqualTo(3));
          expect(channelTimers, 2);
          expect(harness.paths.where((p) => p == 'server-offer'), hasLength(2));
          expect(
            harness.paths.where((p) => p == 'server-cancel'),
            hasLength(1),
          );
          expect(watch.elapsedMilliseconds, lessThan(5500));
          await _settle();
          expect(
            harness.body('outcome')['reason_code'],
            'p2p_budget_exhausted',
          );
          expect(
            harness.logs.any((e) => e.code == 'seed_connect_retry_timeout'),
            true,
          );
          expect(harness.peers.every((peer) => peer.closed), true);
          expect(
            harness.part.existsSync() ? await harness.part.length() : 0,
            0,
          );
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final frames = StackTrace.current
                .toString()
                .split('\n')
                .where(
                  (line) => line.contains('app_upgrade_v40_p2p_client.dart:'),
                );
            final owner = frames.isEmpty ? '' : frames.first;
            if (owner.contains('._waitOpen') && duration > Duration.zero) {
              channelTimers++;
            }
            final delay =
                duration > Duration.zero &&
                (owner.contains('._startSession') ||
                    owner.contains('._connect ('));
            if (delay) delayedTimers++;
            return parent.createTimer(
              zone,
              delay ? duration + const Duration(milliseconds: 300) : duration,
              callback,
            );
          },
        ),
      );
    },
  );

  test(
    'P8P seed retry discards a late first Offer response after the fresh transfer',
    () async {
      seedRetryFixture();
      harness.failSeedConnections = 0;
      harness.manifestOverride['p2p_connect_timeout_ms'] = 5000;
      final late = Completer<void>();
      harness.seedOfferHook = (number) async {
        if (number == 1) await late.future;
      };
      try {
        expect(
          await harness.downloadPrefix(
            bootstrapPiece: (_) async => null,
            bootstrapHandoff: () async {},
          ),
          harness.bytes.length,
        );
        expect(harness.peers.first.remoteDescriptionCalls, 0);
        late.complete();
        await _settle();
        expect(harness.peers.first.remoteDescriptionCalls, 0);
        expect(harness.paths.where((p) => p == 'server-offer'), hasLength(2));
        expect(harness.part.readAsBytesSync(), harness.bytes);
      } finally {
        if (!late.isCompleted) late.complete();
      }
    },
  );

  for (final fault in ['recovered', 'unavailable']) {
    test(
      'P8P seed retry retains a progressing HTTP bootstrap: $fault',
      () async {
        seedRetryFixture();
        final ack = Completer<void>();
        harness.cancelGate = ack.future;
        if (fault == 'unavailable') harness.cancelFault = fault;
        final origin = LoopbackPayload(harness.bytes)
          ..bootstrapPause = Duration.zero
          ..chunkDelay = const Duration(milliseconds: 20);
        await origin.start();
        final http = Dio()..httpClientAdapter = LoopbackPayloadAdapter(origin);
        final telemetry = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) =>
                  h.resolve(Response(requestOptions: r, statusCode: 201)),
            ),
          );
        final cancel = CancelToken();
        final downloader = AppUpgradeV40DownloadClient(
          dio: http,
          p2pClient: harness.client,
          httpsHeadStart: true,
          serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
          supportDirectoryLoader: () async => directory,
        );
        final download = downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async => harness.info,
          cancelToken: cancel,
          onProgress: (_, _) {},
        );
        unawaited(download.then<void>((_) {}, onError: (Object _) {}));
        try {
          await harness.waitForPath('server-cancel');
          expect(origin.exchanges, hasLength(1));
          final before = origin.exchanges.single.offeredBytes;
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(origin.exchanges.single.offeredBytes, greaterThan(before));
          expect(origin.exchanges.single.disconnected, false);
          expect(harness.paths.where((p) => p == 'server-offer'), hasLength(1));
          ack.complete();
          final file = await download.timeout(const Duration(seconds: 12));
          expect(
            sha256.convert(await file.readAsBytes()).toString(),
            harness.info.sha256,
          );
          expect(
            harness.paths.where((p) => p == 'server-offer'),
            hasLength(fault == 'recovered' ? 2 : 1),
          );
          if (fault == 'unavailable') {
            expect(origin.exchanges, hasLength(1));
            expect(downloader.lastHttpsBodyBytes, harness.bytes.length);
          }
          await origin.waitIdle();
          expect(origin.errors, isEmpty);
          expect(harness.peers.every((p) => p.closed), true);
        } finally {
          if (!ack.isCompleted) ack.complete();
          cancel.cancel('fixture_done');
          try {
            await download;
          } catch (_) {}
          http.close(force: true);
          await origin.close();
        }
      },
    );
  }

  test('P8P seed retry requires an explicit supported integer capability', () {
    for (final version in [null, '1', 1.0, true, 2, 1]) {
      harness.manifestOverride.addAll({
        'server_offer_cancel_supported': true,
        'server_offer_cancel_protocol_version': version,
      });
      expect(
        harness.parsedManifest().serverOfferCancel,
        version is int && version == 1,
      );
    }
    harness.manifestOverride['server_offer_cancel_supported'] = false;
    expect(harness.parsedManifest().serverOfferCancel, false);
  });

  const routePython = String.fromEnvironment('P8P_ROUTE_PYTHON');
  const routeScript = String.fromEnvironment('P8P_ROUTE_SCRIPT');
  if (routePython.isNotEmpty && routeScript.isNotEmpty) {
    test(
      'P8P real route retries its own released bootstrap admission once',
      () async {
        multisourceFixture();
        final server = await RealRouteServer.launch(
          routePython,
          routeScript,
          0.7,
        );
        harness.bytes = server.bytes;
        harness.manifestOverride['version'] = server.info['version'];
        final prefix = Completer<void>(), accepted = Completer<void>();
        harness.seedGate = prefix.future;
        harness.beforeLeasedPiece = (_, index, stopped) async {
          if (index >= 3) await Future.any([accepted.future, stopped]);
        };
        final info = AppUpgradeInfo(
          releaseId: 'actual-route-release',
          versionName: server.info['version'] as String,
          versionCode: 8900,
          releaseNotes: '',
          forceUpdate: false,
          downloadUrl: _url,
          downloadProtocol: 'APK_SERVICE_V40',
          downloadSlug: 'lifering',
          fileSize: server.bytes.length,
          sha256: server.info['sha256'] as String,
          downloadEtag: server.info['etag'] as String,
        );
        final http = Dio()..httpClientAdapter = LoopbackPayloadAdapter(server);
        final telemetry = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) =>
                  h.resolve(Response(requestOptions: r, statusCode: 201)),
            ),
          );
        final cancel = CancelToken();
        final downloader = AppUpgradeV40DownloadClient(
          dio: http,
          p2pClient: harness.client,
          httpsHeadStart: true,
          supportDirectoryLoader: () async => directory,
          serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
        );
        var done = false;
        final observer = () async {
          while (!done) {
            final state = await server.stats();
            if ((state['events'] as List).any((value) {
                  final event = value as Map;
                  final match = RegExp(
                    r'^bytes=(\d+)-(\d+)$',
                  ).firstMatch(event['range'] as String);
                  return event['status'] == 206 &&
                      match != null &&
                      int.parse(match[2]!) - int.parse(match[1]!) + 1 <=
                          1048576;
                }) &&
                !accepted.isCompleted) {
              accepted.complete();
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        }();
        try {
          final file = await downloader
              .download(
                info: info,
                url: _url,
                backupUrl: null,
                refreshRelease: () async => info,
                cancelToken: cancel,
                onProgress: (received, _) {
                  if (received >= 1048576 && !prefix.isCompleted) {
                    prefix.complete();
                  }
                },
              )
              .timeout(const Duration(seconds: 15));
          expect(
            sha256.convert(await file.readAsBytes()).toString(),
            info.sha256,
          );
          done = true;
          await observer;
          await server.waitIdle();
          final state = await server.stats();
          expect(state['session_count'], 1);
          final duplicates = (state['events'] as List)
              .where((value) => (value as Map)['status'] == 429)
              .cast<Map>()
              .toList();
          expect(duplicates, hasLength(1));
          final retried = (state['events'] as List).cast<Map>().firstWhere(
            (event) =>
                event['range'] == duplicates.single['range'] &&
                event['status'] == 206,
          );
          expect(
            (retried['at_ms'] as int) - (duplicates.single['at_ms'] as int),
            greaterThanOrEqualTo(2000),
          );
          expect(
            harness.logs.where((event) => event.code == 'p8p_contention_wait'),
            hasLength(1),
          );
          expect(
            (state['events'] as List).any(
              (event) => (event as Map)['status'] == 429,
            ),
            true,
          );
          expect(
            accepted.isCompleted,
            true,
            reason:
                'A bounded HTTP source must survive its own delayed bootstrap cleanup',
          );
          expect(
            harness.logs.any((event) => event.code == 'multisource_started'),
            true,
          );
          // Anonymous fixture-only response and timing evidence for replay.
          // ignore: avoid_print
          print(
            'P8P_REAL_ROUTE_RESULT ${jsonEncode({'case': 'own_bootstrap_once', 'verified': true, 'state': state})}',
          );
        } catch (error) {
          done = true;
          await observer;
          // ignore: avoid_print
          print(
            'REAL_ROUTE_FAILURE ${jsonEncode({'error': error.runtimeType.toString(), 'server': await server.stats(), 'diagnostics': harness.logs.map((event) => event.toJson()).toList()})}',
          );
          rethrow;
        } finally {
          done = true;
          cancel.cancel('fixture_done');
          http.close(force: true);
          telemetry.close(force: true);
          await observer;
          await server.close();
        }
      },
    );
    test(
      'P8P real route cancellation releases the actual response and session',
      () async {
        multisourceFixture();
        final server = await RealRouteServer.launch(
          routePython,
          routeScript,
          0.7,
        );
        harness.bytes = server.bytes;
        harness.manifestOverride['version'] = server.info['version'];
        harness.failControlConnection = (request) =>
            !['manifest', 'session'].contains(request.uri.pathSegments.last);
        final info = AppUpgradeInfo(
          releaseId: 'actual-route-cancel',
          versionName: server.info['version'] as String,
          versionCode: 8900,
          releaseNotes: '',
          forceUpdate: false,
          downloadUrl: _url,
          downloadProtocol: 'APK_SERVICE_V40',
          downloadSlug: 'lifering',
          fileSize: server.bytes.length,
          sha256: server.info['sha256'] as String,
          downloadEtag: server.info['etag'] as String,
        );
        final http = Dio()..httpClientAdapter = LoopbackPayloadAdapter(server);
        final telemetry = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) =>
                  h.resolve(Response(requestOptions: r, statusCode: 201)),
            ),
          );
        final token = CancelToken();
        try {
          final client = AppUpgradeV40DownloadClient(
            dio: http,
            p2pClient: harness.client,
            httpsHeadStart: true,
            supportDirectoryLoader: () async => directory,
            serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
          );
          await expectLater(
            client.download(
              info: info,
              url: _url,
              backupUrl: null,
              refreshRelease: () async => info,
              cancelToken: token,
              onProgress: (received, _) {
                if (received >= 262144) {
                  token.cancel('actual_route_user_cancel');
                }
              },
            ),
            throwsA(isA<DioException>()),
          );
          await server.waitIdle();
          final state = await server.stats();
          expect(state['active_handlers'], 0);
          expect(state['active_rows'], 0);
          expect(state['session_count'], 1);
          expect((state['events'] as List).length, 1);
          expect(
            await directory
                .list(recursive: true)
                .where((entry) => entry.path.endsWith('.https-bootstrap'))
                .length,
            0,
          );
          // ignore: avoid_print
          print(
            'P8P_REAL_ROUTE_RESULT ${jsonEncode({'case': 'cancel', 'state': state})}',
          );
        } finally {
          token.cancel('fixture_done');
          http.close(force: true);
          telemetry.close(force: true);
          await server.close();
        }
      },
    );
  }

  for (final fault in [
    'control-outage',
    'range-truncated',
    'node-and-range-loss',
    'cancel',
  ]) {
    test('P8P loopback HTTP recovery $fault', () async {
      multisourceFixture();
      final origin = LoopbackPayload(harness.bytes);
      origin.truncateFirstPiece =
          fault == 'range-truncated' || fault == 'node-and-range-loss';
      final prefixReady = Completer<void>();
      if (origin.truncateFirstPiece) {
        // These cases explicitly exercise reuse, so admit the seed only after
        // the actual HTTP writer reports one complete prefix piece.
        harness.seedGate = prefixReady.future;
      }
      final failedControlHosts = <String>{};
      var controlDown = fault == 'control-outage' || fault == 'cancel';
      harness.failControlConnection = (request) {
        if (controlDown &&
            !['manifest', 'session'].contains(request.uri.pathSegments.last)) {
          failedControlHosts.add(request.uri.host);
          return true;
        }
        return false;
      };
      var nodeClosed = false;
      if (fault == 'node-and-range-loss') {
        harness.beforeLeasedPiece = (channel, index, _) async {
          if (index < 2) return;
          await origin.firstTruncation.future;
          controlDown = true;
          nodeClosed = true;
          await channel.close();
        };
      }
      await origin.start();
      final http = Dio()..httpClientAdapter = LoopbackPayloadAdapter(origin);
      final telemetry = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) => handler.resolve(
              Response(requestOptions: request, statusCode: 201),
            ),
          ),
        );
      final cancel = CancelToken();
      final downloader = AppUpgradeV40DownloadClient(
        dio: http,
        p2pClient: harness.client,
        httpsHeadStart: true,
        serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
        supportDirectoryLoader: () async => directory,
      );
      try {
        final download = downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async => harness.info,
          cancelToken: cancel,
          onProgress: (received, _) {
            if (received >= 1048576 && !prefixReady.isCompleted) {
              prefixReady.complete();
            }
            if (fault == 'cancel' && received >= 262144) {
              cancel.cancel('loopback_user_cancel');
            }
          },
        );
        if (fault == 'cancel') {
          await expectLater(download, throwsA(isA<DioException>()));
        } else {
          final file = await download.timeout(const Duration(seconds: 15));
          expect(
            sha256.convert(await file.readAsBytes()).toString(),
            harness.info.sha256,
          );
        }
        await origin.waitIdle();
        expect(origin.errors, isEmpty);
        expect(harness.peers.every((peer) => peer.closed), true);
        for (final profile in harness.logs.where(
          (event) => event.metrics.containsKey('peak_reservations'),
        )) {
          expect(profile.metrics['peak_reservations'], lessThanOrEqualTo(4));
          expect(
            profile.metrics['peak_reserved_bytes'],
            lessThanOrEqualTo(4 * 1048576),
          );
        }
        expect(
          await directory
              .list(recursive: true)
              .where((file) => file.path.endsWith('.https-bootstrap'))
              .length,
          0,
        );
        if (fault == 'control-outage') {
          expect(
            failedControlHosts,
            {'download1.csnas.asia'},
            reason:
                'The current v1 manifest pins all control endpoints to the backup origin',
          );
          expect(harness.paths, containsAll(['peers', 'server-offer']));
          expect(
            origin.exchanges,
            hasLength(1),
            reason: 'Control failures must retain the SAME HTTP bootstrap',
          );
          expect(downloader.lastHttpsBodyBytes, harness.bytes.length);
          expect(
            harness.logs.any((event) => event.code == 'multisource_started'),
            false,
          );
        }
        if (fault == 'range-truncated' || fault == 'node-and-range-loss') {
          expect(
            origin.exchanges.where((request) => request.truncated),
            hasLength(1),
          );
          expect(
            harness.logs.any((event) => event.code == 'multisource_started'),
            true,
          );
          expect(
            downloader.lastBootstrapUsedBytes,
            greaterThanOrEqualTo(1048576),
          );
        }
        if (fault == 'node-and-range-loss') {
          expect(nodeClosed, true);
          expect(
            origin.exchanges.any(
              (request) =>
                  request.start > 0 &&
                  request.end == harness.bytes.length - 1 &&
                  request.end - request.start + 1 > 1048576,
            ),
            true,
            reason:
                'After both source losses, regular HTTP resumes the verified prefix',
          );
        }
        if (fault == 'cancel') {
          expect(origin.exchanges, hasLength(1));
          expect(downloader.lastHttpsBodyBytes, lessThan(harness.bytes.length));
        }
      } finally {
        cancel.cancel('fixture_done');
        http.close(force: true);
        telemetry.close(force: true);
        await origin.close();
      }
    });
  }

  Future<DefaultRingTransferEngine> lifetimeEngine() async {
    harness.manifestOverride['final_traffic_diagnostics_supported'] = true;
    final http = Dio()..httpClientAdapter = _LifetimeAdapter();
    harness.dio.httpClientAdapter = _LifetimeAdapter();
    final telemetry = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) =>
              h.resolve(Response(requestOptions: r, statusCode: 201)),
        ),
      );
    final downloader = AppUpgradeV40DownloadClient(
      dio: http,
      p2pClient: harness.client,
      serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
      supportDirectoryLoader: () async => directory,
    );
    return DefaultRingTransferEngine.forTesting(
      RingDownloadConfig(appId: 'lifering', storageDirectory: directory),
      http: http,
      signal: harness.dio,
      p2p: harness.client,
      downloadClient: downloader,
    );
  }

  RingDownloadRequest lifetimeRequest() => RingDownloadRequest(
    releaseId: harness.info.releaseId,
    version: harness.info.versionName,
    url: Uri.parse(_url),
    fileSize: harness.bytes.length,
    sha256: harness.info.sha256,
    etag: harness.info.downloadEtag,
  );

  Future<void> lifetimeUntil(bool Function() ready) async {
    for (var i = 0; i < 400 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), true);
  }

  test(
    'engine lifetime waits for completed receive and final traffic before HTTP close',
    () async {
      final outcome = Completer<void>(), traffic = Completer<void>();
      harness.outcomeGate = outcome.future;
      harness.trafficGate = traffic.future;
      final engine = await lifetimeEngine();
      final signal = harness.dio.httpClientAdapter as _LifetimeAdapter;
      try {
        final file = await engine.download(
          lifetimeRequest(),
          (_, _) {},
          CancelToken(),
        );
        expect(await file.readAsBytes(), harness.bytes);
        await harness.waitForPath('outcome');
        var disposed = false;
        final closing = engine.dispose().then((_) => disposed = true);
        await _settle();
        expect(disposed, false);
        expect(signal.closeCalls, 0);
        expect(harness.paths, isNot(contains('leave')));
        outcome.complete();
        await harness.waitForPath('traffic');
        await _settle();
        expect(disposed, false);
        expect(signal.closeCalls, 0);
        expect(
          harness.paths.indexOf('leave'),
          lessThan(harness.paths.indexOf('traffic')),
        );
        expect(harness.body('traffic')['final_verified'], true);
        traffic.complete();
        await closing;
        expect(signal.closeCalls, 1);
        await engine.dispose();
        expect(signal.closeCalls, 1);
      } finally {
        if (!outcome.isCompleted) outcome.complete();
        if (!traffic.isCompleted) traffic.complete();
        await engine.dispose();
      }
    },
  );

  test(
    'engine lifetime cancels active receiving while retaining its outcome owner',
    () async {
      harness.pieceDelay = const Duration(seconds: 1);
      final outcome = Completer<void>();
      harness.outcomeGate = outcome.future;
      final engine = await lifetimeEngine();
      final signal = harness.dio.httpClientAdapter as _LifetimeAdapter;
      final download = engine.download(
        lifetimeRequest(),
        (_, _) {},
        CancelToken(),
      );
      final cancelled = expectLater(download, throwsA(isA<DioException>()));
      try {
        await harness.waitForPath('server-offer');
        await lifetimeUntil(
          () => harness.peers.any(
            (p) => p.channel.sent.any(
              (m) =>
                  !m.isBinary &&
                  (jsonDecode(m.text) as Map)['type'] == 'get-piece',
            ),
          ),
        );
        var disposed = false;
        final closing = engine.dispose().then((_) => disposed = true);
        await harness.waitForPath('outcome');
        await _settle();
        expect(disposed, false);
        expect(signal.closeCalls, 0);
        expect(harness.peers.every((p) => p.closed), true);
        expect(harness.body('outcome')['outcome'], 'client_interrupted');
        outcome.complete();
        await closing;
        await cancelled;
        expect(
          harness.paths,
          containsAllInOrder(['outcome', 'leave', 'traffic']),
        );
        expect(harness.body('traffic')['final_verified'], false);
        expect(signal.closeCalls, 1);
      } finally {
        if (!outcome.isCompleted) outcome.complete();
        await engine.dispose();
        await cancelled;
      }
    },
  );

  test(
    'engine lifetime bounded final traffic failure cannot strand disposal',
    () async {
      final traffic = Completer<void>();
      harness.trafficGate = traffic.future;
      final engine = await lifetimeEngine();
      final signal = harness.dio.httpClientAdapter as _LifetimeAdapter;
      try {
        await engine.download(lifetimeRequest(), (_, _) {}, CancelToken());
        await harness.waitForPath('traffic');
        await engine.dispose().timeout(const Duration(seconds: 9));
        final reports = harness.requests
            .where((r) => r.uri.path.endsWith('/traffic'))
            .toList();
        expect(reports.length, 2);
        expect(reports[0].data, reports[1].data);
        expect(reports.every((r) => r.cancelToken?.isCancelled == true), true);
        expect(signal.closeCalls, 1);
      } finally {
        traffic.complete();
        await engine.dispose();
        await _settle();
      }
    },
  );

  test(
    'P8P loopback external COS requires no hosted metadata or control',
    () async {
      final origin = LoopbackPayload(harness.bytes);
      origin.bootstrapPause = Duration.zero;
      await origin.start();
      final http = Dio()..httpClientAdapter = LoopbackPayloadAdapter(origin);
      final engine = DefaultRingTransferEngine(
        RingDownloadConfig(
          appId: 'lifering',
          storageDirectory: directory,
          enableP8P: true,
        ),
        http: http,
      );
      try {
        var unexpectedClients = 0;
        final file = await HttpOverrides.runZoned(
          () => engine.download(
            RingDownloadRequest(
              releaseId: 'cos-without-health',
              url: Uri.parse(
                'https://object.example.test/update.apk?sign=fixture',
              ),
            ),
            (_, _) {},
            CancelToken(),
          ),
          createHttpClient: (_) {
            // Only the explicitly injected loopback payload adapter may create
            // real HTTP sockets. A health/signal/telemetry dependency fails here.
            unexpectedClients++;
            throw StateError('External COS attempted an unmapped HTTP client');
          },
        );
        expect(await file.readAsBytes(), harness.bytes);
        await origin.waitIdle();
        expect(origin.errors, isEmpty);
        expect(origin.exchanges, hasLength(1));
        expect(origin.exchanges.single.uri.host, 'object.example.test');
        for (final key in [
          'authorization',
          'x-device-id',
          'x-download-session-id',
          'if-range',
        ]) {
          expect(origin.exchanges.single.headers.containsKey(key), false);
        }
        expect(unexpectedClients, 0);
      } finally {
        await engine.dispose();
        await origin.close();
      }
    },
  );

  test(
    'P8P loopback concurrent task cancellation leaves another download running',
    () async {
      multisourceFixture();
      harness.releaseId = 'cancelled-task';
      harness.failControlConnection = (request) =>
          !['manifest', 'session'].contains(request.uri.pathSegments.last);
      final secondDirectory = await directory.createTemp('other-task-');
      final second = _Harness(secondDirectory)..releaseId = 'healthy-task';
      second.bytes = harness.bytes;
      second.enableTrickle();
      second.leaseCapable = true;
      second.pieceDelay = const Duration(milliseconds: 20);
      second.manifestOverride.addAll(harness.manifestOverride);
      second.client = second.makeClient(hybridStartup: true, enableP8P: true);
      final origin = LoopbackPayload(harness.bytes);
      await origin.start();
      final cancelled = CancelToken(), healthy = CancelToken();
      final httpA = Dio()
        ..httpClientAdapter = LoopbackPayloadAdapter(origin, tag: 'cancelled');
      final httpB = Dio()
        ..httpClientAdapter = LoopbackPayloadAdapter(origin, tag: 'healthy');
      final telemetry = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) =>
                h.resolve(Response(requestOptions: r, statusCode: 201)),
          ),
        );
      AppUpgradeV40DownloadClient downloader(Dio http, _Harness fixture) =>
          AppUpgradeV40DownloadClient(
            dio: http,
            p2pClient: fixture.client,
            httpsHeadStart: true,
            supportDirectoryLoader: () async => fixture.directory,
            serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
          );
      try {
        final stopped = expectLater(
          downloader(httpA, harness).download(
            info: harness.info,
            url: _url,
            backupUrl: null,
            refreshRelease: () async => harness.info,
            cancelToken: cancelled,
            onProgress: (received, _) {
              if (received >= 262144) cancelled.cancel('one_task_only');
            },
          ),
          throwsA(isA<DioException>()),
        );
        final file = await downloader(httpB, second)
            .download(
              info: second.info,
              url: _url,
              backupUrl: null,
              refreshRelease: () async => second.info,
              cancelToken: healthy,
              onProgress: (_, _) {},
            )
            .timeout(const Duration(seconds: 15));
        await stopped;
        expect(
          sha256.convert(await file.readAsBytes()).toString(),
          second.info.sha256,
        );
        expect(healthy.isCancelled, false);
        await origin.waitIdle();
        expect(origin.peakActive, greaterThanOrEqualTo(2));
        expect(
          origin.exchanges.map((request) => request.tag).toSet(),
          containsAll(['healthy', 'cancelled']),
        );
        expect(origin.errors, isEmpty);
        for (final fixture in [harness, second]) {
          for (final profile in fixture.logs.where(
            (event) => event.metrics.containsKey('peak_reservations'),
          )) {
            expect(profile.metrics['peak_reservations'], lessThanOrEqualTo(4));
            expect(
              profile.metrics['peak_reserved_bytes'],
              lessThanOrEqualTo(4 * 1048576),
            );
          }
        }
        expect(
          [...harness.peers, ...second.peers].every((peer) => peer.closed),
          true,
        );
      } finally {
        cancelled.cancel('fixture_done');
        healthy.cancel('fixture_done');
        httpA.close(force: true);
        httpB.close(force: true);
        telemetry.close(force: true);
        await second.client.stopSharing();
        await second.events.close();
        await origin.close();
      }
    },
  );

  test(
    'P8P startup uses a later fast source before the first probe times out',
    () async {
      multisourceFixture(peer: true);
      final slowStarted = Completer<void>(), release = Completer<void>();
      final handedOff = Completer<void>();
      final cancel = CancelToken();
      _FakeChannel? slow;
      // Seed negotiates first. Discovery returns the fast peer only after the
      // first seed request is actually stalled, not merely after a timer.
      harness.peersGate = slowStarted.future;
      harness.beforeLeasedPiece = (channel, index, stopped) async {
        slow ??= channel;
        if (identical(channel, slow)) {
          if (!slowStarted.isCompleted) slowStarted.complete();
          await Future.any([release.future, stopped]);
        }
      };
      final download = harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {
          expect(harness.part.existsSync(), false);
          final probes = harness.peers
              .expand((p) => p.channel.sent)
              .where((m) => !m.isBinary)
              .map((m) => jsonDecode(m.text) as Map)
              .where((m) => m['type'] == 'get')
              .toList();
          expect(probes.length, 2);
          expect(probes.map((p) => p['index']).toSet().length, 2);
          handedOff.complete();
        },
        p8pRangePiece: (index, token) async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          final start = index * 1048576;
          return Uint8List.fromList(
            harness.bytes.sublist(
              start,
              (start + 1048576).clamp(0, harness.bytes.length),
            ),
          );
        },
        cancelToken: cancel,
      );
      // Observe errors immediately even if a timing assertion fails first.
      unawaited(download.then<void>((_) {}, onError: (Object _) {}));
      try {
        await slowStarted.future.timeout(const Duration(seconds: 3));
        await handedOff.future.timeout(const Duration(seconds: 2));
        expect(release.isCompleted, false);
        expect(await download, harness.bytes.length);
        expect(harness.part.readAsBytesSync(), harness.bytes);
        final profile = harness.logs.lastWhere(
          (e) => e.code == 'multisource_profile',
        );
        expect(profile.metrics['peak_reservations'], lessThanOrEqualTo(4));
        expect(
          profile.metrics['peak_reserved_bytes'],
          lessThanOrEqualTo(4 * 1048576),
        );
        expect(harness.peers.every((p) => p.closed), true);
      } finally {
        cancel.cancel('fixture_done');
        release.complete();
        try {
          await download;
        } catch (_) {}
      }
    },
  );

  test(
    'P8P startup cancellation closes every concurrent probe before handoff',
    () async {
      multisourceFixture(peer: true);
      final firstStarted = Completer<void>(), bothStarted = Completer<void>();
      final cancel = CancelToken();
      var probes = 0, handedOff = false;
      harness.peersGate = firstStarted.future;
      harness.beforeLeasedPiece = (channel, index, stopped) async {
        probes++;
        if (!firstStarted.isCompleted) firstStarted.complete();
        if (probes == 2) bothStarted.complete();
        await stopped;
      };
      final download = harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async => handedOff = true,
        p8pRangePiece: (index, token) async =>
            throw StateError('HTTP must stay independent'),
        cancelToken: cancel,
      );
      unawaited(download.then<void>((_) {}, onError: (Object _) {}));
      try {
        await bothStarted.future.timeout(const Duration(seconds: 2));
        cancel.cancel('startup_user_cancel');
        await expectLater(download, throwsA(isA<DioException>()));
        expect(handedOff, false);
        expect(harness.part.existsSync(), false);
        expect(harness.peers.every((p) => p.closed), true);
      } finally {
        cancel.cancel('fixture_done');
        try {
          await download;
        } catch (_) {}
      }
    },
  );

  test('P8P engine resumes its verified prefix after cancellation', () async {
    multisourceFixture();
    final cancel = CancelToken();
    Future<Uint8List> range(int index, CancelToken token) async {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final start = index * 1048576;
      return Uint8List.fromList(
        harness.bytes.sublist(
          start,
          (start + 1048576).clamp(0, harness.bytes.length),
        ),
      );
    }

    await expectLater(
      harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {},
        p8pRangePiece: range,
        cancelToken: cancel,
        onProgress: (received, total) {
          if (received >= 2 * 1048576) cancel.cancel('pause_fixture');
        },
      ),
      throwsA(isA<DioException>()),
    );
    final prefix = await harness.part.length();
    expect(prefix, greaterThanOrEqualTo(2 * 1048576));
    expect(prefix % 1048576, 0);
    expect(harness.peers.every((p) => p.closed), true);
    await _settle();
    final oldPeers = harness.peers.length;
    harness.client = harness.makeClient(hybridStartup: true, enableP8P: true);
    expect(
      await harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {},
        p8pRangePiece: (index, token) async {
          expect(index, greaterThanOrEqualTo(prefix ~/ 1048576));
          return range(index, token);
        },
      ),
      harness.bytes.length,
    );
    final gets = harness.peers
        .skip(oldPeers)
        .expand((p) => p.channel.sent)
        .where((m) => !m.isBinary)
        .map((m) => jsonDecode(m.text) as Map)
        .where((m) => m['type'] == 'get');
    expect(gets.every((m) => m['index'] >= prefix ~/ 1048576), true);
    expect(harness.part.readAsBytesSync(), harness.bytes);
  });

  test(
    'P8P engine does not issue a full hash receipt after disk mutation',
    () async {
      multisourceFixture();
      var verified = false;
      await harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {},
        p8pRangePiece: (index, token) async {
          final start = index * 1048576;
          return Uint8List.fromList(
            harness.bytes.sublist(
              start,
              (start + 1048576).clamp(0, harness.bytes.length),
            ),
          );
        },
        onFileVerified: () => verified = true,
        onProgress: (received, total) {
          if (received == total) {
            final disk = harness.part.openSync(mode: FileMode.append);
            disk.setPositionSync(total - 1);
            disk.writeByteSync(255);
            disk.closeSync();
          }
        },
      );
      expect(verified, false);
      await harness.waitForPath('outcome');
      expect(harness.body('outcome')['verified'], false);
      expect(harness.body('outcome')['reason_code'], 'file_checksum_mismatch');
    },
  );

  const python = String.fromEnvironment('P8P_INTEROP_PYTHON');
  const senderScript = String.fromEnvironment('P8P_INTEROP_SCRIPT');
  if (python.isNotEmpty && senderScript.isNotEmpty) {
    test(
      'P8P actual Python sender and SDK download engine interoperate',
      () async {
        multisourceFixture();
        final fixture = File('${directory.path}/python-fixture');
        await fixture.writeAsBytes(harness.bytes);
        final process = await Process.start(python, [
          '-X',
          'utf8',
          senderScript,
          '--fixture',
          fixture.path,
        ]);
        final bridge = _PythonSender(process);
        harness.leaseBridge = bridge;
        try {
          final httpIndices = <int>[];
          final length = await harness.downloadPrefix(
            bootstrapPiece: (_) async => null,
            bootstrapHandoff: () async {},
            p8pRangePiece: (index, token) async {
              httpIndices.add(index);
              await Future<void>.delayed(const Duration(milliseconds: 20));
              final start = index * 1048576;
              return Uint8List.fromList(
                harness.bytes.sublist(
                  start,
                  (start + 1048576).clamp(0, harness.bytes.length),
                ),
              );
            },
          );
          expect(
            length,
            harness.bytes.length,
            reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
          );
          expect(harness.part.readAsBytesSync(), harness.bytes);
          expect(httpIndices, isNotEmpty);
          expect(bridge.binaryBytes, greaterThan(1048576));
          expect(bridge.stderrText, isEmpty);
          expect(harness.peers.every((p) => p.closed), true);
        } finally {
          await bridge.close();
        }
      },
    );
  }

  for (final peer in [false, true]) {
    test(
      'P8P engine divides verified pieces between HTTPS and RTC peer=$peer',
      () async {
        multisourceFixture(peer: peer);
        harness.manifestOverride['attempt_diagnostics_supported'] = true;
        final httpPieces = <int>[];
        var handoff = false;
        var verified = false;
        final progress = <int>[];
        final size = await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
          bootstrapHandoff: () async {
            expect(
              harness.part.existsSync(),
              false,
              reason: 'Probe must remain paused before HTTP stops',
            );
            handoff = true;
          },
          p8pRangePiece: (index, token) async {
            expect(handoff, true);
            httpPieces.add(index);
            await Future<void>.delayed(const Duration(milliseconds: 25));
            final start = index * 1048576;
            return Uint8List.fromList(
              harness.bytes.sublist(
                start,
                (start + 1048576).clamp(0, harness.bytes.length),
              ),
            );
          },
          onProgress: (received, total) => progress.add(received),
          onFileVerified: () => verified = true,
        );
        expect(
          size,
          harness.bytes.length,
          reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
        );
        expect(verified, true);
        expect(handoff, true);
        expect(httpPieces, isNotEmpty);
        expect(harness.part.readAsBytesSync(), harness.bytes);
        expect(progress.last, harness.bytes.length);
        final completed = harness.logs.where(
          (event) =>
              event.stage == 'transfer' && event.code == 'source_completed',
        );
        expect(completed, isNotEmpty);
        expect(
          harness.logs.any((event) => event.code == 'source_failed'),
          false,
        );
        expect(harness.logs.any((e) => e.code == 'multisource_started'), true);
        // Multiple binary frames must produce one first-arrival event per
        // actual transport, retaining the existing fixed aliases and timing.
        final payloadEvents = harness.logs
            .where((e) => e.code == 'first_payload_received')
            .toList();
        final expectedAliases = {'seed', if (peer) 'peer1'};
        expect(payloadEvents.map((e) => e.attempt).toSet(), expectedAliases);
        for (final alias in expectedAliases) {
          final event = payloadEvents.singleWhere((e) => e.attempt == alias);
          expect(event.stage, 'attempt');
          expect(event.elapsedMs, greaterThanOrEqualTo(0));
          expect(event.toJson()['code'], 'first_payload_received');
          expect(event.toJson()['attempt'], alias);
        }
        final requests = harness.peers
            .expand((p) => p.channel.sent)
            .where((m) => !m.isBinary)
            .map((m) => jsonDecode(m.text) as Map)
            .where((m) => m['type'] == 'get')
            .toList();
        expect(requests, isNotEmpty);
        expect(
          httpPieces.toSet().intersection(
            requests.map((m) => m['index'] as int).toSet(),
          ),
          isEmpty,
        );
        expect(harness.peers.every((p) => p.closed), true);
        final metrics = harness.logs
            .where((e) => e.metrics.containsKey('peak_reservations'))
            .last
            .metrics;
        expect(metrics['peak_reservations'], lessThanOrEqualTo(4));
        expect(metrics['peak_reserved_bytes'], lessThanOrEqualTo(4 * 1048576));
      },
    );
  }

  for (final fault in ['corrupt', 'close']) {
    test('P8P engine continues via HTTP after a $fault RTC source', () async {
      multisourceFixture();
      final injected = <int>{};
      harness.beforeLeasedPiece = (_, index, stopped) async {
        if (index == 0) return; // Keep the real startup proof intact.
        injected.add(index);
        if (fault == 'corrupt') {
          harness.corruptIndex = index;
        } else {
          harness.closeIndex = index;
        }
      };
      final httpPieces = <int>[];
      expect(
        await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
          bootstrapHandoff: () async {},
          p8pRangePiece: (index, token) async {
            httpPieces.add(index);
            await Future<void>.delayed(const Duration(milliseconds: 30));
            final start = index * 1048576;
            return Uint8List.fromList(
              harness.bytes.sublist(
                start,
                (start + 1048576).clamp(0, harness.bytes.length),
              ),
            );
          },
        ),
        harness.bytes.length,
        reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
      );
      expect(harness.part.readAsBytesSync(), harness.bytes);
      expect(injected, isNotEmpty, reason: 'The RTC fault must actually run');
      expect(httpPieces.toSet().containsAll(injected), true);
      expect(harness.peers.every((p) => p.closed), true);
      if (fault == 'corrupt') {
        final failures = harness.logs.where(
          (event) =>
              event.stage == 'transfer' &&
              event.code == 'piece_checksum_mismatch',
        );
        expect(
          failures,
          hasLength(1),
          reason: 'Retain the first verified-piece rejection before teardown',
        );
        final failure = failures.single;
        expect(failure.attempt, 'seed');
        expect(failure.actualBytes, AppUpgradeP2PManifest.chunkSize);
        expect(failure.expectedBytes, AppUpgradeP2PManifest.chunkSize);
        final firstClose = harness.logs.indexWhere(
          (event) => event.stage == 'attempt' && event.code == 'channel_closed',
        );
        expect(harness.logs.indexOf(failure), lessThan(firstClose));
      }
    });
  }

  test(
    'P8P diagnostics throwing during source failure cannot block HTTPS or disposal',
    () async {
      multisourceFixture();
      final injected = <int>{};
      harness.beforeLeasedPiece = (_, index, stopped) async {
        if (index > 0) {
          injected.add(index);
          harness.corruptIndex = index;
        }
      };
      harness.failTransferDiagnostic = true;
      var verified = false;
      final size = await harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        bootstrapHandoff: () async {},
        p8pRangePiece: (index, token) async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          final start = index * AppUpgradeP2PManifest.chunkSize;
          return Uint8List.fromList(
            harness.bytes.sublist(
              start,
              (start + AppUpgradeP2PManifest.chunkSize).clamp(
                0,
                harness.bytes.length,
              ),
            ),
          );
        },
        onFileVerified: () => verified = true,
      );
      expect(size, harness.bytes.length);
      expect(injected, isNotEmpty, reason: 'The rejecting observer must run');
      expect(verified, true);
      expect(harness.part.readAsBytesSync(), harness.bytes);
      expect(harness.peers.every((peer) => peer.closed), true);
      expect(
        harness.logs.any((event) => event.code == 'piece_checksum_mismatch'),
        true,
      );
    },
  );

  test(
    'P8P new service with legacy user node keeps legacy transfer available',
    () async {
      multisourceFixture();
      harness.advertisePeer = true;
      harness.seedBusy = true;
      harness.leasePeerCapable = false;
      expect(
        await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
          bootstrapHandoff: () async =>
              fail('Legacy sender must not trigger new handoff'),
          p8pRangePiece: (index, token) async => throw StateError('unused'),
        ),
        harness.bytes.length,
      );
      expect(harness.logs.any((e) => e.code == 'multisource_started'), false);
      expect(harness.part.readAsBytesSync(), harness.bytes);
    },
  );

  for (final scenario in [
    'normal',
    'cellular',
    'range-mismatch',
    'etag-mismatch',
    'corrupt',
    'oversized',
    'truncated',
    'ignored-range',
    'redirect-cos',
    'contention-once',
    'contention-parallel',
    'contention-fallback',
    'contention-repeated',
    'contention-foreign',
    'contention-quota',
    'contention-long',
    'contention-cancel',
    'contention-external',
    'cancel',
  ]) {
    test('P8P whole download HTTP contract $scenario', () async {
      multisourceFixture();
      if (scenario == 'contention-fallback') harness.closeIndex = 2;
      if (scenario == 'cellular') {
        harness.network = AppUpgradeP2PNetwork.cellular;
      }
      final requests = <RequestOptions>[];
      final https = Dio(), telemetry = Dio(), cancel = CancelToken();
      var rangeFault = false;
      var contentionResponses = 0;
      var boundedResponses = 0;
      final contentionTimes = <DateTime>[];
      final contractClock = Stopwatch()..start();
      final requestTimeline = <Map<String, Object?>>[];
      String? firstRejectedRange;
      final contention = scenario.startsWith('contention-');
      if (contention) harness.pieceDelay = const Duration(milliseconds: 400);
      final secondRejection = Completer<void>();
      final httpAccepted = Completer<void>();
      if (scenario == 'contention-repeated' ||
          scenario == 'contention-parallel') {
        // These fixtures deliberately hold RTC pieces across a two-second HTTP
        // Retry-After. Exercise the real production 8s piece deadline here;
        // the generic fixture's shortened 3s mixes that wait with debug SHA CPU
        // work and can accidentally turn this HTTP retry test into a timeout.
        // Dedicated timeout/cancellation cases keep their short deadlines.
        harness.client = harness.makeClient(
          hybridStartup: true,
          enableP8P: true,
          timeouts: const AppUpgradeP2PTimeouts(
            rtcOperation: Duration(seconds: 3),
            iceGathering: Duration(seconds: 3),
            answer: Duration(seconds: 3),
            channel: Duration(seconds: 3),
          ),
        );
        var piecesStarted = 0;
        harness.beforeLeasedPiece = (_, index, stopped) async {
          if (piecesStarted++ > 0) {
            await Future.any([
              scenario == 'contention-parallel'
                  ? httpAccepted.future
                  : secondRejection.future,
              stopped,
            ]);
          }
        };
      }
      telemetry.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) =>
              h.resolve(Response(requestOptions: r, statusCode: 201)),
        ),
      );
      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) async {
            requests.add(r);
            requestTimeline.add({
              'range': r.headers['range'],
              'at_us': contractClock.elapsedMicroseconds,
            });
            final match = RegExp(
              r'^bytes=(\d+)-(\d*)$',
            ).firstMatch(r.headers['range'] as String)!;
            final start = int.parse(match[1]!);
            final end = match[2]!.isEmpty
                ? harness.bytes.length - 1
                : int.parse(match[2]!);
            final bootstrap = start == 0 && end == harness.bytes.length - 1;
            final fallback = match[2]!.isEmpty;
            if (scenario == 'contention-fallback' && !bootstrap && !fallback) {
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 503,
                  data: ResponseBody.fromBytes([], 503),
                ),
              );
              return;
            }
            if (!bootstrap &&
                ['redirect-cos', 'contention-external'].contains(scenario) &&
                r.uri.host != 'object.example.test') {
              final headers = {
                'location': [
                  'https://object.example.test/file.apk?signature=fixture',
                ],
              };
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 302,
                  headers: Headers.fromMap(headers),
                  data: ResponseBody.fromBytes([], 302, headers: headers),
                ),
              );
              return;
            }
            if (!bootstrap) boundedResponses++;
            final fault =
                !bootstrap && !rangeFault && scenario != 'contention-parallel';
            if (!bootstrap) rangeFault = true;
            if (contention &&
                !bootstrap &&
                (fault ||
                    scenario == 'contention-repeated' &&
                        r.headers['range'] == firstRejectedRange &&
                        contentionResponses < 2 ||
                    scenario == 'contention-parallel' &&
                        boundedResponses > 1 &&
                        contentionResponses < 2)) {
              firstRejectedRange ??= r.headers['range'] as String;
              contentionResponses++;
              if (contentionResponses == 2) secondRejection.complete();
              contentionTimes.add(DateTime.now());
              if (scenario == 'contention-parallel') {
                // Hold both owners before responding. Request order alone can
                // otherwise turn this into two sequential rejections separated
                // by Retry-After, which must fail the bounded retry contract.
                await Future.any<void>([
                  secondRejection.future,
                  r.cancelToken!.whenCancel.then<void>((_) {}),
                ]);
                if (r.cancelToken!.isCancelled) {
                  h.reject(r.cancelToken!.cancelError!);
                  return;
                }
              }
              final headers = <String, List<String>>{
                'x-download-session-id': [
                  scenario == 'contention-foreign'
                      ? 'fedcba9876543210'
                      : '0123456789abcdef',
                ],
                'x-download-deduplicated': ['1'],
                'x-ratelimit-reason': [
                  scenario == 'contention-quota'
                      ? 'ip-window'
                      : 'duplicate-in-flight',
                ],
                'retry-after': [scenario == 'contention-long' ? '30' : '2'],
              };
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 429,
                  headers: Headers.fromMap(headers),
                  data: ResponseBody.fromBytes(
                    utf8.encode(
                      jsonEncode({
                        'error': scenario == 'contention-quota'
                            ? 'rate_limit_exceeded'
                            : 'duplicate_in_flight',
                      }),
                    ),
                    429,
                    headers: headers,
                  ),
                ),
              );
              if (scenario == 'contention-cancel') {
                Timer(
                  const Duration(milliseconds: 50),
                  () => cancel.cancel('cancel_during_contention_wait'),
                );
              }
              return;
            }
            if (!bootstrap &&
                !httpAccepted.isCompleted &&
                (scenario != 'contention-parallel' ||
                    contentionResponses == 2)) {
              httpAccepted.complete();
            }
            final status = fault && scenario == 'ignored-range' ? 200 : 206;
            final headers = <String, List<String>>{
              'content-range': [
                'bytes ${fault && scenario == 'range-mismatch' ? start + 1 : start}-$end/${harness.bytes.length}',
              ],
              'etag': [
                r.uri.host == 'object.example.test' ||
                        fault && scenario == 'etag-mismatch'
                    ? '"other-origin"'
                    : '"release-test"',
              ],
              'x-download-session-id': ['0123456789abcdef'],
            };
            var bytes = Uint8List.fromList(
              harness.bytes.sublist(start, end + 1),
            );
            if (fault && scenario == 'corrupt') bytes[0] ^= 255;
            if (fault && scenario == 'oversized') {
              bytes = Uint8List.fromList([...bytes, 99]);
            }
            if (fault && scenario == 'truncated') {
              bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
            }
            final stream = bootstrap
                ? () async* {
                    yield Uint8List.sublistView(bytes, 0, 1048576);
                    await r.cancelToken!.whenCancel;
                  }()
                : () async* {
                    await Future<void>.delayed(
                      const Duration(milliseconds: 25),
                    );
                    if (!r.cancelToken!.isCancelled) yield bytes;
                  }();
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: status,
                headers: Headers.fromMap(headers),
                data: ResponseBody(stream, status, headers: headers),
              ),
            );
          },
        ),
      );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        httpsHeadStart: true,
        serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
        supportDirectoryLoader: () async => directory,
      );
      try {
        final download = downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async => harness.info,
          cancelToken: cancel,
          onProgress: (received, total) {
            if (scenario == 'cancel' && received >= 2 * 1048576) {
              cancel.cancel('test_user_cancel');
            }
          },
        );
        if (scenario == 'cancel' || scenario == 'contention-cancel') {
          await expectLater(download, throwsA(isA<DioException>()));
          expect(harness.peers.every((p) => p.closed), true);
          if (scenario == 'contention-cancel') {
            expect(contentionResponses, 1);
            expect(
              harness.logs.where(
                (event) => event.code == 'p8p_contention_wait',
              ),
              hasLength(1),
            );
          }
          return;
        }
        final file = await download.catchError((Object error) {
          // ignore: avoid_print
          print(
            'HTTP_CONTRACT_FAILURE ${jsonEncode({'scenario': scenario, 'requests': requests.map((r) => r.headers['range']).toList(), 'events': harness.logs.map((e) => e.toJson()).toList()})}',
          );
          throw error;
        });
        expect(await file.readAsBytes(), harness.bytes);
        expect(harness.logs.any((e) => e.code == 'multisource_started'), true);
        expect(requests.length, greaterThan(1));
        final gets = harness.peers
            .expand((p) => p.channel.sent)
            .where((m) => !m.isBinary)
            .map((m) => jsonDecode(m.text) as Map)
            .where((m) => m['type'] == 'get')
            .toList();
        expect(
          gets.any((m) => m['index'] == 0),
          false,
          reason:
              'The cached HTTP prefix must not be downloaded from a node again',
        );
        expect(downloader.lastBootstrapUsedBytes, 1048576);
        if (scenario == 'cellular') {
          expect(harness.body('session')['network'], 'cellular');
          expect(harness.body('session')['share_enabled'], false);
        }
        expect(downloader.lastHttpsBodyBytes, greaterThanOrEqualTo(1048576));
        final rangeRequests = requests.skip(1).toList();
        expect(
          rangeRequests.every((r) {
            final parts = RegExp(
              r'^bytes=(\d+)-(\d*)$',
            ).firstMatch(r.headers['range'] as String)!;
            if (parts[2]!.isEmpty) return scenario == 'contention-fallback';
            return int.parse(parts[2]!) - int.parse(parts[1]!) + 1 <= 1048576;
          }),
          true,
          reason: jsonEncode({
            'scenario': scenario,
            'requests': requestTimeline,
            'rejection_spacing_ms': [
              for (var i = 1; i < contentionTimes.length; i++)
                contentionTimes[i]
                    .difference(contentionTimes[i - 1])
                    .inMilliseconds,
            ],
            'events': harness.logs.map((event) => event.toJson()).toList(),
          }),
        );
        if (scenario == 'redirect-cos' || scenario == 'contention-external') {
          final redirected = rangeRequests
              .where((r) => r.uri.host == 'object.example.test')
              .toList();
          expect(redirected, isNotEmpty);
          for (final r in redirected) {
            for (final key in [
              'X-Device-Id',
              'X-Client-App-Version',
              'X-Download-Session-Id',
              'if-range',
            ]) {
              expect(r.headers.containsKey(key), false);
            }
          }
        }
        if (contention) {
          final waits = harness.logs
              .where((event) => event.code == 'p8p_contention_wait')
              .length;
          expect(
            waits,
            [
                  'contention-once',
                  'contention-parallel',
                  'contention-fallback',
                  'contention-repeated',
                ].contains(scenario)
                ? 1
                : 0,
          );
          expect(
            contentionResponses,
            ['contention-repeated', 'contention-parallel'].contains(scenario)
                ? 2
                : 1,
          );
          if (scenario == 'contention-parallel') {
            expect(httpAccepted.isCompleted, true);
          } else if (contentionTimes.length == 2) {
            expect(
              contentionTimes[1].difference(contentionTimes[0]).inMilliseconds,
              greaterThanOrEqualTo(2000),
            );
          }
        }
        if (![
          'normal',
          'cellular',
          'redirect-cos',
          'contention-once',
          'contention-parallel',
        ].contains(scenario)) {
          final profile = harness.logs.singleWhere(
            (e) => e.code == 'multisource_profile',
          );
          expect(profile.metrics['source_failures'], greaterThanOrEqualTo(1));
        }
        final outcome = harness.body('outcome');
        expect(outcome['verified'], scenario != 'contention-fallback');
        final result = harness.logs.lastWhere((e) => e.stage == 'result');
        expect(result.seedBytes, greaterThan(0));
        if (['normal', 'cellular', 'redirect-cos'].contains(scenario)) {
          expect(result.seedBytes, lessThan(harness.bytes.length));
          expect(downloader.lastHttpsBodyBytes, greaterThan(1048576));
        }
        expect(harness.peers.every((p) => p.closed), true);
      } finally {
        https.close(force: true);
        telemetry.close(force: true);
      }
    });
  }

  for (final optedIn in [false, true]) {
    for (final serviceSupports in [false, true]) {
      for (final senderSupports in [false, true]) {
        test(
          'P8P compatibility sdk=$optedIn service=$serviceSupports sender=$senderSupports',
          () async {
            harness.enableTrickle();
            harness.advertisePeer = true;
            harness.seedBusy = true;
            harness.pipelineCapable = true;
            harness.p8pCapable = senderSupports;
            harness.pieceDelay = const Duration(milliseconds: 5);
            harness.bytes = Uint8List.fromList(
              List.generate(5 * 1048576 + 79, (i) => i % 251),
            );
            harness.advertisedPieces = List.generate(6, (i) => i);
            if (serviceSupports) {
              harness.manifestOverride['p8p'] = {
                'version': 1,
                'max_window': 4,
                'features': ['adaptive_window_v1', 'capacity_advice_v1'],
              };
            }
            harness.client = harness.makeClient(
              hybridStartup: true,
              enableP8P: optedIn,
            );
            expect(
              await harness.downloadPrefix(bootstrapPiece: (_) async => null),
              harness.bytes.length,
            );
            expect(harness.part.readAsBytesSync(), harness.bytes);
            final active = optedIn && serviceSupports && senderSupports;
            expect(
              harness.logs.any((e) => e.code == 'p8p_window_selected'),
              active,
            );
            final controls = harness.peers
                .expand((p) => p.channel.sent)
                .where((m) => !m.isBinary)
                .map((m) => jsonDecode(m.text) as Map)
                .toList();
            final batches = controls
                .where((m) => m['type'] == 'get-pieces')
                .toList();
            expect(batches.first['indices'], [1, 2, 3, 4]);
            expect(
              controls.any((m) => m.containsKey('p8p')),
              optedIn && serviceSupports,
            );
            expect(harness.peers.every((p) => p.closed), true);
          },
        );
      }
    }
  }

  test(
    'SDK consent false receives data but never advertises upload availability',
    () async {
      harness.advertisePeer = true;
      harness.seedBusy = true;
      harness.enableTrickle();
      harness.client = harness.makeClient(
        hybridStartup: true,
        allowSharing: false,
      );
      expect(
        await harness.downloadPrefix(bootstrapPiece: (_) async => null),
        harness.bytes.length,
      );
      expect(harness.body('session')['network'], 'wifi_unmetered');
      expect(harness.body('session')['share_enabled'], false);
      expect(harness.body('session')['pieces'], isEmpty);
      for (final r in harness.requests.where(
        (r) => r.uri.pathSegments.last == 'heartbeat',
      )) {
        expect((r.data as Map)['share_enabled'], false);
        expect((r.data as Map)['pieces'], isEmpty);
      }
    },
  );

  for (final scenario in ['late', 'absent', 'hard-limit', 'cancel']) {
    test(
      'late ICE candidate grace $scenario stays within ownership and budget',
      () async {
        multisourceFixture(peer: true);
        harness.seedBusy = true;
        harness.trackPeerOwners = true;
        harness.enableTrickle(budgetMs: scenario == 'hard-limit' ? 1000 : 2500);
        harness.manifestOverride['p2p_background_connect_timeout_ms'] =
            scenario == 'hard-limit' ? 1000 : 2500;
        harness.manifestOverride['peer_shared_deadline_supported'] = false;
        harness.channelOpenDelay = Duration(
          milliseconds: scenario == 'hard-limit' || scenario == 'cancel'
              ? 1700
              : 950,
        );
        harness.client = harness.makeClient(
          hybridStartup: true,
          enableP8P: true,
          fastSignaling: true,
          timeouts: const AppUpgradeP2PTimeouts(
            channel: Duration(milliseconds: 650),
          ),
        );
        final cancel = CancelToken();
        final timers = <Timer>[];
        harness.remoteSetHook = (peer) {
          if (peer.target != _other || scenario == 'absent') return;
          timers.add(
            Timer(const Duration(milliseconds: 400), () {
              harness.remoteCandidates.add({
                'from_peer_id': _other,
                'candidate': {
                  'candidate':
                      'candidate:97 1 udp 1 192.0.2.98 4321 typ srflx raddr 192.168.1.98 rport 4321',
                  'sdpMid': '0',
                  'sdpMLineIndex': 0,
                },
              });
            }),
          );
          if (scenario == 'cancel') {
            timers.add(
              Timer(
                const Duration(milliseconds: 850),
                () => cancel.cancel('cancel during candidate grace'),
              ),
            );
          }
        };
        try {
          final pending = replacementDownload(cancelToken: cancel);
          if (scenario == 'cancel') {
            await expectLater(pending, throwsA(isA<DioException>()));
          } else {
            expect(
              await pending,
              scenario == 'late' ? harness.bytes.length : 0,
              reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
            );
          }
          final grace = harness.logs.where(
            (e) => e.code == 'ice_candidate_grace',
          );
          expect(grace.length, scenario == 'absent' ? 0 : 1);
          if (scenario == 'hard-limit') {
            final failed = harness.logs.singleWhere(
              (e) => e.code == 'peer_failure_detail' && e.attempt == 'peer1',
            );
            expect(failed.durationMs, lessThan(1400));
          }
          await harness.client.close();
          await Future.wait(
            harness.peers.map((peer) => peer.disposeCompleted.future),
          ).timeout(const Duration(seconds: 4));
          expect(harness.peers.every((p) => p.closed && p.disposed), true);
        } finally {
          for (final timer in timers) {
            timer.cancel();
          }
          cancel.cancel('fixture cleanup');
        }
      },
    );
  }

  for (final scenario in [
    'counts',
    'missing',
    'invalid',
    'timeout',
    'truncated',
  ]) {
    test(
      'ICE failure snapshot $scenario is bounded and omits private fields',
      () async {
        multisourceFixture(peer: true);
        harness.seedBusy = true;
        harness.trackPeerOwners = true;
        harness.stalledIcePeerIds.add(_other);
        harness.enableTrickle(budgetMs: 1300);
        harness.manifestOverride['p2p_background_connect_timeout_ms'] = 1300;
        final delayed = Completer<List<StatsReport>>();
        harness.iceStats = () async {
          if (scenario == 'timeout') return delayed.future;
          return [
            StatsReport('private-transport-id', 'transport', 123, {
              'bytesSent': 999,
            }),
            for (var i = 0; i < (scenario == 'truncated' ? 70 : 2); i++)
              StatsReport('private-pair-$i', 'candidate-pair', 123, {
                'state': 'in-progress',
                'localCandidateId': 'private-id',
                'address': '192.0.2.44',
                'requestsSent': scenario == 'invalid' ? -1 : 5,
                'requestsReceived': 2.0,
                'responsesSent': '2',
                if (scenario != 'missing') 'responsesReceived': 1,
              }),
          ];
        };
        try {
          await replacementDownload(
            rangeDelay: const Duration(milliseconds: 350),
          );
          await harness.client.close();
          final detail = harness.logs.singleWhere(
            (e) => e.code == 'peer_failure_detail' && e.attempt == 'peer1',
          );
          final metrics = detail.toJson()['metrics'] as Map;
          expect(metrics['ice_stats_sampled'], scenario == 'timeout' ? 0 : 1);
          if (scenario == 'counts') {
            expect(metrics['ice_requests_sent'], 10);
            expect(metrics['ice_requests_received'], 4);
            expect(metrics['ice_responses_sent'], 4);
            expect(metrics['ice_responses_received'], 2);
          }
          if (scenario == 'missing' || scenario == 'timeout') {
            expect(metrics.containsKey('ice_responses_received'), false);
          }
          if (scenario == 'invalid' || scenario == 'truncated') {
            expect(metrics.containsKey('ice_requests_sent'), false);
          }
          if (scenario == 'truncated') {
            expect(metrics['ice_pair_count'], 64);
            expect(metrics['ice_pairs_truncated'], 1);
          }
          expect(harness.iceStatsReads, inInclusiveRange(1, 2));
          expect(jsonEncode(detail.toJson()), isNot(contains('192.0.2.44')));
          expect(jsonEncode(detail.toJson()), isNot(contains('private')));
          await Future.wait(
            harness.peers.map((peer) => peer.disposeCompleted.future),
          ).timeout(const Duration(seconds: 4));
          expect(harness.peers.every((p) => p.closed && p.disposed), true);
          final reads = harness.iceStatsReads;
          delayed.complete([]);
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(harness.iceStatsReads, reads);
        } finally {
          if (!delayed.isCompleted) delayed.complete([]);
        }
      },
    );
  }

  for (final enabled in [false, true]) {
    test(
      'shared channel deadline opt-in=$enabled preserves legacy timeout',
      () async {
        harness.firstPeerId = enabled
            ? 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
            : 'dddddddddddddddddddddddddddddddd';
        harness.enableTrickle(budgetMs: 1000);
        harness.manifestOverride['p2p_background_connect_timeout_ms'] = 1000;
        harness.manifestOverride['peer_shared_deadline_supported'] = enabled;
        harness.advertisePeer = true;
        harness.seedBusy = true;
        harness.channelOpenDelay = const Duration(milliseconds: 180);
        harness.client = harness.makeClient(
          hybridStartup: true,
          timeouts: const AppUpgradeP2PTimeouts(
            channel: Duration(milliseconds: 40),
          ),
        );
        final prefix = await harness.downloadPrefix(
          bootstrapPiece: (_) async => null,
        );
        expect(
          prefix,
          enabled ? harness.bytes.length : 0,
          reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
        );
        expect(harness.peers.every((p) => p.closed), true);
        if (enabled) {
          expect(harness.part.readAsBytesSync(), harness.bytes);
        } else {
          expect(
            harness.logs.any(
              (e) =>
                  e.stage == 'attempt' &&
                  e.source == 'peer' &&
                  e.code == 'peer_connect_timeout',
            ),
            true,
          );
        }
      },
    );
  }

  test(
    'negotiating poll is opt-in fast and never overlaps a slow response',
    () async {
      harness.firstPeerId = 'ffffffffffffffffffffffffffffffff';
      harness.enableTrickle(budgetMs: 2000);
      harness.manifestOverride['peer_fast_signal_poll_ms'] = 100;
      harness.advertisePeer = true;
      harness.seedBusy = true;
      harness.answerDelay = const Duration(milliseconds: 650);
      var inFlight = 0, peak = 0;
      final starts = <int>[], ends = <int>[];
      final clock = Stopwatch()..start();
      harness.signalPoll = () async {
        starts.add(clock.elapsedMilliseconds);
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 90));
        inFlight--;
        ends.add(clock.elapsedMilliseconds);
      };
      harness.client = harness.makeClient(hybridStartup: true);
      expect(
        await harness.downloadPrefix(bootstrapPiece: (_) async => null),
        harness.bytes.length,
        reason: jsonEncode(harness.logs.map((e) => e.toJson()).toList()),
      );
      expect(peak, 1);
      expect(starts.length, greaterThanOrEqualTo(3));
      expect(
        starts[1] - ends[0],
        inInclusiveRange(80, 200),
        reason:
            'Discovery must not turn the first empty poll into idle backoff',
      );
      expect(starts[2] - ends[1], inInclusiveRange(80, 200));
    },
  );

  test(
    'shared channel can open after 10 seconds within original 15 second budget',
    () async {
      harness.enableTrickle();
      harness.manifestOverride['p2p_background_connect_timeout_ms'] = 15000;
      harness.manifestOverride['peer_shared_deadline_supported'] = true;
      harness.firstPeerId = 'abababababababababababababababab';
      harness.advertisePeer = true;
      harness.seedBusy = true;
      harness.channelOpenDelay = const Duration(seconds: 12);
      harness.client = harness.makeClient(
        hybridStartup: true,
        timeouts: const AppUpgradeP2PTimeouts(),
      );
      expect(
        await harness.downloadPrefix(bootstrapPiece: (_) async => null),
        harness.bytes.length,
      );
      final selected = harness.logs.firstWhere(
        (e) => e.code == 'probe_verified',
      );
      expect(selected.elapsedMs, inInclusiveRange(12000, 15000));
      expect(harness.peers.every((p) => p.closed), true);
    },
  );

  test('shared channel wait never extends original startup deadline', () async {
    harness.enableTrickle(budgetMs: 500);
    harness.manifestOverride['p2p_background_connect_timeout_ms'] = 500;
    harness.manifestOverride['peer_shared_deadline_supported'] = true;
    harness.firstPeerId = 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';
    harness.advertisePeer = true;
    harness.seedBusy = true;
    harness.channelOpenDelay = const Duration(seconds: 2);
    harness.client = harness.makeClient(hybridStartup: true);
    final clock = Stopwatch()..start();
    expect(await harness.downloadPrefix(bootstrapPiece: (_) async => null), 0);
    expect(clock.elapsedMilliseconds, lessThan(1200));
    expect(harness.peers.every((p) => p.closed), true);
  });

  test(
    'invalid optional startup policy cannot extend budgets or enable fast polls',
    () {
      for (final value in [null, '100', 99, 251, true]) {
        harness.manifestOverride['peer_fast_signal_poll_ms'] = value;
        harness.manifestOverride['peer_shared_deadline_supported'] = 'true';
        final policy = harness.parsedManifest();
        expect(policy.fastSignalPollMs, null);
        expect(policy.sharedDeadline, false);
      }
    },
  );

  test(
    'fast candidates can arrive before a slow Offer acknowledgement',
    () async {
      harness.enableTrickle(budgetMs: 2000);
      harness.firstPeerId = 'efefefefefefefefefefefefefefefef';
      harness.advertisePeer = true;
      harness.seedBusy = true;
      harness.localIceCandidates = [
        RTCIceCandidate('candidate:1 1 udp 1 192.0.2.1 5001 typ host', '0', 0),
      ];
      final candidateAccepted = Completer<void>();
      harness.signalPost = () => candidateAccepted.future;
      harness.candidatePost = (request) async {
        if (request.uri.pathSegments.last == 'candidate' &&
            !candidateAccepted.isCompleted) {
          candidateAccepted.complete();
        }
      };
      harness.client = harness.makeClient(
        hybridStartup: true,
        fastSignaling: true,
      );
      expect(
        await harness.downloadPrefix(bootstrapPiece: (_) async => null),
        harness.bytes.length,
      );
      expect(candidateAccepted.isCompleted, true);
      expect(harness.peers.every((p) => p.closed), true);
    },
  );

  test(
    'full-hash receipt is issued only after the closed file passes SHA',
    () async {
      var verified = false;
      expect(
        await harness.downloadPrefix(onFileVerified: () => verified = true),
        harness.bytes.length,
      );
      expect(verified, true);
      final renamed = await harness.part.rename(
        '${directory.path}/verified.apk',
      );
      expect(await renamed.readAsBytes(), harness.bytes);
    },
  );

  test('post-piece disk corruption cannot issue a full-hash receipt', () async {
    var verified = false;
    await harness.downloadPrefix(
      onFileVerified: () => verified = true,
      onProgress: (received, total) {
        if (received != total) return;
        final disk = harness.part.openSync(mode: FileMode.append);
        disk.setPositionSync(total - 1);
        disk.writeByteSync(255);
        disk.closeSync();
      },
    );
    await _settle();
    expect(verified, false);
    await harness.waitForPath('outcome');
    expect(harness.body('outcome')['verified'], false);
    expect(harness.body('outcome')['reason_code'], 'file_checksum_mismatch');
  });

  test(
    'first verified seed wins immediately even while users are connecting',
    () async {
      harness.enableTrickle();
      harness.advertisePeer = true;
      harness.answerDelay = const Duration(milliseconds: 500);
      harness.client = harness.makeClient(
        hybridStartup: true,
        fastSignaling: true,
      );
      expect(
        await harness.downloadPrefix(bootstrapPiece: (_) async => null),
        harness.bytes.length,
      );
      final selected = harness.logs.firstWhere(
        (e) => e.code == 'source_selected',
      );
      expect(selected.source, 'seed');
      final first = harness.logs.firstWhere(
        (e) => e.stage == 'attempt' && e.code == 'piece_verified',
      );
      expect(selected.elapsedMs! - first.elapsedMs!, lessThan(100));
      expect(
        harness.logs.any((e) => e.code == 'seed_waiting_for_peers'),
        false,
      );
      expect(
        harness.logs
            .firstWhere(
              (e) => e.stage == 'attempt' && e.code == 'piece_verified',
            )
            .source,
        'seed',
      );
    },
  );

  test('silent users never delay a ready verified seed', () async {
    harness.enableTrickle();
    harness.advertisePeer = true;
    harness.suppressAnswer = true;
    harness.client = harness.makeClient(
      hybridStartup: true,
      fastSignaling: true,
    );
    final watch = Stopwatch()..start();
    expect(
      await harness.downloadPrefix(bootstrapPiece: (_) async => null),
      harness.bytes.length,
    );
    expect(
      harness.logs.firstWhere((e) => e.code == 'source_selected').source,
      'seed',
    );
    expect(watch.elapsedMilliseconds, lessThan(2000));
    final first = harness.logs.firstWhere(
      (e) => e.stage == 'attempt' && e.code == 'piece_verified',
    );
    final selected = harness.logs.firstWhere((e) => e.code == 'probe_verified');
    expect(selected.elapsedMs! - first.elapsedMs!, lessThan(100));
    expect(harness.logs.any((e) => e.code == 'seed_waiting_for_peers'), false);
    expect(harness.peers.every((p) => p.closed), true);
  });

  test(
    'negotiated user pipeline verifies the full file with one-piece replenishment',
    () async {
      harness.enableTrickle();
      harness.advertisePeer = true;
      harness.seedBusy = true;
      harness.pipelineCapable = true;
      harness.pieceDelay = const Duration(milliseconds: 5);
      harness.bytes = Uint8List.fromList(
        List.generate(9 * 1048576 + 79, (i) => i % 251),
      );
      harness.advertisedPieces = List.generate(10, (i) => i);
      harness.client = harness.makeClient(
        hybridStartup: true,
        fastSignaling: true,
      );
      expect(
        await harness.downloadPrefix(bootstrapPiece: (_) async => null),
        harness.bytes.length,
      );
      expect(harness.part.readAsBytesSync(), harness.bytes);
      expect(harness.logs.any((e) => e.code == 'pipeline_four_selected'), true);
      final controls = harness.peers
          .expand((p) => p.channel.sent)
          .where((m) => !m.isBinary)
          .map((m) => jsonDecode(m.text) as Map)
          .where((m) => m['type'] == 'get-pieces')
          .toList();
      expect(controls.first['indices'], [1, 2, 3, 4]);
      expect(
        controls.skip(1).every((c) => (c['indices'] as List).length == 1),
        true,
      );
    },
  );

  test(
    'cancel before any verified source closes every parallel connection',
    () async {
      harness.enableTrickle();
      harness.advertisePeer = true;
      harness.suppressAnswer = true;
      harness.client = harness.makeClient(
        hybridStartup: true,
        fastSignaling: true,
      );
      final gate = Completer<void>();
      harness.seedGate = gate.future;
      final cancel = CancelToken();
      final download = harness.downloadPrefix(
        bootstrapPiece: (_) async => null,
        cancelToken: cancel,
      );
      final assertion = expectLater(download, throwsA(isA<DioException>()));
      await harness.waitForPath('server-offer');
      cancel.cancel();
      gate.complete();
      await assertion;
      expect(harness.peers.every((p) => p.closed), true);
    },
  );

  for (final fault in [
    'no-answer',
    'ice-stall',
    'no-data',
    'wrong-probe',
    'closed-after-takeover',
    'corrupt-after-takeover',
  ]) {
    test(
      'hybrid fault $fault keeps HTTPS advancing and verifies the full file',
      () async {
        harness.enableTrickle();
        harness.pipelineCapable = true;
        harness.bytes = Uint8List.fromList(
          List.generate(5 * 1048576 + 79, (i) => i % 251),
        );
        harness.manifestOverride['p2p_background_connect_timeout_ms'] = 15000;
        harness.manifestOverride['attempt_diagnostics_supported'] = true;
        harness.advertisePeer = true;
        harness.advertiseSecondPeer = true;
        harness.advertisedPieces = [0, 1, 2, 3, 4, 5];
        harness.suppressAnswer = fault == 'no-answer';
        harness.seedBusy = fault == 'no-answer';
        harness.iceNeverCompletes = fault == 'ice-stall';
        if (fault == 'ice-stall') {
          harness.manifestOverride['trickle_ice_supported'] = false;
        }
        if (fault == 'no-data') harness.dropIndex = 0;
        if (fault == 'wrong-probe') harness.corruptIndex = 0;
        if (fault == 'closed-after-takeover') harness.closeIndex = 2;
        if (fault == 'corrupt-after-takeover') harness.corruptIndex = 2;
        harness.client = harness.makeClient(
          hybridStartup: true,
          fastSignaling: true,
          peerBatchPieces: 1,
        );
        final https = Dio(), telemetry = Dio();
        telemetry.interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) =>
                h.resolve(Response(requestOptions: r, statusCode: 201)),
          ),
        );
        final starts = <int>[];
        https.interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              final start = int.parse(
                RegExp(
                  r'bytes=(\d+)-',
                ).firstMatch(r.headers['range'] as String)!.group(1)!,
              );
              starts.add(start);
              final headers = {
                'content-range': [
                  'bytes $start-${harness.bytes.length - 1}/${harness.bytes.length}',
                ],
                'etag': ['"release-test"'],
                'x-download-session-id': ['0123456789abcdef'],
              };
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 206,
                  headers: Headers.fromMap(headers),
                  data: ResponseBody(
                    () async* {
                      for (
                        var at = start;
                        at < harness.bytes.length;
                        at += 65536
                      ) {
                        if (r.cancelToken!.isCancelled) return;
                        yield Uint8List.sublistView(
                          harness.bytes,
                          at,
                          (at + 65536).clamp(0, harness.bytes.length),
                        );
                        await Future<void>.delayed(
                          const Duration(milliseconds: 20),
                        );
                      }
                    }(),
                    206,
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
          httpsHeadStart: true,
          serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
          supportDirectoryLoader: () async => directory,
        );
        final progress = <int>[];
        final file = await downloader.download(
          info: harness.info,
          url: _url,
          backupUrl: null,
          refreshRelease: () async => harness.info,
          cancelToken: CancelToken(),
          onProgress: (bytes, _) => progress.add(bytes),
        );
        expect(
          sha256.convert(await file.readAsBytes()).toString(),
          harness.info.sha256,
        );
        expect(
          progress.where((b) => b > 0 && b < harness.bytes.length).length,
          greaterThan(2),
        );
        expect(starts.first, 0);
        if (fault == 'closed-after-takeover' ||
            fault == 'corrupt-after-takeover') {
          expect(harness.logs.any((e) => e.code == 'probe_verified'), true);
          expect(starts.skip(1).any((at) => at > 0), true);
        } else {
          expect(downloader.lastHttpsBodyBytes, harness.bytes.length);
          expect(harness.client.lastDownloadUsedP2P, false);
        }
        https.close(force: true);
        telemetry.close(force: true);
      },
    );
  }

  for (final scenario in [
    'baseline-1',
    'mixed',
    'baseline-2',
    'mixed-repeat-2',
    'baseline-3',
    'mixed-repeat-3',
    'p2p-fails',
    'https-finishes-first',
    'https-full-corrupt',
    'https-full-truncated',
    'cancel-after-https-body',
    'multi-prefix',
    'partial-handoff',
    'p2p-fails-after-handoff',
    'https-body-error',
    'resume-partial',
    'seed-handoff',
    'range-ignored',
    'redirect-partial',
    'redirect-full',
    'redirect-external',
    'redirect-loop',
    'redirect-unsafe',
    'redirect-range-mismatch',
    'redirect-etag-mismatch',
    'corrupt-prefix',
    'https-slow',
    'https-stalls',
    'cancel',
    'adaptive-user',
    'adaptive-seed',
    'adaptive-parallel',
    'adaptive-silent',
    'adaptive-http-first',
    'adaptive-cancel',
    'adaptive-late-seed',
    'adaptive-corrupt-http',
    'adaptive-near-complete',
    'adaptive-two-users',
    'adaptive-two-users-race',
    'adaptive-two-users-seed',
    'adaptive-answer-grace',
    'adaptive-late-user',
  ]) {
    test('HTTPS head start $scenario preserves integrity and accounting', () async {
      harness.enableTrickle();
      final adaptive = scenario.startsWith('adaptive-');
      if (adaptive) {
        harness.manifestOverride['p2p_background_connect_timeout_ms'] = 15000;
      }
      harness.manifestOverride['https_bootstrap_diagnostics_supported'] = true;
      harness.manifestOverride['final_traffic_diagnostics_supported'] = true;
      harness.advertisePeer =
          scenario != 'seed-handoff' &&
          scenario != 'adaptive-seed' &&
          scenario != 'adaptive-late-seed';
      // These cases exercise a user winner; give the seed an explicitly slower
      // response now that it joins immediately rather than after a fixed wait.
      if (adaptive &&
          !{
            'adaptive-seed',
            'adaptive-parallel',
            'adaptive-two-users-seed',
            'adaptive-late-seed',
            'adaptive-answer-grace',
            'adaptive-http-first',
            'adaptive-silent',
            'adaptive-near-complete',
            'adaptive-cancel',
          }.contains(scenario)) {
        harness.seedDelay = const Duration(milliseconds: 900);
      }
      if (scenario == 'adaptive-late-seed') {
        harness.seedDelay = const Duration(milliseconds: 8500);
      }
      if (scenario.startsWith('adaptive-two-users')) {
        harness.advertiseSecondPeer = true;
        harness.suppressFirstAnswer = scenario == 'adaptive-two-users';
        harness.suppressAnswer = scenario == 'adaptive-two-users-seed';
      }
      if (scenario == 'adaptive-late-user') {
        harness.answerDelay = const Duration(milliseconds: 8500);
        harness.seedBusy = true;
      }
      if (scenario == 'adaptive-parallel') harness.suppressAnswer = true;
      if (scenario == 'adaptive-silent') harness.dropIndex = 0;
      if (scenario == 'adaptive-answer-grace') {
        harness.answerDelay = const Duration(milliseconds: 3000);
        harness.seedDelay = const Duration(seconds: 10);
      }
      if (scenario == 'adaptive-two-users-race') harness.duplicateAnswer = true;
      harness.advertisedPieces = adaptive || scenario == 'multi-prefix'
          ? [0, 1, 2, 3, 4, 5]
          : scenario == 'resume-partial'
          ? [0, 1, 2, 3]
          : [0, 1, 2];
      harness.bytes = Uint8List.fromList(
        List.generate(
          AppUpgradeP2PManifest.chunkSize *
                  (adaptive
                      ? 5
                      : scenario == 'multi-prefix'
                      ? 5
                      : scenario == 'resume-partial'
                      ? 3
                      : 2) +
              79,
          (i) => i % 251,
        ),
      );
      harness.remoteDescriptionDelay = Duration(
        milliseconds: scenario == 'adaptive-answer-grace' ? 1700 : 300,
      );
      harness.client = harness.makeClient(
        hybridStartup: adaptive,
        fastSignaling: true,
        peerBatchPieces: scenario == 'p2p-fails-after-handoff' ? 1 : 4,
        sourceTimeout: Duration(milliseconds: adaptive ? 4000 : 700),
      );
      if (scenario == 'p2p-fails-after-handoff') harness.corruptIndex = 2;
      if (scenario == 'p2p-fails' ||
          scenario == 'cancel' ||
          scenario == 'https-full-corrupt' ||
          scenario == 'https-full-truncated' ||
          scenario == 'cancel-after-https-body') {
        harness.iceNeverCompletes = true;
        harness.manifestOverride['trickle_ice_supported'] = false;
      }
      final https = Dio(), telemetry = Dio(), cancel = CancelToken();
      final httpRequests = <RequestOptions>[], reported = <RequestOptions>[];
      final progress = <int>[];
      telemetry.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            reported.add(r);
            h.resolve(Response(requestOptions: r, statusCode: 201));
          },
        ),
      );
      https.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            httpRequests.add(request);
            final bootstrap =
                request.headers['range'] ==
                'bytes=${scenario == 'resume-partial' ? AppUpgradeP2PManifest.chunkSize + 65536 : 0}-${harness.bytes.length - 1}';
            if (bootstrap &&
                scenario.startsWith('redirect-') &&
                (httpRequests.length == 1 || scenario == 'redirect-loop')) {
              final location = scenario == 'redirect-unsafe'
                  ? 'http://download1.csnas.asia/lifering/download'
                  : scenario == 'redirect-external'
                  ? 'https://object.example.test/release.apk?signature=test'
                  : 'https://download1.csnas.asia/lifering/download';
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': [location],
                  }),
                  data: ResponseBody.fromBytes(
                    [],
                    302,
                    headers: {
                      'location': [location],
                    },
                  ),
                ),
              );
              return;
            }
            if (bootstrap &&
                (scenario == 'https-slow' || scenario == 'cancel')) {
              await request.cancelToken!.whenCancel;
              handler.reject(request.cancelToken!.cancelError!);
              return;
            }
            final start = int.parse(
              RegExp(r'bytes=(\d+)-')
                  .firstMatch(
                    request.headers['range'] as String? ?? 'bytes=0-',
                  )!
                  .group(1)!,
            );
            final end = harness.bytes.length - 1;
            final status =
                bootstrap &&
                    (scenario == 'range-ignored' ||
                        scenario == 'redirect-full' ||
                        scenario == 'redirect-external')
                ? 200
                : 206;
            final headers = {
              'content-range': [
                'bytes ${scenario == 'redirect-range-mismatch' ? start + 1 : start}-$end/${harness.bytes.length}',
              ],
              'etag': [
                scenario == 'redirect-external' ||
                        scenario == 'redirect-etag-mismatch'
                    ? '"different-origin"'
                    : '"release-test"',
              ],
              'x-download-session-id': ['0123456789abcdef'],
            };
            final bytes = Uint8List.fromList(
              harness.bytes.sublist(start, end + 1),
            );
            if (bootstrap &&
                (scenario == 'corrupt-prefix' ||
                    scenario == 'https-full-corrupt' ||
                    scenario == 'adaptive-corrupt-http')) {
              bytes[0] ^= 1;
            }
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: status,
                headers: Headers.fromMap(headers),
                data: bootstrap && scenario == 'https-full-truncated'
                    ? ResponseBody.fromBytes(
                        bytes.sublist(0, bytes.length - 37),
                        status,
                        headers: headers,
                      )
                    : bootstrap && scenario == 'https-stalls'
                    ? ResponseBody(
                        (StreamController<Uint8List>()
                              ..add(Uint8List.sublistView(bytes, 0, 65536)))
                            .stream,
                        status,
                        headers: headers,
                      )
                    : bootstrap &&
                          scenario != 'https-finishes-first' &&
                          scenario != 'https-full-corrupt' &&
                          scenario != 'cancel-after-https-body' &&
                          scenario != 'adaptive-http-first' &&
                          scenario != 'range-ignored'
                    ? ResponseBody(
                        () async* {
                          final pieces = scenario == 'adaptive-near-complete'
                              ? 4
                              : scenario == 'multi-prefix'
                              ? 3
                              : 1;
                          if (scenario == 'partial-handoff') {
                            yield Uint8List.sublistView(
                              bytes,
                              0,
                              AppUpgradeP2PManifest.chunkSize + 65536,
                            );
                            await Future<void>.delayed(
                              const Duration(milliseconds: 600),
                            );
                            yield Uint8List.sublistView(
                              bytes,
                              AppUpgradeP2PManifest.chunkSize + 65536,
                              AppUpgradeP2PManifest.chunkSize * 2,
                            );
                            await request.cancelToken!.whenCancel;
                            return;
                          }
                          if (scenario == 'https-body-error') {
                            yield Uint8List.sublistView(
                              bytes,
                              0,
                              AppUpgradeP2PManifest.chunkSize,
                            );
                            throw const HttpException(
                              'test stream interrupted',
                            );
                          }
                          yield Uint8List.sublistView(
                            bytes,
                            0,
                            AppUpgradeP2PManifest.chunkSize * pieces -
                                (scenario == 'resume-partial' ? 65536 : 0),
                          );
                          await Future.any([
                            Future<void>.delayed(
                              Duration(
                                seconds:
                                    scenario == 'adaptive-late-seed' ||
                                        scenario == 'adaptive-answer-grace' ||
                                        scenario == 'adaptive-late-user'
                                    ? 12
                                    : 3,
                              ),
                            ),
                            request.cancelToken!.whenCancel.then((_) {}),
                          ]);
                          if (!request.cancelToken!.isCancelled) {
                            yield Uint8List.sublistView(
                              bytes,
                              AppUpgradeP2PManifest.chunkSize * pieces -
                                  (scenario == 'resume-partial' ? 65536 : 0),
                            );
                          }
                        }(),
                        status,
                        headers: headers,
                      )
                    : ResponseBody.fromBytes(bytes, status, headers: headers),
              ),
            );
          },
        ),
      );
      final downloader = AppUpgradeV40DownloadClient(
        dio: https,
        p2pClient: harness.client,
        httpsHeadStart: !scenario.startsWith('baseline'),
        serviceEvents: AppUpgradeServiceEvents(dio: telemetry),
        supportDirectoryLoader: () async => directory,
      );
      final initialBytes = scenario == 'resume-partial'
          ? AppUpgradeP2PManifest.chunkSize + 65536
          : 0;
      if (initialBytes > 0) {
        final info = harness.info;
        final dir = Directory('${directory.path}/app-upgrades');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/test-release-${info.sha256.substring(0, 12)}.apk.part',
        ).writeAsBytes(harness.bytes.sublist(0, initialBytes));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'app_upgrade.v40.task.${info.releaseId}',
          jsonEncode({
            'releaseId': info.releaseId,
            'slug': info.downloadSlug,
            'sha256': info.sha256,
            'fileSize': info.fileSize,
            'etag': info.downloadEtag,
            'sessionId': '',
            'httpOrigin': Uri.parse(_url).origin,
            'p2pContributed': false,
            'nonServiceContributed': false,
          }),
        );
      }
      final watch = Stopwatch()..start();
      int? firstProgressMs;
      final download = downloader.download(
        info: harness.info,
        url: _url,
        backupUrl: null,
        refreshRelease: () async => harness.info,
        cancelToken: cancel,
        onProgress: (received, _) {
          if (received > 0) firstProgressMs ??= watch.elapsedMilliseconds;
          progress.add(received);
          if (scenario == 'cancel-after-https-body' &&
              received == harness.bytes.length) {
            cancel.cancel('test_cancel_before_verification');
          }
        },
      );
      if (scenario == 'cancel' ||
          scenario == 'adaptive-cancel' ||
          scenario == 'cancel-after-https-body') {
        final ended = expectLater(download, throwsA(isA<DioException>()));
        if (scenario != 'cancel-after-https-body') {
          await harness.waitForPath('session');
          cancel.cancel('test');
        }
        await ended;
        expect(
          harness.logs.any((e) => e.code == 'verified_https_hash_reused'),
          false,
        );
        expect(
          await Directory(
            '${directory.path}/app-upgrades',
          ).list().where((f) => f.path.endsWith('.https-bootstrap')).length,
          0,
        );
        return;
      }
      final file = await download;
      watch.stop();
      expect(await file.readAsBytes(), harness.bytes);
      final reusedHash = harness.logs.any(
        (e) => e.code == 'verified_hash_reused',
      );
      if (harness.body('outcome')['outcome'] == 'p2p_complete') {
        expect(reusedHash, true);
        expect(
          harness.logs.where((e) => e.code == 'file_hash_profile'),
          isEmpty,
        );
        expect(
          harness.logs
              .singleWhere((e) => e.code == 'transfer_profile')
              .metrics['full_sha_scans'],
          1,
        );
      } else {
        // Partial P2P / pure HTTPS must not inherit a stale full-hash receipt.
        expect(reusedHash, false);
        expect(
          harness.logs.where((e) => e.code == 'file_hash_profile'),
          isNotEmpty,
        );
      }
      if (scenario == 'https-finishes-first' ||
          scenario == 'adaptive-http-first') {
        expect(
          harness.logs.where((e) => e.code == 'https_file_promoted'),
          hasLength(1),
        );
        expect(
          harness.logs.where((e) => e.code == 'verified_https_hash_reused'),
          hasLength(1),
        );
        expect(
          harness.logs.where((e) => e.code == 'file_hash_profile'),
          hasLength(1),
        );
        expect(httpRequests, hasLength(1));
      }
      if (scenario == 'https-full-corrupt' ||
          scenario == 'https-full-truncated') {
        expect(
          harness.logs.any((e) => e.code == 'verified_https_hash_reused'),
          false,
        );
        expect(httpRequests.length, greaterThan(1));
      }
      expect(progress.where((n) => n > 0), isNotEmpty);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      if (scenario.startsWith('baseline')) {
        expect(httpRequests, isEmpty);
      } else {
        expect(
          httpRequests.first.headers['range'],
          'bytes=$initialBytes-${harness.bytes.length - 1}',
        );
      }
      await _settle();
      await harness.waitForPath('traffic');
      final traffic = harness.body('traffic');
      expect(
        harness.body('session')['https_downloading'],
        adaptive ? true : null,
      );
      expect(traffic['https_body_bytes'], downloader.lastHttpsBodyBytes);
      expect(
        traffic['peer_verified_bytes'],
        harness.body('outcome')['peer_bytes'],
      );
      expect(
        traffic['peer_body_bytes'],
        greaterThanOrEqualTo(traffic['peer_verified_bytes'] as int),
      );
      expect(traffic['final_verified'], true);
      expect(
        harness.requests
            .lastWhere((r) => r.uri.pathSegments.last == 'traffic')
            .headers['Authorization'],
        'Bearer scoped_traffic_receipt',
      );
      if (adaptive) {
        expect(httpRequests.first.uri.origin, Uri.parse(_url).origin);
        expect(httpRequests.length, 1);
        if (scenario == 'adaptive-http-first' ||
            scenario == 'adaptive-silent' ||
            scenario == 'adaptive-near-complete') {
          expect(downloader.lastHttpsBodyBytes, harness.bytes.length);
          expect(downloader.lastBootstrapUsedBytes, 0);
          expect(traffic['peer_verified_bytes'], 0);
          expect(traffic['seed_verified_bytes'], 0);
        } else if (scenario == 'adaptive-corrupt-http') {
          expect(downloader.lastBootstrapUsedBytes, 0);
          expect(
            downloader.lastHttpsBodyBytes,
            AppUpgradeP2PManifest.chunkSize,
          );
          expect(traffic['peer_verified_bytes'], harness.bytes.length);
        } else {
          expect(
            downloader.lastBootstrapUsedBytes,
            AppUpgradeP2PManifest.chunkSize,
          );
          expect(
            downloader.lastHttpsBodyBytes,
            AppUpgradeP2PManifest.chunkSize,
          );
          final seed =
              scenario == 'adaptive-seed' ||
              scenario == 'adaptive-parallel' ||
              scenario == 'adaptive-two-users-seed' ||
              scenario == 'adaptive-late-seed';
          expect(
            traffic[seed ? 'seed_verified_bytes' : 'peer_verified_bytes'],
            harness.bytes.length - AppUpgradeP2PManifest.chunkSize,
          );
          expect(
            traffic[seed ? 'seed_body_bytes' : 'peer_body_bytes'],
            scenario == 'adaptive-two-users-race'
                ? inInclusiveRange(
                    harness.bytes.length,
                    harness.bytes.length + AppUpgradeP2PManifest.chunkSize,
                  )
                : harness.bytes.length,
          );
          final probe = harness.logs.firstWhere(
            (e) => e.stage == 'hybrid' && e.code == 'probe_verified',
          );
          expect(probe.source, seed ? 'seed' : 'peer');
          if (scenario == 'adaptive-answer-grace') {
            expect(probe.elapsedMs, greaterThan(4000));
            expect(probe.elapsedMs, lessThan(7500));
          }
          if (scenario == 'adaptive-two-users-race') {
            expect(
              harness.peers.every((p) => p.remoteDescriptionCalls <= 1),
              true,
            );
          }
          final beforeLateCallback = harness.logs.length;
          for (final peer in harness.peers) {
            peer.onIceConnectionState?.call(
              RTCIceConnectionState.RTCIceConnectionStateConnected,
            );
          }
          expect(harness.logs, hasLength(beforeLateCallback));
          if (scenario == 'adaptive-late-user') {
            expect(probe.elapsedMs, greaterThan(8000));
          }
          if (scenario == 'adaptive-late-seed') {
            expect(probe.elapsedMs, greaterThan(8000));
          }
          if (scenario.startsWith('adaptive-two-users')) {
            final offers = harness.requests
                .where(
                  (r) =>
                      r.uri.pathSegments.last == 'signal' &&
                      (r.data as Map)['type'] == 'offer',
                )
                .toList();
            expect(offers.map((r) => (r.data as Map)['peer_id']).toSet(), {
              _other,
              _second,
            });
            // A silent first user must not spend its 4 second budget before
            // the second user gets a chance. This fails under serial attempts.
            if (scenario != 'adaptive-two-users-seed') {
              expect(probe.elapsedMs, lessThan(2500));
              expect(harness.paths, contains('server-offer'));
            }
            expect(
              harness.logs.where(
                (e) => e.stage == 'hybrid' && e.code == 'source_selected',
              ),
              hasLength(1),
            );
            expect(harness.peers.every((p) => p.closed), true);
          }
          if (scenario == 'adaptive-parallel' ||
              scenario == 'adaptive-two-users-seed') {
            expect(
              harness.logs
                  .firstWhere(
                    (e) =>
                        e.stage == 'server_offer' &&
                        e.code == 'request_started',
                  )
                  .elapsedMs,
              lessThan(3000),
            );
          }
        }
      } else if (scenario.startsWith('mixed') ||
          [
            'redirect-partial',
            'redirect-full',
            'redirect-external',
          ].contains(scenario) ||
          scenario == 'multi-prefix' ||
          scenario == 'partial-handoff' ||
          scenario == 'https-body-error') {
        final prefixBytes =
            AppUpgradeP2PManifest.chunkSize *
            (scenario == 'multi-prefix'
                ? 3
                : scenario == 'partial-handoff'
                ? 2
                : 1);
        expect(downloader.lastBootstrapUsedBytes, prefixBytes);
        expect(downloader.lastHttpsBodyBytes, prefixBytes);
        final controls = harness.peers.first.channel.sent
            .where((m) => !m.isBinary)
            .map((m) => jsonDecode(m.text) as Map);
        expect(
          controls.any((m) => m['type'] == 'get-piece' && m['index'] == 0),
          false,
        );
        expect(
          harness.body('outcome')['peer_bytes'],
          harness.bytes.length - prefixBytes,
        );
        expect(
          harness.body('outcome')['diagnostics']['https_bootstrap_used_bytes'],
          prefixBytes,
        );
        expect(
          reported,
          isEmpty,
          reason: 'Do not count mixed completion as pure HTTP coverage',
        );
      } else if (scenario == 'resume-partial') {
        expect(httpRequests.length, 1);
        expect(
          downloader.lastBootstrapUsedBytes,
          AppUpgradeP2PManifest.chunkSize - 65536,
        );
        expect(
          downloader.lastHttpsBodyBytes,
          AppUpgradeP2PManifest.chunkSize - 65536,
        );
        expect(
          harness.body('outcome')['peer_bytes'],
          harness.bytes.length - AppUpgradeP2PManifest.chunkSize * 2,
        );
      } else if (scenario == 'seed-handoff') {
        expect(httpRequests.length, 1);
        expect(
          downloader.lastBootstrapUsedBytes,
          AppUpgradeP2PManifest.chunkSize,
        );
        expect(traffic['peer_body_bytes'], 0);
        expect(traffic['seed_body_bytes'], greaterThan(0));
        expect(
          traffic['seed_verified_bytes'],
          harness.bytes.length - AppUpgradeP2PManifest.chunkSize,
        );
      } else if (scenario == 'p2p-fails-after-handoff') {
        expect(httpRequests.length, 2);
        expect(
          httpRequests.last.headers['range'],
          'bytes=${AppUpgradeP2PManifest.chunkSize * 2}-',
        );
        expect(harness.client.lastDownloadUsedP2P, true);
        expect(
          traffic['peer_body_bytes'],
          greaterThan(traffic['peer_verified_bytes'] as int),
        );
      } else if (scenario == 'p2p-fails') {
        expect(
          httpRequests.length,
          1,
          reason: 'Failed ICE must not restart the running HTTPS stream',
        );
        expect(downloader.lastHttpsBodyBytes, harness.bytes.length);
        expect(harness.client.lastDownloadUsedP2P, false);
      } else if (scenario == 'https-finishes-first' ||
          scenario == 'range-ignored') {
        expect(httpRequests.length, 1);
        expect(downloader.lastHttpsBodyBytes, harness.bytes.length);
        expect(harness.client.lastDownloadUsedP2P, false);
      } else if (scenario == 'https-full-corrupt' ||
          scenario == 'https-full-truncated') {
        expect(harness.client.lastDownloadUsedP2P, false);
        expect(harness.body('outcome')['peer_bytes'], 0);
        expect(
          downloader.lastHttpsBodyBytes,
          greaterThanOrEqualTo(harness.bytes.length),
        );
      } else {
        expect(downloader.lastBootstrapUsedBytes, 0);
        expect(harness.body('outcome')['peer_bytes'], harness.bytes.length);
      }
      if (scenario.startsWith('redirect-')) {
        expect(
          httpRequests.length,
          scenario == 'redirect-loop'
              ? 6
              : scenario == 'redirect-unsafe'
              ? 1
              : 2,
        );
        if (httpRequests.length == 2) {
          expect(
            httpRequests.last.headers['range'],
            httpRequests.first.headers['range'],
          );
          if (scenario == 'redirect-external') {
            expect(httpRequests.last.headers.containsKey('X-Device-Id'), false);
            expect(
              httpRequests.last.headers.containsKey('X-Client-App-Version'),
              false,
            );
            expect(
              httpRequests.last.headers.containsKey('X-Download-Session-Id'),
              false,
            );
            expect(httpRequests.last.headers.containsKey('if-range'), false);
          } else {
            expect(httpRequests.last.headers['X-Device-Id'], isNotEmpty);
            expect(httpRequests.last.headers['if-range'], '"release-test"');
          }
        }
      }
      if (scenario.startsWith('mixed') || scenario.startsWith('baseline')) {
        final output = const String.fromEnvironment(
          'LAB_PROGRESS_BENCHMARK_OUTPUT',
        );
        if (output.isNotEmpty) {
          await File(output).writeAsString(
            '${jsonEncode({'kind': 'controlled_download_not_real_ICE', 'headStart': !scenario.startsWith('baseline'), 'scenario': scenario, 'firstProgressMs': firstProgressMs, 'completeMs': watch.elapsedMilliseconds, 'httpsBodyBytes': downloader.lastHttpsBodyBytes, 'bootstrapUsedBytes': downloader.lastBootstrapUsedBytes, 'verified': true})}\n',
            mode: FileMode.append,
          );
        }
      }
    });
  }

  test('legacy candidates are serialized and keep end marker last', () async {
    harness.enableTrickle();
    harness.client = harness.makeClient(fastSignaling: true);
    harness.localIceCandidates = List.generate(
      3,
      (i) => RTCIceCandidate(
        'candidate:$i 1 udp 1 192.168.1.99 ${1234 + i} typ host',
        '0',
        0,
      ),
    );
    final release = Completer<void>(), ready = Completer<void>();
    harness.seedGate = ready.future;
    var inFlight = 0, peak = 0, completed = 0;
    var ended = false;
    harness.candidatePost = (request) async {
      if ((request.data as Map)['candidate'] == null) {
        expect(completed, 3);
        expect(inFlight, 0);
        ended = true;
        ready.complete();
        return;
      }
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      await release.future;
      completed++;
      inFlight--;
    };
    final download = harness.downloadPrefix();
    await harness.waitForPath('server-candidate');
    await _settle();
    expect(inFlight, 1);
    expect(ended, false);
    release.complete();
    expect(await download, harness.bytes.length);
    expect(peak, 1);
    expect(ended, true);
    expect(await harness.part.readAsBytes(), harness.bytes);
  });

  test(
    'fast signaling cancellation starts no queued candidates or end marker',
    () async {
      harness.enableTrickle();
      harness.client = harness.makeClient(fastSignaling: true);
      harness.localIceCandidates = List.generate(
        6,
        (i) => RTCIceCandidate(
          'candidate:$i 1 udp 1 192.168.1.99 ${1234 + i} typ host',
          '0',
          0,
        ),
      );
      final release = Completer<void>();
      harness.seedGate = release.future;
      harness.candidatePost = (_) => release.future;
      final cancel = CancelToken();
      final download = harness.downloadPrefix(cancelToken: cancel);
      final completed = expectLater(download, throwsA(isA<DioException>()));
      await harness.waitForPath('server-candidate');
      await _settle();
      expect(harness.paths.where((p) => p == 'server-candidate').length, 1);
      cancel.cancel('test');
      release.complete();
      await completed;
      await _settle();
      expect(harness.paths.where((p) => p == 'server-candidate').length, 1);
    },
  );
  test('seed starts immediately while user discovery is stalled', () async {
    harness.enableTrickle();
    harness.manifestOverride['p2p_background_connect_timeout_ms'] = 15000;
    harness.manifestOverride['attempt_diagnostics_supported'] = true;
    final discovery = Completer<void>();
    harness.peersGate = discovery.future;
    harness.client = harness.makeClient(hybridStartup: true);
    final watch = Stopwatch()..start();
    final download = harness.downloadPrefix(bootstrapPiece: (_) async => null);
    await harness.waitForPath('server-offer');
    expect(watch.elapsedMilliseconds, lessThan(1000));
    discovery.complete();
    expect(await download, harness.bytes.length);
    await harness.waitForPath('outcome');
    final outcome = harness.requests.lastWhere(
      (r) => r.uri.pathSegments.last == 'outcome',
    );
    final attempts =
        ((outcome.data as Map)['diagnostics'] as Map)['attempts'] as List;
    expect(
      attempts.any((a) => a['alias'] == 'seed' && a['first_piece_ms'] is int),
      true,
    );
    expect(jsonEncode(attempts).contains(_other), false);
  });

  test(
    'batch candidates preserve order, bound payloads and flush EOC last',
    () async {
      harness.enableTrickle();
      harness.manifestOverride['candidate_batch_supported'] = true;
      harness.localIceCandidates = List.generate(
        32,
        (i) => RTCIceCandidate(
          'candidate:$i 1 udp 1 192.168.1.99 ${5000 + i} typ host',
          '0',
          0,
        ),
      );
      final ready = Completer<void>();
      harness.seedGate = ready.future;
      final seen = <dynamic>[];
      var inFlight = 0, peak = 0;
      harness.candidatePost = (request) async {
        final wave = ((request.data as Map)['candidates'] as List);
        expect(wave.length, inInclusiveRange(1, 8));
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        seen.addAll(wave);
        inFlight--;
        if (wave.last == null && !ready.isCompleted) ready.complete();
      };
      expect(await harness.downloadPrefix(), harness.bytes.length);
      expect(peak, 1);
      expect(seen.length, 33);
      expect(seen.last, null);
      expect(
        seen.take(32).map((v) => (v as Map)['candidate']),
        harness.localIceCandidates.map((v) => v.candidate),
      );
      expect(
        harness.requests
            .where((r) => r.uri.pathSegments.last == 'server-candidate')
            .length,
        lessThanOrEqualTo(5),
      );
    },
  );
}

Future<void> _settle() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Simulated signaling/service responses plus framed DataChannels verify the
/// production scheduler. They intentionally do not claim real ICE/NAT success.
class _LifetimeAdapter implements HttpClientAdapter {
  int closeCalls = 0;
  @override
  void close({bool force = false}) => closeCalls++;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw StateError('Lifetime fixture attempted an unexpected network path');
  }
}

class _Harness {
  String? offerSdpOverride;
  Map<String, Object>? diversityAdvice;
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
  bool failTransferDiagnostic = false;
  final List<_FakePeer> peers = [];
  List<String>? advertisedPeerIds;
  final rejectedPeerIds = <String>{};
  final stalledIcePeerIds = <String>{};
  final peerCandidateKeys = <String, Object>{};
  Future<void> Function(RequestOptions)? signalOfferHook;
  Future<void> Function(_FakeChannel)? beforeLeaseHello;
  Future<void>? ordinaryDisposeGate;
  void Function(String?)? ordinaryDisposeStarted;
  final ordinaryDisposeGates = <String, Future<void>>{};
  bool failOrdinaryDispose = false;
  bool trackPeerOwners = false;
  int badPeerHellos = 0;
  final ownerEvents = <({int index, bool disposed})>[];
  int get peakOrdinaryOwners {
    final alive = <int>{};
    var peak = 0;
    for (final event in ownerEvents) {
      if (event.disposed) {
        alive.remove(event.index);
      } else {
        alive.add(event.index);
      }
      final ordinary = alive.where((i) => peers[i].server != true).length;
      if (ordinary > peak) peak = ordinary;
    }
    return peak;
  }

  void markOffer(RequestOptions request, bool server) {
    if (!trackPeerOwners) return;
    final sdp = (request.data as Map)['sdp'];
    if (sdp is! String) return;
    final match = RegExp(r'a=x-fixture-peer-index:(\d+)').firstMatch(sdp);
    if (match != null) {
      final peer = peers[int.parse(match[1]!)];
      peer.server = server;
      peer.target = server
          ? 'server'
          : (request.data as Map)['peer_id'] as String;
    }
  }

  final List<Map<String, dynamic>> peerConfigurations = [];
  final List<Map<String, dynamic>> signals = [];
  final List<Map<String, dynamic>> remoteCandidates = [];
  List<RTCIceCandidate> localIceCandidates = [];
  bool signalRemoteCandidates = false;
  bool suppressAnswer = false;
  bool duplicateAnswer = false;
  Duration answerDelay = Duration.zero;
  bool pipelineCapable = false;
  bool p8pCapable = false;
  bool leaseCapable = false, leasePeerCapable = false;
  Future<void> Function(_FakeChannel, int, Future<void>)? beforeLeasedPiece;
  bool Function(RequestOptions)? failControlConnection;
  _PythonSender? leaseBridge;
  bool advertiseSecondPeer = false, suppressFirstAnswer = false;
  bool legacyPeer = false;
  Future<void>? seedGate, sessionGate, peersGate;
  Future<void> Function()? peersHook;
  Future<void>? peerCloseGate, cancelGate;
  int failSeedConnections = 0, cancelPending = 0;
  int hangSeedConnections = 0, seedOfferCount = 0;
  Future<void> Function(int)? seedOfferHook;
  String? cancelFault;
  Duration seedDelay = Duration.zero;
  Future<void> Function(RequestOptions)? candidatePost;
  Duration remoteDescriptionDelay = Duration.zero;
  Duration channelOpenDelay = Duration.zero;
  Future<void> Function()? signalPoll;
  void Function(_FakePeer)? remoteSetHook;
  Future<List<StatsReport>> Function()? iceStats;
  int iceStatsReads = 0;
  Future<void> Function()? signalPost;
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
  String releaseId = 'test-release';
  late AppUpgradeV40P2PClient client;
  AppUpgradeP2PNetwork network = AppUpgradeP2PNetwork.wifiUnmetered;
  Map<String, dynamic> manifestOverride = {};
  String? precomputedDigest;
  Map<String, dynamic>? precomputedManifest;
  String get payloadSha =>
      precomputedDigest ?? sha256.convert(bytes).toString();
  String firstPeerId = _other;
  bool advertisePeer = false,
      rejectSignal = false,
      seedBusy = false,
      failCandidatePosts = false,
      peersDisabled = false,
      incomingOffer = false;
  Object? seedBatchCapability;
  int? dropIndex, corruptIndex, closeIndex;
  Duration pieceDelay = Duration.zero;
  Future<void>? outcomeGate;
  Future<void>? trafficGate;
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
  void Function()? onPeerCreated;
  int sessionTimeouts = 0, outcomeTimeouts = 0;
  bool outcomeConflict = false;
  bool rejectDiagnostics = false;
  File get part => File('${directory.path}/test.apk.part');
  List<String> get paths =>
      requests.map((request) => request.uri.pathSegments.last).toList();
  Map<String, dynamic> get manifestJson =>
      precomputedManifest ??
      {
        'status': 'ok',
        'auto_start': true,
        'protocol_version': 1,
        'app_slug': 'lifering',
        'version': 'test',
        'file_size': bytes.length,
        'sha256': payloadSha,
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
        'stun_urls': ['stun:stun.l.google.com:19302'],
        'peer_api_base': '/api/app/lifering/p2p',
        'server_seed_url':
            'https://download.csnas.asia/api/app/lifering/p2p/server-offer',
        'fallback_url': _url,
        ...manifestOverride,
      };
  AppUpgradeInfo get info => AppUpgradeInfo(
    releaseId: releaseId,
    versionName: 'test',
    versionCode: 8900,
    releaseNotes: '',
    forceUpdate: false,
    downloadUrl: _url,
    fileSize: bytes.length,
    sha256: payloadSha,
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
    sha256: payloadSha,
  );
  Map body(String path) =>
      requests
              .lastWhere((request) => request.uri.pathSegments.last == path)
              .data
          as Map;
  AppUpgradeV40P2PClient makeClient({
    bool allowSharing = true,
    Duration sourceTimeout = const Duration(seconds: 3),
    Duration? sharingDuration = Duration.zero,
    AppUpgradeP2PTimeouts? timeouts,
    int batchPieces = 4,
    int peerBatchPieces = 1,
    bool prewarm = false,
    bool hybridStartup = false,
    bool enableP8P = false,
    int p8pPeerRaceLimit = 2,
    bool p8pSourcePortDiversity = false,
    bool fastSignaling = const bool.fromEnvironment('LAB_FAST_SIGNALING'),
  }) => AppUpgradeV40P2PClient(
    dio: dio,
    preferredSeedBatchPieces: batchPieces,
    preferredPeerBatchPieces: peerBatchPieces,
    prewarmSeed: prewarm,
    hybridStartup: hybridStartup,
    enableP8P: enableP8P,
    p8pPeerRaceLimit: p8pPeerRaceLimit,
    p8pSourcePortDiversity: p8pSourcePortDiversity,
    fastSignaling: fastSignaling,
    isAndroid: true,
    networkReader: () async => network,
    networkEvents: events.stream,
    allowSharing: allowSharing,
    diagnostic: (event) {
      logs.add(event);
      if (failTransferDiagnostic) {
        throw StateError('private diagnostic observer');
      }
    },
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
      onPeerCreated?.call();
      if (trackPeerOwners) {
        ownerEvents.add((index: peers.length - 1, disposed: false));
      }
      await creationGate;
      return peer;
    },
  );
  Future<int> downloadPrefix({
    String url = _url,
    CancelToken? cancelToken,
    Future<Uint8List?> Function(int)? bootstrapPiece,
    Future<void> Function()? bootstrapHandoff,
    int Function()? bootstrapReceivedBytes,
    void Function()? bootstrapRejected,
    Future<Uint8List> Function(int, CancelToken)? p8pRangePiece,
    void Function(int, int)? onProgress,
    void Function()? onFileVerified,
  }) => client.downloadVerifiedPrefix(
    downloadUrl: url,
    expectedSlug: 'lifering',
    expectedVersion: 'test',
    expectedFileSize: bytes.length,
    expectedSha256: payloadSha,
    partFile: part,
    onProgress: onProgress ?? (_, _) {},
    cancelToken: cancelToken,
    bootstrapPiece: bootstrapPiece,
    bootstrapHandoff: bootstrapHandoff,
    bootstrapReceivedBytes: bootstrapReceivedBytes,
    bootstrapRejected: bootstrapRejected,
    p8pRangePiece: p8pRangePiece,
    onFileVerified: onFileVerified,
  );

  Future<void> _http(
    RequestOptions request,
    RequestInterceptorHandler handler,
  ) async {
    requests.add(request);
    if (failControlConnection?.call(request) == true) {
      handler.reject(
        DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
          error: const SocketException('Controlled signaling outage'),
        ),
      );
      return;
    }
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
          if (manifestOverride['final_traffic_diagnostics_supported'] == true)
            'traffic_receipt': 'scoped_traffic_receipt',
          'heartbeat_interval': 20,
          if (sessionShareDenied) 'share_enabled': false,
        };
      case 'peers':
        await peersGate;
        await peersHook?.call();
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
                    for (final peerId
                        in advertisedPeerIds ??
                            [firstPeerId, if (advertiseSecondPeer) _second])
                      {
                        'peer_id': peerId,
                        if (diversityAdvice != null)
                          'ice_diversity': diversityAdvice,
                        if (peerCandidateKeys.containsKey(peerId))
                          'candidate_key': peerCandidateKeys[peerId],
                        'pieces': advertisedPieces,
                        if (leasePeerCapable)
                          'p8p_transfer': P8PTransferProtocol.capability,
                        if (manifestOverride['trickle_ice_supported'] == true &&
                            !legacyPeer)
                          'trickle_ice_supported': true,
                      },
                  ]
                : [],
          };
        }
      case 'signals':
        await signalPoll?.call();
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
        };
        signals.clear();
        remoteCandidates.clear();
      case 'signal':
        if (signalOfferHook != null) await signalOfferHook!(request);
        markOffer(request, false);
        await signalPost?.call();
        if (rejectSignal ||
            rejectedPeerIds.contains((request.data as Map)['peer_id'])) {
          status = 404;
          data = {'error': 'peer_not_available'};
        } else {
          status = 202;
          if ((request.data as Map)['type'] == 'offer') {
            final target = (request.data as Map)['peer_id'] as String;
            if (!suppressAnswer && !(suppressFirstAnswer && target == _other)) {
              void answer() {
                for (var i = 0; i < (duplicateAnswer ? 2 : 1); i++) {
                  signals.add({
                    'from_peer_id': target,
                    'type': 'answer',
                    'sdp': 'v=0',
                  });
                }
              }

              if (answerDelay == Duration.zero) {
                answer();
              } else {
                Timer(answerDelay, answer);
              }
            }
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
        markOffer(request, true);
        await seedOfferHook?.call(++seedOfferCount);
        await seedGate;
        await Future<void>.delayed(seedDelay);
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
            if (seedBatchCapability != null)
              'max_batch_pieces': seedBatchCapability,
          };
        }
      case 'server-cancel':
        await cancelGate;
        if (cancelFault == 'pending' || cancelPending-- > 0) {
          status = 408;
          data = {'error': 'server_offer_cancel_pending'};
        } else if (cancelFault == 'unavailable') {
          status = 503;
          data = {'error': 'server_offer_cancel_unavailable'};
        } else {
          data = {
            'ok': true,
            'state': 'closed',
            'offer_id': cancelFault == 'wrong_identity'
                ? 'different'
                : (request.data as Map)['offer_id'],
          };
        }
      case 'candidate':
      case 'server-candidate':
        await candidatePost?.call(request);
        if (failCandidatePosts) {
          status = 503;
          data = {'error': 'server_seed_unavailable'};
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
      case 'traffic':
        await trafficGate;
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

class _FakePeer extends RTCPeerConnection {
  _FakePeer(this.harness)
    : channel = _FakeChannel(harness),
      fixtureIndex = harness.peers.length;
  final _Harness harness;
  final int fixtureIndex;
  bool? server;
  String? target;
  String fixtureSdp(String text) => harness.trackPeerOwners
      ? '$text\r\na=x-fixture-peer-index:$fixtureIndex\r\n'
      : text;
  final _FakeChannel channel;
  RTCSessionDescription? local;
  bool closed = false;
  bool disposed = false;
  final disposeCompleted = Completer<void>();
  bool gatherComplete = false;
  Timer? gatherTimer, channelTimer;
  bool remoteSet = false, candidateBeforeDescription = false;
  int remoteDescriptionCalls = 0;
  final List<RTCIceCandidate> addedCandidates = [];
  @override
  Future<RTCDataChannel> createDataChannel(
    String label,
    RTCDataChannelInit init,
  ) async {
    expect(label, isIn(['lifering-apk-p2p-v1', P8PTransferProtocol.channel]));
    channel.channelLabel = label;
    expect(init.ordered, true);
    expect(init.maxRetransmits, -1);
    return channel;
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    expect(constraints?['mandatory'], {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    });
    return RTCSessionDescription(
      fixtureSdp(harness.offerSdpOverride ?? 'v=0\r\na=partial'),
      'offer',
    );
  }

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
          fixtureSdp(
            harness.offerSdpOverride ??
                'v=0\r\na=candidate:1 1 udp 1 192.168.1.99 1234 typ host\r\na=candidate:2 1 udp 1 2001:db8::99 1234 typ host\r\n',
          ),
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
    remoteDescriptionCalls++;
    await Future<void>.delayed(harness.remoteDescriptionDelay);
    remoteSet = true;
    harness.remoteSetHook?.call(this);
    if (harness.stalledIcePeerIds.contains(target)) {
      onIceConnectionState?.call(
        RTCIceConnectionState.RTCIceConnectionStateChecking,
      );
      return;
    }
    if (description.type == 'answer' && harness.hangSeedConnections-- > 0) {
      return;
    }
    if (description.type == 'answer' && harness.failSeedConnections-- > 0) {
      onIceConnectionState?.call(
        RTCIceConnectionState.RTCIceConnectionStateFailed,
      );
      return;
    }
    onIceConnectionState?.call(
      RTCIceConnectionState.RTCIceConnectionStateConnected,
    );
    if (harness.channelOpenDelay == Duration.zero) {
      channel.open();
    } else {
      channelTimer = Timer(harness.channelOpenDelay, () {
        if (!closed) channel.open();
      });
    }
    if (description.type == 'offer') onDataChannel?.call(channel);
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    candidateBeforeDescription |= !remoteSet;
    addedCandidates.add(candidate);
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async {
    harness.iceStatsReads++;
    return await harness.iceStats?.call() ?? [];
  }

  @override
  Future<void> close() async {
    await harness.peerCloseGate;
    closed = true;
    gatherTimer?.cancel();
    channelTimer?.cancel();
    await channel.close();
  }

  @override
  Future<void> dispose() async {
    await close();
    if (server != true) {
      harness.ordinaryDisposeStarted?.call(target);
      await harness.ordinaryDisposeGates[target];
      await harness.ordinaryDisposeGate;
      if (harness.failOrdinaryDispose) {
        throw StateError('synthetic native dispose failure');
      }
    }
    if (!disposed && harness.trackPeerOwners) {
      harness.ownerEvents.add((index: fixtureIndex, disposed: true));
    }
    disposed = true;
    if (!disposeCompleted.isCompleted) disposeCompleted.complete();
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
  Future<void> responseQueue = Future<void>.value();
  bool pipeline = false;
  int? p8pWindow;
  String channelLabel = 'lifering-apk-p2p-v1';
  final _leaseCancel = <int, Completer<void>>{};
  RTCDataChannelState _state = RTCDataChannelState.RTCDataChannelConnecting;
  @override
  RTCDataChannelState get state => _state;
  @override
  String get label => channelLabel;
  @override
  int get id => 1;
  @override
  int get bufferedAmount => 0;
  @override
  Future<int> getBufferedAmount() async => 0;
  void open() {
    _state = RTCDataChannelState.RTCDataChannelOpen;
    _states.add(_state);
  }

  void receiveText(Map<String, Object?> body) =>
      onMessage?.call(RTCDataChannelMessage(jsonEncode(body)));
  @override
  Future<void> send(RTCDataChannelMessage message) async {
    sent.add(message);
    if (message.isBinary) return;
    final control = jsonDecode(message.text) as Map;
    if (channelLabel == P8PTransferProtocol.channel) {
      if (harness.leaseBridge != null) {
        harness.leaseBridge!.bind(this);
        harness.leaseBridge!.send(message.text);
        return;
      }
      if (!harness.leaseCapable) {
        await close();
        return;
      }
      if (control['type'] == 'hello') {
        void reply() {
          if (_state != RTCDataChannelState.RTCDataChannelOpen) return;
          final badIdentity =
              harness.badPeerHellos > 0 &&
              harness.peers.any(
                (p) => identical(p.channel, this) && p.server == false,
              );
          if (badIdentity) harness.badPeerHellos--;
          receiveText({
            'type': 'hello',
            'version': 1,
            'generation': control['generation'],
            'sha256': badIdentity ? '0' * 64 : harness.payloadSha,
            'max_inflight': 4,
          });
        }

        if (harness.beforeLeaseHello != null) {
          // A delayed remote reply does not block the local native send call.
          unawaited(() async {
            await harness.beforeLeaseHello!(this);
            reply();
          }());
        } else {
          reply();
        }
      } else if (control['type'] == 'get') {
        final id = control['request_id'] as int;
        final stop = _leaseCancel[id] = Completer<void>();
        responseQueue = responseQueue.then(
          (_) => _respondLeased(control, stop),
        );
      } else if (control['type'] == 'cancel') {
        final stop = _leaseCancel[control['request_id']];
        if (stop != null && !stop.isCompleted) stop.complete();
      }
      return;
    }
    if (control['type'] != 'get-piece' && control['type'] != 'get-pieces') {
      return;
    }
    if (control['pipeline_window'] == 4 && harness.pipelineCapable) {
      pipeline = true;
    }
    final extension = control['p8p'];
    if (harness.p8pCapable && extension is Map && extension['version'] == 1) {
      p8pWindow = extension['window'] as int;
    }
    final indices = control['type'] == 'get-pieces'
        ? (control['indices'] as List).cast<int>()
        : [control['index'] as int];
    if (pipeline) {
      responseQueue = responseQueue.then((_) => _respond(indices));
      return;
    }
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
      if (harness.closeIndex == index) {
        await close();
        return;
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
        if (pipeline) 'pipeline_window': 4,
        if (p8pWindow != null)
          'p8p': {'version': 1, 'window': p8pWindow, 'max_window': 4},
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

  Future<void> _respondLeased(Map control, Completer<void> stop) async {
    final id = control['request_id'] as int, index = control['index'] as int;
    await harness.beforeLeasedPiece?.call(this, index, stop.future);
    Map<String, Object?> marker(String kind) => {
      'type': kind,
      'version': 1,
      'generation': control['generation'],
      'request_id': id,
      'index': index,
    };
    if (harness.dropIndex == index) {
      await stop.future;
    } else if (harness.pieceDelay != Duration.zero) {
      await Future.any([Future<void>.delayed(harness.pieceDelay), stop.future]);
    }
    if (_state == RTCDataChannelState.RTCDataChannelClosed) return;
    if (stop.isCompleted) {
      receiveText(marker('cancelled'));
      _leaseCancel.remove(id);
      return;
    }
    if (harness.closeIndex == index) {
      await close();
      return;
    }
    final start = index * AppUpgradeP2PManifest.chunkSize;
    final end = (start + AppUpgradeP2PManifest.chunkSize).clamp(
      0,
      harness.bytes.length,
    );
    final bytes = Uint8List.fromList(harness.bytes.sublist(start, end));
    if (harness.corruptIndex == index) bytes[0] ^= 1;
    receiveText({...marker('piece-start'), 'size': bytes.length});
    for (
      var offset = 0;
      offset < bytes.length;
      offset += P8PTransferProtocol.maxFrameBytes - 16
    ) {
      if (stop.isCompleted ||
          _state == RTCDataChannelState.RTCDataChannelClosed) {
        break;
      }
      final frame = P8PTransferProtocol.encode(
        control['generation'] as int,
        id,
        offset,
        Uint8List.sublistView(
          bytes,
          offset,
          (offset + P8PTransferProtocol.maxFrameBytes - 16).clamp(
            0,
            bytes.length,
          ),
        ),
      );
      onMessage?.call(RTCDataChannelMessage.fromBinary(frame));
      await Future<void>.delayed(Duration.zero);
    }
    if (_state != RTCDataChannelState.RTCDataChannelClosed) {
      receiveText(marker(stop.isCompleted ? 'cancelled' : 'piece-end'));
    }
    _leaseCancel.remove(id);
  }

  @override
  Future<void> close() async {
    if (_state == RTCDataChannelState.RTCDataChannelClosed) return;
    for (final stop in _leaseCancel.values) {
      if (!stop.isCompleted) stop.complete();
    }
    _state = RTCDataChannelState.RTCDataChannelClosed;
    onDataChannelState?.call(_state);
    if (channelLabel == P8PTransferProtocol.channel) {
      await harness.leaseBridge?.close();
    }
    await _states.close();
  }
}

class _PythonSender {
  _PythonSender(this.process) {
    _output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final value = jsonDecode(line) as Map;
          final channel = _channel;
          if (channel == null) return;
          if (value['binary'] is String) {
            final bytes = base64Decode(value['binary'] as String);
            binaryBytes += bytes.length - 16;
            channel.onMessage?.call(RTCDataChannelMessage.fromBinary(bytes));
          } else {
            channel.receiveText(
              Map<String, Object?>.from(value['control'] as Map),
            );
          }
        });
    _errors = process.stderr
        .transform(utf8.decoder)
        .listen((value) => stderrText += value);
  }
  final Process process;
  late final StreamSubscription<String> _output, _errors;
  _FakeChannel? _channel;
  Future<void>? _closing;
  int binaryBytes = 0;
  String stderrText = '';
  void bind(_FakeChannel channel) {
    if (_channel != null && !identical(_channel, channel)) {
      throw StateError('Unexpected second IPC source');
    }
    _channel = channel;
  }

  void send(String raw) => process.stdin.writeln(raw);
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    process.stdin.writeln('{"type":"close"}');
    await process.stdin.close();
    final code = await process.exitCode.timeout(const Duration(seconds: 5));
    await _output.cancel();
    await _errors.cancel();
    expect(code, 0, reason: stderrText);
  }
}
