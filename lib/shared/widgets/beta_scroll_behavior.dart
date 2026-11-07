import 'package:flutter/material.dart';

/// StretchingOverscrollIndicator isolates its child in an ImageFilter pass.
/// Glass inside that pass cannot sample a Scaffold outside it, producing a
/// dark lens in light mode. Native bouncing keeps the same backdrop and full
/// optical effect while preserving overscroll motion throughout Beta pages.
class BetaScrollBehavior extends MaterialScrollBehavior {
  const BetaScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
