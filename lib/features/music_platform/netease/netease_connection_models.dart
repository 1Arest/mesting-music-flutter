import '../domain/platform_search_user.dart';

/// A missing official count remains unknown. In particular, a partial relation
/// list must never become the owner's displayed total on the My page.
class NeteasePersonalStats {
  const NeteasePersonalStats({this.following, this.followers, this.ownerId});
  final int? following, followers;

  /// Allows callers to reject a previous AsyncValue during an account reload.
  final String? ownerId;

  factory NeteasePersonalStats.fromProfile(Map<String, dynamic> profile) {
    int? count(String key) {
      final value = int.tryParse('${profile[key]}');
      return value != null && value >= 0 ? value : null;
    }

    return NeteasePersonalStats(
      following: count('follows'),
      followers: count('followeds'),
      ownerId: RegExp(r'^[1-9][0-9]*$').hasMatch('${profile['userId']}')
          ? 'netease:${profile['userId']}'
          : null,
    );
  }
}

enum NeteaseConnectionKind { user, artist }

enum NeteaseConnectionFilter { all, artists, users }

enum NeteaseConnectionSort { official, name, followTime }

/// User IDs and artist IDs are different namespaces and different write
/// contracts. Keeping the kind in the key prevents a coincident ID from
/// cancelling a user's follow when the intended action is artist unsubscribe.
class NeteaseConnection {
  const NeteaseConnection({
    required this.id,
    required this.name,
    required this.kind,
    this.avatar = '',
    this.description = '',
    this.user,
    this.followedAt,
  });
  final String id, name, avatar, description;
  final NeteaseConnectionKind kind;
  final PlatformSearchUser? user;

  /// Only an explicit upstream relation timestamp may populate this field.
  /// List position, registration time and playlist creation dates are unrelated.
  final DateTime? followedAt;
  String get key => '${kind.name}:$id';
}

class NeteaseConnectionPage {
  const NeteaseConnectionPage({
    required this.items,
    required this.consumed,
    required this.more,
  });
  final List<NeteaseConnection> items;
  final int consumed;
  final bool more;
}
