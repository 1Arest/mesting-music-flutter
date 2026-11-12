import 'dart:collection';
import 'models.dart';

/// State of a download-side logical connection, not proof of native disposal.
enum RingNodeState { connecting, connected, receiving, closed }

enum RingNodeSource { peer, seed }

class RingNodeTransferStatistics {
  const RingNodeTransferStatistics({
    required this.alias,
    required this.source,
    required this.state,
    required this.receivedBytes,
    required this.verifiedBytes,
    required this.bytesPerSecond,
  });

  /// Task-local label only. No node ID, IP, SDP, URL or account identity.
  final String alias;
  final RingNodeSource source;
  final RingNodeState state;

  /// Wire payload can include duplicates/failed pieces. Verified is SHA checked
  /// and persisted unique piece coverage in the current file, not wire traffic.
  final int receivedBytes, verifiedBytes;
  final double bytesPerSecond;
  Map<String, Object> toJson() => {
    'alias': alias,
    'source': source.name,
    'state': state.name,
    'receivedBytes': receivedBytes,
    'verifiedBytes': verifiedBytes,
    'bytesPerSecond': bytesPerSecond,
  };
}

class RingTransferStatistics {
  RingTransferStatistics({
    required this.state,
    required this.elapsed,
    required this.receivedBytes,
    required this.totalBytes,
    this.available = false,
    this.cancelling = false,
    this.httpsReceivedBytes = 0,
    this.peerReceivedBytes = 0,
    this.seedReceivedBytes = 0,
    this.peerVerifiedBytes = 0,
    this.seedVerifiedBytes = 0,
    this.bytesPerSecond = 0,
    this.httpsBytesPerSecond = 0,
    this.peerBytesPerSecond = 0,
    this.seedBytesPerSecond = 0,
    this.estimatedRemaining,
    List<RingNodeTransferStatistics> nodes = const [],
  }) : nodes = UnmodifiableListView(List<RingNodeTransferStatistics>.of(nodes));

  /// False means this engine cannot provide complete source/node counters.
  final bool available, cancelling;
  final RingDownloadState state;
  final Duration elapsed;

  /// File progress may include a resumed prefix; source traffic is this task only.
  final int receivedBytes, totalBytes;
  final int httpsReceivedBytes, peerReceivedBytes, seedReceivedBytes;
  final int peerVerifiedBytes, seedVerifiedBytes;

  /// Two-second rolling payload rate. Does not count an existing cached prefix.
  final double bytesPerSecond,
      httpsBytesPerSecond,
      peerBytesPerSecond,
      seedBytesPerSecond;

  /// Based on advancing file progress, unavailable during startup/stalls/hash.
  final Duration? estimatedRemaining;
  final List<RingNodeTransferStatistics> nodes;
  int get connectingNodes =>
      nodes.where((n) => n.state == RingNodeState.connecting).length;
  int get connectedNodes => nodes
      .where(
        (n) =>
            n.state == RingNodeState.connected ||
            n.state == RingNodeState.receiving,
      )
      .length;
  int get receivingNodes =>
      nodes.where((n) => n.state == RingNodeState.receiving).length;
  Map<String, Object?> toJson() => {
    'available': available,
    'state': state.name,
    'cancelling': cancelling,
    'elapsedMs': elapsed.inMilliseconds,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'httpsReceivedBytes': httpsReceivedBytes,
    'peerReceivedBytes': peerReceivedBytes,
    'seedReceivedBytes': seedReceivedBytes,
    'peerVerifiedBytes': peerVerifiedBytes,
    'seedVerifiedBytes': seedVerifiedBytes,
    'bytesPerSecond': bytesPerSecond,
    'httpsBytesPerSecond': httpsBytesPerSecond,
    'peerBytesPerSecond': peerBytesPerSecond,
    'seedBytesPerSecond': seedBytesPerSecond,
    'estimatedRemainingMs': estimatedRemaining?.inMilliseconds,
    'connectingNodes': connectingNodes,
    'connectedNodes': connectedNodes,
    'receivingNodes': receivingNodes,
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };
}
