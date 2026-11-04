import 'dart:convert';
import '../../../shared/models/track.dart';
import '../data/music_platform_api.dart';
import '../data/platform_category_search.dart';
import '../data/platform_explore.dart';
import '../data/platform_search_repository.dart';
import '../domain/platform_audio_quality.dart';
import 'netease_api.dart';
import '../domain/platform_search_user.dart';

/// NetEase DTOs stop here. Existing pages, bottom controls and search fields use
/// the same Track / catalogue models as Kugou, with provider-qualified IDs.
class NeteaseMusicRepository {
  NeteaseMusicRepository(this.api) : credential = api.session?.credentialId;
  final NeteaseApi api;
  final String? credential;

  /// `startplay` updates recent plays; the separate `play` event carries only
  /// actual elapsed seconds. A 200 response is receipt, not proof of indexing.
  /// Contract evidence: api-enhanced issue 167 and Kumone's recent-play fix.
  Future<Map<String, dynamic>> reportPlayback({
    required String id,
    required bool started,
    int seconds = 0,
    String sourceId = '0',
  }) => api.request(
    '/api/feedback/weblog',
    {
      'logs': jsonEncode([
        {
          'action': started ? 'startplay' : 'play',
          'json': {
            'id': id,
            'type': 'song',
            'mainsite': '1',
            'mainsiteWeb': '1',
            'content': 'id=$sourceId',
            if (!started) ...{
              'time': seconds,
              'end': 'playend',
              'wifi': 0,
              'download': 0,
              'source': 'list',
              'sourceId': sourceId,
            },
          },
        },
      ]),
    },
    playbackLog: true,
    expectedCredential: credential,
  );

  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) => api.call(
    route,
    query: query,
    expectedCredential: credential,
    abortTrigger: abort,
  );

  static Map<String, dynamic> object(Object? value) =>
      MusicPlatformApi.objectMap(value);
  static List<Map<String, dynamic>> rows(Object? value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];
  static String clean(Object? value) =>
      PlatformCategorySearchRepository.clean(value);
  static String songId(String value) {
    final id = value.startsWith('netease_') ? value.substring(8) : value;
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      throw const MusicPlatformException('网易云歌曲标识无效');
    }
    return id;
  }

  static Track? track(Map<String, dynamic> row) {
    final id = '${row['id'] ?? ''}';
    if (!RegExp(r'^\d+$').hasMatch(id)) return null;
    final album = object(row['al'] ?? row['album']);
    final artists = rows(row['ar'] ?? row['artists']);
    return Track(
      id: 'netease_$id',
      title: clean(row['name']),
      artist: artists
          .map((a) => clean(a['name']))
          .where((s) => s.isNotEmpty)
          .join(' / '),
      album: clean(album['name']),
      duration: Duration(
        milliseconds: int.tryParse('${row['dt'] ?? row['duration'] ?? 0}') ?? 0,
      ),
      audioAsset: 'mesting-platform://netease/$id',
      coverAsset: '${album['picUrl'] ?? row['picUrl'] ?? ''}',
      lyricsAsset: 'mesting-lyrics://netease/$id',
      source: TrackSource.netease,
      provider: '网易云音乐',
      platformSongId: id,
      externalUrl: 'https://music.163.com/#/song?id=$id',
      availabilityMessage: '点击获取网易云播放地址',
    );
  }

  static List<Track> tracks(Object? values) =>
      rows(values).map(track).whereType<Track>().toList();

  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abort,
  }) async {
    final result = object(
      (await call('/search', {
        'keywords': query,
        'offset': (page - 1) * 30,
      }, abort))['result'],
    );
    final values = rows(result['songs']);
    final total = int.tryParse('${result['songCount']}');
    return PlatformSearchPage(
      tracks(values),
      total,
      total == null ? values.length >= 30 : page * 30 < total,
    );
  }

  Future<PlatformCategoryPage> category(
    String query,
    PlatformSearchKind kind, {
    int page = 1,
    Future<void>? abort,
  }) async {
    final (type, field, count) = switch (kind) {
      PlatformSearchKind.albums => (10, 'albums', 'albumCount'),
      PlatformSearchKind.artists => (100, 'artists', 'artistCount'),
      PlatformSearchKind.playlists => (1000, 'playlists', 'playlistCount'),
      PlatformSearchKind.lyrics => (1006, 'songs', 'songCount'),
      PlatformSearchKind.users => (1002, 'userprofiles', 'userprofileCount'),
      _ => (1, 'songs', 'songCount'),
    };
    final result = object(
      (await call('/search', {
        'keywords': query,
        'type': type,
        'offset': (page - 1) * 30,
        'limit': 30,
      }, abort))['result'],
    );
    final values = rows(result[field]);
    final items = values
        .map((row) {
          if (kind == PlatformSearchKind.users) {
            final user = PlatformSearchUser.fromNetease(row);
            return PlatformSearchHit(
              kind: kind,
              id: user.id,
              title: user.nickname,
              subtitle: user.signature,
              cover: user.avatar,
              user: user,
            );
          }
          final song =
              kind == PlatformSearchKind.lyrics ||
                  kind == PlatformSearchKind.songs
              ? track(row)
              : null;
          final creator = object(row['creator'] ?? row['artist']);
          final lyric = row['lyrics'];
          return PlatformSearchHit(
            kind: kind,
            id: song?.id ?? '${row['id']}',
            globalId: '${row['id']}',
            title: song?.title ?? clean(row['name']),
            subtitle:
                song?.artist ?? clean(creator['nickname'] ?? creator['name']),
            cover:
                song?.coverAsset ??
                '${row['coverImgUrl'] ?? row['picUrl'] ?? row['img1v1Url'] ?? ''}',
            count: int.tryParse('${row['trackCount']}'),
            track: song,
            lyric: lyric is List ? lyric.map(clean).join('\n') : clean(lyric),
          );
        })
        .where(
          (hit) =>
              kind != PlatformSearchKind.users ||
              RegExp(r'^[1-9][0-9]*$').hasMatch(hit.id),
        )
        .toList();
    final total = int.tryParse('${result[count]}');
    return PlatformCategoryPage(
      items,
      total,
      total == null ? values.length >= 30 : page * 30 < total,
    );
  }

  Future<List<Track>> daily() async {
    final value = await call('/recommend/songs');
    return tracks(object(value['data'])['dailySongs'] ?? value['recommend']);
  }

  Future<List<Track>> newSongs() async =>
      tracks((await call('/top/song'))['data']);
  Future<List<Track>> fm() async =>
      tracks((await call('/personal/fm'))['data']);
  Future<List<Map<String, dynamic>>> featured() async {
    final payload = await call('/recommend/resource');
    return rows(payload['recommend'])
        .map(
          (r) => <String, dynamic>{
            'global_collection_id': '${r['id']}',
            'name': r['name'],
            'pic': r['picUrl'],
            'sizable_cover': r['picUrl'],
            'intro': r['copywriter'],
          },
        )
        .toList();
  }

  /// Detail can omit track objects for large lists. Rehydrate every returned ID
  /// in bounded batches, keeping the server's order and avoiding a silent cut.
  Future<List<Track>> playlist(String id) async {
    final playlist = object(
      (await call('/playlist/detail', {'id': id}))['playlist'],
    );
    final ids = rows(playlist['trackIds']).map((e) => '${e['id']}').toList();
    if (ids.isEmpty) return tracks(playlist['tracks']);
    final known = {
      for (final t in tracks(playlist['tracks'])) t.platformSongId: t,
    };
    final missing = ids.where((id) => !known.containsKey(id)).toList();
    for (var i = 0; i < missing.length; i += 500) {
      final end = (i + 500).clamp(0, missing.length);
      final payload = await call('/song/detail', {
        'ids': missing.sublist(i, end),
      });
      for (final t in tracks(payload['songs'])) {
        known[t.platformSongId] = t;
      }
    }
    return ids.map((id) => known[id]).whereType<Track>().toList();
  }

  Future<List<Track>> categoryTracks(PlatformSearchHit hit) async {
    if (hit.kind == PlatformSearchKind.playlists) return playlist(hit.globalId);
    final payload = await call(
      hit.kind == PlatformSearchKind.artists ? '/artist' : '/album',
      {'id': hit.id},
    );
    return tracks(payload['hotSongs'] ?? payload['songs']);
  }

  Future<List<PlatformExploreItem>> explore(
    PlatformExploreKind kind, {
    int page = 1,
  }) async {
    final route = switch (kind) {
      PlatformExploreKind.rank => '/toplist',
      PlatformExploreKind.album => '/album/new',
      _ => '/top/playlist',
    };
    final payload = await call(route, {'offset': (page - 1) * 30});
    final values = rows(
      payload['list'] ?? payload['albums'] ?? payload['playlists'],
    );
    return values
        .map(
          (r) => PlatformExploreItem(
            id: '${r['id']}',
            title: clean(r['name']),
            cover: '${r['coverImgUrl'] ?? r['picUrl'] ?? ''}',
            kind: kind,
            subtitle: clean(r['description'] ?? object(r['artist'])['name']),
          ),
        )
        .toList();
  }

  Future<List<Track>> exploreTracks(PlatformExploreItem item) async {
    if (item.kind != PlatformExploreKind.album) return playlist(item.id);
    return tracks((await call('/album', {'id': item.id}))['songs']);
  }

  Future<Set<PlatformAudioQuality>> qualities(String id) async {
    final payload = await call('/song/detail', {
      'ids': [songId(id)],
    });
    final values = rows(payload['songs']);
    if (values.isEmpty) throw const MusicPlatformException('暂未获取网易云音质信息');
    final row = values.first;
    bool has(String key) {
      final resource = object(row[key]);
      return resource.isNotEmpty &&
          (int.tryParse('${resource['size']}') ??
                  int.tryParse('${resource['br']}') ??
                  0) >
              0;
    }

    return {
      if (has('l') || has('h')) PlatformAudioQuality.standard,
      if (has('h')) PlatformAudioQuality.high,
      if (has('sq')) PlatformAudioQuality.lossless,
      if (has('hr')) PlatformAudioQuality.hiRes,
      if (has('m')) PlatformAudioQuality.higher,
      if (has('je')) PlatformAudioQuality.jyEffect,
      if (has('sk')) PlatformAudioQuality.sky,
      if (has('jm')) PlatformAudioQuality.jyMaster,
      if (has('db')) PlatformAudioQuality.dolby,
      if (has('vivid')) PlatformAudioQuality.vivid,
    };
  }

  Future<Track> resolve(
    Track track,
    PlatformAudioQuality quality, {
    bool requireQuality = false,
    Future<void>? abortTrigger,
  }) async {
    if (track.source != TrackSource.netease) return track;
    if (api.session == null) throw const MusicPlatformException('请先登录网易云账号');
    final level = quality.neteaseLevel;
    final payload = await call('/song/url', {
      'id': songId(track.id),
      'level': level,
    }, abortTrigger);
    final values = rows(payload['data']);
    final row = values.isEmpty ? <String, dynamic>{} : values.first;
    final url = '${row['url'] ?? ''}';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const MusicPlatformException('网易云暂未提供播放权限，请核对账号会员或版权范围');
    }
    final delivered =
        PlatformAudioQuality.fromNeteaseLevel(row['level'])?.code ?? '';
    if (requireQuality && delivered != quality.code) {
      throw const MusicPlatformException('网易云未返回所选音质，已保留原音源');
    }
    final deliveredMs = int.tryParse('${row['time']}') ?? 0;
    final preview =
        row['freeTrialInfo'] is Map ||
        (deliveredMs > 0 &&
            deliveredMs <= 90000 &&
            track.duration.inMilliseconds > deliveredMs + 2000);
    return track.copyWith(
      audioAsset: url,
      audioHeaders: const {},
      audioBitrate: int.tryParse('${row['br']}') ?? 0,
      playbackQuality: delivered,
      isPreview: preview,
      availabilityMessage: preview ? '网易云试听片段' : '网易云音乐',
    );
  }
}
