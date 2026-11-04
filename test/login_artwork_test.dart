import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_login_options_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_glass_scroll_body.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

class _Auth extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(
          request.url.path.endsWith('/unikey')
              ? {'code': 200, 'unikey': 'synthetic-login-art'}
              : {'code': 801},
        ),
        200,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(_Account.new),
        authControllerProvider.overrideWith(_Auth.new),
        neteaseApiProvider.overrideWithValue(NeteaseApi(client)),
        musicPlatformApiProvider.overrideWithValue(
          MusicPlatformApi(
            server: _Server(),
            client: MockClient((_) async => http.Response('{}', 500)),
          ),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.close();
    });
    await container.read(platformAccountProvider.future);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
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
          home: page,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  }

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      for (final scene in <Widget>[
        const PlatformAccountPage(loginOnly: true),
        const PlatformAccountPage(
          platform: MusicPlatform.netease,
          loginOnly: true,
        ),
        const PlatformLoginOptionsPage(platform: MusicPlatform.kugou),
        const PlatformLoginOptionsPage(platform: MusicPlatform.netease),
      ].indexed) {
        final (index, page) = scene;
        testWidgets(
          'login form fills available space without artwork $dark/$compact/${page.runtimeType}/$index',
          (tester) async {
            await mount(
              tester,
              page,
              dark: dark,
              size: compact ? const Size(320, 650) : const Size(390, 844),
              scale: compact ? 1.4 : 1,
            );
            final viewport = tester.getRect(find.byType(BetaGlassScrollBody));
            expect(viewport.bottom, compact ? 650 : 844);
            expect(find.byType(Image), findsNothing);
            if (page is PlatformAccountPage &&
                page.platform == MusicPlatform.netease) {
              expect(find.byType(QrImageView), findsOneWidget);
            }
            await close(tester);
          },
        );
      }
    }
  }
  for (final dark in [false, true]) {
    testWidgets('keyboard retains input and submit without artwork $dark', (
      tester,
    ) async {
      await mount(
        tester,
        const PlatformAccountPage(loginOnly: true),
        dark: dark,
        size: const Size(320, 650),
        scale: 1.4,
      );
      await tester.enterText(
        find.byKey(const ValueKey('beta11-phone-field')),
        '13800138000',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('beta11-phone-submit')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('beta11-phone-submit')).hitTestable(),
        findsOneWidget,
      );
      tester.view.resetViewInsets();
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('beta11-phone-field')),
      );
      expect(field.controller!.text, '13800138000');
      await close(tester);
    });
  }
  testWidgets('short landscape window prioritizes the form', (tester) async {
    await mount(
      tester,
      const PlatformAccountPage(loginOnly: true),
      size: const Size(844, 390),
    );
    expect(find.byType(Image), findsNothing);
    expect(
      find.byKey(const ValueKey('beta11-phone-submit')).hitTestable(),
      findsOneWidget,
    );
    await close(tester);
  });
}
