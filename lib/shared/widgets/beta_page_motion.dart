import 'beta_edge_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import '../../core/platform/distribution_channel.dart';

/// The opaque surface moves with the content. A stationary full-screen cover
/// hid the parent until route disposal and produced a visible final-frame cut.
/// Linear interaction follows the finger; programmatic entry/pop ease symmetrically.
class BetaPageMotion extends StatelessWidget {
  const BetaPageMotion({
    required this.animation,
    required this.child,
    this.linear = false,
    this.secondaryAnimation = kAlwaysDismissedAnimation,
    super.key,
  });
  final Animation<double> animation;
  final Widget child;
  final bool linear;
  final Animation<double> secondaryAnimation;
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
        // The parent travels left when a deeper page arrives and returns from
        // the left when it leaves, matching the retained tab viewport. Use the
        // same animation coordinates in both directions, not a new entry tween
        // selected from AnimationStatus.reverse halfway through a pop.
        child: BetaParentPageMotion(
          animation: secondaryAnimation,
          linear: linear,
          child: surface,
        ),
      ),
    );
  }
}

Route<T> betaContentRoute<T>(Widget page) => BetaContentRoute<T>(
  allowSnapshotting: false,
  pageBuilder: (_, _, _) => BetaEdgeBack(child: page),
  transitionDuration: const Duration(milliseconds: 360),
  reverseTransitionDuration: const Duration(milliseconds: 320),
  transitionsBuilder: (context, animation, secondary, child) => BetaPageMotion(
    animation: animation,
    secondaryAnimation: secondary,
    child: child,
  ),
);

/// Two legacy feature entries use Cupertino routes on Stable. On the current
/// music UI they must join the same horizontal stack as every ordinary page.
Route<T> mestingCupertinoRoute<T>(Widget page) => DistributionChannel.isBeta
    ? betaContentRoute<T>(page)
    : CupertinoPageRoute<T>(builder: (_) => page);

/// GoRouter and Navigator share the same live, reversible surface. Keeping the
/// route unsnapshotted is essential for inherited glass and retained list state.
class BetaContentTransitionPage<T> extends Page<T> {
  const BetaContentTransitionPage({required this.child, super.key, super.name});
  final Widget child;
  @override
  Route<T> createRoute(BuildContext context) => BetaContentRoute<T>(
    settings: this,
    allowSnapshotting: false,
    pageBuilder: (_, _, _) => child,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (_, animation, secondary, child) => BetaPageMotion(
      animation: animation,
      secondaryAnimation: secondary,
      child: child,
    ),
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
    secondaryAnimation: secondaryAnimation,
    child: BetaEdgeBack(child: child),
  );
}

/// The viewport owns Tab selection motion; the root route itself has no entry
/// animation. The
/// shell must participate as the parent of pages pushed above its Navigator.
/// Otherwise returning from a subpage remounts an apparently forward-moving
/// destination while the real parent remains static beneath it.
class BetaRootTransitionPage<T> extends Page<T> {
  const BetaRootTransitionPage({required this.child, super.key});
  final Widget child;
  @override
  Route<T> createRoute(BuildContext context) => BetaContentRoute<T>(
    settings: this,
    allowSnapshotting: false,
    // Root motion belongs to BetaRootTabViewport. A nonzero primary
    // duration can freeze the newly selected branch's readiness TickerMode.
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => child,
    transitionsBuilder: (_, _, secondary, child) =>
        BetaParentPageMotion(animation: secondary, child: child),
  );
}

class BetaParentPageMotion extends StatelessWidget {
  const BetaParentPageMotion({
    required this.animation,
    required this.child,
    this.linear = false,
    super.key,
  });
  final Animation<double> animation;
  final Widget child;
  final bool linear;
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : SlideTransition(
          position: animation.drive(
            Tween<Offset>(begin: Offset.zero, end: const Offset(-1, 0)).chain(
              CurveTween(curve: linear ? Curves.linear : Curves.easeInOutCubic),
            ),
          ),
          child: child,
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

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      DistributionChannel.isBeta
      ? nextRoute is BetaContentRoute || nextRoute is MestingPageRoute
      : super.canTransitionTo(nextRoute);

  // Keep the reciprocal ordinary-page contract explicit for mixed stacks.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      DistributionChannel.isBeta
      ? previousRoute is BetaContentRoute || previousRoute is MestingPageRoute
      : super.canTransitionFrom(previousRoute);

  // Flutter's Material route supplies a delegated builder even when the theme
  // has no delegated transition. Flutter then proxies the previous route's
  // secondary animation to zero, including when that builder returns null.
  // Beta already coordinates both layers in BetaPageMotion; advertising no
  // delegate preserves the real secondary animation for every route family.
  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      DistributionChannel.isBeta ? null : super.delegatedTransition;
}

/// Only ordinary page pairs share a horizontal parent motion. Player vinyl,
/// avatar zooms, search expansion and modal sheets own their special underlay;
/// feeding those into the parent slide would change their approved entry.
class BetaContentRoute<T> extends PageRouteBuilder<T> {
  BetaContentRoute({
    required super.pageBuilder,
    required super.transitionsBuilder,
    super.settings,
    super.allowSnapshotting = false,
    super.transitionDuration = const Duration(milliseconds: 360),
    super.reverseTransitionDuration = const Duration(milliseconds: 320),
  });
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is BetaContentRoute || nextRoute is MestingPageRoute;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // Navigator updates a declarative Route's settings while retaining its
    // State. A constructor closure captures the FIRST page forever, including
    // a StatefulNavigationShell with its original tab index. Read the latest
    // Page instead, as GoRouter's own CustomTransitionPage route does.
    final page = settings;
    if (page is BetaRootTransitionPage) return page.child;
    if (page is BetaContentTransitionPage) return page.child;
    return super.buildPage(context, animation, secondaryAnimation);
  }
}
