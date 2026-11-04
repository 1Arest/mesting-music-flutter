import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/music_platform_api.dart';
import '../../music_platform_providers.dart';
import '../../platform_backend_providers.dart';
import '../netease_music_repository.dart';
import 'together_record.dart';

final neteaseTogetherRecordsRepositoryProvider =
    Provider<NeteaseTogetherRecordsRepository>((ref) {
      final music = ref.watch(neteaseMusicRepositoryProvider);
      final identity = ref.watch(platformAccountProvider).value;
      return NeteaseTogetherRecordsRepository(
        music,
        isCurrent: () =>
            ref.mounted &&
            ref.read(usesNeteaseProvider) &&
            ref.read(platformAccountProvider).value?.ownerId ==
                identity?.ownerId &&
            ref.read(platformAccountProvider).value?.token == identity?.token &&
            identical(music, ref.read(neteaseMusicRepositoryProvider)),
      );
    });

/// Read-only ending/history queries, independent of the live room controller.
/// Reading a card never ends/creates/rejoins a room, sends a message or mutates
/// old playback logs. Every await retains the original account snapshot.
class NeteaseTogetherRecordsRepository {
  NeteaseTogetherRecordsRepository(this.music, {bool Function()? isCurrent})
    : _isCurrent = isCurrent ?? (() => true),
      _ownerId = music.api.session?.userId,
      _credential = music.credential;
  final NeteaseMusicRepository music;
  final bool Function() _isCurrent;
  final String? _ownerId, _credential;
  static const _readPaths = {
    '/api/listen/together/full/records',
    '/api/listen/together/record/get',
    '/api/listen/together/room/songs/list',
  };

  void checkOwner() {
    if (!_isCurrent() ||
        _ownerId == null ||
        _credential == null ||
        music.api.session?.userId != _ownerId ||
        music.api.session?.credentialId != _credential) {
      throw const MusicPlatformException('账号已变化，请返回后重新打开一起听记录');
    }
  }

  String _roomId(String value) {
    final roomId = togetherRecordRoomId(value);
    if (roomId.isEmpty) {
      throw const MusicPlatformException('这条一起听记录缺少有效的房间标识');
    }
    return roomId;
  }

  /// The official bridge declares these reads as GET+encrypt. That does not
  /// establish its underlying wire method. Reuse Mesting's existing EAPI read
  /// adapter instead of inventing a new encrypted-GET protocol. Real-account
  /// acceptance remains a separate device validation from our contract tests.
  Future<Map<String, dynamic>> _read(
    String path,
    Map<String, Object?> data,
  ) async {
    checkOwner();
    if (!_readPaths.contains(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected a together-record read',
      );
    }
    final result = await music.api.request(
      path,
      data,
      expectedCredential: _credential,
    );
    checkOwner();
    if ('${result['code']}' != '200') {
      throw const MusicPlatformException('一起听记录回执不完整，请稍后重新打开');
    }
    return result['data'] is Map
        ? Map<String, dynamic>.from(result['data'] as Map)
        : result;
  }

  Future<NeteaseTogetherHistoryPageData> history({String? cursor}) async {
    if (cursor != null && cursor.length > 4096) {
      throw const MusicPlatformException('一起听历史分页标识无效，请重新加载');
    }
    final row = await _read('/api/listen/together/full/records', {
      'page': {'size': 50, 'cursor': cursor ?? ''},
    });
    if (row['records'] is! List) {
      throw const MusicPlatformException('一起听历史格式暂不可用，请稍后重试');
    }
    final session = music.api.session!;
    return NeteaseTogetherHistoryPageData.fromJson(
      row,
      self: NeteaseTogetherProfile(
        id: session.userId,
        name: session.nickname,
        avatar: session.avatarUrl,
      ),
    );
  }

  Future<NeteaseTogetherRecord> report(String roomId, {String? peerId}) async {
    final validRoom = _roomId(roomId);
    final row = await _read('/api/listen/together/record/get', {
      'roomId': validRoom,
    });
    // Report readers must not turn an unrelated successful response into a
    // synthetic zero-duration report. Valid older reports may omit statistics.
    if (row['userInfo'] is! Map && row['anotherUserInfo'] is! Map) {
      throw const MusicPlatformException('这条一起听记录暂时无法读取，请稍后重试');
    }
    final record = NeteaseTogetherRecord.fromReport(
      row,
      roomId: validRoom,
      selfId: _ownerId!,
      peerId: peerId,
    );
    if (peerId != null &&
        record.peer?.id.isNotEmpty == true &&
        record.peer!.id != peerId) {
      throw const MusicPlatformException('这条一起听记录与当前好友不匹配，请重新打开');
    }
    final profiles = await Future.wait([
      _profile(record.self),
      _profile(record.peer),
    ]);
    checkOwner();
    return record.withProfiles(self: profiles[0], peer: profiles[1]);
  }

  /// The report's two identity objects do not carry display names/avatars in
  /// the observed schema. As in the official page, enrich them through the
  /// existing public-user read; a failed profile cannot erase valid statistics.
  Future<NeteaseTogetherProfile?> _profile(
    NeteaseTogetherProfile? profile,
  ) async {
    if (profile == null || profile.id.isEmpty) return profile;
    checkOwner();
    try {
      final result = await music.call('/user/detail', {'uid': profile.id});
      checkOwner();
      final value = NeteaseMusicRepository.object(result['profile']);
      if ('${value['userId'] ?? ''}' != profile.id) return profile;
      final display = NeteaseTogetherProfile.fromJson(value);
      return NeteaseTogetherProfile(
        id: profile.id,
        name: display.name,
        avatar: display.avatar,
        online: profile.online,
      );
    } catch (_) {
      // Account/platform changes are not an optional display-data failure.
      checkOwner();
      return profile;
    }
  }

  /// Song IDs are a separate read used only if the user requests collection.
  /// Loading a report does not eagerly fetch or pretend to collect a playlist.
  Future<List<String>> songIds(String roomId) async {
    final row = await _read('/api/listen/together/room/songs/list', {
      'roomId': _roomId(roomId),
    });
    if (row['songIds'] is! List) {
      throw const MusicPlatformException('本次歌曲列表暂时无法读取，请稍后重试');
    }
    return List.unmodifiable(
      (row['songIds'] as List)
          .map((value) => '$value')
          .where((value) => RegExp(r'^[1-9][0-9]*$').hasMatch(value))
          .toSet(),
    );
  }
}
