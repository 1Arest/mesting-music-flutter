/// A music-platform identity is independent of the Mesting CloudBase session.
/// Credentials are serialized only into the platform's secure-storage entry.
enum MusicPlatform { kugou, netease }

class PlatformSession {
  const PlatformSession({
    required this.userId,
    required this.token,
    this.vipToken = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.platform = MusicPlatform.kugou,
    this.kugouStandardToken = '',
    this.kugouStandardVipToken = '',
  });

  final String userId;
  final String token;
  final String vipToken;
  final String nickname;
  final String avatarUrl;
  final MusicPlatform platform;

  /// 标准授权作为同一UID的补充凭据；旧音乐协议继续使用自己的Lite登录。
  /// 两份凭据都只进入加密账号仓库，不向偏好、日志或导出提供序列化入口。
  final String kugouStandardToken, kugouStandardVipToken;
  String get kugouOfficialToken =>
      kugouStandardToken.isNotEmpty ? kugouStandardToken : token;
  int get kugouAppId => kugouStandardToken.isNotEmpty ? 1005 : 3116;
  int get kugouClientVersion => kugouAppId == 1005 ? 20869 : 11440;
  String get ownerId => '${platform.name}:$userId';
  String get platformLabel => platform == MusicPlatform.netease ? '网易云' : '酷狗';

  static String picture(Object? value) {
    var text = '${value ?? ''}'.trim().replaceAll('{size}', '400');
    if (text.startsWith('//')) text = 'https:$text';
    final uri = Uri.tryParse(text);
    return uri != null &&
            uri.host.isNotEmpty &&
            {'http', 'https'}.contains(uri.scheme)
        ? text
        : '';
  }

  factory PlatformSession.fromJson(Map<String, dynamic> json) {
    final userId = '${json['userid'] ?? ''}';
    final token = '${json['token'] ?? ''}';
    if (userId.isEmpty || token.isEmpty) {
      throw const FormatException('音乐平台登录凭证不完整');
    }
    return PlatformSession(
      userId: userId,
      token: token,
      vipToken: '${json['vip_token'] ?? ''}',
      nickname: '${json['nickname'] ?? ''}',
      avatarUrl: picture(
        json['avatar'] ?? json['avatarUrl'] ?? json['pic'] ?? json['img'],
      ),
      kugouStandardToken: '${json['mesting_kugou_standard_token'] ?? ''}',
      kugouStandardVipToken:
          '${json['mesting_kugou_standard_vip_token'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
    'userid': userId,
    'token': token,
    'vip_token': vipToken,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    if (kugouStandardToken.isNotEmpty)
      'mesting_kugou_standard_token': kugouStandardToken,
    if (kugouStandardVipToken.isNotEmpty)
      'mesting_kugou_standard_vip_token': kugouStandardVipToken,
  };
}
