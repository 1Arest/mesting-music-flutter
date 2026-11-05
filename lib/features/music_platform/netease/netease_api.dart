import 'dart:async';
import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'dart:convert';
import '../../../core/performance/background_json.dart';
import 'dart:math';
import 'dart:typed_data';
import '../../../core/cache/browse_response_cache.dart';
import '../../../core/cache/browse_cache_routes.dart';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../data/music_platform_api.dart';
import 'netease_crypto.dart';
import 'netease_session.dart';
import 'netease_extended_routes.dart';
import 'netease_native_transport.dart';
import 'netease_request_exception.dart';
import 'messages/netease_message_protocol.dart';

/// Embedded HTTPS transport. Only fixed upstream music hosts receive cookies;
/// no loopback process, external API deployment, or JavaScript runtime is used.
/// Route/payload contracts are pinned to @neteaseapireborn/api 4.29.7 (MIT).
class NeteaseApi {
  NeteaseApi(
    this.client, {
    String? deviceId,
    BrowseResponseCache? browseCache,
    Map<String, String> Function(Map<String, Object?>)? weapiEncoder,
  }) : deviceId = deviceId ?? newDeviceId(),
       browseCache = browseCache ?? browseResponseCache,
       _weapiEncoder = weapiEncoder ?? NeteaseCrypto.weapi;
  final BrowseResponseCache browseCache;
  // A deterministic encoder lets protocol tests decrypt the real wire request.
  // Production keeps the original cryptographic encoder and its secure entropy.
  final Map<String, String> Function(Map<String, Object?>) _weapiEncoder;
  final http.Client client;
  String deviceId;
  NeteaseSession? _session;
  final Map<String, String> _cookies = {};
  int _generation = 0;
  NeteaseSession? get session => _session;
  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  /// Request-local native candidate identity cannot mutate the account jar.
  Future<Map<String, dynamic>> reportNativePlayback({
    required Map<String, Object?> log,
    required DateTime eventTime,
    required int sequence,
    required String? expectedCredential,
  }) async {
    final generation = _generation;
    if (_session == null || _session?.credentialId != expectedCredential) {
      throw const MusicPlatformException('账号已变化，请重新操作');
    }
    final response = await NeteaseNativeTransport.send(
      client: client,
      cookies: Map.from(_cookies),
      deviceId: deviceId,
      log: log,
      eventTime: eventTime,
      sequence: sequence,
    );
    if (generation != _generation ||
        _session?.credentialId != expectedCredential) {
      throw const MusicPlatformException('账号已变化，上报结果暂不确定');
    }
    return response;
  }

  static String newDeviceId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void configure(NeteaseSession? session) {
    ++_generation;
    _session = session;
    _cookies
      ..clear()
      ..addAll(session?.cookies ?? const {});
    if (session != null) deviceId = session.deviceId;
  }

  /// Interactive login owns a private cookie jar, so QR polling or a rejected
  /// password cannot mutate an already authenticated music session.
  NeteaseApi loginClient() => NeteaseApi(client, deviceId: deviceId);

  Future<Map<String, dynamic>> call(
    String route, {
    Map<String, Object?> query = const {},
    Future<void>? abortTrigger,
    bool allowBusinessError = false,
    String? expectedCredential,
  }) async {
    final generation = _generation;
    final scope = 'netease:${_session?.userId ?? "guest"}';
    void check() {
      if (generation != _generation ||
          expectedCredential != null &&
              _session?.credentialId != expectedCredential) {
        throw const MusicPlatformException('账号已变化，请重新加载页面');
      }
    }

    Future<Map<String, dynamic>> load() => BrowseResponseCache.live(
      () => _callLive(
        route,
        query: query,
        abortTrigger: abortTrigger,
        allowBusinessError: allowBusinessError,
        expectedCredential: expectedCredential,
      ),
    );
    if (BrowseResponseCache.observing &&
        BrowseCacheRoutes.neteaseReads.contains(route)) {
      return browseCache.read(
        scope: scope,
        route: route,
        query: query,
        load: load,
        checkCurrent: check,
        requestIdentity: _session?.credentialId ?? 'guest:$generation',
      );
    }
    final result = await load();
    check();
    if (BrowseCacheRoutes.neteaseMutations.contains(route) &&
        (result['code'] == null || '${result['code']}' == '200')) {
      if (route == '/follow' || route == '/playlist/update/playcount') {
        // A relationship write does not invalidate the user's offline music
        // feed. Revalidate its reads without destroying the last good snapshot.
        browseCache.revalidateScope(scope);
      } else {
        await browseCache.invalidateScope(
          scope,
          preserveRoute: BrowseCacheRoutes.discoveryRead,
        );
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _callLive(
    String route, {
    Map<String, Object?> query = const {},
    Future<void>? abortTrigger,
    bool allowBusinessError = false,
    String? expectedCredential,
  }) {
    Object? q(String key, [Object? fallback]) => query[key] ?? fallback;
    var weapi = false;
    late String path;
    late Map<String, Object?> data;
    switch (route) {
      case '/login/qr/key':
        path = '/api/login/qrcode/unikey';
        data = {'type': 3};
      case '/login/qr/check':
        path = '/api/login/qrcode/client/login';
        data = {'key': q('key'), 'type': 3};
      case '/login/cellphone':
        path = '/api/w/login/cellphone';
        data = {
          'type': '1',
          'https': 'true',
          'phone': q('phone'),
          'countrycode': q('countrycode', '86'),
          'remember': 'true',
          if (q('captcha') != null)
            'captcha': q('captcha')
          else
            'password': md5
                .convert(utf8.encode('${q('password', '')}'))
                .toString(),
        };
      case '/login':
        path = '/api/w/login';
        data = {
          'type': '0',
          'https': 'true',
          'username': q('email'),
          'password': md5
              .convert(utf8.encode('${q('password', '')}'))
              .toString(),
          'rememberLogin': 'true',
        };
      case '/captcha/sent':
        path = '/api/sms/captcha/sent';
        weapi = true;
        data = {
          'ctcode': q('countrycode', '86'),
          'secrete': 'music_middleuser_pclogin',
          'cellphone': q('phone'),
        };
      case '/login/status':
        path = '/api/w/nuser/account/get';
        data = {};
        weapi = true;
      case '/search':
        path = '/api/cloudsearch/pc';
        data = {
          's': q('keywords'),
          'type': q('type', 1),
          'limit': q('limit', 30),
          'offset': q('offset', 0),
          'total': true,
        };
      case '/search/hot':
        path = '/api/hotsearchlist/get';
        data = {};
        weapi = true;
      case '/recommend/songs':
        path = '/api/v3/discovery/recommend/songs';
        data = {};
        weapi = true;
      case '/recommend/resource':
        path = '/api/v1/discovery/recommend/resource';
        data = {};
        weapi = true;
      case '/personal/fm':
        path = '/api/v1/radio/get';
        data = {};
        weapi = true;
      case '/fm/trash':
        path = '/api/radio/trash/add';
        data = {'songId': q('id'), 'time': q('time', 0)};
        weapi = true;
      case '/top/song':
        path = '/api/v1/discovery/new/songs';
        data = {'areaId': q('type', 0), 'total': true};
        weapi = true;
      case '/top/playlist':
        path = '/api/playlist/list';
        data = {
          'cat': q('cat', '全部'),
          'order': q('order', 'hot'),
          'limit': q('limit', 30),
          'offset': q('offset', 0),
          'total': true,
        };
        weapi = true;
      case '/toplist':
        path = '/api/toplist';
        data = {};
        weapi = true;
      case '/album/new':
        path = '/api/album/new';
        data = {
          'area': q('area', 'ALL'),
          'limit': q('limit', 30),
          'offset': q('offset', 0),
          'total': true,
        };
        weapi = true;
      case '/album':
        path = '/api/v1/album/${q('id')}';
        data = {};
        weapi = true;
      case '/artist':
      case '/artists':
        path = '/api/v1/artist/${q('id')}';
        data = {};
        weapi = true;
      case '/user/playlist':
        path = '/api/user/playlist';
        weapi = true;
        data = {
          'uid': q('uid'),
          'limit': q('limit', 100),
          'offset': q('offset', 0),
          'includeVideo': true,
        };
      case '/playlist/detail':
        path = '/api/v6/playlist/detail';
        data = {'id': q('id'), 'n': q('n', 100000), 's': 0};
      case '/song/detail':
        path = '/api/v3/song/detail';
        weapi = true;
        final ids = (q('ids') as List)
            .map((id) => {'id': int.parse('$id')})
            .toList();
        data = {'c': jsonEncode(ids)};
      case '/song/url':
        path = '/api/song/enhance/player/url/v1';
        data = {
          'ids': jsonEncode([int.parse('${q('id')}')]),
          'level': q('level', 'standard'),
          'encodeType': q('level') == 'vivid' ? 'mp3' : 'flac',
          if (q('level') == 'sky') 'immerseType': 'c51',
        };
      case '/lyric':
        path = '/api/song/lyric/v1';
        data = {
          'id': q('id'),
          'cp': false,
          'tv': 0,
          'lv': 0,
          'rv': 0,
          'kv': 0,
          'yv': 0,
          'ytv': 0,
          'yrv': 0,
        };
      case '/like':
        path = '/api/radio/like';
        weapi = true;
        data = {
          'alg': 'itembased',
          'trackId': q('id'),
          'like': q('like', true),
          'time': 3,
        };
      case '/likelist':
        path = '/api/song/like/get';
        data = {'uid': q('uid')};
        weapi = true;
      case '/playlist/create':
        path = '/api/playlist/create';
        data = {'name': q('name'), 'privacy': 0, 'type': 'NORMAL'};
        weapi = true;
      case '/playlist/tracks':
        path = '/api/playlist/manipulate/tracks';
        data = {
          'pid': q('id'),
          'op': q('op'),
          'trackIds': jsonEncode(q('ids')),
          'imme': 'true',
        };
      case '/playlist/subscribe':
        path =
            '/api/playlist/${q('subscribe') == true ? 'subscribe' : 'unsubscribe'}';
        data = {'id': q('id')};
        weapi = true;
      case '/playlist/delete':
        path = '/api/playlist/remove';
        data = {
          'ids': jsonEncode([int.parse('${q('id')}')]),
        };
        weapi = true;
      case '/playlist/update':
        path = '/api/batch';
        data = {
          '/api/playlist/desc/update': jsonEncode({
            'id': int.parse('${q('id')}'),
            'desc': q('description', ''),
          }),
          '/api/playlist/update/name': jsonEncode({
            'id': int.parse('${q('id')}'),
            'name': q('name'),
          }),
        };
      case '/user/detail':
        path = '/api/v1/user/detail/${q('uid')}';
        data = {};
        weapi = true;
      case '/user/update':
        path = '/api/user/profile/update';
        data = Map<String, Object?>.of(query);
      case '/mv/detail':
        path = '/api/v1/mv/detail';
        data = {'id': q('id')};
        weapi = true;
      case '/mv/url':
        path = '/api/song/enhance/play/mv/url';
        data = {'id': q('id'), 'r': q('r', 1080)};
        weapi = true;
      case '/playlist/reorder':
        path = '/api/playlist/manipulate/tracks';
        data = {
          'pid': q('id'),
          'op': 'update',
          'trackIds': jsonEncode(q('ids')),
        };
      case '/comment/new':
        path = '/api/v2/resource/comments';
        final page = int.tryParse('${q('page', 1)}') ?? 1;
        final hot = q('hot') == true;
        final sortType = q('sortType', hot ? 2 : 99);
        data = {
          'threadId': q('threadId'),
          'pageNo': page,
          'pageSize': 30,
          'showInner': true,
          'sortType': sortType,
          'cursor': sortType == 3
              ? q('cursor', '0')
              : sortType == 2
              ? 'normalHot#${(page - 1) * 30}'
              : (page - 1) * 30,
        };
      case '/comment/floor':
        path = '/api/resource/comment/floor/get';
        weapi = true;
        data = {
          'threadId': q('threadId'),
          'parentCommentId': q('parentId'),
          'time': q('time', -1),
          'limit': 30,
        };
      case '/comment/write':
        final action = '${q('action')}';
        if (!{'add', 'delete', 'reply'}.contains(action)) {
          throw ArgumentError('Invalid comment action');
        }
        path = '/api/resource/comments/$action';
        weapi = true;
        data = {
          'threadId': q('threadId'),
          if (action != 'add') 'commentId': q('commentId'),
          if (action != 'delete') 'content': q('content'),
        };
      default:
        final contract = neteaseExtendedRoute(route, query);
        if (contract == null) {
          throw ArgumentError.value(
            route,
            'route',
            'Unknown embedded NetEase route',
          );
        }
        path = contract.path;
        data = contract.data;
        weapi = contract.weapi;
    }
    return request(
      path,
      data,
      weapi: weapi,
      abortTrigger: abortTrigger,
      allowBusinessError: allowBusinessError,
      expectedCredential: expectedCredential,
    );
  }

  /// Native port of the upstream NOS image upload. The upload token is sent
  /// only to its fixed NOS host; music cookies never leave the music hosts.
  Future<String> uploadAvatar(Uint8List bytes, String credential) async {
    final generation = _generation;
    if (_session?.credentialId != credential) {
      throw const MusicPlatformException('账号已变化，请重新打开个人资料');
    }
    final png = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final extension = png ? 'png' : 'jpg';
    final allocated = await request(
      '/api/nos/token/alloc',
      {
        'bucket': 'yyimgs',
        'ext': extension,
        'filename': 'avatar.$extension',
        'local': false,
        'nos_product': 0,
        'type': 'other',
        'return_body': r'{"code":200,"size":"$(ObjectSize)"}',
      },
      weapi: true,
      expectedCredential: credential,
    );
    final data = MusicPlatformApi.objectMap(allocated['result']);
    final key = '${data['objectKey'] ?? ''}', token = '${data['token'] ?? ''}';
    if (key.isEmpty || token.isEmpty || data['docId'] == null) {
      throw const MusicPlatformException('网易云未返回头像上传凭证');
    }
    if (generation != _generation) {
      throw const MusicPlatformException('账号已变化，请重试');
    }
    final req =
        http.Request(
            'POST',
            Uri.https('nosup-hz1.127.net', '/yyimgs/$key', {
              'offset': '0',
              'complete': 'true',
              'version': '1.0',
            }),
          )
          ..followRedirects = false
          ..headers.addAll({
            'x-nos-token': token,
            'Content-Type': png ? 'image/png' : 'image/jpeg',
          })
          ..bodyBytes = bytes;
    final response = await client
        .send(req)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 30));
    if (generation != _generation || response.statusCode != 200) {
      throw const MusicPlatformException('头像上传未完成，请重新打开个人资料确认');
    }
    await request('/api/user/avatar/upload/v1', {
      'imgid': data['docId'],
    }, expectedCredential: credential);
    return Uri.https('p1.music.126.net', '/$key').toString();
  }

  /// No automatic retries: a timeout after a write is not proof it was rejected.
  /// Capture the account generation before I/O and reject responses after a
  /// platform switch, including public searches and QR-independent requests.
  Future<Map<String, dynamic>> request(
    String path,
    Map<String, Object?> data, {
    bool weapi = false,
    Future<void>? abortTrigger,
    bool allowBusinessError = false,
    String? expectedCredential,
    Map<String, String> additionalHeaders = const {},
    bool playbackLog = false,
    bool mobileMessages = false,
  }) {
    final generation = _generation;
    void check() {
      if (generation != _generation ||
          expectedCredential != null &&
              _session?.credentialId != expectedCredential) {
        throw const MusicPlatformException('账号已变化，请重新加载页面');
      }
    }

    Future<Map<String, dynamic>> load() => _requestLive(
      path,
      data,
      weapi: weapi,
      abortTrigger: abortTrigger,
      allowBusinessError: allowBusinessError,
      expectedCredential: expectedCredential,
      additionalHeaders: additionalHeaders,
      playbackLog: playbackLog,
      mobileMessages: mobileMessages,
    );
    if (!mobileMessages &&
        BrowseResponseCache.observing &&
        BrowseCacheRoutes.neteaseRaw(path)) {
      return browseCache.read(
        scope: 'netease:${_session?.userId ?? "guest"}',
        route: path,
        query: data,
        load: load,
        checkCurrent: check,
        requestIdentity: _session?.credentialId ?? 'guest:$generation',
      );
    }
    return load();
  }

  Future<Map<String, dynamic>> _requestLive(
    String path,
    Map<String, Object?> data, {
    bool weapi = false,
    Future<void>? abortTrigger,
    bool allowBusinessError = false,
    String? expectedCredential,
    Map<String, String> additionalHeaders = const {},
    bool playbackLog = false,
    bool mobileMessages = false,
  }) async {
    if (!path.startsWith('/api/') ||
        path.contains('?') ||
        path.contains('..')) {
      throw ArgumentError('Invalid NetEase protocol path');
    }
    if (playbackLog && (path != '/api/feedback/weblog' || weapi)) {
      throw ArgumentError(
        'Playback logging requires the fixed eapi weblog path',
      );
    }
    if (mobileMessages &&
        (weapi ||
            !{
              '/api/msg/private/users',
              '/api/msg/private/history',
            }.contains(path))) {
      throw ArgumentError(
        'Mobile message identity is limited to private-message reads',
      );
    }
    final generation = _generation;
    if (expectedCredential != null &&
        _session?.credentialId != expectedCredential) {
      throw const MusicPlatformException('账号已变化，请返回后重新操作');
    }
    final csrf = _cookies['__csrf'] ?? '';
    final cookie = <String, String>{
      'os': 'pc',
      'appver': '3.1.3.203419',
      'osver': 'Microsoft-Windows-10-Professional-build-19045-64bit',
      'deviceId': deviceId,
      '__remember_me': 'true',
      ..._cookies,
      // Desktop history can contain only a compatibility sentence for mobile
      // cards. The modern Android client version is request-local; no login,
      // cookie jar or send operation adopts this identity.
      if (mobileMessages) ...{
        'os': 'android',
        'appver': NeteaseMessageProtocol.appVersion,
        'osver': NeteaseMessageProtocol.osVersion,
      },
      // This request-local client identity is required by the upstream vivid
      // stream contract; it never mutates the retained account cookie jar.
      if (path == '/api/song/enhance/player/url/v1' &&
          data['level'] == 'vivid') ...{
        'os': 'android',
        'appver': '9.5.61',
      },
      // Only the logging request uses the desktop logging contract. Do not
      // change the account jar or other requests' client identity.
      if (playbackLog) ...{
        'os': 'osx',
        'appver': '3.1.10.5100',
        'osver': '15.5',
        'channel': 'netease',
      },
    };
    final header = <String, String>{
      ...cookie,
      'versioncode': mobileMessages
          ? NeteaseMessageProtocol.versionCode
          : '140',
      'resolution': mobileMessages ? '1080x2400' : '1920x1080',
      'buildver': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'channel': 'netease',
      'requestId':
          '${DateTime.now().millisecondsSinceEpoch}_${Random.secure().nextInt(10000)}',
      '__csrf': csrf,
    };
    final payload = weapi
        ? {...data, 'csrf_token': csrf}
        : {...data, 'header': header, 'e_r': false};
    final encoded = weapi
        ? _weapiEncoder(payload)
        : NeteaseCrypto.eapi(path, payload);
    final uri = Uri.https(
      playbackLog
          ? 'clientlog.music.163.com'
          : weapi
          ? 'music.163.com'
          : 'interface.music.163.com',
      '/${weapi ? 'weapi' : 'eapi'}/${path.substring(5)}',
    );
    http.AbortableRequest buildRequest(Future<void> abort) {
      if (generation != _generation ||
          expectedCredential != null &&
              _session?.credentialId != expectedCredential) {
        throw const MusicPlatformException('账号已变化，请重新加载页面');
      }
      final req = http.AbortableRequest('POST', uri, abortTrigger: abort)
        ..followRedirects = false
        ..headers.addAll({
          'Referer': 'https://music.163.com/',
          'User-Agent': playbackLog
              ? 'NeteaseMusic/3.1.10.5100 (Macintosh; OS X 15.5)'
              : weapi
              ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36'
              : mobileMessages
              ? NeteaseMessageProtocol.userAgent
              : 'NeteaseMusic/9.0.65.240416212826(9006053); Dalvik/2.1.0',
          'Cookie': (weapi ? cookie : header).entries
              .map((e) => '${e.key}=${e.value}')
              .join('; '),
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
          if (additionalHeaders.containsKey('x-nos-token'))
            'x-nos-token': additionalHeaders['x-nos-token']!,
        })
        ..bodyFields = encoded;
      return req;
    }

    try {
      final response = await sendMusicRequest(
        client: client,
        build: buildRequest,
        platform: 'netease',
        operation: path == '/api/sms/captcha/sent'
            ? MusicNetworkOperation.sms
            : path.contains('/login')
            ? MusicNetworkOperation.login
            : path == '/api/song/enhance/player/url/v1'
            ? MusicNetworkOperation.playbackUrl
            : MusicNetworkOperation.read,
        abortTrigger: abortTrigger,
        retryRead:
            !playbackLog &&
            {
              '/api/song/enhance/player/url/v1',
              '/api/v3/song/detail',
              '/api/song/lyric/v1',
              '/api/cloudsearch/pc',
            }.contains(path),
      );
      if (generation != _generation) {
        throw const MusicPlatformException('音乐平台已切换，请重新操作');
      }
      if (response.statusCode != 200) {
        throw NeteaseRequestException(
          '网易云请求未完成（${response.statusCode}）',
          outcome: MusicNetworkOutcome.http,
          httpStatus: response.statusCode,
        );
      }
      final result = MusicPlatformApi.objectMap(
        await decodeJsonBytes(response.bodyBytes),
      );
      if (generation != _generation) {
        throw const MusicPlatformException('音乐平台已切换，请重新操作');
      }
      final code = int.tryParse('${result['code']}');
      // A write with no recognizable receipt may already have reached the
      // service. Keep it uncertain instead of claiming acceptance or retrying.
      // Other API routes retain their existing optional-code contracts.
      if (playbackLog && code == null) {
        throw const MusicPlatformException('网易云播放上报回执不完整，结果暂不确定');
      }
      if ((!allowBusinessError || playbackLog) && code != null && code != 200) {
        MusicNetworkDiagnostics.shared.record(
          platform: 'netease',
          operation: MusicNetworkOperation.other,
          outcome: MusicNetworkOutcome.business,
          status: code,
        );
        final message = switch (code) {
          301 || 302 => '网易云登录已失效，请重新登录',
          415 || 405 => '网易云需要安全验证，请使用扫码登录或稍后重试',
          460 => '网易云暂时限制了此请求，请稍后重试或使用扫码登录',
          _ => '${result['message'] ?? result['msg'] ?? '网易云请求未完成（$code）'}',
        };
        throw MusicPlatformException(message, code: '$code');
      }
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null && !playbackLog) {
        for (final item in setCookie.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
          final pair = item.split(';').first.trim();
          final at = pair.indexOf('=');
          if (at > 0) {
            final key = pair.substring(0, at), value = pair.substring(at + 1);
            if (mobileMessages &&
                {
                  'os',
                  'osver',
                  'appver',
                  'versioncode',
                  'resolution',
                }.contains(key)) {
              continue;
            }
            if (value.isEmpty) {
              _cookies.remove(key);
            } else {
              _cookies[key] = value;
            }
          }
        }
      }
      return result;
    } on MusicTransportException catch (error) {
      // Keep timeout identity for the background phase recorder. Transport
      // categories are not numeric platform rejection codes for listen logs.
      if (error.outcome == MusicNetworkOutcome.timeout) {
        throw TimeoutException(error.message);
      }
      throw NeteaseRequestException(error.message, outcome: error.outcome);
    } on FormatException {
      throw const NeteaseRequestException(
        '网易云返回格式异常，请稍后重试',
        outcome: MusicNetworkOutcome.format,
      );
    }
  }
}
