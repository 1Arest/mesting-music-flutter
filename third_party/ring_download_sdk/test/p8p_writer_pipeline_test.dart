import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/compat.dart';
import 'package:ring_download_sdk/src/p8p/coordinator.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';
import 'package:ring_download_sdk/src/p8p/ordered_writer.dart';
import 'package:ring_download_sdk/src/p8p/sources.dart';

void main() {
  const chunk = AppUpgradeP2PManifest.chunkSize;
  late Directory directory;
  late Uint8List payload;
  late AppUpgradeP2PManifest manifest;
  late AppUpgradeP2PPieceStore store;
  late P8PLeaseBook book;
  late P8POrderedWriter writer;
  late P8PCoordinator coordinator;
  late Completer<void> entered, diskRelease, physicalRelease;
  Future<bool>? running;
  var now = 0, failWrite = false;

  Uint8List piece(int index) => Uint8List.sublistView(
    payload,
    index * chunk,
    ((index + 1) * chunk).clamp(0, payload.length),
  );
  Future<void> until(bool Function() predicate) async {
    final watch = Stopwatch()..start();
    while (!predicate() && watch.elapsed < const Duration(seconds: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      predicate(),
      true,
      reason:
          'Network scheduling and cancellation must continue while '
          'the verified prefix is still physically writing',
    );
  }

  Future<bool> start() {
    final result = coordinator.run(active: () => true);
    // Preserve the original failure for assertions and cleanup, without an
    // unhandled asynchronous error while a test is observing another owner.
    unawaited(result.then<void>((_) {}, onError: (Object _) {}));
    return running = result;
  }

  setUp(() async {
    now = 0;
    failWrite = false;
    running = null;
    entered = Completer<void>();
    diskRelease = Completer<void>();
    physicalRelease = Completer<void>();
    directory = await Directory.systemTemp.createTemp('p8p-writer-pipeline-');
    payload = Uint8List.fromList(List.generate(6 * chunk + 31, (i) => i % 251));
    manifest = AppUpgradeP2PManifest(
      fileSize: payload.length,
      sha256: sha256.convert(payload).toString(),
      pieceHashes: [
        for (var index = 0; index < 7; index++)
          sha256.convert(piece(index)).toString(),
      ],
      stunUrls: const ['stun:example.test:3479'],
      apiBase: 'https://example.test/p2p',
      serverSeedUrl: 'https://example.test/p2p/server-offer',
    );
    store = AppUpgradeP2PPieceStore(
      File('${directory.path}/output'),
      manifest,
      bufferedWrites: true,
    );
    book = P8PLeaseBook(
      contentKey: 'fixture/writer-pipeline',
      fileSha256: manifest.sha256,
      generation: 1,
      fileBytes: payload.length,
      pieceBytes: chunk,
      clockMicros: () => now,
    );
    writer = await P8POrderedWriter.open(
      book,
      store,
      paused: true,
      beforeWrite: (lease) async {
        if (lease.index == 0) {
          entered.complete();
          await diskRelease.future;
          if (failWrite) {
            throw const FileSystemException('injected write failure');
          }
        }
      },
    );
    coordinator = P8PCoordinator(
      writer,
      clockMicros: () => now,
      requestTimeout: const Duration(seconds: 2),
    );
  });

  tearDown(() async {
    if (!diskRelease.isCompleted) diskRelease.complete();
    if (!physicalRelease.isCompleted) physicalRelease.complete();
    for (final closing in [
      coordinator.close(),
      if (running != null) running!,
    ]) {
      try {
        await closing;
      } on FileSystemException {
        if (!failWrite) rethrow;
      }
    }
    await store.close();
    await directory.delete(recursive: true);
  });

  List<int> addImmediateSource() {
    final requests = <int>[];
    coordinator.add(
      P8PHttpPieceSource(writer, (index, token) async {
        requests.add(index);
        return piece(index);
      }, id: 'node'),
    );
    return requests;
  }

  test('writing prefix permits bounded network prefetch', () async {
    final requests = addImmediateSource();
    final download = start();
    await entered.future;
    await until(() => book.reservations == 4);
    expect(requests, [0, 1, 2, 3]);
    expect(book.persistedBytes, 0);
    expect(book.phase(0), P8PPiecePhase.writing);
    expect(book.phase(3), P8PPiecePhase.ready);
    expect(book.reservedBytes, 4 * chunk);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(requests, [
      0,
      1,
      2,
      3,
    ], reason: 'Writing and ready pieces own slots');
    diskRelease.complete();
    expect(await download, true);
    expect(await store.completeAndVerified(), true);
    expect(book.peakReservations, 4);
    expect(book.peakReservedBytes, 4 * chunk);
    expect(book.repeatReservedBytes, 0);
    expect(book.reservations, 0);
  });

  test(
    'blocked write does not postpone network expiry or physical stop',
    () async {
      final cancelled = Completer<void>();
      coordinator.add(
        _PrefixOnlySource(writer, (index, token) async => piece(index)),
      );
      coordinator.add(
        P8PHttpPieceSource(writer, (index, token) async {
          await token.whenCancel;
          cancelled.complete();
          await physicalRelease.future;
          throw token.cancelError!;
        }, id: 'stalled'),
      );
      final stalled = coordinator.probe(1, 'stalled')!;
      final proof = coordinator.probe(0, 'prefix')!;
      await proof.verified;
      await proof.stopped;
      final download = start();
      await entered.future;
      now = 2000000;
      await until(() => cancelled.isCompleted);
      expect(book.leasePhase(stalled.lease), P8PLeasePhase.cancelling);
      expect(book.reservations, 2);
      expect(book.persistedBytes, 0);
      var closed = false;
      final closing = coordinator.close().then((_) => closed = true);
      physicalRelease.complete();
      await stalled.stopped;
      await Future<void>.delayed(Duration.zero);
      expect(book.reservations, 1);
      expect(closed, false, reason: 'The disk writer still owns the file');
      diskRelease.complete();
      await closing;
      expect(await download, false);
      expect(await store.verifyPrefix(), chunk);
      expect(book.reservations, 0);
      expect(book.repeatReservedBytes, 0);
    },
  );

  test(
    'cancel discards prefetched buffers and awaits the physical writer',
    () async {
      final requests = addImmediateSource();
      final download = start();
      await entered.future;
      await until(() => book.reservations == 4);
      var closed = false;
      final closing = coordinator.close().then((_) => closed = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(closed, false);
      expect(book.reservations, 1);
      expect(store.file.existsSync(), false);
      diskRelease.complete();
      await closing;
      expect(await download, false);
      expect(await store.verifyPrefix(), chunk);
      expect(requests, [0, 1, 2, 3]);
      expect(book.reservations, 0);
      expect(writer.bufferedPieces, 0);
    },
  );

  test('write failure remains observable after bounded prefetch', () async {
    failWrite = true;
    final requests = addImmediateSource();
    final download = start();
    await entered.future;
    await until(() => book.reservations == 4);
    diskRelease.complete();
    await expectLater(download, throwsA(isA<FileSystemException>()));
    expect(requests, [0, 1, 2, 3]);
    expect(book.closed, true);
    expect(book.persistedBytes, 0);
    expect(book.reservations, 0);
    expect(writer.bufferedPieces, 0);
    expect(store.file.existsSync(), false);
  });
}

class _PrefixOnlySource extends P8PHttpPieceSource {
  _PrefixOnlySource(super.writer, super.read) : super(id: 'prefix');
  @override
  bool canServe(int index) => index == 0 && super.canServe(index);
}
