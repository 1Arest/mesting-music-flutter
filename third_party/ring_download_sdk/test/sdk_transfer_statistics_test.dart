import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/sdk/engine.dart';
import 'package:ring_download_sdk/src/sdk/transfer_meter.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_transfer_observation.dart';

class _ObservedEngine
    implements RingTransferEngine, RingTransferStatisticsSource {
  _ObservedEngine(this.file);
  final File file;
  Completer<void> started = Completer<void>();
  Completer<File> finish = Completer<File>();
  late void Function(int, int) progress;
  RingTransferSample sample = const RingTransferSample();
  bool throwObservation = false;
  @override
  RingTransferSample get transferSample {
    if (throwObservation) throw StateError('observer failed');
    return sample;
  }

  @override
  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) onProgress,
    CancelToken token,
  ) {
    sample = const RingTransferSample();
    progress = onProgress;
    started.complete();
    return Future.any([
      finish.future,
      token.whenCancel.then<File>((e) => throw e),
    ]);
  }

  void next() {
    started = Completer<void>();
    finish = Completer<File>();
  }

  @override
  void setForeground(bool value) {}
  @override
  void setSharingEnabled(bool value) {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('wire traffic and unique verified coverage have distinct meanings', () {
    final ledger = AppUpgradeTransferObservation();
    final one = ledger.addNode(
      AppUpgradeObservedSource.peer,
      () => true,
      () => false,
    )!;
    final two = ledger.addNode(
      AppUpgradeObservedSource.seed,
      () => true,
      () => false,
    )!;
    ledger.receive(one, one.source, 300);
    expect(
      one.verifiedBytes,
      0,
    ); // Unverified/failed bytes never count as coverage.
    ledger.persisted(0, 100, one);
    ledger.persisted(0, 100, one);
    expect(one.verifiedBytes, 100);
    ledger.receive(two, two.source, 100);
    ledger.persisted(0, 100, two);
    expect(one.verifiedBytes, 0);
    expect(two.verifiedBytes, 100);
    ledger.persisted(0, 100, null); // HTTPS replacement.
    expect(two.verifiedBytes, 0);
    ledger.persisted(1, 100, one);
    ledger.clearCoverage();
    expect(one.verifiedBytes, 0);
    expect(ledger.peerReceivedBytes, 300);
    expect(ledger.seedReceivedBytes, 100);
  });
  test('connection history is bounded and signals incomplete counters', () {
    final ledger = AppUpgradeTransferObservation();
    for (var i = 0; i < 33; i++) {
      ledger.addNode(AppUpgradeObservedSource.peer, () => false, () => true);
    }
    expect(ledger.nodes.length, 32);
    expect(ledger.complete, false);
  });
  test(
    'connected is not receiving; rolling rates decay when traffic stalls',
    () {
      final meter = RingTransferMeter();
      RingTransferStatistics read(int ms, int wire) => meter.read(
        Duration(milliseconds: ms),
        const RingDownloadProgress(RingDownloadState.transferring, 10, 1000),
        RingTransferSample(
          peerBytes: wire,
          nodes: [
            RingNodeSample(
              'node1',
              RingNodeSource.peer,
              RingNodeState.connected,
              wire,
              0,
            ),
          ],
        ),
      );
      final connected = read(0, 0);
      expect(connected.connectedNodes, 1);
      expect(connected.receivingNodes, 0);
      final receiving = read(500, 100);
      expect(receiving.peerBytesPerSecond, 200);
      expect(receiving.receivingNodes, 1);
      expect(receiving.peerVerifiedBytes, 0);
      read(1000, 100);
      read(1500, 100);
      read(2000, 100);
      final stalled = read(2500, 100);
      expect(stalled.peerBytesPerSecond, 0);
      expect(stalled.receivingNodes, 0);
      expect(stalled.connectedNodes, 1);
    },
  );
  test('resumed bytes are not network rate; unknown totals have no ETA', () {
    final meter = RingTransferMeter();
    var value = meter.read(
      const Duration(milliseconds: 500),
      const RingDownloadProgress(RingDownloadState.transferring, 500, 1000),
      const RingTransferSample(),
    );
    expect(value.bytesPerSecond, 0);
    expect(value.estimatedRemaining, null);
    value = meter.read(
      const Duration(seconds: 1),
      const RingDownloadProgress(RingDownloadState.transferring, 600, 0),
      const RingTransferSample(httpsBytes: 100),
    );
    expect(value.httpsBytesPerSecond, 100);
    expect(value.estimatedRemaining, null);
  });
  for (final state in [
    RingDownloadState.verifying,
    RingDownloadState.completed,
    RingDownloadState.cancelled,
    RingDownloadState.failed,
  ]) {
    test('${state.name} has no active download rate or ETA', () {
      final value = RingTransferMeter().read(
        const Duration(seconds: 1),
        RingDownloadProgress(state, 500, 1000),
        const RingTransferSample(
          peerBytes: 100,
          nodes: [
            RingNodeSample(
              'node1',
              RingNodeSource.peer,
              RingNodeState.connected,
              100,
              90,
            ),
          ],
        ),
      );
      expect(value.bytesPerSecond, 0);
      expect(value.estimatedRemaining, null);
      expect(value.connectedNodes, 0);
      expect(value.peerVerifiedBytes, 90);
    });
  }
  test('snapshot is immutable and drops unsafe node aliases', () {
    final nodes = [
      const RingNodeSample(
        'node1',
        RingNodeSource.peer,
        RingNodeState.connecting,
        0,
        0,
      ),
      const RingNodeSample(
        'https://private.invalid/?token=PRIVATE',
        RingNodeSource.peer,
        RingNodeState.connected,
        0,
        0,
      ),
    ];
    final value = RingTransferMeter().read(
      Duration.zero,
      const RingDownloadProgress(RingDownloadState.transferring, 0, 0),
      RingTransferSample(nodes: nodes),
    );
    nodes.clear();
    expect(value.nodes.length, 1);
    expect(value.available, false);
    expect(() => value.nodes.clear(), throwsUnsupportedError);
    expect(jsonEncode(value.toJson()), isNot(contains('PRIVATE')));
  });
  for (final cancelled in [false, true]) {
    test(
      'task-local stream closes and cannot leak into the next task cancelled=$cancelled',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ring-statistics-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = await File(
          '${directory.path}/a.apk',
        ).writeAsBytes(List.filled(4096, 7));
        final engine = _ObservedEngine(file);
        final sdk = RingDownloadSdk.withEngine(
          const RingDownloadConfig(
            appId: 'statistics-test',
            observeLifecycle: false,
          ),
          engine,
        );
        addTearDown(sdk.dispose);
        final request = RingDownloadRequest(
          url: Uri.parse('https://cdn.example.test/a.apk'),
          fileSize: 4096,
          sha256: sha256.convert(await file.readAsBytes()).toString(),
        );
        final first = sdk.download(request);
        expect(first.latestStatistics.state, RingDownloadState.queued);
        final events = <RingTransferStatistics>[];
        final closed = Completer<void>();
        first.statistics.listen(events.add, onDone: closed.complete);
        await engine.started.future;
        engine.sample = const RingTransferSample(
          httpsBytes: 100,
          peerBytes: 200,
          nodes: [
            RingNodeSample(
              'node1',
              RingNodeSource.peer,
              RingNodeState.connected,
              200,
              150,
            ),
          ],
        );
        for (var i = 1; i < 1000; i++) {
          engine.progress(i, 4096);
        }
        if (cancelled) {
          first.cancel();
          expect(first.latestStatistics.cancelling, true);
          await expectLater(
            first.completed,
            throwsA(isA<RingDownloadException>()),
          );
        } else {
          engine.finish.complete(file);
          await first.completed;
        }
        await closed.future;
        expect(events.length, lessThan(10)); // No per-chunk UI flood.
        final snapshot = first.latestStatistics;
        expect(
          snapshot.state,
          cancelled ? RingDownloadState.cancelled : RingDownloadState.completed,
        );
        expect(snapshot.peerVerifiedBytes, 150);
        expect(snapshot.peerReceivedBytes, 200);
        final lateProgress = engine.progress;
        engine.next();
        final next = sdk.download(request);
        await engine.started.future;
        lateProgress(4096, 4096);
        expect(next.latestStatistics.peerReceivedBytes, 0);
        expect(identical(first.latestStatistics, snapshot), true);
        engine.finish.complete(file);
        await next.completed;
        expect(first.latestStatistics.toJson(), snapshot.toJson());
      },
    );
  }
  test('observation failure never changes a valid download result', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ring-observation-failure-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/a.apk').writeAsBytes([1, 2, 3]);
    final engine = _ObservedEngine(file)..throwObservation = true;
    final sdk = RingDownloadSdk.withEngine(
      const RingDownloadConfig(
        appId: 'observer-failure',
        observeLifecycle: false,
      ),
      engine,
    );
    addTearDown(sdk.dispose);
    final task = sdk.download(
      RingDownloadRequest(url: Uri.parse('https://cdn.example.test/a.apk')),
    );
    await engine.started.future;
    engine.finish.complete(file);
    expect((await task.completed).fileSize, 3);
    expect(task.latestStatistics.available, false);
  });
}
