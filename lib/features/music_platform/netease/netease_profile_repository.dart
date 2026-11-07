import 'dart:typed_data';

import '../data/music_platform_api.dart';
import '../data/platform_profile_repository.dart';
import '../domain/platform_profile.dart';
import '../domain/platform_session.dart';
import 'netease_music_repository.dart';

class NeteaseProfileRepository extends PlatformProfileRepository {
  const NeteaseProfileRepository(super.api, this.music);
  final NeteaseMusicRepository music;

  @override
  Future<PlatformProfileInfo> fetch(PlatformSession session) async {
    final result = await music.call('/user/detail', {'uid': session.userId});
    final p = NeteaseMusicRepository.object(result['profile']);
    return PlatformProfileInfo.fromJson({
      ...p,
      'avatar': p['avatarUrl'],
      'sex': p['gender'],
    }, session);
  }

  @override
  Future<void> save(
    PlatformSession session,
    Map<String, Object?> changes,
  ) async {
    if (changes.isEmpty) return;
    final data = {...changes};
    if (data.containsKey('sex')) data['gender'] = data.remove('sex');
    if (data['birthday'] is String) {
      final date = DateTime.tryParse(data['birthday'] as String);
      if (date != null) data['birthday'] = date.millisecondsSinceEpoch;
    }
    await music.call('/user/update', data);
  }

  @override
  Future<String> uploadAvatar(PlatformSession session, Uint8List bytes) async {
    if (bytes.length < 12 ||
        bytes.length > PlatformProfileRepository.maximumAvatarBytes) {
      throw const MusicPlatformException('请选择小于 2 MB 的头像图片');
    }
    return music.api.uploadAvatar(bytes, session.token);
  }
}
