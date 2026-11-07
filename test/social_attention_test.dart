import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/social_notification_bridge.dart';
import 'package:mesting_music/features/social/data/social_repository.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/domain/track_share.dart';
import 'package:mesting_music/features/social/presentation/social_attention_coordinator.dart';
import 'package:mesting_music/features/social/social_attention.dart';
import 'package:mesting_music/features/social/social_providers.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('foreground social attention polling stays responsive', () {
    expect(socialAttentionPollInterval, const Duration(minutes: 10));
    expect(socialAttentionMinimumRefreshGap, const Duration(minutes: 2));
  });

  const me = 'me';
  const firstFollower = SocialUser(uid: 'first', nickname: '初始听友');
  const newFollower = SocialUser(uid: 'new', nickname: '新听友');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'social attention baselines history then notifies only new follow and message',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final repository = _AttentionRepository(
        followers: const [firstFollower],
        conversations: [_conversation('first-message')],
        summary: const SocialSummary(unreadCount: 1),
      );
      final bridge = _NotificationBridge();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          socialRepositoryProvider.overrideWithValue(repository),
          socialNotificationBridgeProvider.overrideWithValue(bridge),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        socialAttentionControllerProvider.notifier,
      );

      await controller.refreshFor(
        me,
        postSystemNotifications: true,
        force: true,
      );
      expect(
        container.read(socialAttentionControllerProvider).messageUnreadCount,
        1,
      );
      expect(
        container.read(socialAttentionControllerProvider).followerUnreadCount,
        0,
      );
      expect(bridge.notifications, isEmpty, reason: '历史数据只建立去重基线');

      repository
        ..followers = const [firstFollower, newFollower]
        ..conversations = [_conversation('new-message')]
        ..summaryData = const SocialSummary(unreadCount: 2);
      await controller.refreshFor(
        me,
        postSystemNotifications: true,
        force: true,
      );

      final attention = container.read(socialAttentionControllerProvider);
      expect(attention.messageUnreadCount, 2);
      expect(attention.followerUnreadCount, 1);
      expect(attention.unreadCount, 3);
      expect(bridge.notifications, hasLength(2));
      expect(
        bridge.notifications.any(
          (item) => item['title'] == '新的关注' && item['body'] == '新听友 关注了你',
        ),
        isTrue,
      );
      expect(
        bridge.notifications.any(
          (item) =>
              item['title'] == '好友 发来新消息' &&
              item['body'] == '[分享歌曲] 心动收藏 · Mesting',
        ),
        isTrue,
      );

      await controller.refreshFor(
        me,
        postSystemNotifications: true,
        force: true,
      );
      expect(bridge.notifications, hasLength(2), reason: '同一事件不能重复推送');

      await controller.markFollowersSeen(me);
      expect(
        container.read(socialAttentionControllerProvider).followerUnreadCount,
        0,
      );
    },
  );

  test('social notification preview identifies together invites and media', () {
    expect(
      socialMessageNotificationPreview(
        _message(
          'together',
          'mesting-together://v1?invitation=i1&session=s1&title=%E5%BF%83%E5%8A%A8',
        ),
      ),
      contains('[一起听]'),
    );
    expect(
      socialMessageNotificationPreview(
        SocialMessage(
          id: 'image',
          senderUid: 'friend',
          receiverUid: me,
          kind: SocialMessageKind.image,
          sentAt: DateTime(2026),
        ),
      ),
      '[图片]',
    );
    expect(socialAttentionUnreadLabel(120), '99+');
  });
}

SocialConversation _conversation(String id) => SocialConversation(
  peer: const SocialUser(uid: 'friend', nickname: '好友'),
  lastMessage: _message(id, encodeTrackShareMessage(_sharedTrack)),
  updatedAt: DateTime(2026, 7, 28),
  unreadCount: 1,
);

final _sharedTrack = Track(
  id: 'heart',
  title: '心动收藏',
  artist: 'Mesting',
  album: 'Mesting Music',
  duration: const Duration(minutes: 3),
  audioAsset: 'https://example.com/heart.mp3',
  coverAsset: 'https://example.com/heart.jpg',
  lyricsAsset: '',
);

SocialMessage _message(String id, String text) => SocialMessage(
  id: id,
  senderUid: 'friend',
  receiverUid: 'me',
  kind: SocialMessageKind.text,
  text: text,
  sentAt: DateTime(2026, 7, 28),
);

class _NotificationBridge extends SocialNotificationBridge {
  final notifications = <Map<String, Object>>[];

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
  }) async {
    notifications.add({'id': id, 'title': title, 'body': body});
    return true;
  }
}

class _AttentionRepository implements SocialRepository {
  _AttentionRepository({
    required this.followers,
    required this.conversations,
    required SocialSummary summary,
  }) : summaryData = summary;

  List<SocialUser> followers;
  List<SocialConversation> conversations;
  SocialSummary summaryData;

  @override
  Future<List<SocialUser>> listConnections(SocialConnectionKind kind) async =>
      kind == SocialConnectionKind.followers ? followers : const [];

  @override
  Future<List<SocialConversation>> listConversations() async => conversations;

  @override
  Future<SocialSummary> summary() async => summaryData;

  @override
  Future<SocialUser> getUser(String uid) => throw UnimplementedError();

  @override
  Future<SocialStatus> getStatus() => throw UnimplementedError();

  @override
  Future<List<SocialMessage>> listMessages(String uid) =>
      throw UnimplementedError();

  @override
  Future<SocialMessage> recallMessage(String uid, String messageId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMessage(String uid, String messageId) =>
      throw UnimplementedError();

  @override
  Future<void> markRead(String uid) => throw UnimplementedError();

  @override
  Future<void> removeFollower(String uid) => throw UnimplementedError();

  @override
  Future<List<SocialUser>> searchUsers(String query) =>
      throw UnimplementedError();

  @override
  Future<SocialMessage> sendMessage(
    String uid, {
    required SocialMessageKind kind,
    String text = '',
    String? mediaUrl,
    String? thumbnailUrl,
  }) => throw UnimplementedError();

  @override
  Future<SocialUser> setFollowing(String uid, {required bool following}) =>
      throw UnimplementedError();

  @override
  Future<void> setBlocked(String uid, {required bool blocked}) =>
      throw UnimplementedError();

  @override
  Future<SocialUser> setRemark(String uid, String remark) =>
      throw UnimplementedError();

  @override
  Future<SocialStatus> setStatus(SocialStatus status) =>
      throw UnimplementedError();

  @override
  Future<SocialUser> updateProfileDetails({
    required int? age,
    required String zodiac,
  }) => throw UnimplementedError();

  @override
  Future<SocialUpload> uploadMedia({
    required String path,
    required SocialMessageKind kind,
  }) => throw UnimplementedError();
}
