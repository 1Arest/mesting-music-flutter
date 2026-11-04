import '../data/music_platform_api.dart';
import '../domain/platform_search_user.dart';
import 'netease_music_repository.dart';

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
