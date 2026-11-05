import '../../../core/security/retained_credential_vault.dart';
import 'dart:convert';

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
  RetainedCredentialVault get _vault => RetainedCredentialVault(_storage);

  @override
  Future<PlatformSession?> read() async {
    final value = await _vault.read(key);
    return value == null
        ? null
        : _vault.decode(
            key,
            () => PlatformSession.fromJson(
              jsonDecode(value) as Map<String, dynamic>,
            ),
          );
  }

  @override
  Future<void> write(PlatformSession session) async {
    final encoded = jsonEncode(session.toJson());
    await _vault.write(key, encoded);
  }

  @override
  Future<void> clear() => _vault.clear(key);
}
