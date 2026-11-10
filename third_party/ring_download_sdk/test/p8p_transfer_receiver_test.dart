import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/compat.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';
import 'package:ring_download_sdk/src/p8p/diagnostics.dart';
import 'package:ring_download_sdk/src/p8p/lifecycle_trace.dart';
import 'package:ring_download_sdk/src/p8p/ordered_writer.dart';
import 'package:ring_download_sdk/src/p8p/transfer_protocol.dart';
import 'package:ring_download_sdk/src/p8p/transfer_receiver.dart';

void main() {
  const chunk = AppUpgradeP2PManifest.chunkSize;
  const timeout = Duration(seconds: 10);
  late Directory directory;
  late Uint8List payload;
  late AppUpgradeP2PManifest manifest;
  late AppUpgradeP2PPieceStore store;
  late P8PLeaseBook book;
  late P8POrderedWriter writer;
  late P8PTransferReceiver receiver;
  late List<Map<String, Object?>> sent;
  Completer<void>? closeGate;
  var now = 0;
  var failClose = false;
  var failObserver = false;
  late List<P8PSourceDiagnostic> diagnostics;
  late List<P8PLifecycleEvent> lifecycle;
  Completer<void>? enqueueGate;
  var failLifecycle = false;
  var closedTransports = 0;
  Map<String, Object?> control(
    String type,
    int id, {
    Map<String, Object?> fields = const {},
  }) => {
    'type': type,
    'version': 1,
    'generation': 7,
    'request_id': id,
    ...fields,
  };
  void marker(
    String type,
    P8PTransferTicket ticket, {
    Map<String, Object?> fields = const {},
  }) => receiver.acceptControl(
    jsonEncode(control(type, ticket.lease.id, fields: fields)),
  );
  Uint8List piece(int index) => Uint8List.sublistView(
    payload,
    index * chunk,
    index * chunk + manifest.pieceSize(index),
  );
  void deliver(P8PTransferTicket ticket, {bool corrupt = false}) {
    final lease = ticket.lease;
    marker(
      'piece-start',
      ticket,
      fields: {'index': lease.index, 'size': lease.bytes},
    );
    final data = Uint8List.fromList(piece(lease.index));
    if (corrupt) data[0] ^= 255;
    for (
      var offset = 0;
      offset < data.length;
      offset += P8PTransferProtocol.maxFrameBytes - 16
    ) {
      final end = (offset + P8PTransferProtocol.maxFrameBytes - 16).clamp(
        0,
        data.length,
      );
      receiver.acceptBinary(
        P8PTransferProtocol.encode(
          7,
          lease.id,
          offset,
          Uint8List.sublistView(data, offset, end),
        ),
      );
    }
    marker('piece-end', ticket, fields: {'index': lease.index});
  }

  Future<P8PTransferTicket> request(int index) async {
    final lease = book.request(index, 'node-a', timeout: timeout)!;
    return receiver.request(lease);
  }

  setUp(() async {
    now = 0;
    failClose = false;
    failObserver = false;
    diagnostics = [];
    lifecycle = [];
    enqueueGate = null;
    failLifecycle = false;
    closedTransports = 0;
    closeGate = null;
    sent = [];
    directory = await Directory.systemTemp.createTemp('p8p-wire-');
    payload = Uint8List.fromList(
      List.generate(chunk + 257, (index) => index % 251),
    );
    manifest = AppUpgradeP2PManifest(
      fileSize: payload.length,
      sha256: sha256.convert(payload).toString(),
      pieceHashes: [
        for (var index = 0; index < 2; index++)
          sha256
              .convert(
                Uint8List.sublistView(
                  payload,
                  index * chunk,
                  ((index + 1) * chunk).clamp(0, payload.length),
                ),
              )
              .toString(),
      ],
      stunUrls: const ['stun:example.test:3479'],
      apiBase: 'https://download1.csnas.asia/api/app/example/p2p',
      serverSeedUrl:
          'https://download1.csnas.asia/api/app/example/p2p/server-offer',
    );
    store = AppUpgradeP2PPieceStore(
      File('${directory.path}/result.part'),
      manifest,
      bufferedWrites: true,
    );
    book = P8PLeaseBook(
      contentKey: 'example/app/release',
      fileSha256: manifest.sha256,
      generation: 7,
      fileBytes: payload.length,
      pieceBytes: chunk,
      clockMicros: () => now,
      repeatBudgetBytes: 2 * chunk,
    );
    writer = await P8POrderedWriter.open(book, store);
    receiver = P8PTransferReceiver(
      source: 'node-a',
      writer: writer,
      send: (value) async {
        sent.add(value);
        if (value['type'] == 'get' && enqueueGate != null) {
          await enqueueGate!.future;
        }
        if (value['type'] == 'hello') {
          receiver.acceptControl(jsonEncode({...value, 'max_inflight': 4}));
        }
      },
      closeTransport: () async {
        closedTransports++;
        if (closeGate != null) await closeGate!.future;
        if (failClose) throw StateError('injected transport close failure');
      },
      onDiagnostic: (event) {
        diagnostics.add(event);
        if (failObserver) throw StateError('private observer failure');
      },
      onLifecycle: (event) {
        lifecycle.add(event);
        if (failLifecycle) throw StateError('injected lifecycle observer');
      },
    );
    await receiver.connect(const Duration(seconds: 1));
  });
  tearDown(() async {
    if (enqueueGate != null && !enqueueGate!.isCompleted) {
      enqueueGate!.complete();
    }
    if (closeGate != null && !closeGate!.isCompleted) closeGate!.complete();
    try {
      await receiver.close();
    } catch (_) {}
    await writer.close();
    await directory.delete(recursive: true);
  });

  test(
    'hello and native enqueue traces do not claim payload delivery',
    () async {
      expect(lifecycle.map((e) => e.code), [P8PLifecycleCode.helloReady]);
      enqueueGate = Completer<void>();
      final first = await request(0);
      expect(
        lifecycle.where((e) => e.code == P8PLifecycleCode.requestEnqueued),
        isEmpty,
      );
      expect(first.receivedBytes, 0);
      expect(book.reservations, 1);
      enqueueGate!.complete();
      await Future<void>.delayed(Duration.zero);
      final queued = lifecycle.singleWhere(
        (e) => e.code == P8PLifecycleCode.requestEnqueued,
      );
      expect(queued.metrics['owner_closed'], 0);
      expect(first.receivedBytes, 0);
      deliver(first);
      await first.verified;
      final second = await request(1);
      deliver(second);
      await second.verified;
      await writer.idle;
      expect(
        lifecycle.where((e) => e.code == P8PLifecycleCode.firstHeader),
        hasLength(1),
      );
      expect(
        lifecycle.where((e) => e.code == P8PLifecycleCode.requestEnqueued),
        hasLength(1),
      );
      expect(sent.map((v) => v['type']), ['hello', 'get', 'get']);
      expect(await store.completeAndVerified(), true);
    },
  );

  test(
    'enqueue failure is not logged as sent and retains physical ownership',
    () async {
      enqueueGate = Completer<void>();
      closeGate = Completer<void>();
      final ticket = await request(0);
      final failed = expectLater(ticket.verified, throwsStateError);
      enqueueGate!.completeError(StateError('injected enqueue failure'));
      await failed;
      expect(receiver.closed, true);
      expect(book.reservations, 1);
      expect(
        lifecycle.where((e) => e.code == P8PLifecycleCode.requestEnqueued),
        isEmpty,
      );
      closeGate!.complete();
      await ticket.stopped;
      expect(book.reservations, 0);
    },
  );

  test(
    'throwing lifecycle observer preserves requests and verified receipts',
    () async {
      failLifecycle = true;
      final first = await request(0), last = await request(1);
      deliver(last);
      deliver(first);
      await Future.wait([first.verified, last.verified]);
      await writer.idle;
      expect(await store.completeAndVerified(), true);
      expect(sent.map((v) => v['type']), ['hello', 'get', 'get']);
      expect(receiver.pending, 0);
      expect(diagnostics, isEmpty);
    },
  );

  test(
    'framed out of order pieces use the existing verified prefix writer',
    () async {
      final first = await request(0), last = await request(1);
      deliver(last);
      await last.verified;
      expect(store.file.existsSync(), false);
      deliver(first);
      await first.verified;
      await writer.idle;
      expect(await store.completeAndVerified(), true);
      expect(book.complete, true);
      expect(receiver.pending, 0);
      expect(receiver.bufferedBytes, 0);
      expect(store.metrics['piece_verify_calls'], 2);
      await receiver.close();
      expect(diagnostics, isEmpty, reason: 'Normal teardown is not a failure');
    },
  );

  test(
    'cancel frees buffers but keeps reservation until ordered ack',
    () async {
      final ticket = await request(0);
      marker('piece-start', ticket, fields: {'index': 0, 'size': chunk});
      expect(receiver.bufferedBytes, chunk);
      expect(ticket.receivedBytes, 0);
      receiver.acceptBinary(
        P8PTransferProtocol.encode(7, ticket.lease.id, 0, Uint8List(10)),
      );
      expect(ticket.receivedBytes, 10);
      expect(book.persistedBytes, 0);
      receiver.cancel(ticket);
      expect(receiver.bufferedBytes, 0);
      expect(book.reservations, 1);
      receiver.acceptBinary(
        P8PTransferProtocol.encode(7, ticket.lease.id, 0, Uint8List(10)),
      );
      marker('piece-end', ticket, fields: {'index': 0});
      expect(ticket.receivedBytes, 10, reason: 'Cancelled bytes are ignored');
      expect(book.reservations, 1);
      marker('cancelled', ticket);
      await expectLater(ticket.verified, throwsStateError);
      await ticket.stopped;
      expect(book.reservations, 0);
      expect(store.file.existsSync(), false);
      expect(diagnostics, isEmpty, reason: 'Cancel acknowledgement is trusted');
    },
  );

  test('old generation and completed request frames cannot allocate', () async {
    final ticket = await request(1);
    receiver.acceptBinary(
      P8PTransferProtocol.encode(6, ticket.lease.id, 0, Uint8List(10)),
    );
    expect(receiver.bufferedBytes, 0);
    deliver(ticket);
    await ticket.verified;
    receiver.acceptBinary(
      P8PTransferProtocol.encode(7, ticket.lease.id, 0, Uint8List(10)),
    );
    expect(receiver.closed, false);
    expect(receiver.bufferedBytes, 0);
  });

  test(
    'unowned request and malformed size cannot allocate beyond budget',
    () async {
      final ticket = await request(0);
      closeGate = Completer<void>();
      marker('piece-start', ticket, fields: {'index': 0, 'size': chunk + 1});
      expect(receiver.closed, true);
      expect(receiver.bufferedBytes, 0);
      expect(book.reservations, 1);
      closeGate!.complete();
      await receiver.close();
      await expectLater(ticket.verified, throwsFormatException);
      expect(
        ticket.receivedBytes,
        0,
        reason: 'Malformed sizes earn no progress',
      );
      await ticket.stopped;
      expect(book.reservations, 0);
    },
  );

  test(
    'wrong binary offset closes the source and never writes a piece',
    () async {
      final ticket = await request(0);
      marker('piece-start', ticket, fields: {'index': 0, 'size': chunk});
      receiver.acceptBinary(
        P8PTransferProtocol.encode(7, ticket.lease.id, 1, Uint8List(10)),
      );
      await receiver.close();
      await expectLater(ticket.verified, throwsFormatException);
      expect(
        ticket.receivedBytes,
        0,
        reason: 'Invalid offsets earn no progress',
      );
      expect(store.file.existsSync(), false);
      expect(book.reservations, 0);
    },
  );

  test('checksum failure cannot become ready or persisted', () async {
    final ticket = await request(0);
    closeGate = Completer<void>();
    failObserver = true;
    deliver(ticket, corrupt: true);
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.reason, P8PDiagnosticCode.checksumMismatch);
    expect(diagnostics.single.actualBytes, chunk);
    expect(diagnostics.single.expectedBytes, chunk);
    expect(book.reservations, 1);
    expect(receiver.bufferedBytes, 0);
    receiver.acceptBinary(Uint8List(20));
    expect(
      diagnostics,
      hasLength(1),
      reason: 'Late teardown cannot replace cause',
    );
    closeGate!.complete();
    await receiver.close();
    expect(closedTransports, 1);
    await expectLater(ticket.verified, throwsA(isA<AppUpgradeP2PFailure>()));
    expect(book.persistedBytes, 0);
    expect(writer.bufferedPieces, 0);
    expect(store.file.existsSync(), false);
  });

  test(
    'lease expiry requests cancellation before accepting more data',
    () async {
      final ticket = await request(0);
      marker('piece-start', ticket, fields: {'index': 0, 'size': chunk});
      now = timeout.inMicroseconds;
      receiver.acceptBinary(
        P8PTransferProtocol.encode(7, ticket.lease.id, 0, Uint8List(10)),
      );
      expect(receiver.bufferedBytes, 0);
      expect(sent.last['type'], 'cancel');
      expect(book.reservations, 1);
      marker('cancelled', ticket);
      await expectLater(ticket.verified, throwsStateError);
      expect(book.reservations, 0);
    },
  );

  test(
    'failed transport cleanup retains capacity instead of admitting work',
    () async {
      final ticket = await request(0);
      failClose = true;
      await expectLater(receiver.close(), throwsStateError);
      await expectLater(ticket.verified, throwsStateError);
      await expectLater(ticket.stopped, throwsStateError);
      expect(book.reservations, 1);
      expect(book.leasePhase(ticket.lease), P8PLeasePhase.cancelling);
      expect(diagnostics.single.reason, P8PDiagnosticCode.cleanupFailed);
    },
  );

  test(
    'source failure preserves another source ready piece and writer',
    () async {
      final ticket = await request(0);
      final other = book.request(1, 'https', timeout: timeout)!;
      writer.submit(other, piece(1));
      await receiver.close();
      await expectLater(ticket.verified, throwsStateError);
      expect(book.closed, false);
      expect(book.phase(1), P8PPiecePhase.ready);
      final retry = book.request(0, 'https', timeout: timeout)!;
      writer.submit(retry, piece(0));
      await writer.idle;
      expect(await store.completeAndVerified(), true);
    },
  );
}
