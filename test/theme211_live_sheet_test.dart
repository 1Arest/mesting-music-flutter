import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_application_theme.dart';
import 'package:mesting_music/features/themes/music_theme_tokens.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:mesting_music/features/themes/theme_gallery_page.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/ui_fix_capture.dart';

class _Host extends ConsumerWidget {
  const _Host({this.localBrightness});
  final Brightness? localBrightness;
  @override
  Widget build(BuildContext context, WidgetRef ref) => RepaintBoundary(
    key: uiFixCaptureKey,
    child: MaterialApp(
      theme: buildMestingTheme(ref.watch(effectiveMusicThemeProvider)),
      builder: (context, child) =>
          MusicApplicationTheme(data: Theme.of(context), child: child!),
      home: Builder(
        builder: (context) {
          final button = Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDressUpCenterSheet(context),
              child: const Text('open'),
            ),
          );
          return Scaffold(
            body: Center(
              // Mirror a page-owned Theme between the opener and Navigator. It
              // starts with the app palette, but capture freezes that old Widget.
              child: Theme(
                data: localBrightness == null
                    ? Theme.of(context)
                    : ThemeData(brightness: localBrightness!),
                child: button,
              ),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester) async {
  // Vinyl previews intentionally keep rotating; settling all tickers would
  // hide this real route behind a timeout rather than exercise its state.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 8)),
    );
  }
}

void _expectSheet(WidgetTester tester, Brightness brightness) {
  final context = tester.element(find.byKey(liquidGlassSheetSurfaceKey));
  expect(Theme.of(context).brightness, brightness);
  final decoration =
      tester
              .widget<DecoratedBox>(find.byKey(liquidGlassSurfaceBodyKey))
              .decoration
          as BoxDecoration;
  expect(
    decoration.color,
    MusicThemeTokens.forBrightness(brightness).glassStrong.withValues(alpha: 1),
  );
  expect(
    context.musicThemeTokens.textPrimary,
    MusicThemeTokens.forBrightness(brightness).textPrimary,
  );
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });
  Future<void> open(
    WidgetTester tester, {
    Brightness? local,
    String initial = 'classic',
  }) async {
    SharedPreferences.setMockInitialValues({'music_theme_preset': initial});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: _Host(localBrightness: local),
      ),
    );
    await tester.tap(find.text('open'));
    await _frames(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets(
    'open dress-up sheet follows light dark and system without losing route or scroll',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await open(tester);
      _expectSheet(tester, Brightness.light);
      final panel = find.byKey(const ValueKey('theme-gallery-sheet-content'));
      final route = ModalRoute.of(tester.element(panel));
      final scroll = find
          .descendant(of: panel, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('theme-mode-classic-dark')),
        180,
        scrollable: scroll,
      );
      // Stable has additional brand choices above the same controls. Bring the
      // whole target to the middle before tapping, rather than accepting a
      // partially laid-out card whose center remains below the viewport.
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('theme-mode-classic-dark'))),
        alignment: .5,
      );
      await _frames(tester);
      final scrollState = tester.state<ScrollableState>(scroll);
      final position = scrollState.position;
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('theme-mode-classic-dark')));
      await _frames(tester);
      _expectSheet(tester, Brightness.dark);
      await captureUiFix(
        tester,
        'dress-up-switched-dark',
        settleAnimations: false,
      );
      expect(
        identical(tester.state<ScrollableState>(scroll), scrollState),
        isTrue,
      );
      expect(
        tester.state<ScrollableState>(scroll).position.pixels,
        closeTo(offset, 1),
      );
      expect(ModalRoute.of(tester.element(panel)), same(route));
      await tester.tap(find.byKey(const ValueKey('theme-mode-classic')));
      await _frames(tester);
      _expectSheet(tester, Brightness.light);
      await captureUiFix(
        tester,
        'dress-up-switched-light',
        settleAnimations: false,
      );
      await tester.tap(find.byKey(const ValueKey('theme-mode-classic-system')));
      await _frames(tester);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await _frames(tester);
      _expectSheet(tester, Brightness.dark);
      await captureUiFix(
        tester,
        'dress-up-system-dark',
        settleAnimations: false,
      );
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      await _frames(tester);
      _expectSheet(tester, Brightness.light);
      await captureUiFix(
        tester,
        'dress-up-system-light',
        settleAnimations: false,
      );
      expect(ModalRoute.of(tester.element(panel)), same(route));
      expect(tester.takeException(), isNull);
    },
  );
  for (final app in Brightness.values) {
    testWidgets(
      'dress-up appearance ignores opposite player-local palette app=$app',
      (tester) async {
        await open(
          tester,
          initial: app == Brightness.dark ? 'classic-dark' : 'classic',
          local: app == Brightness.dark ? Brightness.light : Brightness.dark,
        );
        _expectSheet(tester, app);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
