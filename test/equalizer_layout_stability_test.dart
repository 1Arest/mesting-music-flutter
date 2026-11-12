import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/music_equalizer.dart';
import 'package:mesting_music/core/audio/music_equalizer_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/settings/presentation/music_equalizer_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';

import 'release_103_audio_test.dart' show TestEqualizerBridge;
import 'support/ui_fix_capture.dart';

void main() {
  setUpAll(initializeUiFixCapture);

  for (final spec in [
    (width: 390.0, scale: 1.0, dark: true),
    (width: 320.0, scale: 1.0, dark: false),
    (width: 390.0, scale: 2.0, dark: true),
    (width: 820.0, scale: 1.3, dark: false),
  ]) {
    testWidgets('preset and band positions stay stable $spec', (tester) async {
      tester.view.physicalSize = Size(spec.width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final bridge = TestEqualizerBridge();
      final sessions = StreamController<int?>.broadcast();
      final controller = MusicEqualizerController(
        bridge: bridge,
        preferences: prefs,
        sessions: sessions.stream,
        currentSession: 7,
      );
      final host = BetaBottomSearchHost(location: '/', openMusicSearch: () {});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicEqualizerProvider.overrideWithValue(controller),
          usesNeteaseProvider.overrideWithValue(false),
        ],
      );
      addTearDown(() async {
        container.dispose();
        controller.dispose();
        await sessions.close();
        host.dispose();
      });
      await controller.selectPreset('正常');
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
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(spec.scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: uiFixCaptureKey,
              child: BetaBottomSearchScope(
                host: host,
                child: const MusicEqualizerPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final band = find.byKey(const ValueKey('music-equalizer-band-0'));
      for (final name in musicEqualizerPresets.keys) {
        final choice = find.byKey(ValueKey('equalizer-preset-$name'));
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        final beforeChoices = [
          for (final n in musicEqualizerPresets.keys)
            tester.getRect(find.byKey(ValueKey('equalizer-preset-$n'))),
        ];
        final beforeBand = tester.getRect(band);
        await tester.tap(choice);
        // Check the binding frame as well as the final state; a brief relayout
        // while awaiting the native bridge is visible as a jump on a phone.
        await tester.pump();
        expect(tester.getRect(band), beforeBand, reason: 'binding frame $name');
        await tester.pumpAndSettle();
        expect(controller.state.preset, name);
        expect(
          tester.getRect(band),
          beforeBand,
          reason: 'first band after $name',
        );
        expect([
          for (final n in musicEqualizerPresets.keys)
            tester.getRect(find.byKey(ValueKey('equalizer-preset-$n'))),
        ], beforeChoices);
        expect(tester.takeException(), isNull);
      }
      expect(bridge.applied.last.levels, controller.state.levels);
      await tester.ensureVisible(band);
      await tester.pumpAndSettle();
      final beforeDrag = controller.state.levels.first;
      await tester.drag(band, const Offset(-25, 0));
      await tester.pumpAndSettle();
      expect(controller.state.levels.first, isNot(beforeDrag));
      expect(controller.state.preset, '自定义');
      // Capture the initial scroll position for a comparable page overview.
      await tester.ensureVisible(
        find.byKey(const ValueKey('music-equalizer-enabled')),
      );
      await tester.pumpAndSettle();
      await captureUiFix(
        tester,
        'equalizer-${spec.width.toInt()}-${spec.scale}-${spec.dark}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
