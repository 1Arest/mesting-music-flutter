import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../../core/platform/distribution_channel.dart';

/// A glass overlay reserves space inside the scroll content, rather than
/// adding an opaque empty box outside it. The page surface still paints behind
/// the glass while its last control can scroll fully above the accessory.
class BetaContentInsets extends InheritedWidget {
  const BetaContentInsets({
    required this.bottom,
    required super.child,
    super.key,
  });
  final double bottom;

  /// Reserve the expanded accessory even while it is compact. Otherwise its
  /// scroll-triggered expansion can cover the last control or move the extent.
  /// This is shared by root and independently pushed music pages.
  static double musicChromeBottomOf(BuildContext context) =>
      170 +
      2 * (MediaQuery.textScalerOf(context).scale(24) - 24).clamp(0.0, 28.0) +
      MediaQuery.viewPaddingOf(context).bottom;

  /// Pages build their child before a secondary layout is inserted. An explicit
  /// music-content call therefore has the same fallback as that layout; ordinary
  /// bottomOf callers still require a real overlay ancestor. Stable keeps its
  /// authored spacing, and an explicit zero scope disables music clearance.
  static double musicBottomOf(BuildContext context, [double minimum = 0]) =>
      DistributionChannel.isBeta
      ? math.max(
          minimum,
          context
                  .dependOnInheritedWidgetOfExactType<BetaContentInsets>()
                  ?.bottom ??
              musicChromeBottomOf(context),
        )
      : minimum;

  static EdgeInsets musicPaddingOf(
    BuildContext context,
    EdgeInsetsGeometry padding,
  ) {
    final resolved = padding.resolve(Directionality.of(context));
    return resolved.copyWith(bottom: musicBottomOf(context, resolved.bottom));
  }

  static double bottomOf(BuildContext context, [double minimum = 0]) =>
      math.max(
        minimum,
        context
                .dependOnInheritedWidgetOfExactType<BetaContentInsets>()
                ?.bottom ??
            0,
      );
  @override
  bool updateShouldNotify(BetaContentInsets oldWidget) =>
      bottom != oldWidget.bottom;
}
