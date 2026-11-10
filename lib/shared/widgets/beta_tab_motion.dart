import 'dart:math' as math;

/// Pure, bounded geometry for retained root navigation.
///
/// A distant shortcut travels one viewport, never through unrelated branches.
/// Retargeting preserves every visible surface, including a partly visible old
/// destination. A newly requested third page starts beyond the visible strip.
class BetaTabMotion {
  BetaTabMotion(this.target) : _from = {target: 0}, _to = {target: 0};

  int target;
  Map<int, double> _from, _to;

  /// Common screen displacement of the strip, in viewport widths.
  double get distance => _to[target]! - _from[target]!;

  Map<int, double> positions(double progress) => {
    for (final entry in _from.entries)
      entry.key: entry.value + (_to[entry.key]! - entry.value) * progress,
  };

  /// Paint/hit-test queries need one scalar, not a fresh Map per endpoint on
  /// every animation tick. The complete map remains useful for retargeting.
  double position(int index, double progress) {
    final start = _from[index];
    return start == null ? 0 : start + (_to[index]! - start) * progress;
  }

  void retarget(int next, double progress) {
    if (next == target) return;
    final current = positions(progress);
    final visible = current.entries.where((e) => e.value.abs() < 1).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final rightward = next > target;
    final existing = visible.where((e) => e.key == next).firstOrNull;
    final incomingStart =
        existing?.value ??
        (rightward ? visible.last.value + 1 : visible.first.value - 1);
    _from = {for (final e in visible) e.key: e.value, next: incomingStart};
    _to = {for (final e in _from.entries) e.key: e.value - incomingStart};
    target = next;
  }

  /// Critical damping has no oscillation. Preserve the measured velocity
  /// except when it would cross the destination (visible bounce), or move the
  /// strip's outer edge inside the viewport (blank flash). Only these physical
  /// bounds cap velocity; ordinary reversals keep their continuous momentum.
  double safeVelocity(double velocity) {
    final x = _from[target]!;
    if (x.abs() < .000001) return 0;
    const omega = 20.0; // sqrt(stiffness / mass), shared with the viewport.
    if (velocity * x <= 0) {
      return velocity.abs() > omega * x.abs() ? -omega * x : velocity;
    }
    final values = _from.values;
    final allowance = x > 0
        ? -values.reduce(math.min)
        : values.reduce(math.max);
    final limit = x.abs() + math.max(0, allowance);
    double peak(double speed) {
      final t = speed / (omega * (speed + omega * x.abs()));
      return (x.abs() + (speed + omega * x.abs()) * t) * math.exp(-omega * t);
    }

    var low = 0.0, high = velocity.abs();
    for (var i = 0; i < 40; i++) {
      final mid = (low + high) / 2;
      if (peak(mid) <= limit) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return velocity.sign * low;
  }

  void settle() {
    _from = {target: 0};
    _to = {target: 0};
  }
}
