import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'qishui_api.dart';
import 'qishui_signer_defaults.dart';

class QishuiSignedRequest {
  const QishuiSignedRequest(this.uri, this.headers);
  final Uri uri;
  final Map<String, String> headers;
}

/// Signatures cover the exact URL, body bytes and application headers. The
/// service sees no Cookie, CSRF, user token, Passport nonce or account jar.
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

/// Adapter for the public SodaM service selected explicitly by the user.
/// Only fixed, first-party business requests can be signed, and returned data
/// cannot redirect authentication to another origin or overwrite auth headers.
class SodaMRequestSigner implements QishuiRequestSigner {
  SodaMRequestSigner(this.client, {Uri? endpoint, String? accessToken})
    : endpoint = endpoint ?? Uri.parse(qishuiReferenceSignerUrl),
      accessToken = accessToken ?? qishuiReferenceSignerToken;
  final http.Client client;
  final Uri endpoint;
  final String accessToken;
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
      final response = await sendMusicRequest(
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
      if (response.statusCode == 404 && method == 'GET') return const {};
      if (response.statusCode != 200) {
        throw QishuiException(
          '汽水签名服务暂不可用（HTTP ${response.statusCode}），请稍后重试',
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
    if (!RegExp(r'^\d{8,24}$').hasMatch(field('device_id'))) {
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
    if (!RegExp(r'^\d{8,24}$').hasMatch(did)) {
      throw const QishuiException('汽水签名服务未返回可用设备上下文，请稍后重试', code: 'signer');
    }
    final iid = field('iid');
    return Map.unmodifiable({
      'device_id': did,
      // This is PC protocol context, never Android BDInstall registration.
      'iid': RegExp(r'^\d{8,24}$').hasMatch(iid)
          ? iid
          : '${DateTime.now().millisecondsSinceEpoch + 1}',
      'fp': field('fp').isEmpty ? did : field('fp'),
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
    if (uri.scheme != 'https' ||
        uri.host != 'api.qishui.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !(uri.path.startsWith('/luna/pc/') ||
            uri.path == '/luna/me/playlist/media/sort' ||
            uri.path == '/luna/commerce/v2/check_download') ||
        !{'GET', 'POST'}.contains(method) ||
        utf8.encode(body).length > 1024 * 1024) {
      throw const QishuiException('汽水签名请求参数未通过校验');
    }
    final safeHeaders = <String, String>{};
    for (final entry in headers.entries) {
      if (_headerNames.contains(entry.key.toLowerCase())) {
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
    final query = {...uri.queryParameters};
    var changedQuery = false;
    for (final field in [('ms_token', 'msToken'), ('a_bogus', 'a_bogus')]) {
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
