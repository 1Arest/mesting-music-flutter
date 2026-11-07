import 'dart:io';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/track.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/listen_together.dart';
import '../domain/social_models.dart';
import 'listen_together_repository.dart';
import 'social_repository.dart';

const _previewProfileFieldUnset = Object();

class LocalPreviewSocialRepository
    implements
        SocialRepository,
        ListenTogetherRepository,
        SocialMediaUrlResolver {
  LocalPreviewSocialRepository({
    required AuthUser? Function() userProvider,
    SharedPreferences? preferences,
  }) : _userProvider = userProvider,
       _preferences = preferences;

  final AuthUser? Function() _userProvider;
  final SharedPreferences? _preferences;

  final Map<String, SocialUser> _users = {
    'preview-lin': const SocialUser(
      uid: 'preview-lin',
      nickname: '林间电台',
      bio: '把夜晚和爵士装进口袋。',
      followingCount: 38,
      followerCount: 126,
      isFollowing: true,
      followsMe: true,
    ),
    'preview-mint': const SocialUser(
      uid: 'preview-mint',
      nickname: '薄荷汽水',
      bio: '独立摇滚、City Pop 和晴天。',
      followingCount: 64,
      followerCount: 89,
      isFollowing: true,
    ),
    'preview-noon': const SocialUser(
      uid: 'preview-noon',
      nickname: '午后留声机',
      bio: '最近在循环华语民谣。',
      followingCount: 17,
      followerCount: 53,
      followsMe: true,
    ),
    'preview-orbit': const SocialUser(
      uid: 'preview-orbit',
      nickname: '轨道外的星',
      bio: '电子、氛围与电影原声。',
      followingCount: 92,
      followerCount: 241,
    ),
  };
  final Map<String, List<SocialMessage>> _messages = {};
  final Map<String, Set<String>> _hiddenMessageIdsByUser = {};
  final Map<String, ListenTogetherTrackRecord> _togetherRecords = {};
  ListenTogetherSession? _togetherSession;
  SocialStatus _currentStatus = const SocialStatus.empty();
  String? _loadedStatusUid;

  @override
  Future<SocialSummary> summary() async {
    _requireUser();
    return SocialSummary(
      followingCount: _users.values.where((user) => user.isFollowing).length,
      followerCount: _users.values.where((user) => user.followsMe).length,
      unreadCount: 0,
    );
  }

  @override
  Future<SocialStatus> getStatus() async {
    final user = _requireUser();
    _loadStatus(user.uid);
    return _currentStatus;
  }

  @override
  Future<SocialStatus> setStatus(SocialStatus status) async {
    final user = _requireUser();
    _loadStatus(user.uid);
    if (status.text.trim().length > 24 || status.emoji.trim().length > 8) {
      throw const SocialRequestException('状态内容过长，请精简后重试');
    }
    _currentStatus = SocialStatus(
      emoji: status.emoji.trim(),
      text: status.text.trim(),
    );
    await _preferences?.setString(
      _statusKey(user.uid),
      jsonEncode(_currentStatus.toJson()),
    );
    return _currentStatus;
  }

  @override
  Future<SocialUser> updateProfileDetails({
    required int? age,
    required String zodiac,
  }) async {
    final current = _requireUser();
    if (age != null && (age < 1 || age > 120)) {
      throw const SocialRequestException('年龄需要在 1–120 岁之间');
    }
    final normalizedZodiac = zodiac.trim();
    if (normalizedZodiac.isNotEmpty &&
        !socialZodiacSigns.contains(normalizedZodiac)) {
      throw const SocialRequestException('星座资料无效，请重新选择');
    }
    return _socialUserFor(current, age: age, zodiac: normalizedZodiac);
  }

  void _loadStatus(String uid) {
    if (_loadedStatusUid == uid) return;
    _loadedStatusUid = uid;
    _currentStatus = const SocialStatus.empty();
    final raw = _preferences?.getString(_statusKey(uid));
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _currentStatus = SocialStatus.fromJson(
          Map<String, Object?>.from(decoded),
        );
      }
    } on Object {
      // Ignore a damaged preview value and keep the empty default.
    }
  }

  String _statusKey(String uid) => 'social_preview_status_$uid';

  @override
  Future<List<SocialUser>> searchUsers(String query) async {
    _requireUser();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    return _users.values
        .where(
          (user) =>
              !user.isBlocked &&
              ('${user.nickname} ${user.remark} ${user.bio}'.toLowerCase())
                  .contains(normalized),
        )
        .toList(growable: false);
  }

  @override
  Future<SocialUser> getUser(String uid) async {
    final current = _requireUser();
    if (uid == current.uid) return _socialUserFor(current);
    return _existing(uid);
  }

  SocialUser _socialUserFor(
    AuthUser user, {
    Object? age = _previewProfileFieldUnset,
    String? zodiac,
  }) {
    _loadStatus(user.uid);
    return SocialUser(
      uid: user.uid,
      nickname: user.nickname,
      bio: user.bio,
      age: identical(age, _previewProfileFieldUnset) ? user.age : age as int?,
      zodiac: zodiac ?? user.zodiac,
      avatarUrl: user.avatarUrl,
      status: _currentStatus,
    );
  }

  @override
  Future<List<SocialUser>> listConnections(SocialConnectionKind kind) async {
    _requireUser();
    return switch (kind) {
      SocialConnectionKind.following =>
        _users.values
            .where((user) => user.isFollowing && !user.isBlocked)
            .toList(growable: false),
      SocialConnectionKind.followers =>
        _users.values
            .where((user) => user.followsMe && !user.isBlocked)
            .toList(growable: false),
      SocialConnectionKind.recommended =>
        _users.values
            .where(
              (user) => !user.isFollowing && !user.followsMe && !user.isBlocked,
            )
            .toList(growable: false),
    };
  }

  @override
  Future<SocialUser> setFollowing(String uid, {required bool following}) async {
    _requireUser();
    final user = _existing(uid);
    if (user.isBlocked) {
      throw const SocialRequestException('已加入黑名单，无法关注该用户');
    }
    final updated = user.copyWith(
      isFollowing: following,
      followerCount: (user.followerCount + (following ? 1 : -1)).clamp(
        0,
        1 << 30,
      ),
    );
    _users[uid] = updated;
    return updated;
  }

  @override
  Future<SocialUser> setRemark(String uid, String remark) async {
    _requireUser();
    final updated = _existing(uid).copyWith(remark: remark.trim());
    _users[uid] = updated;
    return updated;
  }

  @override
  Future<void> removeFollower(String uid) async {
    _requireUser();
    final user = _existing(uid);
    _users[uid] = user.copyWith(followsMe: false);
  }

  @override
  Future<void> setBlocked(String uid, {required bool blocked}) async {
    _requireUser();
    final user = _existing(uid);
    _users[uid] = user.copyWith(
      isBlocked: blocked,
      isFollowing: blocked ? false : user.isFollowing,
      followsMe: blocked ? false : user.followsMe,
    );
  }

  @override
  Future<List<SocialConversation>> listConversations() async {
    final current = _requireUser();
    final hidden = _hiddenMessageIdsByUser[current.uid] ?? const <String>{};
    final conversations = <SocialConversation>[];
    for (final entry in _messages.entries) {
      final visible = entry.value
          .where((message) => !hidden.contains(message.id))
          .toList(growable: false);
      if (visible.isEmpty) continue;
      conversations.add(
        SocialConversation(
          peer: _existing(entry.key),
          lastMessage: visible.last,
          updatedAt: visible.last.sentAt,
        ),
      );
    }
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Future<List<SocialMessage>> listMessages(String uid) async {
    final current = _requireUser();
    final peer = _existing(uid);
    if (!peer.isFriend) {
      throw const SocialRequestException('双方互相关注后才能发送消息');
    }
    final allMessages = _messages.putIfAbsent(
      uid,
      () => [
        SocialMessage(
          id: 'welcome-$uid',
          senderUid: uid,
          receiverUid: current.uid,
          kind: SocialMessageKind.text,
          text: '嗨，最近有什么好歌推荐吗？',
          sentAt: DateTime.now().subtract(const Duration(minutes: 18)),
        ),
      ],
    );
    final hidden = _hiddenMessageIdsByUser[current.uid] ?? const <String>{};
    return List.unmodifiable(
      allMessages.where((message) => !hidden.contains(message.id)),
    );
  }

  @override
  Future<SocialMessage> sendMessage(
    String uid, {
    required SocialMessageKind kind,
    String text = '',
    String? mediaUrl,
    String? thumbnailUrl,
  }) async {
    final current = _requireUser();
    final peer = _existing(uid);
    if (!peer.isFriend) {
      throw const SocialRequestException('双方互相关注后才能发送消息');
    }
    if ((kind == SocialMessageKind.text || kind == SocialMessageKind.emoji) &&
        text.trim().isEmpty) {
      throw const SocialRequestException('消息内容不能为空');
    }
    if ((kind == SocialMessageKind.image ||
            kind == SocialMessageKind.video ||
            kind == SocialMessageKind.voice) &&
        (mediaUrl?.trim().isEmpty ?? true)) {
      throw const SocialRequestException('媒体地址无效');
    }
    final message = SocialMessage(
      id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
      senderUid: current.uid,
      receiverUid: uid,
      kind: kind,
      text: text.trim(),
      mediaUrl: mediaUrl,
      thumbnailUrl: thumbnailUrl,
      sentAt: DateTime.now(),
    );
    _messages.putIfAbsent(uid, () => []).add(message);
    return message;
  }

  @override
  Future<SocialMessage> recallMessage(String uid, String messageId) async {
    final current = _requireUser();
    _existing(uid);
    final messages = _messages[uid] ?? const <SocialMessage>[];
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index < 0) throw const SocialRequestException('消息不存在或已被删除');
    final original = messages[index];
    if (original.senderUid != current.uid) {
      throw const SocialRequestException('只能撤回自己发送的消息');
    }
    final recalled = SocialMessage(
      id: original.id,
      senderUid: original.senderUid,
      receiverUid: original.receiverUid,
      kind: original.kind,
      text: '',
      recalled: true,
      sentAt: original.sentAt,
    );
    messages[index] = recalled;
    return recalled;
  }

  @override
  Future<void> deleteMessage(String uid, String messageId) async {
    final current = _requireUser();
    _existing(uid);
    final messages = _messages[uid] ?? const <SocialMessage>[];
    if (!messages.any((message) => message.id == messageId)) {
      throw const SocialRequestException('消息不存在或已被删除');
    }
    _hiddenMessageIdsByUser
        .putIfAbsent(current.uid, () => <String>{})
        .add(messageId);
  }

  @override
  Future<void> markRead(String uid) async {
    _requireUser();
    _existing(uid);
  }

  @override
  Future<ListenTogetherSession?> getListenTogetherSession() async {
    _requireUser();
    return _togetherSession;
  }

  @override
  Future<ListenTogetherSession> inviteToListenTogether(
    String uid, {
    required ListenTogetherPlayback playback,
  }) async {
    final current = _requireUser();
    final peer = _existing(uid);
    if (!peer.isFriend) {
      throw const SocialRequestException('双方互相关注后才能一起听');
    }
    final now = DateTime.now();
    final invitationId = 'preview-together-${now.microsecondsSinceEpoch}';
    final sessionId = <String>[current.uid, uid]..sort();
    final session = ListenTogetherSession(
      id: sessionId.join('__'),
      invitationId: invitationId,
      status: ListenTogetherStatus.pending,
      inviterUid: current.uid,
      inviteeUid: uid,
      peer: peer,
      playback: _previewTogetherPlayback(
        playback,
        revision: 1,
        actorUid: current.uid,
        updatedAt: now,
      ),
      accumulatedDuration:
          _togetherSession?.accumulatedDuration ?? Duration.zero,
      bothPresent: false,
      createdAt: now,
      acceptedAt: null,
      endedAt: null,
      serverNow: now,
    );
    _togetherSession = session;
    final currentTrack = playback.currentTrack;
    await sendMessage(
      uid,
      kind: SocialMessageKind.text,
      text: encodeListenTogetherInvite(
        ListenTogetherInvite(
          invitationId: invitationId,
          sessionId: session.id,
          trackTitle: currentTrack?.title ?? '一起听音乐',
          trackArtist: currentTrack?.artist ?? '',
        ),
      ),
      thumbnailUrl: currentTrack?.coverAsset,
    );
    return session;
  }

  @override
  Future<ListenTogetherSession> respondToListenTogetherInvite(
    String invitationId, {
    required bool accept,
  }) async {
    _requireUser();
    final current = _togetherSession;
    if (current == null || !current.invitationMatches(invitationId)) {
      throw const SocialRequestException('这条一起听邀请已经失效');
    }
    final now = DateTime.now();
    final next = _copyPreviewTogetherSession(
      current,
      status: accept
          ? ListenTogetherStatus.active
          : ListenTogetherStatus.declined,
      bothPresent: accept,
      acceptedAt: accept ? now : null,
      endedAt: accept ? null : now,
      serverNow: now,
    );
    _togetherSession = next;
    final acceptedTrack = next.playback.currentTrack;
    if (accept && acceptedTrack != null) {
      _recordPreviewTogetherTrack(acceptedTrack, now);
    }
    return next;
  }

  @override
  Future<ListenTogetherSession> updateListenTogetherPlayback(
    ListenTogetherPlayback playback, {
    required int baseRevision,
  }) async {
    final user = _requireUser();
    final current = _togetherSession;
    if (current == null || !current.isActive) {
      throw const SocialRequestException('当前没有正在进行的一起听');
    }
    if (baseRevision != current.playback.revision) return current;
    final now = DateTime.now();
    final previousTrack = current.playback.currentTrack;
    final nextPlayback = _previewTogetherPlayback(
      playback,
      revision: baseRevision + 1,
      actorUid: user.uid,
      updatedAt: now,
    );
    final next = _copyPreviewTogetherSession(
      current,
      playback: nextPlayback,
      bothPresent: true,
      accumulatedDuration:
          current.accumulatedDuration + now.difference(current.fetchedAt),
      serverNow: now,
    );
    _togetherSession = next;
    final nextTrack = nextPlayback.currentTrack;
    if (nextTrack != null && nextTrack.id != previousTrack?.id) {
      _recordPreviewTogetherTrack(nextTrack, now);
    }
    return next;
  }

  @override
  Future<ListenTogetherSession> leaveListenTogether() async {
    _requireUser();
    final current = _togetherSession;
    if (current == null) {
      throw const SocialRequestException('当前没有正在进行的一起听');
    }
    final now = DateTime.now();
    final next = _copyPreviewTogetherSession(
      current,
      status: ListenTogetherStatus.ended,
      bothPresent: false,
      endedAt: now,
      serverNow: now,
    );
    _togetherSession = next;
    return next;
  }

  @override
  Future<List<ListenTogetherTrackRecord>> listListenTogetherRecords(
    String uid,
  ) async {
    _requireUser();
    _existing(uid);
    final records = _togetherRecords.values.toList()
      ..sort((a, b) => b.lastListenedAt.compareTo(a.lastListenedAt));
    return records;
  }

  @override
  Future<SocialUpload> uploadMedia({
    required String path,
    required SocialMessageKind kind,
  }) async {
    _requireUser();
    final file = File(path);
    if (!await file.exists()) {
      throw const SocialRequestException('选择的文件已经不存在，请重新选择');
    }
    return SocialUpload(
      cloudObjectId: file.uri.toString(),
      downloadUrl: file.uri.toString(),
    );
  }

  @override
  Future<String?> resolveMediaUrl(
    String value, {
    bool forceRefresh = false,
  }) async {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  void _recordPreviewTogetherTrack(Track track, DateTime listenedAt) {
    final previous = _togetherRecords[track.id];
    _togetherRecords[track.id] = ListenTogetherTrackRecord(
      track: track,
      playCount: (previous?.playCount ?? 0) + 1,
      lastListenedAt: listenedAt,
    );
  }

  AuthUser _requireUser() {
    final user = _userProvider();
    if (user == null) {
      throw const SocialRequestException('登录后才能使用好友与消息功能');
    }
    return user;
  }

  SocialUser _existing(String uid) {
    final user = _users[uid];
    if (user == null) throw const SocialRequestException('没有找到该用户');
    return user;
  }
}

ListenTogetherPlayback _previewTogetherPlayback(
  ListenTogetherPlayback value, {
  required int revision,
  required String actorUid,
  required DateTime updatedAt,
}) {
  return ListenTogetherPlayback(
    queue: value.queue,
    playing: value.playing,
    position: value.position,
    updatedAt: updatedAt,
    revision: revision,
    lastActorUid: actorUid,
  );
}

ListenTogetherSession _copyPreviewTogetherSession(
  ListenTogetherSession value, {
  ListenTogetherStatus? status,
  ListenTogetherPlayback? playback,
  Duration? accumulatedDuration,
  bool? bothPresent,
  DateTime? acceptedAt,
  DateTime? endedAt,
  DateTime? serverNow,
}) {
  return ListenTogetherSession(
    id: value.id,
    invitationId: value.invitationId,
    status: status ?? value.status,
    inviterUid: value.inviterUid,
    inviteeUid: value.inviteeUid,
    peer: value.peer,
    playback: playback ?? value.playback,
    accumulatedDuration: accumulatedDuration ?? value.accumulatedDuration,
    bothPresent: bothPresent ?? value.bothPresent,
    createdAt: value.createdAt,
    acceptedAt: acceptedAt ?? value.acceptedAt,
    endedAt: endedAt ?? value.endedAt,
    serverNow: serverNow ?? value.serverNow,
  );
}
