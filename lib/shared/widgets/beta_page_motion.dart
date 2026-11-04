import 'beta_edge_back.dart';
import 'beta_tab_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root tabs share one spatial axis. Both replacement-route animations and
/// secondary push animations can drive departure; detail routes retain their
/// existing edge-back choreography in [BetaPageMotion].
class BetaRootTabMotion extends ConsumerStatefulWidget {
  const BetaRootTabMotion({
    required this.index,
    required this.animation,
    required this.secondary,
    required this.child,
    super.key,
  });
  final int index;
  final Animation<double> animation, secondary;
  final Widget child;

  @override
  ConsumerState<BetaRootTabMotion> createState() => _BetaRootTabMotionState();
}

class _BetaRootTabMotionState extends ConsumerState<BetaRootTabMotion> {
  late final _navigation = ref.read(betaTabNavigationProvider);
  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_progress);
  }

  @override
  void didUpdateWidget(covariant BetaRootTabMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_progress);
      widget.animation.addListener(_progress);
    }
  }

  void _progress() {
    if (_navigation.motion.value?.to == widget.index) {
      _navigation.progress.value = widget.animation.value;
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_progress);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigation = _navigation;
    final surface = RepaintBoundary(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: widget.child,
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return surface;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.animation,
        widget.secondary,
        navigation.motion,
        navigation.progress,
      ]),
      child: surface,
      builder: (context, child) {
        final motion = navigation.motion.value;
        var offset = 0.0;
        if (motion != null) {
          if (motion.from == widget.index) {
            // Declarative tab replacement can complete the outgoing route
            // without reversing its own animation. Follow the entering route
            // so both live surfaces share the same displacement and seam.
            final progress = navigation.progress.value;
            offset =
                motion.direction *
                Curves.easeInOutCubic.transform(progress.clamp(0, 1));
          } else if (motion.to == widget.index) {
            offset =
                motion.direction *
                (Curves.easeInOutCubic.transform(widget.animation.value) - 1);
          }
        }
        return ClipRect(
          child: FractionalTranslation(
            key: ValueKey('beta-root-tab-motion-${widget.index}'),
            translation: Offset(offset, 0),
            child: child,
          ),
        );
      },
    );
  }
}

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
  pageBuilder: (_, _, _) => BetaEdgeBack(child: page),
  transitionDuration: const Duration(milliseconds: 360),
  reverseTransitionDuration: const Duration(milliseconds: 320),
  transitionsBuilder: (context, animation, _, child) =>
      BetaPageMotion(animation: animation, child: child),
);

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
