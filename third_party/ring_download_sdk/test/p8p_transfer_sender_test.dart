import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/compat.dart';
import 'package:ring_download_sdk/src/p8p/coordinator.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';
import 'package:ring_download_sdk/src/p8p/ordered_writer.dart';
import 'package:ring_download_sdk/src/p8p/sources.dart';
import 'package:ring_download_sdk/src/p8p/transfer_protocol.dart';
import 'package:ring_download_sdk/src/p8p/transfer_receiver.dart';
import 'package:ring_download_sdk/src/p8p/transfer_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late P8PTransferSender sender;
  late List<Map<String, Object?>> controls;
  late List<Uint8List> frames;
  late List<int> reads;
  late Uint8List payload;
  var failures = 0, queued = 0;
  Future<Uint8List> Function(int)? read;
  Future<void> Function(Uint8List, bool Function())? send;
  Map<String, Object?> control(String type, {int? id, int? index}) => {
    'type': type,
    'version': 1,
    'generation': 7,
    if (type == 'hello') 'sha256': sha256.convert(payload).toString(),
    'request_id': ?id,
    'index': ?index,
  };
  void issue(String type, {int? id, int? index}) =>
      sender.acceptControl(jsonEncode(control(type, id: id, index: index)));
  Future<void> until(bool Function() test) async {
    for (var i = 0; i < 500; i++) {
      if (test()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail('sender condition did not settle');
  }

  setUp(() {
    payload = Uint8List.fromList(List.generate(1048576 + 257, (i) => i % 251));
    failures = 0;
    queued = 0;
    controls = [];
    frames = [];
    reads = [];
    read = null;
    send = null;
    sender = P8PTransferSender(
      sha256: sha256.convert(payload).toString(),
      fileBytes: payload.length,
      readPiece: (index) async {
        reads.add(index);
        if (read != null) return read!(index);
        return Uint8List.fromList(
          payload.sublist(
            index * 1048576,
            ((index + 1) * 1048576).clamp(0, payload.length),
          ),
        );
      },
      sendControl: (value) async {
        controls.add(value);
      },
      sendBinary: (value, active) async {
        if (send != null) return send!(value, active);
        if (!active()) throw StateError('cancelled');
        frames.add(value);
      },
      allowed: () => true,
      onFailure: () {
        failures++;
      },
      onPayloadQueued: (n) {
        queued += n;
      },
    );
  });
  tearDown(() async {
    await sender.close();
  });

  for (final supported in [false, true]) {
    test(
      'paced phone requires capacity support before body: $supported',
      () async {
        await sender.close();
        sender = P8PTransferSender(
          sha256: sha256.convert(payload).toString(),
          fileBytes: payload.length,
          requireCapacitySupport: true,
          readPiece: (index) async {
            reads.add(index);
            return Uint8List.fromList(payload.sublist(0, 1048576));
          },
          sendControl: (value) async {
            controls.add(value);
          },
          sendBinary: (value, active) async {
            frames.add(value);
          },
          allowed: () => true,
          onFailure: () {
            failures++;
          },
        );
        sender.acceptControl(
          jsonEncode({
            ...control('hello'),
            if (supported) 'source_capacity_supported': true,
          }),
        );
        issue('get', id: 1, index: 0);
        await until(
          () => supported
              ? controls.any((v) => v['type'] == 'piece-end')
              : sender.closed,
        );
        if (supported) {
          expect(reads, [0]);
          expect(frames, isNotEmpty);
          expect(failures, 0);
        } else {
          expect(reads, isEmpty);
          expect(frames, isEmpty);
          expect(controls.single['code'], 'source_capacity_required');
          expect(failures, 1);
        }
      },
    );
  }

  test(
    'two queued leases preserve identities offsets and the full SHA',
    () async {
      issue('hello');
      issue('get', id: 1, index: 0);
      issue('get', id: 2, index: 1);
      await until(
        () => controls.where((c) => c['type'] == 'piece-end').length == 2,
      );
      final all = BytesBuilder();
      for (final id in [1, 2]) {
        var offset = 0;
        for (final raw in frames) {
          final frame = P8PTransferProtocol.frame(raw);
          if (frame.identity != id) continue;
          expect(frame.generation, 7);
          expect(frame.offset, offset);
          offset += frame.body.length;
          all.add(frame.body);
        }
      }
      expect(
        sha256.convert(all.takeBytes()).toString(),
        sha256.convert(payload).toString(),
      );
      expect(queued, payload.length);
      expect(sender.pending, 0);
      expect(failures, 0);
      expect(controls.first['max_inflight'], 4);
      expect(controls.first['source_capacity'], 1);
    },
  );

  test(
    'close waits for a physical read and never queues its late payload',
    () async {
      final entered = Completer<void>(), gate = Completer<Uint8List>();
      read = (_) {
        entered.complete();
        return gate.future;
      };
      issue('hello');
      issue('get', id: 1, index: 0);
      await entered.future;
      var closed = false;
      final closing = sender.close().then((_) {
        closed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(closed, false);
      gate.complete(Uint8List(1048576));
      await closing;
      expect(frames, isEmpty);
      expect(sender.pending, 0);
      expect(queued, 0);
    },
  );

  test(
    'active cancel is acknowledged only after the read owner ends',
    () async {
      final entered = Completer<void>(), gate = Completer<Uint8List>();
      read = (_) {
        entered.complete();
        return gate.future;
      };
      issue('hello');
      issue('get', id: 1, index: 0);
      await entered.future;
      issue('cancel', id: 1);
      await Future<void>.delayed(Duration.zero);
      expect(controls.where((c) => c['type'] == 'cancelled'), isEmpty);
      gate.complete(Uint8List(1048576));
      await until(() => controls.any((c) => c['type'] == 'cancelled'));
      expect(frames, isEmpty);
      expect(queued, 0);
      expect(failures, 0);
    },
  );

  test(
    'cancel during a pacing send admits no late body before acknowledgement',
    () async {
      final entered = Completer<void>(), gate = Completer<void>();
      send = (frame, active) async {
        entered.complete();
        await gate.future;
        if (!active()) throw StateError('cancelled');
        frames.add(frame);
      };
      issue('hello');
      issue('get', id: 1, index: 0);
      await entered.future;
      issue('cancel', id: 1);
      gate.complete();
      await until(() => controls.any((c) => c['type'] == 'cancelled'));
      expect(frames, isEmpty);
      expect(queued, 0);
      expect(failures, 0);
    },
  );

  test('queued cancellation has no file read and no payload owner', () async {
    final entered = Completer<void>(), gate = Completer<Uint8List>();
    read = (_) {
      entered.complete();
      return gate.future;
    };
    issue('hello');
    issue('get', id: 1, index: 0);
    await entered.future;
    issue('get', id: 2, index: 1);
    issue('cancel', id: 2);
    await until(
      () =>
          controls.any((c) => c['type'] == 'cancelled' && c['request_id'] == 2),
    );
    expect(reads, [0]);
    final closing = sender.close();
    gate.complete(Uint8List(1048576));
    await closing;
    expect(frames, isEmpty);
  });

  test(
    'request identity reuse stops the source while joining its read',
    () async {
      final entered = Completer<void>(), gate = Completer<Uint8List>();
      read = (_) {
        entered.complete();
        return gate.future;
      };
      issue('hello');
      issue('get', id: 1, index: 0);
      await entered.future;
      issue('get', id: 1, index: 1);
      expect(sender.closed, true);
      expect(failures, 1);
      gate.complete(Uint8List(1048576));
      await sender.close();
      expect(frames, isEmpty);
      expect(sender.pending, 0);
    },
  );

  test(
    'sender integrates with actual SDK leases writer and full file verification',
    () async {
      await sender.close();
      final directory = await Directory.systemTemp.createTemp(
        'p8p-sender-e2e-',
      );
      final manifest = AppUpgradeP2PManifest(
        fileSize: payload.length,
        sha256: sha256.convert(payload).toString(),
        pieceHashes: [
          for (final start in [0, 1048576])
            sha256
                .convert(
                  payload.sublist(
                    start,
                    (start + 1048576).clamp(0, payload.length),
                  ),
                )
                .toString(),
        ],
        stunUrls: const [],
        apiBase: 'https://example.test/p2p',
        serverSeedUrl: 'https://example.test/seed',
      );
      final store = AppUpgradeP2PPieceStore(
        File('${directory.path}/received.apk'),
        manifest,
        bufferedWrites: true,
      );
      final clock = Stopwatch()..start();
      final book = P8PLeaseBook(
        contentKey: 'sender-fixture',
        fileSha256: manifest.sha256,
        generation: 7,
        fileBytes: payload.length,
        pieceBytes: 1048576,
        clockMicros: () => clock.elapsedMicroseconds,
      );
      final writer = await P8POrderedWriter.open(book, store);
      late P8PTransferReceiver receiver;
      sender = P8PTransferSender(
        sha256: manifest.sha256,
        fileBytes: payload.length,
        readPiece: (index) async => Uint8List.fromList(
          payload.sublist(
            index * 1048576,
            ((index + 1) * 1048576).clamp(0, payload.length),
          ),
        ),
        requireCapacitySupport: true,
        sendControl: (value) async {
          receiver.acceptControl(jsonEncode(value));
        },
        sendBinary: (value, active) async {
          if (!active()) throw StateError('cancelled');
          receiver.acceptBinary(value);
        },
        allowed: () => true,
        onFailure: () {
          failures++;
        },
      );
      receiver = P8PTransferReceiver(
        source: 'phone',
        writer: writer,
        send: (value) async {
          sender.acceptControl(jsonEncode(value));
        },
        closeTransport: sender.close,
      );
      final coordinator = P8PCoordinator(
        writer,
        clockMicros: () => clock.elapsedMicroseconds,
      );
      try {
        await receiver.connect(const Duration(seconds: 2));
        final source = P8PRtcPieceSource(receiver);
        expect(source.capacity, 1);
        coordinator.add(source, diagnosticAlias: 'peer1');
        expect(await coordinator.run(active: () => true), true);
        expect(await store.completeAndVerified(), true);
        expect(failures, 0);
      } finally {
        await coordinator.close();
        await receiver.close();
        await sender.close();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
