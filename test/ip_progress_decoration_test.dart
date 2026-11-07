import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/player/presentation/ip_progress_decoration.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

void main() {
  test('every IP progress rail has an independent accent', () {
    final colors = MusicThemeIp.values.map(progressTrackColorForIp).toSet();

    expect(colors, hasLength(MusicThemeIp.values.length));
  });

  test(
    'companion center follows the exact thumb at beginning middle and end',
    () {
      for (final progress in [0.0, .5, 1.0]) {
        for (final width in [28.0, 56.0]) {
          final left = progressCompanionLeft(
            progress: progress,
            availableWidth: 320,
            companionWidth: width,
          );
          expect(left + width / 2, closeTo(progress * 320, .001));
        }
      }
      expect(
        progressCompanionSize(MusicThemeIp.helloKitty),
        const Size(24, 24),
      );
      expect(progressCompanionSize(MusicThemeIp.kuromi), const Size(24, 24));
    },
  );
  testWidgets('compact heads have no medallion crest ribbons or extra dot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Row(
            children: [
              IpProgressCompanion(ip: MusicThemeIp.helloKitty, playing: true),
              IpProgressCompanion(ip: MusicThemeIp.kuromi, playing: true),
            ],
          ),
        ),
      ),
    );
    for (final key in [
      'hello-kitty-progress-character',
      'kuromi-progress-character',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      expect(tester.getSize(find.byKey(ValueKey(key))), const Size(24, 24));
    }
    for (final key in [
      'hello-kitty-progress-ribbon-medallion',
      'kuromi-progress-mischief-crest',
      'ip-progress-leading-dot-helloKitty',
      'ip-progress-leading-dot-kuromi',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('themed progress rails paint at empty, partial and full values', (
    tester,
  ) async {
    for (final ip in [
      MusicThemeIp.shinchan,
      MusicThemeIp.helloKitty,
      MusicThemeIp.kuromi,
    ]) {
      for (final value in [0.0, .5, 1.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: ipProgressTrackHeight,
                      trackShape: IpProgressTrackShape(ip: ip),
                      activeTrackColor: progressTrackColorForIp(ip),
                      inactiveTrackColor: Colors.white24,
                      thumbShape: SliderComponentShape.noThumb,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(value: value, onChanged: (_) {}),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$ip at $value');
      }
    }
  });
}
