import 'package:flutter/foundation.dart';

/// Owns the hand-off between finger preview and an asynchronous audio seek.
///
/// Engine ticks never move the thumb during a gesture. A completed seek keeps
/// its preview until the position stream acknowledges it; an older completion
/// cannot clear a newer drag or seek. Audio is requested only on release.
class PlaybackScrubController extends ChangeNotifier {
  double? get previewMilliseconds => _preview;
  double? _preview;
  Duration? _observed;
  Duration? _confirmed;
  Stopwatch? _confirmationClock;
  int _observations = 0, _submittedAtObservation = 0;
  int _revision = 0;
  bool _dragging = false, _completed = false, _disposed = false;

  void begin(double milliseconds) {
    _revision++;
    _dragging = true;
    _completed = false;
    _confirmed = null;
    _confirmationClock?.stop();
    _confirmationClock = null;
    _preview = milliseconds;
    notifyListeners();
  }

  void update(double milliseconds) {
    _preview = milliseconds;
    notifyListeners();
  }

  Future<void> commit(
    double milliseconds,
    Future<void> Function(Duration) seek, {
    Duration Function()? confirmedPosition,
  }) async {
    final revision = ++_revision;
    _dragging = false;
    _completed = false;
    _confirmed = null;
    _submittedAtObservation = _observations;
    _confirmationClock?.stop();
    _confirmationClock = null;
    _preview = milliseconds;
    notifyListeners();
    try {
      await seek(Duration(milliseconds: milliseconds.round()));
      if (_disposed || revision != _revision) return;
      // The engine can already have advanced while a slow seek completes.
      // Use its confirmed position, rather than a one-second guess around the
      // requested point. A cached nearby pre-seek tick is never an ack.
      _confirmed =
          confirmedPosition?.call() ??
          Duration(milliseconds: milliseconds.round());
      _confirmationClock = Stopwatch()..start();
      _completed = true;
      _releaseIfAcknowledged();
    } catch (_) {
      if (!_disposed && revision == _revision) reset();
      rethrow;
    }
  }

  void observe(Duration? position) {
    _observed = position;
    if (position != null) _observations++;
    _releaseIfAcknowledged();
  }

  void _releaseIfAcknowledged() {
    final position = _observed;
    final confirmed = _confirmed;
    final delta = position == null || confirmed == null
        ? null
        : position.inMilliseconds - confirmed.inMilliseconds;
    // Equal-position paused seeks may be deduplicated by the provider. They
    // need no visual hand-off. Other seeks require a post-submission sample.
    final alreadyAtTarget =
        position != null &&
        confirmed != null &&
        _preview != null &&
        (position.inMilliseconds - confirmed.inMilliseconds).abs() <= 1 &&
        (position.inMilliseconds - _preview!).abs() <= 1;
    if (!_dragging &&
        _completed &&
        delta != null &&
        _preview != null &&
        (_observations > _submittedAtObservation || alreadyAtTarget) &&
        delta >= -80 &&
        delta <= (_confirmationClock?.elapsedMilliseconds ?? 0) + 80) {
      _preview = null;
      _completed = false;
      _confirmed = null;
      _confirmationClock?.stop();
      _confirmationClock = null;
      notifyListeners();
    }
  }

  /// Track changes invalidate every outstanding completion, including A→B→A.
  void reset({bool notify = true}) {
    _revision++;
    _preview = null;
    _observed = null;
    _confirmed = null;
    _confirmationClock?.stop();
    _confirmationClock = null;
    _dragging = false;
    _completed = false;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _confirmationClock?.stop();
    super.dispose();
  }
}
