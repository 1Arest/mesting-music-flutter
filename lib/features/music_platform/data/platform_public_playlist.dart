import '../domain/platform_session.dart';
import '../netease/netease_music_repository.dart';
import 'music_platform_api.dart';
import 'platform_explore.dart';

/// Public collection identity is independent of the user's cloud-list ID.
/// Kugou's creator/list IDs are retained for real subscription, never guessed
/// from a numeric specialid or a title match.
class PublicPlaylistInfo {
  const PublicPlaylistInfo({
    required this.item,
    this.description = '',
    this.cover = '',
    this.creator = '',
    this.creatorId = '',
    this.creatorListId = '',
    this.total,
    this.collections,
    this.comments,
    this.shares,
    this.subscribed = false,
  });
  final PlatformExploreItem item;
  final String description, cover, creator, creatorId, creatorListId;
  final int? total, collections, comments, shares;
  final bool subscribed;

  static PublicPlaylistInfo parse(
    PlatformExploreItem item,
    Map<String, dynamic> payload, {
    required bool netease,
  }) {
    Map<String, dynamic> object(Object? value) =>
        MusicPlatformApi.objectMap(value);
    var data = object(payload[netease ? 'playlist' : 'data']);
    if (!netease) {
      final rows = payload['data'] is List
          ? payload['data']
          : data['list'] ?? data['info'];
      if (rows is List) {
        data = rows
            .whereType<Map>()
            .map(object)
            .firstWhere(
              (row) =>
                  '${row['global_collection_id'] ?? row['gid']}' == item.id,
              orElse: () => <String, dynamic>{},
            );
      }
    }
    if (data.isEmpty) throw const MusicPlatformException('歌单资料未完整返回，请重试');
    final author = object(data['creator'] ?? data['author_info']);
    int? count(List<String> keys) {
      for (final key in keys) {
        final value = int.tryParse('${data[key]}');
        if (value != null && value >= 0) return value;
      }
      return null;
    }

    return PublicPlaylistInfo(
      item: item,
      description: '${data['description'] ?? data['intro'] ?? ''}',
      cover: PlatformSession.picture(
        data['coverImgUrl'] ??
            data['sizable_cover'] ??
            data['pic'] ??
            data['imgurl'] ??
            item.cover,
      ),
      creator:
          '${author['nickname'] ?? author['user_name'] ?? data['list_create_username'] ?? data['create_user_name'] ?? ''}',
      creatorId:
          '${author['userId'] ?? author['userid'] ?? data['list_create_userid'] ?? data['create_user_id'] ?? data['userid'] ?? ''}',
      creatorListId: '${data['list_create_listid'] ?? data['listid'] ?? ''}',
      total: count(['trackCount', 'count', 'songcount', 'song_count']),
      collections: count([
        'subscribedCount',
        'collect_count',
        'collection_count',
      ]),
      comments: count(['commentCount', 'comment_count']),
      shares: count(['shareCount', 'share_count']),
      subscribed: data['subscribed'] == true || '${data['is_collect']}' == '1',
    );
  }
}

class PublicPlaylistRepository {
  const PublicPlaylistRepository({
    required this.api,
    required this.owner,
    required this.isCurrent,
    this.netease,
  });
  final MusicPlatformApi api;
  final PlatformSession owner;
  final bool Function() isCurrent;
  final NeteaseMusicRepository? netease;
  Future<PublicPlaylistInfo> info(PlatformExploreItem item) async {
    if (!isCurrent()) throw const MusicPlatformException('账号已变化，请重新打开歌单');
    final payload = netease != null
        ? await netease!.call('/playlist/detail', {'id': item.id, 'n': 0})
        : await api.get(
            '/playlist/detail',
            query: {'ids': item.id},
            expectedSession: owner,
          );
    if (!isCurrent()) throw const MusicPlatformException('账号已变化，请重新打开歌单');
    return PublicPlaylistInfo.parse(item, payload, netease: netease != null);
  }
}
