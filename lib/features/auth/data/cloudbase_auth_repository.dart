import '../../../core/network/system_music_io_client.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/security/avatar_image_validator.dart';
import '../../../core/security/session_store.dart';
import '../domain/auth_models.dart';
import '../domain/password_policy.dart';
import 'auth_repository.dart';

/// Direct CloudBase Auth v2 integration for the Android client.
///
/// No Tencent Cloud secret is embedded in the app. The public environment
/// gateway only receives the user's verification code or password and returns
/// short-lived access tokens plus a rotating refresh token.
class CloudBaseAuthRepository
    implements
        AuthRepository,
        BackgroundRefreshAuthRepository,
        RenewableAuthRepository {
  CloudBaseAuthRepository({
    required String environmentId,
    required SessionStore sessionStore,
    http.Client? client,
    Future<Directory> Function()? avatarDirectoryProvider,
    bool enableAccountCloudProfile = false,
    String accountFunctionName = 'social-api',
  }) : _baseUrl = 'https://${environmentId.trim()}.api.tcloudbasegateway.com',
       _sessionStore = sessionStore,
       _client = client ?? SystemMusicIoClient(),
       _ownsClient = client == null,
       _enableAccountCloudProfile = enableAccountCloudProfile,
       _accountFunctionName = accountFunctionName,
       _avatarDirectoryProvider =
           avatarDirectoryProvider ?? getApplicationDocumentsDirectory;

  final String _baseUrl;
  final SessionStore _sessionStore;
  final http.Client _client;
  final bool _ownsClient;
  final bool _enableAccountCloudProfile;
  final String _accountFunctionName;
  final Future<Directory> Function() _avatarDirectoryProvider;
  AuthSession? _session;
  String? _boundEmail;
  String? _boundPhone;
  String? _cloudAvatarId;
  String? _latestAvatarDownloadUrl;
  final Set<String> _usedResetTokens = <String>{};

  @override
  Future<AuthSession?> restoreSession() async {
    final stored = await _sessionStore.read();
    if (stored == null) return null;
    if (!stored.isExpired) {
      final restored = await _restoreLocalProfile(stored);
      _session = restored;
      return restored;
    }
    try {
      final refreshed = await renewSession();
      if (refreshed == null) return null;
      try {
        return await refreshAccount();
      } on AuthRequestException catch (error) {
        if (_isInvalidSessionError(error.code)) rethrow;
        return refreshed;
      }
    } on Object {
      await _sessionStore.clear();
      return null;
    }
  }

  @override
  Future<AuthSession?> renewSession() async {
    final current = _session ?? await _sessionStore.read();
    if (current == null) return null;
    try {
      final payload = await _post('/auth/v1/token', {
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken,
      });
      final refreshed = await _restoreLocalProfile(
        _sessionFromTokenPayload(payload, fallbackUser: current.user),
      );
      if (refreshed.user.uid != current.user.uid) {
        await _sessionStore.clear();
        _session = null;
        return null;
      }
      await _persist(refreshed);
      return refreshed;
    } on AuthRequestException catch (error) {
      if (_isInvalidSessionError(error.code)) {
        await _sessionStore.clear();
        _session = null;
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<AuthSession?> refreshRestoredSession() async {
    final restored = _session;
    if (restored == null) return null;
    try {
      return await refreshAccount();
    } on AuthRequestException catch (error) {
      if (_isInvalidSessionError(error.code)) {
        await _sessionStore.clear();
        _session = null;
        return null;
      }
      return restored;
    }
  }

  @override
  Future<AuthSession> refreshAccount() async {
    final current = await _requireSession();
    final payload = await _get(
      '/auth/v1/user/me',
      accessToken: current.accessToken,
    );
    final email = _nonEmptyString(payload['email']);
    final phone = _nonEmptyString(payload['phone_number']);
    _boundEmail = email;
    _boundPhone = phone;
    final cloudUid =
        _nonEmptyString(payload['sub']) ??
        _nonEmptyString(payload['user_id']) ??
        _nonEmptyString(payload['uid']);
    if (cloudUid != null && cloudUid != current.user.uid) {
      throw const AuthRequestException('账号身份校验失败，请退出后重新登录');
    }
    final cloudProfile = await _readAccountCloudProfile(current);
    final stored = await _sessionStore.readProfile(current.user.uid);
    final authServerAvatar =
        _nonEmptyString(payload['avatar_url']) ??
        _nonEmptyString(payload['avatarUrl']) ??
        _nonEmptyString(payload['picture']);
    final cloudProfileAvatar = _nonEmptyString(cloudProfile['avatar_url']);
    final cloudProfileAvatarId = _nonEmptyString(
      cloudProfile['avatar_cloud_id'],
    );
    final serverAvatar = cloudProfileAvatar ?? authServerAvatar;
    final storedCloudAvatar =
        stored?.avatarCloudId ?? current.user.avatarCloudId;
    final stableCloudAvatar =
        cloudProfileAvatarId ??
        (authServerAvatar?.startsWith('cloud://') == true
            ? authServerAvatar
            : storedCloudAvatar);
    if (_cloudAvatarId != stableCloudAvatar) {
      _latestAvatarDownloadUrl = null;
    }
    _cloudAvatarId = stableCloudAvatar;
    final displayAvatar = await _displayAvatarFor(
      session: current,
      serverAvatar: serverAvatar,
      stableCloudAvatar: stableCloudAvatar,
      stored: stored,
    );
    final next = current.copyWith(
      user: AuthUser(
        uid: current.user.uid,
        nickname:
            _nonEmptyString(cloudProfile['nickname']) ??
            _nonEmptyString(payload['nickname']) ??
            _nonEmptyString(payload['nickName']) ??
            _nonEmptyString(payload['name']) ??
            stored?.nickname ??
            current.user.nickname,
        bio: cloudProfile.containsKey('bio')
            ? cloudProfile['bio']?.toString().trim() ?? ''
            : _nonEmptyString(payload['description']) ??
                  _nonEmptyString(payload['bio']) ??
                  _nonEmptyString(payload['user_desc']) ??
                  stored?.bio ??
                  current.user.bio,
        age: cloudProfile.containsKey('age')
            ? _asInt(cloudProfile['age'])
            : stored?.age ?? current.user.age,
        zodiac: cloudProfile.containsKey('zodiac')
            ? cloudProfile['zodiac']?.toString().trim() ?? ''
            : stored?.zodiac ?? current.user.zodiac,
        avatarUrl: displayAvatar ?? stored?.avatarUrl ?? current.user.avatarUrl,
        avatarCloudId: stableCloudAvatar,
        emailMasked: email == null ? null : _maskEmail(email),
        phoneMasked: phone == null ? null : _maskPhone(phone),
        hasPassword: payload['has_password'] as bool? ?? false,
      ),
    );
    await _persistWithProfile(next);
    return next;
  }

  @override
  Future<EmailVerificationChallenge> requestEmailCode({
    required String email,
  }) async {
    final payload = await _post('/auth/v1/verification', {
      'email': email.trim(),
      'target': 'ANY',
    });
    final verificationId = payload['verification_id'] as String?;
    if (verificationId == null || verificationId.isEmpty) {
      throw const AuthRequestException('验证码发送成功，但服务没有返回验证凭据，请重新获取');
    }
    return EmailVerificationChallenge(
      verificationId: verificationId,
      expiresIn: Duration(seconds: _asInt(payload['expires_in']) ?? 600),
      isExistingUser: payload['is_user'] as bool? ?? false,
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
    final verification = await _post('/auth/v1/verification/verify', {
      'verification_id': verificationId,
      'verification_code': verificationCode.trim(),
    });
    final verificationToken = verification['verification_token'] as String?;
    if (verificationToken == null || verificationToken.isEmpty) {
      throw const AuthRequestException('邮箱验证没有完成，请重新获取验证码');
    }

    final normalizedEmail = email.trim().toLowerCase();
    final payload = await _post('/auth/v1/signup', {
      'email': normalizedEmail,
      'verification_token': verificationToken,
      'password': password,
    });
    final session = await _restoreLocalProfile(
      _sessionFromTokenPayload(
        payload,
        fallbackUser: _emailUser(
          uid: payload['sub']?.toString() ?? normalizedEmail,
          email: normalizedEmail,
        ),
      ),
    );
    return _finalizeRegistration(session);
  }

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    late final Map<String, Object?> payload;
    try {
      payload = await _post('/auth/v1/signin', {
        'username': normalizedEmail,
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
    final session = await _restoreLocalProfile(
      _sessionFromTokenPayload(
        payload,
        fallbackUser: _emailUser(
          uid: payload['sub']?.toString() ?? normalizedEmail,
          email: normalizedEmail,
        ),
      ),
    );
    await _persist(session);
    return refreshAccount();
  }

  @override
  Future<PhoneVerificationChallenge> requestPhoneCode({
    required String phone,
    required bool registration,
  }) async {
    final payload = await _post('/auth/v1/verification', {
      'phone_number': _cloudBasePhone(phone),
      'target': 'ANY',
    });
    final verificationId = payload['verification_id'] as String?;
    if (verificationId == null || verificationId.isEmpty) {
      throw const AuthRequestException('验证码发送成功，但服务没有返回验证凭据，请重新获取');
    }
    return PhoneVerificationChallenge(
      verificationId: verificationId,
      expiresIn: Duration(seconds: _asInt(payload['expires_in']) ?? 600),
      isExistingUser: payload['is_user'] as bool? ?? false,
    );
  }

  @override
  Future<AuthSession> verifyPhoneCode({
    required String phone,
    required String code,
    required String verificationId,
    required bool registration,
  }) async {
    final verification = await _post('/auth/v1/verification/verify', {
      'verification_id': verificationId,
      'verification_code': code.trim(),
    });
    final verificationToken = verification['verification_token'] as String?;
    if (verificationToken == null || verificationToken.isEmpty) {
      throw const AuthRequestException('手机验证没有完成，请重新获取验证码');
    }

    final normalizedPhone = phone.trim();
    final payload = await _post(
      registration ? '/auth/v1/signup' : '/auth/v1/signin',
      registration
          ? {
              'phone_number': _cloudBasePhone(normalizedPhone),
              'verification_token': verificationToken,
            }
          : {'verification_token': verificationToken},
    );
    final session = await _restoreLocalProfile(
      _sessionFromTokenPayload(
        payload,
        fallbackUser: _phoneUser(
          uid: payload['sub']?.toString() ?? normalizedPhone,
          phone: normalizedPhone,
        ),
      ),
    );
    if (registration) {
      return _finalizeRegistration(session);
    }
    await _persist(session);
    return refreshAccount();
  }

  @override
  Future<AuthSession> updateProfile({
    required String nickname,
    required String bio,
    int? age,
    String zodiac = '',
    String? avatarPath,
  }) async {
    final current = await _requireSession();
    final normalizedNickname = nickname.trim();
    final normalizedBio = bio.trim();
    if (normalizedNickname.length < 2 || normalizedNickname.length > 48) {
      throw const AuthRequestException('昵称需要 2–48 个字符');
    }
    if (normalizedBio.length > 120) {
      throw const AuthRequestException('个人简介不能超过 120 个字符');
    }
    if (age != null && (age < 1 || age > 120)) {
      throw const AuthRequestException('年龄需要在 1–120 岁之间');
    }
    final normalizedZodiac = zodiac.trim();
    var avatarId = _cloudAvatarId ?? current.user.avatarCloudId;
    var displayAvatar = current.user.avatarUrl;
    String? latestDownloadUrl;
    if (avatarPath != null && avatarPath.trim().isNotEmpty) {
      try {
        final uploaded = await _uploadAvatar(current, avatarPath);
        avatarId = uploaded.cloudObjectId;
        displayAvatar = uploaded.localPath;
        latestDownloadUrl = uploaded.downloadUrl;
      } on AvatarValidationException catch (error) {
        throw AuthRequestException(error.message);
      }
    }
    final profileUpdate = <String, Object?>{
      'nickname': normalizedNickname,
      'description': normalizedBio,
    };
    if (avatarId != null) profileUpdate['avatar_url'] = avatarId;
    await _post(
      '/auth/v1/user/basic/edit',
      profileUpdate,
      accessToken: current.accessToken,
    );
    await _writeAccountCloudProfile(
      current,
      nickname: normalizedNickname,
      bio: normalizedBio,
      age: age,
      zodiac: normalizedZodiac,
      avatarCloudId: avatarId,
    );
    _cloudAvatarId = avatarId;
    _latestAvatarDownloadUrl = latestDownloadUrl;
    final optimistic = current.copyWith(
      user: current.user.copyWith(
        nickname: normalizedNickname,
        bio: normalizedBio,
        age: age,
        zodiac: normalizedZodiac,
        avatarUrl: displayAvatar,
        avatarCloudId: avatarId,
      ),
    );
    await _persistWithProfile(optimistic);
    return optimistic;
  }

  @override
  Future<SecurityVerificationChallenge> requestCurrentIdentityCode({
    required AuthMethod method,
  }) async {
    final current = await refreshAccount();
    final account = method == AuthMethod.email ? _boundEmail : _boundPhone;
    if (account == null || account.isEmpty) {
      throw AuthRequestException('当前账号尚未绑定${method.label}');
    }
    final payload = await _post('/auth/v1/verification', {
      if (method == AuthMethod.email)
        'email': account
      else
        'phone_number': _cloudBasePhone(account),
      'target': 'USER',
    }, accessToken: current.accessToken);
    return _challengeFromPayload(
      payload,
      maskedTarget: method == AuthMethod.email
          ? _maskEmail(account)
          : _maskPhone(account),
    );
  }

  @override
  Future<String> verifyCurrentIdentity({
    required String verificationId,
    required String verificationCode,
  }) async {
    final current = await _requireSession();
    final verificationToken = await _verifyCode(
      verificationId: verificationId,
      verificationCode: verificationCode,
    );
    final payload = await _post('/auth/v1/user/sudo', {
      'verification_token': verificationToken,
    }, accessToken: current.accessToken);
    final sudoToken = _nonEmptyString(payload['sudo_token']);
    if (sudoToken == null) {
      throw const AuthRequestException('身份验证没有完成，请重新验证');
    }
    return sudoToken;
  }

  @override
  Future<SecurityVerificationChallenge> requestBindingCode({
    required AuthMethod method,
    required String account,
  }) async {
    await _requireSession();
    final normalized = _normalizeAccount(method, account);
    final payload = await _post('/auth/v1/verification', {
      if (method == AuthMethod.email)
        'email': normalized
      else
        'phone_number': _cloudBasePhone(normalized),
      'target': 'ANY',
    });
    return _challengeFromPayload(
      payload,
      maskedTarget: method == AuthMethod.email
          ? _maskEmail(normalized)
          : _maskPhone(normalized),
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
    final current = await _requireSession();
    if (sudoToken.trim().isEmpty) {
      throw const AuthRequestException('身份验证已失效，请重新验证');
    }
    final normalized = _normalizeAccount(method, account);
    final verificationToken = await _verifyCode(
      verificationId: verificationId,
      verificationCode: verificationCode,
    );
    await _post('/auth/v1/user/contact', {
      if (method == AuthMethod.email)
        'email': normalized
      else
        'phone_number': _cloudBasePhone(normalized),
      'sudo_token': sudoToken,
      'verification_token': verificationToken,
    }, accessToken: current.accessToken);
    return refreshAccount();
  }

  @override
  Future<SecurityVerificationChallenge> requestPasswordResetCode({
    required AuthMethod method,
    required String account,
  }) async {
    final normalized = _normalizeAccount(method, account);
    try {
      final payload = await _post('/auth/v1/verification', {
        if (method == AuthMethod.email)
          'email': normalized
        else
          'phone_number': _cloudBasePhone(normalized),
        'target': 'USER',
      });
      return _challengeFromPayload(payload, maskedTarget: '');
    } on AuthRequestException catch (error) {
      if (!_isConcealableAccountLookupError(error.code)) rethrow;
      return const SecurityVerificationChallenge(
        verificationId: 'concealed-missing-account',
        expiresIn: Duration(minutes: 10),
        maskedTarget: '',
      );
    }
  }

  @override
  Future<PasswordResetProof> verifyPasswordResetCode({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
  }) async {
    if (verificationId == 'concealed-missing-account') {
      throw const AuthRequestException('验证码无效或已过期，请重新获取');
    }
    final token = await _verifyCode(
      verificationId: verificationId,
      verificationCode: verificationCode,
      concealFailure: true,
    );
    return PasswordResetProof(
      method: method,
      account: _normalizeAccount(method, account),
      verificationToken: token,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<void> resetPassword({
    required PasswordResetProof proof,
    required String newPassword,
  }) async {
    if (proof.isExpired || _usedResetTokens.contains(proof.verificationToken)) {
      throw const AuthRequestException('重置凭据已失效，请重新获取验证码');
    }
    final passwordError = validateAccountPassword(newPassword);
    if (passwordError != null) {
      throw AuthRequestException(passwordError);
    }
    await _post('/auth/v1/reset', {
      if (proof.method == AuthMethod.email)
        'email': proof.account
      else
        'phone_number': _cloudBasePhone(proof.account),
      'new_password': newPassword,
      'verification_token': proof.verificationToken,
    });
    _usedResetTokens.add(proof.verificationToken);
    // CloudBase completes password recovery atomically in /auth/v1/reset.
    // Do not follow it with /auth/v1/user/revoke/all: that route is not part
    // of the public Auth API and turns a successful reset into a false 405
    // failure. Clear every local credential after the server confirms reset.
    _session = null;
    _boundEmail = null;
    _boundPhone = null;
    _cloudAvatarId = null;
    _latestAvatarDownloadUrl = null;
    await _sessionStore.clearAll();
  }

  @override
  Future<void> deleteAccount({required String sudoToken}) async {
    final current = await _requireSession();
    final token = sudoToken.trim();
    if (token.isEmpty) {
      throw const AuthRequestException('身份验证已失效，请重新验证');
    }

    // Account data lives in the social Cloud Function while the identity
    // itself belongs to CloudBase Auth. The function clears the application
    // data first and only then invokes CloudBase's authenticated delete-me
    // endpoint with this short-lived sudo token.
    await _callAccountFunction('deleteAccount', {
      'sudo_token': token,
    }, accessToken: current.accessToken);

    _session = null;
    _boundEmail = null;
    _boundPhone = null;
    _cloudAvatarId = null;
    _latestAvatarDownloadUrl = null;
    try {
      await Future.wait<void>([
        _sessionStore.clearAll(),
        _sessionStore.deleteProfile(current.user.uid),
        _clearAvatarCache(current.user.uid),
      ]);
    } on Object {
      // The server has already deleted the account. Keep the device signed out
      // even if a stale image cache cannot be removed on this attempt.
    }
  }

  @override
  Future<void> signOut() async {
    // This is a device-local sign-out. The encrypted refresh credential is
    // retained separately so the explicitly remembered account can use
    // password/OTP-free quick login on this same device.
    _session = null;
    _boundEmail = null;
    _boundPhone = null;
    _cloudAvatarId = null;
    _latestAvatarDownloadUrl = null;
    await _sessionStore.clear();
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    String? accessToken,
  }) {
    return _request('POST', path, body: body, accessToken: accessToken);
  }

  Future<Map<String, Object?>> _get(String path, {String? accessToken}) {
    return _request('GET', path, accessToken: accessToken);
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? accessToken,
  }) async {
    late final http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final headers = {
        'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
        if (accessToken != null) 'authorization': 'Bearer $accessToken',
      };
      Future<http.Response> send(http.Client client) {
        return (method == 'GET'
                ? client.get(uri, headers: headers)
                : client.post(
                    uri,
                    headers: headers,
                    body: jsonEncode(body ?? const <String, Object?>{}),
                  ))
            .timeout(const Duration(seconds: 18));
      }

      try {
        response = await send(_client);
      } on HandshakeException {
        // A TLS handshake failure happens before the HTTP request is sent, so
        // one short retry cannot duplicate a registration or verification.
        // A fresh production client avoids reusing a proxy connection pool
        // that has already failed its TLS handshake.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_ownsClient) {
          final retryClient = SystemMusicIoClient();
          try {
            response = await send(retryClient);
          } finally {
            retryClient.close();
          }
        } else {
          response = await send(_client);
        }
      }
    } on HandshakeException {
      throw const AuthRequestException('安全连接建立失败，请切换网络后重试');
    } on SocketException {
      throw const AuthRequestException('网络连接不可用，请检查网络后重试');
    } on TimeoutException {
      throw const AuthRequestException('账号服务响应较慢，请稍后重试');
    } on http.ClientException {
      throw const AuthRequestException('暂时无法连接账号服务，请稍后重试');
    } on IOException {
      throw const AuthRequestException('网络连接异常，请稍后重试');
    }

    final payload = _decodePayload(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code =
          payload['error']?.toString() ??
          payload['code']?.toString() ??
          payload['error_code']?.toString();
      throw AuthRequestException(_friendlyError(code, payload), code: code);
    }
    return (payload['data'] as Map<String, Object?>?) ?? payload;
  }

  Map<String, Object?> _decodePayload(http.Response response) {
    if (response.bodyBytes.isEmpty) return const {};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) return decoded;
    } on Object {
      // Fall through to the friendly malformed-response error below.
    }
    throw const AuthRequestException('账号服务返回了无法识别的数据');
  }

  String _friendlyError(String? code, Map<String, Object?> payload) {
    final normalizedCode = code?.trim().toLowerCase();
    return switch (normalizedCode) {
      'invalid_verification_code' => '验证码不正确，请重新输入',
      'verification_expired' || 'verification_code_expired' => '验证码已过期，请重新获取',
      'rate_limit_exceeded' => '发送过于频繁，请在 60 秒后重试',
      'resource_exhausted' || '8' => '操作过于频繁，请稍后再试',
      'captcha_required' => '发送次数较多触发安全验证，请稍后再试',
      'user_already_exists' || 'email_already_exists' => '该邮箱已经注册，请切换到登录',
      'user_not_found' ||
      'account_not_found' ||
      'email_not_found' => invalidLoginCredentialsMessage,
      'contact_already_exists' ||
      'phone_number_already_exists' => '该联系方式已绑定其他账号',
      'invalid_access_token' || 'unauthenticated' || '16' => '登录状态已失效，请重新登录',
      'invalid_sudo_token' || 'sudo_token_expired' => '身份验证已失效，请重新验证',
      'invalid_argument' || '3' => '提交的信息不完整或格式不正确，请检查后重试',
      'failed_precondition' || '9' => '当前账号状态不支持此操作，请稍后重试',
      'unimplemented' || 'method_not_allowed' || '12' => '当前账号服务暂不支持此操作，请稍后重试',
      'invalid_grant' ||
      'invalid_password' ||
      'invalid_credentials' ||
      'incorrect_password' ||
      'wrong_password' ||
      'password_error' => invalidLoginCredentialsMessage,
      'weak_password' || 'invalid_password_format' => '密码需为 8–64 位',
      _ => _safeServerMessage(payload),
    };
  }

  String _safeServerMessage(Map<String, Object?> payload) {
    final serverMessage = _nonEmptyString(
      payload['error_description'] ?? payload['message'],
    );
    if (serverMessage != null &&
        RegExp(r'[\u3400-\u9fff]').hasMatch(serverMessage)) {
      return serverMessage;
    }
    return '账号操作失败，请稍后重试';
  }

  AuthSession _sessionFromTokenPayload(
    Map<String, Object?> payload, {
    required AuthUser fallbackUser,
  }) {
    final accessToken = payload['access_token'] as String?;
    final refreshToken = payload['refresh_token'] as String?;
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      throw const AuthRequestException('登录凭据不完整，请重新登录');
    }
    final uid = payload['sub']?.toString();
    final user = uid == null || uid.isEmpty
        ? fallbackUser
        : AuthUser(
            uid: uid,
            nickname: fallbackUser.nickname,
            bio: fallbackUser.bio,
            age: fallbackUser.age,
            zodiac: fallbackUser.zodiac,
            avatarUrl: fallbackUser.avatarUrl,
            avatarCloudId: fallbackUser.avatarCloudId,
            emailMasked: fallbackUser.emailMasked,
            phoneMasked: fallbackUser.phoneMasked,
            hasPassword: fallbackUser.hasPassword,
          );
    return AuthSession(
      user: user,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: _asInt(payload['expires_in']) ?? 7200),
      ),
    );
  }

  AuthUser _emailUser({required String uid, required String email}) {
    return AuthUser(
      uid: uid,
      // The server allocates the public nickname as `用户` plus a unique
      // six-digit number. Never expose the email local-part as a fallback.
      nickname: 'Mesting 用户',
      emailMasked: _maskEmail(email),
      hasPassword: true,
    );
  }

  AuthUser _phoneUser({required String uid, required String phone}) {
    return AuthUser(
      uid: uid,
      nickname: 'Mesting 用户',
      phoneMasked: _maskPhone(phone),
    );
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email.substring(0, 1)}***${email.substring(at)}';
  }

  String _maskPhone(String phone) {
    var value = phone.replaceAll(RegExp(r'\D'), '');
    if (value.length == 13 && value.startsWith('86')) {
      value = value.substring(2);
    }
    if (value.length < 7) return value;
    return '${value.substring(0, 3)}****${value.substring(value.length - 4)}';
  }

  Future<AuthSession> _requireSession() async {
    final current = _session ?? await _sessionStore.read();
    if (current == null) {
      throw const AuthRequestException('登录状态已失效，请重新登录');
    }
    if (current.isExpired) {
      final restored = await restoreSession();
      if (restored == null) {
        throw const AuthRequestException('登录状态已失效，请重新登录');
      }
      return restored;
    }
    _session = current;
    return current;
  }

  SecurityVerificationChallenge _challengeFromPayload(
    Map<String, Object?> payload, {
    required String maskedTarget,
  }) {
    final verificationId = _nonEmptyString(payload['verification_id']);
    if (verificationId == null) {
      throw const AuthRequestException('验证码发送成功，但服务没有返回验证凭据，请重新获取');
    }
    return SecurityVerificationChallenge(
      verificationId: verificationId,
      expiresIn: Duration(seconds: _asInt(payload['expires_in']) ?? 600),
      maskedTarget: maskedTarget,
    );
  }

  Future<String> _verifyCode({
    required String verificationId,
    required String verificationCode,
    bool concealFailure = false,
  }) async {
    try {
      final payload = await _post('/auth/v1/verification/verify', {
        'verification_id': verificationId,
        'verification_code': verificationCode.trim(),
      });
      final token = _nonEmptyString(payload['verification_token']);
      if (token == null) {
        throw const AuthRequestException('验证码验证没有完成，请重新获取');
      }
      return token;
    } on AuthRequestException {
      if (concealFailure) {
        throw const AuthRequestException('验证码无效或已过期，请重新获取');
      }
      rethrow;
    }
  }

  String _normalizeAccount(AuthMethod method, String account) {
    final value = account.trim();
    if (method == AuthMethod.email) {
      final normalized = value.toLowerCase();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
        throw const AuthRequestException('请输入正确的邮箱地址');
      }
      return normalized;
    }
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 13 && digits.startsWith('86')) {
      digits = digits.substring(2);
    }
    if (!RegExp(r'^1\d{10}$').hasMatch(digits)) {
      throw const AuthRequestException('请输入 11 位中国大陆手机号');
    }
    return digits;
  }

  String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  bool _isConcealableAccountLookupError(String? code) {
    return const {
      'user_not_found',
      'not_found',
      'failed_precondition',
      '5',
      '9',
    }.contains(code);
  }

  String _cloudBasePhone(String phone) {
    final value = phone.trim().replaceAll(' ', '');
    if (value.startsWith('+86')) {
      return '+86 ${value.substring(3)}';
    }
    return '+86 $value';
  }

  Future<Map<String, Object?>> _readAccountCloudProfile(
    AuthSession session,
  ) async {
    if (!_enableAccountCloudProfile) return const {};
    try {
      final data = await _callAccountFunction(
        'getAccountProfile',
        const {},
        accessToken: session.accessToken,
      );
      final profile = data['profile'];
      return profile is Map
          ? Map<String, Object?>.from(profile)
          : const <String, Object?>{};
    } on Object {
      // CloudBase Auth remains the primary identity source. An older or
      // temporarily unavailable account-data function must not block login.
      return const {};
    }
  }

  Future<AuthSession> _finalizeRegistration(AuthSession session) async {
    if (!_enableAccountCloudProfile) {
      await _persist(session);
      return session;
    }

    final cloudProfile = await _readAccountCloudProfile(session);
    final nickname = _nonEmptyString(cloudProfile['nickname']);
    final next = nickname == null
        ? session
        : session.copyWith(user: session.user.copyWith(nickname: nickname));
    await _persistWithProfile(next);
    return next;
  }

  Future<void> _writeAccountCloudProfile(
    AuthSession session, {
    required String nickname,
    required String bio,
    required int? age,
    required String zodiac,
    required String? avatarCloudId,
  }) async {
    if (!_enableAccountCloudProfile) return;
    await _callAccountFunction('setAccountProfile', {
      'nickname': nickname,
      'bio': bio,
      'age': age,
      'zodiac': zodiac,
      'avatar_cloud_id': ?avatarCloudId,
    }, accessToken: session.accessToken);
  }

  Future<Map<String, Object?>> _callAccountFunction(
    String action,
    Map<String, Object?> body, {
    required String accessToken,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(
              '$_baseUrl/v1/functions/$_accountFunctionName?webfn=true',
            ),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
              'authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({'action': action, ...body}),
          )
          .timeout(const Duration(seconds: 12));
    } on HandshakeException {
      throw const AuthRequestException('账号资料安全连接建立失败，请稍后重试');
    } on SocketException {
      throw const AuthRequestException('网络连接不可用，账号资料尚未同步');
    } on TimeoutException {
      throw const AuthRequestException('账号资料云同步响应较慢，请稍后重试');
    } on http.ClientException {
      throw const AuthRequestException('暂时无法连接账号资料云服务');
    }
    Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      payload = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } on Object {
      throw const AuthRequestException('账号资料云服务返回了无法识别的数据');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] == false) {
      throw AuthRequestException(
        _nonEmptyString(payload['message']) ?? '账号资料云同步失败，请稍后重试',
        code: _nonEmptyString(payload['code']),
      );
    }
    final data = payload['data'];
    return data is Map
        ? Map<String, Object?>.from(data)
        : const <String, Object?>{};
  }

  Future<_UploadedAvatar> _uploadAvatar(
    AuthSession session,
    String avatarPath,
  ) async {
    final image = await validateAvatarImage(avatarPath);
    final safeUid = session.user.uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final objectId =
        'user-avatars/$safeUid/avatar_${DateTime.now().millisecondsSinceEpoch}'
        '${image.extension}';
    final records = await _storagePost('/v1/storages/get-objects-upload-info', [
      {'objectId': objectId},
    ], accessToken: session.accessToken);
    if (records.isEmpty || records.first is! Map) {
      throw const AuthRequestException('云端没有返回头像上传凭据，请稍后重试');
    }
    final info = Map<String, Object?>.from(records.first! as Map);
    final uploadUrl = _nonEmptyString(info['uploadUrl']);
    final authorization = _nonEmptyString(info['authorization']);
    final token = _nonEmptyString(info['token']);
    final meta = _nonEmptyString(info['cloudObjectMeta']);
    final cloudObjectId = _nonEmptyString(info['cloudObjectId']);
    if (uploadUrl == null ||
        authorization == null ||
        token == null ||
        meta == null ||
        cloudObjectId == null) {
      throw AuthRequestException(
        _nonEmptyString(info['message']) ?? '头像上传凭据不完整，请稍后重试',
      );
    }
    late final http.Response uploadResponse;
    try {
      uploadResponse = await _client
          .put(
            Uri.parse(uploadUrl),
            headers: {
              'authorization': authorization,
              'x-cos-security-token': token,
              'x-cos-meta-fileid': meta,
              'content-type': image.mimeType,
            },
            body: await image.file.readAsBytes(),
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const AuthRequestException('网络连接不可用，头像尚未上传');
    } on TimeoutException {
      throw const AuthRequestException('头像上传超时，请稍后重试');
    } on http.ClientException {
      throw const AuthRequestException('暂时无法上传头像，请稍后重试');
    }
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw const AuthRequestException('头像上传失败，请稍后重试');
    }
    final localPath = await _persistAvatarFile(
      uid: session.user.uid,
      image: image,
    );
    return _UploadedAvatar(
      cloudObjectId: cloudObjectId,
      localPath: localPath,
      downloadUrl:
          _nonEmptyString(info['downloadUrl']) ??
          _nonEmptyString(info['downloadUrlEncoded']),
    );
  }

  Future<String?> _displayAvatarFor({
    required AuthSession session,
    required String? serverAvatar,
    required String? stableCloudAvatar,
    required AuthUser? stored,
  }) async {
    final cachedPath =
        await _existingLocalAvatar(stored?.avatarUrl) ??
        await _existingLocalAvatar(session.user.avatarUrl);
    final cachedCloudAvatar =
        stored?.avatarCloudId ?? session.user.avatarCloudId;
    if (cachedPath != null &&
        (stableCloudAvatar == null || stableCloudAvatar == cachedCloudAvatar)) {
      return cachedPath;
    }

    final resolved = await _resolveCloudAvatar(
      serverAvatar ?? stableCloudAvatar,
      session,
    );
    if (resolved == null) return cachedPath;
    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      return await _cacheRemoteAvatar(
            uid: session.user.uid,
            downloadUrl: resolved,
          ) ??
          cachedPath ??
          resolved;
    }
    return resolved;
  }

  Future<String?> _existingLocalAvatar(String? value) async {
    if (value == null || value.isEmpty) return null;
    File? file;
    if (value.startsWith('file://')) {
      file = File.fromUri(Uri.parse(value));
    } else if (value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
      file = File(value);
    }
    return file != null && await file.exists() ? file.path : null;
  }

  Future<String> _persistAvatarFile({
    required String uid,
    required ValidatedAvatarImage image,
  }) async {
    final directory = await _avatarDirectory(uid);
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      'avatar_${DateTime.now().microsecondsSinceEpoch}${image.extension}',
    );
    await image.file.copy(target.path);
    return target.path;
  }

  Future<String?> _cacheRemoteAvatar({
    required String uid,
    required String downloadUrl,
  }) async {
    File? temporary;
    try {
      final response = await _client
          .get(Uri.parse(downloadUrl))
          .timeout(const Duration(seconds: 18));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > maxAvatarBytes) {
        return null;
      }
      final directory = await _avatarDirectory(uid);
      temporary = File(
        '${directory.path}${Platform.pathSeparator}'
        'avatar_download_${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      final validated = await validateAvatarImage(temporary.path);
      final target = File(
        '${directory.path}${Platform.pathSeparator}'
        'avatar_${DateTime.now().microsecondsSinceEpoch}'
        '${validated.extension}',
      );
      await temporary.rename(target.path);
      temporary = null;
      return target.path;
    } on AvatarValidationException {
      return null;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on FileSystemException {
      return null;
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<Directory> _avatarDirectory(String uid) async {
    final root = await _avatarDirectoryProvider();
    final safeUid = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}mesting_avatars'
      '${Platform.pathSeparator}$safeUid',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _clearAvatarCache(String uid) async {
    final root = await _avatarDirectoryProvider();
    final safeUid = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}mesting_avatars'
      '${Platform.pathSeparator}$safeUid',
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<String?> _resolveCloudAvatar(
    String? avatar,
    AuthSession session,
  ) async {
    if (avatar == null || !avatar.startsWith('cloud://')) return avatar;
    if (_latestAvatarDownloadUrl != null) return _latestAvatarDownloadUrl;
    try {
      final objectId = Uri.parse(avatar).pathSegments.join('/');
      if (objectId.isEmpty) return null;
      final records = await _storagePost(
        '/v1/storages/get-objects-download-info',
        [
          {'objectId': objectId},
        ],
        accessToken: session.accessToken,
      );
      if (records.isEmpty || records.first is! Map) return null;
      final info = Map<String, Object?>.from(records.first! as Map);
      _latestAvatarDownloadUrl =
          _nonEmptyString(info['downloadUrl']) ??
          _nonEmptyString(info['downloadUrlEncoded']);
      return _latestAvatarDownloadUrl;
    } on AuthRequestException {
      // Profile text and login must remain usable if a private avatar URL
      // cannot be refreshed temporarily.
      return null;
    }
  }

  Future<List<Object?>> _storagePost(
    String path,
    List<Map<String, Object?>> body, {
    required String accessToken,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
              'authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 18));
    } on SocketException {
      throw const AuthRequestException('网络连接不可用，请检查网络后重试');
    } on TimeoutException {
      throw const AuthRequestException('云存储响应较慢，请稍后重试');
    } on http.ClientException {
      throw const AuthRequestException('暂时无法连接云存储，请稍后重试');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      throw const AuthRequestException('云存储返回了无法识别的数据');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
      throw AuthRequestException(_friendlyError(null, payload));
    }
    if (decoded is List) return List<Object?>.from(decoded);
    if (decoded is Map && decoded['data'] is List) {
      return List<Object?>.from(decoded['data']! as List);
    }
    throw const AuthRequestException('云存储返回的数据格式不完整');
  }

  Future<void> _persist(AuthSession session) async {
    _session = session;
    await _sessionStore.write(session);
  }

  Future<void> _persistWithProfile(AuthSession session) async {
    _session = session;
    await _sessionStore.writeSessionAndProfile(session);
  }

  bool _isInvalidSessionError(String? code) {
    return const {
      'invalid_access_token',
      'unauthenticated',
      'invalid_grant',
      '16',
    }.contains(code);
  }

  Future<AuthSession> _restoreLocalProfile(AuthSession session) async {
    final stored = await _sessionStore.readProfile(session.user.uid);
    if (stored == null) {
      _cloudAvatarId ??= session.user.avatarCloudId;
      await _sessionStore.writeProfile(session.user);
      return session;
    }
    _cloudAvatarId ??= stored.avatarCloudId ?? session.user.avatarCloudId;
    final merged = session.copyWith(
      user: AuthUser(
        uid: session.user.uid,
        nickname: stored.nickname,
        bio: stored.bio,
        age: stored.age,
        zodiac: stored.zodiac,
        avatarUrl: stored.avatarUrl,
        avatarCloudId: stored.avatarCloudId ?? session.user.avatarCloudId,
        emailMasked: session.user.emailMasked ?? stored.emailMasked,
        phoneMasked: session.user.phoneMasked ?? stored.phoneMasked,
        hasPassword: session.user.hasPassword || stored.hasPassword,
      ),
    );
    return merged;
  }
}

class _UploadedAvatar {
  const _UploadedAvatar({
    required this.cloudObjectId,
    required this.localPath,
    required this.downloadUrl,
  });

  final String cloudObjectId;
  final String localPath;
  final String? downloadUrl;
}
