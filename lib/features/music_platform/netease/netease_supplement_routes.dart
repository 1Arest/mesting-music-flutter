import 'dart:convert';
import 'netease_extended_routes.dart';

/// Music, podcast and library contracts additionally exercised by
/// AlgerMusicPlayer. Desktop windows, custom scripts and third-party accounts
/// are deliberately not mixed into the NetEase request transport.
NeteaseRoute? neteaseSupplementRoute(String route, Map<String, Object?> query) {
  Object? q(String key, [Object? fallback]) => query[key] ?? fallback;
  NeteaseRoute make(
    String path,
    Map<String, Object?> data, {
    bool weapi = true,
  }) => (path: path, data: data, weapi: weapi);
  final page = <String, Object?>{
    'limit': q('limit', 30),
    'offset': q('offset', 0),
  };
  switch (route) {
    case '/dj/recommend':
      return make('/api/djradio/recommend/v1', {});
    case '/dj/catelist':
      return make('/api/djradio/category/get', {});
    case '/dj/recommend/type':
      return make('/api/djradio/recommend', {'cateId': q('type')});
    case '/dj/category/recommend':
      return make('/api/djradio/home/category/recommend', {});
    case '/dj/today/perfered':
      return make('/api/djradio/home/today/perfered', {'page': q('page', 0)});
    case '/dj/personalize/recommend':
      return make('/api/djradio/personalize/rcmd', {'limit': q('limit', 30)});
    case '/dj/banner':
      return make('/api/djradio/banner/get', {});
    case '/dj/toplist':
      return make('/api/djradio/toplist', {
        ...page,
        'type': q('type') == 'hot' ? 1 : 0,
      });
    case '/dj/radio/hot':
      return make('/api/djradio/hot', {...page, 'cateId': q('id')});
    case '/dj/sublist':
      return make('/api/djradio/get/subed', {...page, 'total': true});
    case '/dj/detail':
      return make('/api/djradio/v2/get', {'id': q('id')});
    case '/dj/program':
      return make('/api/dj/program/byradio', {
        ...page,
        'radioId': q('id'),
        'asc': false,
      });
    case '/dj/program/detail':
      return make('/api/dj/program/detail', {'id': q('id')});
    case '/dj/sub':
      return make('/api/djradio/${q('subscribe') == true ? 'sub' : 'unsub'}', {
        'id': q('id'),
      });
    case '/record/recent/dj':
      return make('/api/play-record/djradio/list', {'limit': q('limit', 100)});
    case '/personalized/djprogram':
      return make('/api/personalized/djprogram', {});
    case '/history/recommend/songs':
      return make('/api/discovery/recommend/songs/history/recent', {});
    case '/history/recommend/songs/detail':
      return make('/api/discovery/recommend/songs/history/detail', {
        'date': q('date'),
      });
    case '/recommend/songs/dislike':
      return make('/api/v2/discovery/recommend/dislike', {
        'resId': q('id'),
        'resType': 4,
        'sceneType': 1,
      });
    case '/artist/detail':
      return make('/api/artist/head/info/get', {'id': q('id')}, weapi: false);
    case '/artist/songs':
      return make('/api/v1/artist/songs', {
        ...page,
        'id': q('id'),
        'private_cloud': 'true',
        'work_type': 1,
        'order': q('order', 'hot'),
      }, weapi: false);
    case '/artist/new/song':
      return make('/api/sub/artist/new/works/song/list', {
        'limit': q('limit', 30),
        'startTimestamp': q('before', DateTime.now().millisecondsSinceEpoch),
      });
    case '/follow':
      // Search/profile relationship writes use this lightweight route table,
      // not the separately generated full-catalogue contracts. Keep both paths
      // on the same confirmed weapi endpoint; never retry a relationship write.
      return make(
        '/api/user/${'${q('t')}' == '1' ? 'follow' : 'delfollow'}/${q('id')}',
        {},
      );
    case '/user/follows':
      return make('/api/user/getfollows/${q('uid')}', {...page, 'order': true});
    case '/user/followeds':
      return make('/api/user/getfolloweds/${q('uid')}', {
        ...page,
        'userId': q('uid'),
        'time': '0',
        'getcounts': 'true',
      }, weapi: false);
    case '/search/default':
      return make('/api/search/defaultkeyword/get', {}, weapi: false);
    case '/search/suggest':
      return make('/api/search/suggest/web', {'s': q('keywords', '')});
    case '/personalized/newsong':
      return make('/api/personalized/newsong', {
        'type': 'recommend',
        'limit': q('limit', 30),
        'areaId': q('areaId', 0),
      });
    case '/album/newest':
      return make('/api/discovery/newAlbum', {});
    case '/top/album':
      final now = DateTime.now();
      return make('/api/discovery/new/albums/area', {
        ...page,
        'area': q('area', 'ALL'),
        'type': q('type', 'new'),
        'year': q('year', now.year),
        'month': q('month', now.month),
        'total': false,
        'rcmd': true,
      });
    case '/top/artists':
      return make('/api/artist/top', {...page, 'total': true});
    case '/personalized/mv':
      return make('/api/personalized/mv', {});
    case '/personalized/privatecontent':
      return make('/api/personalized/privatecontent', {});
    case '/banner':
      return make('/api/v2/banner/get', {
        'clientType': 'android',
      }, weapi: false);
    case '/song/music/detail':
      return make('/api/song/music/detail/get', {
        'songId': q('id'),
      }, weapi: false);
    case '/playlist/import/name/task/create':
      return make('/api/playlist/import/name/task/create', {
        'playlistName': q('name'),
        'songs': jsonEncode([
          {
            'name': q('name'),
            'type': '',
            'url':
                'rpc://playlist/import?text=${Uri.encodeComponent('${q('text')}')}',
          },
        ]),
        'taskIdForLog': '',
        'importStarPlaylist': false,
      }, weapi: false);
    case '/playlist/import/task/status':
      return make('/api/playlist/import/task/status/v2', {
        'taskIds': jsonEncode([q('id')]),
      }, weapi: false);
    default:
      return null;
  }
}
