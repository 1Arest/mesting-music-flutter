import 'beta_edge_back.dart';
import 'package:flutter/material.dart';
import '../../core/platform/distribution_channel.dart';

/// The opaque surface moves with the content. A stationary full-screen cover
/// hid the parent until route disposal and produced a visible final-frame cut.
/// Linear interaction follows the finger; programmatic entry/pop ease symmetrically.
class BetaPageMotion extends StatelessWidget {
  const BetaPageMotion({
    required this.animation,
    required this.child,
    this.linear = false,
    super.key,
  });
  final Animation<double> animation;
  final Widget child;
  final bool linear;
  @override
  Widget build(BuildContext context) {
    final surface = RepaintBoundary(
      child: ColoredBox(
        key: const ValueKey('beta10-route-surface'),
        color: Theme.of(context).colorScheme.surface,
        child: child,
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return surface;
    return ClipRect(
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).chain(
            CurveTween(curve: linear ? Curves.linear : Curves.easeInOutCubic),
          ),
        ),
        child: surface,
      ),
    );
  }
}

Route<T> betaContentRoute<T>(Widget page) => PageRouteBuilder<T>(
  allowSnapshotting: false,
  pageBuilder: (_, _, _) => BetaEdgeBack(child: page),
  transitionDuration: const Duration(milliseconds: 360),
  reverseTransitionDuration: const Duration(milliseconds: 320),
  transitionsBuilder: (context, animation, _, child) =>
      BetaPageMotion(animation: animation, child: child),
);

/// GoRouter and Navigator share the same live, reversible surface. Keeping the
/// route unsnapshotted is essential for inherited glass and retained list state.
class BetaContentTransitionPage<T> extends Page<T> {
  const BetaContentTransitionPage({required this.child, super.key, super.name});
  final Widget child;
  @override
  Route<T> createRoute(BuildContext context) => PageRouteBuilder<T>(
    settings: this,
    allowSnapshotting: false,
    pageBuilder: (_, _, _) => child,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (_, animation, _, child) =>
        BetaPageMotion(animation: animation, child: child),
  );
}

/// Material routes used by imported platform pages share the same coverage
/// and lifecycle instead of falling back to a second, default transition.
class BetaPageTransitionsBuilder extends PageTransitionsBuilder {
  const BetaPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => BetaPageMotion(
    animation: animation,
    linear: route.popGestureInProgress,
    child: BetaEdgeBack(child: child),
  );
}

/// Retain Material route semantics on Stable and the existing Beta transition
/// theme, while opting glass-heavy Beta pages out of Android route snapshots.
class MestingPageRoute<T> extends MaterialPageRoute<T> {
  MestingPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    super.requestFocus,
  }) : super(allowSnapshotting: !DistributionChannel.isBeta);
}
