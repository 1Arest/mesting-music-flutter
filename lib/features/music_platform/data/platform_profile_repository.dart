import 'dart:convert';
import 'dart:typed_data';
import '../domain/platform_profile.dart';
import '../domain/platform_session.dart';
import 'music_platform_api.dart';

/// Mirrors md3Music v6.1.0's /user/update and two-step avatar upload. Writes
/// are never retried: the platform may have accepted a timed-out request.
class PlatformProfileRepository {
  static const maximumAvatarBytes = 2 * 1024 * 1024;
  const PlatformProfileRepository(this.api);
  final MusicPlatformApi api;

  Future<PlatformProfileInfo> fetch(PlatformSession session) async =>
      PlatformProfileInfo.fromJson(
        await api.get('/user/detail', expectedSession: session),
        session,
      );

  Future<void> save(
    PlatformSession session,
    Map<String, Object?> changes,
  ) async {
    if (changes.isEmpty) return;
    const allowed = {
      'nickname',
      'sex',
      'birthday',
      'signature',
      'province',
      'city',
    };
    if (changes.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('Unsupported profile field');
    }
    final result = await api.postJson(
      '/user/update',
      body: changes,
      expectedSession: session,
    );
    _requireSuccess(result);
  }

  Future<String> uploadAvatar(PlatformSession session, Uint8List bytes) async {
    // Base64 expands by 4/3; stay below the embedded server's 4MiB JSON cap.
    if (bytes.length < 12 || bytes.length > maximumAvatarBytes) {
      throw const MusicPlatformException('请选择小于 2 MB 的头像图片');
    }
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8;
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final webp =
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    if (!jpeg && !png && !webp) {
      throw const MusicPlatformException('请选择 JPG、PNG 或 WebP 图片');
    }
    final result = await api.postJson(
      '/user/update/avatar',
      expectedSession: session,
      body: {
        'imgFile': base64Encode(bytes),
        'filename':
            'avatar.${jpeg
                ? 'jpg'
                : png
                ? 'png'
                : 'webp'}',
      },
    );
    _requireSuccess(result);
    final data = MusicPlatformApi.objectMap(result['data']);
    return PlatformSession.picture(
      result['pic'] ?? data['pic'] ?? data['avatar'],
    );
  }

  void _requireSuccess(Map<String, dynamic> result) {
    final code =
        '${result['error_code'] ?? result['err_code'] ?? result['errcode'] ?? 0}';
    final accepted = result['status'] != null
        ? result['status'].toString() == '1'
        : result['code']?.toString() == '0';
    if (!accepted || code != '0') {
      // The raw platform message may echo request data. Expose a bounded code,
      // never a credential, URL, base64 image or the user's full draft.
      final safeCode = RegExp(r'^\d{1,10}$').hasMatch(code) && code != '0'
          ? '（错误码 $code）'
          : '';
      throw MusicPlatformException('酷狗暂未接受修改$safeCode，请稍后重试');
    }
  }
}
