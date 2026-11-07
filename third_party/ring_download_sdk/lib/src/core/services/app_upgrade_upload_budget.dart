import 'dart:async';
import 'dart:math';

/// Process-wide phone payload budget. Linux senders and compatibility callers
/// do not use it. RTC framing, signaling and retransmissions are additional.
class AppUpgradeUploadBudget {
  AppUpgradeUploadBudget({
    this.bytesPerSecond = 256 * 1024,
    this.burstBytes = 256 * 1024,
    int Function()? clockMicros,
  }) : assert(bytesPerSecond > 0 && burstBytes > 0),
       _clock = clockMicros ?? _monotonicClock() {
    _tokens = burstBytes.toDouble();
    _last = _clock();
  }

  static final mobile = AppUpgradeUploadBudget();
  static int Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }
  final int bytesPerSecond, burstBytes;
  final int Function() _clock;
  late double _tokens;
  late int _last;
  AppUpgradeUploadSlot? _holder;

  AppUpgradeUploadSlot? tryAcquire() {
    if (_holder != null) return null;
    return _holder = AppUpgradeUploadSlot._(this);
  }

  void _refill() {
    final now = _clock();
    _tokens = min(
      burstBytes.toDouble(),
      _tokens + max(0, now - _last) * bytesPerSecond / 1000000,
    );
    _last = now;
  }
}

/// Cancel wakes a pacing wait immediately. Release is separate: the RTC owner
/// calls it only after its actual file/send/native retirement has settled.
class AppUpgradeUploadSlot {
  AppUpgradeUploadSlot._(this._budget);
  final AppUpgradeUploadBudget _budget;
  bool _cancelled = false, _released = false;
  Timer? _timer;
  Completer<void>? _wake;
  bool get active => !_cancelled && !_released;

  Future<void> take(int bytes, bool Function() allowed) async {
    if (bytes <= 0 || bytes > _budget.burstBytes) {
      throw ArgumentError.value(bytes, 'bytes');
    }
    if (_wake != null) throw StateError('concurrent_upload_budget_wait');
    while (true) {
      if (!active || !allowed()) throw StateError('upload_cancelled');
      _budget._refill();
      if (_budget._tokens >= bytes) {
        _budget._tokens -= bytes;
        return;
      }
      final wait =
          ((_budget._tokens - bytes).abs() * 1000000 / _budget.bytesPerSecond)
              .ceil();
      final wake = _wake = Completer<void>();
      _timer = Timer(Duration(microseconds: max(1, wait)), () {
        if (!wake.isCompleted) wake.complete();
      });
      try {
        await wake.future;
      } finally {
        _timer?.cancel();
        _timer = null;
        _wake = null;
      }
    }
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void release() {
    if (_released) return;
    cancel();
    _released = true;
    if (identical(_budget._holder, this)) _budget._holder = null;
  }
}
