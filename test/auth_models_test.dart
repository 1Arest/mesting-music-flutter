import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';

void main() {
  test('auth session round-trips without losing user profile fields', () {
    final session = AuthSession(
      user: const AuthUser(
        uid: 'user-42',
        nickname: '小新',
        bio: '喜欢晴天和音乐',
        age: 22,
        zodiac: '水瓶座',
        avatarUrl: 'https://example.test/avatar.webp',
        avatarCloudId: 'cloud://music/avatar.webp',
        emailMasked: 'm***@example.test',
      ),
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.utc(2099, 1, 1),
    );

    final restored = AuthSession.fromJson(session.toJson());

    expect(restored.user.uid, 'user-42');
    expect(restored.user.nickname, '小新');
    expect(restored.user.bio, '喜欢晴天和音乐');
    expect(restored.user.age, 22);
    expect(restored.user.zodiac, '水瓶座');
    expect(restored.user.avatarCloudId, 'cloud://music/avatar.webp');
    expect(restored.refreshToken, 'refresh-token');
    expect(restored.isExpired, isFalse);
  });

  test('blank server nickname receives a safe display fallback', () {
    final user = AuthUser.fromJson(const {'uid': 'user-1', 'nickname': '   '});

    expect(user.nickname, 'Mesting 用户');
  });
}
