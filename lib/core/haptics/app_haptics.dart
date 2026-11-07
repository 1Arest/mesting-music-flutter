import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../persistence/app_preferences.dart';

enum HapticStrength {
  light('轻'),
  medium('中'),
  strong('强');

  const HapticStrength(this.label);
  final String label;
}

enum AppHapticEvent { selection, impact, success, warning }

class HapticPreferences {
  const HapticPreferences({
    this.enabled = true,
    this.strength = HapticStrength.light,
  });
  final bool enabled;
  final HapticStrength strength;
}

final hapticPreferencesProvider =
    NotifierProvider<HapticPreferencesController, HapticPreferences>(
      HapticPreferencesController.new,
    );

/// One device preference, independent of accounts, themes and audio playback.
/// Reads are cached; persistence never sits on an animation's frame callback.
class HapticPreferencesController extends Notifier<HapticPreferences> {
  static const enabledKey = 'app_haptics_enabled_v1';
  static const strengthKey = 'app_haptics_strength_v1';
  @override
  HapticPreferences build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return HapticPreferences(
      enabled: prefs.getBool(enabledKey) ?? true,
      strength:
          HapticStrength.values
              .where((s) => s.name == prefs.getString(strengthKey))
              .firstOrNull ??
          HapticStrength.light,
    );
  }

  Future<void> setEnabled(bool value) async {
    state = HapticPreferences(enabled: value, strength: state.strength);
    await ref.read(sharedPreferencesProvider).setBool(enabledKey, value);
  }

  Future<void> setStrength(HapticStrength value) async {
    state = HapticPreferences(enabled: state.enabled, strength: value);
    await ref
        .read(sharedPreferencesProvider)
        .setString(strengthKey, value.name);
  }
}

/// Platform contract is injectable, so settings and action coverage can verify
/// real intents without making the test host vibrate or creating an audio owner.
class HapticBridge {
  static const channel = MethodChannel('com.mesting.music/haptics');
  Future<bool> emit(AppHapticEvent event, HapticStrength strength) async {
    try {
      return await channel.invokeMethod<bool>('emit', {
            'kind': event.name,
            'strength': strength.index,
          }) ??
          false;
    } on MissingPluginException {
      // Other Flutter targets retain the system's own semantic patterns.
      switch (strength) {
        case HapticStrength.light:
          await HapticFeedback.lightImpact();
        case HapticStrength.medium:
          await HapticFeedback.mediumImpact();
        case HapticStrength.strong:
          await HapticFeedback.heavyImpact();
      }
      return true;
    } on PlatformException {
      return false;
    }
  }
}

final hapticBridgeProvider = Provider<HapticBridge>((ref) => HapticBridge());
final appHapticsProvider = Provider<AppHaptics>(
  (ref) => AppHaptics(
    preferences: () => ref.read(hapticPreferencesProvider),
    bridge: ref.read(hapticBridgeProvider),
  ),
);

class AppHaptics {
  AppHaptics({required this.preferences, required this.bridge});
  final HapticPreferences Function() preferences;
  final HapticBridge bridge;
  final _clock = Stopwatch()..start();
  int _last = -1000;

  Future<bool> perform(AppHapticEvent event, {bool preview = false}) async {
    final settings = preferences();
    if (!settings.enabled) return false;
    // Nested controls may describe the same gesture. Coalesce their tactile
    // intent, while preview deliberately plays the currently selected strength.
    final now = _clock.elapsedMilliseconds;
    if (!preview && now - _last < 70) return false;
    _last = now;
    try {
      return await bridge.emit(event, settings.strength);
    } catch (_) {
      return false;
    }
  }

  void feedback(AppHapticEvent event) => unawaited(perform(event));
}

/// Shared presentation surfaces can also be shown in standalone galleries.
/// They remain usable without a ProviderScope; the application always has one.
void appHaptic(BuildContext context, AppHapticEvent event) {
  try {
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(appHapticsProvider).feedback(event);
  } catch (_) {
    /* A standalone visual preview may have no settings owner. */
  }
}
