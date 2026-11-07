import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class MestingAdaptiveBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;
}

enum MestingWindowClass { compact, medium, expanded }

/// Returns whether a window should use tablet-oriented vertical composition.
///
/// The shortest side is used so this works with both logical tablet sizes and
/// high-density screenshots, without treating a phone in landscape as a
/// tablet merely because its width is large.
bool mestingIsTabletWindow(Size size) => size.shortestSide >= 600;

MestingWindowClass mestingWindowClassForWidth(double width) {
  if (width >= MestingAdaptiveBreakpoints.expanded) {
    return MestingWindowClass.expanded;
  }
  if (width >= MestingAdaptiveBreakpoints.medium) {
    return MestingWindowClass.medium;
  }
  return MestingWindowClass.compact;
}

bool mestingUsesNavigationRailForWidth(double width) =>
    mestingWindowClassForWidth(width) == MestingWindowClass.expanded;

double mestingPageMaxWidthFor(double width) {
  return switch (mestingWindowClassForWidth(width)) {
    MestingWindowClass.compact => width,
    MestingWindowClass.medium => 760,
    MestingWindowClass.expanded => 1080,
  };
}

double mestingMusicPageBottomClearanceForWidth(double width) {
  return mestingUsesNavigationRailForWidth(width) ? 112 : 168;
}

int mestingGridColumnCount({
  required double width,
  int compact = 2,
  int medium = 2,
  int expanded = 4,
}) {
  return switch (mestingWindowClassForWidth(width)) {
    MestingWindowClass.compact => compact,
    MestingWindowClass.medium => medium,
    MestingWindowClass.expanded => expanded,
  };
}

class MestingAdaptiveContentFrame extends StatelessWidget {
  const MestingAdaptiveContentFrame({
    required this.child,
    this.maxWidth,
    super.key,
  });

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final resolvedMaxWidth = math.min(
          availableWidth,
          maxWidth ?? mestingPageMaxWidthFor(availableWidth),
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            key: const ValueKey('mesting-adaptive-content-frame'),
            width: resolvedMaxWidth,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: child,
          ),
        );
      },
    );
  }
}
