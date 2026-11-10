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
import 'package:ring_download_sdk/src/p8p/sources.dart';
import 'package:ring_download_sdk/src/p8p/coordinator.dart';
import 'package:ring_download_sdk/src/p8p/transfer_protocol.dart';
import 'package:ring_download_sdk/src/p8p/transfer_receiver.dart';

void main() {
  const chunk = AppUpgradeP2PManifest.chunkSize;
  late Directory directory;
  late Uint8List payload;
  late AppUpgradeP2PManifest manifest;
  late AppUpgradeP2PPieceStore store;
  late P8PLeaseBook book;
  late P8POrderedWriter writer;
  late P8PCoordinator coordinator;
  late Stopwatch clock;
  late List<P8PSourceDiagnostic> diagnostics;
  late List<P8PLifecycleEvent> lifecycle;
  Uint8List piece(int index) => Uint8List.fromList(
    payload.sublist(index * chunk, (index * chunk + manifest.pieceSize(index))),
  );
  Future<void> setup(
    int pieces, {
    int repeat = 2 * chunk,
    Duration requestTimeout = const Duration(seconds: 1),
    Duration hedgeAfter = const Duration(milliseconds: 40),
    bool paused = false,
    int Function()? readClock,
    Duration stopGrace = const Duration(milliseconds: 30),
    bool traceLifecycle = false,
    bool failLifecycle = false,
    bool failObserver = false,
  }) async {
    directory = await Directory.systemTemp.createTemp('p8p-coordinator-');
    payload = Uint8List.fromList(
      List.generate(chunk * (pieces - 1) + 31, (i) => i % 251),
    );
    manifest = AppUpgradeP2PManifest(
      fileSize: payload.length,
      sha256: sha256.convert(payload).toString(),
      pieceHashes: [
        for (var i = 0; i < pieces; i++)
          sha256
              .convert(
                Uint8List.sublistView(
                  payload,
                  i * chunk,
                  ((i + 1) * chunk).clamp(0, payload.length),
                ),
              )
              .toString(),
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
    clock = Stopwatch()..start();
    book = P8PLeaseBook(
      contentKey: 'fixture/release',
      fileSha256: manifest.sha256,
      generation: 1,
      fileBytes: payload.length,
      pieceBytes: chunk,
      clockMicros: readClock ?? () => clock.elapsedMicroseconds,
      repeatBudgetBytes: repeat,
    );
    writer = await P8POrderedWriter.open(book, store, paused: paused);
    diagnostics = [];
    lifecycle = [];
    coordinator = P8PCoordinator(
      writer,
      clockMicros: readClock ?? () => clock.elapsedMicroseconds,
      requestTimeout: requestTimeout,
      hedgeAfter: hedgeAfter,
      stopGrace: stopGrace,
      onLifecycle: traceLifecycle
          ? (event) {
              lifecycle.add(event);
              if (failLifecycle) {
                throw StateError('injected lifecycle logger error');
              }
            }
          : null,
      onDiagnostic: (event) {
        diagnostics.add(event);
        if (failObserver) throw StateError('private diagnostic observer');
      },
    );
  }

  tearDown(() async {
    await coordinator.close();
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'source diagnostic counters keep fixed aliases and exclude raw IDs',
    () async {
      var now = 0;
      await setup(4, paused: true, readClock: () => now);
      final pending = <int, Completer<Uint8List>>{};
      final ids = ['private-device-a', 'private-device-b', 'server', 'https'];
      final aliases = ['peer1', 'peer2', 'seed', 'https'];
      for (var index = 0; index < 4; index++) {
        final gate = Completer<Uint8List>();
        pending[index] = gate;
        expect(
          coordinator.add(
            P8PHttpPieceSource(
              writer,
              (_, token) => gate.future,
              id: ids[index],
            ),
            diagnosticAlias: aliases[index],
          ),
          true,
        );
      }
      final requests = [
        for (var index = 0; index < 4; index++)
          coordinator.probe(index, ids[index])!,
      ];
      for (var index = 0; index < 4; index++) {
        now = (index + 1) * 100000;
        pending[index]!.complete(piece(index));
        await requests[index].verified;
        await requests[index].stopped;
      }
      final before = coordinator.metrics;
      expect(before['verified_bytes'], payload.length);
      for (var index = 0; index < 4; index++) {
        final prefix = 'source_${aliases[index]}_';
        expect(before['${prefix}requests'], 1);
        expect(before['${prefix}verified_bytes'], manifest.pieceSize(index));
        expect(before['${prefix}busy_us'], (index + 1) * 100000);
        expect(before['${prefix}cancelled'], 0);
        expect(before['${prefix}failures'], 0);
      }
      expect(before.keys.any((key) => ids.take(2).any(key.contains)), false);
      expect(
        book.reservations,
        4,
        reason: 'Telemetry cannot release ready ownership',
      );
      await coordinator.close();
      expect(
        coordinator.metrics,
        before,
        reason: 'Snapshotting and cleanup add no phantom work',
      );
      expect(book.reservations, 0);
    },
  );

  test(
    'invalid and duplicate diagnostic aliases do not change source admission',
    () async {
      await setup(4, paused: true);
      expect(
        coordinator.add(
          P8PHttpPieceSource(writer, (index, _) async => piece(index), id: 'a'),
          diagnosticAlias: 'peer1',
        ),
        true,
      );
      expect(
        coordinator.add(
          P8PHttpPieceSource(writer, (index, _) async => piece(index), id: 'b'),
          diagnosticAlias: 'peer1',
        ),
        true,
      );
      expect(
        coordinator.add(
          P8PHttpPieceSource(writer, (index, _) async => piece(index), id: 'c'),
          diagnosticAlias: 'private_token',
        ),
        true,
      );
      final request = coordinator.probe(0, 'b')!;
      await request.verified;
      await request.stopped;
      expect(coordinator.metrics['source_peer1_requests'], 0);
      expect(
        coordinator.metrics.keys.any((key) => key.contains('private_token')),
        false,
      );
      expect(coordinator.metrics['requests'], 1);
    },
  );

  test('failed source diagnostics cannot credit verified bytes', () async {
    var now = 0;
    await setup(3, paused: true, readClock: () => now);
    final gate = Completer<Uint8List>();
    coordinator.add(
      P8PHttpPieceSource(writer, (_, token) => gate.future, id: 'opaque-id'),
      diagnosticAlias: 'peer1',
    );
    final request = coordinator.probe(0, 'opaque-id')!;
    now = 100000;
    gate.completeError(const FormatException('fixture bad piece'));
    await expectLater(request.verified, throwsFormatException);
    await request.stopped;
    await coordinator.close();
    expect(coordinator.metrics['source_peer1_requests'], 1);
    expect(coordinator.metrics['source_peer1_failures'], 1);
    expect(coordinator.metrics['source_peer1_verified_bytes'], 0);
    expect(coordinator.metrics['source_peer1_busy_us'], 100000);
    expect(book.persistedBytes, 0);
    expect(book.reservations, 0);
  });

  test(
    'admission wait releases the prefix and HTTP rejoins after Retry-After',
    () async {
      var now = 0, httpCalls = 0;
      await setup(
        6,
        paused: true,
        readClock: () => now,
        requestTimeout: const Duration(seconds: 10),
        hedgeAfter: const Duration(seconds: 1),
      );
      final http = P8PHttpPieceSource(writer, (index, token) async {
        if (httpCalls++ == 0) {
          throw P8PSourceDeferred(const Duration(seconds: 2));
        }
        return piece(index);
      });
      coordinator.add(http);
      final admission = coordinator.probe(0, 'https')!;
      await expectLater(admission.verified, throwsA(isA<P8PSourceDeferred>()));
      await admission.stopped;
      expect(book.reservations, 0);
      expect(http.closed, false);
      coordinator.add(
        _PrefixSource(writer, (index, token) async => piece(index)),
      );
      final download = coordinator.run(active: () => true);
      try {
        final limit = Stopwatch()..start();
        while (book.persistedPieces < 2 &&
            limit.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(
          book.persistedPieces,
          2,
          reason: 'Ready provider can fill the prefix while HTTP waits',
        );
        expect(httpCalls, 1);
        now = 1999999;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(
          httpCalls,
          1,
          reason: 'No HTTP request before the complete Retry-After',
        );
        now = 2000000;
        expect(await download.timeout(const Duration(seconds: 2)), true);
        expect(await store.completeAndVerified(), true);
        expect(coordinator.metrics['source_deferred'], 1);
        expect(coordinator.metrics['source_failures'] ?? 0, 0);
        expect(book.peakReservations, lessThanOrEqualTo(4));
        expect(
          book.repeatReservedBytes,
          0,
          reason: 'Rejected HTTP admission sent no piece body to repeat',
        );
        expect(book.reservations, 0);
      } finally {
        await coordinator.close();
        await download;
      }
    },
  );

  test('a faster late user peer wins work from an already warm seed', () async {
    var now = 0;
    await setup(
      10,
      paused: true,
      readClock: () => now,
      requestTimeout: const Duration(seconds: 5),
      hedgeAfter: const Duration(seconds: 1),
    );
    final pending = <int, Completer<Uint8List>>{};
    final starts = <int, Completer<String>>{};
    P8PRangeReader reader(String id) => (index, token) async {
      final gate = Completer<Uint8List>();
      pending[index] = gate;
      starts.putIfAbsent(index, () => Completer<String>()).complete(id);
      try {
        return await Future.any([
          gate.future,
          token.whenCancel.then<Uint8List>((error) => throw error),
        ]);
      } finally {
        pending.remove(index);
      }
    };
    Future<String> started(int index) => starts
        .putIfAbsent(index, () => Completer<String>())
        .future
        .timeout(const Duration(seconds: 2));
    void finish(int index) => pending[index]!.complete(piece(index));
    coordinator.add(
      P8PHttpPieceSource(writer, reader('server'), id: 'server'),
      diagnosticAlias: 'seed',
    );
    final seedProbe = coordinator.probe(0, 'server')!;
    now = 300000;
    finish(0);
    await seedProbe.verified;
    await seedProbe.stopped;
    final download = coordinator.run(active: () => true);
    try {
      expect(await started(1), 'server');
      expect(await started(2), 'server');
      coordinator.add(
        P8PHttpPieceSource(writer, reader('B-home'), id: 'B-home'),
        diagnosticAlias: 'peer1',
      );
      expect(
        await started(3),
        'B-home',
        reason: 'The late user peer gets a real cold probe',
      );
      now = 400000;
      finish(3);
      expect(
        await started(4),
        'B-home',
        reason: 'A verified 100ms peer outranks the 300ms seed',
      );
      now = 600000;
      finish(1);
      expect(
        await started(5),
        'B-home',
        reason: 'The server keeps serving while faster peer gets next work',
      );
      expect(coordinator.metrics['source_peer1_verified_bytes'], chunk);
      expect(coordinator.metrics['source_seed_verified_bytes'], 2 * chunk);
      expect(coordinator.metrics['source_failures'] ?? 0, 0);
      expect(book.peakReservations, lessThanOrEqualTo(4));
      expect(book.repeatReservedBytes, 0);
    } finally {
      await coordinator.close();
      await download;
    }
  });

  test('a late cold source probes ahead of a proven writable prefix', () async {
    var now = 0;
    await setup(9, paused: true, readClock: () => now);
    final pending = <int, Completer<Uint8List>>{};
    final starts = <int, Completer<String>>{};
    P8PRangeReader reader(String id) => (index, token) async {
      final gate = pending[index] = Completer<Uint8List>();
      starts.putIfAbsent(index, () => Completer<String>()).complete(id);
      return Future.any([
        gate.future,
        token.whenCancel.then<Uint8List>((error) => throw error),
      ]);
    };
    Future<String> started(int index) => starts
        .putIfAbsent(index, () => Completer<String>())
        .future
        .timeout(const Duration(seconds: 2));
    coordinator.add(
      P8PHttpPieceSource(writer, reader('seed'), id: 'seed'),
      diagnosticAlias: 'seed',
    );
    final proof = coordinator.probe(0, 'seed')!;
    now = 300000;
    pending[0]!.complete(piece(0));
    await proof.verified;
    await proof.stopped;
    writer.resume();
    await writer.idle;
    expect(book.persistedPieces, 1);
    coordinator.add(
      P8PHttpPieceSource(writer, reader('late'), id: 'late'),
      diagnosticAlias: 'peer1',
    );
    final download = coordinator.run(active: () => true);
    try {
      expect(await started(1), 'seed', reason: 'Keep a proven prefix owner');
      expect(
        await started(2),
        'late',
        reason: 'Still give the new origin work',
      );
      expect(await started(3), 'seed');
      expect(coordinator.metrics['source_peer1_requests'], 1);
      expect(book.peakReservations, lessThanOrEqualTo(4));
      expect(book.repeatReservedBytes, 0);
    } finally {
      await coordinator.close();
      await download;
    }
  });

  for (final outcome in ['verified', 'stalled', 'deadline']) {
    test('a cold lookahead prefix window ends with $outcome', () async {
      var now = 0;
      await setup(
        10,
        paused: true,
        readClock: () => now,
        requestTimeout: outcome == 'deadline'
            ? const Duration(milliseconds: 1200)
            : const Duration(seconds: 5),
        hedgeAfter: const Duration(seconds: 1),
      );
      final pending = <int, Completer<Uint8List>>{};
      final starts = <int, Completer<String>>{};
      final progress = <int, void Function(int)>{};
      P8PRangeReader reader(String id) => (index, token) async {
        final gate = pending[index] = Completer<Uint8List>();
        final began = starts.putIfAbsent(index, () => Completer<String>());
        if (!began.isCompleted) began.complete(id);
        return Future.any([
          gate.future,
          token.whenCancel.then<Uint8List>((error) => throw error),
        ]);
      };
      Future<String> started(int index) => starts
          .putIfAbsent(index, () => Completer<String>())
          .future
          .timeout(const Duration(seconds: 2));
      void finish(int index) => pending[index]!.complete(piece(index));
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          reader('seed'),
          id: 'seed',
          readWithProgress: (index, token, report) {
            progress[index] = report;
            return reader('seed')(index, token);
          },
        ),
        diagnosticAlias: 'seed',
      );
      final proof = coordinator.probe(0, 'seed')!;
      now = 50000;
      finish(0);
      await proof.verified;
      await proof.stopped;
      final download = coordinator.run(active: () => true);
      try {
        expect(await started(1), 'seed');
        expect(await started(2), 'seed');
        final cold = P8PHttpPieceSource(writer, reader('late'), id: 'late');
        coordinator.add(cold, diagnosticAlias: 'peer1');
        expect(await started(3), 'late');
        now = 350000;
        finish(1);
        finish(2);
        expect(await started(4), 'seed');
        expect(await started(5), 'seed');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(book.persistedPieces, 3);
        now = 450000;
        finish(4);
        expect(await started(6), 'seed');
        progress[5]!(chunk - 1);
        progress[6]!(chunk - 1);
        coordinator.poll();
        // Other owners have delivered real contiguous progress. Their
        // unfinished slots stay occupied and their bytes earn no goodput.
        now = 1150000;
        finish(5);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cold.closed, false);
        expect(coordinator.metrics['prefix_rescues'] ?? 0, 0);
        expect(coordinator.metrics['source_peer1_verified_bytes'], 0);
        expect(book.peakReservations, 4);
        if (outcome == 'verified') {
          now = 1250000;
          finish(3);
          // Let the completion chain submit the verified piece, then await
          // the actual writer. A fixed 50ms sleep can end during file I/O.
          await Future<void>.delayed(Duration.zero);
          await writer.idle;
          expect(coordinator.metrics['source_peer1_verified_bytes'], chunk);
          expect(book.persistedPieces, greaterThanOrEqualTo(4));
          expect(book.repeatReservedBytes, 0);
          expect(coordinator.metrics['prefix_rescues'] ?? 0, 0);
        } else if (outcome == 'stalled') {
          now = 1450000;
          await Future<void>.delayed(const Duration(milliseconds: 80));
          expect(cold.closed, true);
          expect(coordinator.metrics['prefix_rescues'], 1);
          expect(coordinator.metrics['source_peer1_verified_bytes'], 0);
          expect(book.peakReservations, 4);
          expect(book.repeatReservedBytes, lessThanOrEqualTo(2 * chunk));
        } else {
          // It became the prefix at 350ms, but its original lease started
          // at 50ms. The 1200ms hard deadline still wins at 1250ms.
          now = 1260000;
          coordinator.poll();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(
            diagnostics.any(
              (event) =>
                  event.alias == 'peer1' &&
                  event.reason == P8PDiagnosticCode.requestDeadlineExceeded,
            ),
            true,
          );
          expect(coordinator.metrics['prefix_rescues'] ?? 0, 0);
          expect(coordinator.metrics['source_peer1_verified_bytes'], 0);
          expect(book.peakReservations, 4);
        }
      } finally {
        await coordinator.close();
        await download;
      }
      expect(book.reservations, 0);
    });
  }

  test('shared-source queue time does not demote the faster source', () async {
    var now = 0;
    await setup(
      12,
      paused: true,
      readClock: () => now,
      requestTimeout: const Duration(seconds: 5),
      hedgeAfter: const Duration(seconds: 1),
    );
    final pending = <int, Completer<Uint8List>>{};
    final starts = <int, Completer<String>>{};
    P8PRangeReader reader(String id) => (index, token) async {
      final gate = Completer<Uint8List>();
      pending[index] = gate;
      starts.putIfAbsent(index, () => Completer<String>()).complete(id);
      try {
        return await Future.any([
          gate.future,
          token.whenCancel.then<Uint8List>((error) => throw error),
        ]);
      } finally {
        pending.remove(index);
      }
    };
    Future<String> started(int index) => starts
        .putIfAbsent(index, () => Completer<String>())
        .future
        .timeout(const Duration(seconds: 2));
    void finish(int index) => pending[index]!.complete(piece(index));
    coordinator.add(
      P8PHttpPieceSource(writer, reader('fast'), id: 'fast'),
      diagnosticAlias: 'peer1',
    );
    coordinator.add(
      P8PHttpPieceSource(writer, reader('slow'), id: 'slow'),
      diagnosticAlias: 'peer2',
    );
    final fast = coordinator.probe(0, 'fast')!;
    final slow = coordinator.probe(1, 'slow')!;
    now = 100000;
    finish(0);
    await fast.verified;
    await fast.stopped;
    now = 155000;
    finish(1);
    await slow.verified;
    await slow.stopped;
    final download = coordinator.run(active: () => true);
    try {
      expect(await started(2), 'fast');
      expect(await started(3), 'slow');
      expect(await started(4), 'fast');
      // Each origin serializes its two requests. Fast delivers a piece every
      // 100 ms (last one 110 ms); slow takes 155 ms per piece. Queuing a second
      // fast request must not halve its measured link goodput.
      now = 255000;
      finish(2);
      expect(await started(5), 'fast');
      now = 310000;
      finish(3);
      expect(await started(6), 'slow');
      now = 355000;
      finish(4);
      expect(await started(7), 'fast');
      now = 465000;
      finish(5);
      finish(6);
      expect(await started(8), 'slow', reason: 'The slow origin is now idle');
      expect(
        await started(9),
        'fast',
        reason:
            'With one piece queued each, fast finishes another piece sooner',
      );
      expect(book.repeatReservedBytes, 0);
      expect(coordinator.metrics['source_failures'] ?? 0, 0);
    } finally {
      await coordinator.close();
      await download;
    }
    expect(coordinator.metrics['source_peer1_verified_bytes'], 4 * chunk);
    expect(coordinator.metrics['source_peer2_verified_bytes'], 3 * chunk);
    expect(
      coordinator.metrics['source_peer1_busy_us'],
      410000,
      reason: 'Two overlapping requests share one physical ownership interval',
    );
    expect(coordinator.metrics['source_peer2_busy_us'], 465000);
    expect(coordinator.metrics['source_peer1_cancelled'], 2);
    expect(coordinator.metrics['source_peer2_cancelled'], 1);
    expect(coordinator.metrics['source_peer1_failures'], 0);
    expect(book.reservations, 0);
  });

  for (final sample in <({String name, int received, bool credit})>[
    (name: 'contiguous progress', received: chunk * 99 ~/ 100, credit: true),
    (name: 'oversized progress', received: chunk + 1, credit: false),
    (name: 'negative progress', received: -1, credit: false),
  ]) {
    test('remaining queue estimate handles ${sample.name}', () async {
      var now = 0;
      await setup(
        9,
        paused: true,
        readClock: () => now,
        requestTimeout: const Duration(seconds: 5),
        hedgeAfter: const Duration(seconds: 1),
      );
      final pending = <int, Completer<Uint8List>>{};
      final starts = <int, Completer<String>>{};
      final received = <int, int>{};
      P8PRangeReader reader(String id) => (index, token) async {
        final gate = Completer<Uint8List>();
        pending[index] = gate;
        starts.putIfAbsent(index, () => Completer<String>()).complete(id);
        try {
          return await Future.any([
            gate.future,
            token.whenCancel.then<Uint8List>((error) => throw error),
          ]);
        } finally {
          pending.remove(index);
        }
      };
      Future<String> started(int index) => starts
          .putIfAbsent(index, () => Completer<String>())
          .future
          .timeout(const Duration(seconds: 2));
      void finish(int index) => pending[index]!.complete(piece(index));
      coordinator.add(_PartialQueueSource(writer, reader('fast'), received));
      coordinator.add(P8PHttpPieceSource(writer, reader('slow'), id: 'slow'));
      final fast = coordinator.probe(1, 'fast')!;
      final slow = coordinator.probe(0, 'slow')!;
      now = 200000;
      finish(1);
      await fast.verified;
      await fast.stopped;
      now = 800000;
      finish(0);
      await slow.verified;
      await slow.stopped;
      final download = coordinator.run(active: () => true);
      try {
        expect(await started(2), 'slow');
        expect(await started(3), 'fast');
        expect(await started(4), 'fast');
        // The peer lacks piece 2. While HTTP fills that prefix, the first
        // of the peer's two serialized requests nearly finishes. Its second
        // request still has a whole piece outstanding.
        received[3] = sample.received;
        now = 999000;
        coordinator.poll();
        now = 1000000;
        finish(2);
        final limit = Stopwatch()..start();
        while (book.persistedPieces < 3 &&
            limit.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(book.persistedPieces, 3);
        expect(coordinator.metrics['verified_bytes'], 3 * chunk);
        if (sample.credit) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(
            starts[5]?.isCompleted ?? false,
            false,
            reason:
                'Remaining peer queue predicts about 402ms, versus 500ms '
                'for idle HTTP; the already received 99% is not still queued',
          );
          expect(
            book.persistedBytes,
            3 * chunk,
            reason: 'Partial bytes cannot become verified or persisted',
          );
        } else {
          expect(
            await started(5),
            'slow',
            reason: 'Invalid counts cannot discount the peer queue',
          );
        }
        now = 1002000;
        finish(3);
        if (sample.credit) expect(await started(5), 'fast');
        for (var turn = 0; !book.complete && turn < 30; turn++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          now += 100000;
          for (final index in pending.keys.toList()) {
            if (!pending[index]!.isCompleted) finish(index);
          }
        }
        expect(await download.timeout(const Duration(seconds: 2)), true);
        expect(await store.completeAndVerified(), true);
        expect(book.peakReservations, lessThanOrEqualTo(4));
        expect(book.repeatReservedBytes, 0);
        expect(coordinator.metrics['source_failures'] ?? 0, 0);
      } finally {
        await coordinator.close();
        await download;
      }
      expect(book.reservations, 0);
    });
  }

  test('partial body cannot claim a bodyless admission release', () async {
    await setup(3, paused: true, repeat: 0);
    final http = P8PHttpPieceSource(
      writer,
      (_, _) async => throw StateError('Progress reader required'),
      readWithProgress: (_, _, received) async {
        received(16);
        throw P8PSourceDeferred(const Duration(seconds: 2));
      },
    );
    coordinator.add(http);
    final request = coordinator.probe(0, 'https')!;
    await expectLater(request.verified, throwsStateError);
    await request.stopped;
    expect(coordinator.metrics['source_failures'], 1);
    expect(coordinator.metrics['source_deferred'] ?? 0, 0);
    expect(book.reservations, 0);
    expect(book.request(0, 'node', timeout: const Duration(seconds: 1)), null);
  });

  test(
    'cancellation closes a deferred source without waiting or retrying',
    () async {
      await setup(3, paused: true);
      var calls = 0, active = true;
      final http = P8PHttpPieceSource(writer, (_, _) async {
        calls++;
        throw P8PSourceDeferred(const Duration(seconds: 2));
      });
      coordinator.add(http);
      final request = coordinator.probe(0, 'https')!;
      await expectLater(request.verified, throwsA(isA<P8PSourceDeferred>()));
      await request.stopped;
      var finished = false;
      final download = coordinator
          .run(active: () => active)
          .whenComplete(() => finished = true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        finished,
        false,
        reason: 'A deferred source remains eligible after its wait',
      );
      active = false;
      expect(await download.timeout(const Duration(seconds: 1)), false);
      expect(calls, 1);
      expect(http.closed, true);
      expect(book.reservations, 0);
    },
  );

  test(
    'a progressing prefix is not rescued solely because its whole piece is old',
    () async {
      var now = 0, received = 0;
      await setup(
        5,
        readClock: () => now,
        requestTimeout: const Duration(seconds: 5),
        hedgeAfter: const Duration(seconds: 1),
      );
      final started = Completer<void>(), finish = Completer<void>();
      final source = _MeteredSource(writer, (index, token) async {
        if (index == 0) {
          if (!started.isCompleted) started.complete();
          await Future.any([
            finish.future,
            token.whenCancel.then<void>((error) => throw error),
          ]);
        }
        return piece(index);
      }, () => received);
      coordinator.add(source);
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (index, token) async => piece(index),
          id: 'fast',
        ),
      );
      final download = coordinator.run(active: () => true);
      try {
        await started.future;
        for (var tick = 0; tick < 16; tick++) {
          now += 100000;
          received += chunk ~/ 16;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(
            source.closed,
            false,
            reason: 'The prefix still receives contiguous body bytes',
          );
          expect(book.repeatReservedBytes, 0);
        }
        finish.complete();
        expect(await download.timeout(const Duration(seconds: 2)), true);
        expect(await store.completeAndVerified(), true);
        expect(coordinator.metrics['prefix_rescues'] ?? 0, 0);
      } finally {
        if (!finish.isCompleted) finish.complete();
        await coordinator.close();
        await download;
      }
    },
  );

  for (final outcome in [
    'verified',
    'stalled',
    'deadline',
    'cancelled',
    'capped',
    'not_tail',
    'no_advice',
    'oversized_advice',
    'no_progress',
  ]) {
    test('bounded RTC tail recovery $outcome', () async {
      var now = 0, received = 0;
      var active = true;
      await setup(
        7,
        paused: true,
        readClock: () => now,
        requestTimeout: outcome == 'capped'
            ? const Duration(seconds: 8)
            : outcome == 'deadline'
            ? const Duration(milliseconds: 1200)
            : const Duration(seconds: 5),
        hedgeAfter: const Duration(seconds: 1),
      );
      final pending = <(String, int), Completer<Uint8List>>{};
      final started = <(String, int), Completer<void>>{};
      P8PRangeReader reader(String source) => (index, token) async {
        final key = (source, index);
        final gate = pending[key] = Completer<Uint8List>();
        final began = started.putIfAbsent(key, () => Completer<void>());
        if (!began.isCompleted) began.complete();
        return Future.any([
          gate.future,
          token.whenCancel.then<Uint8List>((error) => throw error),
        ]);
      };
      Future<void> began(String source, int index) => started
          .putIfAbsent((source, index), () => Completer<void>())
          .future
          .timeout(const Duration(seconds: 2));
      final tail = _TailMeteredSource(
        writer,
        reader('tail'),
        () => received,
        outcome == 'no_advice'
            ? 0
            : outcome == 'oversized_advice'
            ? 65537
            : 49136,
      );
      coordinator.add(tail, diagnosticAlias: 'peer1');
      coordinator.add(
        P8PHttpPieceSource(writer, reader('fast'), id: 'fast'),
        diagnosticAlias: 'https',
      );
      final proof = coordinator.probe(1, 'fast')!;
      now = outcome == 'capped' ? 1000000 : 100000;
      pending[('fast', 1)]!.complete(piece(1));
      await proof.verified;
      await proof.stopped;
      final request = coordinator.probe(0, 'tail')!;
      final tailOutcome = request.verified.then<bool>(
        (_) => true,
        onError: (Object _) => false,
      );
      final download = coordinator.run(active: () => active);
      try {
        await began('fast', 2);
        await began('fast', 3);
        now = outcome == 'capped' ? 2000000 : 200000;
        received = outcome == 'not_tail'
            ? chunk ~/ 4
            : outcome == 'no_progress'
            ? 0
            : 1031856;
        coordinator.poll();
        pending[('fast', 2)]!.complete(piece(2));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(book.reservations, 4);
        if (outcome == 'capped') {
          now = 5000000;
          received++;
          coordinator.poll();
        }
        // The verified alternative has one queued piece and predicts 200ms
        // to replace this whole prefix; its second slot is now available.
        now = outcome == 'capped' ? 6500000 : 1250000;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        final qualifies = ![
          'not_tail',
          'no_advice',
          'oversized_advice',
          'no_progress',
        ].contains(outcome);
        expect(tail.closed, !qualifies);
        expect(coordinator.metrics['source_peer1_verified_bytes'], 0);
        expect(book.persistedBytes, 0);
        if (!qualifies) {
          await began('fast', 0);
          expect(await tailOutcome, false);
          expect(coordinator.metrics['prefix_rescues'], 1);
        } else if (outcome == 'verified') {
          now = 1300000;
          pending[('tail', 0)]!.complete(piece(0));
          expect(await tailOutcome, true);
          await writer.idle;
          expect(book.persistedPieces, greaterThanOrEqualTo(3));
          expect(coordinator.metrics['source_peer1_verified_bytes'], chunk);
          expect(coordinator.metrics['prefix_rescues'] ?? 0, 0);
          expect(book.repeatReservedBytes, 0);
        } else if (outcome == 'stalled') {
          now = 1450000;
          await began('fast', 0);
          expect(await tailOutcome, false);
          expect(tail.closed, true);
          expect(coordinator.metrics['prefix_rescues'], 1);
          expect(book.repeatReservedBytes, chunk);
        } else if (outcome == 'capped') {
          now = 7050000;
          await began('fast', 0);
          expect(await tailOutcome, false);
          expect(tail.closed, true);
          expect(coordinator.metrics['prefix_rescues'], 1);
        } else if (outcome == 'deadline') {
          now = 1310000;
          coordinator.poll();
          expect(await tailOutcome, false);
          expect(
            diagnostics.any(
              (event) =>
                  event.alias == 'peer1' &&
                  event.reason == P8PDiagnosticCode.requestDeadlineExceeded,
            ),
            true,
          );
          expect(coordinator.metrics['prefix_rescues'] ?? 0, 0);
        } else {
          active = false;
          expect(await download.timeout(const Duration(seconds: 2)), false);
          expect(await tailOutcome, false);
          expect(tail.closed, true);
          expect(coordinator.metrics['prefix_rescues'] ?? 0, 0);
        }
        expect(book.peakReservations, 4);
        expect(book.peakReservedBytes, lessThanOrEqualTo(4 * chunk));
        expect(book.repeatReservedBytes, lessThanOrEqualTo(2 * chunk));
      } finally {
        active = false;
        await coordinator.close();
        await download;
      }
      expect(book.reservations, 0);
    });
  }

  test(
    'a prefix that stops progressing is still rescued before expiry',
    () async {
      var now = 0;
      await setup(
        6,
        readClock: () => now,
        requestTimeout: const Duration(seconds: 5),
        hedgeAfter: const Duration(seconds: 1),
      );
      final started = Completer<void>();
      late void Function(int) report;
      var cancelled = false;
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (index, token) async => throw StateError('Progress reader required'),
          id: 'stalls',
          readWithProgress: (index, token, received) async {
            report = received;
            started.complete();
            await token.whenCancel;
            cancelled = true;
            throw StateError('cancelled stalled owner');
          },
        ),
      );
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (index, token) async => piece(index),
          id: 'healthy',
        ),
      );
      final download = coordinator.run(active: () => true);
      try {
        await started.future;
        now = 100000;
        report(chunk ~/ 4);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        now = 1000000;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(cancelled, false);
        expect(book.persistedBytes, 0);
        now = 1200000;
        expect(await download.timeout(const Duration(seconds: 2)), true);
        expect(cancelled, true);
        expect(coordinator.metrics['prefix_rescues'], 1);
        expect(await store.completeAndVerified(), true);
        expect(book.peakReservations, lessThanOrEqualTo(4));
        expect(book.repeatReservedBytes, lessThanOrEqualTo(2 * chunk));
        expect(book.reservations, 0);
      } finally {
        await coordinator.close();
        await download;
      }
    },
  );

  test(
    'continuous body progress never extends the hard request deadline',
    () async {
      var now = 0;
      await setup(
        3,
        paused: true,
        readClock: () => now,
        requestTimeout: const Duration(seconds: 1),
      );
      late void Function(int) report;
      var cancelled = false;
      final source = P8PHttpPieceSource(
        writer,
        (index, token) async => throw StateError('Progress reader required'),
        readWithProgress: (index, token, received) async {
          report = received;
          await token.whenCancel;
          cancelled = true;
          throw StateError('cancelled expired owner');
        },
      );
      coordinator.add(source);
      final request = coordinator.probe(0, source.id)!;
      final failure = expectLater(request.verified, throwsStateError);
      for (var tick = 1; tick < 10; tick++) {
        now = tick * 100000;
        report(tick * (chunk ~/ 16));
        coordinator.poll();
        expect(cancelled, false);
        expect(book.reservations, 1);
      }
      now = 1000001;
      report(10 * (chunk ~/ 16));
      coordinator.poll();
      await failure;
      await request.stopped;
      expect(cancelled, true);
      expect(book.reservations, 0);
      expect(book.persistedBytes, 0);
      expect(store.file.existsSync(), false);
    },
  );

  test(
    'an unavailable prefix keeps lookahead from consuming its slot',
    () async {
      await setup(4, readClock: () => 0);
      final requested = <int>[];
      coordinator.add(
        _SelectiveHttpSource(
          writer,
          (index, token) async {
            requested.add(index);
            return piece(index);
          },
          (index) => index > 0,
          id: 'ahead-only',
        ),
      );
      expect(await coordinator.run(active: () => true), false);
      expect(requested, isEmpty);
      expect(book.reservations, 0);
      expect(book.persistedPieces, 0);
    },
  );

  test('a busy lookahead gap does not idle unrelated piece sources', () async {
    await setup(4, readClock: () => 0);
    final release = Completer<void>();
    final next = {2: Completer<void>(), 3: Completer<void>()};
    final prefixRequests = <int>[];
    coordinator.add(
      _SelectiveHttpSource(
        writer,
        (index, token) async {
          prefixRequests.add(index);
          if (index == 0) await release.future;
          return piece(index);
        },
        (index) => index < 2,
        id: 'prefix',
      ),
    );
    for (final index in next.keys) {
      coordinator.add(
        _SelectiveHttpSource(
          writer,
          (requested, token) async {
            next[index]!.complete();
            return piece(requested);
          },
          (requested) => requested == index,
          id: 'ahead-$index',
        ),
      );
    }
    final running = coordinator.run(active: () => true);
    try {
      await Future.wait(
        next.values.map((event) => event.future),
      ).timeout(const Duration(milliseconds: 750));
      expect(prefixRequests, [0]);
      expect(book.persistedPieces, 0);
      expect(book.reservations, 3);
    } finally {
      release.complete();
      expect(await running, true);
    }
    expect(prefixRequests, [0, 1]);
    expect(await store.completeAndVerified(), true);
    expect(book.peakReservations, lessThanOrEqualTo(4));
  });

  test(
    'startup probes share reservations and transfer into the running scheduler',
    () async {
      await setup(7, paused: true);
      for (final id in ['seed', 'peer', 'https']) {
        coordinator.add(
          P8PHttpPieceSource(
            writer,
            (index, token) async => piece(index),
            id: id,
          ),
        );
      }
      final first = coordinator.probe(0, 'seed')!;
      expect(
        coordinator.probe(1, 'seed'),
        isNull,
        reason: 'Only one cold probe per source',
      );
      final second = coordinator.probe(1, 'peer')!;
      expect(
        coordinator.probe(1, 'https'),
        isNull,
        reason: 'No duplicate startup piece',
      );
      expect(
        coordinator.probe(4, 'https'),
        isNull,
        reason: 'Lookahead includes only prefix through prefix+3',
      );
      await Future.wait([first.verified, second.verified]);
      await writer.idle;
      expect(book.reservations, 2);
      expect(store.file.existsSync(), false);
      expect(coordinator.metrics['requests'], 2);
      expect(await coordinator.run(active: () => true), true);
      expect(await store.completeAndVerified(), true);
      expect(book.repeatReservedBytes, 0);
      expect(book.peakReservations, lessThanOrEqualTo(4));
      expect(book.reservations, 0);
    },
  );

  test(
    'startup timeout retains its reservation until the physical owner stops',
    () async {
      await setup(
        3,
        paused: true,
        requestTimeout: const Duration(milliseconds: 40),
      );
      final release = Completer<void>();
      var cancelled = false;
      final source = P8PHttpPieceSource(writer, (index, token) async {
        unawaited(token.whenCancel.then((_) => cancelled = true));
        await release.future;
        return piece(index);
      });
      coordinator.add(source);
      final request = coordinator.probe(0, source.id)!;
      final failure = expectLater(request.verified, throwsA(isA<StateError>()));
      try {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        coordinator.poll();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        coordinator.poll();
        expect(cancelled, true);
        expect(source.closed, true);
        expect(book.reservations, 1);
        expect(store.file.existsSync(), false);
      } finally {
        release.complete();
      }
      await failure;
      await request.stopped;
      expect(book.reservations, 0);
      expect(store.file.existsSync(), false);
      expect(diagnostics.map((event) => event.reason), [
        P8PDiagnosticCode.requestDeadlineExceeded,
        P8PDiagnosticCode.stopGraceExceeded,
      ]);
    },
  );

  test(
    'partial piece reports the original eight second deadline and one second stop grace',
    () async {
      var now = 0;
      await setup(
        3,
        paused: true,
        readClock: () => now,
        requestTimeout: const Duration(seconds: 8),
        stopGrace: const Duration(seconds: 1),
        failObserver: true,
      );
      final release = Completer<Uint8List>();
      final source = _MeteredSource(
        writer,
        (_, token) => release.future,
        () => 884448,
      );
      coordinator.add(source, diagnosticAlias: 'peer1');
      final request = coordinator.probe(0, source.id)!;
      final failure = expectLater(
        request.verified,
        throwsA(isA<P8PLeaseCancelled>()),
      );
      now = 7999999;
      coordinator.poll();
      expect(diagnostics, isEmpty);
      expect(source.closed, false);
      now = 8000000;
      coordinator.poll();
      expect(
        diagnostics.single.reason,
        P8PDiagnosticCode.requestDeadlineExceeded,
      );
      expect(diagnostics.single.alias, 'peer1');
      expect(diagnostics.single.actualBytes, 884448);
      expect(diagnostics.single.expectedBytes, chunk);
      now = 8999999;
      coordinator.poll();
      expect(source.closed, false);
      now = 9000000;
      coordinator.poll();
      coordinator.poll();
      expect(diagnostics.last.reason, P8PDiagnosticCode.stopGraceExceeded);
      expect(diagnostics, hasLength(2));
      expect(source.closed, true);
      expect(
        book.reservations,
        1,
        reason: 'Observer failure cannot release a live owner',
      );
      expect(book.persistedBytes, 0);
      release.complete(piece(0));
      await failure;
      await request.stopped;
      expect(book.reservations, 0);
      expect(coordinator.metrics['source_failures'] ?? 0, 0);
    },
  );

  for (final scenario in ['ack', 'no_ack', 'repeat', 'alternative']) {
    final acknowledge = scenario != 'no_ack';
    final repeat = scenario == 'repeat';
    final alternative = scenario == 'alternative';
    test(
      'proven RTC prefix rescue waits for physical stop and preserves siblings: $scenario',
      () async {
        var now = 0;
        await setup(
          10,
          paused: true,
          readClock: () => now,
          requestTimeout: const Duration(seconds: 8),
          hedgeAfter: const Duration(seconds: 1),
          stopGrace: const Duration(seconds: 1),
          traceLifecycle: true,
        );
        final controls = <Map<String, Object?>>[];
        final httpBodies = <int, Completer<Uint8List>>{};
        var replacePrefix = false, autoHttp = false, autoRtc = false;
        var seedLater = false, seedPrefix = false;
        var transportCloses = 0;
        final delivered = <int>{};
        final closeGate = Completer<void>();
        late P8PTransferReceiver receiver;
        void control(String type, int identity, [int? index]) {
          receiver.acceptControl(
            jsonEncode({
              'type': type,
              'version': 1,
              'generation': 1,
              'request_id': identity,
              'index': ?index,
              if (type == 'piece-start') 'size': manifest.pieceSize(index!),
            }),
          );
        }

        void deliver(int identity, int index) {
          if (!delivered.add(identity)) return;
          final bytes = piece(index);
          control('piece-start', identity, index);
          final frameBytes =
              P8PTransferProtocol.maxFrameBytes -
              P8PTransferProtocol.headerBytes;
          for (var offset = 0; offset < bytes.length; offset += frameBytes) {
            receiver.acceptBinary(
              P8PTransferProtocol.encode(
                1,
                identity,
                offset,
                Uint8List.sublistView(
                  bytes,
                  offset,
                  (offset + frameBytes).clamp(0, bytes.length),
                ),
              ),
            );
          }
          control('piece-end', identity, index);
        }

        Future<void> until(bool Function() done) async {
          final waiting = Stopwatch()..start();
          while (!done() && waiting.elapsed < const Duration(seconds: 3)) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(
            done(),
            true,
            reason:
                'Wait for the actual ownership event: '
                'prefix=${book.persistedPieces}, slots=${book.reservations}, '
                'rescues=${coordinator.metrics['prefix_rescues'] ?? 0}',
          );
        }

        Map<String, Object?> getRequest(int index) => controls.firstWhere(
          (c) => c['type'] == 'get' && c['index'] == index,
        );
        receiver = P8PTransferReceiver(
          source: 'proven-rtc',
          writer: writer,
          send: (value) async {
            controls.add(value);
            if (autoRtc && value['type'] == 'get') {
              scheduleMicrotask(
                () =>
                    deliver(value['request_id'] as int, value['index'] as int),
              );
            }
          },
          closeTransport: () async {
            transportCloses++;
            await closeGate.future;
          },
        );
        final ready = receiver.connect(const Duration(seconds: 1));
        receiver.acceptControl(
          jsonEncode({
            'type': 'hello',
            'version': 1,
            'generation': 1,
            'sha256': manifest.sha256,
            'max_inflight': 4,
          }),
        );
        await ready;
        coordinator.add(
          P8PRtcPieceSource(
            receiver,
            pieces: alternative ? {0, 2, 4, 6} : {0, 2, 4, 7, 9},
          ),
          diagnosticAlias: 'peer1',
        );
        final first = coordinator.probe(0, 'proven-rtc')!;
        now = 100000;
        deliver(first.lease.id, 0);
        await first.verified;
        await first.stopped;
        coordinator.add(
          _SelectiveHttpSource(
            writer,
            (index, token) async {
              if (autoHttp) return piece(index);
              final body = httpBodies.putIfAbsent(
                index,
                Completer<Uint8List>.new,
              );
              return Future.any([
                body.future,
                token.whenCancel.then<Uint8List>(
                  (_) => throw P8PLeaseCancelled(),
                ),
              ]);
            },
            (index) =>
                index != 0 &&
                (!alternative || index < 7) &&
                (index != 4 || receiver.closed) &&
                (index != 2 || replacePrefix),
          ),
          diagnosticAlias: 'https',
        );
        final second = coordinator.probe(1, 'https')!;
        now = 200000;
        httpBodies[1]!.complete(piece(1));
        await second.verified;
        await second.stopped;
        if (alternative) {
          coordinator.add(
            _SelectiveHttpSource(
              writer,
              (index, _) async => piece(index),
              (index) =>
                  index == 3 ||
                  (seedLater && index >= 7) ||
                  (seedPrefix && index == 6),
              id: 'seed',
            ),
            diagnosticAlias: 'seed',
          );
          final proof = coordinator.probe(3, 'seed')!;
          now = 300000;
          await proof.verified;
          await proof.stopped;
        }
        var active = true;
        final run = coordinator.run(active: () => active);
        try {
          await until(() => httpBodies.containsKey(5));
          final prefix = getRequest(2)['request_id'] as int;
          final sibling = getRequest(4)['request_id'] as int;
          if (!alternative) httpBodies[3]!.complete(piece(3));
          httpBodies[5]!.complete(piece(5));
          await until(() => writer.bufferedPieces == 2);
          replacePrefix = true;
          now = 1400000;
          await until(() => controls.any((c) => c['type'] == 'cancel'));
          expect(
            controls
                .where((c) => c['type'] == 'cancel')
                .map((c) => c['request_id']),
            [prefix],
          );
          expect(
            transportCloses,
            0,
            reason: 'One stalled lease must not close a proven transport',
          );
          expect(receiver.closed, false);
          expect(book.reservations, 4);
          expect(
            httpBodies.containsKey(2),
            false,
            reason: 'Sending cancel is not physical slot release',
          );
          expect(coordinator.metrics['source_peer1_verified_bytes'], chunk);
          expect(coordinator.metrics['source_recoveries'], 1);
          if (acknowledge) {
            deliver(sibling, 4);
            await until(() => writer.bufferedPieces == 3);
            control('cancelled', prefix);
            await until(() => httpBodies.containsKey(2));
            if (alternative) seedLater = true;
            httpBodies[2]!.complete(piece(2));
            if (alternative) {
              await until(
                () => book.persistedPieces == 6 && writer.bufferedPieces == 3,
              );
              expect(coordinator.metrics['source_rejoins'] ?? 0, 0);
              expect(transportCloses, 0);
              seedPrefix = true;
              closeGate.complete();
              await until(() {
                now += 25000;
                return coordinator.metrics['prefix_rescues'] == 2;
              });
            } else {
              await until(
                () =>
                    controls.any((c) => c['type'] == 'get' && c['index'] == 7),
              );
              expect(transportCloses, 0);
              expect(
                coordinator.metrics['source_peer1_verified_bytes'],
                2 * chunk,
              );
              expect(coordinator.metrics['source_rejoins'] ?? 0, 0);
              deliver(getRequest(7)['request_id'] as int, 7);
              await until(() => coordinator.metrics['source_rejoins'] == 1);
              // A late ACK for the retired request cannot cancel its successor.
              control('cancelled', prefix);
              expect(receiver.closed, false);
              autoRtc = !repeat;
              for (final request in controls.toList()) {
                if (request['type'] == 'get' &&
                    request['request_id'] != prefix &&
                    (!repeat || request['index'] != 9)) {
                  deliver(
                    request['request_id'] as int,
                    request['index'] as int,
                  );
                }
              }
            }
          } else {
            now = 2399999;
            coordinator.poll();
            expect(transportCloses, 0);
            now = 2400000;
            coordinator.poll();
            await until(() => transportCloses == 1);
            expect(
              book.reservations,
              4,
              reason: 'A pending native close retains both RTC owners',
            );
            expect(httpBodies.containsKey(2), false);
            closeGate.complete();
          }
          autoHttp = true;
          for (final entry in httpBodies.entries) {
            if (!entry.value.isCompleted) {
              entry.value.complete(piece(entry.key));
            }
          }
          if (repeat) {
            await until(
              () =>
                  book.persistedPieces == 9 &&
                  controls.any((c) => c['type'] == 'get' && c['index'] == 9),
            );
            await until(() {
              now += 25000;
              return coordinator.metrics['prefix_rescues'] == 2;
            });
          }
          if (!closeGate.isCompleted) closeGate.complete();
          expect(await run.timeout(const Duration(seconds: 4)), true);
          expect(await store.completeAndVerified(), true);
          expect(book.peakReservations, 4);
          expect(book.peakReservedBytes, lessThanOrEqualTo(4 * chunk));
          expect(book.repeatReservedBytes, lessThanOrEqualTo(2 * chunk));
          expect(book.reservations, 0);
          expect(
            coordinator.metrics['source_rejoins'] ?? 0,
            acknowledge && !alternative ? 1 : 0,
          );
          expect(
            coordinator.metrics['source_recoveries'],
            1,
            reason: 'Only one soft recovery is admitted per RTC source',
          );
          if (repeat || alternative) {
            expect(coordinator.metrics['prefix_rescues'], 2);
          }
        } finally {
          active = false;
          if (!closeGate.isCompleted) closeGate.complete();
          await coordinator.close();
          await run;
        }
      },
    );
  }

  for (final failTrace in [false, true]) {
    test(
      'full-slot rescue snapshot preserves ownership with throwing logger=$failTrace',
      () async {
        var now = 0;
        await setup(
          9,
          readClock: () => now,
          requestTimeout: const Duration(seconds: 5),
          hedgeAfter: const Duration(seconds: 1),
          traceLifecycle: true,
          failLifecycle: failTrace,
        );
        var slowCalls = 0;
        coordinator.add(
          P8PHttpPieceSource(writer, (_, token) async {
            slowCalls++;
            await token.whenCancel;
            throw token.cancelError!;
          }, id: 'private-slow-source'),
          diagnosticAlias: 'peer1',
        );
        coordinator.add(
          P8PHttpPieceSource(
            writer,
            (index, _) async => piece(index),
            id: 'private-fast-source',
          ),
          diagnosticAlias: 'https',
        );
        final run = coordinator.run(active: () => true);
        try {
          final waiting = Stopwatch()..start();
          while ((book.reservations != 4 || writer.bufferedPieces != 3) &&
              waiting.elapsed < const Duration(seconds: 2)) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(book.reservations, 4);
          expect(writer.bufferedPieces, 3);
          final ownership = book.diagnosticReservations;
          expect(() => ownership.clear(), throwsUnsupportedError);
          expect(book.reservations, 4);
          expect(
            lifecycle.where((e) => e.code == P8PLifecycleCode.rescueSlot),
            isEmpty,
          );
          now = 1200000;
          expect(await run.timeout(const Duration(seconds: 3)), true);
          final slots = lifecycle
              .where((e) => e.code == P8PLifecycleCode.rescueSlot)
              .toList();
          expect(slots, hasLength(4));
          expect(slots.map((e) => e.metrics['slot_position']), [1, 2, 3, 4]);
          expect(
            slots.every(
              (e) =>
                  e.metrics['snapshot_sequence'] == 1 &&
                  e.metrics['reserved_slots'] == 4,
            ),
            true,
          );
          final cold = slots.singleWhere((e) => e.alias == 'peer1');
          expect(cold.metrics['slot_phase'], 1);
          expect(cold.metrics['body_bytes'], 0);
          expect(cold.metrics['piece_ahead'], 0);
          expect(cold.metrics['request_remaining_us'], 3800000);
          expect(
            slots
                .where((e) => e.alias == 'https')
                .every(
                  (e) =>
                      e.metrics['slot_phase'] == 3 &&
                      e.metrics['body_bytes'] == chunk,
                ),
            true,
          );
          expect(
            lifecycle.where((e) => e.code == P8PLifecycleCode.requestAllocated),
            hasLength(2),
          );
          expect(
            jsonEncode(slots.map((e) => e.metrics).toList()),
            isNot(contains('private')),
          );
          expect(slowCalls, 1);
          expect(book.repeatReservedBytes, chunk);
          expect(book.peakReservations, 4);
          expect(book.reservations, 0);
          expect(await store.completeAndVerified(), true);
        } finally {
          await coordinator.close();
          await run;
        }
      },
    );
  }

  test(
    'slow cold prefix is rescued before expiry and is not refilled',
    () async {
      await setup(9, requestTimeout: const Duration(seconds: 5));
      var slowCalls = 0;
      int? cancelledAt;
      coordinator.add(
        P8PHttpPieceSource(writer, (index, token) async {
          slowCalls++;
          await token.whenCancel;
          cancelledAt = clock.elapsedMilliseconds;
          throw token.cancelError!;
        }, id: 'slow'),
      );
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (index, token) async => piece(index),
          id: 'fast',
        ),
      );
      expect(await coordinator.run(active: () => true), true);
      expect(slowCalls, 1);
      expect(cancelledAt, lessThan(5000));
      expect(coordinator.metrics['prefix_rescues'], greaterThanOrEqualTo(1));
      expect(book.repeatReservedBytes, chunk);
      expect(book.peakReservations, lessThanOrEqualTo(4));
      expect(await store.completeAndVerified(), true);
    },
  );

  test(
    'different sources retain a bounded lookahead and one verified file',
    () async {
      await setup(9);
      final received = <String, Set<int>>{};
      for (final id in ['node', 'https']) {
        coordinator.add(
          P8PHttpPieceSource(writer, (index, token) async {
            (received[id] ??= {}).add(index);
            await Future<void>.delayed(
              Duration(milliseconds: id == 'node' ? 10 : 15),
            );
            return piece(index);
          }, id: id),
        );
      }
      expect(await coordinator.run(active: () => true), true);
      expect(received.values.every((indices) => indices.isNotEmpty), true);
      expect(received['node']!.intersection(received['https']!), isEmpty);
      expect(await store.completeAndVerified(), true);
      expect(coordinator.metrics['peak_reservations'], lessThanOrEqualTo(4));
      expect(
        coordinator.metrics['peak_reserved_bytes'],
        lessThanOrEqualTo(4 * chunk),
      );
      expect(book.reservations, 0);
    },
  );

  test(
    'four origins share work concurrently and assemble one verified file',
    () async {
      await setup(12);
      const aliases = ['peer1', 'peer2', 'seed', 'https'];
      final firstWave = Completer<void>();
      final received = <String, Set<int>>{};
      var activeReads = 0, peakReads = 0;
      for (final alias in aliases) {
        expect(
          coordinator.add(
            P8PHttpPieceSource(writer, (index, token) async {
              (received[alias] ??= {}).add(index);
              activeReads++;
              if (activeReads > peakReads) peakReads = activeReads;
              if (received.length == aliases.length && !firstWave.isCompleted) {
                firstWave.complete();
              }
              try {
                // No source can finish its probe until all four origins own work.
                await firstWave.future;
                await Future<void>.delayed(const Duration(milliseconds: 5));
                return piece(index);
              } finally {
                activeReads--;
              }
            }, id: alias),
            diagnosticAlias: alias,
          ),
          true,
        );
      }
      final excess = P8PHttpPieceSource(writer, (_, token) async {
        fail('A fifth origin must not start work');
      }, id: 'excess');
      expect(coordinator.add(excess), false);
      await excess.close();
      expect(
        await coordinator
            .run(active: () => true)
            .timeout(const Duration(seconds: 5)),
        true,
      );
      expect(peakReads, 4);
      expect(activeReads, 0);
      final indices = received.values.expand((value) => value).toList();
      expect(indices.length, manifest.pieceHashes.length);
      expect(indices.toSet().length, indices.length);
      for (final alias in aliases) {
        expect(received[alias], isNotEmpty);
        expect(
          coordinator.metrics['source_${alias}_verified_bytes'],
          greaterThan(0),
        );
      }
      expect(coordinator.metrics['verified_bytes'], payload.length);
      expect(book.peakReservations, 4);
      expect(book.peakReservedBytes, lessThanOrEqualTo(4 * chunk));
      expect(book.repeatReservedBytes, 0);
      expect(book.reservations, 0);
      expect(await store.completeAndVerified(), true);
    },
  );

  test(
    'slow tail hedges only within the total duplicate and slot budget',
    () async {
      await setup(3);
      final stopped = Completer<void>();
      coordinator.add(
        P8PHttpPieceSource(writer, (index, token) async {
          if (index == 0) {
            await token.whenCancel;
            stopped.complete();
            throw token.cancelError!;
          }
          return piece(index);
        }, id: 'slow'),
      );
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (index, token) async => piece(index),
          id: 'fast',
        ),
      );
      expect(await coordinator.run(active: () => true), true);
      expect(stopped.isCompleted, true);
      expect(coordinator.metrics['hedges'], 1);
      expect(book.repeatReservedBytes, chunk);
      expect(await store.completeAndVerified(), true);
      expect(book.reservations, 0);
    },
  );

  test(
    'budget zero falls back after timeout without unbudgeted retransmission',
    () async {
      await setup(
        3,
        repeat: 0,
        requestTimeout: const Duration(milliseconds: 80),
      );
      coordinator.add(
        P8PHttpPieceSource(writer, (index, token) async {
          await token.whenCancel;
          throw token.cancelError!;
        }, id: 'stalled'),
      );
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (index, token) async => piece(index),
          id: 'healthy',
        ),
      );
      expect(await coordinator.run(active: () => true), false);
      expect(book.repeatReservedBytes, 0);
      expect(book.persistedBytes, 0);
      expect(store.file.existsSync(), false);
      expect(book.reservations, 0);
    },
  );

  test(
    'cancellation waits for the actual HTTP owner before releasing its slot',
    () async {
      await setup(5);
      final gate = Completer<void>(), started = Completer<void>();
      var active = true;
      coordinator.add(
        P8PHttpPieceSource(writer, (index, token) async {
          if (!started.isCompleted) started.complete();
          await gate.future;
          return piece(index);
        }),
      );
      final run = coordinator.run(active: () => active);
      await started.future;
      active = false;
      var ended = false;
      final closing = coordinator.close().then((_) => ended = true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(ended, false);
      expect(book.reservations, greaterThan(0));
      gate.complete();
      await closing;
      expect(await run, false);
      expect(book.reservations, 0);
      expect(store.file.existsSync(), false);
    },
  );

  test(
    'bad source is retired while another completes its missing pieces',
    () async {
      await setup(6);
      var badCalls = 0;
      coordinator.add(
        P8PHttpPieceSource(writer, (index, token) async {
          badCalls++;
          return piece(index)..[0] ^= 255;
        }, id: 'bad'),
      );
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (index, token) async => piece(index),
          id: 'healthy',
        ),
      );
      expect(await coordinator.run(active: () => true), true);
      expect(badCalls, lessThanOrEqualTo(2));
      expect(coordinator.metrics['source_failures'], greaterThanOrEqualTo(1));
      expect(await store.completeAndVerified(), true);
      expect(book.reservations, 0);
    },
  );

  test(
    'RTC cancellation acknowledged before poll does not retire its source',
    () async {
      var now = 0;
      await setup(
        4,
        paused: true,
        readClock: () => now,
        requestTimeout: const Duration(milliseconds: 100),
      );
      var transportClosed = false;
      final controls = <Map<String, Object?>>[];
      final receiver = P8PTransferReceiver(
        source: 'node',
        writer: writer,
        send: (value) async {
          controls.add(value);
        },
        closeTransport: () async {
          transportClosed = true;
        },
      );
      final ready = receiver.connect(const Duration(seconds: 1));
      receiver.acceptControl(
        jsonEncode({
          'type': 'hello',
          'version': 1,
          'generation': 1,
          'sha256': manifest.sha256,
          'max_inflight': 4,
        }),
      );
      await ready;
      coordinator.add(P8PRtcPieceSource(receiver), diagnosticAlias: 'peer1');
      final request = coordinator.probe(0, 'node')!;
      expect(
        request.progressUnitBytes,
        P8PTransferProtocol.maxFrameBytes - P8PTransferProtocol.headerBytes,
      );
      final cancelled = expectLater(
        request.verified,
        throwsA(isA<StateError>()),
      );
      // The writer/request ledger can expire a lease between coordinator polls.
      // A late RTC frame observes that cancellation and sends its own cancel.
      now = 110000;
      book.expire();
      receiver.acceptBinary(
        P8PTransferProtocol.encode(1, request.lease.id, 0, Uint8List(1)),
      );
      expect(controls.last['type'], 'cancel');
      receiver.acceptControl(
        jsonEncode({
          'type': 'cancelled',
          'version': 1,
          'generation': 1,
          'request_id': request.lease.id,
        }),
      );
      await cancelled;
      await request.stopped;
      await Future<void>.delayed(Duration.zero);
      expect(
        transportClosed,
        false,
        reason: 'An acknowledged local cancel is not a source failure',
      );
      expect(coordinator.metrics['source_failures'] ?? 0, 0);
      expect(coordinator.metrics['source_peer1_failures'], 0);
      expect(book.reservations, 0);
      expect(book.persistedBytes, 0);
      final retry = coordinator.probe(0, 'node');
      expect(
        retry,
        isNotNull,
        reason:
            'The same live source remains eligible within the original retry budget',
      );
      expect(book.repeatReservedBytes, chunk);
    },
  );

  test(
    'HTTP completion after ledger expiry does not retire its live source',
    () async {
      var now = 0;
      await setup(
        4,
        paused: true,
        readClock: () => now,
        requestTimeout: const Duration(milliseconds: 100),
      );
      final body = Completer<Uint8List>();
      final source = P8PHttpPieceSource(writer, (_, token) => body.future);
      coordinator.add(source, diagnosticAlias: 'https');
      final request = coordinator.probe(0, 'https')!;
      expect(request.progressUnitBytes, 0);
      final cancelled = expectLater(
        request.verified,
        throwsA(isA<StateError>()),
      );
      now = 110000;
      book.expire();
      body.complete(piece(0));
      await cancelled;
      await request.stopped;
      await Future<void>.delayed(Duration.zero);
      expect(source.closed, false);
      expect(coordinator.metrics['source_https_failures'], 0);
      expect(coordinator.metrics['source_https_cancelled'], 1);
      expect(book.reservations, 0);
      expect(book.persistedBytes, 0);
      expect(coordinator.probe(0, 'https'), isNotNull);
      expect(book.repeatReservedBytes, chunk);
    },
  );

  test(
    'ordinary source errors cannot claim cancellation by copying its text',
    () async {
      await setup(4, paused: true);
      final source = P8PHttpPieceSource(
        writer,
        (_, token) async => throw StateError('p8p_request_cancelled'),
      );
      coordinator.add(source, diagnosticAlias: 'https');
      final request = coordinator.probe(0, 'https')!;
      await expectLater(request.verified, throwsA(isA<StateError>()));
      await request.stopped;
      await Future<void>.delayed(Duration.zero);
      expect(source.closed, true);
      expect(coordinator.metrics['source_https_failures'], 1);
      expect(coordinator.probe(0, 'https'), isNull);
    },
  );

  test(
    'failed source admission waits for physical close and retains metrics',
    () async {
      await setup(4, paused: true);
      final gate = Completer<void>();
      final failed = _RetirementSource(writer, gate);
      expect(coordinator.add(failed, diagnosticAlias: 'peer1'), true);
      for (final id in ['second', 'seed', 'https']) {
        expect(
          coordinator.add(
            P8PHttpPieceSource(writer, (_, token) async => piece(0), id: id),
          ),
          true,
        );
      }
      final request = coordinator.probe(0, failed.id)!;
      await expectLater(request.verified, throwsStateError);
      await request.stopped;
      var retired = false;
      final closing = coordinator
          .retireFailedSource(failed.id)
          .then((value) => retired = value);
      await Future<void>.delayed(Duration.zero);
      expect(failed.closed, true);
      expect(
        retired,
        false,
        reason: 'A closed flag does not prove physical close completion',
      );
      expect(
        coordinator.add(
          P8PHttpPieceSource(
            writer,
            (_, token) async => piece(0),
            id: 'replacement',
          ),
        ),
        false,
      );
      gate.complete();
      expect(await closing, true);
      expect(
        coordinator.add(
          P8PHttpPieceSource(
            writer,
            (_, token) async => piece(0),
            id: 'replacement',
          ),
          diagnosticAlias: 'peer3',
        ),
        true,
      );
      expect(coordinator.metrics['source_peer1_failures'], 1);
      expect(coordinator.metrics['source_peer1_verified_bytes'], 0);
      expect(
        coordinator.add(
          P8PHttpPieceSource(
            writer,
            (_, token) async => piece(0),
            id: failed.id,
          ),
        ),
        false,
      );
    },
  );

  test('healthy sources cannot be retired for replacement', () async {
    await setup(4, paused: true);
    final source = P8PHttpPieceSource(
      writer,
      (_, token) async => piece(0),
      id: 'healthy',
    );
    coordinator.add(source);
    expect(await coordinator.retireFailedSource(source.id), false);
    expect(source.closed, false);
  });

  test(
    'standby rejection cannot retire a source with a verified piece',
    () async {
      await setup(4, paused: true);
      final source = P8PHttpPieceSource(
        writer,
        (_, token) async => piece(0),
        id: 'proven',
      );
      coordinator.add(source);
      expect(coordinator.hasVerifiedSource(source.id), false);
      final request = coordinator.probe(0, source.id)!;
      await request.verified;
      await request.stopped;
      expect(coordinator.hasVerifiedSource(source.id), true);
      coordinator.rejectUnprovenSource(source.id);
      expect(source.closed, false);
      expect(await coordinator.retireFailedSource(source.id), false);
      expect(coordinator.hasVerifiedSource(source.id), true);
    },
  );

  test(
    'standby rejection retains request ownership until physical stop',
    () async {
      await setup(4, paused: true);
      final stopped = Completer<void>();
      final source = P8PHttpPieceSource(writer, (_, token) async {
        await stopped.future;
        // Return late bytes so the adapter itself must reject the cancelled
        // request after the reader physically exits.
        return piece(0);
      }, id: 'unproven');
      coordinator.add(source);
      final request = coordinator.probe(0, source.id)!;
      final verification = expectLater(
        request.verified,
        throwsA(isA<P8PLeaseCancelled>()),
      );
      coordinator.rejectUnprovenSource(source.id);
      expect(coordinator.hasVerifiedSource(source.id), false);
      expect(book.reservations, 1);
      final retired = coordinator.retireFailedSource(source.id);
      expect(book.reservations, 1);
      stopped.complete();
      await verification;
      await request.stopped;
      expect(await retired, true);
      expect(book.reservations, 0);
      expect(book.phase(0), P8PPiecePhase.missing);
    },
  );

  test('retired sources keep a six-record lifetime admission bound', () async {
    await setup(4, paused: true);
    for (var index = 0; index < 6; index++) {
      final source = P8PHttpPieceSource(
        writer,
        (_, token) async => piece(0),
        id: 'source-$index',
      );
      expect(coordinator.add(source), true);
      await source.close();
      expect(await coordinator.retireFailedSource(source.id), true);
    }
    expect(
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (_, token) async => piece(0),
          id: 'extra-source',
        ),
      ),
      false,
    );
  });

  test(
    'task close during failed source retirement cannot reopen admission',
    () async {
      await setup(4, paused: true);
      final gate = Completer<void>();
      final source = _RetirementSource(writer, gate);
      coordinator.add(source);
      final request = coordinator.probe(0, source.id)!;
      await expectLater(request.verified, throwsStateError);
      await request.stopped;
      final retirement = coordinator.retireFailedSource(source.id);
      final closing = coordinator.close();
      gate.complete();
      expect(await retirement, false);
      await closing;
      expect(
        coordinator.add(
          P8PHttpPieceSource(
            writer,
            (_, token) async => piece(0),
            id: 'replacement',
          ),
        ),
        false,
      );
    },
  );

  test('failed source close cannot release an admission slot', () async {
    await setup(4, paused: true);
    final gate = Completer<void>()..complete();
    final source = _RetirementSource(writer, gate, failClose: true);
    coordinator.add(source);
    final request = coordinator.probe(0, source.id)!;
    await expectLater(request.verified, throwsStateError);
    await request.stopped;
    expect(await coordinator.retireFailedSource(source.id), false);
    for (final id in ['second', 'seed', 'https']) {
      expect(
        coordinator.add(
          P8PHttpPieceSource(writer, (_, token) async => piece(0), id: id),
        ),
        true,
      );
    }
    expect(
      coordinator.add(
        P8PHttpPieceSource(
          writer,
          (_, token) async => piece(0),
          id: 'replacement',
        ),
      ),
      false,
    );
    await expectLater(coordinator.close(), throwsStateError);
    // The failure remains part of final cleanup. The tearDown must observe it.
    coordinator = P8PCoordinator(
      writer,
      clockMicros: () => clock.elapsedMicroseconds,
    );
  });

  test('paused proof cannot write until HTTPS has yielded ownership', () async {
    await setup(3);
    await writer.close();
    book = P8PLeaseBook(
      contentKey: 'paused',
      fileSha256: manifest.sha256,
      generation: 2,
      fileBytes: payload.length,
      pieceBytes: chunk,
      clockMicros: () => clock.elapsedMicroseconds,
    );
    writer = await P8POrderedWriter.open(book, store, paused: true);
    coordinator = P8PCoordinator(
      writer,
      clockMicros: () => clock.elapsedMicroseconds,
    );
    final lease = book.request(0, 'node', timeout: const Duration(seconds: 1))!;
    writer.submit(lease, piece(0));
    await writer.idle;
    expect(store.file.existsSync(), false);
    expect(book.phase(0), P8PPiecePhase.ready);
    writer.resume();
    await writer.idle;
    expect(await store.file.length(), chunk);
  });
}

class _SelectiveHttpSource extends P8PHttpPieceSource {
  _SelectiveHttpSource(
    super.writer,
    super.read,
    this.available, {
    super.id = 'https',
  });
  final bool Function(int) available;
  @override
  bool canServe(int index) => available(index) && super.canServe(index);
}

class _RetirementSource extends P8PHttpPieceSource {
  _RetirementSource(
    P8POrderedWriter writer,
    this.gate, {
    this.failClose = false,
  }) : super(
         writer,
         (_, token) async => throw StateError('fixture body fault'),
         id: 'failed-node',
       );
  final Completer<void> gate;
  final bool failClose;
  Future<void>? _retiring;
  @override
  Future<void> close() => _retiring ??= () async {
    await super.close();
    await gate.future;
    if (failClose) throw StateError('fixture close fault');
  }();
}

class _MeteredSource extends P8PHttpPieceSource {
  _MeteredSource(super.writer, super.read, this.received) : super(id: 'moving');
  final int Function() received;
  @override
  P8PSourceRequest start(P8PLease lease) =>
      _MeteredRequest(super.start(lease), received);
}

class _PrefixSource extends P8PHttpPieceSource {
  _PrefixSource(super.writer, super.read) : super(id: 'ready-provider');
  @override
  bool canServe(int index) => index < 2 && super.canServe(index);
}

class _PartialQueueSource extends P8PHttpPieceSource {
  _PartialQueueSource(super.writer, super.read, this.received)
    : super(id: 'fast');
  final Map<int, int> received;
  @override
  bool canServe(int index) => index != 2 && super.canServe(index);
  @override
  P8PSourceRequest start(P8PLease lease) =>
      _MeteredRequest(super.start(lease), () => received[lease.index] ?? 0);
}

class _MeteredRequest extends P8PSourceRequest {
  _MeteredRequest(P8PSourceRequest request, this.read)
    : super(request.lease, request.verified, request.stopped, request.cancel);
  final int Function() read;
  @override
  int get receivedBytes => read();
}

class _TailMeteredSource extends P8PHttpPieceSource {
  _TailMeteredSource(super.writer, super.read, this.received, this.unit)
    : super(id: 'tail');
  final int Function() received;
  final int unit;
  @override
  P8PSourceRequest start(P8PLease lease) =>
      _TailMeteredRequest(super.start(lease), received, unit);
}

class _TailMeteredRequest extends _MeteredRequest {
  _TailMeteredRequest(super.request, super.read, this.unit);
  final int unit;
  @override
  int get progressUnitBytes => unit;
}
