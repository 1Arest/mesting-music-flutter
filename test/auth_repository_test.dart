import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/security/session_store.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const repository = UnconfiguredAuthRepository();

  test('unconfigured auth restores as signed out', () async {
    expect(await repository.restoreSession(), isNull);
  });

  test('unconfigured auth never creates a fake local account', () async {
    await expectLater(
      repository.registerWithEmail(
        email: 'listener@example.test',
        password: 'strong-password',
        verificationId: 'verification-id',
        verificationCode: '123456',
      ),
      throwsA(
        isA<AuthRequestException>().having(
          (error) => error.code,
          'code',
          'unconfigured',
        ),
      ),
    );
  });

  test('custom auth login uses the unified credential error', () async {
    final repository = HttpAuthRepository(
      baseUrl: 'https://auth.example.test',
      sessionStore: SessionStore(),
      client: MockClient(
        (request) async => http.Response(
          '{"code":"invalid_password","message":"incorrect password"}',
          401,
        ),
      ),
    );

    await expectLater(
      repository.signInWithEmail(
        email: 'listener@example.test',
        password: 'WrongPassword123',
      ),
      throwsA(
        isA<AuthRequestException>()
            .having(
              (error) => error.message,
              'message',
              invalidLoginCredentialsMessage,
            )
            .having((error) => error.code, 'code', 'invalid_password'),
      ),
    );
  });

  test(
    'custom auth deletes the active account with a recent sudo token',
    () async {
      final store = _MemorySessionStore();
      store.session = _testSession();
      store.remembered = _testSession();
      final repository = HttpAuthRepository(
        baseUrl: 'https://auth.example.test',
        sessionStore: store,
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/v1/me');
          expect(request.headers['authorization'], 'Bearer active-access');
          expect(jsonDecode(request.body), {'sudo_token': 'recent-sudo-token'});
          return http.Response('{"deleted":true}', 200);
        }),
      );

      await repository.deleteAccount(sudoToken: 'recent-sudo-token');

      expect(store.session, isNull);
      expect(store.remembered, isNull);
    },
  );

  group('local preview account', () {
    late SharedPreferences preferences;
    late Directory temporaryDirectory;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'mesting_local_account_test_',
      );
    });

    tearDown(() async {
      if (temporaryDirectory.existsSync()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    LocalPreviewAuthRepository createRepository() {
      return LocalPreviewAuthRepository(
        preferences: preferences,
        documentsDirectory: () async => temporaryDirectory,
      );
    }

    test('provisions and restores one stable device account', () async {
      final first = await createRepository().restoreSession();
      final restored = await createRepository().restoreSession();

      expect(first, isNotNull);
      expect(first!.user.uid, localPreviewUserId);
      expect(first.user.nickname, 'Mest');
      expect(restored!.user.uid, first.user.uid);
      expect(restored.user.bio, first.user.bio);
    });

    test('persists profile and copies avatar into app storage', () async {
      final repository = createRepository();
      await repository.restoreSession();
      final source = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}picked.png',
      );
      await source.writeAsBytes(const [137, 80, 78, 71]);

      final updated = await repository.updateProfile(
        nickname: 'Mesting',
        bio: '喜欢音乐',
        avatarPath: source.path,
      );
      final restored = await createRepository().restoreSession();

      expect(updated.user.nickname, 'Mesting');
      expect(updated.user.avatarUrl, isNot(source.path));
      expect(File(updated.user.avatarUrl!).existsSync(), isTrue);
      expect(restored!.user.avatarUrl, updated.user.avatarUrl);
    });

    test('explicit sign out is respected until local sign in', () async {
      final repository = createRepository();
      await repository.restoreSession();
      await repository.signOut();

      expect(await createRepository().restoreSession(), isNull);

      final signedIn = await createRepository().signInWithEmail(
        email: 'listener@example.test',
        password: 'local-password',
      );
      expect(signedIn.user.uid, localPreviewUserId);
      expect(signedIn.user.emailMasked, 'l***@example.test');
    });

    test(
      'deletion removes the device-only account until a new explicit sign in',
      () async {
        final repository = createRepository();
        await repository.restoreSession();
        final challenge = await repository.requestCurrentIdentityCode(
          method: AuthMethod.email,
        );
        final sudoToken = await repository.verifyCurrentIdentity(
          verificationId: challenge.verificationId,
          verificationCode: '123456',
        );

        await repository.deleteAccount(sudoToken: sudoToken);

        expect(await createRepository().restoreSession(), isNull);
        final fresh = await createRepository().signInWithEmail(
          email: 'fresh@example.test',
          password: 'local-password',
        );
        expect(fresh.user.emailMasked, 'f***@example.test');
      },
    );
  });
}

AuthSession _testSession() {
  return AuthSession(
    user: const AuthUser(uid: 'user-1', nickname: 'Listener'),
    accessToken: 'active-access',
    refreshToken: 'active-refresh',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
}

class _MemorySessionStore extends SessionStore {
  AuthSession? session;
  AuthSession? remembered;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> clear() async {
    session = null;
  }

  @override
  Future<void> clearAll() async {
    session = null;
    remembered = null;
  }
}
