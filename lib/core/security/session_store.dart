import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'retained_secure_storage.dart';

import '../../features/auth/domain/auth_models.dart';

class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? retainedSecureStorage;

  static const _sessionKey = 'mesting_auth_session_v1';
  static const _rememberedSessionKey = 'mesting_remembered_auth_session_v1';
  static const _profileKeyPrefix = 'mesting_account_profile_v1_';

  final FlutterSecureStorage _storage;

  Future<AuthSession?> read() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return AuthSession.fromJson(jsonDecode(encoded) as Map<String, Object?>);
    } on Object {
      await clear();
      return null;
    }
  }

  Future<void> write(AuthSession session) async {
    final encoded = jsonEncode(session.toJson());
    await Future.wait<void>([
      _storage.write(key: _sessionKey, value: encoded),
      _storage.write(key: _rememberedSessionKey, value: encoded),
    ]);
  }

  Future<void> clear() => _storage.delete(key: _sessionKey);

  Future<AuthSession?> readRemembered() async {
    final encoded = await _storage.read(key: _rememberedSessionKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return AuthSession.fromJson(jsonDecode(encoded) as Map<String, Object?>);
    } on Object {
      await forgetRemembered();
      return null;
    }
  }

  Future<void> remember(AuthSession session) {
    return _storage.write(
      key: _rememberedSessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<void> restoreRememberedAsActive() async {
    final encoded = await _storage.read(key: _rememberedSessionKey);
    if (encoded == null || encoded.isEmpty) return;
    await _storage.write(key: _sessionKey, value: encoded);
  }

  Future<void> forgetRemembered() =>
      _storage.delete(key: _rememberedSessionKey);

  Future<void> clearAll() async {
    await Future.wait<void>([clear(), forgetRemembered()]);
  }

  Future<AuthUser?> readProfile(String uid) async {
    final encoded = await _storage.read(key: '$_profileKeyPrefix$uid');
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return AuthUser.fromJson(jsonDecode(encoded) as Map<String, Object?>);
    } on Object {
      await _storage.delete(key: '$_profileKeyPrefix$uid');
      return null;
    }
  }

  Future<void> writeProfile(AuthUser user) {
    return _storage.write(
      key: '$_profileKeyPrefix${user.uid}',
      value: jsonEncode(user.toJson()),
    );
  }

  Future<void> deleteProfile(String uid) {
    return _storage.delete(key: '$_profileKeyPrefix$uid');
  }

  Future<void> writeSessionAndProfile(AuthSession session) async {
    await Future.wait<void>([write(session), writeProfile(session.user)]);
  }
}
