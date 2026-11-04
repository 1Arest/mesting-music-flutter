/// The official relation query identifies both participants, in friend/self
/// order. A partial identity must never degrade to a one-user statistics query.
List<int>? togetherRelationUserIds(String accountId, String friendId) {
  final account = int.tryParse(accountId), friend = int.tryParse(friendId);
  if (account == null ||
      friend == null ||
      account <= 0 ||
      friend <= 0 ||
      account == friend) {
    return null;
  }
  return [friend, account];
}

/// A server-confirmed cumulative snapshot plus only its subsequent elapsed
/// time. Playback and widget timers never own the accumulated history.
///
/// The controller must clear this clock whenever account, friend or room
/// changes. On process recreation it starts unknown and re-queries the server;
/// persisting a local estimate would not recover official background history.
class TogetherCumulativeClock {
  TogetherCumulativeClock({Stopwatch? clock}) : _clock = clock ?? Stopwatch();
  final Stopwatch _clock;
  Duration? _snapshot;
  bool _stale = false;

  Duration? get duration =>
      _snapshot == null ? null : _snapshot! + _clock.elapsed;
  bool get isStale => _stale;

  void replace(Duration snapshot) {
    // The official client preserves a prior nonzero value when an update in
    // the same room reports zero. Keep it visibly stale until a positive
    // snapshot confirms the relation again; new identities are cleared first.
    if (snapshot == Duration.zero && (_snapshot?.inMicroseconds ?? 0) > 0) {
      markStale();
      return;
    }
    _snapshot = snapshot;
    _stale = false;
    _clock
      ..reset()
      ..start();
  }

  void markStale() {
    _clock.stop();
    _stale = _snapshot != null;
  }

  void clear() {
    _snapshot = null;
    _stale = false;
    _clock
      ..stop()
      ..reset();
  }
}
