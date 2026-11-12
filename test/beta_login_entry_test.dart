
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/presentation/first_launch_auth_coordinator.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyPlatformStore implements PlatformSessionStore {
  @override
  Future<PlatformSession?> read() async => null;
  @override
  Future<void> write(PlatformSession session) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  testWidgets(
    'Beta first install exposes two logins and guest from platform storage',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mesting_user_agreement_accepted_v1': true,
        'mesting_privacy_policy_accepted_v1': true,
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),

            platformSessionStoreProvider.overrideWithValue(
              _EmptyPlatformStore(),
            ),
          ],
          child: const MaterialApp(
            home: FirstLaunchAuthCoordinator(
              child: Scaffold(body: Text('推荐页面')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // The current Beta welcome first chooses a platform, then a method.
      // Legacy CloudBase restoration must not gate either of these routes.
      expect(find.text('酷狗登录'), findsOneWidget);
      expect(find.text('网易云登录'), findsOneWidget);
      expect(find.text('游客体验'), findsOneWidget);
      await tester.tap(find.text('酷狗登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('手机号登录'), findsOneWidget);
      expect(find.text('微信扫码登录'), findsOneWidget);

      await tester.tap(find.text('手机号登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('手机号登录'), findsOneWidget);
      expect(find.text('酷狗扫码'), findsNothing);
      expect(find.text('微信扫码'), findsNothing);
      expect(find.text('QQ 扫码'), findsNothing);
      await tester.tap(find.byType(BetaGlassBackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(BetaGlassBackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('音乐平台账号'), findsNothing);
      await tester.tap(find.text('游客体验'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('推荐页面'), findsOneWidget);
      expect(preferences.getBool(firstLaunchAuthCompletedPreferenceKey), true);
      await tester.pump();
    },
    skip: !DistributionChannel.isBeta,
  );
}
