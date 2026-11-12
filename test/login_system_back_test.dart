import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesting_music/app/system_back_coordinator.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/beta_entry_back_state.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/auth/presentation/beta_entry_coordinator.dart';
import 'package:mesting_music/features/auth/presentation/beta_welcome_page.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_login_options_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

class _Guest extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);

  testWidgets('Android registers entry routes and returns one level at a time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(_Guest.new),
      ],
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('主页')),
        ),
        GoRoute(
          path: '/covered',
          builder: (_, _) => const Scaffold(body: Text('旧页面')),
        ),
      ],
    );
    bool? handlesBack;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
        handlesBack = call.arguments as bool;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      router.dispose();
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildMestingTheme(musicThemePresets.first),
          routerConfig: router,
          builder: (_, child) => SystemBackCoordinator(
            canPop: () =>
                container.read(betaEntryBackStateProvider).canHandlePop ??
                router.canPop(),
            navigationChanges: router.routerDelegate,
            child: BetaEntryCoordinator(
              backDispatcher: router.backButtonDispatcher,
              child: child!,
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    }

    await settle();
    expect(handlesBack, false, reason: 'welcome root retains Android exit');
    expect(find.byIcon(CupertinoIcons.device_phone_portrait), findsNothing);
    await tester.tap(find.bySemanticsLabel('我已阅读并同意用户协议和隐私政策'));
    await settle();

    for (final platform in MusicPlatform.values) {
      await tester.ensureVisible(
        find.byKey(ValueKey('welcome-${platform.name}-login')),
      );
      await tester.tap(find.byKey(ValueKey('welcome-${platform.name}-login')));
      await settle();
      expect(find.byType(PlatformLoginOptionsPage), findsOneWidget);
      expect(
        router.canPop(),
        false,
        reason: 'entry lives above the app Router',
      );
      expect(handlesBack, true, reason: '${platform.name} selector');

      if (platform == MusicPlatform.kugou) {
        await tester.tap(find.text('手机号登录'));
        await settle();
        expect(
          find.byKey(const ValueKey('beta11-phone-field')),
          findsOneWidget,
        );
        expect(handlesBack, true);
        // A new Android Activity must also receive the entry stack's live flag.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        handlesBack = false;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle();
        expect(handlesBack, true);
        await tester.binding.handlePopRoute();
        await settle();
        expect(find.byType(PlatformLoginOptionsPage), findsOneWidget);
        expect(handlesBack, true);
      }
      await tester.binding.handlePopRoute();
      await settle();
      expect(find.byType(BetaWelcomePage), findsOneWidget);
      expect(handlesBack, false);
    }

    for (final title in ['用户协议', '隐私政策']) {
      await tester.ensureVisible(find.text(title));
      await tester.tap(find.text(title));
      await settle();
      expect(handlesBack, true);
      await tester.binding.handlePopRoute();
      await settle();
      expect(handlesBack, false);
    }

    // A covered app stack must not consume Back at the welcome root. Leaving
    // entry restores the Router's own Back handling without a stale entry flag.
    router.push<void>('/covered');
    await settle();
    expect(router.canPop(), true);
    expect(handlesBack, false);
    await container.read(betaEntryFlowProvider.notifier).finish();
    await settle();
    expect(handlesBack, true);
    await tester.binding.handlePopRoute();
    await settle();
    expect(handlesBack, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
