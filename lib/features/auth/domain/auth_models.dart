import 'dart:async';

enum AuthMethod { email, phone }

const _authUserFieldUnset = Object();

typedef AuthSessionProvider = FutureOr<AuthSession?> Function();
typedef AuthSessionRefresher = Future<AuthSession?> Function();

extension AuthMethodLabel on AuthMethod {
  String get label => this == AuthMethod.email ? '邮箱' : '手机号';
}

class SecurityVerificationChallenge {
  const SecurityVerificationChallenge({
    required this.verificationId,
    required this.expiresIn,
    required this.maskedTarget,
  });

  final String verificationId;
  final Duration expiresIn;
  final String maskedTarget;
}

class PasswordResetProof {
  const PasswordResetProof({
    required this.method,
    required this.account,
    required this.verificationToken,
    required this.expiresAt,
  });

  final AuthMethod method;
  final String account;
  final String verificationToken;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
}

class EmailVerificationChallenge {
  const EmailVerificationChallenge({
    required this.verificationId,
    required this.expiresIn,
    required this.isExistingUser,
  });

  final String verificationId;
  final Duration expiresIn;
  final bool isExistingUser;
}

class PhoneVerificationChallenge {
  const PhoneVerificationChallenge({
    required this.verificationId,
    required this.expiresIn,
    required this.isExistingUser,
  });

  final String verificationId;
  final Duration expiresIn;
  final bool isExistingUser;
}

class AuthUser {
  const AuthUser({
    required this.uid,
    required this.nickname,
    this.bio = '',
    this.age,
    this.zodiac = '',
    this.avatarUrl,
    this.avatarCloudId,
    this.emailMasked,
    this.phoneMasked,
    this.hasPassword = false,
  });

  final String uid;
  final String nickname;
  final String bio;
  final int? age;
  final String zodiac;
  final String? avatarUrl;
  final String? avatarCloudId;
  final String? emailMasked;
  final String? phoneMasked;
  final bool hasPassword;

  bool get hasEmailBinding => emailMasked?.trim().isNotEmpty == true;
  bool get hasPhoneBinding => phoneMasked?.trim().isNotEmpty == true;

  AuthUser copyWith({
    String? nickname,
    String? bio,
    Object? age = _authUserFieldUnset,
    String? zodiac,
    String? avatarUrl,
    String? avatarCloudId,
    String? emailMasked,
    String? phoneMasked,
    bool? hasPassword,
  }) {
    return AuthUser(
      uid: uid,
      nickname: nickname ?? this.nickname,
      bio: bio ?? this.bio,
      age: identical(age, _authUserFieldUnset) ? this.age : age as int?,
      zodiac: zodiac ?? this.zodiac,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarCloudId: avatarCloudId ?? this.avatarCloudId,
      emailMasked: emailMasked ?? this.emailMasked,
      phoneMasked: phoneMasked ?? this.phoneMasked,
      hasPassword: hasPassword ?? this.hasPassword,
    );
  }

  factory AuthUser.fromJson(Map<String, Object?> json) {
    return AuthUser(
      uid: json['uid']! as String,
      nickname: (json['nickname'] as String?)?.trim().isNotEmpty == true
          ? json['nickname']! as String
          : 'Mesting 用户',
      bio: json['bio'] as String? ?? '',
      age: _profileAge(json['age']),
      zodiac: json['zodiac'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      avatarCloudId: json['avatar_cloud_id'] as String?,
      emailMasked: json['email_masked'] as String?,
      phoneMasked: json['phone_masked'] as String?,
      hasPassword: json['has_password'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
    'uid': uid,
    'nickname': nickname,
    'bio': bio,
    'age': age,
    'zodiac': zodiac,
    'avatar_url': avatarUrl,
    'avatar_cloud_id': avatarCloudId,
    'email_masked': emailMasked,
    'phone_masked': phoneMasked,
    'has_password': hasPassword,
  };
}

int? _profileAge(Object? value) {
  final age = value is int ? value : int.tryParse(value?.toString() ?? '');
  return age != null && age >= 1 && age <= 120 ? age : null;
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final AuthUser user;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpired =>
      expiresAt.isBefore(DateTime.now().add(const Duration(seconds: 30)));

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      user: AuthUser.fromJson(json['user']! as Map<String, Object?>),
      accessToken: json['access_token']! as String,
      refreshToken: json['refresh_token']! as String,
      expiresAt: DateTime.parse(json['expires_at']! as String),
    );
  }

  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };

  AuthSession copyWith({AuthUser? user}) {
    return AuthSession(
      user: user ?? this.user,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    );
  }
}

class AuthRequestException implements Exception {
  const AuthRequestException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
