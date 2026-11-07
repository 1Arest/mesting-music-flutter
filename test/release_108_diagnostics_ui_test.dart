import 'dart:io';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'support/no_music_account_fixture.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/performance/frame_timing_probe.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/settings/presentation/frame_diagnostics_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'support/diagnostics_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const export = bool.fromEnvironment('EXPORT_V108_UI');
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (export) {
      final font = ByteData.sublistView(
        await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
      );
      await (FontLoader('V108QA')..addFont(Future.value(font))).load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });
  for (final config in [
    (false, 390.0, 1.0),
    (true, 390.0, 1.0),
    (false, 320.0, 1.6),
    (true, 768.0, 1.0),
  ]) {
    testWidgets('diagnostic idle, recording and drain states $config', (
      tester,
    ) async {
      tester.view.physicalSize = Size(config.$2, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PackageInfo.setMockInitialValues(
        appName: 'Mesting Music',
        packageName: 'com.mesting.music.beta',
        version: '1.0.8',
        buildNumber: '29',
        buildSignature: '',
      );
      // Renderer metadata is a separate optional native boundary. Model its
      // explicit "unknown" response instead of racing a missing host plugin
      // against pumpAndSettle's no-scheduled-frame exit.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const rendererChannel = MethodChannel('com.mesting.music/system_media');
      messenger.setMockMethodCallHandler(
        rendererChannel,
        (_) async => <String, Object>{},
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(rendererChannel, null),
      );
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      var theme = buildMestingTheme(
        musicThemePresetById(config.$1 ? 'classic-dark' : 'classic'),
      );
      if (export) {
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'V108QA'),
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformAccountProvider.overrideWith(NoMusicAccountFixture.new),
            sharedPreferencesProvider.overrideWithValue(preferences),
            diagnosticControllerProvider.overrideWith(
              (ref) async => diagnosticFixture(),
            ),
          ],
          child: LiquidGlassWidgets.wrap(
            adaptiveQuality: false,
            brightnessResolver: Theme.maybeBrightnessOf,
            child: RepaintBoundary(
              key: const ValueKey('diagnostics108'),
              child: MaterialApp(
                theme: theme,
                debugShowCheckedModeBanner: false,
                locale: const Locale('zh', 'CN'),
                supportedLocales: const [Locale('zh', 'CN')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(config.$3)),
                  child: child!,
                ),
                home: const Scaffold(body: FrameDiagnosticsPage()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String state) async {
        if (!export) return;
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('diagnostics108')),
          );
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final directory = Directory(
            '.codex-artifacts/2026-10-28-release108/screens',
          )..createSync(recursive: true);
          File(
            '${directory.path}/${config.$1 ? 'dark' : 'light'}-${config.$2.toInt()}-$state.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
        });
      }

      await capture('idle');
      await tester.scrollUntilVisible(
        find.text('开始采集'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始采集'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始采集'));
      await tester.pumpAndSettle();
      expect(FrameTimingProbe.recording.value, isTrue);
      expect(
        FrameTimingProbe.sessionReport()['environment'],
        containsPair('appVersion', '1.0.8'),
      );
      await tester.tap(find.text('停止采集'));
      await tester.pump();
      expect(find.text('正在收齐报告…'), findsOneWidget);
      expect(FrameTimingProbe.draining.value, isTrue);
      await capture('draining');
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(FrameTimingProbe.draining.value, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
