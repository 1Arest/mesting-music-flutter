/// Restoring a login can outlive a second shortcut/notification tap. Keep one
/// preparation in flight, re-read the durable request afterwards, and navigate
/// only the latest request. Deferred login and disposed hosts retain the intent.
class MusicEntryDispatcher {
  MusicEntryDispatcher({
    required this.peek,
    required this.prepare,
    required this.navigate,
    required this.acknowledge,
    required this.active,
  });
  final Future<Map<String, dynamic>?> Function() peek;
  final Future<String?> Function(Map<String, dynamic>) prepare;
  final void Function(String route) navigate;
  final Future<void> Function(String id) acknowledge;
  final bool Function() active;
  bool _running = false, _again = false;

  Future<void> dispatch() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final entry = await peek();
        if (entry == null || !active()) break;
        final id = entry['id'];
        if (id is! String || id.isEmpty) break;
        final route = await prepare(entry);
        if (route == null || !active()) break;
        final latest = await peek();
        if (latest?['id'] != id) {
          _again = true;
          continue;
        }
        if (!active()) break;
        navigate(route);
        await acknowledge(id);
      } while (_again && active());
    } finally {
      _running = false;
    }
  }
}
