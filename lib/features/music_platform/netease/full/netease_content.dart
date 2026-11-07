import 'dart:convert';
import '../../../../shared/models/track.dart';
import '../netease_music_repository.dart';
import 'netease_catalog.dart';

/// Collection totals are metadata, not content. An empty successful list must
/// remain empty even when the server also returns count: 0.
bool neteaseIsCollection(String route) =>
    route.endsWith('/sublist') ||
    {
      '/song/purchased',
      '/digitalAlbum/purchased',
      '/user/playlist',
      '/user/dj',
      '/dj/sublist',
      '/user/follows',
      '/user/followeds',
    }.contains(route);

/// Protocol responses end at this boundary. Screens consume music entities,
/// messages and labelled facts; account/transport maps are never rendered.
class NeteaseContentRow {
  const NeteaseContentRow({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle = '',
    this.cover = '',
    this.track,
    this.raw = const {},
  });
  final String id, title, kind, subtitle, cover;
  final Track? track;
  final Map<String, dynamic> raw;
  String get identity => '$kind:$id:$title';
}

class NeteaseContent {
  const NeteaseContent(this.rows, this.facts, {this.more = false, this.cursor});
  final List<NeteaseContentRow> rows;
  final Map<String, String> facts;
  final bool more;
  final Object? cursor;
  factory NeteaseContent.parse(Map<String, dynamic> payload, String route) {
    final rows = <NeteaseContentRow>[];
    final facts = <String, String>{};
    final seen = <String>{};
    const labels = <String, String>{
      'level': '等级',
      'nickname': '昵称',
      'signature': '个人介绍',
      'listenSongs': '听过的歌曲',
      'createDays': '加入天数',
      'point': '积分',
      'balance': '余额',
      'yunbei': '云贝',
      'growthPoint': '成长值',
      'expireTime': '到期时间',
      'version': '兼容版本',
      'connection': '连接方式',
      'message': '说明',
      'msg': '说明',
      'success': '处理结果',
      'playable': '播放权限',
      'lyric': '歌词',
      'introduction': '介绍',
      'briefDesc': '简介',
      'desc': '介绍',
      'description': '介绍',
      'content': '内容',
      'title': '标题',
      'name': '名称',
      'count': '数量',
      'total': '总数',
      'commentCount': '评论数',
      'playCount': '播放数',
      'subCount': '收藏数',
      'follower': '粉丝数',
      'followeds': '粉丝数',
      'follows': '关注数',
      'size': '数量',
      'paidCount': '已购数量',
      'taskName': '任务名称',
      'taskDesc': '任务说明',
      'qrurl': '二维码',
      'info': '说明',
      'text': '内容',
      'date': '日期',
      'time': '时间',
      'status': '状态',
      'unikey': '二维码标识',
      'roomId': '房间号',
      'inviterId': '邀请人编号',
      'userId': '用户编号',
      'canPlay': '可以播放',
      'isSign': '今日已签到',
      'signedIn': '今日已签到',
      'sheetName': '乐谱名称',
      'songName': '歌曲名称',
      'albumName': '专辑名称',
      'artistName': '歌手',
      'bitrate': '实际码率',
      'format': '文件格式',
      'tagName': '曲风',
      'enName': '英文名称',
      'tagId': '曲风编号',
      'videoId': '视频编号',
      'songId': '歌曲编号',
      'voiceId': '声音编号',
      'voiceListId': '声音列表编号',
      'resourceId': '资源编号',
      'taskId': '任务编号',
      'artistId': '歌手编号',
      'albumId': '专辑编号',
      'countryCode': '国家区号',
      'codeName': '国家名称',
      'zh': '国家或地区',
      'en': '英文名称',
      'cn': '国家或地区',
      'country': '国家或地区',
      'areaCode': '区号',
    };
    String clean(Object? value) =>
        (value is String || value is num || value is bool)
        ? NeteaseMusicRepository.clean(value).replaceAll(RegExp(r'<[^>]+>'), '')
        : '';
    String kindFor(String key, Map<String, dynamic> row) {
      if (row['ar'] is List ||
          row['al'] is Map ||
          row['mainSong'] is Map ||
          row['song'] is Map ||
          key == 'songs' ||
          key == 'tracks' ||
          key == 'dailySongs') {
        return 'song';
      }
      if (key.toLowerCase().contains('playlist') ||
          row['coverImgUrl'] != null) {
        return 'playlist';
      }
      if (key.toLowerCase().contains('album')) return 'album';
      if (key.toLowerCase().contains('artist')) return 'artist';
      if (key.toLowerCase().contains('video') || row['vid'] != null) {
        return 'video';
      }
      if (key.toLowerCase().contains('mv') ||
          route.startsWith('/mv') ||
          route == '/personalized/mv') {
        return 'mv';
      }
      if (key.toLowerCase().contains('radio') || row['dj'] != null) {
        return 'podcast';
      }
      if (key.toLowerCase().contains('comment') || row['commentId'] != null) {
        return 'comment';
      }
      if (key.toLowerCase().contains('event')) return 'event';
      if (key.toLowerCase().contains('msg') || route.startsWith('/msg')) {
        return 'message';
      }
      if (row['userId'] != null && row['nickname'] != null) return 'user';
      if (route.startsWith('/artist')) {
        return route.contains('album') ? 'album' : 'artist';
      }
      if (route.startsWith('/album') || route.startsWith('/digitalAlbum')) {
        return 'album';
      }
      if (route.startsWith('/style')) return 'style';
      return 'content';
    }

    void visit(Object? value, String key, int depth) {
      if (depth > 7) return;
      if (value is List) {
        for (final v in value) {
          if (v is Track) {
            final row = NeteaseContentRow(
              id: v.platformSongId,
              title: v.title,
              kind: 'song',
              subtitle: v.artist,
              track: v,
            );
            if (seen.add(row.identity)) rows.add(row);
            continue;
          }
          if (v is! Map) {
            if (v is String && v.isNotEmpty) {
              final row = NeteaseContentRow(
                id: v,
                title: clean(v),
                kind: 'content',
              );
              if (seen.add(row.identity)) rows.add(row);
            }
            continue;
          }
          var row = Map<String, dynamic>.from(v);
          for (final nested in ['json', 'lastMsg', 'msg']) {
            if (row[nested] is String &&
                '${row[nested]}'.trim().startsWith('{')) {
              try {
                final decoded = jsonDecode('${row[nested]}');
                if (decoded is Map) {
                  row = {...row, ...Map<String, dynamic>.from(decoded)};
                }
              } catch (_) {
                /* Ordinary user text remains plain text. */
              }
            }
          }
          if (row['data'] is Map && (row['data'] as Map).isNotEmpty) {
            row = {...row, ...Map<String, dynamic>.from(row['data'] as Map)};
          }
          if (row['song'] is Map) {
            row = {...row, ...Map<String, dynamic>.from(row['song'] as Map)};
          }
          final kind = kindFor(key, row);
          var track = kind == 'song' ? NeteaseMusicRepository.track(row) : null;
          if (row['mainSong'] is Map) {
            track = NeteaseMusicRepository.track(
              Map<String, dynamic>.from(row['mainSong'] as Map),
            );
          }
          final user = NeteaseMusicRepository.object(
            row['user'] ?? row['fromUser'] ?? row['creator'] ?? row['artist'],
          );
          final title = clean(
            row['name'] ??
                row['title'] ??
                row['nickname'] ??
                row['content'] ??
                row['msg'] ??
                row['taskName'] ??
                row['reason'] ??
                row['text'] ??
                row['label'] ??
                row['tagName'] ??
                row['zh'] ??
                row['cn'] ??
                row['country'] ??
                row['date'] ??
                row['time'] ??
                user['nickname'],
          );
          if (title.isEmpty) {
            visit(row, key, depth + 1);
            continue;
          }
          final item = NeteaseContentRow(
            id: '${row['id'] ?? row['tagId'] ?? row['vid'] ?? row['commentId'] ?? row['userId'] ?? row['taskId'] ?? title}',
            title: title,
            kind: kind,
            subtitle: clean(
              row['description'] ??
                  row['briefDesc'] ??
                  row['msg'] ??
                  user['nickname'] ??
                  user['name'] ??
                  row['artistName'] ??
                  row['total'] ??
                  row['count'] ??
                  row['countryCode'] ??
                  (route == '/countries/code/list' ? row['code'] : null),
            ),
            cover:
                '${row['picUrl'] ?? row['coverUrl'] ?? row['coverImgUrl'] ?? row['avatarUrl'] ?? row['img1v1Url'] ?? ''}',
            track: track,
            raw: row,
          );
          if (seen.add(item.identity)) rows.add(item);
        }
      } else if (value is Map) {
        for (final e in value.entries) {
          if (route == '/digitalAlbum/ordering' &&
              {
                'url',
                'qrCode',
                'qrCodeUrl',
                'codeUrl',
                'payUrl',
                'qrcode',
              }.contains('${e.key}') &&
              e.value is String) {
            facts['支付二维码'] = '${e.value}';
            continue;
          }
          if (route.startsWith('/sheet') &&
              {'url', 'imageUrl', 'picUrl'}.contains('${e.key}') &&
              e.value is String) {
            facts['乐谱图片'] = '${e.value}';
            continue;
          }
          if ({
            'cookie',
            'cookies',
            'token',
            'header',
            'MUSIC_U',
            'MUSIC_A',
            '__csrf',
            'password',
            'url',
            'urls',
            'encodeType',
            'id',
            'ids',
            'uid',
            'userId',
            'threadId',
            'roomId',
            'inviterId',
            'songId',
            'artistId',
            'albumId',
            'videoId',
            'voiceId',
            'voiceListId',
            'resourceId',
            'taskId',
            'tagId',
            'commentId',
            'province',
            'city',
            'birthday',
            'gender',
            'offset',
            'limit',
            'cursor',
            'version',
          }.contains('${e.key}')) {
            continue;
          }
          if (e.value is Map || e.value is List) {
            visit(e.value, '${e.key}', depth + 1);
          } else if ((labels.containsKey('${e.key}') ||
                  neteaseFieldLabels.containsKey('${e.key}')) &&
              e.value != null &&
              '${e.value}'.isNotEmpty) {
            facts.putIfAbsent(
              labels['${e.key}'] ?? neteaseFieldLabels['${e.key}']!,
              () => e.value is bool
                  ? (e.value == true ? '是' : '否')
                  : {'time', 'date', 'expireTime'}.contains('${e.key}') &&
                        int.tryParse('${e.value}') != null
                  ? _date(e.value)
                  : clean(e.value),
            );
          }
        }
      }
    }

    visit(payload, 'data', 0);
    final data = NeteaseMusicRepository.object(payload['data']);
    final cursor =
        payload['lasttime'] ??
        payload['lastTime'] ??
        payload['cursor'] ??
        data['cursor'] ??
        data['lastTime'] ??
        data['lasttime'];
    return NeteaseContent(
      rows,
      facts,
      more:
          payload['more'] == true ||
          payload['hasMore'] == true ||
          data['more'] == true ||
          data['hasMore'] == true,
      cursor: cursor,
    );
  }

  static String _date(Object? value) {
    final stamp = int.tryParse('$value') ?? 0;
    if (stamp <= 0) return '暂未提供';
    final date = DateTime.fromMillisecondsSinceEpoch(
      stamp < 100000000000 ? stamp * 1000 : stamp,
    );
    return '${date.year}年${date.month}月${date.day}日';
  }
}
