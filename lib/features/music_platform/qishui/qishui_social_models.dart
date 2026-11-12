import 'qishui_api.dart';
import 'qishui_models.dart';

/// A missing server count is unknown, not zero. The regular counts are the
/// same fields appended to the official User; Luna-only counts are separate
/// breakdowns and must not replace the regular count silently.
class QishuiSocialStats {
  const QishuiSocialStats({
    this.following,
    this.followers,
    this.likes,
    this.lunaFollowing,
    this.lunaFollowers,
    this.commentLikes,
    this.likesTitle = '',
    this.likesDescription = '',
  });

  final int? following, followers, likes, lunaFollowing, lunaFollowers;
  final int? commentLikes;
  final String likesTitle, likesDescription;

  bool get hasCounts => following != null || followers != null || likes != null;

  static QishuiSocialStats parse(Map<String, dynamic> profile) {
    final root = qishuiSocialPayload(profile);
    return fromStats(sodaMap(root['my_stats'] ?? root['user_stats']));
  }

  static QishuiSocialStats fromStats(Map<String, dynamic> value) {
    // RetrofitManager's Gson explicitly uses LOWER_CASE_WITH_UNDERSCORES.
    // NetAllCommentsLikedDetail is an official aggregate/popup, not a list of
    // users who liked us. Never manufacture such a list from these counts.
    final detail = sodaMap(value['all_comments_liked_detail']);
    final popup = sodaMap(detail['popup']);
    return QishuiSocialStats(
      following: qishuiSocialCount(value['count_following']),
      followers: qishuiSocialCount(value['count_follower']),
      likes: qishuiSocialCount(value['count_all_liked']),
      lunaFollowing: qishuiSocialCount(value['count_luna_following']),
      lunaFollowers: qishuiSocialCount(value['count_luna_follower']),
      commentLikes: qishuiSocialCount(detail['count']),
      likesTitle: _text(popup['title'], maximum: 200),
      likesDescription: _text(popup['content'], maximum: 4000),
    );
  }
}

enum QishuiFollowListKind {
  following('following', '关注'),
  followers('follower', '粉丝');

  const QishuiFollowListKind(this.pathName, this.label);
  final String pathName, label;
}

enum QishuiFollowSource {
  qishui('2', '汽水'),
  douyin('1', '抖音');

  const QishuiFollowSource(this.scene, this.label);
  final String scene, label;
}

/// User and artist IDs belong to different namespaces. A pure artist can be
/// opened as an artist, but must never be passed to the user-follow endpoint.
class QishuiSocialPerson {
  const QishuiSocialPerson({
    required this.key,
    required this.name,
    this.userId,
    this.artistId,
    this.avatar = '',
    this.signature = '',
    this.followStatus,
    this.followedByMe,
    this.artistEntity = false,
  });

  final String key, name, avatar, signature;
  final String? userId, artistId;
  final int? followStatus;
  final bool? followedByMe;
  final bool artistEntity;

  bool get requested => followStatus == 4 || followStatus == 5;
  bool? get following => requested
      ? null
      : switch (followStatus) {
          1 || 2 => true,
          0 || 3 => false,
          _ => followedByMe,
        };
  String get relationshipLabel => requested
      ? '已申请'
      : followStatus == 2
      ? '互相关注'
      : following == true
      ? '已关注'
      : following == false
      ? '关注'
      : '刷新状态';

  static QishuiSocialPerson? parseMixed(Object? value) {
    final row = sodaMap(value);
    final kind = _text(row['item_type']);
    final artist = sodaMap(row['artist']);
    final linkedUser = kind == 'artist'
        ? sodaMap(artist['user_info'])
        : const <String, dynamic>{};
    final user = kind == 'user' ? sodaMap(row['user']) : linkedUser;
    final uid = qishuiSocialId(user['id']);
    final aid = qishuiSocialId(artist['id']);
    // Unknown item kinds cannot opt into authenticated user mutations. Keep
    // only known, explicitly typed entities with a real identity.
    if (!{'user', 'artist'}.contains(kind) ||
        kind == 'user' && uid == null ||
        kind == 'artist' && aid == null) {
      return null;
    }
    final state = sodaMap(
      kind == 'artist'
          ? artist['state']
          : row['my_user_state'] ?? user['user_state'],
    );
    return QishuiSocialPerson(
      key: kind == 'artist' ? 'artist:$aid' : 'user:$uid',
      artistEntity: kind == 'artist',
      userId: uid,
      artistId: aid,
      name: kind == 'artist' ? _text(artist['name']) : _text(user['nickname']),
      avatar: sodaPicture([
        user['medium_avatar_url'],
        user['thumb_avatar_url'],
        artist['url_avatar'],
      ]),
      signature: _text(user['signature'], maximum: 1000),
      followStatus: kind == 'artist' ? null : _status(state['follow_status']),
      followedByMe: _bool(
        kind == 'artist' ? state['is_collected'] : state['followed_by_me'],
      ),
    );
  }

  QishuiSocialPerson withArtistMembership(bool member) => QishuiSocialPerson(
    key: key,
    name: name,
    userId: userId,
    artistId: artistId,
    artistEntity: artistEntity,
    avatar: avatar,
    signature: signature,
    followedByMe: member,
  );

  static QishuiSocialPerson parseUserInfo(
    Map<String, dynamic> response,
    String expectedUser,
  ) {
    final root = qishuiSocialPayload(response);
    final user = sodaMap(root['user']);
    if (qishuiSocialId(user['id']) != expectedUser) {
      throw const QishuiException('汽水返回的用户身份不匹配');
    }
    final state = sodaMap(root['my_user_state']);
    return QishuiSocialPerson(
      key: 'user:$expectedUser',
      userId: expectedUser,
      artistId: qishuiSocialId(user['artist_id']),
      name: _text(user['nickname']),
      avatar: sodaPicture([
        user['larger_avatar_url'],
        user['medium_avatar_url'],
      ]),
      signature: _text(user['signature'], maximum: 1000),
      followStatus: _status(state['follow_status']),
      followedByMe: _bool(state['followed_by_me']),
    );
  }
}

class QishuiSocialPage {
  const QishuiSocialPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
    this.nextCursor,
    this.continuationProblem,
  });
  final List<QishuiSocialPerson> items;
  final String cursor;
  final bool hasMore;
  final String? nextCursor, continuationProblem;

  static QishuiSocialPage parse(Map<String, dynamic> response, String cursor) {
    final root = qishuiSocialPayload(response);
    // The shipped response constructor initializes an empty ArrayList and
    // BasePageResponse defaults hasMore to false. The official service omits
    // those fields for an empty source group (confirmed by the user's 178
    // receipt). Accept only that acknowledged empty envelope; a different
    // payload, an explicit null/wrong list, or a continuation is still an error.
    final rows = _confirmedEmptyFollowPage(response, root)
        ? const <Object>[]
        : root['follow_items'];
    if (rows is! List || rows.length > 200) {
      throw const QishuiException('汽水关注列表格式异常，请刷新重试');
    }
    final people = <String, QishuiSocialPerson>{};
    for (final row in rows) {
      final person = QishuiSocialPerson.parseMixed(row);
      if (person != null) people[person.key] = person;
    }
    final more = _bool(root['has_more']) == true;
    final next = root['next_cursor'];
    final validNext =
        next is String &&
        next.isNotEmpty &&
        qishuiSocialCursorValid(next) &&
        next != cursor;
    return QishuiSocialPage(
      items: List.unmodifiable(people.values),
      cursor: cursor,
      hasMore: more && validNext,
      nextCursor: validNext ? next : null,
      continuationProblem: more && !validNext ? '汽水未返回有效续载位置，请下拉刷新。' : null,
    );
  }
}

bool _confirmedEmptyFollowPage(
  Map<String, dynamic> response,
  Map<String, dynamic> root,
) {
  if (root.containsKey('follow_items')) return false;
  const envelopeKeys = {
    'status_info',
    'status_code',
    'error_code',
    'code',
    'next_cursor',
    'has_more',
  };
  for (final envelope in [response, root]) {
    final outerWrapper =
        identical(envelope, response) && !identical(root, response);
    if (envelope.keys.any(
      (key) => !envelopeKeys.contains(key) && !(outerWrapper && key == 'data'),
    )) {
      return false;
    }
    if (envelope.containsKey('status_info') &&
        envelope['status_info'] is! Map) {
      return false;
    }
    if (envelope.containsKey('has_more') &&
        _bool(envelope['has_more']) != false) {
      return false;
    }
    final next = envelope['next_cursor'];
    if (next != null && (next is! String || !qishuiSocialCursorValid(next))) {
      return false;
    }
  }
  final status = sodaMap(root['status_info']);
  final outerStatus = sodaMap(response['status_info']);
  final codes = [
    response['status_code'],
    response['error_code'],
    response['code'],
    root['status_code'],
    root['error_code'],
    root['code'],
    status['code'],
    status['status_code'],
    outerStatus['code'],
    outerStatus['status_code'],
  ].where((code) => code != null).toList();
  // A blank/unknown JSON object must never masquerade as an empty official
  // follow list. A concrete successful business receipt is required here.
  return codes.isNotEmpty &&
      codes.every((code) => qishuiSocialCount(code) == 0);
}

Map<String, dynamic> qishuiSocialPayload(Map<String, dynamic> response) =>
    response['data'] is Map ? sodaMap(response['data']) : response;

String? qishuiSocialId(Object? value) {
  final text = '$value';
  return RegExp(r'^[0-9]{1,30}$').hasMatch(text) ? text : null;
}

bool qishuiSocialCursorValid(String value) =>
    value.length <= 256 && !RegExp(r'[\x00-\x20\x7f]').hasMatch(value);

int? qishuiSocialCount(Object? value) {
  if (value is! int && value is! String) return null;
  final parsed = int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : null;
}

int? _status(Object? value) {
  final number = qishuiSocialCount(value);
  return number != null && number <= 5 ? number : null;
}

bool? _bool(Object? value) => switch (value) {
  true || 1 || '1' => true,
  false || 0 || '0' => false,
  _ => null,
};

String _text(Object? value, {int maximum = 200}) {
  if (value is! String || value.length > maximum) return '';
  return value
      .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'), '')
      .trim();
}
