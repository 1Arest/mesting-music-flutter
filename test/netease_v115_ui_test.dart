import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/music_platform/netease/netease_membership_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_settings_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_options.dart';
import 'package:mesting_music/features/music_platform/netease/netease_listening_reporter.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'netease_v115_sources_test.dart' show TestAccount;

void main() {
  // Marquee headers are intentionally continuous. Bound frame advancement
  // rather than waiting for every animation in the whole tree to become idle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> reveal(WidgetTester tester, Finder target) =>
      tester.scrollUntilVisible(
        target,
        220,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_NETEASE_115')) {
      for (final family in [
        'MestingQA',
        'Roboto',
        'sans-serif',
        'Noto Sans SC',
        'Microsoft YaHei',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });

  Future<ProviderContainer> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    bool compact = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(TestAccount.new),
        savedKugouSessionProvider.overrideWith((ref) async => null),
        neteaseListeningJournalProvider.overrideWith((ref) => Stream.value([])),
      ],
    );
    addTearDown(c.dispose);
    await c.read(platformAccountProvider.future);
    tester.view.physicalSize = compact
        ? const Size(320, 650)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'MestingQA'),
            // ListTileTheme can carry a color-only TextStyle, which otherwise
            // inherits the test runner's Ahem face instead of Android's CJK font.
            // Match the other QA paragraphs without shipping a desktop font.
            listTileTheme: theme.listTileTheme.copyWith(
              subtitleTextStyle: theme.listTileTheme.subtitleTextStyle
                  ?.copyWith(fontFamily: 'MestingQA'),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(compact ? 1.5 : 1)),
            child: RepaintBoundary(
              key: const ValueKey('v115-capture'),
              child: child!,
            ),
          ),
          home: Scaffold(body: page),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    return c;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_NETEASE_115')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('v115-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('.codex-artifacts/2026-10-29-release115/ui/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets(
        'membership and UID scope render dark=$dark compact=$compact',
        (tester) async {
          await mount(
            tester,
            const NeteaseMembershipPage(),
            dark: dark,
            compact: compact,
          );
          expect(find.text('至尊SVIP'), findsOneWidget);
          await capture(tester, 'membership-$dark-$compact');
          await reveal(
            tester,
            find.byKey(const ValueKey('local-svip-save-uids')),
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
          await capture(tester, 'membership-uids-$dark-$compact');
        },
      );
      testWidgets(
        'source settings and unavailable entries render dark=$dark compact=$compact',
        (tester) async {
          await mount(
            tester,
            const NeteasePlaybackSettingsPage(),
            dark: dark,
            compact: compact,
          );
          expect(find.text('至尊SVIP 已启用'), findsOneWidget);
          await capture(tester, 'settings-$dark-$compact');
          await reveal(tester, find.text('GD Studio'));
          await settle(tester);
          expect(tester.takeException(), isNull);
          await capture(tester, 'settings-sources-$dark-$compact');
          await reveal(tester, find.text('音源诊断日志'));
          await settle(tester);
          expect(tester.takeException(), isNull);
          await capture(tester, 'settings-cache-$dark-$compact');
        },
      );
    }
  }
  testWidgets(
    'membership toggle saves per account and enables fallback on activation',
    (tester) async {
      final c = await mount(tester, const NeteaseMembershipPage());
      final toggle = find.widgetWithText(SwitchListTile, '当前账号启用至尊SVIP');
      await tester.tap(toggle);
      await settle(tester);
      expect(c.read(neteaseLocalSvipProvider), isFalse);
      await c.read(neteaseFallbackEnabledProvider.notifier).setEnabled(false);
      await tester.tap(toggle);
      await settle(tester);
      expect(c.read(neteaseLocalSvipProvider), isTrue);
      expect(c.read(neteaseFallbackEnabledProvider), isTrue);
      (c.read(platformAccountProvider.notifier) as TestAccount).replace('8');
      await settle(tester);
      expect(find.text('请使用当前网易云账号重新打开'), findsOneWidget);
    },
  );
  testWidgets('membership glass button cancels held drag without saving', (
    tester,
  ) async {
    final c = await mount(tester, const NeteaseMembershipPage());
    final button = find.byKey(const ValueKey('local-svip-save-uids'));
    await reveal(tester, button);
    await settle(tester);
    final lens = find.descendant(
      of: button,
      matching: find.byType(AdaptiveGlass),
    );
    final width = tester.getRect(lens).width;
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 180));
    await gesture.moveBy(const Offset(0, -60));
    await gesture.moveBy(const Offset(0, -35));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<AdaptiveGlass>(lens).glowIntensity, 0);
    expect(tester.getRect(lens).width, closeTo(width, 1));
    expect(
      c
          .read(sharedPreferencesProvider)
          .containsKey(NeteaseLocalMembershipController.key),
      isFalse,
    );
    await capture(tester, 'membership-held-drag');
    await gesture.up();
    await settle(tester);
  });
  testWidgets(
    'UID field saves and diagnostics is an explicit on-device action',
    (tester) async {
      final c = await mount(tester, const NeteaseMembershipPage());
      await reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), '7, 8');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      await reveal(tester, find.byKey(const ValueKey('local-svip-save-uids')));
      await tester.tap(find.byKey(const ValueKey('local-svip-save-uids')));
      await settle(tester);
      expect(c.read(neteaseLocalMembershipSettingsProvider).allowedUids, {
        '7',
        '8',
      });
    },
  );
}
