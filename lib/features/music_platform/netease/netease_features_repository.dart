import '../../../shared/models/track.dart';
import '../../../shared/utils/media_uri.dart';
import '../../../core/diagnostics/local_music_diagnostics.dart';
import '../data/music_platform_api.dart';
import 'netease_music_repository.dart';
import 'netease_song_metadata.dart';

enum NeteaseFeed {
  recommended,
  premium,
  categories,
  category,
  artists,
  albums,
  mvs,
  likedAlbums,
  likedArtists,
  likedMvs,
  cloud,
  week,
  allTime,
  artistAlbums,
  artistMvs,
  similarArtists,
  similarMvs,
  intelligence,
  recentSongs,
  recentPlaylists,
  recentAlbums,
  podcasts,
  podcastCategories,
  podcastCategory,
  podcastPrograms,
  subscribedPodcasts,
  podcastToday,
  podcastPersonal,
  podcastTop,
  recentPodcasts,
  recommendedPrograms,
  historyDates,
  historySongs,
  artistSongs,
  artistNewSongs,
  follows,
  followers,
  userPlaylists,
  recommendedMvs,
  privateContent,
  newestAlbums,
  topAlbums,
  recommendedSongs,
}

enum NeteaseEntity {
  song,
  playlist,
  album,
  artist,
  mv,
  category,
  podcast,
  podcastCategory,
  program,
  date,
  user,
}

/// Provider-neutral widgets receive typed entities, never raw protocol maps.
/// IDs here belong to NetEase; playback Track IDs stay provider-qualified.
class NeteaseItem {
  const NeteaseItem({
    required this.id,
    required this.name,
    required this.kind,
    this.subtitle = '',
    this.cover = '',
    this.track,
    this.cursor = 0,
  });
  final String id, name, subtitle, cover;
  final NeteaseEntity kind;
  final Track? track;
  final int cursor;
}

class NeteaseBatch {
  const NeteaseBatch(this.items, {this.more = false, this.cursor = 0});
  final List<NeteaseItem> items;
  final bool more;
  final int cursor;
}

class NeteaseFeaturesRepository {
  const NeteaseFeaturesRepository(this.music);
  final NeteaseMusicRepository music;
  static const titles = <NeteaseFeed, String>{
    NeteaseFeed.recommended: '推荐歌单',
    NeteaseFeed.premium: '精品歌单',
    NeteaseFeed.categories: '歌单分类',
    NeteaseFeed.category: '分类歌单',
    NeteaseFeed.artists: '歌手榜',
    NeteaseFeed.albums: '新碟上架',
    NeteaseFeed.mvs: 'MV',
    NeteaseFeed.likedAlbums: '收藏的专辑',
    NeteaseFeed.likedArtists: '关注的歌手',
    NeteaseFeed.likedMvs: '收藏的 MV',
    NeteaseFeed.cloud: '音乐云盘',
    NeteaseFeed.week: '最近一周听歌排行',
    NeteaseFeed.allTime: '所有时间听歌排行',
    NeteaseFeed.artistAlbums: '歌手专辑',
    NeteaseFeed.artistMvs: '歌手 MV',
    NeteaseFeed.similarArtists: '相似歌手',
    NeteaseFeed.similarMvs: '相似 MV',
    NeteaseFeed.intelligence: '心动模式',
    NeteaseFeed.recentSongs: '云端最近播放的歌曲',
    NeteaseFeed.recentPlaylists: '云端最近播放的歌单',
    NeteaseFeed.recentAlbums: '云端最近播放的专辑',
    NeteaseFeed.podcasts: '播客电台',
    NeteaseFeed.podcastCategories: '播客分类',
    NeteaseFeed.podcastCategory: '分类播客',
    NeteaseFeed.podcastPrograms: '播客节目',
    NeteaseFeed.subscribedPodcasts: '订阅的播客',
    NeteaseFeed.podcastToday: '今日优选播客',
    NeteaseFeed.podcastPersonal: '为你推荐的播客',
    NeteaseFeed.podcastTop: '热门播客榜',
    NeteaseFeed.recentPodcasts: '云端最近播放的播客',
    NeteaseFeed.recommendedPrograms: '推荐节目',
    NeteaseFeed.historyDates: '历史日推',
    NeteaseFeed.historySongs: '历史推荐歌曲',
    NeteaseFeed.artistSongs: '歌手全部歌曲',
    NeteaseFeed.artistNewSongs: '关注歌手新歌',
    NeteaseFeed.follows: '网易云关注',
    NeteaseFeed.followers: '网易云粉丝',
    NeteaseFeed.userPlaylists: '用户公开歌单',
    NeteaseFeed.recommendedMvs: '推荐 MV',
    NeteaseFeed.privateContent: '独家放送',
    NeteaseFeed.newestAlbums: '最新专辑',
    NeteaseFeed.topAlbums: '本月新碟',
    NeteaseFeed.recommendedSongs: '推荐新歌',
  };

  Future<NeteaseBatch> load(
    NeteaseFeed feed, {
    int page = 1,
    int before = 0,
    String id = '',
    String category = '全部',
    String area = 'ALL',
    int artistArea = 1,
  }) async {
    final q = <String, Object?>{'offset': (page - 1) * 30, 'limit': 30};
    late String route;
    var kind = NeteaseEntity.playlist;
    switch (feed) {
      case NeteaseFeed.recommended:
        route = '/personalized';
      case NeteaseFeed.premium:
        route = '/top/playlist/highquality';
        q.addAll({'cat': category, 'before': before});
      case NeteaseFeed.categories:
        route = '/playlist/catlist';
        kind = NeteaseEntity.category;
      case NeteaseFeed.category:
        route = '/top/playlist';
        q['cat'] = category;
      case NeteaseFeed.artists:
        route = '/toplist/artist';
        kind = NeteaseEntity.artist;
        q['type'] = artistArea;
      case NeteaseFeed.albums:
        route = '/album/new';
        kind = NeteaseEntity.album;
        q['area'] = area;
      case NeteaseFeed.mvs:
        route = '/mv/all';
        kind = NeteaseEntity.mv;
        q['area'] = area == 'ALL' ? '全部' : area;
      case NeteaseFeed.likedAlbums:
        route = '/album/sublist';
        kind = NeteaseEntity.album;
      case NeteaseFeed.likedArtists:
        route = '/artist/sublist';
        kind = NeteaseEntity.artist;
      case NeteaseFeed.likedMvs:
        route = '/mv/sublist';
        kind = NeteaseEntity.mv;
      case NeteaseFeed.cloud:
        route = '/user/cloud';
        kind = NeteaseEntity.song;
      case NeteaseFeed.podcasts:
        route = '/dj/recommend';
        kind = NeteaseEntity.podcast;
      case NeteaseFeed.podcastCategories:
        route = '/dj/catelist';
        kind = NeteaseEntity.podcastCategory;
      case NeteaseFeed.podcastCategory:
        route = '/dj/radio/hot';
        kind = NeteaseEntity.podcast;
        q['id'] = id;
      case NeteaseFeed.podcastPrograms:
        route = '/dj/program';
        kind = NeteaseEntity.program;
        q['id'] = id;
      case NeteaseFeed.subscribedPodcasts:
        route = '/dj/sublist';
        kind = NeteaseEntity.podcast;
      case NeteaseFeed.podcastToday:
        route = '/dj/today/perfered';
        kind = NeteaseEntity.podcast;
        q['page'] = page - 1;
      case NeteaseFeed.podcastPersonal:
        route = '/dj/personalize/recommend';
        kind = NeteaseEntity.podcast;
      case NeteaseFeed.podcastTop:
        route = '/dj/toplist';
        kind = NeteaseEntity.podcast;
        q['type'] = 'hot';
      case NeteaseFeed.recentPodcasts:
        route = '/record/recent/dj';
        kind = NeteaseEntity.podcast;
        q['limit'] = 300;
      case NeteaseFeed.recommendedPrograms:
        route = '/personalized/djprogram';
        kind = NeteaseEntity.program;
      case NeteaseFeed.historyDates:
        route = '/history/recommend/songs';
        kind = NeteaseEntity.date;
      case NeteaseFeed.historySongs:
        route = '/history/recommend/songs/detail';
        kind = NeteaseEntity.song;
        q['date'] = id;
      case NeteaseFeed.artistSongs:
        route = '/artist/songs';
        kind = NeteaseEntity.song;
        q['id'] = id;
      case NeteaseFeed.artistNewSongs:
        route = '/artist/new/song';
        kind = NeteaseEntity.song;
        q['before'] = before == 0
            ? DateTime.now().millisecondsSinceEpoch
            : before;
      case NeteaseFeed.follows:
        route = '/user/follows';
        kind = NeteaseEntity.user;
        q['uid'] = music.api.session?.userId;
      case NeteaseFeed.followers:
        route = '/user/followeds';
        kind = NeteaseEntity.user;
        q['uid'] = music.api.session?.userId;
      case NeteaseFeed.userPlaylists:
        route = '/user/playlist';
        q['uid'] = id;
      case NeteaseFeed.recommendedMvs:
        route = '/personalized/mv';
        kind = NeteaseEntity.mv;
      case NeteaseFeed.privateContent:
        route = '/personalized/privatecontent';
        kind = NeteaseEntity.mv;
      case NeteaseFeed.newestAlbums:
        route = '/album/newest';
        kind = NeteaseEntity.album;
      case NeteaseFeed.topAlbums:
        route = '/top/album';
        kind = NeteaseEntity.album;
        q['area'] = area;
      case NeteaseFeed.recommendedSongs:
        route = '/personalized/newsong';
        kind = NeteaseEntity.song;
      case NeteaseFeed.recentSongs:
        route = '/record/recent/song';
        kind = NeteaseEntity.song;
        q['limit'] = 300;
      case NeteaseFeed.recentPlaylists:
        route = '/record/recent/playlist';
        q['limit'] = 300;
      case NeteaseFeed.recentAlbums:
        route = '/record/recent/album';
        kind = NeteaseEntity.album;
        q['limit'] = 300;
      case NeteaseFeed.week:
      case NeteaseFeed.allTime:
        route = '/user/record';
        kind = NeteaseEntity.song;
        q.addAll({
          'uid': music.api.session?.identity.userId,
          'type': feed == NeteaseFeed.week ? 1 : 0,
        });
      case NeteaseFeed.artistAlbums:
        route = '/artist/album';
        kind = NeteaseEntity.album;
        q['id'] = id;
      case NeteaseFeed.artistMvs:
        route = '/artist/mv';
        kind = NeteaseEntity.mv;
        q['id'] = id;
      case NeteaseFeed.similarArtists:
        route = '/simi/artist';
        kind = NeteaseEntity.artist;
        q['id'] = id;
      case NeteaseFeed.similarMvs:
        route = '/simi/mv';
        kind = NeteaseEntity.mv;
        q['id'] = id;
      case NeteaseFeed.intelligence:
        final lists = NeteaseMusicRepository.rows(
          (await music.call('/user/playlist', {
            'uid': music.api.session?.identity.userId,
            'limit': 1,
          }))['playlist'],
        );
        if (lists.isEmpty) return const NeteaseBatch([]);
        final songs = (await music.playlistPage(
          '${lists.first['id']}',
          limit: 1,
        )).items;
        if (songs.isEmpty) return const NeteaseBatch([]);
        route = '/playmode/intelligence/list';
        kind = NeteaseEntity.song;
        q.addAll({'id': songs.first.platformSongId, 'pid': lists.first['id']});
    }
    final payload = await music.call(route, q);
    final recent = {
      NeteaseFeed.recentSongs,
      NeteaseFeed.recentAlbums,
      NeteaseFeed.recentPlaylists,
      NeteaseFeed.recentPodcasts,
    }.contains(feed);
    final data = NeteaseMusicRepository.object(payload['data']);
    if (feed == NeteaseFeed.historyDates) {
      final dates = data['dates'] ?? payload['dates'];
      return NeteaseBatch(
        dates is List
            ? dates
                  .map(
                    (d) => NeteaseItem(
                      id: d is Map ? '${d['date']}' : '$d',
                      name: d is Map ? '${d['date']}' : '$d',
                      kind: NeteaseEntity.date,
                    ),
                  )
                  .toList()
            : [],
      );
    }
    final raw = switch (feed) {
      NeteaseFeed.categories => payload['sub'],
      NeteaseFeed.artists => NeteaseMusicRepository.object(
        payload['list'],
      )['artists'],
      NeteaseFeed.recommended => payload['result'],
      NeteaseFeed.week => payload['weekData'],
      NeteaseFeed.allTime => payload['allData'],
      NeteaseFeed.podcastCategories => payload['categories'],
      NeteaseFeed.podcastPrograms => payload['programs'],
      NeteaseFeed.podcastToday => data['list'] ?? payload['data'],
      NeteaseFeed.recommendedPrograms => payload['result'],
      NeteaseFeed.historySongs => data['songs'],
      NeteaseFeed.artistSongs => payload['songs'],
      NeteaseFeed.artistNewSongs => data['newWorks'] ?? payload['data'],
      NeteaseFeed.follows => payload['follow'],
      NeteaseFeed.followers => payload['followeds'],
      NeteaseFeed.recommendedMvs ||
      NeteaseFeed.privateContent ||
      NeteaseFeed.recommendedSongs => payload['result'],
      _ when recent => NeteaseMusicRepository.object(payload['data'])['list'],
      _ =>
        payload['playlists'] ??
            payload['albums'] ??
            payload['hotAlbums'] ??
            payload['artists'] ??
            payload['mvs'] ??
            payload['djRadios'] ??
            payload['djRadioList'] ??
            payload['data'],
    };
    var rows = NeteaseMusicRepository.rows(raw);
    if (feed == NeteaseFeed.artistNewSongs) {
      rows = [
        for (final row in rows)
          if (row['songLists'] is List)
            ...NeteaseMusicRepository.rows(row['songLists'])
          else
            row,
      ];
    }
    if (feed == NeteaseFeed.intelligence) {
      rows = await music.hydrateSparseSongs(rows);
    }
    final items = rows
        .map(
          (r) => parse(
            recent ? NeteaseMusicRepository.object(r['data']) : r,
            kind,
            cloud: feed == NeteaseFeed.cloud,
            cloudOwner: music.api.session?.userId ?? '',
          ),
        )
        .toList();
    // Fixed-size upstream collections must not be fetched repeatedly as pages.
    final fixed = {
      NeteaseFeed.recommended,
      NeteaseFeed.categories,
      NeteaseFeed.artists,
      NeteaseFeed.week,
      NeteaseFeed.allTime,
      NeteaseFeed.similarArtists,
      NeteaseFeed.similarMvs,
      NeteaseFeed.intelligence,
    };
    fixed.addAll({
      NeteaseFeed.podcasts,
      NeteaseFeed.podcastCategories,
      NeteaseFeed.podcastPersonal,
      NeteaseFeed.recommendedPrograms,
      NeteaseFeed.historySongs,
      NeteaseFeed.recommendedMvs,
      NeteaseFeed.privateContent,
      NeteaseFeed.newestAlbums,
      NeteaseFeed.recommendedSongs,
    });
    final cursor =
        int.tryParse('${data['lastTimestamp']}') ??
        (rows.isEmpty
            ? before
            : int.tryParse('${rows.last['updateTime']}') ?? before);
    return NeteaseBatch(
      items,
      more:
          !recent &&
          !fixed.contains(feed) &&
          (payload['hasMore'] == true ||
              payload['more'] == true ||
              (payload['hasMore'] == null &&
                  payload['more'] == null &&
                  rows.length >= 30)),
      cursor: cursor,
    );
  }

  static NeteaseItem parse(
    Map<String, dynamic> r,
    NeteaseEntity kind, {
    bool cloud = false,
    String cloudOwner = '',
  }) {
    if (r['program'] is Map) r = NeteaseMusicRepository.object(r['program']);
    if (r['djRadio'] is Map) r = NeteaseMusicRepository.object(r['djRadio']);
    if (kind == NeteaseEntity.program) {
      final main = NeteaseMusicRepository.object(r['mainSong']);
      final radio = NeteaseMusicRepository.object(r['radio']);
      final dj = NeteaseMusicRepository.object(r['dj']);
      final songId = '${main['id'] ?? ''}';
      return NeteaseItem(
        id: '${r['id']}',
        name: '${r['name'] ?? ''}',
        kind: kind,
        cover: '${r['coverUrl'] ?? radio['picUrl'] ?? ''}',
        subtitle: '${dj['nickname'] ?? radio['name'] ?? ''}',
        track: RegExp(r'^\d+$').hasMatch(songId)
            ? Track(
                id: 'netease_$songId',
                title: '${r['name'] ?? main['name'] ?? ''}',
                artist: '${dj['nickname'] ?? ''}',
                album: '${radio['name'] ?? ''}',
                duration: Duration(
                  milliseconds:
                      int.tryParse('${r['duration'] ?? main['duration']}') ?? 0,
                ),
                audioAsset: 'mesting-platform://netease/$songId',
                coverAsset: '${r['coverUrl'] ?? ''}',
                lyricsAsset: '',
                source: TrackSource.netease,
                provider: '网易云播客',
                platformSongId: songId,
                externalUrl: 'https://music.163.com/#/program?id=${r['id']}',
              )
            : null,
      );
    }
    final song = neteaseSongMetadata(r);
    var track = kind == NeteaseEntity.song
        ? NeteaseMusicRepository.track(song)
        : null;
    if (cloud && track == null) {
      track = NeteaseMusicRepository.track({
        'id': r['songId'],
        'name': r['songName'] ?? r['fileName'],
        'ar': [
          {'name': r['artist']},
        ],
        'al': {'name': r['album']},
      });
    }
    if (cloud && track != null && cloudOwner.isNotEmpty) {
      track = track.copyWith(
        lyricsAsset: Uri(
          scheme: 'mesting-lyrics',
          host: 'netease',
          path: '/${track.platformSongId}',
          queryParameters: {'cloudUid': cloudOwner},
        ).toString(),
      );
    }
    final artist = NeteaseMusicRepository.object(r['artist']);
    if (kind == NeteaseEntity.artist) {
      LocalMusicDiagnostics.record('artist.cover_schema', {
        'fields': {
          for (final key in [
            'picUrl',
            'img1v1Url',
            'coverImgUrl',
            'coverUrl',
            'avatarUrl',
            'cover',
          ])
            key: r[key]?.runtimeType.toString(),
        },
        'image': LocalMusicDiagnostics.artwork(
          firstArtworkUri([r['picUrl'], r['img1v1Url'], r['coverImgUrl']]),
        ),
      });
    }
    final creators = NeteaseMusicRepository.rows(r['artists'] ?? r['creator']);
    return NeteaseItem(
      id: kind == NeteaseEntity.category
          ? '${r['name']}'
          : (track?.platformSongId ??
                '${r['id'] ?? r['vid'] ?? r['userId'] ?? r['songId'] ?? ''}'),
      name:
          track?.title ??
          NeteaseMusicRepository.clean(
            r['name'] ?? r['nickname'] ?? r['title'],
          ),
      kind: kind,
      track: track,
      cover: track?.coverAsset ?? neteaseArtwork(r),
      subtitle:
          track?.artist ??
          NeteaseMusicRepository.clean(
            r['artistName'] ??
                artist['name'] ??
                (creators.isNotEmpty
                    ? creators
                          .map((e) => e['name'] ?? e['userName'])
                          .join(' / ')
                    : r['description']),
          ),
    );
  }

  Future<void> subscribe(NeteaseItem item, bool value) async {
    final route = switch (item.kind) {
      NeteaseEntity.album => '/album/sub',
      NeteaseEntity.artist => '/artist/sub',
      NeteaseEntity.mv => '/mv/sub',
      NeteaseEntity.playlist => '/playlist/subscribe',
      NeteaseEntity.podcast => '/dj/sub',
      _ => throw const MusicPlatformException('此内容不支持收藏'),
    };
    await music.call(route, {'id': item.id, 'subscribe': value});
  }

  Future<bool> subscribed(NeteaseItem item) async {
    if (item.kind == NeteaseEntity.playlist) {
      return NeteaseMusicRepository.object(
            (await music.call('/playlist/detail', {'id': item.id}))['playlist'],
          )['subscribed'] ==
          true;
    }
    if (item.kind == NeteaseEntity.podcast) {
      return NeteaseMusicRepository.object(
            (await music.call('/dj/detail', {'id': item.id}))['djRadio'],
          )['subed'] ==
          true;
    }
    if (item.kind == NeteaseEntity.album) {
      return (await music.call('/album/detail/dynamic', {
            'id': item.id,
          }))['isSub'] ==
          true;
    }
    final feed = item.kind == NeteaseEntity.artist
        ? NeteaseFeed.likedArtists
        : NeteaseFeed.likedMvs;
    for (var page = 1; ; page++) {
      final batch = await load(feed, page: page);
      if (batch.items.any((i) => i.id == item.id)) return true;
      if (!batch.more || batch.items.isEmpty) return false;
    }
  }

  Future<String> signIn() async {
    final result = await music.api.call(
      '/daily_signin',
      query: {'type': 0},
      expectedCredential: music.credential,
      allowBusinessError: true,
    );
    if (result['code'] == 200) {
      return '网易云签到成功${result['point'] == null ? '' : '，获得 ${result['point']} 积分'}';
    }
    if (result['code'] == -2) return '网易云今日已签到';
    throw MusicPlatformException(
      '${result['message'] ?? result['msg'] ?? '网易云签到未完成，请稍后重试'}',
    );
  }
}
