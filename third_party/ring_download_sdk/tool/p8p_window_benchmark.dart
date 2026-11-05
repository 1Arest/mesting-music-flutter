// Deterministic queue model using the real window controller. This is a
// scheduling experiment, not a network or whole-APK speed measurement.
import 'dart:convert';
import 'dart:io';
import 'package:ring_download_sdk/src/p8p/window.dart';

Map<String, Object> simulate({
  required String name,
  required int roundTripUs,
  required int pieceUs,
  required int consumerUs,
  required bool adaptive,
}) {
  final policy = adaptive ? P8PWindowController() : null;
  const count = 125;
  final arrivals = <int, int>{};
  var now = 0, serverReady = 0, requested = 0, lastWait = 0;
  var peak = 0, bufferedPieceUs = 0, previousSample = 0;
  final windows = <int>[];
  for (var index = 0; index < count; index++) {
    final ready = arrivals.values.where((finish) => finish <= now).length;
    if (index > 0) {
      policy?.observe(
        waitMicros: lastWait,
        consumeMicros: consumerUs,
        readyPieces: ready,
      );
    }
    final window = policy?.window ?? 4;
    windows.add(window);
    while (arrivals.length < window && requested < count) {
      final arrivedAtServer = now + roundTripUs ~/ 2;
      final start = serverReady > arrivedAtServer
          ? serverReady
          : arrivedAtServer;
      serverReady = start + pieceUs;
      arrivals[requested++] = serverReady + roundTripUs ~/ 2;
    }
    if (arrivals.length > peak) peak = arrivals.length;
    final finished = arrivals.remove(index)!;
    lastWait = finished > now ? finished - now : 0;
    now += lastWait;
    bufferedPieceUs += arrivals.length * (now - previousSample);
    bufferedPieceUs += arrivals.length * consumerUs;
    now += consumerUs;
    previousSample = now;
  }
  return {
    'scenario': name,
    'policy': adaptive ? 'adaptive' : 'fixed_four',
    'model': 'serialized_sender_with_RTT_and_consumer_delay',
    'pieces': count,
    'elapsed_us': now,
    'peak_outstanding_pieces': peak,
    'first_window': windows.first,
    'last_window': windows.last,
    'min_window': windows.reduce((a, b) => a < b ? a : b),
    'max_window': windows.reduce((a, b) => a > b ? a : b),
    'queue_piece_us': bufferedPieceUs,
  };
}

void main(List<String> args) {
  final results = <Map<String, Object>>[];
  for (final scenario in [
    (name: 'fast_link_fast_consumer', rtt: 2000, piece: 2000, consume: 500),
    (name: 'fast_link_slow_consumer', rtt: 2000, piece: 2000, consume: 50000),
    (name: 'high_RTT_fast_link', rtt: 100000, piece: 5000, consume: 1000),
    (name: 'slow_link_fast_consumer', rtt: 20000, piece: 100000, consume: 1000),
  ]) {
    for (final adaptive in [false, true]) {
      results.add(
        simulate(
          name: scenario.name,
          roundTripUs: scenario.rtt,
          pieceUs: scenario.piece,
          consumerUs: scenario.consume,
          adaptive: adaptive,
        ),
      );
    }
  }
  final result = const JsonEncoder.withIndent('  ').convert({
    'scope':
        'Deterministic model, no actual network/RTC/device performance claim',
    'results': results,
  });
  if (args.length == 1) File(args.single).writeAsStringSync(result);
  stdout.writeln(result);
}
