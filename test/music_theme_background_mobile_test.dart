import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/custom_background_controller.dart';
import 'package:mesting_music/features/themes/music_theme_background.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/classic_music_artwork.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('all theme backgrounds render on a phone without layout errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final preset in musicThemePresets) {
      SharedPreferences.setMockInitialValues({
        'music_theme_preset': preset.id,
        'theme_performance_mode': 'reduced',
        'music_background_strength': .72,
      });
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(preset.id),
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp(
            home: MusicThemeBackground(
              child: ColoredBox(
                color: Colors.transparent,
                child: Center(child: Text(preset.name)),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(tester.takeException(), isNull, reason: preset.id);
      expect(find.text(preset.name), findsOneWidget, reason: preset.id);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('classic light and dark backgrounds render without artwork', (
    tester,
  ) async {
    for (final id in const ['classic', 'classic-dark']) {
      SharedPreferences.setMockInitialValues({
        'music_theme_preset': id,
        'theme_performance_mode': 'reduced',
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(id),
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: const MaterialApp(
            home: MusicThemeBackground(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(ClassicMusicArtwork), findsNothing, reason: id);
      expect(tester.takeException(), isNull, reason: id);
    }
  });

  testWidgets('custom image background overrides the classic appearance', (
    tester,
  ) async {
    const imagePath = 'assets/branding/mesting-mark-master.png';
    SharedPreferences.setMockInitialValues({
      'music_theme_preset': 'classic',
      'custom_background_path': imagePath,
      'custom_background_kind': CustomBackgroundKind.image.name,
      'theme_performance_mode': 'reduced',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(
          home: MusicThemeBackground(child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('custom video background always loops and remains muted', () async {
    final loopingCalls = <bool>[];
    final volumeCalls = <double>[];
    var playCalls = 0;

    await configureMutedThemeBackgroundVideo(
      setLooping: (looping) async => loopingCalls.add(looping),
      setVolume: (volume) async => volumeCalls.add(volume),
      play: () async {
        playCalls += 1;
      },
      foreground: true,
    );

    expect(loopingCalls, [true]);
    expect(volumeCalls, [0]);
    expect(playCalls, 1);
  });
}
