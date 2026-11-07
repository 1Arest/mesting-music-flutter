import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:mesting_music/features/themes/theme_follow_icons.dart';
import 'package:mesting_music/features/themes/theme_gallery_page.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'follow choices use distinct code-native icons in light and dark',
    (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: Row(
                children: [
                  ThemeFollowIcon(kind: ThemeFollowIconKind.progressStyle),
                  ThemeFollowIcon(kind: ThemeFollowIconKind.progressCharacter),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        final styleFinder = find.byKey(
          const ValueKey('follow-theme-progress-style-icon'),
        );
        final characterFinder = find.byKey(
          const ValueKey('follow-theme-progress-character-icon'),
        );
        expect(styleFinder, findsOneWidget);
        expect(characterFinder, findsOneWidget);
        expect(tester.getSize(styleFinder), const Size.square(28));
        expect(tester.getSize(characterFinder), const Size.square(28));
        final stylePaint = tester.widget<CustomPaint>(styleFinder);
        final characterPaint = tester.widget<CustomPaint>(characterFinder);
        expect(
          stylePaint.painter.runtimeType,
          isNot(characterPaint.painter.runtimeType),
        );
        expect(find.text('随'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('dress-up sheet avoids a full-screen live blur layer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDressUpCenterSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(
      () => warmUpDressUpAssets(tester.element(find.text('open'))),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheetSurface = find.byKey(liquidGlassSheetSurfaceKey);
    expect(sheetSurface, findsOneWidget);
    final surface = tester.widget<LiquidGlassSurface>(sheetSurface);
    expect(surface.blurSigma, 0);
    expect(surface.showShadow, isFalse);
    expect(surface.showDecorativeGlow, isFalse);
    expect(surface.surfaceColor, isNull);
    expect(surface.surfaceColorBuilder, isNotNull);
    final surfaceBody = tester.widget<DecoratedBox>(
      find.byKey(liquidGlassSurfaceBodyKey),
    );
    final surfaceDecoration = surfaceBody.decoration as BoxDecoration;
    expect(surfaceDecoration.color?.a, 1);
    expect(surfaceDecoration.gradient, isNull);
    expect(
      find.byKey(const ValueKey('theme-gallery-sheet-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('theme-gallery-glass-panel')),
      findsNothing,
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('dress-up sheet mounts real choices in its first visible frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDressUpCenterSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      find.byKey(const ValueKey('theme-gallery-sheet-content')),
      findsOneWidget,
    );
    expect(find.text('品牌套装'), findsOneWidget);
    expect(find.text('播放器样式'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-style-classic')), findsOneWidget);
  });

  testWidgets('dress-up sheet surface follows theme changes while open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      musicThemePreferenceKey: 'classic',
    });
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: buildMestingTheme(ref.watch(effectiveMusicThemeProvider)),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showDressUpCenterSheet(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(
      () => warmUpDressUpAssets(tester.element(find.text('open'))),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Color sheetColor() {
      final body = tester.widget<DecoratedBox>(
        find.byKey(liquidGlassSurfaceBodyKey),
      );
      return (body.decoration as BoxDecoration).color!;
    }

    final lightSurfaceColor = sheetColor();
    expect(lightSurfaceColor, Colors.white);

    await tester.runAsync(
      () => container.read(musicThemeProvider.notifier).select('classic-dark'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(liquidGlassSheetSurfaceKey), findsOneWidget);
    expect(sheetColor(), const Color(0xFF12151C));
    expect(sheetColor(), isNot(lightSurfaceColor));
  });

  testWidgets('close button stays fixed and settings avoid native choice UI', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: ThemeGalleryPage()),
      ),
    );
    await tester.pumpAndSettle();

    final close = find.byTooltip('关闭装扮');
    expect(close, findsOneWidget);
    final initialPosition = tester.getTopLeft(close);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(
      find.byType(DropdownButtonFormField<ThemePerformanceMode>),
      findsNothing,
    );
    expect(find.text('品牌套装'), findsOneWidget);
    expect(find.text('播放器样式'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-gallery-glass-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('player-style-classic')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('classic-player-turntable-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('classic-player-preview-vinyl')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('classic-player-preview-tonearm')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('player-style-aurora')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-style-cassette')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('player-style-lyricStage')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player-style-real-preview-aurora')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player-style-real-preview-cassette')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player-style-real-preview-lyricStage')),
      findsOneWidget,
    );
    final classicPreview = find.byKey(const ValueKey('classic-theme-preview'));
    expect(classicPreview, findsOneWidget);
    expect(tester.getSize(classicPreview).height, 88);
    expect(find.text('当前：浅色'), findsOneWidget);
    expect(find.text('星环脉冲'), findsOneWidget);
    expect(find.text('液态频谱'), findsOneWidget);
    expect(find.text('磁带电台'), findsNothing);
    expect(find.text('歌词剧场'), findsNothing);
    expect(find.byKey(const ValueKey('brand-style-coral')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('brand-style-morning_mist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('brand-style-midnight_vinyl')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('brand-preview-morning_mist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('brand-preview-midnight_vinyl')),
      findsOneWidget,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('跟随系统'), findsWidgets);
    expect(
      find.byKey(const ValueKey('classic-theme-mode-row')),
      findsOneWidget,
    );
    final lightMode = find.byKey(const ValueKey('theme-mode-classic'));
    final darkMode = find.byKey(const ValueKey('theme-mode-classic-dark'));
    final systemMode = find.byKey(const ValueKey('theme-mode-classic-system'));
    expect(lightMode, findsOneWidget);
    expect(darkMode, findsOneWidget);
    expect(systemMode, findsOneWidget);
    final modeTop = tester.getTopLeft(lightMode).dy;
    expect(tester.getTopLeft(darkMode).dy, modeTop);
    expect(tester.getTopLeft(systemMode).dy, modeTop);
    expect(tester.getSize(lightMode).width, lessThan(130));
    expect(tester.getSize(darkMode).width, tester.getSize(lightMode).width);
    expect(tester.getSize(systemMode).width, tester.getSize(lightMode).width);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(close, findsOneWidget);
    expect(tester.getTopLeft(close), initialPosition);
    expect(find.text('经典圆点'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('follow-theme-progress-style-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('follow-theme-progress-character-icon')),
      findsOneWidget,
    );
    expect(find.byType(ThemeFollowIcon), findsNWidgets(2));
    expect(find.text('随'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(close, findsOneWidget);
    expect(tester.getTopLeft(close), initialPosition);
    expect(find.text('自动推荐'), findsOneWidget);
  });

  testWidgets('brand selection is described as taking effect next launch', (
    tester,
  ) async {
    const brandChannel = MethodChannel('com.mesting.music/brand_style');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      brandChannel,
      (call) async {
        if (call.method == 'applyQueuedBrandStyle') return true;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        brandChannel,
        null,
      ),
    );
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: ThemeGalleryPage()),
      ),
    );
    await tester.pumpAndSettle();
    final morningStyle = find.byKey(const ValueKey('brand-style-morning_mist'));
    await tester.runAsync(() async {
      tester.widget<InkWell>(morningStyle).onTap!();
      for (var attempt = 0; attempt < 100; attempt++) {
        if (preferences.getString('app_brand_style') != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    expect(preferences.getString('app_brand_style'), 'morning_mist');
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('晨雾律动已保存').evaluate().isNotEmpty) break;
    }
    expect(find.text('晨雾律动已保存'), findsOneWidget);
    expect(find.text('下次启动生效'), findsNothing); // Compact HUD no longer repeats explanatory copy.
  });

  testWidgets(
    'classic appearance preview remains compact for dark and system modes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final scenario in [
        (
          preference: 'classic-dark',
          brightness: Brightness.light,
          title: '深色模式',
          status: '已启用',
        ),
        (
          preference: 'classic-system',
          brightness: Brightness.dark,
          title: '跟随系统',
          status: '当前：深色',
        ),
      ]) {
        SharedPreferences.setMockInitialValues({
          'music_theme_preset': scenario.preference,
        });
        final preferences = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              systemBrightnessProvider.overrideWithValue(scenario.brightness),
            ],
            child: const MaterialApp(home: ThemeGalleryPage()),
          ),
        );
        await tester.pumpAndSettle();

        final preview = find.byKey(const ValueKey('classic-theme-preview'));
        expect(preview, findsOneWidget);
        expect(tester.getSize(preview).height, 88);
        expect(find.text(scenario.title), findsOneWidget);
        expect(find.text(scenario.status), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
