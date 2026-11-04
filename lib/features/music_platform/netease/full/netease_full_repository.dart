import 'dart:convert';
import 'dart:typed_data';
import '../../../../core/cache/browse_response_cache.dart';
import '../../../../core/cache/browse_cache_routes.dart';
import 'package:crypto/crypto.dart';
import '../netease_api.dart';
import '../netease_cloud_upload.dart';
import '../netease_music_repository.dart';
import '../../data/music_platform_api.dart';
import 'netease_catalog.dart';
import 'netease_manual_routes.dart';
import 'netease_upload_workflows.dart';

/// All new task pages share a credential snapshot. The transport rejects a
/// late response after switching platform/account; composite operations also
/// check between steps. No mutation has an automatic retry.
class NeteaseFullRepository {
  NeteaseFullRepository(this.music);
  final NeteaseMusicRepository music;
  NeteaseApi get api => music.api;
  void checkOwner() {
    if (music.credential == null ||
        api.session?.credentialId != music.credential) {
      throw const MusicPlatformException('账号已变化，请重新打开此页面');
    }
  }

  Future<Map<String, dynamic>> run(
    NeteaseEndpoint endpoint,
    Map<String, Object?> input,
  ) async {
    checkOwner();
    Future<Map<String, dynamic>> load() =>
        BrowseResponseCache.live(() => _runLive(endpoint, input));
    if (!endpoint.write &&
        BrowseResponseCache.observing &&
        BrowseCacheRoutes.neteaseReads.contains(endpoint.route)) {
      return api.browseCache.read(
        scope: 'netease:${api.session!.userId}',
        route: 'full:${endpoint.route}',
        query: input,
        load: load,
        checkCurrent: checkOwner,
        requestIdentity: music.credential ?? 'guest',
      );
    }
    final result = await load();
    if (endpoint.write &&
        BrowseCacheRoutes.neteaseMutations.contains(endpoint.route)) {
      await api.browseCache.invalidateScope('netease:${api.session!.userId}');
    }
    return result;
  }

  Future<Map<String, dynamic>> _runLive(
    NeteaseEndpoint endpoint,
    Map<String, Object?> input,
  ) async {
    checkOwner();
    if (endpoint.unavailable != null) {
      throw MusicPlatformException('平台暂不支持：${endpoint.unavailable}');
    }
    final q = Map<String, Object?>.of(input);
    q.removeWhere((key, value) => value == null || value == '');
    q.removeWhere(
      (key, _) => {
        'cookie',
        'cookies',
        'header',
        'crypto',
        'proxy',
        'domain',
        'ua',
        'realIP',
      }.contains(key),
    );
    for (final field in endpoint.parameters.where((p) => p.required)) {
      if (endpoint.route == '/voice/upload' &&
          field.key == 'coverImgId' &&
          q['imgFile'] is Uint8List) {
        continue;
      }
      if (!{
            'imgFile',
            'songFile',
            'desc',
            'signature',
            'tags',
          }.contains(field.key) &&
          (q[field.key] == null || '${q[field.key]}'.trim().isEmpty)) {
        throw MusicPlatformException('请填写${field.label}');
      }
    }
    final credential = music.credential!;
    if (endpoint.route == '/inner/version') {
      return {
        'code': 200,
        'data': {'version': '4.29.7', 'connection': 'App 直接连接网易云'},
      };
    }
    if (endpoint.route == '/login/qr/create') {
      final key = '${q['key'] ?? ''}';
      if (key.isEmpty) throw const MusicPlatformException('请先生成登录二维码');
      return {
        'code': 200,
        'data': {
          'qrurl': Uri.https('music.163.com', '/login', {
            'codekey': key,
          }).toString(),
        },
      };
    }
    if (endpoint.route == '/register/anonimous') {
      // Guest creation must never replace the current authenticated cookie jar.
      final device = NeteaseApi.newDeviceId();
      const xor = '3go8&\$8*3*3h0k(2)2';
      final encoded = String.fromCharCodes([
        for (var i = 0; i < device.length; i++)
          device.codeUnitAt(i) ^ xor.codeUnitAt(i % xor.length),
      ]);
      final digest = base64Encode(md5.convert(utf8.encode(encoded)).bytes);
      final result = await api.loginClient().request(
        '/api/register/anonimous',
        {'username': base64Encode(utf8.encode('$device $digest'))},
        weapi: true,
      );
      checkOwner();
      return _publicResult(result);
    }
    if (endpoint.route == '/avatar/upload' ||
        endpoint.route == '/playlist/cover/update') {
      final bytes = q['imgFile'];
      if (bytes is! Uint8List) throw const MusicPlatformException('请先选择图片');
      final uploader = NeteaseUploadWorkflows(api, credential);
      final imageId = await uploader.picture(bytes);
      checkOwner();
      final result = endpoint.route == '/avatar/upload'
          ? await api.request('/api/user/avatar/upload/v1', {
              'imgid': imageId,
            }, expectedCredential: credential)
          : await api.request(
              '/api/playlist/cover/update',
              {'id': q['id'], 'coverImgId': imageId},
              weapi: true,
              expectedCredential: credential,
            );
      return _publicResult(result);
    }
    if (endpoint.route == '/cloud' || endpoint.route == '/voice/upload') {
      final file = q['songFile'];
      if (file is! Map) throw const MusicPlatformException('请先选择音频文件');
      if (endpoint.route == '/cloud') {
        await NeteaseCloudUploader(
          api,
          credential,
        ).upload(Map<Object?, Object?>.from(file));
      } else {
        await NeteaseUploadWorkflows(
          api,
          credential,
        ).voice(Map<Object?, Object?>.from(file), {
          ...q,
          if (q['imgFile'] is Uint8List)
            'coverImgId': await NeteaseUploadWorkflows(
              api,
              credential,
            ).picture(q['imgFile'] as Uint8List),
        });
      }
      checkOwner();
      return {'code': 200, 'message': '上传已完成，请刷新内容列表确认'};
    }
    if (endpoint.route == '/playlist/track/all') {
      final page = await music.playlistPage(
        '${q['id']}',
        offset: int.tryParse('${q['offset']}') ?? 0,
        limit: int.tryParse('${q['limit']}') ?? 1000,
      );
      checkOwner();
      return {
        'code': 200,
        'tracks': page.items,
        'more': page.hasMore,
        'total': page.total,
        'nextOffset': page.nextOffset,
      };
    }
    if (endpoint.route == '/related/playlist') {
      final response = await api.client
          .get(Uri.https('music.163.com', '/playlist', {'id': '${q['id']}'}))
          .timeout(const Duration(seconds: 18));
      checkOwner();
      if (response.statusCode != 200) {
        throw const MusicPlatformException('相关歌单暂时无法加载');
      }
      final pattern = RegExp(
        r'<div class="cver u-cover u-cover-3">[\s\S]*?<img src="([^"]+)">[\s\S]*?<a class="sname f-fs1 s-fc0" href="([^"]+)"[^>]*>([^<]+?)</a>[\s\S]*?<a class="nm nm f-thide s-fc3" href="([^"]+)"[^>]*>([^<]+?)</a>',
      );
      return {
        'code': 200,
        'playlists': [
          for (final m in pattern.allMatches(response.body))
            {
              'id': Uri.parse(m[2]!).queryParameters['id'],
              'name': m[3],
              'coverImgUrl': m[1]!.split('?').first,
              'creator': {'nickname': m[5]},
            },
        ],
      };
    }
    if (endpoint.route == '/audio/match') {
      if ((q['audioFP']?.toString() ?? '').isEmpty) {
        throw const MusicPlatformException('请先录制一段声音');
      }
      final response = await api.client
          .get(
            Uri.https('interface.music.163.com', '/api/music/audio/match', {
              'sessionId': '0123456789abcdef',
              'algorithmCode': 'shazam_v2',
              'duration': '${q['duration'] ?? 5}',
              'rawdata': '${q['audioFP']}',
              'times': '1',
              'decrypt': '1',
            }),
          )
          .timeout(const Duration(seconds: 25));
      checkOwner();
      if (response.statusCode != 200) {
        throw const MusicPlatformException('识曲暂未完成，请重试');
      }
      return _publicResult(
        MusicPlatformApi.objectMap(jsonDecode(response.body)),
      );
    }
    if (endpoint.route == '/batch') {
      final requests = q['requests'];
      if (requests is! List || requests.isEmpty || requests.length > 20) {
        throw const MusicPlatformException('请选择1至20项内容');
      }
      final payload = <String, Object?>{};
      for (final entry in requests) {
        final route = '${(entry as Map)['route']}';
        if (!{
          '/user/account',
          '/user/level',
          '/user/subcount',
        }.contains(route)) {
          throw const MusicPlatformException('此内容暂不支持批量读取');
        }
        final contract = neteaseCompleteContract(
          route,
          Map<String, Object?>.from(entry['query'] as Map),
        );
        if (contract == null || !contract.path.startsWith('/api/')) {
          throw const MusicPlatformException('此内容暂不支持批量读取');
        }
        if (payload.containsKey(contract.path)) {
          throw const MusicPlatformException('批量内容不能重复');
        }
        payload[contract.path] = jsonEncode(contract.data);
      }
      return _publicResult(
        await api.request(
          '/api/batch',
          payload,
          expectedCredential: credential,
        ),
      );
    }
    final route = endpoint.route;
    if (route == '/playlist/update') {
      // Encode text as JSON values. The original Node template interpolates
      // quotes literally, which breaks legitimate names containing quotes.
      return _publicResult(
        await api.request('/api/batch', {
          '/api/playlist/desc/update': jsonEncode({
            'id': int.parse('${q['id']}'),
            'desc': q['desc'] ?? '',
          }),
          '/api/playlist/tags/update': jsonEncode({
            'id': int.parse('${q['id']}'),
            'tags': q['tags'] ?? '',
          }),
          '/api/playlist/update/name': jsonEncode({
            'id': int.parse('${q['id']}'),
            'name': q['name'],
          }),
        }, expectedCredential: credential),
      );
    }
    if (route == '/comment/new') {
      q['threadId'] ??=
          '${const ['R_SO_4_', 'R_MV_5_', 'A_PL_0_', 'R_AL_3_', 'A_DJ_1_', 'R_VI_62_', 'A_EV_2_', 'A_DR_14_'][(int.tryParse('${q['type']}') ?? 0).clamp(0, 7)]}${q['id']}';
      q['page'] = q['pageNo'] ?? 1;
      if (q['sortType'] != null) {
        q['sortType'] = int.tryParse('${q['sortType']}') ?? 3;
      }
    }
    if (route == '/playlist/tracks') {
      q['id'] = q['pid'] ?? q['id'];
      q['ids'] = '${q['tracks'] ?? ''}'
          .split(',')
          .where((s) => s.isNotEmpty)
          .map(int.parse)
          .toList();
    }
    final contract = neteaseCompleteContract(route, q);
    // Register/reset/SMS workflows use a private jar. A returned login cookie
    // cannot silently change the active account's request identity.
    final isolated =
        route.startsWith('/register/') || route.startsWith('/captcha/');
    final client = isolated ? api.loginClient() : api;
    final result = contract == null
        ? await client.call(
            route,
            query: q,
            expectedCredential: isolated ? null : credential,
          )
        : await client.request(
            contract.path,
            contract.data,
            weapi: contract.weapi,
            expectedCredential: isolated ? null : credential,
          );
    checkOwner();
    if (route == '/song/purchased') {
      // The bought-song endpoint may contain only songId/price records. Hydrate
      // them before presentation instead of rendering a bare "数量 0" fact or
      // dropping real purchases that do not carry a title in this response.
      final entries = NeteaseMusicRepository.rows(result['data']);
      final ids = entries
          .map((r) => '${r['songId'] ?? r['id'] ?? ''}')
          .where((id) => RegExp(r'^\d+$').hasMatch(id))
          .toSet()
          .take(500)
          .toList();
      if (ids.isNotEmpty) {
        final detail = await music.call('/song/detail', {'ids': ids});
        checkOwner();
        return _publicResult({
          ...result,
          'data': null,
          'songs': detail['songs'],
        });
      }
    }
    if ({'/song/url', '/song/url/v1', '/song/download/url'}.contains(route)) {
      final media = NeteaseMusicRepository.rows(
        result['data'] is List ? result['data'] : [result['data']],
      );
      final ids = media
          .map((m) => '${m['id'] ?? ''}')
          .where((id) => RegExp(r'^\d+$').hasMatch(id))
          .take(500)
          .toList();
      if (ids.isNotEmpty) {
        final songs = await music.call('/song/detail', {'ids': ids});
        checkOwner();
        final tracks = NeteaseMusicRepository.tracks(songs['songs']);
        result['tracks'] = [
          for (final track in tracks)
            for (final m in media)
              if ('${m['id']}' == track.platformSongId &&
                  Uri.tryParse('${m['url']}')?.hasAuthority == true)
                track.copyWith(
                  audioAsset: '${m['url']}',
                  isPreview: m['freeTrialInfo'] is Map,
                  availabilityMessage: m['freeTrialInfo'] is Map
                      ? '网易云试听片段'
                      : '网易云音乐',
                ),
        ];
      }
    }
    if (route == '/check/music') {
      final rows = NeteaseMusicRepository.rows(result['data']);
      final success =
          rows.isNotEmpty &&
          rows.first['code'] == 200 &&
          '${rows.first['url'] ?? ''}'.isNotEmpty;
      return {
        'code': 200,
        'data': {
          'playable': success,
          'message': success ? '当前账号可以播放' : '平台暂未提供完整播放权限',
        },
      };
    }
    if (route == '/verify/getQr') {
      final data = MusicPlatformApi.objectMap(result['data']);
      data['qrurl'] = Uri.https('st.music.163.com', '/encrypt-pages', {
        'qrCode': '${data['qrCode']}',
        'verifyToken': '${q['token']}',
        'verifyId': '${q['vid']}',
        'verifyType': '${q['type']}',
        'params': jsonEncode({'event_id': q['evid'], 'sign': q['sign']}),
      }).toString();
      return {'code': 200, 'data': data};
    }
    return _publicResult(result);
  }

  /// Responses used by UI never contain account cookies or request headers.
  Map<String, dynamic> _publicResult(Map<String, dynamic> result) {
    Object? scrub(Object? v) => v is Map
        ? <String, Object?>{
            for (final e in v.entries)
              if (!{
                'cookie',
                'cookies',
                'token',
                'MUSIC_U',
                'MUSIC_A',
                '__csrf',
                'password',
                'header',
              }.contains('${e.key}'))
                '${e.key}': scrub(e.value),
          }
        : v is List
        ? v.map(scrub).toList()
        : v;
    return Map<String, dynamic>.from(scrub(result) as Map);
  }
}
