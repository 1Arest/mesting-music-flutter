import 'dart:math';
import 'engine.dart';
import 'models.dart';
import 'transfer_statistics.dart';

class _Point {
  _Point(this.at, this.sample, this.file);
  final Duration at;
  final RingTransferSample sample;
  final int file;
}

/// Bounded rolling observation; the caller owns clock/timer and task lifetime.
class RingTransferMeter {
  final _points = <_Point>[
    _Point(Duration.zero, const RingTransferSample(), 0),
  ];
  int? _firstFileProgress;
  RingTransferStatistics read(
    Duration elapsed,
    RingDownloadProgress progress,
    RingTransferSample sample, {
    bool cancelling = false,
  }) {
    if (progress.receivedBytes > 0) {
      _firstFileProgress ??= progress.receivedBytes;
    }
    final aliases = <String>{};
    final safeNodes = [
      for (final node in sample.nodes.take(32))
        if (RegExp(r'^node([1-9]|[12][0-9]|3[0-2])$').hasMatch(node.alias) &&
            aliases.add(node.alias))
          node,
    ];
    sample = RingTransferSample(
      available: sample.available && safeNodes.length == sample.nodes.length,
      httpsBytes: max(0, sample.httpsBytes),
      peerBytes: max(0, sample.peerBytes),
      seedBytes: max(0, sample.seedBytes),
      nodes: List.unmodifiable(safeNodes),
    );
    final cutoff = elapsed - const Duration(seconds: 2);
    while (_points.length > 1 && _points[1].at <= cutoff) {
      _points.removeAt(0);
    }
    final before = _points.first;
    final seconds = (elapsed - before.at).inMicroseconds / 1000000;
    final moving =
        progress.state == RingDownloadState.transferring && !cancelling;
    double rate(int current, int previous) =>
        moving && seconds >= .1 ? max(0, current - previous) / seconds : 0;
    final http = rate(sample.httpsBytes, before.sample.httpsBytes);
    final peer = rate(sample.peerBytes, before.sample.peerBytes);
    final seed = rate(sample.seedBytes, before.sample.seedBytes);
    final priorNodes = {
      for (final node in before.sample.nodes) node.alias: node,
    };
    final nodes = [
      for (final node in sample.nodes)
        RingNodeTransferStatistics(
          alias: node.alias,
          source: node.source,
          state:
              !moving &&
                  progress.state != RingDownloadState.queued &&
                  progress.state != RingDownloadState.transferring
              ? RingNodeState.closed
              : node.state == RingNodeState.connected &&
                    rate(
                          node.receivedBytes,
                          priorNodes[node.alias]?.receivedBytes ?? 0,
                        ) >
                        0
              ? RingNodeState.receiving
              : node.state,
          receivedBytes: node.receivedBytes,
          verifiedBytes: node.verifiedBytes,
          bytesPerSecond: node.state == RingNodeState.closed
              ? 0
              : rate(
                  node.receivedBytes,
                  priorNodes[node.alias]?.receivedBytes ?? 0,
                ),
        ),
    ];
    final fileRate = rate(
      progress.receivedBytes,
      max(before.file, _firstFileProgress ?? 0),
    );
    final remaining = progress.totalBytes - progress.receivedBytes;
    final etaSeconds = fileRate > 0 ? remaining / fileRate : 0.0;
    final eta =
        moving &&
            elapsed.inMilliseconds >= 500 &&
            remaining > 0 &&
            etaSeconds.isFinite &&
            etaSeconds > 0 &&
            etaSeconds <= 604800
        ? Duration(milliseconds: (etaSeconds * 1000).ceil())
        : null;
    // Publishing at most twice/second keeps the window bounded independently of
    // chunk size, peer events and application listener count.
    if (_points.last.at == elapsed) {
      _points.removeLast();
    }
    _points.add(_Point(elapsed, sample, progress.receivedBytes));
    if (_points.length > 16) _points.removeAt(0);
    return RingTransferStatistics(
      state: progress.state,
      elapsed: elapsed,
      cancelling: cancelling,
      available: sample.available,
      receivedBytes: progress.receivedBytes,
      totalBytes: progress.totalBytes,
      httpsReceivedBytes: sample.httpsBytes,
      peerReceivedBytes: sample.peerBytes,
      seedReceivedBytes: sample.seedBytes,
      peerVerifiedBytes: nodes
          .where((n) => n.source == RingNodeSource.peer)
          .fold(0, (n, v) => n + v.verifiedBytes),
      seedVerifiedBytes: nodes
          .where((n) => n.source == RingNodeSource.seed)
          .fold(0, (n, v) => n + v.verifiedBytes),
      bytesPerSecond: http + peer + seed,
      httpsBytesPerSecond: http,
      peerBytesPerSecond: peer,
      seedBytesPerSecond: seed,
      estimatedRemaining: eta,
      nodes: nodes,
    );
  }
}
