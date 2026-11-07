import 'dart:async';

/// A read cursor acknowledges only history that reached a visible chat frame.
/// A later message timestamp always survives reconciliation with stale counts.
class NeteaseMessageReads {
  NeteaseMessageReads({Map<String, int> restored = const {}, this.persist})
    : _seen = {...restored};
  final Future<void> Function(Map<String, int>)? persist;
  final Map<String, int> _seen;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  bool includes(String peer, DateTime last) =>
      last.millisecondsSinceEpoch > 0 &&
      last.millisecondsSinceEpoch <= (_seen[peer] ?? 0);
  void displayed(String peer, DateTime through) {
    final time = through.millisecondsSinceEpoch;
    if (peer.isEmpty || time <= (_seen[peer] ?? 0)) return;
    _seen[peer] = time;
    _changes.add(null);
    final write = persist;
    if (write != null) {
      unawaited(write(Map.unmodifiable(_seen)).catchError((Object _) {}));
    }
  }

  void close() {
    unawaited(_changes.close());
  }
}
