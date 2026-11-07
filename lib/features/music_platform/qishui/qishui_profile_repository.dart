import 'dart:typed_data';
import '../data/platform_profile_repository.dart';
import '../domain/platform_profile.dart';
import '../domain/platform_session.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_repository.dart';

class QishuiProfileRepository extends PlatformProfileRepository {
  QishuiProfileRepository(super.api, this.music);
  final QishuiRepository music;
  @override
  Future<PlatformProfileInfo> fetch(PlatformSession session) async {
    if (session.platform != MusicPlatform.qishui ||
        session.token != music.credential) {
      throw const QishuiException('汽水账号已变化');
    }
    final user = sodaMap((await music.profile())['my_info']);
    if ('${user['id'] ?? ''}' != session.userId) {
      throw const QishuiException('汽水账号资料不匹配');
    }
    return PlatformProfileInfo(
      '${user['nickname'] ?? session.nickname}',
      sodaPicture(user['larger_avatar_url'] ?? user['medium_avatar_url']),
      signature: user['signature'] as String?,
    );
  }

  @override
  Future<void> save(PlatformSession session, Map<String, Object?> changes) =>
      Future.error(const QishuiException('当前仅支持读取汽水账号资料'));
  @override
  Future<String> uploadAvatar(PlatformSession session, Uint8List bytes) =>
      Future.error(const QishuiException('当前未接入汽水头像上传'));
}
