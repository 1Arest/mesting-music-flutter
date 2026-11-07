import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'qishui_api.dart';
import 'qishui_signer_defaults.dart';
import 'qishui_signer_settings.dart';

class QishuiSignedRequest {
  const QishuiSignedRequest(this.uri, this.headers);
  final Uri uri;
  final Map<String, String> headers;
}

/// Signatures cover the exact URL, body bytes and application headers. The
/// Anonymous is the default. The separate opt-in policy permits only the exact
/// official Cookie header to a user-selected HTTPS helper; CSRF/token headers
/// and the account jar are never part of the helper payload.
abstract interface class QishuiRequestSigner {
  Future<Map<String, String>> identity(Future<void> abort);
  Future<QishuiSignedRequest> sign(
    Uri uri,
    String method,
    String body,
    Map<String, String> headers,
    Future<void> abort,
  );
  void invalidateIdentity();
}

/// Kept separate so test/local signers cannot accidentally opt into credentials.
/// The API consults this before exposing even the eligible Cookie header.
abstract interface class QishuiAccountRequestSigner {
  Future<bool> usesAccountCookie();
}

/// Adapter for the public SodaM service selected explicitly by the user.
/// Only fixed, first-party business requests can be signed, and returned data
/// cannot redirect authentication to another origin or overwrite auth headers.
class SodaMRequestSigner
    implements QishuiRequestSigner, QishuiAccountRequestSigner {
  SodaMRequestSigner(
    this.client, {
    Uri? endpoint,
    String? accessToken,
    this.custom = false,
    this.accountBoundSigning = false,
  }) : endpoint = endpoint ?? Uri.parse(qishuiReferenceSignerUrl),
       accessToken = accessToken ?? qishuiReferenceSignerToken;
  final http.Client client;
  final Uri endpoint;
  final String accessToken;
  final bool custom;
  final bool accountBoundSigning;

  bool get _accountAllowed =>
      accountBoundSigning &&
      custom &&
      endpoint.scheme == 'https' &&
      endpoint.host != Uri.parse(qishuiReferenceSignerUrl).host &&
      endpoint.userInfo.isEmpty;

  @override
  Future<bool> usesAccountCookie() async {
    if (accountBoundSigning && !_accountAllowed) {
      throw const QishuiException('账号参与签名仅支持自建 HTTPS 服务', code: 'signer');
    }
    return _accountAllowed;
  }

  Future<Map<String, String>>? _identity;
  static const userAgent = 'SodaMusic/3.3.0';
  static const _headerNames = {
    'accept',
    'content-type',
    'user-agent',
    'x-ss-stub',
    'x-luna-background-type',
    'x-luna-is-background-req',
    'x-luna-is-local-user',
  };

  @override
  void invalidateIdentity() => _identity = null;

  Future<Map<String, dynamic>> _call(
    Uri target,
    String method,
    String? body,
    Future<void> abort,
  ) async {
    try {
      // The pinned Flutter engine supports a per-Zone HTTP exception. Keep it
      // inside this exact configured helper call, with redirects disabled. No
      // global Android cleartext/TLS policy or first-party request is changed.
      Future<http.Response> send() => sendMusicRequest(
        client: client,
        platform: 'qishui',
        operation: MusicNetworkOperation.playbackUrl,
        maximumResponseBytes: 65536,
        timeout: const Duration(seconds: 16),
        abortTrigger: abort,
        retryRead: false,
        build: (cancel) {
          final request =
              http.AbortableRequest(method, target, abortTrigger: cancel)
                ..followRedirects = false
                ..headers.addAll({
                  'accept': 'application/json',
                  if (accessToken.isNotEmpty)
                    'authorization': 'Bearer $accessToken',
                });
          if (body != null) {
            request.headers['content-type'] = 'application/json; charset=utf-8';
            request.body = body;
          }
          return request;
        },
      );
      final response = target.scheme == 'http'
          ? await runZoned(send, zoneValues: {#flutter.io.allow_http: true})
          : await send();
      if (!custom && response.statusCode == 404 && method == 'GET') {
        return const {};
      }
      if (response.statusCode != 200) {
        throw QishuiException(
          switch (response.statusCode) {
            401 ||
            403 => '签名助手访问令牌不正确或未获授权（HTTP ${response.statusCode}），请检查签名服务设置',
            404 => '签名服务路径不存在（HTTP 404），请检查服务地址和路径前缀',
            429 => '签名助手请求过于频繁（HTTP 429），请稍后重试',
            503 => '签名助手尚未就绪或当前繁忙（HTTP 503），请检查助手状态',
            400 ||
            415 ||
            422 => '签名助手拒绝请求参数（HTTP ${response.statusCode}），请核对助手接口版本',
            _ => '汽水签名服务暂不可用（HTTP ${response.statusCode}），请检查助手状态',
          },
          code: 'signer',
          kind: QishuiFailureKind.refused,
        );
      }
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic> || value['ok'] == false) {
        throw const QishuiException(
          '汽水签名服务未接受请求，请稍后重试',
          code: 'signer',
          kind: QishuiFailureKind.refused,
        );
      }
      return value;
    } on QishuiException {
      rethrow;
    } on http.RequestAbortedException {
      rethrow;
    } on MusicTransportException catch (error) {
      throw QishuiException(
        error.outcome == MusicNetworkOutcome.timeout
            ? '签名服务连接超时，请检查地址与助手状态'
            : '签名服务连接失败，请检查地址、网络或 HTTPS 证书',
        code: 'signer',
        kind: error.outcome == MusicNetworkOutcome.timeout
            ? QishuiFailureKind.timeout
            : QishuiFailureKind.connection,
      );
    } on Object {
      throw const QishuiException(
        '汽水签名服务连接或回执异常，请稍后重试',
        code: 'signer',
        kind: QishuiFailureKind.connection,
      );
    }
  }

  @override
  Future<Map<String, String>> identity(Future<void> abort) =>
      _identity ??= _loadIdentity(abort).catchError((Object error) {
        _identity = null;
        throw error;
      });

  Future<Map<String, String>> _loadIdentity(Future<void> abort) async {
    final config = endpoint.replace(
      path: endpoint.path.replaceFirst(RegExp(r'/sign/?$'), '/config'),
    );
    var value = await _call(config, 'GET', null, abort);
    String field(String name) {
      final inner = value['identity'];
      final raw =
          '${inner is Map ? inner[name] ?? value[name] ?? '' : value[name] ?? ''}';
      return raw.length <= 256 &&
              !raw.contains('*') &&
              !raw.contains(RegExp(r'[\r\n]'))
          ? raw
          : '';
    }

    // The selected reference instance currently lacks /config but publishes
    // its desktop device_id on /sign. Bootstrap signs a credential-free read;
    // no account read or write is dispatched to the official service here.
    if (!custom && !RegExp(r'^\d{1,30}$').hasMatch(field('device_id'))) {
      value = await _call(
        endpoint,
        'POST',
        jsonEncode({
          'url': 'https://api.qishui.com/luna/pc/me',
          'method': 'GET',
          'body': '',
          'headers': {'Accept': 'application/json', 'User-Agent': userAgent},
          'ts_ms': DateTime.now().millisecondsSinceEpoch,
        }),
        abort,
      );
    }
    final did = field('device_id');
    if (!RegExp(r'^\d{1,30}$').hasMatch(did)) {
      throw const QishuiException('汽水签名服务未返回可用设备上下文，请稍后重试', code: 'signer');
    }
    final iid = field('iid');
    final ua = field('user_agent');
    final fp = field('fp');
    if (custom &&
        (!RegExp(r'^\d{1,30}$').hasMatch(iid) ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(fp) ||
            !RegExp(r'^LunaPC/\d+\.\d+\.\d+\(\d+\)$').hasMatch(ua))) {
      throw const QishuiException(
        '签名助手未返回完整的 PC 身份和 User-Agent，请检查助手配置',
        code: 'signer',
      );
    }
    return Map.unmodifiable({
      'device_id': did,
      // This is PC protocol context, never Android BDInstall registration.
      'iid': RegExp(r'^\d{1,30}$').hasMatch(iid)
          ? iid
          : '${DateTime.now().millisecondsSinceEpoch + 1}',
      'fp': fp.isEmpty ? did : fp,
      if (custom) 'user_agent': ua,
    });
  }

  @override
  Future<QishuiSignedRequest> sign(
    Uri uri,
    String method,
    String body,
    Map<String, String> headers,
    Future<void> abort,
  ) async {
    // Validate again at the transport boundary, even when called outside the
    // settings UI. An invalid opt-in never downgrades to HTTP or a public host.
    final withAccount = await usesAccountCookie();
    if (uri.scheme != 'https' ||
        uri.host != 'api.qishui.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !(uri.path.startsWith('/luna/pc/') ||
            uri.path == '/luna/me/playlist/media/sort' ||
            uri.path == '/luna/commerce/v2/check_download' ||
            uri.path == '/luna/video/uploader' && method == 'GET') ||
        !{'GET', 'POST'}.contains(method) ||
        utf8.encode(body).length > 1024 * 1024) {
      throw const QishuiException('汽水签名请求参数未通过校验');
    }
    final safeHeaders = <String, String>{};
    for (final entry in headers.entries) {
      final name = entry.key.toLowerCase();
      if (_headerNames.contains(name) ||
          withAccount && uri.path == '/luna/pc/track_v2' && name == 'cookie') {
        if (entry.value.contains(RegExp(r'[\r\n]')) ||
            entry.value.length > 32768) {
          throw const QishuiException('签名请求头未通过校验', code: 'signer');
        }
        safeHeaders[entry.key] = entry.value;
      }
    }
    final value = await _call(
      endpoint,
      'POST',
      jsonEncode({
        'url': '$uri',
        'method': method,
        'body': body,
        'headers': safeHeaders,
        'ts_ms': DateTime.now().millisecondsSinceEpoch,
      }),
      abort,
    );
    final signedHeaders = <String, String>{};
    void take(String name, Object? raw) {
      if (raw is String &&
          raw.isNotEmpty &&
          raw.length <= 16384 &&
          !raw.contains(RegExp(r'[\r\n]'))) {
        signedHeaders[name] = raw;
      }
    }

    final returned = value['headers'];
    if (returned is Map) {
      for (final entry in returned.entries) {
        final name = '${entry.key}'.toLowerCase().replaceAll('_', '-');
        if ({'x-helios', 'x-medusa'}.contains(name)) take(name, entry.value);
      }
    }
    for (final name in ['x-helios', 'x-medusa']) {
      take(name, value[name] ?? value[name.replaceAll('-', '_')]);
    }
    if (!signedHeaders.keys.toSet().containsAll({'x-helios', 'x-medusa'})) {
      throw const QishuiException('汽水签名服务未返回完整应用签名，请稍后重试', code: 'signer');
    }
    MusicNetworkDiagnostics.shared.record(
      platform: 'qishui',
      operation: MusicNetworkOperation.playbackUrl,
      outcome: MusicNetworkOutcome.success,
      phase: MusicDiagnosticPhase.accountSigning,
      accountCookieSigned: safeHeaders.keys.any(
        (key) => key.toLowerCase() == 'cookie',
      ),
    );
    if (custom && value['device_id'] != uri.queryParameters['device_id']) {
      throw const QishuiException('签名助手返回的设备身份不一致，请检查助手配置', code: 'signer');
    }
    final query = {...uri.queryParameters};
    var changedQuery = false;
    for (final field
        in custom
            ? <(String, String)>[]
            : [('ms_token', 'msToken'), ('a_bogus', 'a_bogus')]) {
      final v = value[field.$1];
      if (v is String && v.isNotEmpty && v.length < 8192) {
        query[field.$2] = v;
        changedQuery = true;
      }
    }
    return QishuiSignedRequest(
      changedQuery ? uri.replace(queryParameters: query) : uri,
      Map.unmodifiable(signedHeaders),
    );
  }
}

/// Both the connection check and playback build the exact same PC context.
/// Internal UA metadata is not appended to the official URL's query string.
Map<String, String> qishuiDesktopParameters(Map<String, String> identity) {
  final match = RegExp(
    r'^LunaPC/(\d+)\.(\d+)\.(\d+)\(',
  ).firstMatch(identity['user_agent'] ?? '');
  return {
    'aid': '386088',
    'app_name': 'luna_pc',
    'region': 'cn',
    'geo_region': 'cn',
    'os_region': 'cn',
    'sim_region': '',
    'version_name': match == null
        ? '3.3.0'
        : '${match[1]}.${match[2]}.${match[3]}',
    'version_code': match == null
        ? '30030000'
        : '${int.parse(match[1]!) * 1000000 + int.parse(match[2]!) * 1000 + int.parse(match[3]!)}',
    'channel': 'official',
    'build_mode': match == null ? 'master' : 'release',
    'network_carrier': '',
    'ac': 'wifi',
    'tz_name': 'Asia/Shanghai',
    'resolution': '',
    'device_platform': 'windows',
    'device_type': 'Windows',
    'os_version': 'Windows 11',
    for (final key in ['device_id', 'iid', 'fp'])
      if (identity.containsKey(key)) key: identity[key]!,
  };
}

/// Reads only committed settings; an unreadable saved record must fail closed.
/// Selecting a private helper never silently retries against a public service.
class ConfiguredQishuiRequestSigner
    implements QishuiRequestSigner, QishuiAccountRequestSigner {
  ConfiguredQishuiRequestSigner(this.client, this.load);
  final http.Client client;
  final Future<QishuiSignerConfig?> Function() load;
  QishuiSignerConfig? _config;
  SodaMRequestSigner? _delegate;
  Future<SodaMRequestSigner> _selected() async {
    QishuiSignerConfig? config;
    try {
      config = await load().timeout(const Duration(seconds: 10));
    } on Object {
      throw const QishuiException('签名服务设置未能读取，请前往设置重试', code: 'signer');
    }
    if (config == null) {
      throw const QishuiException('请先在设置中填写并保存汽水签名服务的访问令牌', code: 'signer');
    }
    if (_delegate == null || config != _config) {
      _config = config;
      _delegate = SodaMRequestSigner(
        client,
        endpoint: config.signUri,
        accessToken: config.accessToken,
        custom: true,
        accountBoundSigning: config.accountBoundSigning,
      );
    }
    return _delegate!;
  }

  @override
  Future<Map<String, String>> identity(Future<void> abort) async =>
      (await _selected()).identity(abort);
  @override
  Future<bool> usesAccountCookie() async =>
      (await _selected()).usesAccountCookie();
  @override
  Future<QishuiSignedRequest> sign(
    Uri uri,
    String method,
    String body,
    Map<String, String> headers,
    Future<void> abort,
  ) async => (await _selected()).sign(uri, method, body, headers, abort);
  @override
  void invalidateIdentity() => _delegate?.invalidateIdentity();
}

/// No official business request is made by the connection test: it obtains a
/// real signature for an anonymous read and discards it without dispatching it.
Future<void> testQishuiSignerConnection(
  http.Client client,
  QishuiSignerConfig config,
  Future<void> abort,
) async {
  final signer = SodaMRequestSigner(
    client,
    endpoint: config.signUri,
    accessToken: config.accessToken,
    custom: true,
  );
  final identity = await signer.identity(abort);
  final uri = Uri.https('api.qishui.com', '/luna/pc/me', {
    ...qishuiDesktopParameters(identity),
    '_rticket': '${DateTime.now().millisecondsSinceEpoch}',
  });
  await signer.sign(uri, 'GET', '', {
    'accept': 'application/json',
    'user-agent': identity['user_agent']!,
  }, abort);
}
