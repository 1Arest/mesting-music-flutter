import '../../../core/network/system_music_io_client.dart';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/security/session_store.dart';
import '../domain/auth_models.dart';
import '../domain/password_policy.dart';

const invalidLoginCredentialsMessage = '账号或密码错误';

bool isInvalidLoginCredentialsCode(String? code) {
  return const {
    'user_not_found',
    'account_not_found',
    'email_not_found',
    'invalid_grant',
    'invalid_password',
    'invalid_credentials',
    'incorrect_password',
    'wrong_password',
    'password_error',
  }.contains(code?.trim().toLowerCase());
}

/// Backend-neutral account contract consumed by the Flutter UI.
///
/// Implementations may use CloudBase, the Java/MySQL HTTP service or a local
/// preview, but none may expose passwords or verification codes to callers.
abstract interface class AuthRepository {
  Future<AuthSession?> restoreSession();

  Future<AuthSession> refreshAccount();

  Future<EmailVerificationChallenge> requestEmailCode({required String email});

  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    required String verificationId,
    required String verificationCode,
  });

  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  });

  Future<PhoneVerificationChallenge> requestPhoneCode({
    required String phone,
    required bool registration,
  });

  Future<AuthSession> verifyPhoneCode({
    required String phone,
    required String code,
    required String verificationId,
    required bool registration,
  });

  Future<AuthSession> updateProfile({
    required String nickname,
    required String bio,
    int? age,
    String zodiac = '',
    String? avatarPath,
  });

  Future<SecurityVerificationChallenge> requestCurrentIdentityCode({
    required AuthMethod method,
  });

  Future<String> verifyCurrentIdentity({
    required String verificationId,
    required String verificationCode,
  });

  Future<SecurityVerificationChallenge> requestBindingCode({
    required AuthMethod method,
    required String account,
  });

  Future<AuthSession> bindCredential({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
    required String sudoToken,
  });

  Future<SecurityVerificationChallenge> requestPasswordResetCode({
    required AuthMethod method,
    required String account,
  });

  Future<PasswordResetProof> verifyPasswordResetCode({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
  });

  Future<void> resetPassword({
    required PasswordResetProof proof,
    required String newPassword,
  });

  /// Permanently removes the currently authenticated account after a recent
  /// current-identity verification has yielded [sudoToken].
  Future<void> deleteAccount({required String sudoToken});

  Future<void> signOut();
}

/// Repositories that can show a valid cached account immediately and then
/// reconcile it with the server without blocking the first authenticated UI.
abstract interface class BackgroundRefreshAuthRepository {
  Future<AuthSession?> refreshRestoredSession();
}

/// Repositories that can exchange a refresh token for a new access token
/// without requiring the user to sign in again.
abstract interface class RenewableAuthRepository {
  Future<AuthSession?> renewSession();
}

const localPreviewUserId = 'local-preview-account';

class UnconfiguredAuthRepository implements AuthRepository {
  const UnconfiguredAuthRepository();

  static const unavailableMessage =
      '账号云服务尚未配置。客户端页面已经就绪，完成 CloudBase 环境与 API 地址配置后即可注册登录。';

  Never _unavailable() => throw const AuthRequestException(
    unavailableMessage,
    code: 'unconfigured',
  );

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<AuthSession> refreshAccount() async => _unavailable();

  @override
  Future<EmailVerificationChallenge> requestEmailCode({
    required String email,
  }) async => _unavailable();

  @override
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    required String verificationId,
    required String verificationCode,
  }) async => _unavailable();

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async => _unavailable();

  @override
  Future<PhoneVerificationChallenge> requestPhoneCode({
    required String phone,
    required bool registration,
  }) async => _unavailable();

  @override
  Future<AuthSession> verifyPhoneCode({
    required String phone,
    required String code,
    required String verificationId,
    required bool registration,
  }) async => _unavailable();

  @override
  Future<AuthSession> updateProfile({
    required String nickname,
    required String bio,
    int? age,
    String zodiac = '',
    String? avatarPath,
  }) async => _unavailable();

  @override
  Future<SecurityVerificationChallenge> requestCurrentIdentityCode({
    required AuthMethod method,
  }) async => _unavailable();

  @override
  Future<String> verifyCurrentIdentity({
    required String verificationId,
    required String verificationCode,
  }) async => _unavailable();

  @override
  Future<SecurityVerificationChallenge> requestBindingCode({
    required AuthMethod method,
    required String account,
  }) async => _unavailable();

  @override
  Future<AuthSession> bindCredential({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
    required String sudoToken,
  }) async => _unavailable();

  @override
  Future<SecurityVerificationChallenge> requestPasswordResetCode({
    required AuthMethod method,
    required String account,
  }) async => _unavailable();

  @override
  Future<PasswordResetProof> verifyPasswordResetCode({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
  }) async => _unavailable();

  @override
  Future<void> resetPassword({
    required PasswordResetProof proof,
    required String newPassword,
  }) async => _unavailable();

  @override
  Future<void> deleteAccount({required String sudoToken}) async =>
      _unavailable();

  @override
  Future<void> signOut() async {}
}

/// A device-only account used while the cloud account service is not configured.
///
/// It deliberately uses a separate preference key from the real cloud session,
/// so enabling the API later will not overwrite or impersonate a server account.
class LocalPreviewAuthRepository implements AuthRepository {
  LocalPreviewAuthRepository({
    required SharedPreferences preferences,
    Future<Directory> Function()? documentsDirectory,
  }) : _preferences = preferences,
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  static const _sessionKey = 'mesting_local_preview_session_v1';
  static const _signedOutKey = 'mesting_local_preview_signed_out_v1';
  static const _deletedKey = 'mesting_local_preview_deleted_v1';

  final SharedPreferences _preferences;
  final Future<Directory> Function() _documentsDirectory;
  AuthSession? _session;

  @override
  Future<AuthSession?> restoreSession() async {
    if (_preferences.getBool(_deletedKey) == true) return null;
    final encoded = _preferences.getString(_sessionKey);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final stored = AuthSession.fromJson(
          jsonDecode(encoded) as Map<String, Object?>,
        );
        _session = stored;
        return stored;
      } on Object {
        await _preferences.remove(_sessionKey);
      }
    }
    if (_preferences.getBool(_signedOutKey) == true) return null;
    return _persist(_newSession());
  }

  @override
  Future<AuthSession> refreshAccount() => _ensureSession();

  @override
  Future<EmailVerificationChallenge> requestEmailCode({
    required String email,
  }) async {
    return const EmailVerificationChallenge(
      verificationId: 'local-preview-verification',
      expiresIn: Duration(minutes: 10),
      isExistingUser: false,
    );
  }

  @override
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    required String verificationId,
    required String verificationCode,
  }) async {
    final passwordError = validateAccountPassword(password);
    if (passwordError != null) {
      throw AuthRequestException(passwordError);
    }
    return _activate(email: email);
  }

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _activate(email: email);
  }

  @override
  Future<PhoneVerificationChallenge> requestPhoneCode({
    required String phone,
    required bool registration,
  }) async {
    return PhoneVerificationChallenge(
      verificationId: 'local-preview-phone-verification',
      expiresIn: const Duration(minutes: 10),
      isExistingUser: !registration,
    );
  }

  @override
  Future<AuthSession> verifyPhoneCode({
    required String phone,
    required String code,
    required String verificationId,
    required bool registration,
  }) async {
    final current = await _ensureSession();
    return _persist(
      current.copyWith(
        user: current.user.copyWith(phoneMasked: _maskPhone(phone)),
      ),
    );
  }

  @override
  Future<AuthSession> updateProfile({
    required String nickname,
    required String bio,
    int? age,
    String zodiac = '',
    String? avatarPath,
  }) async {
    final current = await _ensureSession();
    var avatarUrl = current.user.avatarUrl;
    if (avatarPath != null && avatarPath.trim().isNotEmpty) {
      avatarUrl = await _copyAvatar(avatarPath);
    }
    return _persist(
      current.copyWith(
        user: current.user.copyWith(
          nickname: nickname.trim(),
          bio: bio.trim(),
          age: age,
          zodiac: zodiac.trim(),
          avatarUrl: avatarUrl,
        ),
      ),
    );
  }

  @override
  Future<SecurityVerificationChallenge> requestCurrentIdentityCode({
    required AuthMethod method,
  }) async {
    final current = await _ensureSession();
    final target = method == AuthMethod.email
        ? current.user.emailMasked
        : current.user.phoneMasked;
    if (target == null || target.isEmpty) {
      throw AuthRequestException('当前账号尚未绑定${method.label}');
    }
    return SecurityVerificationChallenge(
      verificationId: 'local-current-${method.name}',
      expiresIn: const Duration(minutes: 5),
      maskedTarget: target,
    );
  }

  @override
  Future<String> verifyCurrentIdentity({
    required String verificationId,
    required String verificationCode,
  }) async {
    if (verificationId.isEmpty || verificationCode.trim().length != 6) {
      throw const AuthRequestException('验证码不正确，请重新输入');
    }
    return 'local-sudo-token';
  }

  @override
  Future<SecurityVerificationChallenge> requestBindingCode({
    required AuthMethod method,
    required String account,
  }) async {
    await _ensureSession();
    return SecurityVerificationChallenge(
      verificationId: 'local-binding-${method.name}',
      expiresIn: const Duration(minutes: 10),
      maskedTarget: method == AuthMethod.email
          ? _maskEmail(account)
          : _maskPhone(account),
    );
  }

  @override
  Future<AuthSession> bindCredential({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
    required String sudoToken,
  }) async {
    if (sudoToken != 'local-sudo-token' ||
        verificationId.isEmpty ||
        verificationCode.trim().length != 6) {
      throw const AuthRequestException('身份验证已失效，请重新验证');
    }
    final current = await _ensureSession();
    final user = method == AuthMethod.email
        ? current.user.copyWith(emailMasked: _maskEmail(account))
        : current.user.copyWith(phoneMasked: _maskPhone(account));
    return _persist(current.copyWith(user: user));
  }

  @override
  Future<SecurityVerificationChallenge> requestPasswordResetCode({
    required AuthMethod method,
    required String account,
  }) async {
    return SecurityVerificationChallenge(
      verificationId: 'local-reset-${method.name}',
      expiresIn: const Duration(minutes: 10),
      maskedTarget: method == AuthMethod.email
          ? _maskEmail(account)
          : _maskPhone(account),
    );
  }

  @override
  Future<PasswordResetProof> verifyPasswordResetCode({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
  }) async {
    if (verificationId.isEmpty || verificationCode.trim().length != 6) {
      throw const AuthRequestException('验证码无效或已过期，请重新获取');
    }
    return PasswordResetProof(
      method: method,
      account: account.trim(),
      verificationToken: 'local-reset-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<void> resetPassword({
    required PasswordResetProof proof,
    required String newPassword,
  }) async {
    if (proof.isExpired) {
      throw const AuthRequestException('重置凭据已失效，请重新验证');
    }
    final passwordError = validateAccountPassword(newPassword);
    if (passwordError != null) {
      throw AuthRequestException(passwordError);
    }
    await signOut();
  }

  @override
  Future<void> deleteAccount({required String sudoToken}) async {
    if (sudoToken != 'local-sudo-token') {
      throw const AuthRequestException('身份验证已失效，请重新验证');
    }
    _session = null;
    await _preferences.remove(_sessionKey);
    await _preferences.setBool(_signedOutKey, true);
    await _preferences.setBool(_deletedKey, true);
    try {
      final root = await _documentsDirectory();
      final avatarDirectory = Directory(
        '${root.path}${Platform.pathSeparator}mesting_local_profile',
      );
      if (await avatarDirectory.exists()) {
        await avatarDirectory.delete(recursive: true);
      }
    } on Object {
      // The deletion marker and session removal still prevent the local demo
      // account from being restored if an old image cache cannot be removed.
    }
  }

  @override
  Future<void> signOut() async {
    _session = null;
    await _preferences.remove(_sessionKey);
    await _preferences.setBool(_signedOutKey, true);
  }

  Future<AuthSession> _activate({String? email}) async {
    final current = _session ?? _readStoredSession() ?? _newSession();
    final next = email == null || email.trim().isEmpty
        ? current
        : current.copyWith(
            user: current.user.copyWith(emailMasked: _maskEmail(email)),
          );
    await _preferences.remove(_signedOutKey);
    // A new explicit local-preview sign-in starts a fresh device-only demo
    // account. It never restores the data that was removed on deletion.
    await _preferences.remove(_deletedKey);
    return _persist(next);
  }

  Future<AuthSession> _ensureSession() async {
    if (_preferences.getBool(_deletedKey) == true) {
      throw const AuthRequestException('本地体验账号已注销，请先重新登录');
    }
    final current = _session ?? _readStoredSession();
    if (current != null) return current;
    if (_preferences.getBool(_signedOutKey) == true) {
      throw const AuthRequestException('请先登录本地体验账号');
    }
    return _persist(_newSession());
  }

  AuthSession? _readStoredSession() {
    final encoded = _preferences.getString(_sessionKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return AuthSession.fromJson(jsonDecode(encoded) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  AuthSession _newSession() {
    return AuthSession(
      user: const AuthUser(
        uid: localPreviewUserId,
        nickname: 'Mest',
        bio: '本地体验账号 · 收藏、歌单和资料保存在当前设备',
        emailMasked: 'local@device',
      ),
      accessToken: 'local-preview-access',
      refreshToken: 'local-preview-refresh',
      expiresAt: DateTime.utc(2099, 1, 1),
    );
  }

  Future<AuthSession> _persist(AuthSession session) async {
    _session = session;
    await _preferences.setString(_sessionKey, jsonEncode(session.toJson()));
    return session;
  }

  Future<String> _copyAvatar(String avatarPath) async {
    final source = File(avatarPath);
    if (!await source.exists()) {
      throw const AuthRequestException('选择的头像文件已不存在，请重新选择');
    }
    final root = await _documentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}mesting_local_profile',
    );
    await directory.create(recursive: true);
    final extension = _safeImageExtension(avatarPath);
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      'avatar_${DateTime.now().millisecondsSinceEpoch}$extension',
    );
    await source.copy(target.path);
    return target.path;
  }

  String _safeImageExtension(String path) {
    final fileName = path.replaceAll('\\', '/').split('/').last;
    final dot = fileName.lastIndexOf('.');
    if (dot > 0) {
      final extension = fileName.substring(dot).toLowerCase();
      if (const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)) {
        return extension;
      }
    }
    return '.jpg';
  }

  String _maskEmail(String email) {
    final value = email.trim();
    final at = value.indexOf('@');
    if (at <= 1) return value;
    return '${value.substring(0, 1)}***${value.substring(at)}';
  }

  String _maskPhone(String phone) {
    final value = phone.trim();
    if (value.length < 7) return value;
    return '${value.substring(0, 3)}****${value.substring(value.length - 4)}';
  }
}

/// AuthRepository implementation for the versioned Java/MySQL HTTP API.
///
/// It owns only the active encrypted session. Remembered-account UI data is
/// intentionally managed by [SessionStore] as a separate, explicit feature.
class HttpAuthRepository implements AuthRepository, RenewableAuthRepository {
  HttpAuthRepository({
    required String baseUrl,
    required SessionStore sessionStore,
    http.Client? client,
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), ''),
       _sessionStore = sessionStore,
       _client = client ?? SystemMusicIoClient();

  final String _baseUrl;
  final SessionStore _sessionStore;
  final http.Client _client;
  AuthSession? _session;

  @override
  /// Restores a valid cached session or exchanges its refresh token once.
  ///
  /// An unsuccessful refresh clears the active session rather than leaving an
  /// expired token available for subsequent authenticated requests.
  Future<AuthSession?> restoreSession() async {
    final stored = await _sessionStore.read();
    if (stored == null) return null;
    if (!stored.isExpired) {
      _session = stored;
      return stored;
    }
    try {
      final refreshed = await _sessionRequest('/v1/auth/refresh', {
        'refresh_token': stored.refreshToken,
      });
      return refreshed;
    } on Object {
      await _sessionStore.clear();
      return null;
    }
  }

  @override
  Future<AuthSession?> renewSession() async {
    final current = _session ?? await _sessionStore.read();
    if (current == null) return null;
    return _sessionRequest('/v1/auth/refresh', {
      'refresh_token': current.refreshToken,
    });
  }

  @override
  Future<AuthSession> refreshAccount() async {
    final current = _session ?? await _sessionStore.read();
    if (current == null) {
      throw const AuthRequestException('登录状态已失效，请重新登录');
    }
    _session = current;
    final payload = await _request(
      '/v1/me',
      const {},
      method: 'GET',
      authenticated: true,
    );
    final userPayload = (payload['user'] as Map<String, Object?>?) ?? payload;
    final next = current.copyWith(user: AuthUser.fromJson(userPayload));
    await _persist(next);
    return next;
  }

  @override
  Future<EmailVerificationChallenge> requestEmailCode({
    required String email,
  }) async {
    final payload = await _request('/v1/auth/email/code', {'email': email});
    return EmailVerificationChallenge(
      verificationId: payload['verification_id']! as String,
      expiresIn: Duration(seconds: payload['expires_in'] as int? ?? 600),
      isExistingUser: payload['is_user'] as bool? ?? false,
    );
  }

  @override
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    required String verificationId,
    required String verificationCode,
  }) {
    final passwordError = validateAccountPassword(password);
    if (passwordError != null) {
      throw AuthRequestException(passwordError);
    }
    return _sessionRequest('/v1/auth/email/register', {
      'email': email,
      'password': password,
      'verification_id': verificationId,
      'verification_code': verificationCode,
    });
  }

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _sessionRequest('/v1/auth/email/login', {
        'email': email,
        'password': password,
      });
    } on AuthRequestException catch (error) {
      if (isInvalidLoginCredentialsCode(error.code)) {
        throw AuthRequestException(
          invalidLoginCredentialsMessage,
          code: error.code,
        );
      }
      rethrow;
    }
  }

  @override
  Future<PhoneVerificationChallenge> requestPhoneCode({
    required String phone,
    required bool registration,
  }) async {
    final payload = await _request('/v1/auth/phone/code', {
      'phone': phone,
      'purpose': registration ? 'register' : 'login',
    });
    return PhoneVerificationChallenge(
      verificationId: payload['verification_id']! as String,
      expiresIn: Duration(seconds: payload['expires_in'] as int? ?? 600),
      isExistingUser: payload['is_user'] as bool? ?? false,
    );
  }

  @override
  Future<AuthSession> verifyPhoneCode({
    required String phone,
    required String code,
    required String verificationId,
    required bool registration,
  }) {
    return _sessionRequest('/v1/auth/phone/verify', {
      'phone': phone,
      'code': code,
      'verification_id': verificationId,
      'purpose': registration ? 'register' : 'login',
    });
  }

  @override
  Future<AuthSession> updateProfile({
    required String nickname,
    required String bio,
    int? age,
    String zodiac = '',
    String? avatarPath,
  }) async {
    var avatarUrl = _session?.user.avatarUrl;
    if (avatarPath != null) {
      // Media is uploaded before the JSON profile patch so the database only
      // receives an address returned by the account service.
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/v1/me/avatar'),
      );
      request.headers.addAll(_headers(authenticated: true, json: false));
      request.files.add(
        await http.MultipartFile.fromPath('avatar', avatarPath),
      );
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final payload = _decodeResponse(response);
      avatarUrl = payload['avatar_url'] as String?;
    }

    final payload = await _request(
      '/v1/me',
      {
        'nickname': nickname,
        'bio': bio,
        'age': age,
        'zodiac': zodiac.trim(),
        'avatar_url': avatarUrl,
      },
      method: 'PATCH',
      authenticated: true,
    );
    final current = _session;
    if (current == null) {
      throw const AuthRequestException('登录状态已失效，请重新登录');
    }
    final returned = AuthUser.fromJson(
      payload['user']! as Map<String, Object?>,
    );
    final next = current.copyWith(
      user: returned.copyWith(age: age, zodiac: zodiac.trim()),
    );
    await _persist(next);
    return next;
  }

  @override
  Future<SecurityVerificationChallenge> requestCurrentIdentityCode({
    required AuthMethod method,
  }) async {
    final payload = await _request('/v1/me/security/code', {
      'method': method.name,
    }, authenticated: true);
    return _securityChallenge(payload);
  }

  @override
  Future<String> verifyCurrentIdentity({
    required String verificationId,
    required String verificationCode,
  }) async {
    final payload = await _request('/v1/me/security/verify', {
      'verification_id': verificationId,
      'verification_code': verificationCode.trim(),
    }, authenticated: true);
    final sudoToken = payload['sudo_token'] as String?;
    if (sudoToken == null || sudoToken.isEmpty) {
      throw const AuthRequestException('身份验证没有完成，请重新验证');
    }
    return sudoToken;
  }

  @override
  Future<SecurityVerificationChallenge> requestBindingCode({
    required AuthMethod method,
    required String account,
  }) async {
    final payload = await _request('/v1/me/bindings/code', {
      'method': method.name,
      'account': account.trim(),
    }, authenticated: true);
    return _securityChallenge(payload);
  }

  @override
  Future<AuthSession> bindCredential({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
    required String sudoToken,
  }) async {
    await _request(
      '/v1/me/bindings',
      {
        'method': method.name,
        'account': account.trim(),
        'verification_id': verificationId,
        'verification_code': verificationCode.trim(),
        'sudo_token': sudoToken,
      },
      method: 'PATCH',
      authenticated: true,
    );
    return refreshAccount();
  }

  @override
  Future<SecurityVerificationChallenge> requestPasswordResetCode({
    required AuthMethod method,
    required String account,
  }) async {
    final payload = await _request('/v1/auth/password/reset/code', {
      'method': method.name,
      'account': account.trim(),
    });
    return _securityChallenge(payload);
  }

  @override
  Future<PasswordResetProof> verifyPasswordResetCode({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
  }) async {
    final payload = await _request('/v1/auth/password/reset/verify', {
      'method': method.name,
      'account': account.trim(),
      'verification_id': verificationId,
      'verification_code': verificationCode.trim(),
    });
    final token = payload['reset_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const AuthRequestException('验证码无效或已过期，请重新获取');
    }
    return PasswordResetProof(
      method: method,
      account: account.trim(),
      verificationToken: token,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: payload['expires_in'] as int? ?? 300),
      ),
    );
  }

  @override
  Future<void> resetPassword({
    required PasswordResetProof proof,
    required String newPassword,
  }) async {
    if (proof.isExpired) {
      throw const AuthRequestException('重置凭据已过期，请重新获取验证码');
    }
    final passwordError = validateAccountPassword(newPassword);
    if (passwordError != null) {
      throw AuthRequestException(passwordError);
    }
    await _request('/v1/auth/password/reset', {
      'method': proof.method.name,
      'account': proof.account,
      'reset_token': proof.verificationToken,
      'new_password': newPassword,
    });
    _session = null;
    await _sessionStore.clearAll();
  }

  @override
  Future<void> deleteAccount({required String sudoToken}) async {
    final current = _session ?? await _sessionStore.read();
    if (current == null) {
      throw const AuthRequestException('登录状态已失效，请重新登录');
    }
    if (sudoToken.trim().isEmpty) {
      throw const AuthRequestException('身份验证已失效，请重新验证');
    }
    _session = current;
    await _request(
      '/v1/me',
      {'sudo_token': sudoToken.trim()},
      method: 'DELETE',
      authenticated: true,
    );
    _session = null;
    await _sessionStore.clearAll();
  }

  @override
  Future<void> signOut() async {
    // Keep the separately encrypted remembered credential for the explicit
    // quick-login card; only the active session is removed here.
    _session = null;
    await _sessionStore.clear();
  }

  /// Parses and persists a complete session only after the server succeeds.
  Future<AuthSession> _sessionRequest(
    String path,
    Map<String, Object?> body,
  ) async {
    final payload = await _request(path, body);
    final session = AuthSession.fromJson(payload);
    await _persist(session);
    return session;
  }

  Future<void> _persist(AuthSession session) async {
    _session = session;
    await _sessionStore.write(session);
  }

  /// Sends one API request and normalizes transport failures for the UI.
  ///
  /// Sensitive authorization is attached only for authenticated paths; request
  /// bodies are never logged here because they can contain passwords or codes.
  Future<Map<String, Object?>> _request(
    String path,
    Map<String, Object?> body, {
    String method = 'POST',
    bool authenticated = false,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    late final http.Response response;
    try {
      final headers = _headers(authenticated: authenticated);
      final encoded = jsonEncode(body);
      response = switch (method) {
        'GET' => await _client.get(uri, headers: headers),
        'PATCH' => await _client.patch(uri, headers: headers, body: encoded),
        'DELETE' => await _client.delete(uri, headers: headers, body: encoded),
        _ => await _client.post(uri, headers: headers, body: encoded),
      };
    } on SocketException {
      throw const AuthRequestException('网络连接不可用，请检查网络后重试');
    } on http.ClientException {
      throw const AuthRequestException('账号服务暂时无法连接，请稍后重试');
    }
    return _decodeResponse(response);
  }

  SecurityVerificationChallenge _securityChallenge(
    Map<String, Object?> payload,
  ) {
    final verificationId = payload['verification_id'] as String?;
    if (verificationId == null || verificationId.isEmpty) {
      throw const AuthRequestException('验证码发送成功，但服务没有返回验证凭据');
    }
    return SecurityVerificationChallenge(
      verificationId: verificationId,
      expiresIn: Duration(seconds: payload['expires_in'] as int? ?? 600),
      maskedTarget: payload['masked_target'] as String? ?? '',
    );
  }

  Map<String, String> _headers({
    required bool authenticated,
    bool json = true,
  }) {
    return {
      if (json) 'content-type': 'application/json; charset=utf-8',
      'accept': 'application/json',
      if (authenticated && _session != null)
        'authorization': 'Bearer ${_session!.accessToken}',
    };
  }

  Map<String, Object?> _decodeResponse(http.Response response) {
    Map<String, Object?> payload;
    try {
      payload =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
    } on Object {
      throw const AuthRequestException('账号服务返回了无法识别的数据');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthRequestException(
        payload['message'] as String? ?? '操作失败，请稍后重试',
        code: payload['code'] as String?,
      );
    }
    return (payload['data'] as Map<String, Object?>?) ?? payload;
  }
}
