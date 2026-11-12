import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

/// One visible journey for both list shortcuts. Longer lazy-list distances get
/// more time, with a bounded duration so large collections remain practical.
/// animateTo builds intervening slivers during travel; jumpTo would skip all
/// of those frames and only animate a tiny final alignment after the jump.
abstract final class SongListScrollMotion {
  static Duration duration(ScrollPosition position, double target) {
    final screens =
        (target - position.pixels).abs() /
        math.max(1, position.viewportDimension);
    return Duration(
      milliseconds: (400 + screens * 55).round().clamp(420, 1000),
    );
  }

  static Future<void> move(
    ScrollPosition position,
    double target, {
    required bool reduceMotion,
    double? Function()? measuredTarget,
    bool Function()? isCurrent,
  }) async {
    final destination = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (reduceMotion) {
      position.jumpTo(destination);
      return;
    }
    if ((destination - position.pixels).abs() < .5) return;
    if (position is ScrollPositionWithSingleContext && measuredTarget != null) {
      // 一个滚动活动贯穿估算位置和真实行高校准。校准时继承当前速度，
      // 不再等第一段减速到零后启动 ensureVisible，避免途中“顿一下”。
      final activity = _MeasuredScrollActivity(
        position,
        destination,
        duration(position, destination),
        measuredTarget,
        isCurrent ?? () => true,
      );
      position.beginActivity(activity);
      await activity.done;
      return;
    }
    await position.animateTo(
      destination,
      duration: duration(position, destination),
      curve: Curves.easeInOutCubic,
    );
  }
}

/// 使用 Flutter 自身的 ScrollActivity 生命周期，手动拖动/新操作会正常取消。
/// Hermite 曲线在重新定标时保留位置和一阶速度，校准不产生中途静止帧。
class _MeasuredScrollActivity extends ScrollActivity {
  _MeasuredScrollActivity(
    this.position,
    this._to,
    Duration duration,
    this.measure,
    this.current,
  ) : _from = position.pixels,
      _seconds = duration.inMicroseconds / 1000000,
      super(position) {
    _ticker = position.context.vsync.createTicker(_tick)..start();
  }
  final ScrollPositionWithSingleContext position;
  final double? Function() measure;
  final bool Function() current;
  late final Ticker _ticker;
  final _completion = Completer<void>();
  Future<void> get done => _completion.future;
  double _from, _to, _seconds, _speed = 0, _startSpeed = 0;
  double _segmentStart = 0;
  bool _disposed = false;

  void _tick(Duration elapsed) {
    if (_disposed) return;
    if (!current()) {
      delegate.goIdle();
      return;
    }
    final now = elapsed.inMicroseconds / 1000000;
    final exact = measure();
    if (exact != null && exact.isFinite) {
      final corrected = exact.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((corrected - _to).abs() > .75) {
        final remaining = (_seconds - (now - _segmentStart)).clamp(.12, 1.0);
        _from = position.pixels;
        _to = corrected;
        _startSpeed = _speed;
        _seconds = remaining;
        // 同方向的末段缩短时限制时长，保持速度且不冲过目标。
        final distance = _to - _from;
        if (_startSpeed * distance > 0 && _startSpeed.abs() > .1) {
          _seconds = math.min(
            _seconds,
            math.max(.016, 2.8 * distance.abs() / _startSpeed.abs()),
          );
        }
        _segmentStart = now;
      }
    }
    final t = ((now - _segmentStart) / _seconds).clamp(0.0, 1.0);
    final t2 = t * t, t3 = t2 * t;
    final value =
        (2 * t3 - 3 * t2 + 1) * _from +
        (t3 - 2 * t2 + t) * _seconds * _startSpeed +
        (-2 * t3 + 3 * t2) * _to;
    _speed =
        ((6 * t2 - 6 * t) * _from +
            (3 * t2 - 4 * t + 1) * _seconds * _startSpeed +
            (-6 * t2 + 6 * t) * _to) /
        _seconds;
    final pixels = value.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final overflow = delegate.setPixels(pixels);
    if (overflow.abs() > .5 || t >= 1 || now > 4) delegate.goBallistic(0);
  }

  @override
  bool get shouldIgnorePointer => true;
  @override
  bool get isScrolling => true;
  @override
  double get velocity => _speed;
  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    if (!_completion.isCompleted) _completion.complete();
    super.dispose();
  }
}
