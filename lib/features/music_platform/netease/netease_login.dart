import '../data/music_platform_api.dart';
import 'netease_api.dart';
import 'netease_session.dart';

enum NeteaseLoginMethod {
  qr('网易云扫码'),
  sms('手机验证码'),
  phonePassword('手机号与密码'),
  email('邮箱与密码');

  const NeteaseLoginMethod(this.label);
  final String label;
}

class NeteaseQrChallenge {
  const NeteaseQrChallenge(this.key);
  final String key;
  String get url =>
      Uri.https('music.163.com', '/login', {'codekey': key}).toString();
}

/// One page owns one login jar. Only the account controller can commit it to
/// secure storage after the user completed authentication on the platform.
class NeteaseLoginService {
  NeteaseLoginService(NeteaseApi active) : api = active.loginClient();
  final NeteaseApi api;

  Future<NeteaseQrChallenge> createQr() async {
    final result = await api.call('/login/qr/key');
    final key = '${result['unikey'] ?? ''}';
    if (key.isEmpty) throw const MusicPlatformException('网易云二维码生成失败，请重试');
    return NeteaseQrChallenge(key);
  }

  Future<NeteaseSession?> poll(NeteaseQrChallenge challenge) async {
    final result = await api.call(
      '/login/qr/check',
      query: {'key': challenge.key},
      allowBusinessError: true,
    );
    switch ('${result['code']}') {
      case '801':
      case '802':
        return null;
      case '800':
        throw const MusicPlatformException('二维码已过期，请刷新');
      case '803':
        return _session(await api.call('/login/status'));
      default:
        throw const MusicPlatformException('网易云扫码未完成，请刷新重试');
    }
  }

  Future<void> sendCode(String phone, String countryCode) async {
    _validatePhone(phone, countryCode);
    final result = await api.call(
      '/captcha/sent',
      query: {'phone': phone, 'countrycode': countryCode},
    );
    if ('${result['code']}' != '200') {
      throw const MusicPlatformException('平台未确认验证码已发送，请稍后重试');
    }
  }

  Future<NeteaseSession> login(
    NeteaseLoginMethod method,
    String account,
    String secret, {
    String countryCode = '86',
  }) async {
    if (account.isEmpty || secret.isEmpty) {
      throw const MusicPlatformException('请完整填写登录信息');
    }
    if (method != NeteaseLoginMethod.email) {
      _validatePhone(account, countryCode);
    }
    if (method == NeteaseLoginMethod.email && !account.contains('@')) {
      throw const MusicPlatformException('请输入网易邮箱账号');
    }
    final result = await api.call(
      method == NeteaseLoginMethod.email ? '/login' : '/login/cellphone',
      query: {
        if (method == NeteaseLoginMethod.email)
          'email': account
        else
          'phone': account,
        'countrycode': countryCode,
        if (method == NeteaseLoginMethod.sms)
          'captcha': secret
        else
          'password': secret,
      },
    );
    return _session(result);
  }

  void _validatePhone(String phone, String countryCode) {
    if (!RegExp(r'^\d{1,4}$').hasMatch(countryCode) ||
        !RegExp(r'^\d{6,15}$').hasMatch(phone) ||
        (countryCode == '86' && !RegExp(r'^1\d{10}$').hasMatch(phone))) {
      throw const MusicPlatformException('请核对国家区号和手机号码');
    }
  }

  NeteaseSession _session(Map<String, dynamic> result) {
    if (result['data'] is Map) {
      result = MusicPlatformApi.objectMap(result['data']);
    }
    final profile = MusicPlatformApi.objectMap(result['profile']);
    final account = MusicPlatformApi.objectMap(result['account']);
    final id = '${profile['userId'] ?? account['id'] ?? ''}';
    if (id.isEmpty || (api.cookies['MUSIC_U'] ?? '').isEmpty) {
      throw const MusicPlatformException('网易云未返回完整登录凭证，请刷新后重试');
    }
    return NeteaseSession(
      userId: id,
      cookies: api.cookies,
      deviceId: api.deviceId,
      nickname: '${profile['nickname'] ?? ''}',
      avatarUrl: '${profile['avatarUrl'] ?? ''}',
    );
  }
}
