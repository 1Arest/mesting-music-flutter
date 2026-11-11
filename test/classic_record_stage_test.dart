import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/player/presentation/classic_record_stage.dart';
import 'package:mesting_music/features/player/presentation/vinyl_disc.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';

void main() {
  test(
    'stylus lands on grooves outside the cover and disc stays inside its stage',
    () {
      for (final side in [120.0, 260.0, 340.0, 560.0]) {
        final geometry = ClassicRecordGeometry(side);
        final distance = (geometry.stylus - geometry.record.center).distance;
        expect(distance, greaterThan(geometry.record.width / 2 * .62));
        expect(distance, lessThan(geometry.record.width / 2));
        expect(geometry.pivot.dy, lessThan(geometry.record.top));
        expect(geometry.record.bottom, lessThanOrEqualTo(geometry.height));
        expect(geometry.record.left, greaterThanOrEqualTo(0));
        expect(geometry.record.right, lessThanOrEqualTo(side));
      }
    },
  );

  for (final size in [
    const Size(320, 320),
    const Size(520, 220),
    const Size(190, 300),
  ]) {
    testWidgets('record remains round with a safe arm at $size', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: const ClassicRecordStage(
                  coverAsset: 'assets/images/playlists/13416469337261709.jpeg',
                  playing: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final disc = tester.getSize(
        find.byKey(const ValueKey('classic-record-disc')),
      );
      final cover = tester.getSize(find.byType(ArtworkImage));
      expect(disc.width, closeTo(disc.height, .01));
      expect(cover.width, closeTo(cover.height, .01));
      expect(cover.width / disc.width, closeTo(.62, .001));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pause lifts the arm, stops rotation and reduced motion has no repeating ticker',
    (tester) async {
      var playing = true, reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQueryData(disableAnimations: reduced),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 320,
                      child: ClassicRecordStage(
                        coverAsset:
                            'assets/images/playlists/13416469337261709.jpeg',
                        playing: playing,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final turns = tester
          .widget<RotationTransition>(
            find.descendant(
              of: find.byType(VinylDisc),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns;
      expect(turns.value, greaterThan(0));
      update(() => playing = false);
      await tester.pumpAndSettle();
      final paused = turns.value;
      final arm =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('classic-record-tonearm')),
                  )
                  .painter!
              as ClassicTonearmPainter;
      expect(arm.angle, closeTo(-.34, .001));
      await tester.pump(const Duration(seconds: 1));
      expect(turns.value, paused);
      update(() {
        playing = true;
        reduced = true;
      });
      await tester.pumpAndSettle();
      expect(tester.widget<VinylDisc>(find.byType(VinylDisc)).playing, false);
      expect(tester.takeException(), isNull);
    },
  );
}
