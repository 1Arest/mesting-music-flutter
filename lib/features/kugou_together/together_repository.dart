import '../../shared/models/track.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/domain/platform_session.dart';
import 'together_models.dart';

/// All room requests bind to the identity selected when this repository was
/// created. MusicPlatformApi also checks that identity after a response arrives.
class TogetherRepository {
  TogetherRepository(this.api, this.identity);
  final MusicPlatformApi api;
  final PlatformSession identity;

  Future<Map<String, dynamic>> call(
    String domain,
    String operation, [
    Map<String, Object?> body = const {},
  ]) async {
    final result = await api.postJson(
      '/listen/together/$domain',
      body: {'operation': operation, 'biz': 1009, ...body},
      expectedSession: identity,
    );
    final code = togetherText(result, ['error_code', 'errcode', 'err_code']);
    if (result['status']?.toString() == '0' || code.isNotEmpty && code != '0') {
      throw MusicPlatformException(switch (code) {
        '51002' => '请重新登录酷狗账号后使用一起听',
        '20006' => '当前账号已有一起听房间，请先恢复该房间',
        '55004' => '已达到房间创建上限，请先管理现有房间',
        '55006' || '20005' || '20002' => '房间不存在或已解散',
        _ => '一起听暂未完成请求${code.isEmpty ? '' : '（$code）'}，请重试',
      }, code: code);
    }
    return result;
  }

  Future<List<TogetherRoom>> rooms() async {
    final result = await call('music', 'list', {'page': 1, 'pagesize': 30});
    return togetherRows(result)
        .map(TogetherRoom.fromJson)
        .where((r) => r.id.isNotEmpty && !r.closed)
        .toList();
  }

  Future<TogetherRoom> detail(String room) async {
    final result = await call('music', 'detail', {'room_id': room});
    final data = togetherMap(togetherData(result));
    return TogetherRoom.fromJson({'room_id': room, ...data});
  }

  Future<String> currentRoom() async => togetherNestedText(
    await call('room', 'status', {'room_id': ''}),
    ['room_id', 'roomid', 'groupid', 'group_id'],
  );
  Future<String> create(String name) async {
    final payload = await call('room', 'create', {
      'introduction': name.trim(),
      'room_privacy': 2,
      'capacity': 5,
    });
    final id = togetherNestedText(payload, [
      'groupid',
      'group_id',
      'room_id',
      'roomid',
    ]);
    if (id.isEmpty) throw const MusicPlatformException('平台未返回房间号，请刷新恢复当前房间');
    return id;
  }

  Future<void> join(String room) async {
    await call('room', 'join', {'room_id': room});
  }

  Future<void> leave(String room, {required bool owner}) async {
    await call('room', owner ? 'dismiss' : 'leave', {'room_id': room});
  }

  Future<void> heartbeat(String room) async {
    await call('room', 'heartbeat', {'room_id': room});
  }

  Future<List<TogetherMember>> members(String room) async => togetherRows(
    await call('music', 'members', {'room_id': room, 'pagesize': 100}),
  ).map(TogetherMember.fromJson).where((m) => m.id.isNotEmpty).toList();
  Future<List<TogetherSong>> songs(String room) async => togetherRows(
    await call('music', 'playlist', {'room_id': room, 'pagesize': 50}),
  ).map(TogetherSong.fromJson).where((s) => s.hash.isNotEmpty).toList();
  Future<TogetherPlayerSnapshot> player(String room) async =>
      TogetherPlayerSnapshot.parse(
        await call('music', 'sync_player', {'room_id': room}),
      );
  Future<void> initialize(
    String room,
    List<TogetherSong> songs,
    Map<String, Object?> progress,
  ) async {
    await call('music', 'initialize', {
      'room_id': room,
      'audios': songs.take(50).map((s) => s.audio).toList(),
      'progress_info': progress,
      'sendall': 1,
    });
  }

  Future<void> add(
    String room,
    List<TogetherSong> songs,
    String version,
  ) async {
    await call('music', 'music_add', {
      'room_id': room,
      'action': 1,
      'list_version': version,
      'audios': songs.take(50).map((s) => s.audio).toList(),
      'sendall': 1,
    });
  }

  Future<void> switchSong(
    String room,
    TogetherSong song,
    String version,
  ) async {
    await call('music', 'switch_song', {
      'room_id': room,
      'act_type': 1,
      'list_version': version,
      'hash': song.hash,
      'mixsongid': song.mixId,
      'is_auto': 0,
    });
  }

  Future<void> playing(String room, bool playing) async {
    await call('music', 'player_operation', {
      'room_id': room,
      'action': 3,
      'pause': playing ? 1 : 2,
    });
  }

  Future<void> seek(String room, Duration position) async {
    await call('music', 'player_operation', {
      'room_id': room,
      'action': 2,
      'progress': position.inSeconds,
    });
  }

  Future<Track> resolve(String room, TogetherSong song) async {
    final payload = await call('music', 'playback_url', {
      'room_id': room,
      'hash': song.hash,
      'mixsongid': song.mixId,
    });
    String url(Object? value, [int depth = 0]) {
      if (depth > 5) return '';
      if (value is String) {
        final uri = Uri.tryParse(value);
        if (uri != null &&
            const {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty) {
          return value;
        }
      }
      if (value is List) {
        for (final child in value) {
          final found = url(child, depth + 1);
          if (found.isNotEmpty) return found;
        }
      }
      if (value is Map) {
        for (final key in const ['url', 'play_url', 'data']) {
          final found = url(value[key], depth + 1);
          if (found.isNotEmpty) return found;
        }
      }
      return '';
    }

    final media = url(payload);
    if (media.isEmpty) throw const MusicPlatformException('平台暂未提供这首房间歌曲的播放权限');
    final path = Uri.tryParse(media)?.path.toLowerCase() ?? '';
    if (RegExp(r'\.(kgs|kgm|kgma|kgg|vpr)$').hasMatch(path)) {
      throw const MusicPlatformException('平台返回了当前设备不支持的加密音频格式');
    }
    return song.track.copyWith(audioAsset: media);
  }
}
