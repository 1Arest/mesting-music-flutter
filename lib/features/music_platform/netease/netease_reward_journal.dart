import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A tiny account-owned write-ahead journal prevents a lost reward reply from
/// being sent again after process death. It stores only the day and a public
/// counter checkpoint, never cookies, tokens, ad identifiers or response bodies.
class NeteaseRewardJournal {
  NeteaseRewardJournal(this.preferences);
  final SharedPreferences? preferences;
  final _memory = <String, Map<String, dynamic>>{};

  static String key(String owner, String action) =>
      'mesting.netease.reward.pending.$owner.$action';

  Map<String, dynamic>? read(String owner, String action) {
    final identity = key(owner, action);
    final encoded = preferences?.getString(identity);
    if (encoded == null) return _memory[identity];
    try {
      final value = jsonDecode(encoded);
      if (value is Map) return Map<String, dynamic>.from(value);
    } on Object {
      // An unreadable pending marker cannot safely be treated as no request.
    }
    return const {'unreadable': true};
  }

  Future<void> begin(
    String owner,
    String action,
    Map<String, dynamic> checkpoint,
  ) async {
    final identity = key(owner, action);
    if (preferences != null &&
        !await preferences!.setString(identity, jsonEncode(checkpoint))) {
      throw StateError('Reward checkpoint was not saved');
    }
    _memory[identity] = Map.unmodifiable(checkpoint);
  }

  Future<void> clear(String owner, String action) async {
    final identity = key(owner, action);
    // Keep a failed removal in memory as pending. A future deliberate request
    // will reconcile it through an authoritative read before issuing a write.
    if (preferences != null && !await preferences!.remove(identity)) return;
    _memory.remove(identity);
  }
}
