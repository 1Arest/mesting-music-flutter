enum SocialConnectionKind { following, followers, recommended }

enum SocialMessageKind { text, image, emoji, video, voice }

const socialZodiacSigns = <String>[
  '白羊座',
  '金牛座',
  '双子座',
  '巨蟹座',
  '狮子座',
  '处女座',
  '天秤座',
  '天蝎座',
  '射手座',
  '摩羯座',
  '水瓶座',
  '双鱼座',
];

class SocialStatus {
  const SocialStatus({required this.emoji, required this.text});

  const SocialStatus.empty() : emoji = '', text = '';

  final String emoji;
  final String text;

  bool get isEmpty => text.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;
  String get label =>
      emoji.trim().isEmpty ? text.trim() : '${emoji.trim()} ${text.trim()}';

  factory SocialStatus.fromJson(Map<String, Object?> json) => SocialStatus(
    emoji: json['status_emoji'] as String? ?? json['emoji'] as String? ?? '',
    text: json['status_text'] as String? ?? json['text'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {'emoji': emoji, 'text': text};

  @override
  bool operator ==(Object other) =>
      other is SocialStatus && other.emoji == emoji && other.text == text;

  @override
  int get hashCode => Object.hash(emoji, text);
}

class SocialUser {
  const SocialUser({
    required this.uid,
    required this.nickname,
    this.bio = '',
    this.age,
    this.zodiac = '',
    this.avatarUrl,
    this.remark = '',
    this.followingCount = 0,
    this.followerCount = 0,
    this.isFollowing = false,
    this.followsMe = false,
    this.isBlocked = false,
    this.status = const SocialStatus.empty(),
  });

  final String uid;
  final String nickname;
  final String bio;
  final int? age;
  final String zodiac;
  final String? avatarUrl;
  final String remark;
  final int followingCount;
  final int followerCount;
  final bool isFollowing;
  final bool followsMe;
  final bool isBlocked;
  final SocialStatus status;

  String get displayName => remark.trim().isEmpty ? nickname : remark.trim();
  bool get isFriend => isFollowing && followsMe && !isBlocked;

  factory SocialUser.fromJson(Map<String, Object?> json) {
    return SocialUser(
      uid: json['uid'] as String? ?? '',
      nickname: (json['nickname'] as String?)?.trim().isNotEmpty == true
          ? json['nickname']! as String
          : 'Mesting 用户',
      bio: json['bio'] as String? ?? '',
      age: _optionalProfileAge(json['age']),
      zodiac: json['zodiac'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      remark: json['remark'] as String? ?? '',
      followingCount: _intValue(json['following_count']),
      followerCount: _intValue(json['follower_count']),
      isFollowing: json['is_following'] as bool? ?? false,
      followsMe: json['follows_me'] as bool? ?? false,
      isBlocked: json['is_blocked'] as bool? ?? false,
      status: SocialStatus.fromJson(json),
    );
  }

  Map<String, Object?> toJson() => {
    'uid': uid,
    'nickname': nickname,
    'bio': bio,
    'age': age,
    'zodiac': zodiac,
    'avatar_url': avatarUrl,
    'remark': remark,
    'following_count': followingCount,
    'follower_count': followerCount,
    'is_following': isFollowing,
    'follows_me': followsMe,
    'is_blocked': isBlocked,
    'status_emoji': status.emoji,
    'status_text': status.text,
  };

  SocialUser copyWith({
    String? remark,
    int? followingCount,
    int? followerCount,
    bool? isFollowing,
    bool? followsMe,
    bool? isBlocked,
    SocialStatus? status,
  }) {
    return SocialUser(
      uid: uid,
      nickname: nickname,
      bio: bio,
      age: age,
      zodiac: zodiac,
      avatarUrl: avatarUrl,
      remark: remark ?? this.remark,
      followingCount: followingCount ?? this.followingCount,
      followerCount: followerCount ?? this.followerCount,
      isFollowing: isFollowing ?? this.isFollowing,
      followsMe: followsMe ?? this.followsMe,
      isBlocked: isBlocked ?? this.isBlocked,
      status: status ?? this.status,
    );
  }
}

class SocialSummary {
  const SocialSummary({
    this.followingCount = 0,
    this.followerCount = 0,
    this.unreadCount = 0,
  });

  final int followingCount;
  final int followerCount;
  final int unreadCount;

  factory SocialSummary.fromJson(Map<String, Object?> json) => SocialSummary(
    followingCount: _intValue(json['following_count']),
    followerCount: _intValue(json['follower_count']),
    unreadCount: _intValue(json['unread_count']),
  );
}

class SocialConversation {
  const SocialConversation({
    required this.peer,
    required this.updatedAt,
    this.lastMessage,
    this.unreadCount = 0,
  });

  final SocialUser peer;
  final SocialMessage? lastMessage;
  final DateTime updatedAt;
  final int unreadCount;

  factory SocialConversation.fromJson(Map<String, Object?> json) {
    return SocialConversation(
      peer: SocialUser.fromJson(_mapValue(json['peer'])),
      lastMessage: json['last_message'] == null
          ? null
          : SocialMessage.fromJson(_mapValue(json['last_message'])),
      updatedAt: _dateValue(json['updated_at']),
      unreadCount: _intValue(json['unread_count']),
    );
  }
}

class SocialMessage {
  const SocialMessage({
    required this.id,
    required this.senderUid,
    required this.receiverUid,
    required this.kind,
    required this.sentAt,
    this.text = '',
    this.mediaUrl,
    this.thumbnailUrl,
    this.recalled = false,
  });

  final String id;
  final String senderUid;
  final String receiverUid;
  final SocialMessageKind kind;
  final String text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final bool recalled;
  final DateTime sentAt;

  factory SocialMessage.fromJson(Map<String, Object?> json) {
    final rawKind = json['kind'] as String? ?? 'text';
    return SocialMessage(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      senderUid: json['sender_uid'] as String? ?? '',
      receiverUid: json['receiver_uid'] as String? ?? '',
      kind: SocialMessageKind.values.firstWhere(
        (value) => value.name == rawKind,
        orElse: () => SocialMessageKind.text,
      ),
      text: json['text'] as String? ?? '',
      mediaUrl: json['media_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      recalled: json['recalled'] == true,
      sentAt: _dateValue(json['sent_at']),
    );
  }

  SocialMessage copyWith({
    String? text,
    String? mediaUrl,
    String? thumbnailUrl,
    bool? recalled,
  }) {
    return SocialMessage(
      id: id,
      senderUid: senderUid,
      receiverUid: receiverUid,
      kind: kind,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      recalled: recalled ?? this.recalled,
      sentAt: sentAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'sender_uid': senderUid,
    'receiver_uid': receiverUid,
    'kind': kind.name,
    'text': text,
    'media_url': mediaUrl,
    'thumbnail_url': thumbnailUrl,
    'recalled': recalled,
    'sent_at': sentAt.toUtc().toIso8601String(),
  };
}

int? _optionalProfileAge(Object? value) {
  final age = value is int ? value : int.tryParse(value?.toString() ?? '');
  return age != null && age >= 1 && age <= 120 ? age : null;
}

class SocialUpload {
  const SocialUpload({required this.cloudObjectId, required this.downloadUrl});

  final String cloudObjectId;
  final String downloadUrl;
}

class SocialRequestException implements Exception {
  const SocialRequestException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

int _intValue(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

DateTime _dateValue(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  }
  return DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
