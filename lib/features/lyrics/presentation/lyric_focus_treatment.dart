import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

/// Matches the official renderer's separation of sharp sung text from blurred
/// text masks. Filtering stays local to visible rows, never the whole player.
/// The gallery previews this exact treatment without starting audio or timers.
class LyricFocusTreatment extends StatelessWidget {
  const LyricFocusTreatment({
    required this.distance,
    required this.child,
    super.key,
  });
  final double distance;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: distance.clamp(0, 3).toDouble() / 3),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 460),
    curve: Curves.easeOutCubic,
    child: RepaintBoundary(child: child),
    builder: (_, value, child) => ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: value * 4.2, sigmaY: value * 4.2),
      enabled: value > .01,
      child: Opacity(opacity: 1 - value * .72, child: child),
    ),
  );
}
