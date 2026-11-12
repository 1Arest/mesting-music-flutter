import '../../../shared/models/track.dart';
import '../domain/platform_session.dart';
import '../netease/netease_music_repository.dart';
import 'music_platform_api.dart';
import 'platform_explore.dart';

/// Chart metadata has platform-specific ownership: NetEase charts are real
/// playlists; a Kugou rank ID is never a cloud playlist/comment resource ID.
class PlatformRankingInfo {
  const PlatformRankingInfo({
    required this.item,
    required this.platform,
    this.description = '',
    this.cover = '',
    this.period = '',
    this.total,
    this.collections,
    this.comments,
    this.shares,
    this.subscribed = false,
    this.updatedAt,
  });
  final PlatformExploreItem item;
  final MusicPlatform platform;
  final String description, cover, period;
  final int? total, collections, comments, shares;
  final bool subscribed;
  final DateTime? updatedAt;

  Uri get shareUri => platform == MusicPlatform.netease
      ? Uri.https('music.163.com', '/playlist', {'id': item.id})
      : Uri.https('www.kugou.com', '/yy/rank/home/1-${item.id}.html');

  String snapshotName(DateTime day) =>
      '${item.title} · ${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}'
      '${period.isEmpty ? '' : ' · 第$period期'}';
}

class PlatformRankingRepository {
  PlatformRankingRepository({
    required this.api,
    required this.owner,
    required this.isCurrent,
    this.netease,
  });
  final MusicPlatformApi api;
  final PlatformSession owner;
  final bool Function() isCurrent;
  final NeteaseMusicRepository? netease;

  void check() {
    if (!isCurrent()) throw const MusicPlatformException('账号已变化，请重新打开榜单');
  }

  Future<PlatformRankingInfo> info(PlatformExploreItem item) async {
    check();
    if (!RegExp(r'^[1-9]\d*$').hasMatch(item.id)) {
      throw const MusicPlatformException('榜单标识不完整，请返回后重试');
    }
    final payload = netease != null
        ? await netease!.call('/playlist/detail', {'id': item.id, 'n': 0})
        : await api.get(
            '/rank/info',
            query: {
              'rankid': item.id,
              'rank_cid': item.rankCid.isEmpty ? '0' : item.rankCid,
            },
            expectedSession: owner,
          );
    check();
    final data = MusicPlatformApi.objectMap(
      payload[netease != null ? 'playlist' : 'data'],
    );
    if (data.isEmpty) throw const MusicPlatformException('榜单资料未完整返回，请重试');
    int? count(String key) {
      final value = int.tryParse('${data[key]}');
      return value != null && value >= 0 ? value : null;
    }

    return PlatformRankingInfo(
      item: item,
      platform: owner.platform,
      description: '${data['description'] ?? data['intro'] ?? ''}',
      cover: PlatformSession.picture(
        data['coverImgUrl'] ?? data['imgurl'] ?? item.cover,
      ),
      period: '${data['rank_cid'] ?? ''}',
      total: count('trackCount'),
      collections: count('subscribedCount'),
      comments: count('commentCount'),
      shares: count('shareCount'),
      subscribed: data['subscribed'] == true,
      updatedAt: netease != null
          ? ((count('updateTime') ?? 0) > 0
                ? DateTime.fromMillisecondsSinceEpoch(count('updateTime')!)
                : null)
          : DateTime.tryParse(
              '${MusicPlatformApi.objectMap(MusicPlatformApi.objectMap(MusicPlatformApi.objectMap(data['extra'])['resp'])['scheduled_release_conf'])['latest_rank_cid_publish_date'] ?? ''}',
            ),
    );
  }

  Future<void> subscribe(PlatformExploreItem item, bool selected) async {
    check();
    if (netease == null) throw const MusicPlatformException('酷狗榜单请收藏本期歌曲');
    await netease!.call('/playlist/subscribe', {
      'id': item.id,
      'subscribe': selected,
    });
    check();
  }

  /// Explicit Play All walks every page before replacing playback. Repeated
  /// pages or a missing tail fail visibly instead of silently playing page one.
  Future<List<Track>> complete(
    PlatformExploreRepository catalog,
    PlatformExploreItem item,
  ) async {
    check();
    final result = <Track>[];
    final ids = <String>{};
    var offset = 0;
    for (var page = 0; page < 400; page++) {
      final batch = await catalog.tracksPage(item, offset: offset);
      check();
      var added = 0;
      for (final track in batch.items) {
        if (ids.add(track.id)) {
          result.add(track);
          added++;
        }
      }
      if (!batch.hasMore) {
        if (batch.total != null && result.length < batch.total!) {
          throw const MusicPlatformException('部分榜单歌曲资料未返回，已保留当前队列，请重试');
        }
        return result;
      }
      if (batch.nextOffset <= offset || added == 0) {
        throw const MusicPlatformException('榜单读取未完成，已保留当前播放队列，请重试');
      }
      offset = batch.nextOffset;
    }
    throw const MusicPlatformException('榜单超过本次读取范围，请在官方客户端查看');
  }
}
