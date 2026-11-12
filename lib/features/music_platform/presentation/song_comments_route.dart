import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_page_motion.dart';

/// Artwork gestures are vertical. Keep ordinary list/comment entry on its
/// existing route, and never let the global horizontal theme override this one.
Route<T> songCommentsRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool fromPlayer = false,
}) {
  if (!fromPlayer) return MestingPageRoute<T>(builder: builder);
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<T>(
    settings: const RouteSettings(name: '/player/comments'),
    allowSnapshotting: false,
    fullscreenDialog: true,
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 360),
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280),
    pageBuilder: (context, _, _) => ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: builder(context),
    ),
    transitionsBuilder: (context, animation, secondary, child) =>
        MediaQuery.disableAnimationsOf(context)
        ? child
        : SlideTransition(
            position: animation.drive(
              Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeInOutCubic)),
            ),
            child: child,
          ),
  );
}
