import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/beta_edge_back.dart';
import '../../experience/presentation/player_dismiss_motion.dart';
import 'now_playing_transition.dart';

class NowPlayingTransitionPage extends Page<void> {
  const NowPlayingTransitionPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) {
    late final _NowPlayingRoute route;
    route = _NowPlayingRoute(
      settings: this,
      // The vinyl flight is rendered inside the live player page so it can use
      // the mini player's exact global bounds without route snapshot artifacts.
      // Snapshot static page bodies while the route itself slides/fades. The
      // shell player and navigation stay outside this route and remain live.
      allowSnapshotting: !DistributionChannel.isBeta,
      opaque: false,
      transitionDuration: nowPlayingTransitionDuration,
      reverseTransitionDuration: nowPlayingReverseTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          DistributionChannel.isBeta ? BetaEdgeBack(child: child) : child,
      // The player animates its vinyl and chrome from the route animation.
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          DistributionChannel.isBeta
          ? AnimatedBuilder(
              animation: Listenable.merge([
                animation,
                route.playerDismissMotion,
              ]),
              builder: (context, child) {
                final motion = route.playerDismissMotion;
                final progress = motion.dragDriven
                    ? animation.value
                    : (animation.status == AnimationStatus.reverse
                              ? Curves.easeInCubic
                              : Curves.easeOutCubic)
                          .transform(animation.value);
                return FractionalTranslation(
                  translation: Offset(0, 1 - progress),
                  child: child,
                );
              },
              child: RepaintBoundary(child: child),
            )
          : child,
    );
    return route;
  }
}

class _NowPlayingRoute extends PageRouteBuilder<void>
    implements PlayerDismissRoute {
  _NowPlayingRoute({
    required super.pageBuilder,
    required super.transitionsBuilder,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
    required super.opaque,
    required super.allowSnapshotting,
    super.settings,
  });

  @override
  late final PlayerDismissMotion playerDismissMotion;

  @override
  void install() {
    super.install();
    playerDismissMotion = PlayerDismissMotion(controller!);
  }

  @override
  bool didPop(void result) {
    playerDismissMotion.markPopped();
    return super.didPop(result);
  }

  @override
  void dispose() {
    playerDismissMotion.dispose();
    super.dispose();
  }

  @override
  DelegatedTransitionBuilder get delegatedTransition =>
      (context, animation, secondaryAnimation, allowSnapshotting, child) {
        if (child == null) return null;
        // The Beta player is a real sliding surface. Its underlay must stay
        // painted throughout both route pop and handle dismissal. The formal
        // vinyl flight uses its original two-phase choreography below.
        if (DistributionChannel.isBeta) return child;
        return AnimatedBuilder(
          animation: secondaryAnimation,
          child: child,
          builder: (context, child) {
            final progress = secondaryAnimation.value;
            return Opacity(
              opacity: nowPlayingUnderlayOpacity(progress),
              child: Transform.translate(
                offset: Offset(0, nowPlayingUnderlayOffset(progress)),
                child: Transform.scale(
                  scale: nowPlayingUnderlayScale(progress),
                  alignment: Alignment.bottomCenter,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: nowPlayingUnderlayBlurSigma(progress),
                      sigmaY: nowPlayingUnderlayBlurSigma(progress),
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      };
}
