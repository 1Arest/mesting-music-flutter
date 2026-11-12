import 'dart:convert';

/// A notification carries a typed in-app destination, never an upstream URL or
/// executable route. Identifiers are validated again when an old notification
/// is opened after process death or an application update.
enum NoticeTargetKind {
  conversation,
  comment,
  user,
  song,
  album,
  playlist,
  artist,
  event,
  daily,
  category,
}

class NoticeTarget {
  const NoticeTarget({
    required this.kind,
    this.id = '',
    this.name = '',
    this.resourceKind = '',
    this.resourceId = '',
    this.tag = '',
    this.hash = '',
    this.category = 'interaction',
    this.section = '',
  });
  final NoticeTargetKind kind;
  final String id, name, resourceKind, resourceId, tag, hash, category, section;

  static String identifier(Object? value) {
    final text = '${value ?? ''}';
    return RegExp(r'^[1-9]\d{0,19}$').hasMatch(text) ? text : '';
  }

  static String audioHash(Object? value) {
    final text = '${value ?? ''}'.toLowerCase();
    return RegExp(r'^[a-f0-9]{32}$').hasMatch(text) ? text : '';
  }

  static String label(Object? value) => value is String
      ? String.fromCharCodes(
          value.replaceAll(RegExp(r'[\x00-\x1f]'), '').runes.take(100),
        )
      : '';
  static String messageTag(Object? value) {
    final text = '${value ?? ''}';
    return RegExp(r'^[A-Za-z0-9_:.-]{1,160}$').hasMatch(text) ? text : '';
  }

  static const categories = {
    'privateMessage',
    'interaction',
    'artist',
    'recommendation',
  };
  static const resourceKinds = {
    'song',
    'playlist',
    'album',
    'mv',
    'podcast',
    'video',
    'event',
    'radio',
  };
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'id': id,
    'name': name,
    'resourceKind': resourceKind,
    'resourceId': resourceId,
    'tag': tag,
    'hash': hash,
    'category': category,
    'section': section,
  };

  static NoticeTarget fromJson(Object? raw, {String fallback = 'interaction'}) {
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        raw = null;
      }
    }
    final map = raw is Map ? raw : const {};
    final category = categories.contains(map['category'])
        ? map['category'] as String
        : categories.contains(fallback)
        ? fallback
        : 'interaction';
    final kind =
        NoticeTargetKind.values
            .where((v) => v.name == map['kind'])
            .firstOrNull ??
        NoticeTargetKind.category;
    final id = identifier(map['id']),
        resourceId = identifier(map['resourceId']);
    final resourceKind = resourceKinds.contains(map['resourceKind'])
        ? map['resourceKind'] as String
        : '';
    final valid = switch (kind) {
      NoticeTargetKind.category || NoticeTargetKind.daily => true,
      NoticeTargetKind.comment =>
        id.isNotEmpty && resourceId.isNotEmpty && resourceKind.isNotEmpty,
      NoticeTargetKind.song =>
        id.isNotEmpty || audioHash(map['hash']).isNotEmpty,
      _ => id.isNotEmpty,
    };
    return NoticeTarget(
      kind: valid ? kind : NoticeTargetKind.category,
      id: id,
      name: label(map['name']),
      resourceKind: resourceKind,
      resourceId: resourceId,
      tag: messageTag(map['tag']),
      hash: audioHash(map['hash']),
      category: category,
      section:
          const {
            'fans',
            'comments',
            'mentions',
            'notices',
          }.contains(map['section'])
          ? map['section'] as String
          : '',
    );
  }

  /// The row is read from the native account-scoped inbox. Compatibility only
  /// recovers explicit IDs written by 1.1.0, never guesses from display text.
  static NoticeTarget forNotice(Map row) {
    final category = categories.contains(row['kind'])
        ? row['kind'] as String
        : 'interaction';
    if (row['target'] != null) {
      return fromJson(row['target'], fallback: category);
    }
    final peer = identifier(row['peer']);
    if (category == 'privateMessage' && peer.isNotEmpty) {
      return NoticeTarget(
        kind: NoticeTargetKind.conversation,
        id: peer,
        name: label(row['title']),
        category: category,
      );
    }
    final match = RegExp(
      r'^artist:([1-9]\d{0,19})$',
    ).firstMatch('${row['sourceId'] ?? row['id']}');
    if (match != null) {
      return NoticeTarget(
        kind: row['platform'] == 'kugou'
            ? NoticeTargetKind.album
            : NoticeTargetKind.song,
        id: match[1]!,
        name: label(row['title']),
        category: category,
      );
    }
    if (category == 'recommendation') {
      return NoticeTarget(kind: NoticeTargetKind.daily, category: category);
    }
    return NoticeTarget(kind: NoticeTargetKind.category, category: category);
  }
}

/// Native must resolve the persisted row under its stored login scope first.
/// The router only accepts the resulting small, typed query field allowlist.
String noticeDestinationRoute(Map entry) {
  final target = NoticeTarget.forNotice(entry);
  return Uri(
    path: '/music/notice-content',
    queryParameters: {
      'platform': '${entry['platform']}',
      'scope': '${entry['scope'] ?? ''}',
      'kind': target.kind.name,
      'id': target.id,
      'name': target.name,
      'resourceKind': target.resourceKind,
      'resourceId': target.resourceId,
      'tag': target.tag,
      'hash': target.hash,
      'category': target.category,
      'section': target.section,
    },
  ).toString();
}

/// Explicit NetEase thread prefixes also cover album/playlist/video comments.
/// A notice without the underlying resource stays in its message category.
NoticeTarget neteaseNoticeTarget({
  required String category,
  String userId = '',
  String userName = '',
  String commentId = '',
  String threadId = '',
  String resourceKind = '',
  String resourceId = '',
  String eventId = '',
}) {
  if (category == 'fans' && NoticeTarget.identifier(userId).isNotEmpty) {
    return NoticeTarget(
      kind: NoticeTargetKind.user,
      id: NoticeTarget.identifier(userId),
      name: userName,
      section: category,
    );
  }
  const prefixes = {
    'R_SO_4_': 'song',
    'A_PL_0_': 'playlist',
    'R_AL_3_': 'album',
    'R_MV_5_': 'mv',
    'R_VI_62_': 'video',
    'A_EV_2_': 'event',
    'A_DJ_1_': 'podcast',
    'A_DR_14_': 'radio',
  };
  for (final prefix in prefixes.entries) {
    if (threadId.startsWith(prefix.key)) {
      final id = NoticeTarget.identifier(threadId.substring(prefix.key.length));
      if (id.isNotEmpty) {
        resourceKind = prefix.value;
        resourceId = id;
        break;
      }
    }
  }
  if (NoticeTarget.resourceKinds.contains(resourceKind) &&
      NoticeTarget.identifier(resourceId).isNotEmpty &&
      NoticeTarget.identifier(commentId).isNotEmpty) {
    return NoticeTarget(
      kind: NoticeTargetKind.comment,
      id: NoticeTarget.identifier(commentId),
      resourceId: NoticeTarget.identifier(resourceId),
      resourceKind: resourceKind,
      section: category,
    );
  }
  if (NoticeTarget.identifier(eventId).isNotEmpty) {
    return NoticeTarget(
      kind: NoticeTargetKind.event,
      id: NoticeTarget.identifier(eventId),
    );
  }
  return NoticeTarget(kind: NoticeTargetKind.category, section: category);
}
