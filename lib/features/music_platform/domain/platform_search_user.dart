/// Public profile fields only. Credentials and music-account sessions never
/// enter search results or a user-profile route's navigation arguments.
class PlatformSearchUser {
  const PlatformSearchUser({
    required this.id,
    required this.nickname,
    this.avatar = '',
    this.signature = '',
    this.followed = false,
    this.followsMe = false,
    this.followers = 0,
    this.following = 0,
    this.playlists = 0,
    this.level,
    this.description = '',
  });
  final String id, nickname, avatar, signature, description;
  final bool followed, followsMe;
  final int followers, following, playlists;
  final int? level;

  factory PlatformSearchUser.fromNetease(
    Map<String, dynamic> value, {
    int? level,
  }) {
    String clean(Object? v) =>
        '${v ?? ''}'.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    int count(String key) => int.tryParse('${value[key]}') ?? 0;
    bool flag(String key) => value[key] == true || '${value[key]}' == '1';
    return PlatformSearchUser(
      id: clean(value['userId']),
      nickname: clean(value['nickname']),
      avatar: clean(value['avatarUrl']),
      signature: clean(value['signature']),
      followed: flag('followed'),
      followsMe: flag('followMe'),
      followers: count('followeds'),
      following: count('follows'),
      playlists: count('playlistCount'),
      level: level,
      description: clean(value['description'] ?? value['detailDescription']),
    );
  }
}
