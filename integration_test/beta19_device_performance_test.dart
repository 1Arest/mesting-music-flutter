import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/presentation/beta_entry_coordinator.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/music_platform/domain/platform_rewards.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_reward_calendar.dart';
import 'package:mesting_music/features/settings/presentation/haptic_settings_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/app/startup_image_surface.dart';
import 'package:mesting_music/features/themes/startup_style.dart';
import 'package:mesting_music/features/player/presentation/shinchan_progress_walker.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';

class _NoPlatformAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

class _FailedPlatformAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      throw const FormatException('Local recovery fixture');
}

class _NoLegacyAccount extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

/// The production calendar is exercised against local state. Overscroll may
/// invoke refresh, so that operation is also local; no rewards are claimed.
class _LocalRewardCalendar extends PlatformRewardsController {
  @override
  PlatformRewardState build() => PlatformRewardState(
    ownerId: 'native-glass-fixture',
    snapshot: RewardSnapshot(now: DateTime(2026, 10, 27)),
  );

  @override
  Future<void> refresh() async {}
}

/// Native optical regression fixtures. Run in the isolated benchmark package
/// with --keep-app-running; preferences are memory-only. No credential is read,
/// cleared or replaced, and reward refresh is a local no-op.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'native controls keep their material during page scrolling',
    (tester) async {
      expect(const bool.fromEnvironment('MESTING_ISOLATED_BENCHMARK'), isTrue);
      SharedPreferences.setMockInitialValues({
        'mesting_first_launch_auth_completed_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();
      // Local provider overrides show the production login form without signing
      // out, replacing, or clearing the user's real encrypted account.
      Future<void> show(Widget page, {bool restoreError = false}) async {
        await tester.pumpWidget(
          LiquidGlassWidgets.wrap(
            brightnessResolver: Theme.maybeBrightnessOf,
            adaptiveQuality: false,
            child: ProviderScope(
              // An error fixture needs a new Notifier instance. Updating an
              // override factory on the existing scope retains its controller.
              key: ValueKey(restoreError),
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                platformAccountProvider.overrideWith(
                  restoreError
                      ? _FailedPlatformAccount.new
                      : _NoPlatformAccount.new,
                ),
                authControllerProvider.overrideWith(_NoLegacyAccount.new),
                platformRewardsProvider.overrideWith(_LocalRewardCalendar.new),
              ],
              child: MaterialApp(
                theme: buildMestingTheme(musicThemePresetById('classic')),
                home: page,
              ),
            ),
          ),
        );
        await _wait(tester, const Duration(seconds: 1));
      }

      Future<void> capture(String name, Finder target) async {
        // Capture Android's actual compositor output with the desktop companion.
        // Converting SurfaceView to ImageView would change the path under test.
        final rect = tester.getRect(target);
        final scale = tester.view.devicePixelRatio;
        // ignore: avoid_print
        print(
          'MESTING_DEVICE_CAPTURE $name ${jsonEncode({'left': rect.left * scale, 'top': rect.top * scale, 'width': rect.width * scale, 'height': rect.height * scale})}',
        );
        await _wait(tester, const Duration(milliseconds: 900));
      }

      Future<void> scrollButton(Finder button, String prefix) async {
        await capture('$prefix-before', button);
        for (final dy in [-90.0, 90.0]) {
          final direction = dy < 0 ? 'up' : 'down';
          final finger = await tester.startGesture(tester.getCenter(button));
          await finger.moveBy(Offset(0, dy));
          await _wait(tester, const Duration(milliseconds: 180));
          await capture('$prefix-$direction-drag', button);
          await finger.up();
          await _wait(tester, const Duration(milliseconds: 600));
          await capture('$prefix-$direction-after', button);
        }
        final background = await tester.startGesture(
          tester.getCenter(button) + const Offset(0, 110),
        );
        await background.moveBy(const Offset(0, -100));
        await _wait(tester, const Duration(milliseconds: 180));
        await capture('$prefix-page-drag', button);
        await background.up();
      }

      await show(const HapticSettingsPage());
      await scrollButton(
        find.byKey(const ValueKey('haptics-preview')),
        'haptics',
      );
      await show(const PlatformAccountPage());
      await scrollButton(
        find
            .ancestor(
              of: find.text('登录'),
              matching: find.byType(BetaGlassButton),
            )
            .first,
        'phone',
      );
      await show(const PlatformRewardCalendar());
      for (final (label, name) in [
        ('签到', 'sign-in'),
        ('听歌领取', 'listen'),
        ('广告领取', 'ad'),
      ]) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(BetaGlassButton),
        );
        await tester.ensureVisible(button);
        await _wait(tester, const Duration(milliseconds: 600));
        await scrollButton(button, 'rewards-$name');
      }
      for (final style in [StartupStyle.staticOne, StartupStyle.staticTwo]) {
        await show(StartupImageSurface(style: style));
        await capture('startup-${style.id}', find.byType(StartupImageSurface));
      }
      for (final weather in ShinchanProgressWeather.values) {
        await show(
          Scaffold(
            body: Center(
              child: ShinchanProgressWalker(
                presetId: 'classic',
                weather: weather,
                playing: true,
              ),
            ),
          ),
        );
        await capture(
          'weather-${weather.name}',
          find.byType(ShinchanProgressWalker),
        );
      }
      await show(
        const BetaEntryCoordinator(child: Scaffold(body: SizedBox.expand())),
        restoreError: true,
      );
      expect(find.text('账号暂未恢复，登录信息已保留'), findsOneWidget);
      final text = tester.element(find.text('账号暂未恢复，登录信息已保留'));
      expect(DefaultTextStyle.of(text).style.fontSize, lessThan(20));
      await capture(
        'startup-account-recovery',
        find.byType(BetaEntryCoordinator),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Wall-clock pumps leave Android's vsync and Impeller in charge of frame rate.
/// Advancing a fake test clock by 8ms would manufacture a 120Hz result.
Future<void> _wait(WidgetTester tester, Duration duration) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await tester.pump();
  }
}
