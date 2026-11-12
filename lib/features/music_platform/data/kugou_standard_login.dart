import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'kugou_v4_grade_protocol.dart';

/// Only a readable failure leaves this boundary; response bodies, URLs,
/// challenges and credential values must never be included in diagnostics.
class KugouStandardLoginException implements Exception {
  const KugouStandardLoginException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// An in-memory authorization challenge. A different service instance cannot
/// poll it, and creating a newer challenge invalidates the previous one.
class KugouStandardQrChallenge {
  const KugouStandardQrChallenge._({
    required String code,
    required Map<String, String> device,
    required this.expiresAt,
  }) : _code = code,
       _device = device;

  final String _code;
  final Map<String, String> _device;
  final DateTime expiresAt;

  String get qrcodeData => Uri.https(
    'h5.kugou.com',
    '/apps/loginQRCode/html/index.html',
    {'qrcode': _code, 'appid': '1005'},
  ).toString();
}

/// Standard Android 20.8.6 QR authorization, independent of the existing Lite
/// login. [device] must reuse this installation's registered device provider
/// (production passes `KugouOfficialApi.registeredDevice`).
///
/// Native KGQRCodeApi issues the challenge with appid 1005 and the standard
/// signature. The native app then refreshes a confirmed QR token through its
/// private NativeParams token exchange. This adapter instead proves that the
/// issued credential can read the v4 grade service with zero counters before
/// returning it; failed proof never replaces the caller's saved credentials.
/// There is no fallback that labels a Lite token as standard authorization.
class KugouStandardLoginService {
  KugouStandardLoginService({
    required http.Client client,
    required Future<Map<String, String>> Function() device,
    required bool Function() current,
    DateTime Function()? clock,
  }) : _client = client,
       _device = device,
       _current = current,
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final Future<Map<String, String>> Function() _device;
  final bool Function() _current;
  final DateTime Function() _clock;
  KugouStandardQrChallenge? _active;
  int _generation = 0;
  bool _polling = false;

  void cancel() {
    _generation++;
    _active = null;
  }

  void _checkCurrent() {
    if (!_current()) {
      cancel();
      throw const KugouStandardLoginException('账号已切换，请重新打开标准授权');
    }
  }

  void _checkChallenge(KugouStandardQrChallenge challenge) {
    _checkCurrent();
    if (!identical(_active, challenge)) {
      throw const KugouStandardLoginException('二维码已失效，请重新获取');
    }
    if (!_clock().isBefore(challenge.expiresAt)) {
      _active = null;
      throw const KugouStandardLoginException('二维码已过期，请重新获取');
    }
  }

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is num && value.isFinite && value == value.truncate()) {
      return value.toInt();
    }
    return null;
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Map<String, String> _query(Map<String, String> device) => {
    'dfid': device['dfid']!,
    'appid': KugouV4GradeProtocol.standardAppId,
    'mid': device['mid']!,
    'uuid': device['uuid']!,
    'clientver': KugouV4GradeProtocol.standardClientVersion,
    'clienttime': (_clock().millisecondsSinceEpoch ~/ 1000).toString(),
  };

  /// Bounded to one request, with no redirect, credential-bearing error or
  /// automatic retry. The caller controls polling and its route lifetime.
  Future<Map<String, dynamic>> _send(
    Uri uri, {
    String? body,
    required void Function() check,
  }) async {
    check();
    try {
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..followRedirects = false;
      if (body != null) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.body = body;
      }
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
      check();
      if (response.statusCode != 200) {
        throw const KugouStandardLoginException('酷狗授权服务暂不可用，请稍后重试');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        check();
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const KugouStandardLoginException('酷狗授权返回异常，请重新获取二维码');
        }
        bytes.addAll(chunk);
      }
      check();
      final result = jsonDecode(utf8.decode(bytes));
      if (result is! Map) {
        throw const KugouStandardLoginException('酷狗授权返回异常，请重新获取二维码');
      }
      return Map<String, dynamic>.from(result);
    } on KugouStandardLoginException {
      rethrow;
    } catch (_) {
      check();
      throw const KugouStandardLoginException('酷狗授权读取失败，请检查网络后重试');
    }
  }

  Future<KugouStandardQrChallenge> createQr() async {
    _checkCurrent();
    final generation = ++_generation;
    _active = null;
    void check() {
      _checkCurrent();
      if (_generation != generation) {
        throw const KugouStandardLoginException('二维码已失效，请重新获取');
      }
    }

    late final Map<String, String> device;
    try {
      device = Map<String, String>.from(await _device());
    } catch (_) {
      check();
      throw const KugouStandardLoginException('设备注册未完成，请稍后重试标准授权');
    }
    check();
    for (final key in ['mid', 'dfid', 'uuid']) {
      final value = device[key] ?? '';
      if (value.isEmpty || value == '-' || value.length > 128) {
        throw const KugouStandardLoginException('设备注册未完成，请稍后重试标准授权');
      }
    }
    // Both the renamed platform and LoginHistoryUserEntity.TYPE_PHONE are
    // exactly "1" in the shipped 20.8.6 DEX static-field table.
    final query = <String, String>{'plat': '1', 'type': '1', ..._query(device)};
    query['signature'] = KugouV4GradeProtocol.signature(query);
    final response = await _send(
      Uri.https('login-user.kugou.com', '/v2/qrcode', query),
      check: check,
    );
    final code = '${_map(response['data'])['qrcode'] ?? ''}';
    if (_integer(response['error_code']) != 0 ||
        code.isEmpty ||
        code.length > 1024 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(code)) {
      throw const KugouStandardLoginException('酷狗二维码读取失败，请重试');
    }
    check();
    final challenge = KugouStandardQrChallenge._(
      code: code,
      device: Map.unmodifiable(device),
      // Official fragment caps polling at 300 seconds. The product may apply
      // a shorter UI deadline; a successful server response never extends it.
      expiresAt: _clock().add(const Duration(minutes: 5)),
    );
    _active = challenge;
    return challenge;
  }

  Future<Map<String, dynamic>?> poll(KugouStandardQrChallenge challenge) async {
    _checkChallenge(challenge);
    if (_polling) return null;
    _polling = true;
    try {
      void check() => _checkChallenge(challenge);
      final query = <String, String>{
        'qrcode': challenge._code,
        'plat': '1',
        ..._query(challenge._device),
      };
      query['signature'] = KugouV4GradeProtocol.signature(query);
      final response = await _send(
        Uri.https('login-user.kugou.com', '/v2/get_userinfo_qrcode', query),
        check: check,
      );
      if (_integer(response['error_code']) != 0) {
        throw const KugouStandardLoginException('酷狗扫码状态读取失败，请重试');
      }
      final data = _map(response['data']);
      final status = _integer(data['status']);
      if (status == 1 || status == 2) return null;
      if (status != 4) {
        _active = null;
        throw const KugouStandardLoginException('二维码已过期或授权已取消，请重新获取');
      }
      final uid = '${data['userid'] ?? ''}';
      final token = '${data['token'] ?? ''}';
      if ((_integer(uid) ?? 0) <= 0 || token.isEmpty || token.length > 8192) {
        _active = null;
        throw const KugouStandardLoginException('标准授权凭据不完整，请重新扫码');
      }
      try {
        // Validate the newly issued 1005 credential without reporting any
        // listening time. A QR confirmation alone is not saved authorization.
        final proof = KugouV4GradeProtocol.build(
          userId: uid,
          token: token,
          credentialAppId: KugouV4GradeProtocol.standardAppId,
          device: challenge._device,
          clientTimeMs: _clock().millisecondsSinceEpoch,
          includeMedals: false,
        );
        final verified = await _send(
          KugouV4GradeRequest.endpoint.replace(queryParameters: proof.query),
          body: proof.body,
          check: check,
        );
        final grade = _map(verified['data']);
        final level = _integer(grade['p_grade']);
        final nextLevel = _integer(grade['p_next_grade']);
        if (_integer(verified['status']) != 1 ||
            '${grade['userid'] ?? ''}' != uid ||
            (_integer(grade['d_sec']) ?? -1) < 0 ||
            level == null ||
            level < 0 ||
            level > 99 ||
            nextLevel == null ||
            nextLevel < 0 ||
            nextLevel > 99 ||
            [
              'p_grade_point',
              'p_next_grade_point',
              'p_current_point',
            ].any((key) => (_integer(grade[key]) ?? -1) < 0)) {
          throw const KugouStandardLoginException('酷狗标准授权验证未通过，请重新扫码；原账号登录已保留');
        }
        check();
        _active = null;
        return {
          'userid': uid,
          'token': token,
          'vip_token': '${data['vip_token'] ?? ''}',
          'nickname': '${data['nickname'] ?? ''}',
          'avatar': '${data['pic'] ?? ''}',
          'mesting_kugou_appid': 1005,
        };
      } catch (_) {
        _active = null;
        rethrow;
      }
    } finally {
      _polling = false;
    }
  }
}
