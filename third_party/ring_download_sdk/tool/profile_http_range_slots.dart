// Controlled loopback experiment, not a production speed test. No release URL,
// credentials, device identity, RTC connection or production record is used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_piece_store.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_protocol.dart';
import 'package:ring_download_sdk/src/p8p/coordinator.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';
import 'package:ring_download_sdk/src/p8p/ordered_writer.dart';
import 'package:ring_download_sdk/src/p8p/sources.dart';

const _chunk = AppUpgradeP2PManifest.chunkSize;

// Experimental source cap only. Production keeps its original two HTTP slots;
// overriding this getter does not change the global four-slot lease book.
class _Slots extends P8PHttpPieceSource {
  _Slots(super.writer, super.read, {this.slots = 2});
  final int slots;
  @override
  int get capacity => slots;
}

Future<Map<String, Object?>> _trial(
  Uint8List payload,
  AppUpgradeP2PManifest manifest, {
  required int slots,
  required int headerWaitMs,
  required int sharedBodyMsPerMiB,
}) async {
  final directory = await Directory.systemTemp.createTemp('p8p-http-slots-');
  final file = File('${directory.path}/payload.part');
  final store = AppUpgradeP2PPieceStore(file, manifest, bufferedWrites: true);
  final clock = Stopwatch();
  final book = P8PLeaseBook(
    contentKey: 'loopback/shared-link/${manifest.sha256}',
    fileSha256: manifest.sha256,
    generation: 1,
    fileBytes: payload.length,
    pieceBytes: _chunk,
    clockMicros: () => clock.elapsedMicroseconds,
  );
  final writer = await P8POrderedWriter.open(book, store);
  final coordinator = P8PCoordinator(
    writer,
    clockMicros: () => clock.elapsedMicroseconds,
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final client = HttpClient()
    ..maxConnectionsPerHost = 4
    ..connectionTimeout = const Duration(seconds: 2);
  var active = 0, peakActive = 0, requests = 0, servedBytes = 0;
  Future<void> bodyTail = Future<void>.value();
  final handlers = <Future<void>>[];
  final listener = server.listen((request) {
    final job = () async {
      active++;
      peakActive = max(peakActive, active);
      requests++;
      try {
        final match = RegExp(
          r'^bytes=(\d+)-(\d+)$',
        ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
        if (request.uri.path != '/fixture' || match == null) {
          throw StateError('Unexpected loopback request');
        }
        final start = int.parse(match[1]!), end = int.parse(match[2]!);
        if (start < 0 || end < start || end >= payload.length) {
          throw StateError('Invalid loopback range');
        }
        await Future<void>.delayed(Duration(milliseconds: headerWaitMs));
        // Every request shares ONE server body-service queue. Four clients do
        // not manufacture four independent copies of the modeled link rate.
        final body = bodyTail.then((_) async {
          final size = end - start + 1;
          await Future<void>.delayed(
            Duration(microseconds: sharedBodyMsPerMiB * 1000 * size ~/ _chunk),
          );
          request.response
            ..statusCode = HttpStatus.partialContent
            ..contentLength = size
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-$end/${payload.length}',
            )
            ..add(Uint8List.sublistView(payload, start, end + 1));
          await request.response.close();
          servedBytes += size;
        });
        bodyTail = body;
        await body;
      } finally {
        active--;
      }
    }();
    handlers.add(job);
    unawaited(job.then<void>((_) {}, onError: (Object _) {}));
  });
  final uri = Uri.parse('http://127.0.0.1:${server.port}/fixture');
  try {
    coordinator.add(
      // Vary only the experimental source's cap; the coordinator, writer and
      // global four-slot ledger are identical in both experiment arms.
      _Slots(writer, (index, token) async {
        final start = index * _chunk,
            end = start + manifest.pieceSize(index) - 1;
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 2));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        var finished = false;
        unawaited(
          token.whenCancel.then((error) {
            if (!finished) request.abort(error);
          }),
        );
        try {
          final response = await request.close().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              request.abort();
              throw TimeoutException('Loopback headers stalled');
            },
          );
          if (response.statusCode != HttpStatus.partialContent ||
              response.contentLength != end - start + 1 ||
              response.headers.value(HttpHeaders.contentRangeHeader) !=
                  'bytes $start-$end/${payload.length}') {
            throw StateError('Loopback response validation failed');
          }
          final bytes = BytesBuilder(copy: false);
          await for (final part in response.timeout(
            const Duration(seconds: 5),
          )) {
            if (token.isCancelled) throw token.cancelError!;
            bytes.add(part);
          }
          return bytes.takeBytes();
        } finally {
          finished = true;
        }
      }, slots: slots),
      diagnosticAlias: 'https',
    );
    clock.start();
    final complete = await coordinator.run(active: () => true);
    clock.stop();
    if (!complete || !await store.completeAndVerified()) {
      throw StateError('Loopback output incomplete or corrupt');
    }
    await Future.wait(handlers);
    if (servedBytes != payload.length ||
        requests != manifest.pieceHashes.length ||
        book.peakReservations > 4 ||
        book.peakReservedBytes > 4 * _chunk ||
        book.repeatReservedBytes != 0 ||
        active != 0) {
      throw StateError('Loopback ownership or byte accounting failed');
    }
    return {
      'slots': slots,
      'elapsed_us': clock.elapsedMicroseconds,
      'requests': requests,
      'served_bytes': servedBytes,
      'peak_HTTP_requests': peakActive,
      'peak_reservations': book.peakReservations,
      'peak_reserved_bytes': book.peakReservedBytes,
      'repeat_reserved_bytes': book.repeatReservedBytes,
      'full_sha_verified': true,
      'metrics': coordinator.metrics,
      'store_metrics': store.metrics,
    };
  } finally {
    await coordinator.close();
    client.close(force: true);
    await server.close(force: true);
    await listener.cancel();
    await store.close();
    if (await file.exists()) await file.delete();
    // Only this fixture's single output file is removed; no recursive delete.
    await directory.delete();
  }
}

Future<Map<String, Object?>> _coldAdmission(
  Uint8List payload,
  AppUpgradeP2PManifest manifest,
  int slots,
) async {
  final directory = await Directory.systemTemp.createTemp('p8p-http-cold-');
  final file = File('${directory.path}/payload.part');
  final store = AppUpgradeP2PPieceStore(file, manifest, bufferedWrites: true);
  final clock = Stopwatch()..start();
  final book = P8PLeaseBook(
    contentKey: 'cold-source/${manifest.sha256}',
    fileSha256: manifest.sha256,
    generation: 1,
    fileBytes: payload.length,
    pieceBytes: _chunk,
    clockMicros: () => clock.elapsedMicroseconds,
    repeatBudgetBytes: 2 * _chunk,
  );
  final writer = await P8POrderedWriter.open(book, store, paused: true);
  final coordinator = P8PCoordinator(
    writer,
    clockMicros: () => clock.elapsedMicroseconds,
    requestTimeout: const Duration(seconds: 3),
    hedgeAfter: const Duration(seconds: 2),
  );
  final full = Completer<void>(), late = Completer<void>();
  var active = 0;
  Future<bool>? download;
  try {
    coordinator.add(
      _Slots(writer, (index, token) async {
        if (index == 0) return Uint8List.sublistView(payload, 0, _chunk);
        if (++active == slots && !full.isCompleted) full.complete();
        try {
          await token.whenCancel;
          throw token.cancelError!;
        } finally {
          active--;
        }
      }, slots: slots),
    );
    final warm = coordinator.probe(0, 'https')!;
    await warm.verified;
    await warm.stopped;
    download = coordinator.run(active: () => true);
    await full.future.timeout(const Duration(seconds: 2));
    // Scheduler-only stand-in for a newly available RTC source. No assertion
    // about native ICE, UDP or NAT is made by this admission experiment.
    coordinator.add(
      P8PHttpPieceSource(writer, (index, _) async {
        if (!late.isCompleted) late.complete();
        return Uint8List.sublistView(
          payload,
          index * _chunk,
          min(payload.length, (index + 1) * _chunk),
        );
      }, id: 'late-peer'),
    );
    final admitted = await Future.any([
      late.future.then((_) => true),
      Future<bool>.delayed(const Duration(milliseconds: 300), () => false),
    ]);
    return {
      'HTTP_slots': slots,
      'late_source_admitted_within_300ms': admitted,
      'HTTP_request_deadline_ms': 3000,
      'peak_reservations': book.peakReservations,
      'scope': 'Scheduler-only late-source admission while HTTPS bodies stall',
    };
  } finally {
    await coordinator.close();
    await download;
    await store.close();
    if (active != 0 || book.reservations != 0) {
      throw StateError('Cold admission fixture leaked owners');
    }
    if (await file.exists()) await file.delete();
    await directory.delete();
  }
}

Future<void> main(List<String> args) async {
  final payload = Uint8List.fromList(
    List.generate(12 * _chunk + 79, (index) => index % 251),
  );
  final manifest = AppUpgradeP2PManifest(
    fileSize: payload.length,
    sha256: sha256.convert(payload).toString(),
    pieceHashes: [
      for (var start = 0; start < payload.length; start += _chunk)
        sha256
            .convert(
              Uint8List.sublistView(
                payload,
                start,
                min(payload.length, start + _chunk),
              ),
            )
            .toString(),
    ],
    stunUrls: const ['stun:loopback.invalid:3479'],
    apiBase: 'https://loopback.invalid/unused',
    serverSeedUrl: 'https://loopback.invalid/unused',
  );
  final results = <Map<String, Object?>>[];
  if (args.contains('--cold-admission-only')) {
    stdout.writeln(
      jsonEncode({
        'cold_admission': [
          await _coldAdmission(payload, manifest, 2),
          await _coldAdmission(payload, manifest, 4),
        ],
      }),
    );
    return;
  }
  for (final profile in [
    (name: 'per_request_wait', headerMs: 180, bodyMs: 15),
    (name: 'shared_link_bound', headerMs: 15, bodyMs: 180),
  ]) {
    final rows = <Map<String, Object?>>[];
    for (var round = 0; round < 3; round++) {
      // Alternate arm order to reduce warm-up/order bias on the local host.
      for (final slots in round.isEven ? [2, 4] : [4, 2]) {
        rows.add({
          'round': round + 1,
          ...await _trial(
            payload,
            manifest,
            slots: slots,
            headerWaitMs: profile.headerMs,
            sharedBodyMsPerMiB: profile.bodyMs,
          ),
        });
      }
    }
    int median(int slots) {
      final times =
          rows
              .where((r) => r['slots'] == slots)
              .map((r) => r['elapsed_us'] as int)
              .toList()
            ..sort();
      return times[times.length ~/ 2];
    }

    results.add({
      'profile': profile.name,
      'header_wait_ms': profile.headerMs,
      'shared_body_ms_per_MiB': profile.bodyMs,
      'median_2_slots_us': median(2),
      'median_4_slots_us': median(4),
      'median_time_reduction': 1 - median(4) / median(2),
      'trials': rows,
    });
  }
  stdout.writeln(
    jsonEncode({
      'scope':
          'Controlled HTTP/1 loopback, shared body service, real SDK ledger/writer/coordinator; not mobile or internet speed',
      'production_mutated': false,
      'runtime_capacity_changed': false,
      'payload_bytes': payload.length,
      'payload_sha256': manifest.sha256,
      'profiles': results,
    }),
  );
}
