import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/features/social/data/social_repository.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/presentation/public_profile_page.dart';
import 'package:mesting_music/features/social/presentation/social_connections_page.dart';
import 'package:mesting_music/features/social/presentation/social_messages_page.dart';
import 'package:mesting_music/features/social/presentation/social_widgets.dart';
import 'package:mesting_music/features/social/social_providers.dart';
import 'package:mesting_music/features/social/social_attention.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';

void main() {
  const friend = SocialUser(
    uid: 'friend',
    nickname: '林间电台',
    bio: '把夜晚和爵士装进口袋。',
    age: 24,
    zodiac: '天秤座',
    followingCount: 38,
    followerCount: 126,
    isFollowing: true,
    followsMe: true,
    status: SocialStatus(emoji: '🌷', text: '等春天'),
  );

  testWidgets('friend profile menu contains requested actions and no report', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(
            _FakeSocialRepository(friend),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PublicProfilePage(uid: 'friend')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('等春天'), findsOneWidget);
    expect(find.text('24 岁'), findsOneWidget);
    expect(find.text('天秤座'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();

    expect(find.text('设置备注名'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('移除粉丝'), findsOneWidget);
    expect(find.text('加入黑名单'), findsOneWidget);
    expect(find.text('举报'), findsNothing);
  });

  testWidgets('friend profile hides optional details when they are unset', (
    tester,
  ) async {
    const withoutDetails = SocialUser(
      uid: 'friend',
      nickname: 'Friend',
      bio: 'Bio',
      isFollowing: true,
      followsMe: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(
            _FakeSocialRepository(withoutDetails),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PublicProfilePage(uid: 'friend')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('public-profile-age')), findsNothing);
    expect(find.byKey(const ValueKey('public-profile-zodiac')), findsNothing);
  });

  testWidgets('followers row menu only offers follower removal', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(
            _FakeSocialRepository(friend),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SocialConnectionsPage(initialTab: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('粉丝管理'));
    await tester.pumpAndSettle();

    expect(find.text('移除粉丝'), findsOneWidget);
    expect(find.text('加入黑名单'), findsNothing);
    expect(find.text('举报'), findsNothing);
  });

  testWidgets('friends page only contains following and followers tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(
            _FakeSocialRepository(friend),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SocialConnectionsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关注'), findsOneWidget);
    expect(find.text('粉丝'), findsOneWidget);
    expect(find.text('推荐'), findsNothing);
  });

  testWidgets('social avatars use the persistent remote image cache', (
    tester,
  ) async {
    const userWithAvatar = SocialUser(
      uid: 'friend-with-avatar',
      nickname: '缓存好友',
      avatarUrl: 'https://cdn.example/avatars/friend-with-avatar.jpg',
    );
    await tester.pumpWidget(
      const MaterialApp(home: SocialAvatar(user: userWithAvatar)),
    );

    final image = tester.widget<ArtworkImage>(find.byType(ArtworkImage));
    expect(image.persistentNetworkCacheKey, 'social-avatar-friend-with-avatar');
  });

  testWidgets(
    'friends page identifies unread messages and opens them directly',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/social',
        routes: [
          GoRoute(
            path: '/social',
            builder: (context, state) =>
                const Scaffold(body: SocialConnectionsPage()),
          ),
          GoRoute(
            path: '/social/messages',
            builder: (context, state) =>
                const Scaffold(body: Text('messages-destination')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialRepositoryProvider.overrideWithValue(
              _FakeSocialRepository(friend),
            ),
            socialAttentionControllerProvider.overrideWith(
              _UnreadAttentionController.new,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('social-messages-unread-badge')),
        findsOneWidget,
      );
      expect(find.text('你有 3 条未读私信，点击查看消息来源'), findsOneWidget);

      await tester.tap(find.text('你有 3 条未读私信，点击查看消息来源'));
      await tester.pumpAndSettle();

      expect(find.text('messages-destination'), findsOneWidget);
    },
  );

  testWidgets('follower removal sheet stays above the persistent player', (
    tester,
  ) async {
    final repository = _RecordingSocialRepository(friend);
    var playerTapCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) =>
                          const SocialConnectionsPage(initialTab: 1),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 150,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => playerTapCount += 1,
                    child: const ColoredBox(
                      color: Colors.black,
                      child: Center(child: Text('模拟底部播放器')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('粉丝管理'));
    await tester.pumpAndSettle();
    expect(find.text('移除粉丝'), findsOneWidget);
    await tester.tap(find.text('移除粉丝'));
    await tester.pumpAndSettle();

    expect(repository.removedUid, friend.uid);
    expect(playerTapCount, 0);
  });

  testWidgets('friends page leaves loading when the backend never responds', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(_NeverSocialRepository()),
          socialReadTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SocialConnectionsPage())),
      ),
    );
    await tester.pump();

    expect(find.text('正在加载...'), findsNothing);
    expect(
      find.byKey(const ValueKey('social-loading-animation')),
      findsWidgets,
    );
    expect(find.bySemanticsLabel('正在加载关注与粉丝列表'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 21));
    await tester.pump();

    expect(find.textContaining('好友服务响应较慢'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('正在加载...'), findsNothing);
  });

  testWidgets('messages page leaves loading when the backend never responds', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(_NeverSocialRepository()),
          socialReadTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SocialMessagesPage())),
      ),
    );
    await tester.pump();

    expect(find.text('正在加载...'), findsNothing);
    expect(
      find.byKey(const ValueKey('social-loading-animation')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('正在加载会话与未读消息'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 21));
    await tester.pump();

    expect(find.textContaining('好友服务响应较慢'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('正在加载...'), findsNothing);
  });

  testWidgets('friend profile uses the shared text-free curve loader', (
    tester,
  ) async {
    final repository = _PendingProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(body: PublicProfilePage(uid: 'friend')),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('public-profile-loading-animation')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('正在加载好友主页'), findsOneWidget);
    expect(find.textContaining('正在加载'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    repository.user.complete(friend);
    await tester.pumpAndSettle();
  });

  testWidgets('unread count is capped at 99+ without moving the time', (
    tester,
  ) async {
    Widget messagesApp(int unreadCount) {
      return ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(
            _MessagesSocialRepository(
              SocialConversation(
                peer: friend,
                updatedAt: DateTime.now(),
                unreadCount: unreadCount,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SocialMessagesPage())),
      );
    }

    await tester.pumpWidget(messagesApp(111));
    await tester.pumpAndSettle();

    final timeFinder = find.byKey(
      const ValueKey('social-conversation-time-friend'),
    );
    final badgeFinder = find.byKey(
      const ValueKey('social-conversation-unread-friend'),
    );
    final timeLeftWithBadge = tester.getTopLeft(timeFinder).dx;
    expect(find.text('99+'), findsOneWidget);
    expect(tester.getSize(badgeFinder), const Size.square(22));
    expect(
      tester.getTopLeft(badgeFinder).dy,
      greaterThan(tester.getTopLeft(timeFinder).dy),
    );

    await tester.pumpWidget(messagesApp(1));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(tester.getSize(badgeFinder), const Size.square(22));

    await tester.pumpWidget(messagesApp(0));
    await tester.pumpAndSettle();

    expect(find.text('99+'), findsNothing);
    expect(tester.getTopLeft(timeFinder).dx, closeTo(timeLeftWithBadge, .01));
  });

  testWidgets('voice messages use a clear conversation preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(
            _MessagesSocialRepository(
              SocialConversation(
                peer: friend,
                updatedAt: DateTime.now(),
                lastMessage: SocialMessage(
                  id: 'voice',
                  senderUid: 'friend',
                  receiverUid: 'me',
                  kind: SocialMessageKind.voice,
                  text: '3200',
                  mediaUrl: 'cloud://voice/message.m4a',
                  sentAt: DateTime.now(),
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SocialMessagesPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('[语音]'), findsOneWidget);
  });
}

class _FakeSocialRepository extends Fake implements SocialRepository {
  _FakeSocialRepository(this.user);

  final SocialUser user;

  @override
  Future<SocialUser> getUser(String uid) async => user;

  @override
  Future<List<SocialUser>> listConnections(SocialConnectionKind kind) async {
    return kind == SocialConnectionKind.recommended ? const [] : [user];
  }
}

class _RecordingSocialRepository extends _FakeSocialRepository {
  _RecordingSocialRepository(super.user);

  String? removedUid;

  @override
  Future<void> removeFollower(String uid) async {
    removedUid = uid;
  }
}

class _UnreadAttentionController extends SocialAttentionController {
  @override
  SocialAttention build() => const SocialAttention(messageUnreadCount: 3);
}

class _NeverSocialRepository extends Fake implements SocialRepository {
  @override
  Future<List<SocialUser>> listConnections(SocialConnectionKind kind) {
    return Completer<List<SocialUser>>().future;
  }

  @override
  Future<List<SocialConversation>> listConversations() {
    return Completer<List<SocialConversation>>().future;
  }
}

class _PendingProfileRepository extends Fake implements SocialRepository {
  final Completer<SocialUser> user = Completer<SocialUser>();

  @override
  Future<SocialUser> getUser(String uid) => user.future;
}

class _MessagesSocialRepository extends Fake implements SocialRepository {
  _MessagesSocialRepository(this.conversation);

  final SocialConversation conversation;

  @override
  Future<List<SocialConversation>> listConversations() async => [conversation];
}
