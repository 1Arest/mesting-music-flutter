import 'qishui_api.dart' show qishuiMix;

/// One coherent mobile Passport contract, pinned to the public 19.0.0 APK
/// installed on the user's phone. REA traced DefaultAccountManager to the
/// legacy SendCodeApiThread/QuickLoginApiThread, not the coexisting SaaS DTO.
/// These constants describe the wire contract; they do not claim that Mesting
/// has the official package signature, a BDInstall registration, or a native
/// security context. Never silently try another branch by sending a second SMS.
abstract final class QishuiPhoneProtocol {
  static const query = {
    'version_name': '19.0.0',
    'version_code': '100190050',
    'passport-sdk-version': '601397',
    'request_from_account_sdk': '1',
    'is_from_ttaccountsdk': '1',
  };

  static Map<String, String> sendForm(String normalizedMobile) => {
    'mobile': qishuiMix(normalizedMobile),
    'type': qishuiMix('24'),
    'unbind_exist': qishuiMix('0'),
    'mix_mode': '1',
    // No SMS-reading permission or automatic OTP reader is used by Mesting.
    'auto_read': '0',
    'account_sdk_source': 'app',
  };

  static Map<String, String> loginForm(String normalizedMobile, String code) =>
      {
        'mobile': qishuiMix(normalizedMobile),
        'code': qishuiMix(code),
        'mix_mode': '1',
        'account_sdk_source': 'app',
      };
}
