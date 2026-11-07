import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'dart:async';
import '../../../core/performance/background_json.dart';
import 'dart:convert';
import '../../../core/cache/browse_response_cache.dart';
import '../../../core/cache/browse_cache_routes.dart';

import 'package:http/http.dart' as http;

import '../domain/platform_session.dart';
import 'embedded_music_server.dart';

/// Adapter for md3Music's embedded Rust routes at commit a69503b.
/// Endpoint contracts come from the AGPL upstream; see third_party/md3music.
/// Pages never construct upstream URLs or handle authentication headers.
class MusicPlatformApi {
  MusicPlatformApi({
    required MusicServer server,
    required http.Client client,
    bool Function()? sessionCurrent,
    bool Function(String path)? routeAllowed,
    BrowseResponseCache? browseCache,
  }) : _server = server,
       _client = client,
       _routeAllowed = routeAllowed ?? ((_) => true),
       _sessionCurrent = sessionCurrent ?? (() => true),
       browseCache = browseCache ?? browseResponseCache;
  final BrowseResponseCache browseCache;

  final MusicServer _server;
  final http.Client _client;
  final bool Function() _sessionCurrent;
  final bool Function(String path) _routeAllowed;
  PlatformSession? session;
  String? _dfid;
  Future<void>? _registration;

  /// Login must share the same registered device as subsequent signed requests.
  /// This coalesces initialization only; an SMS request is never auto-retried.
  Future<void> ensureRegisteredDevice() =>
      _dfid?.isNotEmpty == true ? Future.value() : registerDevice();

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String> query = const {},
    bool allowBusinessError = false,
    Future<void>? abortTrigger,
    PlatformSession? expectedSession,
  }) {
    if (!_routeAllowed(path) ||
        expectedSession?.platform == MusicPlatform.qishui ||
        session?.platform == MusicPlatform.qishui) {
      return Future.error(
        const MusicPlatformException('此入口尚未接入汽水，请使用汽水页面中的功能'),
      );
    }
    Future<Map<String, dynamic>> load() => _request(
      'GET',
      path,
      query: query,
      allowBusinessError: allowBusinessError,
      abortTrigger: abortTrigger,
      expectedSession: expectedSession,
    );
    if (!BrowseResponseCache.observing ||
        !BrowseCacheRoutes.kugouReads.contains(path)) {
      return load();
    }
    final identity = session;
    void check() {
      if (!_sessionCurrent() ||
          session?.userId != identity?.userId ||
          session?.token != identity?.token ||
          (expectedSession != null &&
              (identity?.userId != expectedSession.userId ||
                  identity?.token != expectedSession.token))) {
        throw const MusicPlatformException('账号已变化，请重新加载页面');
      }
    }

    return browseCache.read(
      scope: 'kugou:${identity?.userId ?? "guest"}',
      route: path,
      query: query,
      load: load,
      checkCurrent: check,
      requestIdentity: identity?.token ?? 'guest',
    );
  }

  /// Comment writes follow the upstream POST contract with flat query fields.
  /// Never retry here: a timed-out write may already have reached the platform.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, String> query = const {},
    required PlatformSession expectedSession,
    Duration timeout = const Duration(seconds: 15),
  }) => _request(
    'POST',
    path,
    query: query,
    allowBusinessError: true,
    expectedSession: expectedSession,
    timeout: timeout,
  );

  /// Profile/avatar payloads belong in a JSON body, especially base64 images.
  /// Putting an image in the URL exceeds request-line limits and exposes its
  /// contents to URL diagnostics. Existing flat-query write contracts remain.
  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, Object?> body,
    required PlatformSession expectedSession,
  }) => _request(
    'POST',
    path,
    query: const {},
    body: body,
    allowBusinessError: true,
    expectedSession: expectedSession,
    timeout: const Duration(seconds: 30),
  );

  /// PCM recognition is an octet-stream contract, not JSON or URL data.
  Future<Map<String, dynamic>> postBytes(
    String path,
    List<int> bytes, {
    Future<void>? abortTrigger,
    PlatformSession? expectedSession,
  }) => _request(
    'POST',
    path,
    query: const {},
    allowBusinessError: false,
    binaryBody: bytes,
    abortTrigger: abortTrigger,
    expectedSession: expectedSession,
    timeout: const Duration(seconds: 20),
  );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    required Map<String, String> query,
    required bool allowBusinessError,
    Future<void>? abortTrigger,
    PlatformSession? expectedSession,
    Duration timeout = const Duration(seconds: 15),
    Map<String, Object?>? body,
    List<int>? binaryBody,
  }) async {
    if (!_routeAllowed(path) ||
        expectedSession?.platform == MusicPlatform.qishui ||
        session?.platform == MusicPlatform.qishui) {
      throw const MusicPlatformException('此入口尚未接入汽水，请使用汽水页面中的功能');
    }
    // Per-request account sources may outlive their parent provider while an
    // HTTP future settles. Reject every follow-up, not just the final result.
    if (!_sessionCurrent()) {
      throw const MusicPlatformException('账号已变化，请返回后重新操作');
    }
    // Enforce the boundary even if a future caller passes a malformed path.
    if (!path.startsWith('/') || path.startsWith('//') || path.contains('?')) {
      throw ArgumentError.value(path, 'path', 'Expected an absolute API path');
    }
    final base = await _server.start();
    if (base.scheme != 'http' || base.host != '127.0.0.1') {
      throw StateError('音乐接口必须使用本机回环地址');
    }
    final identity = session;
    if (!_sessionCurrent()) {
      throw const MusicPlatformException('账号已变化，请返回后重新操作');
    }
    if (expectedSession != null &&
        (identity?.userId != expectedSession.userId ||
            identity?.token != expectedSession.token)) {
      throw const MusicPlatformException('账号已变化，请返回后重新操作');
    }
    http.AbortableRequest buildRequest(Future<void> abort) {
      if (!_sessionCurrent() ||
          session?.ownerId != identity?.ownerId ||
          session?.token != identity?.token) {
        throw const MusicPlatformException('账号已变化，请返回后重新操作');
      }
      final request = http.AbortableRequest(
        method,
        base.replace(
          path: path,
          queryParameters: {
            ...query,
            'dfid': ?_dfid,
            // Account-specific responses must never hit another account's cache.
            if (identity != null)
              't': '${DateTime.now().microsecondsSinceEpoch}',
          },
        ),
        abortTrigger: abort,
      );
      request.followRedirects = false;
      request.headers['Accept'] = 'application/json';
      request.headers['x-apicache-bypass'] = '1';
      request.headers['Cache-Control'] = 'no-cache';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.body = jsonEncode(body);
      } else if (binaryBody != null) {
        request.headers['Content-Type'] = 'application/octet-stream';
        request.bodyBytes = binaryBody;
      }
      if (identity != null) {
        request.headers['Authorization'] = [
          'token=${identity.token}',
          'userid=${identity.userId}',
          if (identity.vipToken.isNotEmpty) 'vip_token=${identity.vipToken}',
        ].join(';');
      }
      return request;
    }

    try {
      final response = await sendMusicRequest(
        client: _client,
        build: buildRequest,
        platform: 'kugou',
        operation: path == '/captcha/sent'
            ? MusicNetworkOperation.sms
            : path.startsWith('/login/')
            ? MusicNetworkOperation.login
            : path.startsWith('/song/url')
            ? MusicNetworkOperation.playbackUrl
            : MusicNetworkOperation.read,
        timeout: timeout,
        abortTrigger: abortTrigger,
        retryResponse: _transportResponse,
        retryRead: {
          '/song/url',
          '/song/url/new',
          '/audio',
          '/search',
          '/song/info',
        }.contains(path),
      );
      final decoded = await decodeJsonBytes(response.bodyBytes);
      if (response.statusCode >= 500 &&
          path.startsWith('/song/url') &&
          _transportResponse(response)) {
        throw MusicPlatformException(
          '播放地址服务暂时不可用（HTTP ${response.statusCode}），请重试',
          code: 'http_${response.statusCode}',
        );
      }
      if (!_sessionCurrent() ||
          session?.ownerId != identity?.ownerId ||
          session?.token != identity?.token) {
        throw const MusicPlatformException('账号已变化，请返回后重新操作');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('音乐平台返回了无法识别的数据');
      }
      if (!allowBusinessError &&
          (response.statusCode != 200 ||
              decoded['status']?.toString() == '0' ||
              (decoded['error_code'] != null &&
                  decoded['error_code'].toString() != '0'))) {
        // Raw responses/URLs can contain credentials. Never log or expose them.
        final rawCode =
            '${decoded['error_code'] ?? decoded['err_code'] ?? decoded['errcode'] ?? ''}';
        final code = RegExp(r'^\d+$').hasMatch(rawCode) ? rawCode : '';
        MusicNetworkDiagnostics.shared.record(
          platform: 'kugou',
          operation: MusicNetworkOperation.other,
          outcome: MusicNetworkOutcome.business,
          status: int.tryParse(code),
        );
        throw MusicPlatformException(
          code == '20017' || code == '20018'
              ? '音乐平台登录已失效，请重新登录后重试'
              : code == '60045'
              ? '请先在酷狗客户端完成安全验证后重试'
              : '音乐平台暂时未能完成请求${code.isEmpty || code == '0' ? '' : '（错误码 $code）'}，请稍后重试',
          code: code,
        );
      }
      if (!_sessionCurrent()) {
        throw const MusicPlatformException('账号已变化，请返回后重新操作');
      }
      if (expectedSession != null &&
          (session?.userId != expectedSession.userId ||
              session?.token != expectedSession.token)) {
        throw const MusicPlatformException('账号已变化，请返回后重新操作');
      }
      if (BrowseCacheRoutes.kugouMutations.contains(path) &&
          response.statusCode == 200 &&
          decoded['status']?.toString() != '0' &&
          (decoded['error_code'] == null ||
              decoded['error_code'].toString() == '0')) {
        await browseCache.invalidateScope(
          'kugou:${identity?.userId ?? "guest"}',
          preserveRoute: BrowseCacheRoutes.discoveryRead,
        );
      }
      return decoded;
    } on http.RequestAbortedException {
      rethrow;
    } on MusicTransportException catch (error) {
      throw MusicPlatformException(error.message);
    } on FormatException {
      throw const MusicPlatformException('音乐平台返回格式异常，请稍后重试');
    } on TimeoutException {
      throw const MusicPlatformException('音乐平台连接超时，请重试');
    } on MusicPlatformException {
      rethrow;
    } on Object {
      throw const MusicPlatformException('暂时无法连接音乐平台，请检查网络后重试');
    }
  }

  Future<void> registerDevice() => _registration ??= _registerDevice()
      .whenComplete(() => _registration = null);

  Future<void> _registerDevice() async {
    final result = await get('/register/dev');
    final data = objectMap(result['data']);
    final dfid = data['dfid']?.toString() ?? '';
    if (dfid.isEmpty || dfid == '-') {
      throw const MusicPlatformException('设备注册尚未完成，请稍后重试');
    }
    _dfid = dfid;
  }

  /// The Rust adapter uses HTTP 502 for BOTH upstream business rejection and
  /// transport failure. Preserve device/rights/verification codes for resolver
  /// policy; retry only its recognized empty transport envelope or a gateway.
  static bool _transportResponse(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is! Map) return true;
      final nested = value['data'];
      for (final item in [value, if (nested is Map) nested]) {
        if (['errcode', 'error_code', 'err_code'].any(item.containsKey)) {
          return false;
        }
      }
      final message = value['msg'];
      return value['status'] == 0 && message is Map && message.isEmpty;
    } on FormatException {
      return true;
    }
  }

  static Map<String, dynamic> objectMap(Object? value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
}

class MusicPlatformException implements Exception {
  const MusicPlatformException(this.message, {this.code = ''});
  final String message;
  final String code;
  @override
  String toString() => message;
}
