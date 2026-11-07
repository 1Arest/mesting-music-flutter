import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persistence/app_preferences.dart';
import '../../core/platform/distribution_channel.dart';

const appBrandStylePreferenceKey = 'app_brand_style';

enum AppBrandStyle { coral, morningMist, midnightVinyl }

extension AppBrandStyleDetails on AppBrandStyle {
  String get id => switch (this) {
    AppBrandStyle.coral => 'coral',
    AppBrandStyle.morningMist => 'morning_mist',
    AppBrandStyle.midnightVinyl => 'midnight_vinyl',
  };

  String get name => switch (this) {
    AppBrandStyle.coral => '珊瑚原声',
    AppBrandStyle.morningMist => '晨雾律动',
    AppBrandStyle.midnightVinyl => '午夜唱片',
  };

  String get description => switch (this) {
    AppBrandStyle.coral => '温暖珊瑚红与经典 M 标记',
    AppBrandStyle.morningMist => '暖米晨光、薄荷节拍与深青 M 标记',
    AppBrandStyle.midnightVinyl => '深海蓝黑、青绿唱片轨迹与金色唱针',
  };

  String? get iconAsset => switch (this) {
    AppBrandStyle.coral => null,
    AppBrandStyle.morningMist => 'assets/branding/dress-morning-icon-v2.png',
    AppBrandStyle.midnightVinyl => 'assets/branding/dress-midnight-icon-v2.png',
  };

  String? get launchAsset => switch (this) {
    AppBrandStyle.coral => null,
    AppBrandStyle.morningMist => 'assets/branding/dress-morning-launch.webp',
    AppBrandStyle.midnightVinyl =>
      'assets/branding/dress-midnight-launch-v2.webp',
  };
}

AppBrandStyle appBrandStyleById(String? id) => AppBrandStyle.values.firstWhere(
  (style) => style.id == id,
  orElse: () => AppBrandStyle.coral,
);

class AppBrandStyleBridge {
  const AppBrandStyleBridge._();

  static const _channel = MethodChannel('com.mesting.music/brand_style');

  static Future<AppBrandStyle> current() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AppBrandStyle.coral;
    }
    try {
      final id = await _channel.invokeMethod<String>('getBrandStyle');
      return appBrandStyleById(id);
    } on MissingPluginException {
      return AppBrandStyle.coral;
    } on PlatformException {
      return AppBrandStyle.coral;
    }
  }

  static Future<void> select(AppBrandStyle style) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('queueBrandStyle', {'style': style.id});
  }

  static Future<bool> applyQueuedStyle() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('applyQueuedBrandStyle') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> syncLaunchTheme(
    ThemeMode mode, {
    bool updateLauncher = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setLaunchThemeMode', {
        'mode': mode.name,
        'updateLauncher': updateLauncher,
      });
    } on MissingPluginException {
      // Older debug hosts may not expose the launch-theme bridge yet.
    } on PlatformException {
      // The Flutter launch screen still follows the saved theme preference.
    }
  }
}

class AppBrandStyleController extends Notifier<AppBrandStyle> {
  @override
  AppBrandStyle build() {
    if (DistributionChannel.isBeta) return AppBrandStyle.coral;
    final saved = ref
        .watch(sharedPreferencesProvider)
        .getString(appBrandStylePreferenceKey);
    return appBrandStyleById(saved);
  }

  Future<void> select(AppBrandStyle style) async {
    if (DistributionChannel.isBeta) style = AppBrandStyle.coral;
    if (style == state) return;
    final previous = state;
    final preferences = ref.read(sharedPreferencesProvider);
    state = style;
    try {
      await AppBrandStyleBridge.select(style);
      await preferences.setString(appBrandStylePreferenceKey, style.id);
      final applied = await AppBrandStyleBridge.applyQueuedStyle();
      if (!applied) {
        throw PlatformException(
          code: 'brand_style_not_applied',
          message: 'Android 未能完成品牌套装图标切换',
        );
      }
    } on Object {
      state = previous;
      await preferences.setString(appBrandStylePreferenceKey, previous.id);
      rethrow;
    }
  }
}

final appBrandStyleProvider =
    NotifierProvider<AppBrandStyleController, AppBrandStyle>(
      AppBrandStyleController.new,
    );
