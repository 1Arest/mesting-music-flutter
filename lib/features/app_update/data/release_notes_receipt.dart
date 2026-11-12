import 'package:shared_preferences/shared_preferences.dart';
import '../domain/app_update_models.dart';

/// Local acknowledgement belongs to the installed package/build, independently
/// of network update checks, download snoozes and the user's music account.
class ReleaseNotesReceipt {
  const ReleaseNotesReceipt(this.preferences);
  final SharedPreferences preferences;

  String _key(AppVersionInfo version) =>
      'music_release_notes_seen_v1_${version.packageName}';
  String _identity(AppVersionInfo version) =>
      '${version.versionCode}:${version.versionName.trim()}';

  bool hasSeen(AppVersionInfo version) =>
      preferences.getString(_key(version)) == _identity(version);

  /// Call only after the sheet is dismissed. An interrupted launch must not
  /// consume the next opportunity to read this build's actual bundled notes.
  Future<void> acknowledge(AppVersionInfo version) async {
    if (!await preferences.setString(_key(version), _identity(version))) {
      throw StateError('Unable to persist release notes acknowledgement');
    }
  }
}
