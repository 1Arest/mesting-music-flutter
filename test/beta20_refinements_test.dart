import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/app/startup_image_surface.dart';
import 'package:mesting_music/app/startup_visibility_gate.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_reward_day.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/beta_appearance.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/startup_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var qaFont = false;
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('EXPORT_BETA20_SCREENSHOTS')) {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        await (FontLoader(
          'Beta20QA',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
        qaFont = true;
        await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
              rootBundle.load(
                'packages/cupertino_icons/assets/CupertinoIcons.ttf',
              ),
            ))
            .load();
      }
    }
  });

  ThemeData theme(bool dark) {
    final base = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    return qaFont
        ? base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Beta20QA'))
        : base;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('EXPORT_BETA20_SCREENSHOTS')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('beta20-preview')),
      );
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        const String.fromEnvironment('BETA20_SCREENSHOT_DIR'),
      );
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'static artwork gets its full visibility period after presentation, not process start',
    (tester) async {
      var elapsed = false;
      final gate = StartupVisibilityGate(onElapsed: () => elapsed = true);
      await tester.pump(const Duration(seconds: 2)); // Simulated slow decode.
      expect(elapsed, isFalse);
      gate.presented();
      await tester.pump(const Duration(milliseconds: 300));
      gate.presented(); // An extra decoded frame must not restart the hold.
      await tester.pump(const Duration(milliseconds: 199));
      expect(elapsed, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(elapsed, isTrue);
      gate.dispose();
    },
  );

  testWidgets(
    'disposing a startup hold suppresses a stale navigation callback',
    (tester) async {
      var callbacks = 0;
      final gate = StartupVisibilityGate(onElapsed: () => callbacks++);
      gate.presented();
      await tester.pump(const Duration(milliseconds: 250));
      gate.dispose();
      await tester.pump(const Duration(seconds: 1));
      gate.presented();
      expect(callbacks, 0);
    },
  );

  testWidgets(
    'the image presentation callback follows a decoded painted frame only once',
    (tester) async {
      var frames = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StartupImageSurface(
            style: StartupStyle.staticOne,
            onPresented: () => frames++,
          ),
        ),
      );
      expect(frames, 0);
      final context = tester.element(find.byType(StartupImageSurface));
      await tester.runAsync(
        () => precacheImage(
          AssetImage(StartupStyle.staticOne.posterAsset!),
          context,
        ),
      );
      await tester.pump();
      expect(frames, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(frames, 1);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an unavailable static image reports failure instead of waiting forever for a painted frame',
    (tester) async {
      final bundle = _MissingStartupBundle();
      var failures = 0, presentations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultAssetBundle(
            bundle: bundle,
            child: StartupImageSurface(
              style: StartupStyle.staticOne,
              onPresented: () => presentations++,
              onFailed: () => failures++,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          AssetImage(StartupStyle.staticOne.posterAsset!, bundle: bundle),
          tester.element(find.byType(StartupImageSurface)),
          onError: (_, _) {},
        ),
      );
      await tester.pump();
      expect(failures, 1);
      expect(presentations, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    test(
      'Beta functional, favorite and completion colors have separate readable roles ($dark)',
      () {
        final colors = theme(dark).colorScheme;
        expect(colors.primary, BetaAppearance.accent(colors.brightness));
        expect(
          colors.primary,
          isNot(BetaAppearance.favorite(colors.brightness)),
        );
        expect(
          _contrast(colors.primary, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.primary, colors.surfaceContainerLow),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.onPrimary, colors.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(
            BetaAppearance.success(colors.brightness),
            BetaAppearance.successSurface(colors.brightness),
          ),
          greaterThanOrEqualTo(4.5),
        );
        final panel = colors.surfaceContainerLow;
        final channels = [panel.r, panel.g, panel.b]..sort();
        expect((channels.last - channels.first) * 255, lessThanOrEqualTo(6));
      },
      skip: !DistributionChannel.isBeta,
    );

    testWidgets(
      'calendar keeps completion inside the cell and marks today independently ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 300);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('beta20-preview'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme(dark),
              home: Scaffold(
                backgroundColor: theme(dark).colorScheme.surface,
                body: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '2026 年 10 月',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            for (var n = 25; n <= 31; n++)
                              Expanded(
                                child: PlatformRewardDay(
                                  number: n,
                                  month: 10,
                                  checked: n < 28,
                                  today: n == 27,
                                  future: n > 27,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '已签到 3 天',
                          style: TextStyle(
                            color: BetaAppearance.success(
                              theme(dark).brightness,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.bySemanticsLabel('10月27日，今天，已签到'), findsOneWidget);
        final today = tester.widget<Container>(
          find.byKey(const ValueKey('reward-day-27')),
        );
        expect((today.decoration! as BoxDecoration).border, isNotNull);
        for (final icon in find.byIcon(CupertinoIcons.check_mark).evaluate()) {
          final checkRect = tester.getRect(
            find.byElementPredicate((e) => identical(e, icon)),
          );
          final day = find.ancestor(
            of: find.byElementPredicate((e) => identical(e, icon)),
            matching: find.byType(PlatformRewardDay),
          );
          expect(tester.getRect(day).contains(checkRect.topLeft), isTrue);
          expect(tester.getRect(day).contains(checkRect.bottomRight), isTrue);
        }
        expect(tester.takeException(), isNull);
        await capture(tester, 'calendar-${dark ? 'dark' : 'light'}-large-text');
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final accessory in [false, true]) {
    testWidgets(
      'search field receives taps above the keyboard with accessory=$accessory',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final focus = FocusNode();
        final text = TextEditingController(text: '薛之谦');
        var underlyingTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme(true),
            home: GlassScaffold(
              edgeFade: false,
              resizeToAvoidBottomInset: false,
              body: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => underlyingTaps++,
                child: const SizedBox.expand(),
              ),
              bottomBar: BetaMusicBottomBar(
                selectedIndex: 0,
                onTabSelected: (_) {},
                isSearchActive: true,
                accessory: accessory
                    ? const SizedBox(height: 50, child: Text('当前播放'))
                    : null,
                accessoryEnabled: false,
                searchConfig: GlassSearchBarConfig(
                  onSearchToggle: (_) {},
                  controller: text,
                  focusNode: focus,
                  autoFocusOnExpand: false,
                  expandWhenActive: true,
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        focus.requestFocus();
        await tester.pump();
        for (final inset in [100.0, 280.0, 180.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          final field = find.byType(CupertinoTextField);
          final rect = tester.getRect(field);
          expect(rect.bottom, lessThanOrEqualTo(844 - inset));
          await tester.tapAt(rect.center);
          await tester.pump(const Duration(milliseconds: 350));
          expect(
            underlyingTaps,
            0,
            reason:
                'The painted field must stay inside every ancestor hit region during IME changes.',
          );
          expect(focus.hasFocus, isTrue);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        focus.dispose();
        text.dispose();
      },
    );
  }
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

class _MissingStartupBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => key == StartupStyle.staticOne.posterAsset
      ? Future<ByteData>.error(StateError('unavailable test image'))
      : rootBundle.load(key);
}
