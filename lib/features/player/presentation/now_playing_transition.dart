import 'package:flutter/widgets.dart';

const nowPlayingTransitionDuration = Duration(milliseconds: 480);
const nowPlayingReverseTransitionDuration = Duration(milliseconds: 480);
const nowPlayingContentHandoffProgress = .54;

/// Carries the mini vinyl's exact screen position into the full player.
class NowPlayingTransitionIntent {
  const NowPlayingTransitionIntent({required this.vinylOrigin});

  final Rect vinylOrigin;
}

/// Visual state for the page below the full player.
///
/// The underlying page stays concealed while the player is open, then returns
/// during the vinyl's reverse flight instead of appearing after it.
double nowPlayingUnderlayOpacity(double routeProgress) {
  final progress = (routeProgress / nowPlayingContentHandoffProgress).clamp(
    0.0,
    1.0,
  );
  return 1 - Curves.easeInOutCubic.transform(progress);
}

double nowPlayingForegroundOpacity(double routeProgress) {
  final progress =
      ((routeProgress - nowPlayingContentHandoffProgress) /
              (1 - nowPlayingContentHandoffProgress))
          .clamp(0.0, 1.0);
  return Curves.easeOutCubic.transform(progress);
}

class NowPlayingForegroundCurve extends Curve {
  const NowPlayingForegroundCurve();

  @override
  double transformInternal(double t) => nowPlayingForegroundOpacity(t);
}

double nowPlayingUnderlayScale(double routeProgress) {
  final progress = Curves.easeOutCubic.transform(routeProgress.clamp(0.0, 1.0));
  return 1 - (.015 * progress);
}

double nowPlayingUnderlayOffset(double routeProgress) {
  final progress = Curves.easeOutCubic.transform(routeProgress.clamp(0.0, 1.0));
  return 8 * progress;
}

double nowPlayingUnderlayBlurSigma(double routeProgress) {
  final progress = Curves.easeOutCubic.transform(routeProgress.clamp(0.0, 1.0));
  return 2.4 * progress;
}
