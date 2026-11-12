/// In-process receive observation. No protocol IDs or addresses enter samples.
enum AppUpgradeObservedSource { peer, seed }

class AppUpgradeObservedNode {
  AppUpgradeObservedNode(
    this.alias,
    this.source,
    this.isConnected,
    this.isClosed,
  );
  final String alias;
  final AppUpgradeObservedSource source;
  final bool Function() isConnected, isClosed;
  int receivedBytes = 0, verifiedBytes = 0;
}

class AppUpgradeTransferObservation {
  final nodes = <AppUpgradeObservedNode>[];
  final _pieces = <int, (AppUpgradeObservedNode, int)>{};
  int peerReceivedBytes = 0, seedReceivedBytes = 0;
  bool complete = true;

  AppUpgradeObservedNode? addNode(
    AppUpgradeObservedSource source,
    bool Function() connected,
    bool Function() closed,
  ) {
    if (nodes.length >= 32) {
      complete = false;
      return null;
    }
    final node = AppUpgradeObservedNode(
      'node${nodes.length + 1}',
      source,
      connected,
      closed,
    );
    nodes.add(node);
    return node;
  }

  void receive(
    AppUpgradeObservedNode? node,
    AppUpgradeObservedSource source,
    int bytes,
  ) {
    if (bytes <= 0) return;
    if (source == AppUpgradeObservedSource.seed) {
      seedReceivedBytes += bytes;
    } else {
      peerReceivedBytes += bytes;
    }
    if (node != null) node.receivedBytes += bytes;
  }

  /// The writer calls only after SHA verification and a successful piece write.
  /// Replaced/repeated indices cannot inflate useful contribution.
  void persisted(int index, int bytes, AppUpgradeObservedNode? node) {
    final previous = _pieces.remove(index);
    if (previous != null) previous.$1.verifiedBytes -= previous.$2;
    if (node == null || bytes <= 0) return; // HTTPS replaced this index.
    _pieces[index] = (node, bytes);
    node.verifiedBytes += bytes;
  }

  /// A fresh HTTP 200 truncates old coverage, but not actual network traffic.
  void clearCoverage() {
    _pieces.clear();
    for (final node in nodes) {
      node.verifiedBytes = 0;
    }
  }
}
