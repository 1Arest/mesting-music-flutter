import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/themes/app_brand_style.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mesting.music/brand_style');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'brand style selection is queued for next launch and persists',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      String? selectedOnAndroid;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'queueBrandStyle') {
              selectedOnAndroid =
                  (call.arguments as Map<Object?, Object?>)['style'] as String?;
              return null;
            }
            if (call.method == 'applyQueuedBrandStyle') return true;
            return 'coral';
          });
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);

      await container
          .read(appBrandStyleProvider.notifier)
          .select(AppBrandStyle.morningMist);

      expect(container.read(appBrandStyleProvider), AppBrandStyle.morningMist);
      expect(selectedOnAndroid, 'morning_mist');
      expect(preferences.getString(appBrandStylePreferenceKey), 'morning_mist');
    },
  );

  test(
    'brand style selection applies the queued alias after persistence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'applyQueuedBrandStyle') return true;
            return null;
          });
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);

      await container
          .read(appBrandStyleProvider.notifier)
          .select(AppBrandStyle.midnightVinyl);

      expect(methods, <String>['queueBrandStyle', 'applyQueuedBrandStyle']);
      expect(methods, isNot(contains('setBrandStyle')));
    },
  );

  test(
    'failed launcher application rolls back the selected brand preference',
    () async {
      SharedPreferences.setMockInitialValues({
        appBrandStylePreferenceKey: AppBrandStyle.coral.id,
      });
      final preferences = await SharedPreferences.getInstance();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'applyQueuedBrandStyle') return false;
            return null;
          });
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(appBrandStyleProvider.notifier)
            .select(AppBrandStyle.morningMist),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'brand_style_not_applied',
          ),
        ),
      );

      expect(container.read(appBrandStyleProvider), AppBrandStyle.coral);
      expect(preferences.getString(appBrandStylePreferenceKey), 'coral');
    },
  );

  test('launch theme mode is synchronized with Android', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    await AppBrandStyleBridge.syncLaunchTheme(ThemeMode.light);
    await AppBrandStyleBridge.syncLaunchTheme(ThemeMode.dark);
    await AppBrandStyleBridge.syncLaunchTheme(ThemeMode.system);

    expect(
      calls.map((call) => call.method),
      everyElement('setLaunchThemeMode'),
    );
    expect(
      calls.map(
        (call) => (call.arguments as Map<Object?, Object?>)['mode'] as String?,
      ),
      <String>['light', 'dark', 'system'],
    );
    expect(
      calls.map(
        (call) =>
            (call.arguments as Map<Object?, Object?>)['updateLauncher']
                as bool?,
      ),
      everyElement(isFalse),
    );
  });

  test(
    'music theme selection never changes the active launcher component',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(container.dispose);

      await container.read(musicThemeProvider.notifier).select('starry-radio');

      expect(preferences.getString(musicThemePreferenceKey), 'starry-radio');
      expect(calls, hasLength(1));
      expect(calls.single.method, 'setLaunchThemeMode');
      expect(calls.single.arguments, <String, Object>{
        'mode': 'dark',
        'updateLauncher': false,
      });
    },
  );

  test(
    'queued launcher state can be applied only after Flutter is ready',
    () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'applyQueuedBrandStyle') return true;
            return null;
          });

      expect(await AppBrandStyleBridge.applyQueuedStyle(), isTrue);
      expect(methods, <String>['applyQueuedBrandStyle']);
    },
  );

  test('unknown saved style safely falls back to coral', () async {
    SharedPreferences.setMockInitialValues({
      appBrandStylePreferenceKey: 'retired-style',
    });
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(container.read(appBrandStyleProvider), AppBrandStyle.coral);
  });

  test('formal brand artwork is declared only for its distribution', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().toSet();

    for (final style in <AppBrandStyle>[
      AppBrandStyle.morningMist,
      AppBrandStyle.midnightVinyl,
    ]) {
      for (final asset in <String?>[style.iconAsset, style.launchAsset]) {
        expect(asset, isNotNull, reason: style.id);
        expect(File(asset!).existsSync(), isTrue, reason: asset);
        expect(
          assets.contains(asset),
          !DistributionChannel.isBeta,
          reason: asset,
        );
      }
    }
  });
}
