import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// HTTP and P2P share the existing random installation identity. No hardware,
/// account or network identity is used, and none of these values are logged.
class AppUpgradeP2PIdentity {
  static const _deviceKey = 'app_upgrade.v40.device_id';
  static Future<void> _queue = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static Future<String> deviceId() => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKey) ?? '';
    if (RegExp(r'^[A-Za-z0-9._\-]{8,64}$').hasMatch(existing)) return existing;
    final value = const Uuid().v4();
    if (!await prefs.setString(_deviceKey, value)) {
      throw StateError('identity_storage_failed');
    }
    return value;
  });

  /// Retain the exact session body and key across uncertain responses/process
  /// death. A retry must not change even network/pieces in the original body;
  /// reconcile current network policy with a heartbeat after acquiring token.
  static Future<AppUpgradeP2PSessionRequest> sessionRequest({
    required String apiBase,
    required String sha,
    required bool sharing,
    required Map<String, Object?> body,
  }) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = sha256.convert(utf8.encode('$apiBase|$sha|$sharing'));
    final storageKey = 'app_upgrade.p2p.pending.$scope';
    try {
      final stored = jsonDecode(prefs.getString(storageKey) ?? '') as Map;
      final key = stored['key'];
      final created = DateTime.parse(stored['created'] as String);
      final age = DateTime.now().toUtc().difference(created);
      if (key is String &&
          RegExp(r'^[a-f0-9]{32}$').hasMatch(key) &&
          age >= Duration.zero &&
          age < const Duration(minutes: 3) &&
          stored['body'] is Map) {
        return AppUpgradeP2PSessionRequest(
          storageKey,
          key,
          Map<String, Object?>.from(stored['body'] as Map),
        );
      }
    } catch (_) {
      // Absent/invalid/expired task metadata starts a new bounded attempt.
    }
    final random = Random.secure();
    final key = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final snapshot = Map<String, Object?>.unmodifiable(body);
    if (!await prefs.setString(
      storageKey,
      jsonEncode({
        'key': key,
        'created': DateTime.now().toUtc().toIso8601String(),
        'body': snapshot,
      }),
    )) {
      throw StateError('identity_storage_failed');
    }
    return AppUpgradeP2PSessionRequest(storageKey, key, snapshot);
  });

  /// A late cleanup can remove only its own request, never a newer task's key.
  static Future<void> release(AppUpgradeP2PSessionRequest request) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        try {
          final stored =
              jsonDecode(prefs.getString(request.storageKey) ?? '') as Map;
          if (stored['key'] == request.key) {
            await prefs.remove(request.storageKey);
          }
        } catch (_) {}
      });
}

class AppUpgradeP2PSessionRequest {
  const AppUpgradeP2PSessionRequest(this.storageKey, this.key, this.body);
  final String storageKey;
  final String key;
  final Map<String, Object?> body;
}
