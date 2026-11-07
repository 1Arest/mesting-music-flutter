import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/security/session_store.dart';
import 'package:mesting_music/features/auth/data/cloudbase_auth_repository.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';

void main() {
  group('CloudBase authentication', () {
    test(
      'session and profile persistence starts both writes together',
      () async {
        final store = BlockingSessionStore();
        final persistence = store.writeSessionAndProfile(_activeSession());

        await Future.wait<void>([
          store.sessionWriteStarted.future,
          store.profileWriteStarted.future,
        ]).timeout(const Duration(seconds: 1));
        store.releaseWrites.complete();
        await persistence;

        expect(store.sessionWriteCount, 1);
        expect(store.profileWriteCount, 1);
      },
    );

    test('retries one TLS handshake failure before signing in', () async {
      var requestCount = 0;
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: MemorySessionStore(),
        client: MockClient((request) async {
          requestCount += 1;
          if (requestCount == 1) {
            throw const HandshakeException(
              'Connection terminated during handshake',
            );
          }
          if (request.url.path == '/auth/v1/signin') {
            return _json({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'expires_in': 7200,
              'sub': 'cloud-user-1',
            });
          }
          expect(request.url.path, '/auth/v1/user/me');
          return _json({'sub': 'cloud-user-1'});
        }),
      );

      final session = await repository.signInWithEmail(
        email: 'listener@example.com',
        password: 'StrongPassword123',
      );

      expect(session.user.uid, 'cloud-user-1');
      expect(requestCount, 3);
    });

    for (final code in const [
      'user_not_found',
      'account_not_found',
      'email_not_found',
      'invalid_grant',
      'invalid_password',
      'invalid_credentials',
      'incorrect_password',
      'wrong_password',
      'password_error',
    ]) {
      test('conceals $code as the unified login credential error', () async {
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: MemorySessionStore(),
          client: MockClient((request) async {
            expect(request.url.path, '/auth/v1/signin');
            return _json({'error': code}, 401);
          }),
        );

        await expectLater(
          repository.signInWithEmail(
            email: 'listener@example.com',
            password: 'WrongPassword123',
          ),
          throwsA(
            isA<AuthRequestException>()
                .having((error) => error.message, 'message', '账号或密码错误')
                .having((error) => error.code, 'code', code),
          ),
        );
      });
    }

    test(
      'restores profile and avatar from account cloud data after local data is cleared',
      () async {
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: MemorySessionStore(),
          enableAccountCloudProfile: true,
          client: MockClient((request) async {
            if (request.url.path == '/auth/v1/signin') {
              return _json({
                'access_token': 'cloud-profile-access',
                'refresh_token': 'cloud-profile-refresh',
                'expires_in': 7200,
                'sub': 'cloud-profile-user',
              });
            }
            if (request.url.path == '/auth/v1/user/me') {
              return _json({
                'sub': 'cloud-profile-user',
                'nickname': 'Mesting 用户',
              });
            }
            if (request.url.path == '/v1/functions/social-api') {
              final body = Map<String, Object?>.from(
                jsonDecode(request.body) as Map,
              );
              expect(body['action'], 'getAccountProfile');
              return _json({
                'success': true,
                'data': {
                  'profile': {
                    'uid': 'cloud-profile-user',
                    'nickname': '云端昵称',
                    'bio': '云端简介',
                    'age': 24,
                    'zodiac': '天秤座',
                    'avatar_url': 'https://cdn.example/profile-avatar.png',
                    'avatar_cloud_id':
                        'cloud://music-env.bucket/user-avatars/cloud-profile-user/avatar.png',
                  },
                },
              });
            }
            if (request.url.host == 'cdn.example') {
              return http.Response('', 404);
            }
            throw StateError(
              'Unexpected request: ${request.method} ${request.url}',
            );
          }),
        );

        final session = await repository.signInWithEmail(
          email: 'profile@example.com',
          password: 'StrongPassword123',
        );

        expect(session.user.nickname, '云端昵称');
        expect(session.user.bio, '云端简介');
        expect(session.user.age, 24);
        expect(session.user.zodiac, '天秤座');
        expect(
          session.user.avatarUrl,
          'https://cdn.example/profile-avatar.png',
        );
        expect(
          session.user.avatarCloudId,
          'cloud://music-env.bucket/user-avatars/cloud-profile-user/avatar.png',
        );
      },
    );

    test('profile edits are backed up to account cloud data', () async {
      Map<String, Object?>? cloudWrite;
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: MemorySessionStore(),
        enableAccountCloudProfile: true,
        client: MockClient((request) async {
          if (request.url.path == '/auth/v1/signin') {
            return _json({
              'access_token': 'cloud-write-access',
              'refresh_token': 'cloud-write-refresh',
              'expires_in': 7200,
              'sub': 'cloud-write-user',
            });
          }
          if (request.url.path == '/auth/v1/user/me') {
            return _json({'sub': 'cloud-write-user', 'nickname': '旧昵称'});
          }
          if (request.url.path == '/auth/v1/user/basic/edit') {
            return _json({});
          }
          if (request.url.path == '/v1/functions/social-api') {
            final body = Map<String, Object?>.from(
              jsonDecode(request.body) as Map,
            );
            if (body['action'] == 'getAccountProfile') {
              return _json({
                'success': true,
                'data': {
                  'profile': {
                    'uid': 'cloud-write-user',
                    'nickname': '旧昵称',
                    'bio': '',
                    'age': null,
                    'zodiac': '',
                  },
                },
              });
            }
            expect(body['action'], 'setAccountProfile');
            cloudWrite = body;
            return _json({
              'success': true,
              'data': {
                'profile': {
                  'uid': 'cloud-write-user',
                  'nickname': body['nickname'],
                  'bio': body['bio'],
                  'age': body['age'],
                  'zodiac': body['zodiac'],
                },
              },
            });
          }
          throw StateError(
            'Unexpected request: ${request.method} ${request.url}',
          );
        }),
      );

      await repository.signInWithEmail(
        email: 'profile-write@example.com',
        password: 'StrongPassword123',
      );
      final updated = await repository.updateProfile(
        nickname: '新昵称',
        bio: '会跨设备恢复',
        age: 25,
        zodiac: '天蝎座',
      );

      expect(updated.user.nickname, '新昵称');
      expect(cloudWrite, isNotNull);
      expect(cloudWrite!['bio'], '会跨设备恢复');
      expect(cloudWrite!['age'], 25);
      expect(cloudWrite!['zodiac'], '天蝎座');
    });

    test(
      'restores a legacy camel-case CloudBase avatar after local clone data is gone',
      () async {
        final temporaryDirectory = await Directory.systemTemp.createTemp(
          'mesting_legacy_clone_avatar_test_',
        );
        try {
          const cloudAvatar =
              'cloud://music-env.bucket/user-avatars/legacy-user/avatar.png';
          final store = MemorySessionStore();
          final repository = CloudBaseAuthRepository(
            environmentId: 'music-env',
            sessionStore: store,
            avatarDirectoryProvider: () async => temporaryDirectory,
            client: MockClient((request) async {
              return switch (request.url.path) {
                '/auth/v1/signin' => _json({
                  'access_token': 'legacy-access',
                  'refresh_token': 'legacy-refresh',
                  'expires_in': 7200,
                  'sub': 'legacy-user',
                }),
                '/auth/v1/user/me' => _json({
                  'sub': 'legacy-user',
                  'nickName': 'Hello',
                  'avatarUrl': cloudAvatar,
                }),
                '/v1/storages/get-objects-download-info' => _jsonList([
                  {'downloadUrl': 'https://cdn.example/legacy-avatar.png'},
                ]),
                '/legacy-avatar.png' => http.Response.bytes(const [
                  0x89,
                  0x50,
                  0x4E,
                  0x47,
                  0x0D,
                  0x0A,
                  0x1A,
                  0x0A,
                  0,
                  0,
                  0,
                  0,
                ], 200),
                _ => throw StateError(
                  'Unexpected request: ${request.method} ${request.url}',
                ),
              };
            }),
          );

          final session = await repository.signInWithEmail(
            email: 'hello@example.com',
            password: 'StrongPassword123',
          );

          expect(session.user.nickname, 'Hello');
          expect(session.user.avatarCloudId, cloudAvatar);
          expect(session.user.avatarUrl, isNotNull);
          expect(File(session.user.avatarUrl!).existsSync(), isTrue);
          expect(store.profiles['legacy-user']?.avatarCloudId, cloudAvatar);
          expect(
            File(store.profiles['legacy-user']!.avatarUrl!).existsSync(),
            isTrue,
          );
        } finally {
          await temporaryDirectory.delete(recursive: true);
        }
      },
    );

    test('converts repeated TLS handshake failures to Chinese', () async {
      var requestCount = 0;
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: MemorySessionStore(),
        client: MockClient((request) async {
          requestCount += 1;
          throw const HandshakeException(
            'Connection terminated during handshake',
          );
        }),
      );

      await expectLater(
        repository.signInWithEmail(
          email: 'listener@example.com',
          password: 'StrongPassword123',
        ),
        throwsA(
          isA<AuthRequestException>().having(
            (error) => error.message,
            'message',
            '安全连接建立失败，请切换网络后重试',
          ),
        ),
      );
      expect(requestCount, 2);
    });

    test(
      'sends an email verification code through the environment gateway',
      () async {
        late Map<String, Object?> requestBody;
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: MemorySessionStore(),
          client: MockClient((request) async {
            expect(
              request.url.toString(),
              'https://music-env.api.tcloudbasegateway.com/auth/v1/verification',
            );
            requestBody = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response(
              jsonEncode({
                'verification_id': 'verify-1',
                'expires_in': 600,
                'is_user': false,
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
        );

        final challenge = await repository.requestEmailCode(
          email: 'Listener@Example.com',
        );

        expect(requestBody['email'], 'Listener@Example.com');
        expect(requestBody['target'], 'ANY');
        expect(challenge.verificationId, 'verify-1');
        expect(challenge.expiresIn, const Duration(minutes: 10));
        expect(challenge.isExistingUser, isFalse);
      },
    );

    test('verifies the code, signs up, and persists the session', () async {
      final paths = <String>[];
      final store = MemorySessionStore();
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: store,
        client: MockClient((request) async {
          paths.add(request.url.path);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (request.url.path.endsWith('/verification/verify')) {
            expect(body['verification_id'], 'verify-1');
            expect(body['verification_code'], '123456');
            return _json({'verification_token': 'verified-token'});
          }
          expect(request.url.path, '/auth/v1/signup');
          expect(body['email'], 'listener@example.com');
          expect(body['verification_token'], 'verified-token');
          expect(body['password'], 'StrongPassword123');
          return _json({
            'token_type': 'Bearer',
            'access_token': 'access-1',
            'refresh_token': 'refresh-1',
            'expires_in': 7200,
            'sub': 'cloud-user-1',
          });
        }),
      );

      final session = await repository.registerWithEmail(
        email: 'Listener@Example.com',
        password: 'StrongPassword123',
        verificationId: 'verify-1',
        verificationCode: '123456',
      );

      expect(paths, ['/auth/v1/verification/verify', '/auth/v1/signup']);
      expect(session.user.uid, 'cloud-user-1');
      expect(session.user.emailMasked, 'l***@example.com');
      expect(session.accessToken, 'access-1');
      expect(store.session?.refreshToken, 'refresh-1');
    });

    test(
      'uses the unique cloud nickname immediately after email registration',
      () async {
        final paths = <String>[];
        final store = MemorySessionStore();
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: store,
          enableAccountCloudProfile: true,
          client: MockClient((request) async {
            paths.add(request.url.path);
            final body = jsonDecode(request.body) as Map<String, Object?>;
            if (request.url.path.endsWith('/verification/verify')) {
              return _json({'verification_token': 'verified-token'});
            }
            if (request.url.path == '/auth/v1/signup') {
              return _json({
                'token_type': 'Bearer',
                'access_token': 'generated-name-access',
                'refresh_token': 'generated-name-refresh',
                'expires_in': 7200,
                'sub': 'generated-name-user',
              });
            }
            expect(request.url.path, '/v1/functions/social-api');
            expect(
              request.headers['authorization'],
              'Bearer generated-name-access',
            );
            expect(body['action'], 'getAccountProfile');
            return _json({
              'success': true,
              'data': {
                'profile': {
                  'uid': 'generated-name-user',
                  'nickname': '用户482731',
                  'bio': '',
                  'age': null,
                  'zodiac': '',
                },
              },
            });
          }),
        );

        final session = await repository.registerWithEmail(
          email: 'new-user@example.com',
          password: 'StrongPassword123',
          verificationId: 'verify-1',
          verificationCode: '123456',
        );

        expect(paths, [
          '/auth/v1/verification/verify',
          '/auth/v1/signup',
          '/v1/functions/social-api',
        ]);
        expect(session.user.nickname, '用户482731');
        expect(store.session?.user.nickname, '用户482731');
        expect(store.profiles['generated-name-user']?.nickname, '用户482731');
      },
    );

    test('rotates an expired session refresh token on restore', () async {
      final store = MemorySessionStore();
      await store.write(
        AuthSession(
          user: const AuthUser(
            uid: 'cloud-user-1',
            nickname: 'listener',
            emailMasked: 'l***@example.com',
          ),
          accessToken: 'expired-access',
          refreshToken: 'old-refresh',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: store,
        client: MockClient((request) async {
          if (request.url.path == '/auth/v1/user/me') {
            expect(request.headers['authorization'], 'Bearer fresh-access');
            return _json({'sub': 'cloud-user-1'});
          }
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(request.url.path, '/auth/v1/token');
          expect(body['grant_type'], 'refresh_token');
          expect(body['refresh_token'], 'old-refresh');
          return _json({
            'access_token': 'fresh-access',
            'refresh_token': 'fresh-refresh',
            'expires_in': 7200,
            'sub': 'cloud-user-1',
          });
        }),
      );

      final restored = await repository.restoreSession();

      expect(restored?.accessToken, 'fresh-access');
      expect(restored?.refreshToken, 'fresh-refresh');
      expect(store.session?.refreshToken, 'fresh-refresh');
    });

    test(
      'renews an active access token when an authenticated API rejects it',
      () async {
        final store = MemorySessionStore();
        await store.write(
          AuthSession(
            user: const AuthUser(uid: 'cloud-user-1', nickname: 'listener'),
            accessToken: 'rejected-access',
            refreshToken: 'active-refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: store,
          client: MockClient((request) async {
            expect(request.url.path, '/auth/v1/token');
            final body = jsonDecode(request.body) as Map<String, Object?>;
            expect(body['grant_type'], 'refresh_token');
            expect(body['refresh_token'], 'active-refresh');
            return _json({
              'access_token': 'forced-fresh-access',
              'refresh_token': 'forced-fresh-refresh',
              'expires_in': 7200,
              'sub': 'cloud-user-1',
            });
          }),
        );

        final renewed = await repository.renewSession();

        expect(renewed?.accessToken, 'forced-fresh-access');
        expect(store.session?.refreshToken, 'forced-fresh-refresh');
      },
    );

    test('migrates an existing session profile into account storage', () async {
      final store = MemorySessionStore();
      await store.write(
        AuthSession(
          user: const AuthUser(
            uid: 'cloud-user-legacy',
            nickname: '旧版昵称',
            bio: '旧版个人简介',
            avatarUrl: '/stable/avatar.png',
            emailMasked: 'l***@example.com',
          ),
          accessToken: 'active-access',
          refreshToken: 'active-refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: store,
        client: MockClient((request) async {
          expect(request.url.path, '/auth/v1/user/me');
          return _json({'sub': 'cloud-user-legacy'});
        }),
      );

      final restored = await repository.restoreSession();

      expect(restored?.user.nickname, '旧版昵称');
      expect(store.profiles['cloud-user-legacy']?.bio, '旧版个人简介');
      expect(
        store.profiles['cloud-user-legacy']?.avatarUrl,
        '/stable/avatar.png',
      );
    });

    test(
      'returns a valid cached account before background reconciliation',
      () async {
        final store = MemorySessionStore();
        await store.write(
          AuthSession(
            user: const AuthUser(
              uid: 'cloud-user-fast',
              nickname: '缓存昵称',
              bio: '立即显示的本地资料',
            ),
            accessToken: 'active-access',
            refreshToken: 'active-refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        final responseGate = Completer<http.Response>();
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: store,
          client: MockClient((request) {
            expect(request.url.path, '/auth/v1/user/me');
            return responseGate.future;
          }),
        );

        final cached = await repository.restoreSession();

        expect(cached?.user.nickname, '缓存昵称');
        expect(responseGate.isCompleted, isFalse);

        final refresh = repository.refreshRestoredSession();
        await Future<void>.delayed(Duration.zero);
        expect(responseGate.isCompleted, isFalse);
        responseGate.complete(
          _json({'sub': 'cloud-user-fast', 'nickname': '云端昵称'}),
        );

        expect((await refresh)?.user.nickname, '云端昵称');
      },
    );

    test('registers a phone account with an SMS verification token', () async {
      final paths = <String>[];
      final store = MemorySessionStore();
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: store,
        enableAccountCloudProfile: true,
        client: MockClient((request) async {
          paths.add(request.url.path);
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return switch (request.url.path) {
            '/auth/v1/verification' => () {
              expect(body['phone_number'], '+86 13800138000');
              expect(body['target'], 'ANY');
              return _json({
                'verification_id': 'sms-verify-1',
                'expires_in': 600,
                'is_user': false,
              });
            }(),
            '/auth/v1/verification/verify' => () {
              expect(body['verification_id'], 'sms-verify-1');
              expect(body['verification_code'], '654321');
              return _json({'verification_token': 'sms-token'});
            }(),
            '/auth/v1/signup' => () {
              expect(body['phone_number'], '+86 13800138000');
              expect(body['verification_token'], 'sms-token');
              return _json({
                'access_token': 'phone-access',
                'refresh_token': 'phone-refresh',
                'expires_in': 7200,
                'sub': 'phone-user-1',
              });
            }(),
            '/v1/functions/social-api' => () {
              expect(request.headers['authorization'], 'Bearer phone-access');
              expect(body['action'], 'getAccountProfile');
              return _json({
                'success': true,
                'data': {
                  'profile': {
                    'uid': 'phone-user-1',
                    'nickname': '用户163904',
                    'bio': '',
                    'age': null,
                    'zodiac': '',
                  },
                },
              });
            }(),
            _ => throw StateError('Unexpected path: ${request.url.path}'),
          };
        }),
      );

      final challenge = await repository.requestPhoneCode(
        phone: '13800138000',
        registration: true,
      );
      final session = await repository.verifyPhoneCode(
        phone: '13800138000',
        code: '654321',
        verificationId: challenge.verificationId,
        registration: true,
      );

      expect(paths, [
        '/auth/v1/verification',
        '/auth/v1/verification/verify',
        '/auth/v1/signup',
        '/v1/functions/social-api',
      ]);
      expect(session.user.uid, 'phone-user-1');
      expect(session.user.nickname, '用户163904');
      expect(session.user.phoneMasked, '138****8000');
      expect(store.session?.accessToken, 'phone-access');
    });

    test('profile and validated avatar restore from CloudBase by uid', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'mesting_cloud_profile_test_',
      );
      try {
        var signInCount = 0;
        var cloudNickname = '';
        var cloudBio = '';
        var cloudAvatar = '';
        final paths = <String>[];
        final store = MemorySessionStore();
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: store,
          avatarDirectoryProvider: () async => temporaryDirectory,
          client: MockClient((request) async {
            paths.add('${request.method} ${request.url.path}');
            switch (request.url.path) {
              case '/auth/v1/signin':
                signInCount += 1;
                return _json({
                  'access_token': 'access-$signInCount',
                  'refresh_token': 'refresh-$signInCount',
                  'expires_in': 7200,
                  'sub': 'cloud-user-1',
                });
              case '/auth/v1/user/me':
                return _json({
                  'sub': 'cloud-user-1',
                  'email': 'listener@example.com',
                  if (cloudNickname.isNotEmpty) 'name': cloudNickname,
                  if (cloudBio.isNotEmpty) 'user_desc': cloudBio,
                  if (cloudAvatar.isNotEmpty) 'picture': cloudAvatar,
                });
              case '/v1/storages/get-objects-upload-info':
                expect(request.headers['authorization'], 'Bearer access-1');
                final body = jsonDecode(request.body) as List<Object?>;
                expect(
                  (body.first! as Map<String, Object?>)['objectId'],
                  startsWith('user-avatars/cloud-user-1/avatar_'),
                );
                return _jsonList([
                  {
                    'uploadUrl': 'https://upload.example/avatar',
                    'authorization': 'signed-upload',
                    'token': 'temporary-token',
                    'cloudObjectMeta': 'avatar-meta',
                    'downloadUrl': 'https://cdn.example/avatar-signed',
                    'cloudObjectId':
                        'cloud://music-env.bucket/user-avatars/cloud-user-1/avatar.png',
                  },
                ]);
              case '/avatar':
                expect(request.method, 'PUT');
                expect(request.headers['authorization'], 'signed-upload');
                expect(request.headers['content-type'], 'image/png');
                expect(request.bodyBytes.take(8), [
                  0x89,
                  0x50,
                  0x4E,
                  0x47,
                  0x0D,
                  0x0A,
                  0x1A,
                  0x0A,
                ]);
                return http.Response('', 200);
              case '/auth/v1/user/basic/edit':
                final body = jsonDecode(request.body) as Map<String, Object?>;
                cloudNickname = body['nickname']! as String;
                cloudBio = body['description']! as String;
                cloudAvatar = body['avatar_url']! as String;
                return _json({});
              case '/v1/storages/get-objects-download-info':
                return _jsonList([
                  {'downloadUrl': 'https://cdn.example/avatar-refreshed'},
                ]);
              case '/auth/v1/user/signout':
                return _json({});
              default:
                throw StateError(
                  'Unexpected request: ${request.method} ${request.url}',
                );
            }
          }),
        );

        await repository.signInWithEmail(
          email: 'listener@example.com',
          password: 'StrongPassword123',
        );
        final accountReadsBeforeUpdate = paths
            .where((path) => path == 'GET /auth/v1/user/me')
            .length;
        final sessionWritesBeforeUpdate = store.sessionWriteCount;
        final profileWritesBeforeUpdate = store.profileWriteCount;
        final pickedAvatar = File(
          '${temporaryDirectory.path}${Platform.pathSeparator}picked.png',
        );
        await pickedAvatar.writeAsBytes(const [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0,
          0,
          0,
          0,
        ]);
        final updated = await repository.updateProfile(
          nickname: 'Mesting Listener',
          bio: '每天都要听音乐',
          age: 23,
          zodiac: '双子座',
          avatarPath: pickedAvatar.path,
        );
        expect(
          paths.where((path) => path == 'GET /auth/v1/user/me').length,
          accountReadsBeforeUpdate,
        );
        expect(store.sessionWriteCount, sessionWritesBeforeUpdate + 1);
        expect(store.profileWriteCount, profileWritesBeforeUpdate + 1);

        await repository.signOut();
        final restored = await repository.signInWithEmail(
          email: 'listener@example.com',
          password: 'StrongPassword123',
        );

        expect(restored.user.nickname, 'Mesting Listener');
        expect(restored.user.bio, '每天都要听音乐');
        expect(restored.user.age, 23);
        expect(restored.user.zodiac, '双子座');
        expect(updated.user.avatarUrl, isNotNull);
        expect(File(updated.user.avatarUrl!).existsSync(), isTrue);
        expect(
          updated.user.avatarCloudId,
          'cloud://music-env.bucket/user-avatars/cloud-user-1/avatar.png',
        );
        expect(restored.user.avatarUrl, updated.user.avatarUrl);
        expect(restored.user.avatarCloudId, updated.user.avatarCloudId);
        expect(store.session?.accessToken, 'access-2');
        expect(paths, contains('PUT /avatar'));
        expect(paths, contains('POST /auth/v1/user/basic/edit'));
        expect(
          paths,
          isNot(contains('POST /v1/storages/get-objects-download-info')),
        );
      } finally {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test(
      'caches a refreshed CloudBase avatar and restores it while offline',
      () async {
        final temporaryDirectory = await Directory.systemTemp.createTemp(
          'mesting_cloud_avatar_cache_test_',
        );
        try {
          const cloudAvatar =
              'cloud://music-env.bucket/user-avatars/cloud-user-1/avatar.png';
          const expiredAvatar =
              'https://cdn.example/avatar.png?expired-token=1';
          final user = const AuthUser(
            uid: 'cloud-user-1',
            nickname: 'listener',
            avatarUrl: expiredAvatar,
            avatarCloudId: cloudAvatar,
          );
          final store = MemorySessionStore();
          await store.write(
            AuthSession(
              user: user,
              accessToken: 'active-access',
              refreshToken: 'active-refresh',
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          );
          await store.writeProfile(user);

          var online = true;
          var downloadInfoCalls = 0;
          final client = MockClient((request) async {
            if (!online) throw const SocketException('offline');
            return switch (request.url.path) {
              '/auth/v1/user/me' => _json({
                'sub': 'cloud-user-1',
                'picture': cloudAvatar,
              }),
              '/v1/storages/get-objects-download-info' => () {
                downloadInfoCalls += 1;
                return _jsonList([
                  {'downloadUrl': 'https://cdn.example/avatar-file.png'},
                ]);
              }(),
              '/avatar-file.png' => http.Response.bytes(const [
                0x89,
                0x50,
                0x4E,
                0x47,
                0x0D,
                0x0A,
                0x1A,
                0x0A,
                0,
                0,
                0,
                0,
              ], 200),
              _ => throw StateError('Unexpected path: ${request.url.path}'),
            };
          });
          final repository = CloudBaseAuthRepository(
            environmentId: 'music-env',
            sessionStore: store,
            client: client,
            avatarDirectoryProvider: () async => temporaryDirectory,
          );

          final cached = await repository.restoreSession();
          expect(cached?.user.avatarUrl, expiredAvatar);

          final refreshed = await repository.refreshRestoredSession();
          final cachedPath = refreshed!.user.avatarUrl!;
          expect(cachedPath, isNot(expiredAvatar));
          expect(File(cachedPath).existsSync(), isTrue);
          expect(refreshed.user.avatarCloudId, cloudAvatar);
          expect(downloadInfoCalls, 1);

          online = false;
          final restartedRepository = CloudBaseAuthRepository(
            environmentId: 'music-env',
            sessionStore: store,
            client: client,
            avatarDirectoryProvider: () async => temporaryDirectory,
          );
          final offline = await restartedRepository.restoreSession();

          expect(offline?.user.avatarUrl, cachedPath);
          expect(File(offline!.user.avatarUrl!).existsSync(), isTrue);
          expect(downloadInfoCalls, 1);
        } finally {
          await temporaryDirectory.delete(recursive: true);
        }
      },
    );

    test(
      'refreshes real cloud binding state and only persists masks',
      () async {
        final store = MemorySessionStore();
        await store.write(_activeSession());
        await store.writeProfile(_activeSession().user);
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: store,
          client: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/auth/v1/user/me');
            expect(request.headers['authorization'], 'Bearer active-access');
            return _json({
              'sub': 'cloud-user-1',
              'email': 'listener@example.com',
              'phone_number': '+86 13800138000',
              'has_password': true,
            });
          }),
        );

        final refreshed = await repository.refreshAccount();

        expect(refreshed.user.emailMasked, 'l***@example.com');
        expect(refreshed.user.phoneMasked, '138****8000');
        expect(refreshed.user.hasPassword, isTrue);
        expect(
          jsonEncode(store.session!.toJson()),
          isNot(contains('13800138000')),
        );
        expect(
          jsonEncode(store.session!.toJson()),
          isNot(contains('listener@example.com')),
        );
      },
    );

    test(
      'reauthenticates current contact before binding a new phone',
      () async {
        final store = MemorySessionStore();
        await store.write(_activeSession());
        var currentPhone = '';
        var verificationCall = 0;
        var verifyCall = 0;
        final paths = <String>[];
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: store,
          client: MockClient((request) async {
            paths.add(request.url.path);
            final body = request.body.isEmpty
                ? <String, Object?>{}
                : jsonDecode(request.body) as Map<String, Object?>;
            switch (request.url.path) {
              case '/auth/v1/user/me':
                expect(
                  request.headers['authorization'],
                  'Bearer active-access',
                );
                return _json({
                  'sub': 'cloud-user-1',
                  'email': 'listener@example.com',
                  if (currentPhone.isNotEmpty) 'phone_number': currentPhone,
                  'has_password': true,
                });
              case '/auth/v1/verification':
                verificationCall += 1;
                if (verificationCall == 1) {
                  expect(body['target'], 'USER');
                  expect(body['email'], 'listener@example.com');
                  return _json({
                    'verification_id': 'current-code',
                    'expires_in': 300,
                  });
                }
                expect(body['target'], 'ANY');
                expect(body['phone_number'], '+86 13900139000');
                return _json({
                  'verification_id': 'new-phone-code',
                  'expires_in': 600,
                });
              case '/auth/v1/verification/verify':
                verifyCall += 1;
                return _json({
                  'verification_token': verifyCall == 1
                      ? 'current-proof'
                      : 'new-phone-proof',
                });
              case '/auth/v1/user/sudo':
                expect(body['verification_token'], 'current-proof');
                expect(
                  request.headers['authorization'],
                  'Bearer active-access',
                );
                return _json({'sudo_token': 'sudo-proof'});
              case '/auth/v1/user/contact':
                expect(body['phone_number'], '+86 13900139000');
                expect(body['verification_token'], 'new-phone-proof');
                expect(body['sudo_token'], 'sudo-proof');
                expect(
                  request.headers['authorization'],
                  'Bearer active-access',
                );
                currentPhone = '+86 13900139000';
                return _json({});
              default:
                throw StateError('Unexpected path: ${request.url.path}');
            }
          }),
        );

        final currentChallenge = await repository.requestCurrentIdentityCode(
          method: AuthMethod.email,
        );
        final sudoToken = await repository.verifyCurrentIdentity(
          verificationId: currentChallenge.verificationId,
          verificationCode: '123456',
        );
        final newChallenge = await repository.requestBindingCode(
          method: AuthMethod.phone,
          account: '13900139000',
        );
        final result = await repository.bindCredential(
          method: AuthMethod.phone,
          account: '13900139000',
          verificationId: newChallenge.verificationId,
          verificationCode: '654321',
          sudoToken: sudoToken,
        );

        expect(result.user.phoneMasked, '139****9000');
        expect(paths, [
          '/auth/v1/user/me',
          '/auth/v1/verification',
          '/auth/v1/verification/verify',
          '/auth/v1/user/sudo',
          '/auth/v1/verification',
          '/auth/v1/verification/verify',
          '/auth/v1/user/contact',
          '/auth/v1/user/me',
        ]);
      },
    );

    test(
      'deletes CloudBase account data through the guarded function',
      () async {
        final store = MemorySessionStore();
        await store.write(_activeSession());
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: store,
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/v1/functions/social-api');
            expect(request.headers['authorization'], 'Bearer active-access');
            expect(jsonDecode(request.body), {
              'action': 'deleteAccount',
              'sudo_token': 'recent-sudo-token',
            });
            return _json({
              'success': true,
              'data': {'deleted': true},
            });
          }),
        );

        await repository.deleteAccount(sudoToken: 'recent-sudo-token');

        expect(store.session, isNull);
        expect(store.rememberedSession, isNull);
        expect(store.profiles, isEmpty);
      },
    );

    test(
      'resets password once without a false post-reset 405 failure',
      () async {
        final store = MemorySessionStore();
        await store.write(_activeSession());
        final paths = <String>[];
        final repository = CloudBaseAuthRepository(
          environmentId: 'music-env',
          sessionStore: store,
          client: MockClient((request) async {
            paths.add(request.url.path);
            final body = jsonDecode(request.body) as Map<String, Object?>;
            return switch (request.url.path) {
              '/auth/v1/verification' => () {
                expect(body['target'], 'USER');
                expect(body['email'], 'listener@example.com');
                return _json({
                  'verification_id': 'reset-code',
                  'expires_in': 600,
                  'is_user': true,
                });
              }(),
              '/auth/v1/verification/verify' => _json({
                'verification_token': 'one-use-reset-token',
              }),
              '/auth/v1/reset' => () {
                expect(body['email'], 'listener@example.com');
                expect(body['new_password'], 'lowercaseonly');
                expect(body['verification_token'], 'one-use-reset-token');
                return _json({});
              }(),
              _ => throw StateError('Unexpected path: ${request.url.path}'),
            };
          }),
        );

        final challenge = await repository.requestPasswordResetCode(
          method: AuthMethod.email,
          account: 'Listener@Example.com',
        );
        final proof = await repository.verifyPasswordResetCode(
          method: AuthMethod.email,
          account: 'Listener@Example.com',
          verificationId: challenge.verificationId,
          verificationCode: '123456',
        );
        await repository.resetPassword(
          proof: proof,
          newPassword: 'lowercaseonly',
        );

        expect(store.session, isNull);
        expect(paths, [
          '/auth/v1/verification',
          '/auth/v1/verification/verify',
          '/auth/v1/reset',
        ]);
        await expectLater(
          repository.resetPassword(proof: proof, newPassword: 'lowercaseonly'),
          throwsA(isA<AuthRequestException>()),
        );
        expect(paths.length, 3);
      },
    );

    test('translates an English method error into Chinese', () async {
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: MemorySessionStore(),
        client: MockClient((request) async {
          return _json({
            'error': 'unimplemented',
            'error_description': 'Method Not Allowed',
          }, 501);
        }),
      );

      await expectLater(
        repository.requestPasswordResetCode(
          method: AuthMethod.email,
          account: 'listener@example.com',
        ),
        throwsA(
          isA<AuthRequestException>().having(
            (error) => error.message,
            'message',
            '当前账号服务暂不支持此操作，请稍后重试',
          ),
        ),
      );
    });

    test('does not reveal whether a recovery account exists', () async {
      final repository = CloudBaseAuthRepository(
        environmentId: 'music-env',
        sessionStore: MemorySessionStore(),
        client: MockClient((request) async {
          return _json({
            'error': 'user_not_found',
            'error_description': 'User does not exist',
          }, 404);
        }),
      );

      final challenge = await repository.requestPasswordResetCode(
        method: AuthMethod.phone,
        account: '13800138000',
      );

      expect(challenge.maskedTarget, isEmpty);
      await expectLater(
        repository.verifyPasswordResetCode(
          method: AuthMethod.phone,
          account: '13800138000',
          verificationId: challenge.verificationId,
          verificationCode: '123456',
        ),
        throwsA(
          isA<AuthRequestException>().having(
            (error) => error.message,
            'message',
            '验证码无效或已过期，请重新获取',
          ),
        ),
      );
    });
  });
}

AuthSession _activeSession() {
  return AuthSession(
    user: const AuthUser(
      uid: 'cloud-user-1',
      nickname: 'listener',
      emailMasked: 'l***@example.com',
    ),
    accessToken: 'active-access',
    refreshToken: 'active-refresh',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
}

http.Response _json(Map<String, Object?> payload, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(payload),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

http.Response _jsonList(List<Object?> payload, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(payload),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

class MemorySessionStore extends SessionStore {
  AuthSession? session;
  AuthSession? rememberedSession;
  final Map<String, AuthUser> profiles = {};
  int sessionWriteCount = 0;
  int profileWriteCount = 0;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession session) async {
    sessionWriteCount += 1;
    this.session = session;
    rememberedSession = session;
  }

  @override
  Future<void> clear() async {
    session = null;
  }

  @override
  Future<AuthSession?> readRemembered() async => rememberedSession;

  @override
  Future<void> remember(AuthSession session) async {
    rememberedSession = session;
  }

  @override
  Future<void> restoreRememberedAsActive() async {
    session = rememberedSession;
  }

  @override
  Future<void> forgetRemembered() async {
    rememberedSession = null;
  }

  @override
  Future<void> clearAll() async {
    session = null;
    rememberedSession = null;
  }

  @override
  Future<AuthUser?> readProfile(String uid) async => profiles[uid];

  @override
  Future<void> writeProfile(AuthUser user) async {
    profileWriteCount += 1;
    profiles[user.uid] = user;
  }

  @override
  Future<void> deleteProfile(String uid) async {
    profiles.remove(uid);
  }
}

class BlockingSessionStore extends MemorySessionStore {
  final sessionWriteStarted = Completer<void>();
  final profileWriteStarted = Completer<void>();
  final releaseWrites = Completer<void>();

  @override
  Future<void> write(AuthSession session) async {
    sessionWriteStarted.complete();
    await releaseWrites.future;
    await super.write(session);
  }

  @override
  Future<void> writeProfile(AuthUser user) async {
    profileWriteStarted.complete();
    await releaseWrites.future;
    await super.writeProfile(user);
  }
}
