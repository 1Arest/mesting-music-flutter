import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/app_preferences.dart';
import '../../core/platform/distribution_channel.dart';

/// Startup media is independent of launcher aliases, player style and theme.
/// Beta.19 adds static art without retiring either existing film.
const startupStylePreferenceKey = 'beta12_startup_style';
const beta19StartupMigrationKey = 'beta19_static_startup_migrated';

enum StartupStyle {
  staticOne(
    'static-one',
    '音乐伙伴 · 静态',
    'assets/branding/startup/companions-static-1',
    staticImage: true,
  ),
  staticTwo(
    'static-two',
    '声音伙伴 · 静态',
    'assets/branding/startup/companions-static-2',
    staticImage: true,
  ),
  companionsOne('video-one', '音乐伙伴', 'assets/branding/startup/companions-1'),
  companionsTwo('video-two', '唱片派对', 'assets/branding/startup/companions-2'),
  classic('classic', '经典启动页', null);

  const StartupStyle(
    this.id,
    this.label,
    this.assetBase, {
    this.staticImage = false,
  });
  final String id;
  final String label;
  final String? assetBase;
  final bool staticImage;
  bool get isVideo => assetBase != null && !staticImage;
  String? get videoAsset => isVideo ? '$assetBase.mp4' : null;
  String? get posterAsset =>
      assetBase == null ? null : '$assetBase.${staticImage ? 'png' : 'webp'}';
}

/// Explicitly confirmed upgrade rule: switch once, then respect later choices.
/// Never use a per-launch default write, which would overwrite user selections.
Future<void> migrateBeta19StartupStyle(SharedPreferences preferences) async {
  if (!DistributionChannel.isBeta ||
      preferences.getBool(beta19StartupMigrationKey) == true) {
    return;
  }
  final saved = await preferences.setString(
    startupStylePreferenceKey,
    StartupStyle.staticOne.id,
  );
  if (saved) await preferences.setBool(beta19StartupMigrationKey, true);
}

StartupStyle savedStartupStyle(SharedPreferences preferences) =>
    StartupStyle.values.firstWhere(
      (style) => style.id == preferences.getString(startupStylePreferenceKey),
      orElse: () => DistributionChannel.isBeta
          ? StartupStyle.staticOne
          : StartupStyle.companionsOne,
    );

class StartupStyleController extends Notifier<StartupStyle> {
  @override
  StartupStyle build() =>
      savedStartupStyle(ref.watch(sharedPreferencesProvider));

  Future<void> select(StartupStyle style) async {
    // Publish after persistence succeeds so the checkmark is never misleading.
    final saved = await ref
        .read(sharedPreferencesProvider)
        .setString(startupStylePreferenceKey, style.id);
    if (!saved) throw StateError('启动页未能保存，请重试');
    if (ref.mounted) state = style;
  }
}

final startupStyleProvider =
    NotifierProvider<StartupStyleController, StartupStyle>(
      StartupStyleController.new,
    );
