import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/player/presentation/now_playing_transition.dart';

void main() {
  test('return transition restores the page while the vinyl is shrinking', () {
    expect(nowPlayingUnderlayOpacity(1), 0);
    expect(nowPlayingUnderlayOpacity(0), 1);
    expect(
      nowPlayingUnderlayOpacity(.4),
      greaterThan(nowPlayingUnderlayOpacity(.7)),
    );
    expect(
      nowPlayingUnderlayOpacity(.2),
      greaterThan(nowPlayingUnderlayOpacity(.4)),
    );
  });

  test('player foreground and destination page never overlap', () {
    expect(nowPlayingForegroundOpacity(nowPlayingContentHandoffProgress), 0);
    expect(nowPlayingUnderlayOpacity(nowPlayingContentHandoffProgress), 0);

    for (var step = 0; step <= 100; step += 1) {
      final progress = step / 100;
      final foreground = nowPlayingForegroundOpacity(progress);
      final underlay = nowPlayingUnderlayOpacity(progress);
      expect(
        foreground > 0 && underlay > 0,
        isFalse,
        reason: 'route progress $progress paints both page contents',
      );
    }
  });

  test('return transition settles transform and blur without overshoot', () {
    expect(nowPlayingUnderlayScale(1), closeTo(.985, .0001));
    expect(nowPlayingUnderlayScale(0), 1);
    expect(nowPlayingUnderlayOffset(1), closeTo(8, .0001));
    expect(nowPlayingUnderlayOffset(0), 0);
    expect(nowPlayingUnderlayBlurSigma(1), closeTo(2.4, .0001));
    expect(nowPlayingUnderlayBlurSigma(0), 0);
  });

  test('route and vinyl use one coordinated timeline', () {
    expect(nowPlayingTransitionDuration, const Duration(milliseconds: 480));
    expect(nowPlayingReverseTransitionDuration, nowPlayingTransitionDuration);
  });
}
