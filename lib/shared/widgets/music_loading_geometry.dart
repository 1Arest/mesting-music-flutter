import 'dart:math' as math;

/// Converts window safe areas and floating chrome into a viewport's local
/// coordinates. A page below an existing header must not reserve that header
/// or the already-consumed bottom space a second time.
class MusicLoadingGeometry {
  const MusicLoadingGeometry({required this.top, required this.bottom});

  factory MusicLoadingGeometry.inWindow({
    required double origin,
    required double height,
    required double windowHeight,
    required double safeTop,
    required double chromeBottom,
  }) {
    final top = (safeTop - origin).clamp(0.0, height);
    return MusicLoadingGeometry(
      top: top,
      bottom: (windowHeight - chromeBottom - origin).clamp(top, height),
    );
  }

  static const indicatorExtent = 32.0;
  static const contentGap = 14.0;
  static const chromeGap = 16.0;
  final double top;
  final double bottom;

  /// Last revealed content stops here, leaving only one spinner and two small
  /// gaps above the controls. This is not the list's trailing content padding.
  double footer(double viewportBottom) => math.max(
    0,
    viewportBottom - bottom + indicatorExtent + contentGap + chromeGap,
  );

  double indicatorTop({
    required double cutoff,
    required double extent,
    required bool refreshing,
    double refreshOrigin = 0,
  }) {
    final maximum = math.max(top, bottom - extent - chromeGap);
    final requested = refreshing
        ? math.max(top, refreshOrigin) + 18
        : cutoff == 0
        ? top + (bottom - top - extent) / 2
        : maximum;
    return requested.clamp(top, maximum);
  }
}
