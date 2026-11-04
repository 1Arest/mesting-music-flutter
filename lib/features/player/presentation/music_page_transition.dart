import 'package:flutter/material.dart';

enum MusicPageTransitionDirection { forward, backward }

const musicPageTransitionDuration = Duration(milliseconds: 340);
const musicPageReverseTransitionDuration = Duration(milliseconds: 320);
const musicPageHandoffProgress = .42;
const musicPageLayerOpacityFloor = 1.0;
const musicPageUsesRouteSnapshotting = false;
const musicPageHorizontalOffset = .045;
const musicPageMotionCurve = Curves.easeInOutCubic;
// Keep routes opened from the music hub visually aligned with the hub drawer
// itself. These values are deliberately shared instead of recreating a near
// match at each menu destination.
const musicHubPanelTransitionDuration = Duration(milliseconds: 310);
const musicHubPanelTransitionOffset = Offset(-1, 0);
const musicHubPanelTransitionCurve = Curves.easeOutCubic;
const musicHubPanelReverseTransitionCurve = Curves.easeInCubic;
const musicHubDestinationTransitionDuration = Duration(milliseconds: 300);
const musicHubDestinationReverseTransitionDuration = Duration(
  milliseconds: 240,
);
const musicHubDestinationTransitionOffset = Offset(-.055, 0);
const musicHubDestinationTransitionCurve = Cubic(.16, 1, .3, 1);
const musicHubDestinationReverseTransitionCurve = Cubic(.4, 0, 1, 1);
const messagesPageTransitionDuration = Duration(milliseconds: 360);
const messagesPageReverseTransitionDuration = Duration(milliseconds: 280);
const messagesPageHandoffProgress = .18;
const messagesPageHorizontalOffset = .032;
const messagesPageStartScale = .992;
// Keep this aligned with the profile route beneath the editor. A different
// threshold would briefly hide both page layers while the editor is popped.
const profileEditPageHandoffProgress = musicPageHandoffProgress;
const profileEditPageTransitionDuration = Duration(milliseconds: 320);
const profileEditPageReverseTransitionDuration = Duration(milliseconds: 260);
const profileEditPageHorizontalOffset = .032;
const profileEditPageStartScale = .996;
const profileEditPageReverseMotionCurve = Curves.easeInCubic;
const collectionRevealDuration = Duration(milliseconds: 380);
const collectionRevealReverseDuration = Duration(milliseconds: 340);
const collectionRevealStartScale = .985;
const collectionRevealVerticalOffset = .022;

/// Clips the moving page content while the shared theme background stays still.
class MusicPageTransitionSurface extends StatelessWidget {
  const MusicPageTransitionSurface({
    required this.position,
    required this.child,
    this.scale,
    this.scaleAlignment = Alignment.center,
    super.key,
  });

  final Animation<Offset> position;
  final Animation<double>? scale;
  final Alignment scaleAlignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget movingContent = SlideTransition(
      key: const ValueKey('music-page-transition-moving-content'),
      position: position,
      child: child,
    );
    if (scale case final scale?) {
      movingContent = ScaleTransition(
        alignment: scaleAlignment,
        scale: scale,
        child: movingContent,
      );
    }
    return SizedBox.expand(
      child: ClipRect(
        key: const ValueKey('music-page-transition-content-clip'),
        child: movingContent,
      ),
    );
  }
}

/// The left-edge slide and fade used by the music hub drawer and by routes
/// opened from it. Keeping this as one widget prevents motion drift between
/// the menu and its destinations.
class MusicHubPanelTransition extends StatelessWidget {
  const MusicHubPanelTransition({
    required this.animation,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = CurvedAnimation(
      parent: animation,
      curve: musicHubPanelTransitionCurve,
      reverseCurve: musicHubPanelReverseTransitionCurve,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: musicHubPanelTransitionOffset,
        end: Offset.zero,
      ).animate(motion),
      child: FadeTransition(opacity: motion, child: child),
    );
  }
}

/// A quiet continuation after the music hub panel has fully left the screen.
///
/// Repeating the drawer's full-width sweep made destination navigation feel
/// like two unrelated transitions. The destination is already substantially
/// visible and travels only a short distance, so the motion reads as one
/// continuous handoff. A fixed opaque surface stays beneath the moving page so
/// its short travel never reveals the previous recommendation page.
class MusicHubDestinationTransition extends StatelessWidget {
  const MusicHubDestinationTransition({
    required this.animation,
    required this.child,
    this.handoffProgress = musicPageHandoffProgress,
    this.blockUnderlyingContent = false,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;
  final double handoffProgress;
  final bool blockUnderlyingContent;

  @override
  Widget build(BuildContext context) {
    final motion = CurvedAnimation(
      parent: animation,
      curve: Interval(
        handoffProgress,
        1,
        curve: musicHubDestinationTransitionCurve,
      ),
      reverseCurve: Interval(
        handoffProgress,
        1,
        curve: musicHubDestinationReverseTransitionCurve,
      ),
    );
    final position = Tween<Offset>(
      begin: musicHubDestinationTransitionOffset,
      end: Offset.zero,
    ).animate(motion);
    final movingPage = ClipRect(
      key: const ValueKey('music-hub-destination-clip'),
      child: RepaintBoundary(
        child: SlideTransition(
          key: const ValueKey('music-hub-destination-slide'),
          position: position,
          child: child,
        ),
      ),
    );
    if (!blockUnderlyingContent) return movingPage;

    // Dialog-style destinations are mounted on the root navigator, so the
    // shell route beneath them does not receive a secondary animation and
    // cannot participate in the normal single-layer handoff. Paint a truly
    // opaque semantic surface in that one case. Do not use
    // scaffoldBackgroundColor here: Mesting intentionally defines it as
    // transparent so regular pages can reveal the shared theme artwork.
    final theme = Theme.of(context);
    final opaqueSurface = Color.alphaBlend(
      theme.colorScheme.surface,
      theme.brightness == Brightness.dark ? Colors.black : Colors.white,
    );
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            key: const ValueKey('music-hub-destination-opaque-underlay'),
            color: opaqueSurface,
          ),
          movingPage,
        ],
      ),
    );
  }
}

/// Coordinates routes opened from the music hub with the outgoing page.
///
/// The outgoing route remains visible only before [handoffProgress], and the
/// destination becomes visible only at or after that exact boundary. This is
/// the hard guarantee that recommendation content and destination content can
/// never be painted in the same frame.
class MusicHubDestinationLayerHandoff extends StatelessWidget {
  const MusicHubDestinationLayerHandoff({
    required this.primaryAnimation,
    required this.secondaryAnimation,
    required this.child,
    this.handoffProgress = musicPageHandoffProgress,
    this.blockUnderlyingContent = false,
    super.key,
  });

  final Animation<double> primaryAnimation;
  final Animation<double> secondaryAnimation;
  final Widget child;
  final double handoffProgress;
  final bool blockUnderlyingContent;

  @override
  Widget build(BuildContext context) {
    return MusicPageSingleLayerHandoff(
      primaryAnimation: primaryAnimation,
      secondaryAnimation: secondaryAnimation,
      handoffProgress: handoffProgress,
      child: MusicHubDestinationTransition(
        animation: primaryAnimation,
        handoffProgress: handoffProgress,
        blockUnderlyingContent: blockUnderlyingContent,
        child: child,
      ),
    );
  }
}

bool musicPageLayerIsVisible({
  required AnimationStatus primaryStatus,
  required double primaryValue,
  required AnimationStatus secondaryStatus,
  required double secondaryValue,
  double handoffProgress = musicPageHandoffProgress,
}) {
  if (primaryStatus == AnimationStatus.dismissed) return false;
  if (primaryStatus == AnimationStatus.forward) {
    return primaryValue >= handoffProgress;
  }
  if (primaryStatus == AnimationStatus.reverse) {
    return primaryValue > handoffProgress;
  }
  if (secondaryStatus == AnimationStatus.dismissed) return true;
  if (secondaryStatus == AnimationStatus.forward) {
    return secondaryValue < handoffProgress;
  }
  if (secondaryStatus == AnimationStatus.reverse) {
    return secondaryValue <= handoffProgress;
  }
  return false;
}

double musicPageLayerOpacity({
  required AnimationStatus primaryStatus,
  required double primaryValue,
  required AnimationStatus secondaryStatus,
  required double secondaryValue,
  double handoffProgress = musicPageHandoffProgress,
}) {
  if (primaryStatus == AnimationStatus.dismissed) return 0;
  if (primaryStatus == AnimationStatus.forward) {
    if (primaryValue < handoffProgress) return 0;
    final progress = ((primaryValue - handoffProgress) / (1 - handoffProgress))
        .clamp(0.0, 1.0);
    return musicPageLayerOpacityFloor +
        (1 - musicPageLayerOpacityFloor) *
            musicPageMotionCurve.transform(progress);
  }
  if (primaryStatus == AnimationStatus.reverse) {
    if (primaryValue <= handoffProgress) return 0;
    final progress = ((primaryValue - handoffProgress) / (1 - handoffProgress))
        .clamp(0.0, 1.0);
    return musicPageLayerOpacityFloor +
        (1 - musicPageLayerOpacityFloor) *
            musicPageMotionCurve.transform(progress);
  }
  if (secondaryStatus == AnimationStatus.dismissed) return 1;
  if (secondaryStatus == AnimationStatus.forward) {
    if (secondaryValue >= handoffProgress) return 0;
    final progress = (secondaryValue / handoffProgress).clamp(0.0, 1.0);
    return musicPageLayerOpacityFloor +
        (1 - musicPageLayerOpacityFloor) *
            (1 - musicPageMotionCurve.transform(progress));
  }
  if (secondaryStatus == AnimationStatus.reverse) {
    final reverseHandoff = handoffProgress;
    if (secondaryValue > reverseHandoff) return 0;
    final progress = (1 - secondaryValue / reverseHandoff).clamp(0.0, 1.0);
    return musicPageLayerOpacityFloor +
        (1 - musicPageLayerOpacityFloor) *
            musicPageMotionCurve.transform(progress);
  }
  return 0;
}

/// Hands the page surface from the outgoing route to the incoming route.
///
/// Music pages are intentionally transparent so the selected theme artwork can
/// remain in the shell. The visible page remains fully opaque during handoff:
/// applying fractional opacity to a route containing backdrop filters creates
/// an offscreen layer and can flash a dark blurred frame on Android. [Offstage]
/// preserves the strict single-layer rule while hidden routes stay alive
/// without painting, hit testing, or exposing their semantics.
class MusicPageSingleLayerHandoff extends StatelessWidget {
  const MusicPageSingleLayerHandoff({
    required this.primaryAnimation,
    required this.secondaryAnimation,
    required this.child,
    this.handoffProgress = musicPageHandoffProgress,
    super.key,
  });

  final Animation<double> primaryAnimation;
  final Animation<double> secondaryAnimation;
  final Widget child;
  final double handoffProgress;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([primaryAnimation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final visible = musicPageLayerIsVisible(
          primaryStatus: primaryAnimation.status,
          primaryValue: primaryAnimation.value,
          secondaryStatus: secondaryAnimation.status,
          secondaryValue: secondaryAnimation.value,
          handoffProgress: handoffProgress,
        );
        final opacity = musicPageLayerOpacity(
          primaryStatus: primaryAnimation.status,
          primaryValue: primaryAnimation.value,
          secondaryStatus: secondaryAnimation.status,
          secondaryValue: secondaryAnimation.value,
          handoffProgress: handoffProgress,
        );
        return Offstage(
          key: const ValueKey('music-page-outgoing-layer'),
          offstage: !visible,
          child: IgnorePointer(
            ignoring:
                primaryAnimation.status != AnimationStatus.completed ||
                secondaryAnimation.status != AnimationStatus.dismissed,
            child: Opacity(
              key: const ValueKey('music-page-layer-opacity'),
              opacity: opacity,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Makes a route opened from the music hub participate in later pushes.
///
/// Hub destinations enter with the drawer's own motion, so they do not use
/// [MusicPageSingleLayerHandoff] for their primary animation. They still need
/// to stop painting when another route is pushed above them; otherwise their
/// toolbar and list remain visible under the next transparent music page.
class MusicPageOutgoingLayerHandoff extends StatelessWidget {
  const MusicPageOutgoingLayerHandoff({
    required this.secondaryAnimation,
    required this.child,
    this.handoffProgress = musicPageHandoffProgress,
    super.key,
  });

  final Animation<double> secondaryAnimation;
  final Widget child;
  final double handoffProgress;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: secondaryAnimation,
      child: child,
      builder: (context, child) {
        final visible = musicPageLayerIsVisible(
          primaryStatus: AnimationStatus.completed,
          primaryValue: 1,
          secondaryStatus: secondaryAnimation.status,
          secondaryValue: secondaryAnimation.value,
          handoffProgress: handoffProgress,
        );
        return Offstage(
          key: const ValueKey('music-page-outgoing-layer'),
          offstage: !visible,
          child: IgnorePointer(
            ignoring: secondaryAnimation.status != AnimationStatus.dismissed,
            child: child,
          ),
        );
      },
    );
  }
}

@immutable
class MusicPageTransitionIntent {
  const MusicPageTransitionIntent(
    this.direction, {
    this.handoffProgress,
    this.usesMusicHubPanelTransition = false,
  });

  const MusicPageTransitionIntent.forward({this.handoffProgress})
    : direction = MusicPageTransitionDirection.forward,
      usesMusicHubPanelTransition = false;

  const MusicPageTransitionIntent.backward({this.handoffProgress})
    : direction = MusicPageTransitionDirection.backward,
      usesMusicHubPanelTransition = false;

  /// Opens a full page with the same left-edge motion as the music hub drawer.
  const MusicPageTransitionIntent.fromMusicHubPanel()
    : direction = MusicPageTransitionDirection.forward,
      handoffProgress = null,
      usesMusicHubPanelTransition = true;

  /// Keeps a conversation opened from the messages list on that list's
  /// earlier handoff boundary. Matching both routes prevents them from
  /// painting together while the conversation is popped.
  const MusicPageTransitionIntent.messagesConversation()
    : direction = MusicPageTransitionDirection.forward,
      handoffProgress = messagesPageHandoffProgress,
      usesMusicHubPanelTransition = false;

  factory MusicPageTransitionIntent.betweenTabs(int from, int to) {
    return MusicPageTransitionIntent(
      to >= from
          ? MusicPageTransitionDirection.forward
          : MusicPageTransitionDirection.backward,
    );
  }

  final MusicPageTransitionDirection direction;
  final double? handoffProgress;
  final bool usesMusicHubPanelTransition;

  double get horizontalOffset =>
      direction == MusicPageTransitionDirection.forward
      ? musicPageHorizontalOffset
      : -musicPageHorizontalOffset;
}
