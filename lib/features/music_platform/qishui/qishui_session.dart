import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/security/retained_credential_vault.dart';
import '../../../core/security/retained_secure_storage.dart';
import '../domain/platform_session.dart';

/// Passport mobile and PC/Web are different credential scopes. Preserve this
/// distinction across encrypted restore; never rewrite a Cookie's domain.
enum QishuiSessionProtocol { mobile, web }

/// Private Passport state. Only [identity], a non-secret projection, leaves the
/// Soda adapter. In particular no cookie/token may enter Track or MediaItem.
class QishuiSession {
  QishuiSession({
    required this.userId,
    required List<Map<String, String>> cookies,
    Map<String, String> tokens = const {},
    this.nickname = '',
    this.avatarUrl = '',
    this.passportUserId = '',
    this.protocol = QishuiSessionProtocol.mobile,
    this.webDeviceId = '',
    this.webInstallId = '',
    String? loginId,
  }) : cookies = List.unmodifiable(
         cookies.map(Map<String, String>.unmodifiable),
       ),
       tokens = Map.unmodifiable(tokens),
       _loginId = loginId;

  final String userId, nickname, avatarUrl;
  final List<Map<String, String>> cookies;
  final Map<String, String> tokens;
  final String passportUserId;
  final QishuiSessionProtocol protocol;

  /// Non-secret PC/Web identifiers remain encrypted with their own account.
  /// Empty fields preserve compatibility with older stored sessions.
  final String webDeviceId, webInstallId;
  final String? _loginId;
  bool get complete =>
      userId.isNotEmpty &&
      cookies.any(
        (c) =>
            {'sessionid', 'sessionid_ss'}.contains(c['name']) &&
            (c['value'] ?? '').isNotEmpty &&
            (protocol != QishuiSessionProtocol.web ||
                c['domain'] == 'api.qishui.com'),
      );
  String get credentialId =>
      _loginId ??
      sha256
          .convert(
            utf8.encode(jsonEncode({'cookies': cookies, 'tokens': tokens})),
          )
          .toString();
  PlatformSession get identity => PlatformSession(
    userId: userId,
    token: credentialId,
    nickname: nickname,
    avatarUrl: avatarUrl,
    platform: MusicPlatform.qishui,
  );
  QishuiSession withProfile({String? name, String? avatar}) => QishuiSession(
    userId: userId,
    cookies: cookies,
    tokens: tokens,
    nickname: name ?? nickname,
    avatarUrl: avatar ?? avatarUrl,
    passportUserId: passportUserId,
    protocol: protocol,
    webDeviceId: webDeviceId,
    webInstallId: webInstallId,
    loginId: credentialId,
  );
  Map<String, Object?> toJson() => {
    'userId': userId,
    'cookies': cookies,
    'tokens': tokens,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'passportUserId': passportUserId,
    'protocol': protocol.name,
    'webDeviceId': webDeviceId,
    'webInstallId': webInstallId,
    'loginId': credentialId,
  };
  factory QishuiSession.fromJson(Map<String, dynamic> value) {
    final rawProtocol = value['protocol'] ?? 'mobile';
    if (rawProtocol != 'mobile' && rawProtocol != 'web') {
      throw const FormatException('未知的汽水登录协议');
    }
    final webDevice = '${value['webDeviceId'] ?? ''}';
    final webInstall = '${value['webInstallId'] ?? ''}';
    if (webDevice.isNotEmpty && !RegExp(r'^\d{16}$').hasMatch(webDevice) ||
        webInstall.isNotEmpty && !RegExp(r'^\d{15}$').hasMatch(webInstall)) {
      throw const FormatException('汽水扫码会话信息无效');
    }
    final session = QishuiSession(
      userId: '${value['userId'] ?? ''}',
      cookies: (value['cookies'] as List)
          .map((v) => Map<String, String>.from(v as Map))
          .toList(),
      tokens: Map<String, String>.from(value['tokens'] as Map? ?? {}),
      nickname: '${value['nickname'] ?? ''}',
      avatarUrl: PlatformSession.picture(value['avatarUrl']),
      passportUserId: '${value['passportUserId'] ?? ''}',
      protocol: rawProtocol == 'web'
          ? QishuiSessionProtocol.web
          : QishuiSessionProtocol.mobile,
      webDeviceId: webDevice,
      webInstallId: webInstall,
      loginId:
          value['loginId'] is String &&
              RegExp(r'^[a-f0-9]{64}$').hasMatch(value['loginId'] as String)
          ? value['loginId'] as String
          : null,
    );
    if (!session.complete) throw const FormatException('汽水登录凭据不完整');
    return session;
  }
}

abstract interface class QishuiSessionStore {
  Future<QishuiSession?> read();
  Future<void> write(QishuiSession session);
  Future<void> clear();
}

/// Uses the retained vault's durable readback and isolated recovery overlay;
/// never resets the old encrypted database or either existing music account.
class SecureQishuiSessionStore implements QishuiSessionStore {
  const SecureQishuiSessionStore({this.storage = retainedSecureStorage});
  static const key = 'mesting_music_platform_qishui_session_v1';
  final FlutterSecureStorage storage;
  RetainedCredentialVault get _vault => RetainedCredentialVault(storage);
  @override
  Future<QishuiSession?> read() async {
    final value = await _vault.read(key);
    return value == null
        ? null
        : _vault.decode(
            key,
            () => QishuiSession.fromJson(
              jsonDecode(value) as Map<String, dynamic>,
            ),
          );
  }

  @override
  Future<void> write(QishuiSession session) async {
    if (!session.complete) throw const FormatException('汽水登录凭据不完整');
    await _vault.write(key, jsonEncode(session.toJson()));
  }

  Future<CredentialRecoveryWrite> recover(QishuiSession session) =>
      _vault.recover(key, jsonEncode(session.toJson()));
  @override
  Future<void> clear() => _vault.clear(key);
}
