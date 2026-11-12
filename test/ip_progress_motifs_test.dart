import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/player/presentation/ip_progress_decoration.dart';
import 'package:mesting_music/features/player/presentation/ip_progress_motifs.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Kirby body is centered after lifting the hat-and-bubble canvas', () {
    for (final center in [20.0, 24.0, 28.0]) {
      final top = progressCompanionTop(
        MusicThemeIp.sleepingKirby,
        trackCenterY: center,
      );
      expect(top, closeTo(center - 17.92, .01));
      // The opaque body midpoint is below the PNG midpoint due to the hat.
      expect(top + 28 * .64, closeTo(center, .01));
      expect(top, lessThan(center - 14));
    }
  });

  for (final ip in [
    MusicThemeIp.helloKitty,
    MusicThemeIp.kuromi,
    MusicThemeIp.myMelody,
    MusicThemeIp.cinnamoroll,
    MusicThemeIp.chiikawa,
    MusicThemeIp.hachiware,
    MusicThemeIp.usagi,
    MusicThemeIp.puppyWhite,
    MusicThemeIp.puppyGray,
    MusicThemeIp.sleepingKirby,
  ]) {
    testWidgets(
      '${ip.name} adds a silhouette beyond the rail without painting unplayed progress',
      (tester) async {
        for (final direction in TextDirection.values) {
          await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            paintIpProgressMotifs(
              canvas,
              ip: ip,
              track: const Rect.fromLTWH(0, 17, 320, 6),
              active: Rect.fromLTWH(
                direction == TextDirection.ltr ? 0 : 160,
                17,
                160,
                6,
              ),
              direction: direction,
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(320, 40);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            var outsideRail = 0, inactivePixels = 0;
            for (var y = 0; y < 40; y++) {
              for (var x = 0; x < 320; x++) {
                if (bytes[(y * 320 + x) * 4 + 3] == 0) continue;
                if (y < 17 || y > 23) outsideRail++;
                if (direction == TextDirection.ltr ? x >= 160 : x < 160) {
                  inactivePixels++;
                }
              }
            }
            expect(
              outsideRail,
              greaterThan(10),
              reason:
                  'IP silhouettes must be visible beyond a recolored 6px line',
            );
            expect(
              inactivePixels,
              0,
              reason: 'Ornaments must not imply extra playback progress',
            );
            image.dispose();
            picture.dispose();
          });
        }
      },
    );
  }

  testWidgets('empty playback does not paint decorative progress', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      paintIpProgressMotifs(
        Canvas(recorder),
        ip: MusicThemeIp.sleepingKirby,
        track: const Rect.fromLTWH(0, 17, 320, 6),
        active: const Rect.fromLTWH(0, 17, 0, 6),
        direction: TextDirection.ltr,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(320, 40);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(bytes.every((b) => b == 0), true);
      image.dispose();
      picture.dispose();
    });
  });
}
