import 'package:mesting_music/shared/widgets/beta_control_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/app/branded_launch_screen.dart';
import 'package:mesting_music/app/startup_image_surface.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/queue/presentation/playback_mode_button.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/startup_style.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:mesting_music/shared/widgets/beta_selection_controls.dart';
import 'support/ui_fix_capture.dart';

void main() {
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });
  for (final size in [
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    for (final style in StartupStyle.values) {
      testWidgets(
        'startup ${style.id} adapts to ${size.width}x${size.height}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            RepaintBoundary(
              key: uiFixCaptureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: style == StartupStyle.classic
                    ? const MestingBrandedLaunchScreen(forceCoral: true)
                    : StartupImageSurface(style: style),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
          if (style != StartupStyle.classic) {
            final image = tester.widget<Image>(find.byType(Image));
            expect(
              image.image,
              AssetImage(
                style.posterForWindow(width: size.width, height: size.height)!,
              ),
            );
            expect(
              image.fit,
              size.shortestSide >= 600 ? BoxFit.cover : BoxFit.contain,
            );
          } else {
            final rect = tester.getRect(
              find.byKey(const ValueKey('mesting-launch-lockup')),
            );
            expect(rect.width, lessThanOrEqualTo(size.width));
            expect(rect.height, lessThan(size.height * .75));
            if (size.shortestSide >= 600) expect(rect.height, greaterThan(360));
          }
          expect(tester.takeException(), isNull);
          await captureUiFix(
            tester,
            'startup-${style.id}-${size.width.toInt()}x${size.height.toInt()}',
          );
        },
      );
    }
  }

  for (final dark in [false, true]) {
    testWidgets(
      'Apple controls and anchored queue menu fit large text dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var mode = PlaybackMode.list, selected = false, enabled = true;
        var theme = buildMestingTheme(
          musicThemePresetById(dark ? 'classic-dark' : 'classic'),
        );
        if (uiFixCaptureDirectory.isNotEmpty) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'UiFixCJK'),
            listTileTheme: theme.listTileTheme.copyWith(
              titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
                fontFamily: 'UiFixCJK',
              ),
              subtitleTextStyle: theme.listTileTheme.subtitleTextStyle
                  ?.copyWith(fontFamily: 'UiFixCJK'),
            ),
          );
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              qishuiNavigationProvider.overrideWithValue(false),
            ],
            child: RepaintBoundary(
              key: uiFixCaptureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(1.6)),
                  child: child!,
                ),
                home: Scaffold(
                  backgroundColor: theme.colorScheme.surface,
                  body: StatefulBuilder(
                    builder: (context, update) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 30),
                          const Text(
                            '待播列表',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: PlaybackModeButton(
                              mode: mode,
                              onSelected: (v) => update(() => mode = v),
                            ),
                          ),
                          const SizedBox(height: 24),
                          BetaSwitchTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('随机播放'),
                            value: enabled,
                            onChanged: (v) => update(() => enabled = v),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: BetaSelectionChip(
                              label: const Text('最近一周'),
                              selected: selected,
                              onSelected: (v) => update(() => selected = v),
                            ),
                          ),
                          BetaActionButton(
                            red: true,
                            onPressed: () {},
                            child: const Text('播放全部'),
                          ),
                          const BetaSwitchTile(
                            title: Text('暂不可用'),
                            value: false,
                            onChanged: null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('最近一周'));
        await tester.pumpAndSettle();
        expect(selected, isTrue);
        if (DistributionChannel.isBeta) {
          expect(find.byType(CupertinoSwitch), findsNWidgets(2));
        }
        await captureUiFix(tester, 'apple-selection-controls-$dark');
        await tester.tap(find.byKey(const ValueKey('queue-playback-mode')));
        await tester.pumpAndSettle();
        if (DistributionChannel.isBeta) {
          expect(find.byType(BetaGlassMenuSurface), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await captureUiFix(tester, 'apple-queue-mode-$dark');
        await tester.tap(find.byKey(const ValueKey('queue-mode-random')));
        await tester.pumpAndSettle();
        expect(mode, PlaybackMode.random);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'shared actions work without constructing any account or settings owner',
    (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: BetaControlScope(
                apple: true,
                child: BetaActionButton(
                  onPressed: () => pressed++,
                  child: const Text('独立操作'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('独立操作'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Qishui selection controls retain their previous presentation', (
    tester,
  ) async {
    await preferences.setString('beta_active_account_v2', 'qishui');
    await tester.pumpWidget(
      BetaControlScope(
        apple: false,
        child: ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Column(
                children: [
                  BetaSelectionChip(
                    label: const Text('汽水原控件'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  BetaSwitchTile(
                    title: const Text('汽水原开关'),
                    value: true,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ChoiceChip), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });
}
