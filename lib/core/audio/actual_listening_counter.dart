/// Monotonic time is independent of the calendar, media position and speed.
abstract interface class ListeningClock {
  int get elapsedMicroseconds;
  DateTime get now;
}

class MonotonicListeningClock implements ListeningClock {
  final Stopwatch _watch = Stopwatch()..start();
  @override
  int get elapsedMicroseconds => _watch.elapsedMicroseconds;
  @override
  DateTime get now => DateTime.now();
}

/// Counts playing AND decoder-ready AND non-seeking intervals. Every state
/// edge settles the preceding interval before changing eligibility. One real
/// second at 2x is one heard second. Shared by local and official statistics.
class ActualListeningCounter {
  ActualListeningCounter(this.clock) : _last = clock.elapsedMicroseconds;
  final ListeningClock clock;
  int _last;
  int _heard = 0;
  double _mediaHeard = 0;
  bool _playing = false, _ready = false, _seeking = false;
  double _speed = 1;

  bool get audible =>
      _playing && _ready && !_seeking && _speed.isFinite && _speed > 0;

  void update({bool? playing, bool? ready, bool? seeking, double? speed}) {
    sample();
    _playing = playing ?? _playing;
    _ready = ready ?? _ready;
    _seeking = seeking ?? _seeking;
    _speed = speed ?? _speed;
  }

  int sample() {
    final current = clock.elapsedMicroseconds;
    final elapsed = current - _last;
    if (audible && elapsed > 0) {
      _heard += elapsed;
      _mediaHeard += elapsed * _speed;
    }
    _last = current;
    return _heard ~/ 1000;
  }

  /// Official play logs distinguish audible wall time from the corresponding
  /// speed-weighted media interval. Seeking still contributes to neither.
  int sampleMediaMilliseconds() {
    sample();
    return _mediaHeard ~/ 1000;
  }
}
