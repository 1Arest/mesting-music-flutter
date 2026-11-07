import 'dart:async';

/// Measures visibility from the first decoded image's painted frame, not from
/// process startup. Dependency initialization remains independent and parallel.
/// The bootstrap can leave only after both this gate and dependencies are ready.
class StartupVisibilityGate {
  StartupVisibilityGate({
    required this.onElapsed,
    this.minimum = const Duration(milliseconds: 500),
  });

  final void Function() onElapsed;
  final Duration minimum;
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;

  void presented() {
    if (_disposed || _started) return;
    _started = true;
    _timer = Timer(minimum, () {
      if (!_disposed) onElapsed();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
