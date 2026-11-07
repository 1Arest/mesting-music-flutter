import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/social/data/cloudbase_social_repository.dart';
import 'package:mesting_music/features/social/data/local_preview_social_repository.dart';
import 'package:mesting_music/features/social/data/social_repository.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/social_providers.dart';

void main() {
  const currentUser = AuthUser(uid: 'me', nickname: 'Mesting');

  group('LocalPreviewSocialRepository', () {
    late LocalPreviewSocialRepository repository;

    setUp(() {
      repository = LocalPreviewSocialRepository(
        userProvider: () => currentUser,
      );
    });

    test('mutual followers can exchange all supported message kinds', () async {
      final peer = await repository.getUser('preview-lin');
      expect(peer.isFriend, isTrue);

      for (final kind in SocialMessageKind.values) {
        final message = await repository.sendMessage(
          peer.uid,
          kind: kind,
          text:
              kind == SocialMessageKind.text || kind == SocialMessageKind.emoji
              ? '🎧'
              : '',
          mediaUrl:
              kind == SocialMessageKind.image ||
                  kind == SocialMessageKind.video ||
                  kind == SocialMessageKind.voice
              ? 'file:///preview/media'
              : null,
        );
        expect(message.kind, kind);
      }

      final messages = await repository.listMessages(peer.uid);
      expect(messages.length, 5);
    });

    test('one-way following is not enough to chat', () async {
      final peer = await repository.getUser('preview-mint');
      expect(peer.isFollowing, isTrue);
      expect(peer.followsMe, isFalse);

      await expectLater(
        repository.sendMessage(
          peer.uid,
          kind: SocialMessageKind.text,
          text: '你好',
        ),
        throwsA(
          isA<SocialRequestException>().having(
            (error) => error.message,
            'message',
            contains('互相关注'),
          ),
        ),
      );
    });

    test(
      'recall replaces a sent message and deletion only hides it locally',
      () async {
        const peerUid = 'preview-lin';
        final sent = await repository.sendMessage(
          peerUid,
          kind: SocialMessageKind.voice,
          text: '2400',
          mediaUrl: 'file:///preview/voice.m4a',
        );

        final recalled = await repository.recallMessage(peerUid, sent.id);
        expect(recalled.recalled, isTrue);
        expect(recalled.mediaUrl, isNull);
        expect(
          (await repository.listMessages(
            peerUid,
          )).singleWhere((message) => message.id == sent.id).recalled,
          isTrue,
        );

        await repository.deleteMessage(peerUid, sent.id);
        expect(
          (await repository.listMessages(
            peerUid,
          )).any((message) => message.id == sent.id),
          isFalse,
        );
      },
    );

    test(
      'remove follower and blacklist update both relationship directions',
      () async {
        await repository.removeFollower('preview-noon');
        expect((await repository.getUser('preview-noon')).followsMe, isFalse);

        await repository.setBlocked('preview-lin', blocked: true);
        final blocked = await repository.getUser('preview-lin');
        expect(blocked.isBlocked, isTrue);
        expect(blocked.isFollowing, isFalse);
        expect(blocked.followsMe, isFalse);
      },
    );

    test(
      'remark changes display name without changing public nickname',
      () async {
        final updated = await repository.setRemark('preview-lin', '小林');
        expect(updated.displayName, '小林');
        expect(updated.nickname, '林间电台');
      },
    );
    test('profile details can explicitly clear a restored age', () async {
      final repository = LocalPreviewSocialRepository(
        userProvider: () =>
            const AuthUser(uid: 'me', nickname: 'Mesting', age: 35),
      );

      final updated = await repository.updateProfileDetails(
        age: null,
        zodiac: '',
      );

      expect(updated.age, isNull);
      expect(updated.zodiac, isEmpty);
    });
  });

  group('CloudBaseSocialRepository', () {
    test(
      'retries one TLS handshake failure before calling social-api',
      () async {
        var requestCount = 0;
        final repository = CloudBaseSocialRepository(
          environmentId: 'test-env',
          sessionProvider: () => AuthSession(
            user: currentUser,
            accessToken: 'token',
            refreshToken: 'refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          client: MockClient((_) async {
            requestCount += 1;
            if (requestCount == 1) {
              throw const HandshakeException(
                'Connection terminated during handshake',
              );
            }
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'conversations': <Object?>[]},
              }),
              200,
            );
          }),
        );

        expect(await repository.listConversations(), isEmpty);
        expect(requestCount, 2);
      },
    );

    test('converts repeated TLS handshake failures to Chinese', () async {
      var requestCount = 0;
      final repository = CloudBaseSocialRepository(
        environmentId: 'test-env',
        sessionProvider: () => AuthSession(
          user: currentUser,
          accessToken: 'token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        client: MockClient((_) async {
          requestCount += 1;
          throw const HandshakeException(
            'Connection terminated during handshake',
          );
        }),
      );

      await expectLater(
        repository.listConversations(),
        throwsA(
          isA<SocialRequestException>().having(
            (error) => error.message,
            'message',
            '安全连接建立失败，请切换网络后重试',
          ),
        ),
      );
      expect(requestCount, 2);
    });

    test('updates status through the authenticated cloud function', () async {
      late Map<String, Object?> requestBody;
      final repository = CloudBaseSocialRepository(
        environmentId: 'test-env',
        sessionProvider: () => AuthSession(
          user: currentUser,
          accessToken: 'token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'status': {'emoji': '🌷', 'text': '等春天'},
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final status = await repository.setStatus(
        const SocialStatus(emoji: '🌷', text: '等春天'),
      );

      expect(requestBody['action'], 'setStatus');
      expect(requestBody['emoji'], '🌷');
      expect(requestBody['text'], '等春天');
      expect(requestBody.containsKey('uid'), isFalse);
      expect(status.label, '🌷 等春天');
    });

    test('updates optional profile details through social-api', () async {
      late Map<String, Object?> requestBody;
      final repository = CloudBaseSocialRepository(
        environmentId: 'test-env',
        sessionProvider: () => AuthSession(
          user: currentUser,
          accessToken: 'token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'user': {
                  'uid': 'me',
                  'nickname': 'Mesting',
                  'age': 24,
                  'zodiac': '天秤座',
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final updated = await repository.updateProfileDetails(
        age: 24,
        zodiac: ' 天秤座 ',
      );

      expect(requestBody['action'], 'setProfileDetails');
      expect(requestBody['age'], 24);
      expect(requestBody['zodiac'], '天秤座');
      expect(requestBody.containsKey('uid'), isFalse);
      expect(updated.age, 24);
      expect(updated.zodiac, '天秤座');
    });

    test('uses bearer identity and never sends a caller uid', () async {
      late http.Request captured;
      final repository = CloudBaseSocialRepository(
        environmentId: 'test-env',
        sessionProvider: () => AuthSession(
          user: currentUser,
          accessToken: 'access-secret',
          refreshToken: 'refresh-secret',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'users': [
                  {
                    'uid': 'friend',
                    'nickname': '好友',
                    'is_following': false,
                    'follows_me': true,
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await repository.searchUsers('好友');
      final body = jsonDecode(captured.body) as Map<String, Object?>;

      expect(captured.url.path, '/v1/functions/social-api');
      expect(captured.url.queryParameters['webfn'], 'true');
      expect(captured.headers['authorization'], 'Bearer access-secret');
      expect(body['action'], 'searchUsers');
      expect(body['query'], '好友');
      expect(body.containsKey('caller_uid'), isFalse);
      expect(body.containsKey('uid'), isFalse);
      expect(result.single.followsMe, isTrue);
    });

    test('maps mutual-follow denial to a friendly message', () async {
      final repository = CloudBaseSocialRepository(
        environmentId: 'test-env',
        sessionProvider: () => AuthSession(
          user: currentUser,
          accessToken: 'token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': false,
              'code': 'not_mutual_follow',
              'message': 'server text',
            }),
            400,
          ),
        ),
      );

      await expectLater(
        repository.sendMessage(
          'friend',
          kind: SocialMessageKind.text,
          text: '你好',
        ),
        throwsA(
          isA<SocialRequestException>().having(
            (error) => error.message,
            'message',
            '双方互相关注后才能发送消息',
          ),
        ),
      );
    });

    test('a hanging cloud function request always reaches a timeout', () async {
      final repository = CloudBaseSocialRepository(
        environmentId: 'test-env',
        sessionProvider: () => AuthSession(
          user: currentUser,
          accessToken: 'token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        requestTimeout: const Duration(milliseconds: 20),
        client: MockClient((_) => Completer<http.Response>().future),
      );

      await expectLater(
        repository.listConversations(),
        throwsA(
          isA<SocialRequestException>().having(
            (error) => error.message,
            'message',
            contains('响应较慢'),
          ),
        ),
      );
    });

    test(
      'renews once and retries when the gateway rejects an access token',
      () async {
        var session = AuthSession(
          user: currentUser,
          accessToken: 'stale-access',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
        var requestCount = 0;
        var refreshCount = 0;
        final repository = CloudBaseSocialRepository(
          environmentId: 'test-env',
          sessionProvider: () => session,
          sessionRefresher: () async {
            refreshCount += 1;
            session = AuthSession(
              user: currentUser,
              accessToken: 'fresh-access',
              refreshToken: 'fresh-refresh',
              expiresAt: DateTime.now().add(const Duration(hours: 2)),
            );
            return session;
          },
          client: MockClient((request) async {
            requestCount += 1;
            if (requestCount == 1) {
              expect(request.headers['authorization'], 'Bearer stale-access');
              return http.Response(
                jsonEncode({'success': false, 'code': 'invalid_access_token'}),
                401,
              );
            }
            expect(request.headers['authorization'], 'Bearer fresh-access');
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'conversations': <Object?>[]},
              }),
              200,
            );
          }),
        );

        expect(await repository.listConversations(), isEmpty);
        expect(refreshCount, 1);
        expect(requestCount, 2);
      },
    );

    test(
      'gateway credential errors never expose English server text',
      () async {
        final repository = CloudBaseSocialRepository(
          environmentId: 'test-env',
          sessionProvider: () => AuthSession(
            user: currentUser,
            accessToken: 'token',
            refreshToken: 'refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'code': 'MISSING_CREDENTIALS',
                'message': 'Credentials missing',
              }),
              401,
            ),
          ),
        );

        await expectLater(
          repository.listConversations(),
          throwsA(
            isA<SocialRequestException>().having(
              (error) => error.message,
              'message',
              '登录状态已失效，请重新登录',
            ),
          ),
        );
      },
    );

    test(
      'resolves a legacy CloudBase media ID to a playable download URL',
      () async {
        var downloadInfoCalls = 0;
        final repository = CloudBaseSocialRepository(
          environmentId: 'test-env',
          sessionProvider: () => AuthSession(
            user: currentUser,
            accessToken: 'token',
            refreshToken: 'refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          client: MockClient((request) async {
            expect(request.url.path, '/v1/storages/get-objects-download-info');
            expect(request.headers['authorization'], 'Bearer token');
            expect(jsonDecode(request.body), [
              {'objectId': 'social-media/me/voice.m4a'},
            ]);
            downloadInfoCalls += 1;
            return http.Response(
              jsonEncode([
                {'downloadUrl': 'https://cdn.example/social-media/voice.m4a'},
              ]),
              200,
            );
          }),
        );

        const objectId = 'cloud://test-env.bucket/social-media/me/voice.m4a';
        expect(
          await repository.resolveMediaUrl(objectId),
          'https://cdn.example/social-media/voice.m4a',
        );
        expect(
          await repository.resolveMediaUrl(objectId),
          'https://cdn.example/social-media/voice.m4a',
        );
        expect(downloadInfoCalls, 1);
        expect(
          await repository.resolveMediaUrl(objectId, forceRefresh: true),
          'https://cdn.example/social-media/voice.m4a',
        );
        expect(downloadInfoCalls, 2);
      },
    );
  });

  group('social provider cache', () {
    test('keeps successful reads across a quick page re-entry', () async {
      final repository = _CountingSocialRepository();
      final container = ProviderContainer(
        overrides: [
          socialRepositoryProvider.overrideWithValue(repository),
          socialReadCacheTtlProvider.overrideWithValue(
            const Duration(minutes: 2),
          ),
        ],
      );
      addTearDown(container.dispose);

      final firstListener = container.listen(
        socialConversationsProvider,
        (_, _) {},
      );
      await container.read(socialConversationsProvider.future);
      firstListener.close();
      await Future<void>.delayed(Duration.zero);

      final secondListener = container.listen(
        socialConversationsProvider,
        (_, _) {},
      );
      await container.read(socialConversationsProvider.future);
      expect(repository.listConversationsCallCount, 1);

      container.invalidate(socialConversationsProvider);
      await container.read(socialConversationsProvider.future);
      expect(repository.listConversationsCallCount, 2);
      secondListener.close();
    });
  });
}

class _CountingSocialRepository implements SocialRepository {
  int listConversationsCallCount = 0;

  @override
  Future<List<SocialConversation>> listConversations() async {
    listConversationsCallCount += 1;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
