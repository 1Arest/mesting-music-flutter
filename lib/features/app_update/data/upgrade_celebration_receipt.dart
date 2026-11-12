import 'package:shared_preferences/shared_preferences.dart';
import '../domain/app_update_models.dart';

/// One local receipt per installed package, shared by all music accounts.
/// Android install times also handle the first migration from older builds
/// which did not yet persist a celebration receipt.
class UpgradeCelebrationReceipt {
  const UpgradeCelebrationReceipt(this.preferences);
  final SharedPreferences preferences;
  String _key(AppVersionInfo v) =>
      'music_upgrade_celebration_v1_${v.packageName}';

  bool shouldCelebrate(AppVersionInfo v) =>
      v.isUpgradedInstall && (preferences.getInt(_key(v)) ?? 0) < v.versionCode;

  Future<void> acknowledge(AppVersionInfo v) async {
    if ((preferences.getInt(_key(v)) ?? 0) >= v.versionCode) return;
    if (!await preferences.setInt(_key(v), v.versionCode)) {
      throw StateError('Unable to persist update success receipt');
    }
  }
}
