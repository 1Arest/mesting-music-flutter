import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_session.dart';

class QishuiVerificationRequired extends QishuiException {
  const QishuiVerificationRequired(this.url, {super.code})
    : super('汽水要求安全验证，请完成后再重试');
  final String url;
}

/// This client has its own ephemeral cookie jar. Merely sending a code never
/// changes the selected music account or writes a persistent credential.
class QishuiLogin {
  QishuiLogin(QishuiApi api) : api = api.loginClient();
  final QishuiApi api;
  String _smsCodeKey = '', _sentMobile = '';
  bool _disposed = false;
  void dispose() {
    _disposed = true;
    api.dispose();
  }

  static String mobile(String area, String phone) {
    final prefix = area.trim().replaceAll(' ', '');
    final number = phone.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\+\d{1,4}$').hasMatch(prefix) ||
        !RegExp(r'^\d{5,15}$').hasMatch(number) ||
        prefix == '+86' && !RegExp(r'^1\d{10}$').hasMatch(number)) {
      throw const QishuiException('请填写正确的区号和手机号');
    }
    return '$prefix$number';
  }

  void _success(Map<String, dynamic> value) {
    final data = sodaMap(value['data']);
    final rawCode =
        '${data['error_code'] ?? value['error_code'] ?? value['status_code'] ?? ''}';
    final code = rawCode.isEmpty || RegExp(r'^-?\d{1,12}$').hasMatch(rawCode)
        ? rawCode
        : 'invalid';
    if (value['message'] == 'success' && (code.isEmpty || code == '0')) return;
    final url =
        '${data['redirect_url'] ?? data['verify_url'] ?? data['captcha_url'] ?? ''}';
    final uri = Uri.tryParse(url);
    if (uri?.scheme == 'https' &&
        uri!.userInfo.isEmpty &&
        (uri.host == 'douyin.com' ||
            uri.host.endsWith('.douyin.com') ||
            uri.host == 'snssdk.com' ||
            uri.host.endsWith('.snssdk.com') ||
            uri.host.endsWith('.bytedance.com'))) {
      throw QishuiVerificationRequired(url, code: code);
    }
    throw QishuiException(
      '汽水未接受本次验证${code.isEmpty ? '' : '（$code）'}',
      code: code,
    );
  }

  Future<void> sendCode(String area, String phone) async {
    final number = mobile(area, phone);
    // A newly requested number cannot inherit the preceding attempt's key.
    _smsCodeKey = '';
    _sentMobile = '';
    late final Map<String, dynamic> value;
    try {
      value = await api.request(
        '/passport/mobile/send_code/',
        authenticated: false,
        write: true,
        allowBusinessError: true,
        query: const {
          'passport-sdk-version': '60651',
          'request_from_account_sdk': '1',
          'is_from_ttaccountsdk': '1',
        },
        form: {
          'mobile': number,
          'type': qishuiMix('24'),
          'mix_mode': '1',
          'is_from_iesaccountsaas': '1',
          'account_sdk_source': 'app',
        },
      );
    } on QishuiException catch (error) {
      // An SMS may arrive after a timeout. Let its owner submit that code
      // without automatically requesting another message or claiming success.
      if (!_disposed && error.unknownWrite) _sentMobile = number;
      rethrow;
    }
    if (_disposed) throw const QishuiException('登录已取消');
    _success(value);
    _smsCodeKey = '${sodaMap(value['data'])['sms_code_key'] ?? ''}';
    _sentMobile = number;
  }

  Future<QishuiSession> login(String area, String phone, String code) async {
    final number = mobile(area, phone);
    if (number != _sentMobile) throw const QishuiException('请先为当前手机号获取验证码');
    if (!RegExp(r'^\d{4,8}$').hasMatch(code.trim())) {
      throw const QishuiException('请填写短信验证码');
    }
    final authenticationRevision = api.authenticationRevision;
    final value = await api.request(
      '/passport/mobile/sms_login/',
      authenticated: false,
      write: true,
      allowBusinessError: true,
      query: const {
        'passport-sdk-version': '60651',
        'request_from_account_sdk': '1',
        'is_from_ttaccountsdk': '1',
      },
      form: {
        'mobile': qishuiMix(number),
        'code': qishuiMix(code.trim()),
        if (_smsCodeKey.isNotEmpty) 'sms_code_key': qishuiMix(_smsCodeKey),
        'mix_mode': '1',
        'is_from_iesaccountsaas': '1',
        'account_sdk_source': 'app',
      },
    );
    if (_disposed) throw const QishuiException('登录已取消');
    _success(value);
    final data = sodaMap(value['data']);
    final user = sodaMap(data['user_info'] ?? data);
    final uid =
        '${user['user_id_str'] ?? user['user_id'] ?? user['uid'] ?? ''}';
    final candidate = api.snapshot(uid);
    if (!candidate.complete ||
        api.authenticationRevision == authenticationRevision) {
      throw const QishuiException('汽水未返回本次登录的完整凭据，请重新登录');
    }
    api.configure(candidate);
    // A business-success response is insufficient: verify the same identity
    // using Luna before a controller may commit this private session.
    final profile = await api.request('/luna/me', get: true);
    if (_disposed) throw const QishuiException('登录已取消');
    final me = sodaMap(
      profile['my_info'] ??
          profile['user'] ??
          sodaMap(profile['data'])['user'] ??
          profile['data'],
    );
    final actualUid = '${me['id'] ?? me['user_id'] ?? me['uid'] ?? ''}';
    // Passport and Luna are separate identity domains. /luna/me reads the
    // authenticated account without a caller-supplied ID; retain both IDs.
    if (actualUid.isEmpty) {
      throw const QishuiException('汽水账号资料核对未完成，请重试');
    }
    return api.snapshot(
      actualUid,
      passportUserId: uid,
      name: '${me['nickname'] ?? me['name'] ?? ''}',
      avatar: sodaPicture(
        me['larger_avatar_url'] ?? me['avatar'] ?? me['url_avatar'],
      ),
    );
  }
}
