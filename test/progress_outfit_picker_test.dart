import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/player/presentation/shinchan_progress_walker.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/progress_decoration_picker.dart';
import 'package:mesting_music/features/themes/progress_outfit_picker.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'support/ui_fix_capture.dart';

void main() {
  setUpAll(initializeUiFixCapture);

  for (final spec in [
    (width: 390.0, scale: 1.0, dark: true),
    (width: 320.0, scale: 1.0, dark: false),
    (width: 390.0, scale: 2.0, dark: true),
    (width: 820.0, scale: 1.3, dark: false),
  ]) {
    testWidgets(
      'outfits preserve old mixes, pair explicitly and customize $spec',
      (tester) async {
        tester.view.physicalSize = Size(spec.width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({
          'music_progress_style': 'kuromi',
          'music_progress_character': 'myMelody',
          'music_shinchan_progress_weather': 'storm',
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);
        var theme = buildMestingTheme(
          musicThemePresetById(spec.dark ? 'classic-dark' : 'classic'),
        );
        if (uiFixCaptureDirectory.isNotEmpty) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'UiFixCJK'),
          );
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(spec.scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: RepaintBoundary(
                key: uiFixCaptureKey,
                child: const Scaffold(
                  body: SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: ProgressOutfitPicker(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProgressDecorationPicker), findsOneWidget);
        expect(
          tester
              .widget<ProgressDecorationPicker>(
                find.byType(ProgressDecorationPicker),
              )
              .character,
          true,
        );
        expect(prefs.getString('music_progress_style'), 'kuromi');
        expect(prefs.getString('music_progress_character'), 'myMelody');
        expect(find.text('美乐蒂 · 库洛米轨道'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('progress-track-kuromi')),
          findsNothing,
        );
        await captureUiFix(
          tester,
          'outfit-roles-${spec.width.toInt()}-${spec.scale}-${spec.dark}',
        );

        for (final value in ProgressDecoration.values.where(
          (v) =>
              !DistributionChannel.isBeta ||
              v != ProgressDecoration.followTheme,
        )) {
          final choice = find.byKey(
            ValueKey('progress-character-${value.name}'),
          );
          await tester.ensureVisible(choice);
          await tester.pumpAndSettle();
          await tester.tap(choice);
          await tester.pumpAndSettle();
          final selected = container.read(themeVisualSettingsProvider);
          expect(selected.progressCharacter, value);
          expect(selected.progressStyle, value);
          expect(prefs.getString('music_progress_character'), value.name);
          expect(prefs.getString('music_progress_style'), value.name);
          expect(tester.takeException(), isNull);
        }

        final customize = find.byKey(
          const ValueKey('progress-outfit-customize'),
        );
        await tester.ensureVisible(customize);
        await tester.pumpAndSettle();
        await tester.tap(customize);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ProgressDecorationPicker>(
                find.byType(ProgressDecorationPicker),
              )
              .character,
          false,
        );
        expect(
          find.byKey(const ValueKey('progress-character-nailong')),
          findsNothing,
        );
        expect(
          find.byType(ProgressTrackPreview),
          findsNWidgets(DistributionChannel.isBeta ? 14 : 15),
        );
        for (final value in ProgressDecoration.values.where(
          (v) =>
              !DistributionChannel.isBeta ||
              v != ProgressDecoration.followTheme,
        )) {
          final choice = find.byKey(ValueKey('progress-track-${value.name}'));
          await tester.ensureVisible(choice);
          await tester.pumpAndSettle();
          await tester.tap(choice);
          await tester.pumpAndSettle();
          final selected = container.read(themeVisualSettingsProvider);
          expect(selected.progressStyle, value);
          expect(selected.progressCharacter, ProgressDecoration.nailong);
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('progress-outfit-preview')),
        );
        await tester.pumpAndSettle();
        await captureUiFix(
          tester,
          'outfit-tracks-${spec.width.toInt()}-${spec.scale}-${spec.dark}',
        );

        // Return to roles and keep the independently saved weather when applying
        // a fresh Shinchan pairing. Custom track edits must not clear weather.
        await tester.tap(customize);
        await tester.pumpAndSettle();
        final shinchan = find.byKey(
          const ValueKey('progress-character-shinchan'),
        );
        await tester.ensureVisible(shinchan);
        await tester.pumpAndSettle();
        await tester.tap(shinchan);
        await tester.pumpAndSettle();
        expect(
          container.read(themeVisualSettingsProvider).shinchanWeather,
          ShinchanProgressWeather.storm,
        );
        expect(
          find.byKey(const ValueKey('shinchan-weather-storm')),
          DistributionChannel.isBeta ? findsOneWidget : findsNothing,
        );

        // A later custom mix survives closing/reopening the settings container.
        await container
            .read(themeVisualSettingsProvider.notifier)
            .setProgressStyle(ProgressDecoration.sleepingKirby);
        await tester.pumpAndSettle();
        final restored = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        expect(
          restored.read(themeVisualSettingsProvider).progressStyle,
          ProgressDecoration.sleepingKirby,
        );
        expect(
          restored.read(themeVisualSettingsProvider).progressCharacter,
          ProgressDecoration.shinchan,
        );
        restored.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
