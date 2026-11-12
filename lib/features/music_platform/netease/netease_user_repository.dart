import '../data/music_platform_api.dart';
import '../domain/platform_search_user.dart';
import 'netease_music_repository.dart';
import 'netease_connection_models.dart';

class NeteaseUserPage<T> {
  const NeteaseUserPage(this.items, this.more, {int? consumed})
    : _consumed = consumed;
  final List<T> items;
  final bool more;
  final int? _consumed;
  int get consumed => _consumed ?? items.length;
}

class NeteasePublicPlaylist {
  const NeteasePublicPlaylist({
    required this.id,
    required this.name,
    required this.cover,
    required this.creator,
    required this.trackCount,
  });
  final String id, name, cover, creator;
  final int trackCount;
}

/// Independent from Mesting's own social backend. Every call uses the captured
/// NetEase credential generation, including checks after a late write response.
class NeteaseUserRepository {
  const NeteaseUserRepository(this.music);
  final NeteaseMusicRepository music;
  static void validateId(String id) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
      throw const MusicPlatformException('网易云用户ID无效');
    }
  }

  Future<PlatformSearchUser> profile(String id) async {
    validateId(id);
    final result = await music.call('/user/detail', {'uid': id});
    final profile = NeteaseMusicRepository.object(result['profile']);
    if ('${profile['userId'] ?? ''}' != id) {
      throw const MusicPlatformException('该用户资料暂时不可用');
    }
    return PlatformSearchUser.fromNetease(
      profile,
      level: int.tryParse('${result['level']}'),
    );
  }

  Future<NeteasePersonalStats> personalStats(String id) async {
    validateId(id);
    final result = await music.call('/user/detail', {'uid': id});
    final profile = NeteaseMusicRepository.object(result['profile']);
    if ('${profile['userId'] ?? ''}' != id) {
      throw const MusicPlatformException('该账号的关注与粉丝数据暂时不可用');
    }
    return NeteasePersonalStats.fromProfile(profile);
  }

  /// These owner-list methods deliberately retain the established public-user
  /// connection API below. Users and subscribed artists have separate upstream
  /// pagination and identity namespaces; no unsupported mixed search/sort query
  /// is sent to the SDK's user_follow_mixed endpoint.
  Future<NeteaseConnectionPage> personalConnections(
    String id, {
    required bool followers,
    required int offset,
  }) async {
    validateId(id);
    final result = await music.call(
      followers ? '/user/followeds' : '/user/follows',
      {'uid': id, 'offset': offset, 'limit': 30},
    );
    final field = followers ? 'followeds' : 'follow';
    if (result[field] is! List) {
      throw const MusicPlatformException('关注列表暂时不可用，请重试');
    }
    final rows = NeteaseMusicRepository.rows(result[field]);
    return NeteaseConnectionPage(
      items: [
        for (final row in rows)
          if (_validId(row['userId']))
            _userConnection(row, followers: followers),
      ],
      consumed: (result[field] as List).length,
      more: _more(result, (result[field] as List).length, offset),
    );
  }

  Future<NeteaseConnectionPage> subscribedArtists(int offset) async {
    final result = await music.call('/artist/sublist', {
      'offset': offset,
      'limit': 30,
    });
    if (result['data'] is! List) {
      throw const MusicPlatformException('关注歌手暂时不可用，请重试');
    }
    final rows = NeteaseMusicRepository.rows(result['data']);
    return NeteaseConnectionPage(
      items: [
        for (final row in rows)
          if (_validId(row['id']))
            NeteaseConnection(
              id: '${row['id']}',
              name: NeteaseMusicRepository.clean(row['name']),
              kind: NeteaseConnectionKind.artist,
              avatar: '${row['picUrl'] ?? row['img1v1Url'] ?? ''}',
              description: '歌手',
              followedAt: _relationTime(row),
            ),
      ],
      consumed: (result['data'] as List).length,
      more: _more(result, (result['data'] as List).length, offset),
    );
  }

  Future<void> subscribeArtist(String id, bool subscribed) async {
    validateId(id);
    if (music.api.session == null) {
      throw const MusicPlatformException('请先登录网易云');
    }
    final result = await music.call('/artist/sub', {
      'id': id,
      // The embedded allowlisted route uses subscribe, whereas the upstream
      // JavaScript SDK accepts t. Calling /follow for artist IDs is incorrect.
      'subscribe': subscribed,
    });
    if ('${result['code']}' != '200') {
      throw const MusicPlatformException('歌手关注操作未成功，请稍后重试');
    }
  }

  static bool _validId(Object? value) =>
      RegExp(r'^[1-9][0-9]*$').hasMatch('$value');

  static bool _more(Map<String, dynamic> result, int length, int offset) {
    if (result['more'] is bool) return result['more'] as bool;
    if (result['hasMore'] is bool) return result['hasMore'] as bool;
    final total = int.tryParse('${result['count'] ?? result['total']}');
    return total == null ? length >= 30 : offset + length < total;
  }

  static DateTime? _relationTime(Map<String, dynamic> row) {
    final value = int.tryParse(
      '${row['followTime'] ?? row['followedTime'] ?? row['subscribedTime']}',
    );
    // NetEase's explicit relationship times use epoch milliseconds. Reject
    // seconds, ordinals and malformed values instead of inventing a date.
    if (value == null || value < 946684800000 || value > 8640000000000000) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  static NeteaseConnection _userConnection(
    Map<String, dynamic> row, {
    required bool followers,
  }) {
    final value = PlatformSearchUser.fromNetease({
      ...row,
      // List membership is authoritative even when the row omits these flags.
      if (!followers) 'followed': true,
      if (followers) 'followMe': true,
    });
    return NeteaseConnection(
      id: value.id,
      name: value.nickname,
      kind: NeteaseConnectionKind.user,
      avatar: value.avatar,
      description: value.signature,
      user: value,
      followedAt: _relationTime(row),
    );
  }

  Future<void> follow(String id, bool followed) async {
    validateId(id);
    if (id == music.api.session?.userId) {
      throw const MusicPlatformException('不能关注自己');
    }
    if (music.api.session == null) {
      throw const MusicPlatformException('请先登录网易云');
    }
    final result = await music.call('/follow', {
      'id': id,
      't': followed ? 1 : 0,
    });
    if ('${result['code']}' != '200') {
      throw const MusicPlatformException('关注操作未成功，请稍后重试');
    }
  }

  Future<NeteaseUserPage<NeteasePublicPlaylist>> playlists(
    String id,
    int offset,
  ) async {
    validateId(id);
    final result = await music.call('/user/playlist', {
      'uid': id,
      'offset': offset,
      'limit': 30,
    });
    final values = NeteaseMusicRepository.rows(result['playlist']);
    return NeteaseUserPage(
      [
        for (final row in values)
          if ('${row['privacy'] ?? 0}' == '0' &&
              '${row['id'] ?? ''}'.isNotEmpty)
            NeteasePublicPlaylist(
              id: '${row['id']}',
              name: NeteaseMusicRepository.clean(row['name']),
              cover: '${row['coverImgUrl'] ?? ''}',
              creator:
                  '${NeteaseMusicRepository.object(row['creator'])['userId'] ?? ''}',
              trackCount: int.tryParse('${row['trackCount']}') ?? 0,
            ),
      ],
      result['more'] == true || (result['more'] == null && values.length == 30),
      consumed: values.length,
    );
  }

  Future<NeteaseUserPage<PlatformSearchUser>> connections(
    String id, {
    required bool followers,
    required int offset,
  }) async {
    validateId(id);
    final result = await music.call(
      followers ? '/user/followeds' : '/user/follows',
      {'uid': id, 'offset': offset, 'limit': 30},
    );
    final rows = NeteaseMusicRepository.rows(
      result[followers ? 'followeds' : 'follow'],
    );
    return NeteaseUserPage(
      rows.map(PlatformSearchUser.fromNetease).toList(),
      result['more'] == true || (result['more'] == null && rows.length == 30),
    );
  }
}
