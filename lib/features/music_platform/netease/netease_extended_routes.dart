import 'dart:convert';
import 'netease_supplement_routes.dart';

/// Explicit native request contracts from @neteaseapireborn/api 4.29.7.
/// Keeping the allowlist separate prevents UI code from sending arbitrary
/// protocol paths, and lets contract tests inspect payloads without networking.
typedef NeteaseRoute = ({String path, Map<String, Object?> data, bool weapi});

NeteaseRoute? neteaseExtendedRoute(String route, Map<String, Object?> query) {
  Object? q(String key, [Object? fallback]) => query[key] ?? fallback;
  NeteaseRoute make(
    String path,
    Map<String, Object?> data, {
    bool weapi = true,
  }) => (path: path, data: data, weapi: weapi);
  final page = <String, Object?>{
    'limit': q('limit', 30),
    'offset': q('offset', 0),
    'total': true,
  };
  switch (route) {
    case '/user/account':
      return make('/api/w/nuser/account/get', {});
    case '/login/refresh':
      return make('/api/login/token/refresh', {}, weapi: false);
    case '/logout':
      return make('/api/logout', {}, weapi: false);
    case '/personalized':
      return make('/api/personalized/playlist', {
        'limit': q('limit', 30),
        'total': true,
        'n': 1000,
      });
    case '/playlist/catlist':
      return make('/api/playlist/catalogue', {}, weapi: false);
    case '/top/playlist/highquality':
      return make('/api/playlist/highquality/list', {
        'cat': q('cat', '全部'),
        'limit': q('limit', 30),
        'lasttime': q('before', 0),
        'total': true,
      });
    case '/album/detail/dynamic':
      return make('/api/album/detail/dynamic', {'id': q('id')});
    case '/album/sub':
      return make('/api/album/${q('subscribe') == true ? 'sub' : 'unsub'}', {
        'id': q('id'),
      });
    case '/artist/sub':
      return make('/api/artist/${q('subscribe') == true ? 'sub' : 'unsub'}', {
        'artistId': q('id'),
        'artistIds': '[${q('id')}]',
      });
    case '/mv/sub':
      return make('/api/mv/${q('subscribe') == true ? 'sub' : 'unsub'}', {
        'mvId': q('id'),
        'mvIds': jsonEncode(['${q('id')}']),
      });
    case '/album/sublist':
    case '/artist/sublist':
      return make('/api$route', page);
    case '/mv/sublist':
      return make('/api/cloudvideo/allvideo/sublist', page);
    case '/artist/album':
      return make('/api/artist/albums/${q('id')}', page);
    case '/artist/mv':
      return make('/api/artist/mvs', {...page, 'artistId': q('id')});
    case '/toplist/artist':
      return make('/api/toplist/artist', {
        'type': q('type', 1),
        'limit': 100,
        'offset': 0,
        'total': true,
      });
    case '/simi/artist':
      return make('/api/discovery/simiArtist', {'artistid': q('id')});
    case '/simi/mv':
      return make('/api/discovery/simiMV', {'mvid': q('id')});
    case '/mv/all':
      return make('/api/mv/all', {
        ...page,
        'tags': jsonEncode({
          '地区': q('area', '全部'),
          '类型': q('type', '全部'),
          '排序': q('order', '最新'),
        }),
      }, weapi: false);
    case '/mv/first':
      return make('/api/mv/first', {
        'area': q('area', ''),
        'limit': q('limit', 30),
        'total': true,
      }, weapi: false);
    case '/user/record':
      return make('/api/v1/play/record', {
        'uid': q('uid'),
        'type': q('type', 1),
      });
    case '/record/recent/song':
    case '/record/recent/playlist':
    case '/record/recent/album':
      return make('/api/play-record/${route.split('/').last}/list', {
        'limit': q('limit', 100),
      });
    case '/song/download/url/v1':
      return make('/api/song/enhance/download/url/v1', {
        'id': q('id'),
        'level': q('level', 'standard'),
        'immerseType': 'c51',
      }, weapi: false);
    case '/daily_signin':
      return make('/api/point/dailyTask', {'type': q('type', 0)}, weapi: false);
    case '/user/cloud':
      return make('/api/v1/cloud/get', {
        'limit': q('limit', 30),
        'offset': q('offset', 0),
      });
    case '/user/cloud/detail':
      return make('/api/v1/cloud/get/byids', {'songIds': q('ids')});
    case '/user/cloud/del':
      return make('/api/cloud/del', {'songIds': q('ids')});
    case '/cloud/lyric':
      return make('/api/cloud/lyric/get', {
        'songId': q('id'),
        'userId': q('uid'),
        'lv': '-1',
        'kv': '-1',
      }, weapi: false);
    case '/playmode/intelligence/list':
      return make('/api/playmode/intelligence/list', {
        'songId': q('id'),
        'type': 'fromPlayOne',
        'playlistId': q('pid'),
        'startMusicId': q('sid', q('id')),
        'count': q('count', 30),
      }, weapi: false);
    case '/scrobble':
      return make('/api/feedback/weblog', {
        'logs': jsonEncode([
          {
            'action': 'play',
            'json': {
              'download': 0,
              'end': q('end', 'playend'),
              'id': q('id'),
              'sourceId': q('sourceid', 0),
              'time': q('time'),
              'type': 'song',
              'wifi': 0,
              'source': 'list',
              'mainsite': 1,
              'content': '',
            },
          },
        ]),
      });
    case '/comment/like':
      return make('/api/v1/comment/${q('like') == true ? 'like' : 'unlike'}', {
        'threadId': q('threadId'),
        'commentId': q('commentId'),
      });
    default:
      return neteaseSupplementRoute(route, query);
  }
}
