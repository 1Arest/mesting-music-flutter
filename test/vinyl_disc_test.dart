import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/player/presentation/now_playing_page.dart';
import 'package:mesting_music/features/player/presentation/vinyl_disc.dart';
import 'package:mesting_music/shared/layout/adaptive_layout.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';

void main() {
  test('vinyl only animates after audio is genuinely ready', () {
    expect(
      shouldAnimateVinyl(
        PlaybackState(
          processingState: AudioProcessingState.loading,
          playing: true,
        ),
      ),
      isFalse,
    );
    expect(
      shouldAnimateVinyl(
        PlaybackState(
          processingState: AudioProcessingState.buffering,
          playing: true,
        ),
      ),
      isFalse,
    );
    expect(
      shouldAnimateVinyl(
        PlaybackState(
          processingState: AudioProcessingState.ready,
          playing: true,
        ),
      ),
      isTrue,
    );
    expect(
      shouldAnimateVinyl(
        PlaybackState(
          processingState: AudioProcessingState.ready,
          playing: false,
        ),
      ),
      isFalse,
    );
  });

  test('tonearm rotates 22.5 degrees around the fixed pivot when paused', () {
    final delta =
        (nowPlayingTonearmPlayingTurns - nowPlayingTonearmPausedTurns) * 360;

    expect(delta, closeTo(22.5, .001));
    expect(nowPlayingTonearmPivotAlignment, const Alignment(-.78, -.86));
  });

  test('turntable geometry follows the normalized reference proportions', () {
    const viewport = Size(411.428571, 914.285714);
    final layout = NowPlayingTurntableLayout.fromSize(viewport);

    expect(layout.recordRect.center.dx, closeTo(viewport.width / 2, .001));
    expect(
      layout.tonearmRect.width / layout.recordRect.width,
      closeTo(.33, .001),
    );
    expect(
      layout.tonearmRect.height / layout.recordRect.height,
      closeTo(.49, .001),
    );
    expect(layout.tonearmRect.top, lessThan(layout.recordRect.top));
  });

  test('tablet turntable is centered between the header and controls', () {
    const viewport = Size(1200, 2048);
    final layout = NowPlayingTurntableLayout.fromSize(viewport);

    expect(mestingIsTabletWindow(viewport), isTrue);
    expect(layout.recordRect.top, greaterThan(600));
    expect(layout.recordRect.center.dy, greaterThan(850));
  });

  testWidgets('vinyl artwork is constrained to a perfect circle', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 320,
              child: VinylDisc(
                coverAsset: 'assets/images/covers/qifengle.jpg',
                playing: false,
              ),
            ),
          ),
        ),
      ),
    );

    final artworkSize = tester.getSize(find.byType(ArtworkImage));
    expect(artworkSize.width, artworkSize.height);
    expect(artworkSize.width, closeTo(192, .1));
    expect(artworkSize.height, closeTo(192, .1));
  });

  testWidgets('vinyl can shrink to the capsule size during its flight', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 54,
              child: VinylDisc(
                coverAsset: 'assets/images/covers/qifengle.jpg',
                playing: false,
                labelSizeFactor: .59,
              ),
            ),
          ),
        ),
      ),
    );

    final artworkSize = tester.getSize(find.byType(ArtworkImage));
    expect(artworkSize.width, closeTo(31.86, .1));
    expect(artworkSize.height, closeTo(31.86, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the full player tonearm asset is bundled', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    final bytes = await rootBundle.load(nowPlayingTonearmAsset);
    expect(bytes.lengthInBytes, greaterThan(10000));
  });
}
