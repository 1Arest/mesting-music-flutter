import 'dart:convert';
import 'dart:math';

/// Disposable PC/Web Passport identity, following the working myMusic flow.
/// These identifiers and the bootstrap nonce belong only to this QR. They are
/// never presented as Android BDInstall registration or native signing factors.
class QishuiQrContext {
  QishuiQrContext() {
    final random = Random.secure();
    String digits(int length) => List.generate(
      length,
      (index) => index == 0 ? random.nextInt(9) + 1 : random.nextInt(10),
    ).join();
    deviceId = digits(16);
    installId = digits(15);
    msToken =
        '${base64Url.encode(List.generate(88, (_) => random.nextInt(256))).replaceAll('=', '')}==';
  }

  late final String deviceId, installId, msToken;

  /// Keep the same web identity through create/check/MFA/profile requests.
  /// The nonce is seeded into the WebView once; the SDK may then update its
  /// own runtime state. Never reset or manufacture a new nonce while polling.
  Map<String, String> parameters(String traceId) => {
    'passport_jssdk_version': '2.4.13',
    'passport_jssdk_type': 'normal',
    'is_from_ttaccountsdk': '1',
    'aid': '386088',
    'language': 'zh',
    'account_sdk_source': 'web',
    'p_js_v': '2.4.13',
    'p_js_t': 'pro',
    'p_zt': '3.3.5',
    'p_ver': '1.0.29',
    // This encoded Passport client-origin marker is part of the reference
    // contract; it is not a navigation target or a claim about a local file.
    'request_host': 'app%3A%2F%2Fresources',
    'p_bd': '1.0.0.41',
    'is_new_login': '1',
    'is_from_iesaccountsaas': '1',
    'device_platform': 'PC',
    'version_code': '3.5.2',
    'account_sdk_source_info': '00',
    'biz_trace_id': traceId,
    'device_id': deviceId,
    'install_id': installId,
    'did': deviceId,
    'iid': installId,
    'msToken': msToken,
  };
}
