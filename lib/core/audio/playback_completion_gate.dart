class PlaybackCompletionGate {
  bool _eligible = false;

  bool get isEligible => _eligible;

  void reset() {
    _eligible = false;
  }

  void onPlay(Duration position) {
    if (position <= const Duration(seconds: 1)) {
      _eligible = true;
    }
  }

  void onSeek({required Duration from, required Duration to}) {
    if (to <= const Duration(seconds: 1) ||
        to > from + const Duration(seconds: 1)) {
      _eligible = false;
    }
  }

  bool takeCompletion() {
    final completedInFull = _eligible;
    _eligible = false;
    return completedInFull;
  }
}
