import '../../../core/security/retained_secure_read.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/platform_session.dart';
import '../../../core/security/retained_secure_storage.dart';

abstract interface class PlatformSessionStore {
  Future<PlatformSession?> read();
  Future<void> write(PlatformSession session);
  Future<void> clear();
}

/// Separate key and repository: signing out of either account cannot clear the
/// other provider. No credentials are written to preferences, logs or exports.
class SecurePlatformSessionStore implements PlatformSessionStore {
  const SecurePlatformSessionStore({
    FlutterSecureStorage storage = retainedSecureStorage,
  }) : _storage = storage;

  static const key = 'mesting_music_platform_kugou_session_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<PlatformSession?> read() async {
    // Android may briefly reject an encrypted read while its engine/keystore
    // attaches. Retry only that transport failure; never delete credentials on
    // a cold-start read or JSON failure. Explicit signOut is the sole eraser.
    for (var attempt = 0; ; attempt++) {
      try {
        final value = await readRetainedSecureValue(_storage, key);
        if (value == null) {
          if (attempt >= 2) return null;
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
          continue;
        }
        return PlatformSession.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
      } on PlatformException {
        if (attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
  }

  @override
  Future<void> write(PlatformSession session) async {
    final encoded = jsonEncode(session.toJson());
    await _storage.write(key: key, value: encoded);
    // Publish success only after a durable round-trip, not just a platform ACK.
    if (await _storage.read(key: key) != encoded) {
      throw StateError('账号保存未完成，请重试登录');
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: key);
}
