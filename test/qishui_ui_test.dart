import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_login_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_pages.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_welfare_page.dart';
import 'qishui_protocol_test.dart'
    show sodaSession, fixtureContext, fixtureJson, sodaRecording;
import 'support/release_152_qa.dart' show theme152;
import 'support/release_147_qa.dart' show load147IconFonts;

const capture = bool.fromEnvironment('CAPTURE_SODA');
const sodaCaptureDirectory = String.fromEnvironment(
  'SODA_CAPTURE_DIR',
  defaultValue: '.codex-artifacts/2026-11-06-soda-integration/ui-reviewed',
);
const boundary = ValueKey('soda-host-capture');

class FixtureAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      sodaSession().withProfile(name: '界面测试账号').identity;
  void changeForTest(PlatformSession? account) => state = AsyncData(account);
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!capture) return;
    await load147IconFonts();
    for (final name in [
      'SodaQA',
      'Microsoft YaHei',
      'Noto Sans SC',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(name)..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  Future<void> shot(WidgetTester tester, String name) async {
    if (!capture) return;
    final paint = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundary),
    );
    await tester.runAsync(() async {
      final image = await paint.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$sodaCaptureDirectory/host-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<List<String>> mount(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = false,
    bool tabs = false,
    int branch = 0,
    bool refuse = false,
    bool smsRefuse = false,
    bool pushed = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'beta_active_account_v2': 'qishui',
    });
    final preferences = await SharedPreferences.getInstance();
    final requests = <String>[];
    final api = QishuiApi(
      MockClient((request) async {
        requests.add(request.url.path);
        if (refuse) return fixtureJson({'status_code': 1000062});
        if (smsRefuse && request.url.path.endsWith('send_code/')) {
          return fixtureJson({
            'message': 'error',
            'data': {'error_code': 2156},
          });
        }
        if (request.url.path.endsWith('commerce_info')) {
          return fixtureJson({
            'status_code': 0,
            'status_info': {'now_ts_ms': 1793923200000},
            'membership': {'is_membership': false},
          });
        }
        if (request.url.path.contains('playlist') ||
            request.url.path.contains('discover')) {
          return fixtureJson({
            'status_code': 0,
            'playlists': [
              {
                'id': 'fixture-playlist',
                'title': '午后片刻 · 测试歌单',
                'count_tracks': 3,
                'type': 3,
                'url_cover': '',
              },
            ],
          });
        }
        return fixtureJson({
          'status_code': 0,
          'tracks': [
            {
              'id': 'fixture-track',
              'name': '界面测试歌曲',
              'duration': 230000,
              'artists': [
                {'name': '测试歌手'},
              ],
              'album': {'name': '测试专辑'},
              'url_cover': '',
            },
          ],
        });
      }),
      context: fixtureContext,
    )..configure(sodaSession());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        platformAccountProvider.overrideWith(FixtureAccount.new),
        qishuiApiProvider.overrideWithValue(api),
        currentMediaItemProvider.overrideWith(
          (_) => Stream<MediaItem?>.value(null),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    var theme = theme152(dark);
    if (capture) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'SodaQA'),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'SodaQA'),
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: TextStyle(
            fontFamily: 'SodaQA',
            fontSize: 16,
            color: theme.colorScheme.onSurface,
          ),
          subtitleTextStyle: TextStyle(
            fontFamily: 'SodaQA',
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp(
            navigatorKey: navigator,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: dark ? Colors.black : Colors.white,
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontFamily: capture ? 'SodaQA' : null,
                      color: theme.colorScheme.onSurface,
                    ),
                    child: child!,
                  ),
                ),
              ),
            ),
            home: pushed
                ? const SizedBox.shrink()
                : Stack(
                    children: [
                      page,
                      if (tabs)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: BetaMusicBottomBar(
                            soda: true,
                            selectedIndex: branch,
                            onTabSelected: (_) {},
                            searchConfig: GlassSearchBarConfig(
                              onSearchToggle: (_) {},
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
    if (pushed) {
      navigator.currentState!.push(betaContentRoute<void>(page));
      await tester.pump();
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    return requests;
  }

  test('three visual tabs retain the old four-branch routing contract', () {
    expect(qishuiMusicTabs.map((t) => t.label), ['发现', '音乐', '我的']);
    expect(qishuiVisualTab(3), 2);
    expect(qishuiBranchTab(2), 3);
    expect(betaMusicRoutes[qishuiBranchTab(2)], '/profile');
    expect(betaMusicTabs, hasLength(4));
  });
  for (final variant in [
    (const Size(390, 844), 1.0, false),
    (const Size(320, 740), 1.8, true),
  ]) {
    testWidgets(
      'phone form ${variant.$1.width} scale ${variant.$2} starts no network request',
      (tester) async {
        final requests = await mount(
          tester,
          const QishuiLoginPage(),
          size: variant.$1,
          scale: variant.$2,
          dark: variant.$3,
        );
        expect(requests, isEmpty);
        expect(find.text('手机号'), findsOneWidget);
        // Phone remains the default and opening it starts neither SMS nor QR.
        // The newly approved fallback is offered only as an explicit action.
        expect(find.text('使用抖音扫码登录'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'login-${variant.$1.width.toInt()}-${variant.$2}');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Closing an unused form must not read a disposed WidgetRef',
        );
      },
    );
  }
  testWidgets(
    'discovery uses real adapter data and only three visible destinations',
    (tester) async {
      final requests = await mount(
        tester,
        const QishuiRootPage(QishuiRoot.discover),
        tabs: true,
      );
      expect(find.text('午后片刻 · 测试歌单'), findsOneWidget);
      expect(requests, ['/luna/discover/mix']);
      expect(find.text('功能'), findsNothing);
      expect(tester.takeException(), isNull);
      await shot(tester, 'discover-390-light');
    },
  );
  testWidgets('music root shows actual feed and a mode entry in dark theme', (
    tester,
  ) async {
    await mount(
      tester,
      const QishuiRootPage(QishuiRoot.music),
      tabs: true,
      branch: 1,
      dark: true,
    );
    expect(find.text('界面测试歌曲'), findsOneWidget);
    expect(find.text('选择听歌模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'music-390-dark');
  });
  testWidgets('mine remains usable on narrow screens with large text', (
    tester,
  ) async {
    await mount(
      tester,
      const QishuiRootPage(QishuiRoot.mine),
      tabs: true,
      branch: 3,
      size: const Size(320, 740),
      scale: 1.8,
      dark: true,
    );
    expect(find.text('界面测试账号'), findsOneWidget);
    expect(find.text('官版音效'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'mine-320-large-dark');
  });
  testWidgets(
    'SMS refusal identifies the send stage and never starts a success countdown',
    (tester) async {
      final requests = await mount(
        tester,
        const QishuiLoginPage(),
        smsRefuse: true,
      );
      await tester.enterText(
        find.widgetWithText(TextField, '手机号'),
        '13800000000',
      );
      await tester.tap(find.byKey(const ValueKey('qishui-send-code')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(requests, ['/passport/mobile/send_code/']);
      expect(find.text('汽水未接受发送验证码请求（2156）'), findsOneWidget);
      expect(find.text('获取验证码'), findsOneWidget);
      expect(find.textContaining('s 后重新获取'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'business refusal is visible and offers retry instead of fake catalog rows',
    (tester) async {
      final requests = await mount(
        tester,
        const QishuiRootPage(QishuiRoot.discover),
        refuse: true,
      );
      expect(find.textContaining('1000062'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(requests, ['/luna/discover/mix']);
      expect(find.text('午后片刻 · 测试歌单'), findsNothing);
      expect(tester.takeException(), isNull);
      await shot(tester, 'refusal-390');
    },
  );
  testWidgets('tablet playlist cells fit their cover and scaled title', (
    tester,
  ) async {
    await mount(
      tester,
      const QishuiRootPage(QishuiRoot.discover),
      tabs: true,
      size: const Size(768, 1024),
      scale: 1.3,
    );
    expect(find.text('午后片刻 · 测试歌单'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'discover-768-tablet');
  });
  testWidgets(
    'a pushed private page hides the old account and cancels reads on switch',
    (tester) async {
      final cancelled = Completer<void>();
      await mount(
        tester,
        QishuiTrackPage(
          title: '测试私人列表',
          load: (abort) {
            abort.then((_) {
              if (!cancelled.isCompleted) cancelled.complete();
            });
            return Future.value([sodaRecording()]);
          },
        ),
      );
      expect(find.text('Fixture recording'), findsOneWidget);
      final context = tester.element(find.byType(QishuiTrackPage));
      (ProviderScope.containerOf(context).read(platformAccountProvider.notifier)
              as FixtureAccount)
          .changeForTest(null);
      await tester.pump();
      expect(find.text('Fixture recording'), findsNothing);
      expect(find.text('账号已变化'), findsOneWidget);
      expect(cancelled.isCompleted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'welfare page only reads on entry, never claims or settles advertising',
    (tester) async {
      final requests = await mount(
        tester,
        const QishuiWelfarePage(),
        pushed: true,
      );
      expect(requests, ['/luna/commerce/v2/commerce_info']);
      expect(find.text('活动免费 VIP'), findsOneWidget);
      expect(find.text('广告奖励时长'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'welfare-390');
    },
  );
}
