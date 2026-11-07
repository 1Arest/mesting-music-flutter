import '../netease_features_repository.dart';
import 'netease_catalog.dart';

/// Navigation describes a user's task, not one item per HTTP request. Atomic
/// contracts stay in the catalogue for coverage and contextual actions.
String neteaseWorkflowKey(NeteaseEndpoint e) {
  final r = e.route;
  if (r.startsWith('/listentogether/')) return 'together';
  if (e.category == '消息中心' || r.startsWith('/send/')) return 'messages';
  if (e.category == '音乐搜索') return 'search';
  if ({'/user/update', '/avatar/upload'}.contains(r)) return 'profile-edit';
  if ({
    '/login',
    '/login/cellphone',
    '/login/status',
    '/login/qr/key',
    '/login/qr/create',
    '/login/qr/check',
    '/captcha/sent',
  }.contains(r)) {
    return 'account-login';
  }
  if ({
    '/playlist/update',
    '/playlist/name/update',
    '/playlist/desc/update',
    '/playlist/tags/update',
  }.contains(r)) {
    return 'playlist-edit';
  }
  if ({'/song/url', '/song/url/v1', '/check/music', '/scrobble'}.contains(r)) {
    return 'playback-settings';
  }
  if ((r.startsWith('/comment') && r != '/comment/hotwall/list') ||
      r == '/hug/comment') {
    return 'comments';
  }
  if ({'/vip/info', '/vip/info/v2'}.contains(r)) return 'vip-info';
  return r;
}

String? neteaseWorkflowTitle(NeteaseEndpoint e) =>
    switch (neteaseWorkflowKey(e)) {
      'messages' => '我的消息',
      'together' => '一起听',
      'search' => '搜索音乐与用户',
      'profile-edit' => '编辑个人资料与头像',
      'account-login' => '账号登录与管理',
      'playlist-edit' => '编辑歌单',
      'playback-settings' => '音质、备用音源与播放同步',
      'comments' => '评论与互动',
      'vip-info' => '我的会员',
      _ => null,
    };

const neteaseFeedRoutes = <String, NeteaseFeed>{
  '/personalized': NeteaseFeed.recommended,
  '/top/playlist/highquality': NeteaseFeed.premium,
  '/playlist/catlist': NeteaseFeed.categories,
  '/top/playlist': NeteaseFeed.category,
  '/toplist/artist': NeteaseFeed.artists,
  '/album/new': NeteaseFeed.albums,
  '/mv/all': NeteaseFeed.mvs,
  '/album/sublist': NeteaseFeed.likedAlbums,
  '/artist/sublist': NeteaseFeed.likedArtists,
  '/mv/sublist': NeteaseFeed.likedMvs,
  '/user/cloud': NeteaseFeed.cloud,
  '/record/recent/song': NeteaseFeed.recentSongs,
  '/record/recent/playlist': NeteaseFeed.recentPlaylists,
  '/record/recent/album': NeteaseFeed.recentAlbums,
  '/record/recent/dj': NeteaseFeed.recentPodcasts,
  '/history/recommend/songs': NeteaseFeed.historyDates,
  '/artist/new/song': NeteaseFeed.artistNewSongs,
  '/user/follows': NeteaseFeed.follows,
  '/user/followeds': NeteaseFeed.followers,
  '/personalized/mv': NeteaseFeed.recommendedMvs,
  '/personalized/privatecontent': NeteaseFeed.privateContent,
  '/album/newest': NeteaseFeed.newestAlbums,
  '/top/album': NeteaseFeed.topAlbums,
  '/personalized/newsong': NeteaseFeed.recommendedSongs,
  '/dj/recommend': NeteaseFeed.podcasts,
  '/dj/catelist': NeteaseFeed.podcastCategories,
  '/dj/sublist': NeteaseFeed.subscribedPodcasts,
  '/dj/today/perfered': NeteaseFeed.podcastToday,
  '/dj/personalize/recommend': NeteaseFeed.podcastPersonal,
  '/dj/toplist': NeteaseFeed.podcastTop,
  '/personalized/djprogram': NeteaseFeed.recommendedPrograms,
};

/// These values are service mechanics, not editable product preferences.
const neteaseAutomaticFields = {
  'offset',
  'cursor',
  'page',
  'pageNo',
  'pageSize',
  'pagesize',
  'limit',
  'size',
  'idCursor',
  'lasttime',
  'before',
  'idx',
  'res',
  'total',
  'timestamp',
};

Map<String, Object?> neteaseWorkflowDefaults(
  String route,
  String userId, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  String date(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  return {
    'uid': userId,
    'userId': userId,
    if (route == '/calendar' || route == '/vip/timemachine') ...{
      'startTime': today.millisecondsSinceEpoch,
      'endTime': today.add(const Duration(days: 30)).millisecondsSinceEpoch,
    },
    if (route == '/musician/play/trend') ...{
      'startTime': date(today.subtract(const Duration(days: 6))),
      'endTime': date(today),
    },
    if (route == '/ugc/detail') 'type': 1,
    if (route == '/digitalAlbum/ordering') ...{'quantity': 1, 'payment': 0},
    if (route == '/user/record') 'type': 1,
    if (route == '/playlist/tracks') 'op': 'add',
    if (route == '/playlist/update') ...{'desc': '', 'tags': ''},
  };
}
