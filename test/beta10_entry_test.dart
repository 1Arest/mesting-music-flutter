import 'package:mesting_music/features/music_platform/presentation/platform_login_options_page.dart';
import 'dart:async';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
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
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/auth/presentation/beta_entry_coordinator.dart';
import 'package:mesting_music/features/auth/presentation/beta_welcome_page.dart';
import 'package:mesting_music/features/auth/presentation/beta_onboarding_page.dart';
import 'package:mesting_music/features/auth/presentation/mesting_music_companions.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/player/player_visual_style.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_success_feedback.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

class _Auth extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

class _Platform extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

const _captureKey = ValueKey('beta10-capture');
void main() {
  // These are Beta welcome/guide surfaces with Beta-only assets. The formal
  // channel has its own auth flow tests and never mounts these entry pages.
  group(
    'Beta entry surfaces',
    _betaEntryTests,
    skip: !DistributionChannel.isBeta,
  );
}

void _betaEntryTests() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      for (final family in [
        'BetaQACJK',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(
          family,
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/flutter/mesting-beta5/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
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
  Future<ProviderContainer> prepare(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(390, 844),
    bool dark = false,
    double scale = 1,
    Map<String, Object> values = const {},
    MusicPlatformApi? api,
  }) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authControllerProvider.overrideWith(_Auth.new),
        if (api != null) musicPlatformApiProvider.overrideWithValue(api),
        platformAccountProvider.overrideWith(_Platform.new),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'BetaQACJK'),
      );
    }
    if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      theme = theme.copyWith(
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: theme.chipTheme.labelStyle?.copyWith(
            fontFamily: 'BetaQACJK',
          ),
          secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
            fontFamily: 'BetaQACJK',
          ),
        ),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return container;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) return;
    final context = tester.element(find.byType(MaterialApp).first);
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    await tester.runAsync(() async {
      await Future.wait(
        images.map((image) => precacheImage(image.image, context)),
      );
    });
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    await tester.runAsync(() async {
      // Raster export is real engine I/O, outside the widget fake clock.
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(
        '${const String.fromEnvironment('BETA10_CAPTURE_DIR', defaultValue: String.fromEnvironment('BETA_SCREENSHOT_DIR'))}/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'welcome has living companions, both primary entries and guest ($dark)',
      (tester) async {
        await prepare(tester, const BetaWelcomePage(), dark: dark);
        expect(find.text('酷狗登录'), findsOneWidget);
        expect(find.text('网易云登录'), findsOneWidget);
        expect(find.text('游客体验'), findsOneWidget);
        expect(find.byType(MestingMusicCompanions), findsOneWidget);
        await capture(tester, 'welcome-${dark ? 'dark' : 'light'}');
        await tester.tap(find.bySemanticsLabel('我已阅读并同意用户协议和隐私政策'));
        await tester.pump();
        await tester.tap(find.text('酷狗登录'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('Mesting 账号登录'), findsNothing);
        expect(find.text('酷狗扫码登录'), findsOneWidget);
        expect(find.text('QQ 扫码登录'), findsOneWidget);
        await capture(tester, 'other-logins-${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'eight guide pages move both ways and real player choice persists ($dark)',
      (tester) async {
        var finished = 0;
        final container = await prepare(
          tester,
          BetaOnboardingPage(onFinish: () => finished++),
          dark: dark,
        );
        for (var i = 0; i < 8; i++) {
          final progress = tester.widget<AnimatedContainer>(
            find.byKey(ValueKey('guide-progress-$i')),
          );
          expect(
            (progress.decoration! as BoxDecoration).color,
            Theme.of(
              tester.element(find.byType(BetaOnboardingPage)),
            ).colorScheme.primary,
          );
          expect(
            find.text(betaGuidePages[i].title),
            i == 3 ? findsNothing : findsOneWidget,
          );
          await capture(tester, 'guide-${i + 1}-${dark ? 'dark' : 'light'}');
          if (i == 6) {
            await tester.tap(find.text('流光唱片'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 450));
            expect(
              container.read(playerVisualStyleProvider),
              PlayerVisualStyle.aurora,
            );
            expect(
              container
                  .read(sharedPreferencesProvider)
                  .getString(
                    DistributionChannel.isBeta
                        ? 'player_visual_style_beta5'
                        : 'player_visual_style',
                  ),
              'aurora',
            );
          }
          if (i < 7) {
            await tester.tap(find.byKey(const ValueKey('guide-next')));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 420));
          }
        }
        await tester.tap(find.bySemanticsLabel('上一页'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 420));
        expect(find.text('五种播放器风格'), findsOneWidget);
        await tester.tap(find.text('跳过'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 420));
        expect(finished, 0);
        await tester.tap(find.byKey(const ValueKey('guide-next')));
        expect(finished, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets(
      'beta11 dedicated phone form displays failed send without false countdown ($dark)',
      (tester) async {
        var sends = 0;
        final api = MusicPlatformApi(
          server: _Server(),
          client: MockClient((r) async {
            if (r.url.path == '/register/dev') {
              return http.Response(
                '{"status":1,"data":{"dfid":"device"}}',
                200,
              );
            }
            sends++;
            return http.Response(
              jsonEncode({'status': 0, 'error_code': 20015}),
              502,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        await prepare(
          tester,
          const PlatformAccountPage(),
          dark: dark,
          api: api,
        );
        expect(find.text('手机号登录'), findsOneWidget);
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.text('Mesting Music'), findsNothing);
        await capture(tester, 'beta11-phone-${dark ? 'dark' : 'light'}');
        await tester.enterText(
          find.byKey(const ValueKey('beta11-phone-field')),
          '13800138000',
        );
        await tester.tap(find.byKey(const ValueKey('beta11-send-code')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(sends, 1);
        expect(find.textContaining('20015'), findsOneWidget);
        expect(find.text('获取验证码'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'beta11-phone-error-${dark ? 'dark' : 'light'}');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'beta11 inline code action owns pending, confirmed countdown and duplicate guard',
    (tester) async {
      final pending = Completer<http.Response>();
      var sends = 0;
      final api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((r) async {
          if (r.url.path == '/register/dev') {
            return http.Response('{"status":1,"data":{"dfid":"device"}}', 200);
          }
          sends++;
          return pending.future;
        }),
      );
      await prepare(tester, const PlatformAccountPage(), api: api);
      final field = find.byKey(const ValueKey('beta11-code-field'));
      final action = find.byKey(const ValueKey('beta11-send-code'));
      final rect = tester.getRect(field);
      final button = tester.getRect(action);
      expect(button.right, lessThanOrEqualTo(rect.right));
      expect(button.left, greaterThan(rect.center.dx));
      expect(button.center.dy, closeTo(rect.center.dy, 1));
      expect(
        find.ancestor(of: action, matching: find.byType(BetaGlassField)),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('beta11-phone-field')),
        '13800138000',
      );
      await tester.tap(action);
      await tester.pump();
      expect(tester.widget<BetaGlassButton>(action).loading, true);
      // Sending a code blocks duplicate login without replacing the primary
      // button's glass layer or its visible label.
      final submit = find.byKey(const ValueKey('beta11-phone-submit'));
      expect(
        find.descendant(of: submit, matching: find.text('登录')),
        findsOneWidget,
      );
      final submitGlass = tester.widget<GlassButton>(
        find.descendant(of: submit, matching: find.byType(GlassButton)),
      );
      // Real disabled interaction now retains optics independently; keeping
      // the inner button enabled is no longer needed to avoid opacity fade.
      expect(submitGlass.enabled, false);
      expect(submitGlass.fadeWhenDisabled, false);
      await capture(tester, 'beta11-phone-code-pending');
      await tester.tap(action);
      await tester.pump();
      expect(sends, 1);
      pending.complete(http.Response('{"status":1}', 200));
      await tester.pump();
      expect(find.text('60s 后重试'), findsOneWidget);
      await capture(tester, 'beta11-phone-code-countdown');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'beta11 dedicated phone keyboard and large text retain readable code ($dark)',
      (tester) async {
        await prepare(
          tester,
          const PlatformAccountPage(),
          size: const Size(320, 640),
          scale: 1.6,
          dark: dark,
        );
        await tester.enterText(
          find.byKey(const ValueKey('beta11-phone-field')),
          '13800138000',
        );
        final code = find.byKey(const ValueKey('beta11-code-field'));
        await tester.enterText(code, '863432');
        await tester.pump();
        final editable = tester
            .state<EditableTextState>(
              find.descendant(of: code, matching: find.byType(EditableText)),
            )
            .renderEditable;
        expect(editable.maxScrollExtent, lessThan(1));
        expect(
          find.byKey(const ValueKey('beta11-code-label')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.widget<TextField>(code).controller!.text, '863432');
        await capture(
          tester,
          'beta11-phone-small-code-${dark ? 'dark' : 'light'}',
        );
        await tester.showKeyboard(code);
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('beta11-phone-submit')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const ValueKey('beta11-phone-submit')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('beta11-code-label')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'beta11-phone-small-keyboard-${dark ? 'dark' : 'light'}',
        );
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('small large-text welcome and guide keep actions reachable', (
    tester,
  ) async {
    await prepare(
      tester,
      const BetaWelcomePage(),
      size: const Size(320, 640),
      scale: 1.6,
    );
    expect(tester.takeException(), isNull);
    await capture(tester, 'welcome-small-large-text');
    await prepare(
      tester,
      BetaOnboardingPage(onFinish: () {}),
      size: const Size(320, 640),
      scale: 1.6,
    );
    for (var i = 0; i < 8; i++) {
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('guide-next'))).bottom,
        lessThanOrEqualTo(640),
      );
      if (i < 7) {
        await tester.tap(find.byKey(const ValueKey('guide-next')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 420));
      }
    }
    await capture(tester, 'guide-small-large-text');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('wide welcome and success card have bounded compositions', (
    tester,
  ) async {
    await prepare(tester, const BetaWelcomePage(), size: const Size(1000, 760));
    await capture(tester, 'welcome-wide');
    expect(tester.takeException(), isNull);
    var completed = 0;
    await prepare(
      tester,
      Scaffold(body: BetaLoginSuccess(onComplete: () => completed++)),
    );
    await capture(tester, 'login-success');
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'each fresh login shows success and guide; skip reaches last guide page; logout resets',
    (tester) async {
      var reset = 0;
      final c = await prepare(
        tester,
        BetaEntryCoordinator(
          onLogout: () => reset++,
          child: const Scaffold(body: Text('应用主页')),
        ),
        values: {BetaEntryFlow.completedKey: true},
      );
      expect(find.text('应用主页'), findsOneWidget);
      c.read(betaEntryFlowProvider.notifier).authenticated();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BetaLoginSuccess), findsOneWidget);
      c.read(betaEntryFlowProvider.notifier).authenticated();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BetaOnboardingPage), findsOneWidget);
      await tester.tap(find.text('跳过'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.read(betaEntryFlowProvider), BetaEntryStage.guide);
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pump();
      expect(c.read(betaEntryFlowProvider), BetaEntryStage.app);
      await c.read(betaEntryFlowProvider.notifier).welcome();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(reset, 1);
      expect(find.byType(BetaWelcomePage), findsOneWidget);
      c.read(betaEntryFlowProvider.notifier).authenticated();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BetaLoginSuccess), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'beta13 entry dispatcher returns phone QR and both legal pages through their owning Navigator',
    (tester) async {
      final dispatcher = RootBackButtonDispatcher();
      Future<bool> fallback() async => false;
      dispatcher.addCallback(fallback);
      addTearDown(() => dispatcher.removeCallback(fallback));
      await prepare(
        tester,
        BetaEntryCoordinator(
          backDispatcher: dispatcher,
          child: const Scaffold(body: Text('应用主页')),
        ),
      );
      await tester.tap(find.bySemanticsLabel('我已阅读并同意用户协议和隐私政策'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('welcome-kugou-login')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('手机号登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('beta11-phone-field')), findsOneWidget);
      expect(find.text('+86'), findsOneWidget);
      expect(await dispatcher.didPopRoute(), true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlatformAccountPage), findsNothing);
      expect(find.byType(PlatformLoginOptionsPage), findsOneWidget);
      expect(await dispatcher.didPopRoute(), true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BetaWelcomePage), findsOneWidget);
      for (final title in ['用户协议', '隐私政策']) {
        await tester.tap(find.text(title).hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (title == '用户协议') {
          await tester.tap(find.byKey(const ValueKey('legal-page-back')));
        } else {
          expect(await dispatcher.didPopRoute(), true);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(BetaWelcomePage), findsOneWidget);
      }
      await tester.tap(find.text('酷狗登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('微信扫码登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlatformAccountPage), findsOneWidget);
      expect(await dispatcher.didPopRoute(), true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlatformAccountPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'beta18 success reveals interactive guide immediately and preserves early Next state',
    (tester) async {
      var sounds = 0;
      const channel = MethodChannel('com.mesting.music/ui_sound');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'loginSuccess') sounds++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final c = await prepare(
        tester,
        const BetaEntryCoordinator(child: Scaffold(body: Text('应用主页'))),
        values: {BetaEntryFlow.completedKey: true},
      );
      final semantics = tester.ensureSemantics();
      expect(sounds, 0);
      c.read(betaEntryFlowProvider.notifier).authenticated();
      await tester.pump();
      expect(find.byType(BetaOnboardingPage), findsOneWidget);
      final guideState = tester.state(find.byType(BetaOnboardingPage));
      expect(
        TickerMode.valuesOf(
          tester.element(find.byType(BetaOnboardingPage)),
        ).enabled,
        true,
      );
      expect(find.bySemanticsLabel('下一步'), findsOneWidget);
      expect(find.bySemanticsLabel('跳过'), findsOneWidget);
      expect(find.byKey(const ValueKey('beta13-success-cover')), findsNothing);
      await tester.pump(const Duration(milliseconds: 350));
      final card = tester.getRect(
        find.byKey(const ValueKey('beta10-login-success')),
      );
      expect(card.width, 104);
      expect(card.height, 104);
      expect(card.top, 76);
      expect(card.center.dy, lessThan(844 / 2));
      await capture(tester, 'beta18-success-over-visible-guide');
      // Click while the HUD is visible. Its completion must not reset the
      // active guide page or replay a second sound.
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('播放与歌词'), findsOneWidget);
      expect(find.byType(BetaLoginSuccess), findsOneWidget);
      await capture(tester, 'beta18-success-early-next');
      c.read(betaEntryFlowProvider.notifier).authenticated();
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 260));
      expect(sounds, 1);
      expect(
        TickerMode.valuesOf(
          tester.element(find.byType(BetaOnboardingPage)),
        ).enabled,
        true,
      );
      expect(find.byType(BetaLoginSuccess), findsNothing);
      expect(tester.state(find.byType(BetaOnboardingPage)), same(guideState));
      expect(find.text('播放与歌词'), findsOneWidget);
      expect(find.bySemanticsLabel('下一步'), findsOneWidget);
      await tester.tap(find.text('跳过'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.read(betaEntryFlowProvider), BetaEntryStage.guide);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('开始使用'), findsOneWidget);
      await capture(tester, 'beta13-guide-skip-final');
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
