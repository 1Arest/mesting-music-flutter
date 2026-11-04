import 'dart:math' as math;
import 'package:flutter/widgets.dart';

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
    await position.animateTo(
      destination,
      duration: duration(position, destination),
      curve: Curves.easeInOutCubic,
    );
  }
}
