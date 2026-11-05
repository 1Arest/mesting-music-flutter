import '../../../core/security/retained_secure_read.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/retained_secure_storage.dart';
import '../domain/platform_session.dart';

/// Cookies never occupy Kugou's token field or its secure-storage key. The
/// public identity uses a digest only to reject work from a replaced login.
class NeteaseSession {
  const NeteaseSession({
    required this.userId,
    required this.cookies,
    required this.deviceId,
    this.nickname = '',
    this.avatarUrl = '',
  });
  final String userId, deviceId, nickname, avatarUrl;
  final Map<String, String> cookies;

  String get credentialId =>
      sha256.convert(utf8.encode(cookies['MUSIC_U'] ?? '')).toString();
  PlatformSession get identity => PlatformSession(
    userId: userId,
    token: credentialId,
    nickname: nickname,
    avatarUrl: avatarUrl,
    platform: MusicPlatform.netease,
  );

  Map<String, Object?> toJson() => {
    'userId': userId,
    'cookies': cookies,
    'deviceId': deviceId,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
  };

  factory NeteaseSession.fromJson(Map<String, dynamic> json) {
    final cookies = Map<String, String>.from(json['cookies'] as Map);
    final userId = '${json['userId'] ?? ''}';
    final device = '${json['deviceId'] ?? ''}';
    if (userId.isEmpty ||
        device.isEmpty ||
        (cookies['MUSIC_U'] ?? '').isEmpty) {
      throw const FormatException('网易云登录凭证不完整');
    }
    return NeteaseSession(
      userId: userId,
      cookies: Map.unmodifiable(cookies),
      deviceId: device,
      nickname: '${json['nickname'] ?? ''}',
      avatarUrl: PlatformSession.picture(json['avatarUrl']),
    );
  }
}

abstract interface class NeteaseSessionStore {
  Future<NeteaseSession?> read();
  Future<void> write(NeteaseSession session);
  Future<void> clear();
}

class SecureNeteaseSessionStore implements NeteaseSessionStore {
  const SecureNeteaseSessionStore({
    FlutterSecureStorage storage = retainedSecureStorage,
  }) : _storage = storage;
  static const key = 'mesting_music_platform_netease_session_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<NeteaseSession?> read() async {
    // A failed restore must leave the encrypted bytes available for recovery.
    final encoded = await readRetainedSecureValue(_storage, key);
    return encoded == null
        ? null
        : NeteaseSession.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
  }

  @override
  Future<void> write(NeteaseSession session) async {
    final encoded = jsonEncode(session.toJson());
    await _storage.write(key: key, value: encoded);
    if (await _storage.read(key: key) != encoded) {
      throw StateError('网易云账号保存未完成，请重试');
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: key);
}
