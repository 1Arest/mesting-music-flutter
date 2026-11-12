import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/experience/presentation/music_functions_page.dart';
import 'package:mesting_music/features/experience/presentation/player_glass_button.dart';
import 'package:mesting_music/features/experience/presentation/player_more_menu.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/listening_sync_page.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_providers.dart';
import 'package:mesting_music/features/recognition/song_recognition_page.dart';
import 'package:mesting_music/features/settings/presentation/frame_diagnostics_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const export = bool.fromEnvironment('EXPORT_V107_UI');
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
    if (!export) return;
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
    );
    for (final family in [
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'V107QA',
      'Noto Sans SC',
      'Microsoft YaHei',
      'sans-serif',
    ]) {
      await (FontLoader(family)..addFont(Future.value(font))).load();
    }
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!export) return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('v107-ui-capture')),
          )
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        const String.fromEnvironment('V107_UI_SCREENSHOT_DIR'),
      );
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final config in [
    (false, const Size(390, 844), 1.0, 'light'),
    (true, const Size(390, 844), 1.0, 'dark'),
    (false, const Size(320, 740), 1.6, 'small-large'),
    (true, const Size(768, 1024), 1.0, 'tablet'),
  ]) {
    testWidgets(
      'new feature surfaces and retained liquid controls ${config.$4}',
      (tester) async {
        tester.view.physicalSize = config.$2;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        Future<void> mount(Widget page) async {
          var theme = buildMestingTheme(
            musicThemePresetById(config.$1 ? 'classic-dark' : 'classic'),
          );
          if (export) {
            theme = theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'V107QA'),
              listTileTheme: theme.listTileTheme.copyWith(
                subtitleTextStyle: theme.listTileTheme.subtitleTextStyle
                    ?.copyWith(fontFamily: 'V107QA'),
              ),
            );
          }
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(preferences),
                platformAccountProvider.overrideWith(_Account.new),

                platformListeningSyncSummaryProvider.overrideWith(
                  (ref) => Stream.value(ListeningSyncSummary(const [])),
                ),
              ],
              child: LiquidGlassWidgets.wrap(
                adaptiveQuality: false,
                brightnessResolver: Theme.maybeBrightnessOf,
                child: RepaintBoundary(
                  key: const ValueKey('v107-ui-capture'),
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme,
                    locale: const Locale('zh', 'CN'),
                    supportedLocales: const [Locale('zh', 'CN')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(config.$3)),
                      child: child!,
                    ),
                    home: Scaffold(
                      backgroundColor: theme.colorScheme.surface,
                      body: page,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await mount(const MusicFunctionsPage());
        expect(find.byKey(const ValueKey('function-听书')), findsOneWidget);
        await capture(tester, 'functions-${config.$4}');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -550));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('function-本地音乐')), findsOneWidget);
        await capture(tester, 'functions-bottom-${config.$4}');
        await mount(const SongRecognitionPage());
        expect(find.text('开始识别'), findsOneWidget);
        await capture(tester, 'recognition-${config.$4}');
        await mount(const ListeningSyncPage());
        expect(find.text('同步播放历史与听歌时长'), findsOneWidget);
        await capture(tester, 'sync-${config.$4}');
        await mount(const FrameDiagnosticsPage());
        await capture(tester, 'diagnostics-${config.$4}');
        await mount(
          Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF46686A)),
              ),
              Positioned(
                top: 40,
                left: 16,
                child: PlayerGlassButton(
                  icon: CupertinoIcons.chevron_down,
                  label: '收起播放器',
                  onPressed: () {},
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: PlayerMoreMenu(
                  onSelected: (_) {},
                  groups: const [
                    [
                      PlayerMenuAction(
                        'queue',
                        '待播列表与播放模式',
                        CupertinoIcons.list_bullet,
                      ),
                      PlayerMenuAction(
                        'quality',
                        '音质选择',
                        CupertinoIcons.waveform,
                      ),
                      PlayerMenuAction(
                        'effects',
                        '音效',
                        CupertinoIcons.slider_horizontal_3,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
        await capture(tester, 'player-lenses-${config.$4}');
        await tester.tap(find.byType(PlayerMoreMenu));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await capture(tester, 'menu-inner-edge-${config.$4}');
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
