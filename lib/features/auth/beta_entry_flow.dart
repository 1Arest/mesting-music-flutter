import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/persistence/app_preferences.dart';

enum BetaEntryStage { idle, welcome, success, guide, app }

/// Explicit login events are separate from credential restoration/refresh.
/// A QR poll cannot open multiple tours; each fresh login after logout can.
final betaEntryFlowProvider = NotifierProvider<BetaEntryFlow, BetaEntryStage>(
  BetaEntryFlow.new,
);

class BetaEntryFlow extends Notifier<BetaEntryStage> {
  static const completedKey = 'mesting_first_launch_auth_completed_v1';
  @override
  BetaEntryStage build() => BetaEntryStage.idle;
  void authenticated() {
    if (state == BetaEntryStage.success || state == BetaEntryStage.guide) {
      return;
    }
    state = BetaEntryStage.success;
  }

  void showGuide() {
    if (state == BetaEntryStage.success) state = BetaEntryStage.guide;
  }

  Future<void> finish() async {
    final saved = await ref
        .read(sharedPreferencesProvider)
        .setBool(completedKey, true);
    if (!saved) throw StateError('无法保存进入状态，请重试');
    state = BetaEntryStage.app;
  }

  Future<void> welcome() async {
    await ref.read(sharedPreferencesProvider).setBool(completedKey, false);
    state = BetaEntryStage.welcome;
  }
}
