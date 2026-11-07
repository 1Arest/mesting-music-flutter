import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/presentation/first_launch_auth_coordinator.dart';
import 'package:mesting_music/features/auth/presentation/beta_consent_row.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Guest175 extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  Future<void> mount(
    WidgetTester tester,
    SharedPreferences prefs, {
    bool aboveNavigator = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const home = Scaffold(body: Text('推荐页面'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          platformAccountProvider.overrideWith(_Guest175.new),
        ],
        child: MaterialApp(
          builder: aboveNavigator
              ? (_, child) => FirstLaunchAuthCoordinator(child: child!)
              : null,
          home: aboveNavigator
              ? home
              : const FirstLaunchAuthCoordinator(child: home),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
  }

  testWidgets(
    'first install exposes three platforms and remembers guest choice',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await mount(tester, prefs);
      for (final label in ['酷狗登录', '网易云登录', '汽水登录']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('phone-auth-form')), findsNothing);
      await tester.ensureVisible(find.text('游客体验'));
      await tester.tap(find.text('游客体验'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('推荐页面').hitTestable(), findsOneWidget);
      expect(prefs.getBool(firstLaunchAuthCompletedPreferenceKey), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'entry above app Navigator opens legal and platform pages with explicit consent',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await mount(tester, prefs, aboveNavigator: true);
      await tester.ensureVisible(find.text('用户协议'));
      await tester.tap(find.text('用户协议'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('三、登录、安全与账号归属'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      final consent = find.descendant(
        of: find.byType(BetaConsentRow),
        matching: find.byType(InkResponse),
      );
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pump();
      await tester.ensureVisible(find.text('酷狗登录'));
      await tester.tap(find.text('酷狗登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('手机号登录'), findsOneWidget);
      expect(prefs.getBool('mesting_user_agreement_accepted_v1'), isTrue);
      expect(prefs.getBool('mesting_privacy_policy_accepted_v1'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
