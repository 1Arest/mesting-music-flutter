import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/compat.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';
import 'package:ring_download_sdk/src/p8p/ordered_writer.dart';

class _ControlledStore extends AppUpgradeP2PPieceStore {
  _ControlledStore(super.file, super.manifest) : super(bufferedWrites: true);
  Completer<void>? gate;
  final entered = Completer<void>();
  bool failWrite = false;

  @override
  Future<void> append(int offset, int index, Uint8List bytes) async {
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    if (failWrite) throw const FileSystemException('injected disk failure');
    await super.append(offset, index, bytes);
  }
}

void main() {
  const chunk = AppUpgradeP2PManifest.chunkSize;
  const timeout = Duration(seconds: 10);
  late Directory directory;
  late Uint8List payload;
  late AppUpgradeP2PManifest manifest;
  late _ControlledStore store;
  late P8PLeaseBook book;
  P8POrderedWriter? writer;
  var now = 0;

  P8PLeaseBook makeBook({int generation = 1, int persisted = 0, String? sha}) =>
      P8PLeaseBook(
        contentKey: 'example/app/release',
        fileSha256: sha ?? manifest.sha256,
        generation: generation,
        fileBytes: payload.length,
        pieceBytes: chunk,
        persistedPieces: persisted,
        clockMicros: () => now,
        repeatBudgetBytes: chunk * 2,
      );
  Uint8List piece(int index) => Uint8List.sublistView(
    payload,
    index * chunk,
    index * chunk + manifest.pieceSize(index),
  );

  setUp(() async {
    now = 0;
    writer = null;
    directory = await Directory.systemTemp.createTemp('p8p-ordered-');
    payload = Uint8List.fromList(List.generate(chunk * 3 + 13, (i) => i % 251));
    manifest = AppUpgradeP2PManifest(
      fileSize: payload.length,
      sha256: sha256.convert(payload).toString(),
      pieceHashes: [
        for (var index = 0; index < 4; index++)
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
    store = _ControlledStore(File('${directory.path}/result.part'), manifest);
    book = makeBook();
  });
  tearDown(() async {
    if (store.gate != null && !store.gate!.isCompleted) store.gate!.complete();
    try {
      await writer?.close();
    } catch (_) {}
    await store.close();
    await directory.delete(recursive: true);
  });

  test('out of order sources produce one contiguous verified file', () async {
    writer = await P8POrderedWriter.open(book, store);
    final leases = [
      for (var index = 0; index < 4; index++)
        book.request(
          index,
          index.isEven ? 'https' : 'c-node',
          timeout: timeout,
        )!,
    ];
    for (final index in [3, 1, 2]) {
      expect(writer!.submit(leases[index], piece(index)), true);
    }
    await writer!.idle;
    expect(store.file.existsSync(), false);
    expect(book.persistedBytes, 0);
    expect(book.reservations, 4);
    expect(writer!.bufferedPieces, 3);
    writer!.submit(leases[0], piece(0));
    payload[0] ^= 255; // The writer owns immutable copies, not caller aliases.
    await writer!.idle;
    expect(book.complete, true);
    expect(book.reservations, 0);
    expect(await store.completeAndVerified(), true);
    expect(store.metrics['piece_verify_calls'], 4);
    expect(store.metrics['piece_write_calls'], 4);
    expect(store.metrics['full_sha_scans'], 1);
  });

  test(
    'cancel waits for an ongoing write and discards later ready pieces',
    () async {
      store.gate = Completer<void>();
      writer = await P8POrderedWriter.open(book, store);
      final leases = [
        for (var index = 0; index < 4; index++)
          book.request(index, 'c-node', timeout: timeout)!,
      ];
      for (final index in [2, 1, 0]) {
        writer!.submit(leases[index], piece(index));
      }
      await store.entered.future;
      expect(book.phase(0), P8PPiecePhase.writing);
      expect(book.reservations, 4);
      var finished = false;
      final closing = writer!.close().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      expect(writer!.submit(leases[3], piece(3)), false);
      store.gate!.complete();
      await closing;
      expect(await store.file.length(), chunk);
      expect(await store.verifyPrefix(), chunk);
      expect(book.persistedPieces, 1);
      expect(writer!.bufferedPieces, 0);
      expect(book.reservations, 1); // Network request 3 still needs a stop ack.
      book.acknowledgeStopped(leases[3]);
      expect(book.reservations, 0);
    },
  );

  test(
    'late old callbacks cannot enter a new writer for the same file',
    () async {
      writer = await P8POrderedWriter.open(book, store);
      final old = book.request(0, 'c-node', timeout: timeout)!;
      final before = writer!;
      await before.close();
      book.acknowledgeStopped(old);
      final next = makeBook(generation: 2);
      writer = await P8POrderedWriter.open(next, store);
      final lease = next.request(0, 'https', timeout: timeout)!;
      expect(lease.id, old.id);
      expect(before.submit(old, piece(0)), false);
      expect(writer!.submit(old, piece(0)), false);
      expect(store.metrics['piece_verify_calls'], null);
      expect(writer!.submit(lease, piece(0)), true);
      await writer!.idle;
      expect(next.persistedBytes, chunk);
      expect(book.persistedBytes, 0);
    },
  );

  test(
    'corrupt or partial bodies never become ready or touch the file',
    () async {
      writer = await P8POrderedWriter.open(book, store);
      final lease = book.request(0, 'c-node', timeout: timeout)!;
      final corrupt = Uint8List.fromList(piece(0))..[0] ^= 255;
      for (final bytes in [corrupt, Uint8List(1)]) {
        expect(
          () => writer!.submit(lease, bytes),
          throwsA(isA<AppUpgradeP2PFailure>()),
        );
        expect(book.phase(0), P8PPiecePhase.leased);
        expect(writer!.bufferedPieces, 0);
        expect(store.file.existsSync(), false);
      }
    },
  );

  test('mismatched content hash is rejected before opening the file', () async {
    final wrong = makeBook(sha: 'b' * 64);
    await expectLater(P8POrderedWriter.open(wrong, store), throwsArgumentError);
    expect(store.file.existsSync(), false);
  });

  test(
    'unverified or partial resume cannot silently become a full prefix',
    () async {
      await store.file.writeAsBytes(piece(0));
      await expectLater(
        P8POrderedWriter.open(book, store),
        throwsA(isA<AppUpgradeP2PFailure>()),
      );
      book = makeBook(persisted: 1);
      writer = await P8POrderedWriter.open(book, store);
      final lease = book.request(1, 'https', timeout: timeout)!;
      writer!.submit(lease, piece(1));
      await writer!.idle;
      expect(await store.file.length(), chunk * 2);
      expect(book.persistedPieces, 2);
    },
  );

  test(
    'task deadline during write clears ready payloads after that write',
    () async {
      store.gate = Completer<void>();
      writer = await P8POrderedWriter.open(book, store);
      final first = book.request(0, 'https', timeout: timeout)!;
      final next = book.request(1, 'c-node', timeout: timeout)!;
      writer!.submit(next, piece(1));
      writer!.submit(first, piece(0));
      await store.entered.future;
      now = const Duration(minutes: 5).inMicroseconds;
      store.gate!.complete();
      await writer!.idle;
      expect(book.closed, true);
      expect(book.persistedPieces, 1);
      expect(book.reservations, 0);
      expect(writer!.bufferedPieces, 0);
      expect(await store.file.length(), chunk);
      expect(await store.verifyPrefix(), chunk);
    },
  );

  test(
    'disk failure fences future arrivals and reports cleanup failure',
    () async {
      store.failWrite = true;
      writer = await P8POrderedWriter.open(book, store);
      final lease = book.request(0, 'https', timeout: timeout)!;
      writer!.submit(lease, piece(0));
      await expectLater(writer!.idle, throwsA(isA<FileSystemException>()));
      expect(book.closed, true);
      expect(book.persistedBytes, 0);
      expect(book.reservations, 0);
      expect(writer!.submit(lease, piece(0)), false);
      await expectLater(writer!.close(), throwsA(isA<FileSystemException>()));
    },
  );
}
