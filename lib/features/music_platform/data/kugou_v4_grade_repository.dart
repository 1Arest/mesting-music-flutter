import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/platform_session.dart';
import 'kugou_official_api.dart';
import 'kugou_v4_grade_protocol.dart';

/// Separate from the legacy Lite gateway: its baseline and credentials cannot
/// be substituted for standard-grade values or migrated into its journal.
abstract interface class KugouStandardGradeGateway {
  Future<int?> seconds(PlatformSession identity);
  Future<bool> report(
    PlatformSession identity, {
    required int localMillis,
    required int diffSeconds,
  });
}

/// A parsed, explicit upstream business rejection has a known outcome. It is
/// distinct from a timeout/malformed reply, whose write outcome stays unknown.
class KugouStandardGradeRejected extends KugouOfficialException {
  const KugouStandardGradeRejected(super.message, {super.loginRequired});
}

/// The current standard account's v4 transport. This class never queues or
/// retries requests; a reporting timeout remains ambiguous in the caller's
/// claim-before-send journal. Zero-counter reads never resubmit a delta.
class KugouV4GradeRepository implements KugouStandardGradeGateway {
  KugouV4GradeRepository({
    required this.client,
    required this.currentIdentity,
    required this.device,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final http.Client client;
  final PlatformSession? Function() currentIdentity;
  final Future<Map<String, String>> Function() device;
  final DateTime Function() clock;

  void _check(PlatformSession expected) {
    final current = currentIdentity();
    if (expected.platform != MusicPlatform.kugou ||
        expected.kugouAppId != 1005 ||
        expected.kugouStandardToken.isEmpty) {
      throw const KugouOfficialException(
        '此官方服务需要为当前酷狗账号完成标准版授权',
        loginRequired: true,
      );
    }
    if (current?.platform != expected.platform ||
        current?.userId != expected.userId ||
        current?.token != expected.token ||
        current?.kugouStandardToken != expected.kugouStandardToken) {
      throw const KugouOfficialException('账号已变化，请稍后重试');
    }
  }

  static Map<String, dynamic> _data(Map<String, dynamic> payload) {
    Object? data = payload['data'];
    if (data is String) data = jsonDecode(data);
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  /// Exposes the same official profile read to the grade UI. It carries no
  /// locally measured counter and therefore has no reporting side effect.
  Future<Map<String, dynamic>> readProfile(PlatformSession identity) =>
      _request(identity);

  @override
  Future<int?> seconds(PlatformSession identity) async {
    final value = int.tryParse('${_data(await _request(identity))['d_sec']}');
    return value != null && value >= 0 ? value : null;
  }

  @override
  Future<bool> report(
    PlatformSession identity, {
    required int localMillis,
    required int diffSeconds,
  }) async {
    if (localMillis < 0 || diffSeconds <= 0) {
      throw ArgumentError(
        'Only a genuine positive measured delta is eligible.',
      );
    }
    await _request(
      identity,
      localMillis: localMillis,
      diffSeconds: diffSeconds,
    );
    return true;
  }

  Future<Map<String, dynamic>> _request(
    PlatformSession identity, {
    int localMillis = 0,
    int diffSeconds = 0,
  }) async {
    _check(identity);
    final registered = await device();
    _check(identity);
    final encoded = KugouV4GradeProtocol.build(
      userId: identity.userId,
      token: identity.kugouStandardToken,
      credentialAppId: '${identity.kugouAppId}',
      credentialClientVersion: '${identity.kugouClientVersion}',
      device: registered,
      clientTimeMs: clock().millisecondsSinceEpoch,
      localMillis: localMillis,
      diffSeconds: diffSeconds,
    );
    final uri = KugouV4GradeRequest.endpoint.replace(
      queryParameters: encoded.query,
    );
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/json;charset=utf-8',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      })
      ..body = encoded.body;
    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) throw const FormatException();
      }
      _check(identity);
      if (response.statusCode != 200) {
        throw const KugouOfficialException('酷狗等级服务暂时不可用，请稍后重试');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException();
      final payload = Map<String, dynamic>.from(decoded);
      final codes = [
        for (final key in ['errcode', 'error_code', 'err_code'])
          if (payload.containsKey(key)) '${payload[key]}',
      ];
      final code = codes.firstWhere((value) => value != '0', orElse: () => '0');
      if ('${payload['status']}' != '1' || code != '0') {
        final auth = {'30000', '20018', '20010'}.contains(code);
        throw KugouStandardGradeRejected(
          auth ? '请为当前酷狗账号重新完成标准版授权' : '酷狗未确认这次等级请求',
          loginRequired: auth,
        );
      }
      final data = _data(payload);
      if ('${data['userid']}' != identity.userId) {
        throw const KugouOfficialException('酷狗等级资料与当前账号不一致，请重新授权');
      }
      _check(identity);
      return {...payload, 'data': data};
    } on KugouOfficialException {
      rethrow;
    } on Object {
      // Only a fixed categorical error crosses this boundary. Never expose the
      // signed URL, encrypted payload or upstream body in diagnostics.
      throw const KugouOfficialException('酷狗等级读取或回执未确认，请稍后核对');
    }
  }
}
