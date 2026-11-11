import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:mesting_music/features/themes/player_layout_picker.dart';

void main() {
  test('old and unknown preferences keep the original layout', () async {
    for (final value in [null, 'unknown']) {
      SharedPreferences.setMockInitialValues({
        if (value != null) ThemeVisualSettingsController.playerLayoutKey: value,
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      expect(
        c.read(themeVisualSettingsProvider).playerLayout,
        PlayerPageLayout.original,
      );
      c.dispose();
    }
  });

  test(
    'both layouts restore after restart without changing progress decoration',
    () async {
      SharedPreferences.setMockInitialValues({
        'music_progress_style': 'kuromi',
      });
      final prefs = await SharedPreferences.getInstance();
      for (final layout in [
        PlayerPageLayout.spacious,
        PlayerPageLayout.original,
      ]) {
        final c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        await c
            .read(themeVisualSettingsProvider.notifier)
            .setPlayerLayout(layout);
        c.dispose();
        final restored = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        expect(restored.read(themeVisualSettingsProvider).playerLayout, layout);
        expect(
          restored.read(themeVisualSettingsProvider).progressStyle,
          ProgressDecoration.kuromi,
        );
        expect(
          restored
              .read(themeVisualSettingsProvider)
              .copyWith(showIpDecoration: true)
              .playerLayout,
          layout,
        );
        restored.dispose();
      }
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'two illustrated cards save selections at large text, dark=$dark',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.6),
                  ),
                  child: const Center(
                    child: SizedBox(width: 280, child: PlayerLayoutPicker()),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('player-layout-preview-original')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('player-layout-preview-spacious')),
          findsOneWidget,
        );
        expect(find.text('沉浸歌词'), findsNothing);
        for (final layout in [
          PlayerPageLayout.spacious,
          PlayerPageLayout.original,
        ]) {
          await tester.ensureVisible(
            find.byKey(ValueKey('player-layout-${layout.name}')),
          );
          await tester.tap(
            find.byKey(ValueKey('player-layout-${layout.name}')),
          );
          await tester.pumpAndSettle();
          expect(c.read(themeVisualSettingsProvider).playerLayout, layout);
          expect(
            prefs.getString(ThemeVisualSettingsController.playerLayoutKey),
            layout.name,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
