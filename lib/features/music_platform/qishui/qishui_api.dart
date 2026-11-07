import 'dart:async';
import 'dart:convert';
import 'dart:io' show Cookie;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'qishui_session.dart';
import 'qishui_web_routes.dart';
import 'qishui_request_signer.dart';

/// Stable, credential-free categories shared by the transport and status HUD.
/// A malformed media reply must never be presented as a broken user network.
enum QishuiFailureKind {
  operation,
  connection,
  timeout,
  authentication,
  refused,
  entitlement,
  format,
  cancelled,
  uncertainWrite,
}

class QishuiException implements Exception {
  const QishuiException(
    this.message, {
    this.code = '',
    this.unknownWrite = false,
    this.kind = QishuiFailureKind.operation,
  });
  final String message, code;
  final bool unknownWrite;
  final QishuiFailureKind kind;
  String get title => unknownWrite
      ? '请核对操作结果'
      : switch (kind) {
          QishuiFailureKind.authentication => '汽水登录需要更新',
          QishuiFailureKind.refused => '汽水暂未接受请求',
          QishuiFailureKind.entitlement => '汽水播放或下载受限',
          QishuiFailureKind.format => '汽水资料读取未完成',
          QishuiFailureKind.timeout => '汽水服务响应超时',
          QishuiFailureKind.connection => '汽水连接未完成',
          QishuiFailureKind.cancelled => '操作已取消',
          _ => '操作未完成',
        };
  @override
  String toString() => message;
}

/// Device fields are read from Android, not fabricated installation identities.
/// No native installation identity or security factor is synthesized here.
/// The separately injected desktop signer is used only for its explicit routes.
Future<Map<String, String>> qishuiAndroidContext() async {
  const bridge = MethodChannel('com.mesting.music/qishui');
  final value = await bridge.invokeMapMethod<String, String>('context');
  if (value == null) throw const QishuiException('无法读取手机信息，请重试');
  return Map.unmodifiable(value);
}

typedef QishuiContext = Future<Map<String, String>> Function();

/// Each credential remains bound to its first-party protocol/host. There is
/// Signatures are requested anonymously before first-party credentials are
/// attached; the signer cannot redirect an authenticated request to another host.
class QishuiApi {
  QishuiApi(
    this.client, {
    QishuiContext? context,
    this.persistRefresh,
    this.signer,
  }) : context = context ?? qishuiAndroidContext;
  static const host = 'beta-luna.douyin.com';
  final http.Client client;
  final QishuiContext context;
  final QishuiRequestSigner? signer;
  final Future<void> Function(QishuiSession expected, QishuiSession updated)?
  persistRefresh;
  QishuiSession? _session;
  final _cookies = <Map<String, String>>[];
  final _tokens = <String, String>{};
  final _pending = <Completer<void>>{};
  Completer<void> _identityAbort = Completer<void>();
  Future<void> get identityAbort => _identityAbort.future;
  int _epoch = 0;
  int authenticationRevision = 0;
  QishuiSession? get session => _session;
  String? get credential => _session?.credentialId;
  QishuiApi loginClient() => QishuiApi(client, context: context);

  /// A settings change revokes old in-flight work without replacing the live
  /// account jar. Already-dispatched writes keep the existing unknown journal.
  void invalidateSigner() {
    ++_epoch;
    for (final abort in _pending.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    signer?.invalidateIdentity();
  }

  void configure(QishuiSession? session) {
    ++_epoch;
    if (!_identityAbort.isCompleted) _identityAbort.complete();
    _identityAbort = Completer<void>();
    for (final abort in _pending.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    _session = session;
    _cookies
      ..clear()
      ..addAll(session?.cookies.map(Map<String, String>.of) ?? []);
    _tokens
      ..clear()
      ..addAll(session?.tokens ?? {});
  }

  void dispose() => configure(null);

  QishuiSession snapshot(
    String uid, {
    String name = '',
    String avatar = '',
    String? passportUserId,
  }) => QishuiSession(
    userId: uid,
    cookies: _cookies,
    tokens: _tokens,
    nickname: name,
    avatarUrl: avatar,
    passportUserId: passportUserId ?? _session?.passportUserId ?? '',
    protocol: _session?.protocol ?? QishuiSessionProtocol.mobile,
    webDeviceId: _session?.webDeviceId ?? '',
    webInstallId: _session?.webInstallId ?? '',
    loginId: _session?.userId == uid ? _session?.credentialId : null,
  );

  /// A token rotation retains the login epoch and does not replace a live jar
  /// which may already have received a newer concurrent response.
  void acknowledgeRefresh(QishuiSession expected, QishuiSession updated) {
    if (_session?.userId == expected.userId &&
        credential == expected.credentialId) {
      _session = updated;
    }
  }

  /// Split only between cookie assignments, preserving Expires' comma. Scope,
  /// expiry, secure flag and paths survive encrypted persistence and restore.
  void _capture(http.Response response, Uri uri) {
    final responseHeaders = {
      for (final entry in response.headers.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final raw = responseHeaders['set-cookie'];
    if (raw != null) {
      for (final value in raw.split(RegExp(r',(?=\s*[^;,=\s]+\s*=)'))) {
        try {
          final c = Cookie.fromSetCookieValue(value.trim());
          final domain = (c.domain ?? uri.host)
              .replaceFirst(RegExp(r'^\.'), '')
              .toLowerCase();
          if (domain.isEmpty ||
              !(uri.host == domain || uri.host.endsWith('.$domain'))) {
            continue;
          }
          // Do not accept public suffix cookies or an unrelated API host.
          if (domain != uri.host &&
              !(uri.host == host && domain == 'douyin.com') &&
              !(uri.host == 'api.qishui.com' && domain == 'qishui.com')) {
            continue;
          }
          if ({'sessionid', 'sessionid_ss'}.contains(c.name)) {
            ++authenticationRevision;
          }
          final path = c.path?.startsWith('/') == true ? c.path! : '/';
          _cookies.removeWhere(
            (v) =>
                v['name'] == c.name &&
                v['domain'] == domain &&
                v['path'] == path,
          );
          if (c.value.isEmpty || c.maxAge == 0) continue;
          final expires = c.maxAge == null
              ? c.expires
              : DateTime.now().add(Duration(seconds: c.maxAge!));
          if (expires != null && !expires.isAfter(DateTime.now())) continue;
          _cookies.add({
            'name': c.name,
            'value': c.value,
            'domain': domain,
            'path': path,
            'secure': '${c.secure}',
            'hostOnly': '${c.domain == null}',
            if (expires != null) 'expires': expires.toUtc().toIso8601String(),
          });
        } on FormatException {
          /* Ignore malformed individual cookies. */
        }
      }
    }
    for (final name in ['x-tt-token', 'x-tt-session-sign', 'd-ticket']) {
      final value = responseHeaders[name];
      if (name == 'x-tt-token' && value?.isNotEmpty == true) {
        ++authenticationRevision;
      }
      if (value != null && !RegExp(r'[\r\n]').hasMatch(value)) {
        _tokens[name] = value;
      }
    }
  }

  Iterable<Map<String, String>> _eligibleCookies(Uri uri) =>
      _cookies.where((c) {
        final domain = c['domain'] ?? '';
        final expiry = DateTime.tryParse(c['expires'] ?? '');
        final path = c['path'] ?? '/';
        return domain.isNotEmpty &&
            (uri.host == domain ||
                c['hostOnly'] != 'true' && uri.host.endsWith('.$domain')) &&
            (uri.path == path ||
                uri.path.startsWith(path.endsWith('/') ? path : '$path/')) &&
            (expiry == null || expiry.isAfter(DateTime.now())) &&
            (c['secure'] != 'true' || uri.scheme == 'https');
      });
  String _cookieHeader(Uri uri) =>
      _eligibleCookies(uri).map((c) => '${c['name']}=${c['value']}').join('; ');

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    Map<String, String>? form,
    bool get = false,
    bool write = false,
    bool authenticated = true,
    String? expectedCredential,
    Future<void>? abortTrigger,
    bool allowBusinessError = false,
  }) async {
    if (!path.startsWith('/luna/') && !path.startsWith('/passport/mobile/')) {
      throw const QishuiException('不支持的汽水请求');
    }
    final epoch = _epoch;
    if (authenticated && _session == null) {
      throw const QishuiException('请先登录汽水账号');
    }
    if (expectedCredential != null && expectedCredential != credential) {
      throw const QishuiException('账号已变化，请重新操作');
    }
    final abort = Completer<void>();
    _pending.add(abort);
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    var dispatched = false;
    try {
      final web = _session?.protocol == QishuiSessionProtocol.web;
      final route = web
          ? QishuiWebRoute.resolve(path, body, query, write)
          : null;
      final signedPc =
          web &&
          (route!.path == '/luna/pc/track_v2' ||
              route.path == '/luna/commerce/v2/check_download' ||
              write);
      if (signedPc && signer == null) {
        throw const QishuiException('汽水应用签名服务尚未就绪，请稍后重试', code: 'signer');
      }
      final device = signedPc
          ? await signer!.identity(abort.future)
          : web
          ? const <String, String>{}
          : await context();
      if (epoch != _epoch || abort.isCompleted) {
        throw const QishuiException('操作已取消');
      }
      var uri = Uri.https(web ? 'api.qishui.com' : host, route?.path ?? path, {
        // These are protocol constants from the pinned 21.5.0 contract, not
        // claims about Mesting's installed package/version or registered iid.
        if (!web) ...{
          'aid': '8478',
          'app_name': 'luna',
          'version_name': '21.5.0',
          'version_code': '100215040',
          'device_platform': 'android',
        } else if (signedPc) ...{
          ...qishuiDesktopParameters(device),
        } else ...{
          'aid': '386088',
          'app_name': 'luna_pc',
          'device_platform': 'web',
          'channel': 'pc_web',
          if (_session!.webDeviceId.isNotEmpty) ...{
            'device_id': _session!.webDeviceId,
            'did': _session!.webDeviceId,
          },
          if (_session!.webInstallId.isNotEmpty) ...{
            'install_id': _session!.webInstallId,
            'iid': _session!.webInstallId,
          },
        },
        if (!signedPc) ...device,
        '_rticket': '${DateTime.now().millisecondsSinceEpoch}',
        ...(route?.query ?? query),
      });
      final headers = <String, String>{
        'accept': 'application/json',
        'user-agent': signedPc
            ? device['user_agent'] ?? SodaMRequestSigner.userAgent
            : 'MestingMusic/1.0 (Android; Soda mobile adapter)',
      };
      final method = (route?.get ?? get) ? 'GET' : 'POST';
      // Encode once; do not re-encode a Map after a signature has been issued.
      final encodedBody = method == 'GET'
          ? ''
          : jsonEncode(route?.body ?? body);
      if (signedPc) {
        headers.addAll({
          'content-type': 'application/json; charset=utf-8',
          'x-ss-stub': md5
              .convert(utf8.encode(encodedBody))
              .toString()
              .toUpperCase(),
          'x-luna-background-type': 'foreground',
          'x-luna-is-background-req': '0',
          'x-luna-is-local-user': '0',
        });
        final signed = await signer!.sign(
          uri,
          method,
          encodedBody,
          headers,
          abort.future,
        );
        if (epoch != _epoch || abort.isCompleted) {
          throw const QishuiException('操作已取消');
        }
        uri = signed.uri;
        headers.addAll(signed.headers);
      }
      // Attach credentials only after the anonymous signing operation, and
      // only to the fixed original first-party host. No signer-supplied auth.
      final cookie = _cookieHeader(uri);
      if (cookie.isNotEmpty) headers['cookie'] = cookie;
      headers.addAll(_tokens);
      final csrf = _eligibleCookies(
        uri,
      ).where((c) => c['name'] == 'passport_csrf_token').firstOrNull?['value'];
      if (csrf?.isNotEmpty == true) headers['x-tt-passport-csrf-token'] = csrf!;
      final response = await sendMusicRequest(
        client: client,
        platform: 'qishui',
        operation: path.startsWith('/passport/')
            ? MusicNetworkOperation.login
            : path == '/luna/media_v2'
            ? MusicNetworkOperation.playbackUrl
            : MusicNetworkOperation.read,
        abortTrigger: abort.future,
        retryRead: false,
        maximumResponseBytes: 8 * 1024 * 1024,
        build: (cancel) {
          final request =
              http.AbortableRequest(method, uri, abortTrigger: cancel)
                ..followRedirects = false
                ..headers.addAll(headers);
          if (!(route?.get ?? get)) {
            if (form != null) {
              request.bodyFields = form;
            } else {
              request.headers['content-type'] =
                  'application/json; charset=utf-8';
              request.body = encodedBody;
            }
          }
          dispatched = true;
          return request;
        },
      );
      if (epoch != _epoch || abort.isCompleted) {
        throw const QishuiException('操作已取消');
      }
      if (response.statusCode != 200) {
        throw QishuiException(
          '汽水请求未完成（HTTP ${response.statusCode}）',
          kind: response.statusCode == 401
              ? QishuiFailureKind.authentication
              : QishuiFailureKind.refused,
          unknownWrite: write && response.statusCode >= 500,
        );
      }
      if (response.bodyBytes.isEmpty) {
        if (signedPc) signer?.invalidateIdentity();
        throw QishuiException(
          signedPc ? '汽水未接受本次应用签名，请稍后重试' : '汽水服务返回空响应，请稍后重试',
          kind: QishuiFailureKind.refused,
          unknownWrite: write && dispatched,
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded.isEmpty) {
        throw const QishuiException('汽水返回了空数据，请稍后重试');
      }
      final data = decoded['data'];
      final statusInfo = decoded['status_info'];
      final rawCode =
          '${decoded['status_code'] ?? decoded['error_code'] ?? (statusInfo is Map ? statusInfo['code'] ?? statusInfo['status_code'] : null) ?? (data is Map ? data['error_code'] : null) ?? 0}';
      // Business codes are numeric. Never display arbitrary response strings
      // that could contain identifiers, credentials or untrusted instructions.
      final code = RegExp(r'^-?\d{1,12}$').hasMatch(rawCode)
          ? rawCode
          : 'invalid';
      if (!allowBusinessError && code != '0') {
        throw QishuiException(
          code == '1000062' ? '汽水暂未接受当前客户端请求（1000062）' : '汽水拒绝了请求（$code）',
          code: code,
          kind: QishuiFailureKind.refused,
        );
      }
      _capture(response, uri);
      final previous = _session;
      if (previous != null && persistRefresh != null) {
        final updated = snapshot(
          previous.userId,
          name: previous.nickname,
          avatar: previous.avatarUrl,
        );
        if (!updated.complete) throw const QishuiException('汽水登录已失效，请重新登录');
        if (jsonEncode(updated.toJson()) != jsonEncode(previous.toJson())) {
          await persistRefresh!(previous, updated);
          if (epoch != _epoch) throw const QishuiException('账号已变化，操作已取消');
        }
      }
      return decoded;
    } on QishuiException {
      // Aborting a dispatched mutation only stops our local wait. The server
      // may already have committed it, so keep the journal across account
      // changes and restarts instead of treating cancellation as rejection.
      if (write && dispatched && (epoch != _epoch || abort.isCompleted)) {
        throw const QishuiException(
          '提交结果尚未确认，请先核对歌单，不要重复提交',
          kind: QishuiFailureKind.uncertainWrite,
          unknownWrite: true,
        );
      }
      rethrow;
    } on FormatException {
      throw QishuiException(
        write && dispatched
            ? '提交后的汽水回执无法读取，请先刷新核对，不要重复提交'
            : '汽水返回的数据格式异常，请稍后重试',
        kind: QishuiFailureKind.format,
        unknownWrite: write && dispatched,
      );
    } on Object catch (error) {
      // Never surface raw URLs/JSON/headers, which may contain OTP or tokens.
      final outcome = classifyMusicNetworkError(error);
      final cancelled =
          outcome == MusicNetworkOutcome.cancelled ||
          epoch != _epoch ||
          abort.isCompleted;
      throw QishuiException(
        write && dispatched
            ? '请求结果尚未确认，请先核对状态，不要重复提交'
            : cancelled
            ? '操作已取消'
            : error is MusicTransportException ||
                  error is http.ClientException ||
                  error is TimeoutException
            ? musicNetworkMessage(outcome)
            : '汽水请求处理未完成，请重试；可在连接诊断中核对失败阶段',
        kind: cancelled
            ? QishuiFailureKind.cancelled
            : outcome == MusicNetworkOutcome.timeout
            ? QishuiFailureKind.timeout
            : error is MusicTransportException || error is http.ClientException
            ? QishuiFailureKind.connection
            : QishuiFailureKind.operation,
        unknownWrite: write && dispatched,
      );
    } finally {
      _pending.remove(abort);
    }
  }
}

/// Passport uses XOR5 + lowercase hex once at the selected contract's field
/// boundary. Legacy and SaaS parameter objects do not mix the same fields.
String qishuiMix(String value) => utf8
    .encode(value)
    .map((v) => (v ^ 5).toRadixString(16).padLeft(2, '0'))
    .join();
