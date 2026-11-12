import 'package:mesting_music/features/auth/presentation/beta_account_card.dart';
import 'package:mesting_music/features/legal/presentation/disclaimer_dialog.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/auth/presentation/beta_welcome_page.dart';
import 'package:mesting_music/features/auth/presentation/mesting_music_companions.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_login.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_login_options_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';

class _Store implements PlatformSessionStore {
  PlatformSession? value;
  @override
  Future<PlatformSession?> read() async => value;
  @override
  Future<void> write(PlatformSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _NetStore implements NeteaseSessionStore {
  NeteaseSession? value;
  @override
  Future<NeteaseSession?> read() async => value;
  @override
  Future<void> write(NeteaseSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

const _capture = ValueKey('dual-platform-capture');
void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_DUAL_PLATFORM')) {
      // Host-only fonts improve QA screenshots and never enter app assets.
      for (final family in [
        'Roboto',
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

  Future<ProviderContainer> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({
      BetaAccountChoiceController.preferenceKey: 'guest',
    });
    final prefs = await SharedPreferences.getInstance();
    await saveLegalDocumentConsent(prefs);
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/unikey')
              ? {'code': 200, 'unikey': 'public-test-fixture'}
              : {'code': 801},
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),

        platformSessionStoreProvider.overrideWithValue(_Store()),
        neteaseSessionStoreProvider.overrideWithValue(_NetStore()),
        neteaseApiProvider.overrideWithValue(NeteaseApi(client)),
        musicPlatformApiProvider.overrideWithValue(
          MusicPlatformApi(server: _Server(), client: client),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildMestingTheme(
            musicThemePresetById(dark ? 'classic-dark' : 'classic'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => RepaintBoundary(
              key: _capture,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: page,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (page is BetaWelcomePage &&
        const bool.fromEnvironment('CAPTURE_DUAL_PLATFORM')) {
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/branding/welcome/companions-atlas.webp'),
          tester.element(find.byType(BetaWelcomePage)),
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
    return container;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_DUAL_PLATFORM')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_capture),
      );
      final img = await boundary.toImage(pixelRatio: 1.5);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '.codex-artifacts/2026-10-28-netease-integration/ui/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      img.dispose();
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'NetEase account uses the shared account card and platform chooser ($dark)',
      (tester) async {
        final container = await mount(
          tester,
          const Scaffold(body: SingleChildScrollView(child: BetaAccountCard())),
          dark: dark,
        );
        await container.read(platformAccountProvider.future);
        await container
            .read(platformAccountProvider.notifier)
            .acceptNetease(
              const NeteaseSession(
                userId: '7',
                deviceId: 'fixture-device',
                nickname: '网易云账号夹具',
                cookies: {'MUSIC_U': 'fixture-cookie'},
              ),
            );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('网易云账号 · 已登录'), findsOneWidget);
        await capture(tester, 'netease-account-$dark');
        await tester.tap(find.text('切换音乐平台'));
        await tester.pumpAndSettle();
        expect(find.text('网易云音乐 · 当前平台'), findsOneWidget);
        await tester.tap(find.text('酷狗音乐'));
        await tester.pumpAndSettle();
        expect(find.text('手机号登录'), findsOneWidget);
        expect(
          container.read(platformAccountProvider).value?.platform,
          MusicPlatform.netease,
        );
        expect(tester.takeException(), isNull);
      },
      skip: !DistributionChannel.isBeta,
    );

    testWidgets(
      'NetEase QR uses the same opaque login page ($dark)',
      (tester) async {
        await mount(
          tester,
          const PlatformAccountPage(
            platform: MusicPlatform.netease,
            neteaseMethod: NeteaseLoginMethod.qr,
            loginOnly: true,
          ),
          dark: dark,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('刷新二维码'), findsOneWidget);
        expect(find.byType(PlatformAccountPage), findsOneWidget);
        await capture(tester, 'netease-qr-$dark');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
      },
      skip: !DistributionChannel.isBeta,
    );

    testWidgets(
      'welcome groups platforms and retains incumbent controls ($dark)',
      (tester) async {
        await mount(tester, const BetaWelcomePage(), dark: dark);
        expect(find.byType(MestingMusicCompanions), findsOneWidget);
        expect(find.text('酷狗登录'), findsOneWidget);
        expect(find.text('网易云登录'), findsOneWidget);
        expect(find.text('游客体验'), findsOneWidget);
        expect(find.text('手机号登录'), findsNothing);
        expect(
          tester.getTopLeft(find.text('酷狗登录')).dy,
          lessThan(tester.getTopLeft(find.text('网易云登录')).dy),
        );
        expect(find.text('汽水登录'), findsOneWidget);
        expect(find.byType(BetaGlassButton), findsNWidgets(4));
        await capture(tester, 'welcome-$dark');
        await tester.tap(find.text('酷狗登录'));
        await tester.pumpAndSettle();
        for (final label in ['手机号登录', '酷狗扫码登录', '微信扫码登录', 'QQ 扫码登录']) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.tap(find.text('手机号登录'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('beta11-phone-field')),
          findsOneWidget,
        );
        expect(find.byType(BetaGlassField), findsWidgets);
        expect(tester.takeException(), isNull);
      },
      skip: !DistributionChannel.isBeta,
    );

    testWidgets(
      'NetEase method selection uses existing glass buttons ($dark)',
      (tester) async {
        await mount(
          tester,
          const PlatformLoginOptionsPage(platform: MusicPlatform.netease),
          dark: dark,
        );
        for (final method in NeteaseLoginMethod.values) {
          expect(find.text(method.label), findsOneWidget);
        }
        expect(find.byType(BetaGlassButton), findsNWidgets(5));
        await capture(tester, 'netease-methods-$dark');
        await tester.tap(find.text(NeteaseLoginMethod.email.label));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('netease-login-account')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('netease-login-password')),
          findsOneWidget,
        );
        expect(find.byType(BetaGlassField), findsNWidgets(2));
        expect(find.text('网易邮箱'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      skip: !DistributionChannel.isBeta,
    );

    testWidgets(
      'NetEase email form fits narrow screens and large text ($dark)',
      (tester) async {
        await mount(
          tester,
          const PlatformAccountPage(
            platform: MusicPlatform.netease,
            neteaseMethod: NeteaseLoginMethod.email,
            loginOnly: true,
          ),
          dark: dark,
          size: const Size(320, 650),
          scale: 1.5,
        );
        await capture(tester, 'netease-email-small-$dark');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('netease-login-account')));
        await tester.enterText(
          find.byKey(const ValueKey('netease-login-account')),
          'fixture@163.com',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
      skip: !DistributionChannel.isBeta,
    );
  }
}
