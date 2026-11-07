import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'qishui_api.dart';
import 'qishui_auth_errors.dart';
import 'qishui_models.dart';
import 'qishui_qr_context.dart';
import 'qishui_session.dart';

/// Gateway is deliberately independent of widgets, persistent accounts and
/// mobile Passport. A fake gateway tests the transaction without a phone.
abstract interface class QishuiQrGateway {
  Future<void> begin(String flowId, String msToken);
  Future<bool> openScanner(String flowId);
  Future<Map<String, dynamic>> request(
    String flowId,
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  );
  Future<List<Map<String, String>>> cookies(String flowId);
  Future<bool> verify(
    String flowId,
    Map<String, dynamic> decision,
    Map<String, String> params,
  );
  Future<void> close(String flowId);
}

class AndroidQishuiQrGateway implements QishuiQrGateway {
  const AndroidQishuiQrGateway();
  static const _channel = MethodChannel('com.mesting.music/qishui_web_auth');
  Future<T?> _invoke<T>(
    String method,
    String id, [
    Map<String, Object?> values = const {},
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, {'flowId': id, ...values});
    } on PlatformException catch (error) {
      // Only our native bridge's fixed codes are shown, never its raw message.
      throw QishuiException(switch (error.code) {
        'sdk_timeout' => '汽水安全组件加载超时，请重新生成二维码',
        'isolation' => '本次汽水登录隔离未完成，请重新打开登录页',
        'timeout' => '汽水登录请求超时，请核对状态后重试',
        'cancelled' => '汽水登录已取消',
        _ => '汽水登录组件未完成，请重新打开登录页',
      });
    } on MissingPluginException {
      throw const QishuiException('扫码登录需要在Android应用中使用');
    }
  }

  @override
  Future<void> begin(String flowId, String msToken) async {
    await _invoke<void>('begin', flowId, {'msToken': msToken});
  }

  @override
  Future<bool> openScanner(String flowId) async =>
      await _invoke<bool>('openScanner', flowId) == true;

  @override
  Future<Map<String, dynamic>> request(
    String flowId,
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) async {
    final raw = await _invoke<String>('request', flowId, {
      'method': method,
      'url': '$uri',
      'headers': headers,
      'body': body,
    });
    final envelope = sodaMap(jsonDecode(raw ?? '{}'));
    final result = sodaMap(envelope['result']);
    if (envelope['ok'] != true || result['status'] != 200) {
      throw const QishuiException('汽水扫码请求未完成，请稍后重试');
    }
    if (QishuiQrLogin.trustedRedirect(uri)) return const {};
    final responseUri = Uri.tryParse('${result['responseURL'] ?? ''}');
    if (uri.path.startsWith('/passport/web/') &&
        ((responseUri?.queryParameters['a_bogus']?.length ?? 0) < 40)) {
      throw const QishuiException('汽水安全组件尚未完成签名，请重新生成二维码');
    }
    final value = jsonDecode('${result['body'] ?? ''}');
    if (value is! Map<String, dynamic>) throw const QishuiException('汽水扫码响应无效');
    return value;
  }

  @override
  Future<List<Map<String, String>>> cookies(String flowId) async {
    final value = await _invoke<List<dynamic>>('cookies', flowId) ?? [];
    return value
        .whereType<Map>()
        .map((v) => Map<String, String>.from(v))
        .toList();
  }

  @override
  Future<bool> verify(
    String flowId,
    Map<String, dynamic> decision,
    Map<String, String> params,
  ) async =>
      await _invoke<bool>('verify', flowId, {
        'decision': jsonEncode(decision),
        'params': jsonEncode(params),
      }) ==
      true;
  @override
  Future<void> close(String flowId) async {
    await _invoke<void>('close', flowId);
  }
}

enum QishuiQrPhase {
  waiting,
  scanned,
  rateLimited,
  verificationRequired,
  expired,
  complete,
}

class QishuiQrStatus {
  const QishuiQrStatus(this.phase, this.message, {this.session});
  final QishuiQrPhase phase;
  final String message;
  final QishuiSession? session;
}

/// One QR, one disposable transaction. The service's confirmed state, a fresh
/// cookie jar, and an authenticated Luna profile are all required. A local
/// verification callback or an old cached cookie can never commit an account.
class QishuiQrLogin {
  QishuiQrLogin(this.gateway, {DateTime Function()? now, String? flowId})
    : now = now ?? DateTime.now,
      flowId = flowId ?? randomHex(16);
  final QishuiQrGateway gateway;
  final DateTime Function() now;
  final String flowId;
  final _context = QishuiQrContext();
  static const host = 'api.qishui.com';
  static String randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String _token = '', scanUrl = '';
  String get _portrait =>
      '${flowId.substring(0, 8)}-${flowId.substring(8, 12)}-${flowId.substring(12, 16)}-${flowId.substring(16, 20)}-${flowId.substring(20)}.login';
  bool _closed = false, _busy = false;
  DateTime? _expires, _nextPoll;
  Map<String, dynamic>? _decision;
  QishuiQrStatus _last = const QishuiQrStatus(
    QishuiQrPhase.waiting,
    '等待汽水音乐扫码',
  );
  Map<String, String> get _params => _context.parameters(randomHex(4));
  void _alive() {
    if (_closed) throw const QishuiException('汽水登录已取消');
  }

  static bool trustedScanUrl(String raw) {
    final uri = Uri.tryParse(raw);
    // The PC Passport endpoint returns a BFF scan-confirmation URL. Keep its
    // exact host/path and scan-auth purpose; accepting arbitrary qishui.com
    // pages would turn a server-provided URL into an unrelated login prompt.
    final bffScan =
        uri?.host == 'bff-pc.qishui.com' &&
        uri?.path == '/ucenter_web/app/sdk-next' &&
        uri?.queryParameters['uc_sdk'] == 'scan-auth';
    return uri?.scheme == 'https' &&
        uri!.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443) &&
        (uri.host == 'douyin.com' ||
            uri.host.endsWith('.douyin.com') ||
            uri.host == host ||
            bffScan) &&
        uri.queryParameters['token']?.isNotEmpty == true;
  }

  static bool trustedRedirect(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      (uri.host == host ||
          uri.host == 'sso.douyin.com' ||
          uri.host == 'sso.qishui.com') &&
      uri.path.startsWith('/passport/') &&
      uri.path.contains('sso');

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String> query = const {},
    Map<String, String>? form,
  }) async {
    _alive();
    final entries = form?.entries.toList()
      ?..sort((a, b) => a.key.compareTo(b.key));
    final body = entries
        ?.map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    final traceId = randomHex(4);
    final params = {..._context.parameters(traceId), ...query};
    final sortedParams = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final headers = {
      'Accept': 'application/json, text/javascript',
      'x-tt-passport-verify-portrait': _portrait,
      'x-tt-passport-trace-id': traceId,
      if (body != null) 'Content-Type': 'application/x-www-form-urlencoded',
      if (body != null)
        'x-ss-stub': md5.convert(utf8.encode(body)).toString().toUpperCase(),
    };
    final result = await gateway.request(
      flowId,
      form == null ? 'GET' : 'POST',
      Uri.https(host, path, sortedParams),
      headers,
      body,
    );
    _alive();
    return result;
  }

  Future<void> start() async {
    _alive();
    if (_busy || _token.isNotEmpty) {
      throw const QishuiException('请使用当前二维码或重新打开登录页');
    }
    _busy = true;
    try {
      await gateway.begin(flowId, _context.msToken);
      _alive();
      final old = await gateway.cookies(flowId);
      _alive();
      if (old.any((c) => {'sessionid', 'sessionid_ss'}.contains(c['name']))) {
        throw const QishuiException('本次扫码会话尚未隔离，请重新打开登录页');
      }
      final result = await _request(
        '/passport/web/get_qrcode/',
        query: {
          'next': 'https://$host',
          'need_logo': 'false',
          'need_short_url': 'false',
          'is_new_login': '1',
        },
      );
      final data = sodaMap(result['data']);
      final code = qishuiAuthCode(result);
      final token = '${data['token'] ?? ''}';
      final url = '${data['qrcode_index_url'] ?? ''}';
      if (result['message'] != 'success' || code != '0' && code.isNotEmpty) {
        throw QishuiException(
          '汽水未生成可用的登录二维码${code.isEmpty ? '' : '（$code）'}',
          code: code,
        );
      }
      // A successful upstream response rejected by local validation is not a
      // service business error "0". Report the failed local step separately.
      if (token.isEmpty || token.length > 4096 || url.isEmpty) {
        throw const QishuiException('汽水二维码响应不完整，请重新生成');
      }
      if (!trustedScanUrl(url)) {
        throw const QishuiException('汽水返回的扫码地址未通过校验，请更新应用后重试');
      }
      // Preserve the URL exactly. Rewriting it to a different scan-login path
      // can leave the server stuck at "scanned" after the user confirms.
      _token = token;
      scanUrl = url;
      _expires = now().add(const Duration(minutes: 3));
    } finally {
      _busy = false;
    }
  }

  Future<QishuiQrStatus> poll() async {
    _alive();
    if (_token.isEmpty) throw const QishuiException('请先生成二维码');
    if (_expires != null && !now().isBefore(_expires!)) {
      return _last = const QishuiQrStatus(
        QishuiQrPhase.expired,
        '二维码已过期，请重新生成',
      );
    }
    if (_busy ||
        _last.phase == QishuiQrPhase.complete ||
        _decision != null ||
        _nextPoll != null && now().isBefore(_nextPoll!)) {
      return _last;
    }
    _busy = true;
    _nextPoll = now().add(const Duration(milliseconds: 2500));
    try {
      return await _check();
    } finally {
      _busy = false;
    }
  }

  Future<QishuiQrStatus> _check({
    Map<String, String> extra = const {},
    bool resend = false,
  }) async {
    final result = await _request(
      '/passport/web/check_qrconnect/',
      query: {if (resend) 'isResend': 'true'},
      form: {
        ...extra,
        'need_logo': 'false',
        'need_short_url': 'false',
        'is_frontier': 'true',
        'token': _token,
        'is_new_login': '1',
        'next': 'https://$host',
      },
    );
    final data = sodaMap(result['data']);
    final code = qishuiAuthCode(result);
    final status = '${data['status'] ?? ''}'.toLowerCase();
    if (result['message'] != 'success' && (code.isEmpty || code == '0')) {
      throw const QishuiException('汽水尚未接受扫码确认，请重试');
    }
    if (code == '2046') {
      _decision = data;
      _expires = now().add(const Duration(minutes: 10));
      return _last = const QishuiQrStatus(
        QishuiQrPhase.verificationRequired,
        '汽水要求安全验证，请由你本人完成',
      );
    }
    if (code == '7') {
      _nextPoll = now().add(const Duration(seconds: 5));
      return _last = const QishuiQrStatus(
        QishuiQrPhase.rateLimited,
        '汽水暂时限制查询频率，稍后继续确认',
      );
    }
    if (code == '2' || {'expired', 'expire', 'timeout'}.contains(status)) {
      return _last = const QishuiQrStatus(
        QishuiQrPhase.expired,
        '二维码已过期，请重新生成',
      );
    }
    if (code.isNotEmpty && code != '0') {
      final detail = qishuiAuthDescription(
        result,
        secrets: [
          _token,
          flowId,
          _context.msToken,
          _context.deviceId,
          _context.installId,
        ],
      );
      throw QishuiException(
        '汽水扫码确认未完成（$code）${detail.isEmpty ? '' : '：$detail'}',
        code: code,
      );
    }
    if ({'3', 'confirmed', 'success'}.contains(status) ||
        data['logged_in'] == true) {
      return await _finish(data);
    }
    if ({'2', 'scanned'}.contains(status)) {
      return _last = const QishuiQrStatus(
        QishuiQrPhase.scanned,
        '已扫码，请在汽水音乐中确认登录',
      );
    }
    if ({'1', 'new', 'waiting', 'pending'}.contains(status)) {
      return _last = const QishuiQrStatus(QishuiQrPhase.waiting, '等待汽水音乐扫码');
    }
    throw const QishuiException('汽水返回未知扫码状态，请重新生成二维码');
  }

  Future<QishuiQrStatus> verify() async {
    _alive();
    final decision = _decision;
    if (_busy || decision == null) return _last;
    _busy = true;
    try {
      final done = await gateway.verify(flowId, decision, _params);
      _alive();
      if (!done) return _last;
      _decision = null;
      return await _check(
        extra: bizParams(decision['biz_params']),
        resend: true,
      );
    } finally {
      _busy = false;
    }
  }

  /// Opening the official scanner does not create another QR transaction.
  /// The user confirms there; returning to this route resumes the same poll.
  Future<bool> openScanner() async {
    _alive();
    if (_token.isEmpty) return false;
    return gateway.openScanner(flowId);
  }

  static Map<String, String> bizParams(Object? value) {
    if (value is Map) {
      return {
        for (final e in value.entries)
          if (e.value != null)
            '${e.key}': e.value is String
                ? e.value as String
                : jsonEncode(e.value),
      };
    }
    if (value is! String || value.length > 32 * 1024) return {};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return bizParams(decoded);
    } on FormatException {
      /* Query-string representation below. */
    }
    try {
      return Uri.splitQueryString(value);
    } on FormatException {
      return {};
    }
  }

  Future<QishuiQrStatus> _finish(Map<String, dynamic> data) async {
    var cookies = await gateway.cookies(flowId);
    _alive();
    bool authenticated() => cookies.any(
      (c) =>
          {'sessionid', 'sessionid_ss'}.contains(c['name']) &&
          (c['value'] ?? '').isNotEmpty &&
          c['domain'] == host,
    );
    if (!authenticated()) {
      final redirect = Uri.tryParse('${data['redirect_url'] ?? ''}');
      if (redirect == null || !trustedRedirect(redirect)) {
        throw const QishuiException('汽水确认后未返回完整登录态，请重新扫码');
      }
      await gateway.request(flowId, 'GET', redirect, const {
        'Accept': 'application/json, text/javascript',
      }, null);
      _alive();
      cookies = await gateway.cookies(flowId);
      _alive();
    }
    if (!authenticated()) throw const QishuiException('汽水确认后未返回完整登录态，请重新扫码');
    final profile = await _request('/luna/pc/me');
    final profileCode = qishuiAuthCode(profile);
    if (profileCode.isNotEmpty && profileCode != '0') {
      throw const QishuiException('汽水扫码账号资料尚未核验，请重试');
    }
    final container = sodaMap(profile['data']);
    final me = sodaMap(
      profile['my_info'] ??
          profile['user'] ??
          container['my_info'] ??
          container['user'] ??
          (container.isEmpty ? profile : container),
    );
    final uid = '${me['id'] ?? me['user_id'] ?? me['uid'] ?? ''}';
    if (uid.isEmpty ||
        uid.length > 128 ||
        {'0', '-1', 'null'}.contains(uid) ||
        RegExp(r'[\x00-\x20]').hasMatch(uid)) {
      throw const QishuiException('汽水未返回可核验的账号身份，请重新扫码');
    }
    cookies = await gateway.cookies(flowId);
    _alive();
    final session = QishuiSession(
      userId: uid,
      cookies: cookies,
      protocol: QishuiSessionProtocol.web,
      webDeviceId: _context.deviceId,
      webInstallId: _context.installId,
      nickname: '${me['nickname'] ?? me['name'] ?? ''}',
      avatarUrl: sodaPicture(
        me['larger_avatar_url'] ?? me['avatar'] ?? me['url_avatar'],
      ),
    );
    if (!session.complete) throw const QishuiException('汽水登录态不完整，请重新扫码');
    return _last = QishuiQrStatus(
      QishuiQrPhase.complete,
      '账号已核验，正在保存',
      session: session,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _token = '';
    _decision = null;
    try {
      await gateway.close(flowId);
    } on Object {
      /* Disposal cannot replace or erase an existing account. */
    }
  }
}
