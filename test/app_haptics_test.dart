import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/haptics/app_haptics.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/settings/presentation/haptic_settings_page.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';

class _Bridge extends HapticBridge {
  final events = <(AppHapticEvent, HapticStrength)>[];
  @override
  Future<bool> emit(AppHapticEvent event, HapticStrength strength) async {
    events.add((event, strength));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);

  test(
    'haptic preferences persist independently of account restoration',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      expect(
        container.read(hapticPreferencesProvider).strength,
        HapticStrength.light,
      );
      await container
          .read(hapticPreferencesProvider.notifier)
          .setStrength(HapticStrength.strong);
      await container
          .read(hapticPreferencesProvider.notifier)
          .setEnabled(false);
      container.dispose();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(hapticPreferencesProvider).enabled, false);
      expect(
        container.read(hapticPreferencesProvider).strength,
        HapticStrength.strong,
      );
    },
  );

  test(
    'haptics coalesce duplicate gestures and disabled includes previews',
    () async {
      var prefs = const HapticPreferences(strength: HapticStrength.medium);
      final bridge = _Bridge();
      final feedback = AppHaptics(preferences: () => prefs, bridge: bridge);
      expect(await feedback.perform(AppHapticEvent.selection), true);
      expect(await feedback.perform(AppHapticEvent.impact), false);
      expect(
        await feedback.perform(AppHapticEvent.impact, preview: true),
        true,
      );
      expect(bridge.events, [
        (AppHapticEvent.selection, HapticStrength.medium),
        (AppHapticEvent.impact, HapticStrength.medium),
      ]);
      prefs = const HapticPreferences(enabled: false);
      expect(
        await feedback.perform(AppHapticEvent.success, preview: true),
        false,
      );
      expect(bridge.events.length, 2);
    },
  );

  test(
    'native haptic contract carries semantic event and selected strength',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HapticBridge.channel, (call) async {
        calls.add(call);
        return false;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(HapticBridge.channel, null),
      );
      expect(
        await HapticBridge().emit(
          AppHapticEvent.success,
          HapticStrength.strong,
        ),
        false,
      );
      expect(calls.single.method, 'emit');
      expect(calls.single.arguments, {'kind': 'success', 'strength': 2});
    },
  );

  testWidgets(
    'small large-text haptic settings preview once and disable cleanly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final bridge = _Bridge();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          hapticBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const HapticSettingsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('haptics-preview')));
      await tester.pump();
      expect(bridge.events.length, 1);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();
      expect(container.read(hapticPreferencesProvider).enabled, false);
      expect(
        tester
            .widget<BetaGlassButton>(
              find.byKey(const ValueKey('haptics-preview')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
