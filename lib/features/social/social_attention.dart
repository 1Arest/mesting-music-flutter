import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/app_preferences.dart';
import '../../core/platform/social_notification_bridge.dart';
import 'domain/listen_together.dart';
import 'domain/social_models.dart';
import 'domain/track_share.dart';
import 'social_providers.dart';

const _knownFollowersPrefix = 'social_attention_known_followers_v1_';
const _pendingFollowersPrefix = 'social_attention_pending_followers_v1_';
const _knownMessagesPrefix = 'social_attention_known_messages_v1_';

String _key(String prefix, String uid) => '$prefix${uid.trim()}';

class SocialAttention {
  const SocialAttention({
    this.messageUnreadCount = 0,
    this.followerUnreadCount = 0,
  });

  final int messageUnreadCount;
  final int followerUnreadCount;

  int get unreadCount => messageUnreadCount + followerUnreadCount;
  bool get hasUnread => unreadCount > 0;

  SocialAttention copyWith({
    int? messageUnreadCount,
    int? followerUnreadCount,
  }) => SocialAttention(
    messageUnreadCount: messageUnreadCount ?? this.messageUnreadCount,
    followerUnreadCount: followerUnreadCount ?? this.followerUnreadCount,
  );
}

String socialAttentionUnreadLabel(int count) => count > 99 ? '99+' : '$count';

String socialMessageNotificationPreview(SocialMessage? message) {
  if (message == null) return '给你发来了一条消息';
  return switch (message.kind) {
    SocialMessageKind.text => _textNotificationPreview(message.text),
    SocialMessageKind.emoji => message.text,
    SocialMessageKind.image => '[图片]',
    SocialMessageKind.video => '[视频]',
    SocialMessageKind.voice => '[语音]',
  };
}

String _textNotificationPreview(String text) {
  final together = decodeListenTogetherInvite(text);
  if (together != null) return '[一起听] 邀请你一起听 ${together.trackTitle}';
  final track = decodeTrackShareMessage(text);
  if (track != null) return '[分享歌曲] ${track.title} · ${track.artist}';
  return text.trim().isEmpty ? '给你发来了一条消息' : text.trim();
}

final socialNotificationBridgeProvider = Provider<SocialNotificationBridge>(
  (ref) => SocialNotificationBridge(),
);

final socialAttentionControllerProvider =
    NotifierProvider<SocialAttentionController, SocialAttention>(
      SocialAttentionController.new,
    );

class SocialAttentionController extends Notifier<SocialAttention> {
  static const _refreshCooldown = Duration(seconds: 30);
  Future<void>? _refreshInFlight;
  DateTime? _lastRefreshAt;
  String? _lastRefreshUid;
  bool _lastRefreshPostedNotifications = false;

  @override
  SocialAttention build() => const SocialAttention();

  Future<void> refreshFor(
    String uid, {
    required bool postSystemNotifications,
    bool force = false,
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      _lastRefreshAt = null;
      _lastRefreshUid = null;
      _lastRefreshPostedNotifications = false;
      state = const SocialAttention();
      return;
    }

    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastRefreshUid == normalizedUid &&
        _lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _refreshCooldown &&
        (!postSystemNotifications || _lastRefreshPostedNotifications)) {
      return;
    }
    final refresh = _refresh(
      normalizedUid,
      postSystemNotifications: postSystemNotifications,
    );
    _refreshInFlight = refresh;
    _lastRefreshUid = normalizedUid;
    _lastRefreshAt = now;
    _lastRefreshPostedNotifications = postSystemNotifications;
    try {
      await refresh;
    } finally {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    }
  }

  Future<void> _refresh(
    String normalizedUid, {
    required bool postSystemNotifications,
  }) async {
    final repository = ref.read(socialRepositoryProvider);
    final preferences = ref.read(sharedPreferencesProvider);
    final results = await Future.wait<Object>([
      repository.summary(),
      repository.listConnections(SocialConnectionKind.followers),
      repository.listConversations(),
    ]);
    final summary = results[0] as SocialSummary;
    final followers = results[1] as List<SocialUser>;
    final conversations = results[2] as List<SocialConversation>;

    final newFollowers = await _refreshFollowers(
      preferences,
      normalizedUid,
      followers,
    );
    final newMessages = await _refreshMessages(
      preferences,
      normalizedUid,
      conversations,
    );
    final pendingFollowers = _readSet(
      preferences,
      _key(_pendingFollowersPrefix, normalizedUid),
    );
    state = SocialAttention(
      messageUnreadCount: summary.unreadCount,
      followerUnreadCount: pendingFollowers.length,
    );

    if (!postSystemNotifications) return;
    final bridge = ref.read(socialNotificationBridgeProvider);
    for (final follower in newFollowers) {
      await bridge.show(
        id: _notificationId('follow:${follower.uid}'),
        title: '新的关注',
        body: '${follower.displayName} 关注了你',
      );
    }
    for (final conversation in newMessages) {
      await bridge.show(
        id: _notificationId(
          'message:${conversation.lastMessage?.id ?? conversation.peer.uid}',
        ),
        title: '${conversation.peer.displayName} 发来新消息',
        body: socialMessageNotificationPreview(conversation.lastMessage),
      );
    }
  }

  Future<void> markFollowersSeen(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return;
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.remove(_key(_pendingFollowersPrefix, normalizedUid));
    state = state.copyWith(followerUnreadCount: 0);
  }

  void clear() {
    _lastRefreshAt = null;
    _lastRefreshUid = null;
    _lastRefreshPostedNotifications = false;
    state = const SocialAttention();
  }

  Future<List<SocialUser>> _refreshFollowers(
    SharedPreferences preferences,
    String uid,
    List<SocialUser> followers,
  ) async {
    final knownKey = _key(_knownFollowersPrefix, uid);
    final pendingKey = _key(_pendingFollowersPrefix, uid);
    final current = followers.map((user) => user.uid).toSet();
    final initialized = preferences.containsKey(knownKey);
    final known = _readSet(preferences, knownKey);
    final added = initialized
        ? followers.where((user) => !known.contains(user.uid)).toList()
        : const <SocialUser>[];
    final pending = _readSet(preferences, pendingKey)
      ..removeWhere((id) => !current.contains(id))
      ..addAll(added.map((user) => user.uid));
    await Future.wait([
      _writeSet(preferences, knownKey, current),
      _writeSet(preferences, pendingKey, pending),
    ]);
    return added;
  }

  Future<List<SocialConversation>> _refreshMessages(
    SharedPreferences preferences,
    String uid,
    List<SocialConversation> conversations,
  ) async {
    final key = _key(_knownMessagesPrefix, uid);
    final known = _readSet(preferences, key);
    final initialized = preferences.containsKey(key);
    final currentIds = conversations
        .map((conversation) => conversation.lastMessage?.id ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final added = initialized
        ? conversations
              .where(
                (conversation) =>
                    conversation.unreadCount > 0 &&
                    conversation.lastMessage != null &&
                    !known.contains(conversation.lastMessage!.id),
              )
              .toList(growable: false)
        : const <SocialConversation>[];
    final next = <String>{...known, ...currentIds}.toList()
      ..sort((a, b) => b.compareTo(a));
    if (next.length > 120) next.removeRange(120, next.length);
    await _writeSet(preferences, key, next.toSet());
    return added;
  }
}

Set<String> _readSet(SharedPreferences preferences, String key) {
  final raw = preferences.getString(key);
  if (raw == null || raw.isEmpty) return <String>{};
  try {
    final value = jsonDecode(raw);
    if (value is! List) return <String>{};
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  } on Object {
    return <String>{};
  }
}

Future<void> _writeSet(
  SharedPreferences preferences,
  String key,
  Set<String> values,
) => preferences.setString(key, jsonEncode(values.toList()..sort()));

int _notificationId(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return 320000 + (hash % 900000);
}
