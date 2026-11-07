import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderView;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_settings.dart';
import 'package:liquid_glass_widgets/src/engine/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_widgets/src/engine/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/app/startup_image_surface.dart';
import 'package:mesting_music/app/startup_video_surface.dart';
import 'package:mesting_music/features/themes/startup_style.dart';
import 'package:mesting_music/features/player/presentation/shinchan_progress_walker.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/auth/presentation/beta_entry_coordinator.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecoveryFailure extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      throw const FormatException('Local recovery test');
}

class _NoRecoveryLegacyAccount extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

/// Tests the renderer's layout contract without substituting host software
/// pixels for the Android Impeller validation performed on the real device.
class _Lens extends LiquidGlassRenderObject {
  _Lens()
    : super(
        link: GeometryRenderLink(),
        settings: const LiquidGlassSettings(),
        devicePixelRatio: 1,
      );
  @override
  Size get desiredMatteSize => switch (owner?.rootNode) {
    RenderView view => view.size,
    RenderBox box => box.size,
    _ => Size.zero,
  };
  @override
  Matrix4 get matteTransform => Matrix4.identity();
  void acknowledgeGeometry() => needsGeometryUpdate = false;
  bool get geometryInvalidated => needsGeometryUpdate;
  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect bounds,
  ) {}
}

class _LensHost extends LeafRenderObjectWidget {
  const _LensHost();
  @override
  RenderObject createRenderObject(BuildContext context) => _Lens();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'cold recovery errors use readable Material text and retry actions',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mesting_first_launch_auth_completed_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            platformAccountProvider.overrideWith(_RecoveryFailure.new),
            authControllerProvider.overrideWith(_NoRecoveryLegacyAccount.new),
          ],
          child: MaterialApp(
            builder: (context, child) => BetaEntryCoordinator(child: child!),
            home: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final message = find.text('账号暂未恢复，登录信息已保留');
      expect(message, findsOneWidget);
      final style = DefaultTextStyle.of(tester.element(message)).style;
      expect(style.fontSize, lessThan(20));
      expect(style.decoration, isNot(TextDecoration.underline));
      expect(find.text('重试恢复'), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Beta upgrade chooses image one once and then respects explicit changes',
    () async {
      SharedPreferences.setMockInitialValues({
        startupStylePreferenceKey: StartupStyle.companionsTwo.id,
      });
      final prefs = await SharedPreferences.getInstance();
      await migrateBeta19StartupStyle(prefs);
      expect(
        savedStartupStyle(prefs),
        DistributionChannel.isBeta
            ? StartupStyle.staticOne
            : StartupStyle.companionsTwo,
      );
      await prefs.setString(
        startupStylePreferenceKey,
        StartupStyle.staticTwo.id,
      );
      await migrateBeta19StartupStyle(prefs);
      expect(savedStartupStyle(prefs), StartupStyle.staticTwo);
      await prefs.setString(
        startupStylePreferenceKey,
        StartupStyle.companionsOne.id,
      );
      await migrateBeta19StartupStyle(prefs);
      expect(savedStartupStyle(prefs), StartupStyle.companionsOne);
    },
  );

  testWidgets(
    'both static startup images preserve full artwork without a decoder',
    (tester) async {
      for (final style in [StartupStyle.staticOne, StartupStyle.staticTwo]) {
        await tester.pumpWidget(
          MaterialApp(home: StartupImageSurface(style: style)),
        );
        await tester.pump();
        expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
        expect(style.videoAsset, isNull);
        expect(find.byType(StartupVideoSurface), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
      }
    },
  );

  test(
    'all seven weather choices persist independently of progress and theme',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      for (final weather in ShinchanProgressWeather.values) {
        var c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        await c
            .read(themeVisualSettingsProvider.notifier)
            .setShinchanWeather(weather);
        await c
            .read(themeVisualSettingsProvider.notifier)
            .setProgressCharacter(ProgressDecoration.kuromi);
        await c
            .read(themeVisualSettingsProvider.notifier)
            .setProgressCharacter(ProgressDecoration.shinchan);
        await c
            .read(themeVisualSettingsProvider.notifier)
            .setProgressStyle(ProgressDecoration.helloKitty);
        c.dispose();
        c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        expect(c.read(themeVisualSettingsProvider).shinchanWeather, weather);
        expect(
          c.read(themeVisualSettingsProvider).progressStyle,
          ProgressDecoration.helloKitty,
        );
        expect(
          c.read(themeVisualSettingsProvider).progressCharacter,
          ProgressDecoration.shinchan,
        );
        c.dispose();
      }
    },
  );

  test('missing and future weather values preserve legacy fallback', () {
    expect(ShinchanProgressWeather.fromName(null), isNull);
    expect(ShinchanProgressWeather.fromName('future-value'), isNull);
    expect(const ThemeVisualSettings().shinchanWeather, isNull);
  });

  testWidgets('identical or same-size layouts reuse the lens matte', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Center(child: SizedBox(width: 100, height: 40, child: _LensHost())),
    );
    final lens = tester.renderObject<_Lens>(find.byType(_LensHost));
    lens.acknowledgeGeometry();
    lens.layout(lens.constraints);
    expect(
      lens.geometryInvalidated,
      isFalse,
      reason:
          'A parent checking cached layout must not allocate another geometry texture.',
    );
    lens.markNeedsLayout();
    await tester.pump();
    expect(lens.geometryInvalidated, isFalse);
    // A genuine size change still invalidates geometry before the next paint.
    lens.layout(const BoxConstraints.tightFor(width: 120, height: 40));
    expect(lens.geometryInvalidated, isTrue);
  });

  testWidgets(
    'enabled ImageFiltered changes the glass pass without moving it',
    (tester) async {
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: ValueListenableBuilder<bool>(
                valueListenable: enabled,
                builder: (_, value, child) => ImageFiltered(
                  enabled: value,
                  imageFilter: ui.ImageFilter.blur(sigmaX: 1),
                  child: child,
                ),
                child: const _LensHost(),
              ),
            ),
          ),
        ),
      );
      final lens = tester.renderObject<_Lens>(find.byType(_LensHost));
      expect(
        lens.enclosingBackdropPassRect(),
        tester.getRect(find.byType(ImageFiltered)),
      );
      enabled.value = false;
      await tester.pump();
      expect(lens.enclosingBackdropPassRect(), isNull);
    },
  );

  testWidgets(
    'retained glass checks pass changes even at an identical transform',
    (tester) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(width: 100, height: 40, child: _LensHost()),
        ),
      );
      final lens = tester.renderObject<_Lens>(find.byType(_LensHost));
      var updates = 0;
      final layer = GeometryTransformTrackingLayer()
        ..renderObject = lens
        ..updateAtComposite = () {
          updates++;
          return true;
        };
      for (var i = 0; i < 2; i++) {
        final builder = ui.SceneBuilder();
        layer.addToScene(builder);
        builder.build().dispose();
      }
      expect(updates, 2);
      layer.dispose();
    },
  );

  testWidgets('cached offscreen weather previews stop their tickers', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 160,
            child: ListView(
              controller: scroll,
              cacheExtent: 1000,
              children: const [
                SizedBox(height: 400),
                ShinchanProgressWalker(
                  presetId: 'classic',
                  weather: ShinchanProgressWeather.storm,
                  playing: true,
                ),
                SizedBox(height: 400),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    scroll.jumpTo(380);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion retains the selected weather without tickers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(
            child: ShinchanProgressWalker(
              presetId: 'classic',
              weather: ShinchanProgressWeather.storm,
              playing: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(
      tester
          .widget<ShinchanProgressWalker>(find.byType(ShinchanProgressWalker))
          .weather,
      ShinchanProgressWeather.storm,
    );
  });
}
