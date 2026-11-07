import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_piece_store.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_protocol.dart';
import 'package:ring_download_sdk/src/p8p/coordinator.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';
import 'package:ring_download_sdk/src/p8p/ordered_writer.dart';
import 'package:ring_download_sdk/src/p8p/sources.dart';

/// Real loopback HTTP with one shared bandwidth shaper per origin. No TLS,
/// ICE, signaling, cellular or internet speed claim. Single-source fixed-four
/// and multi-source use the same verified writer and global four-piece budget.
class _Pipe {
  _Pipe(this.response, this.offset, this.end);
  final HttpResponse response;
  int offset;
  final int end;
  bool closed = false;
}

class _Origin {
  _Origin(this.payload);
  final Uint8List payload;
  final _queue = Queue<_Pipe>();
  late HttpServer server;
  Timer? _timer;
  int sent = 0, requests = 0;
  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/fixture');
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      final match = RegExp(
        r'^bytes=(\d+)-(\d+)$',
      ).firstMatch(request.headers.value('range') ?? '');
      if (match == null) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }
      final start = int.parse(match[1]!), end = int.parse(match[2]!);
      if (start < 0 || end < start || end >= payload.length) {
        request.response.statusCode = 416;
        await request.response.close();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      request.response.statusCode = 206;
      request.response.contentLength = end - start + 1;
      request.response.headers.set(
        'content-range',
        'bytes $start-$end/${payload.length}',
      );
      final pipe = _Pipe(request.response, start, end);
      unawaited(
        request.response.done.then<void>(
          (_) {
            pipe.closed = true;
          },
          onError: (Object _) {
            pipe.closed = true;
          },
        ),
      );
      _queue.add(pipe);
    });
    // Shared 32KiB/10ms per origin, regardless of request count.
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      while (_queue.isNotEmpty && _queue.first.closed) {
        _queue.removeFirst();
      }
      if (_queue.isEmpty) return;
      final pipe = _queue.removeFirst();
      final end = min(pipe.end + 1, pipe.offset + 32768);
      try {
        pipe.response.add(Uint8List.sublistView(payload, pipe.offset, end));
        sent += end - pipe.offset;
        pipe.offset = end;
        if (end > pipe.end) {
          unawaited(
            pipe.response.close().then<void>((_) {}, onError: (Object _) {}),
          );
        } else {
          _queue.add(pipe);
        }
      } catch (_) {
        pipe.closed = true;
      }
    });
  }

  Future<void> close() async {
    _timer?.cancel();
    await server.close(force: true);
  }
}

class _FixedFour extends P8PHttpPieceSource {
  _FixedFour(super.writer, super.read, {required super.id});
  @override
  int get capacity => 4;
}

Future<Map<String, Object?>> _run(
  String policy,
  int round,
  Directory root,
  AppUpgradeP2PManifest manifest,
  Uint8List payload,
) async {
  final a = _Origin(payload), b = _Origin(payload);
  await a.start();
  await b.start();
  final http = Dio();
  final watch = Stopwatch()..start();
  int? firstPersisted;
  final startRss = ProcessInfo.currentRss;
  var peakRss = startRss;
  final sample = Timer.periodic(const Duration(milliseconds: 20), (_) {
    peakRss = max(peakRss, ProcessInfo.currentRss);
  });
  final file = File('${root.path}/$policy-$round.part');
  final store = AppUpgradeP2PPieceStore(file, manifest, bufferedWrites: true);
  final book = P8PLeaseBook(
    contentKey: 'example/benchmark',
    fileSha256: manifest.sha256,
    generation: round + 1,
    fileBytes: payload.length,
    pieceBytes: AppUpgradeP2PManifest.chunkSize,
    clockMicros: () => watch.elapsedMicroseconds,
    repeatBudgetBytes: 2 * 1024 * 1024,
  );
  final writer = await P8POrderedWriter.open(
    book,
    store,
    onPersisted: (_) {
      firstPersisted ??= watch.elapsedMilliseconds;
    },
  );
  final coordinator = P8PCoordinator(
    writer,
    clockMicros: () => watch.elapsedMicroseconds,
    requestTimeout: const Duration(seconds: 8),
  );
  P8PRangeReader reader(_Origin origin) => (index, token) async {
    final start = index * AppUpgradeP2PManifest.chunkSize;
    final end = start + manifest.pieceSize(index) - 1;
    final response = await http.get<ResponseBody>(
      origin.uri.toString(),
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'range': 'bytes=$start-$end'},
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 206 ||
        response.headers.value('content-range') !=
            'bytes $start-$end/${payload.length}') {
      throw StateError('Benchmark range rejected');
    }
    final bytes = Uint8List(end - start + 1);
    var offset = 0;
    await for (final frame in response.data!.stream) {
      if (offset + frame.length > bytes.length) {
        throw StateError('Benchmark overflow');
      }
      bytes.setRange(offset, offset + frame.length, frame);
      offset += frame.length;
    }
    if (offset != bytes.length) throw StateError('Benchmark truncated');
    return bytes;
  };
  if (policy == 'fixed_four_single_origin') {
    coordinator.add(_FixedFour(writer, reader(a), id: 'origin-a'));
  } else {
    coordinator.add(P8PHttpPieceSource(writer, reader(a), id: 'origin-a'));
    coordinator.add(P8PHttpPieceSource(writer, reader(b), id: 'origin-b'));
  }
  try {
    final complete = await coordinator.run(active: () => true);
    final verified = complete && await store.completeAndVerified();
    return {
      'policy': policy,
      'round': round,
      'verified': verified,
      'bytes': payload.length,
      'elapsed_ms': watch.elapsedMilliseconds,
      'first_persisted_ms': firstPersisted,
      'body_bytes': a.sent + b.sent,
      'origin_a_bytes': a.sent,
      'origin_b_bytes': b.sent,
      'http_requests': a.requests + b.requests,
      'start_rss_bytes': startRss,
      'peak_process_rss_bytes': peakRss,
      'queue_metrics': coordinator.metrics,
    };
  } finally {
    sample.cancel();
    await coordinator.close();
    await store.close();
    http.close(force: true);
    await a.close();
    await b.close();
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Expected result.json output path');
  const chunk = AppUpgradeP2PManifest.chunkSize;
  final payload = Uint8List(12 * chunk + 137);
  for (var i = 0; i < payload.length; i++) {
    payload[i] = i % 251;
  }
  final manifest = AppUpgradeP2PManifest(
    fileSize: payload.length,
    sha256: sha256.convert(payload).toString(),
    pieceHashes: [
      for (var i = 0; i < payload.length; i += chunk)
        sha256
            .convert(
              Uint8List.sublistView(payload, i, min(i + chunk, payload.length)),
            )
            .toString(),
    ],
    stunUrls: const ['stun:example.test:3479'],
    apiBase: 'https://example.test/p2p',
    serverSeedUrl: 'https://example.test/p2p/seed',
  );
  final root = await Directory.systemTemp.createTemp('p8p-shaped-benchmark-');
  final rows = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'scope':
        'Controlled real loopback HTTP per-origin shaper; no TLS/ICE/signaling/cellular/internet acceptance',
    'baseline':
        'Same verified coordinator/writer with one fixed-four HTTP source; not old SDK network acceptance',
    'shape': {
      'bytes_per_tick_per_origin': 32768,
      'tick_ms': 10,
      'header_delay_ms': 20,
    },
    'memory_scope':
        'Process RSS includes runtime/HTTP fixture; reservation bytes are separate from heap/RSS',
    'runs': rows,
  };
  try {
    for (var round = 0; round < 3; round++) {
      for (final policy in ['fixed_four_single_origin', 'two_origins']) {
        final row = await _run(policy, round, root, manifest, payload);
        rows.add(row);
        await File(args[0]).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
        stdout.writeln(jsonEncode(row));
      }
    }
    if (rows.any((row) => row['verified'] != true)) {
      throw StateError('A benchmark run failed verification');
    }
  } finally {
    await root.delete(recursive: true);
  }
}
