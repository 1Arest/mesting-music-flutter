import 'dart:async';
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
import 'package:mesting_music/features/experience/presentation/player_more_menu.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_profile_edit_page.dart';
import 'package:mesting_music/shared/widgets/quiet_pull_to_refresh.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

const _export = bool.fromEnvironment('EXPORT_V106_SCREENSHOTS');
const _owner = PlatformSession(
  userId: 'synthetic106',
  token: 'local-fixture-only',
  nickname: '音乐旅人',
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _owner;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_export) {
      final bytes = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
      for (final name in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'V106QA',
      ]) {
        await (FontLoader(
          name,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!_export) return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('v106-capture')),
          )
          .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory(
        const String.fromEnvironment('V106_SCREENSHOT_DIR'),
      );
      await folder.create(recursive: true);
      await File(
        '${folder.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (_export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'V106QA'),
      );
    }
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        adaptiveQuality: false,
        brightnessResolver: Theme.maybeBrightnessOf,
        child: RepaintBoundary(
          key: const ValueKey('v106-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final config in [
    (false, const Size(390, 844), 1.0, 'light'),
    (true, const Size(390, 844), 1.0, 'dark'),
    (false, const Size(320, 740), 1.6, 'small-large-text'),
    (true, const Size(768, 1024), 1.0, 'wide'),
  ]) {
    testWidgets('glass trigger, flight, pressed row and reverse ${config.$4}', (
      tester,
    ) async {
      String? selected;
      await mount(
        tester,
        Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: config.$1
                          ? [const Color(0xFF496F70), const Color(0xFF151519)]
                          : [const Color(0xFFDCE9EA), const Color(0xFFBABACB)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: PlayerMoreMenu(
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
                        'comments',
                        '歌曲评论',
                        CupertinoIcons.text_bubble,
                      ),
                    ],
                    [
                      PlayerMenuAction(
                        'equalizer',
                        '均衡器',
                        CupertinoIcons.slider_horizontal_3,
                      ),
                      PlayerMenuAction(
                        'effects',
                        '音效',
                        CupertinoIcons.waveform,
                      ),
                      PlayerMenuAction(
                        'mv',
                        '观看 MV',
                        CupertinoIcons.play_rectangle,
                      ),
                      PlayerMenuAction(
                        'sleep',
                        '定时关闭',
                        CupertinoIcons.moon_zzz,
                      ),
                    ],
                  ],
                  disclosure: const PlayerMenuDisclosure(
                    title: '封面样式',
                    current: '沉浸封面',
                    actions: [
                      PlayerMenuAction(
                        'cover',
                        '沉浸封面',
                        CupertinoIcons.photo,
                        selected: true,
                      ),
                      PlayerMenuAction(
                        'classic',
                        '黑胶唱片',
                        CupertinoIcons.circle,
                      ),
                    ],
                  ),
                  onSelected: (value) => selected = value,
                ),
              ),
            ],
          ),
        ),
        dark: config.$1,
        size: config.$2,
        scale: config.$3,
      );
      await capture(tester, 'menu-${config.$4}-trigger');
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await capture(tester, 'menu-${config.$4}-flight');
      await tester.pumpAndSettle();
      await capture(tester, 'menu-${config.$4}-open');
      final style = find.byKey(const ValueKey('player-style-disclosure'));
      await tester.ensureVisible(style);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(style));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester
            .widget<AnimatedScale>(
              find.descendant(of: style, matching: find.byType(AnimatedScale)),
            )
            .scale,
        .985,
      );
      await capture(tester, 'menu-${config.$4}-press');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('黑胶唱片'), findsOneWidget);
      await tester.ensureVisible(find.text('黑胶唱片'));
      await tester.tap(find.text('黑胶唱片'));
      await tester.pump();
      expect(selected, isNull);
      await tester.pumpAndSettle();
      expect(selected, 'classic');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'real birthday picker uses Chinese and keeps edits local until save',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Account.new),
          platformEditableProfileProvider(_owner).overrideWith(
            (ref) async =>
                const PlatformProfileInfo('音乐旅人', '', birthday: '2000-02-01'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await mount(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: const PlatformProfileEditPage(),
        ),
      );
      await tester.ensureVisible(find.text('生日'));
      await tester.tap(find.text('生日'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      final context = tester.element(find.byType(CupertinoDatePicker));
      expect(CupertinoLocalizations.of(context).datePickerMonth(2), '二月');
      expect(find.text('February'), findsNothing);
      await capture(tester, 'birthday-chinese');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('2000-02-01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pull refresh has no floating spinner and coalesces one gesture',
    (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      await mount(
        tester,
        Scaffold(
          body: QuietPullToRefresh(
            onRefresh: () {
              calls++;
              return gate.future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              children: const [SizedBox(height: 1400, child: Text('签到记录'))],
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 230));
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(RefreshIndicator), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 230));
      await tester.pump();
      expect(calls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
