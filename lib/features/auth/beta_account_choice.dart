import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/persistence/app_preferences.dart';

/// Selection is separate from either credential format. A saved guest choice
/// prevents an old credential from becoming active again after logout.
enum BetaAccountChoice { guest, kugou, netease, qishui }

final betaAccountChoiceProvider =
    NotifierProvider<BetaAccountChoiceController, BetaAccountChoice?>(
      BetaAccountChoiceController.new,
    );

class BetaAccountChoiceController extends Notifier<BetaAccountChoice?> {
  static const preferenceKey = 'beta_active_account_v2';

  @override
  BetaAccountChoice? build() {
    final saved = ref.read(sharedPreferencesProvider).getString(preferenceKey);
    // A retired account choice must not silently activate a saved platform.
    // Keep every platform credential and local database row intact; the user
    // can explicitly select a supported platform from the guest surface.
    if (saved == 'mesting') return BetaAccountChoice.guest;
    return BetaAccountChoice.values
        .where((value) => value.name == saved)
        .firstOrNull;
  }

  Future<void> select(BetaAccountChoice choice) async {
    final saved = await ref
        .read(sharedPreferencesProvider)
        .setString(preferenceKey, choice.name);
    if (!saved) throw StateError('无法保存账号选择，请重试');
    state = choice;
  }
}
