import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/mesting_audio_handler.dart';
import '../../../../core/audio/playback_providers.dart';
import '../../../../shared/models/track.dart';
import '../../data/music_platform_api.dart';
import '../../platform_backend_providers.dart';
import '../netease_music_repository.dart';
import '../messages/netease_messages_repository.dart';
import '../full/netease_manual_routes.dart';
import 'together_presence.dart';

/// Kept outside pages so dismissing a sheet/chat cannot stop a room. Watching
/// the account recreates and disposes the controller on logout/platform switch.
final neteaseTogetherControllerProvider = Provider<NeteaseTogetherController?>((
  ref,
) {
  if (!ref.watch(usesNeteaseProvider)) return null;
  ref.watch(neteaseMusicRepositoryProvider.select((m) => m.credential));
  final music = ref.read(neteaseMusicRepositoryProvider);
  final controller = NeteaseTogetherController(
    music: music,
    player: _HandlerTogetherPlayer(ref.watch(audioHandlerProvider)),
    messages: ref.read(neteaseMessagesRepositoryProvider),
    isCurrent: () => music.api.session?.credentialId == music.credential,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

abstract interface class NeteaseTogetherPlayer {
  Track? get track;
  List<Track> get tracks;
  bool get playing;
  Duration get position;
  Stream<String> get commands;
  Stream<String> get trackChanges;
  Future<void> apply(
    List<Track> queue,
    String songId,
    Duration position,
    bool playing,
  );
}

class _HandlerTogetherPlayer implements NeteaseTogetherPlayer {
  _HandlerTogetherPlayer(this.handler);
  final MestingAudioHandler handler;
  @override
  Track? get track => handler.trackForId(handler.mediaItem.value?.id ?? '');
  @override
  List<Track> get tracks => handler.queue.value
      .map((m) => handler.trackForId(m.id))
      .whereType<Track>()
      .toList();
  @override
  bool get playing => handler.playbackState.value.playing;
  @override
  Duration get position => handler.currentPosition;
  @override
  Stream<String> get commands => handler.userCommandStream;
  @override
  Stream<String> get trackChanges =>
      handler.mediaItem.map((m) => m?.id ?? '').distinct();
  @override
  Future<void> apply(
    List<Track> queue,
    String songId,
    Duration position,
    bool playing,
  ) async {
    if (track?.platformSongId != songId) {
      final index = queue.indexWhere((t) => t.platformSongId == songId);
      if (index < 0) return;
      await handler.replaceQueue(
        queue,
        initialIndex: index,
        initialPosition: position,
        autoplay: playing,
      );
    } else {
      if ((handler.currentPosition - position).inMilliseconds.abs() > 1500) {
        await handler.seek(position);
      }
      if (playing && !this.playing) await handler.play();
      if (!playing && this.playing) await handler.pause();
    }
  }
}

class NeteaseTogetherInvitation {
  const NeteaseTogetherInvitation(this.room, this.inviter, [this.songId = '']);
  final String room, inviter, songId;
  static NeteaseTogetherInvitation? parse(String text) {
    final match = RegExp(
      r'https://st\.music\.163\.com/listen-together/share/\?[^\s]+',
    ).firstMatch(text);
    final uri = Uri.tryParse(match?.group(0) ?? text.trim());
    if (uri?.scheme != 'https' ||
        uri?.userInfo.isNotEmpty == true ||
        uri?.host != 'st.music.163.com' ||
        uri?.path != '/listen-together/share/') {
      return null;
    }
    final room = uri!.queryParameters['roomId'] ?? '',
        inviter = uri.queryParameters['inviterId'] ?? '';
    if (!RegExp(r'^[\w-]+$').hasMatch(room) ||
        !RegExp(r'^\d+$').hasMatch(inviter)) {
      return null;
    }
    return NeteaseTogetherInvitation(
      room,
      inviter,
      uri.queryParameters['songId'] ?? '',
    );
  }
}

/// Mutation requests are serialized and never replayed. Polling is read-only
/// plus the protocol heartbeat; it is independent of navigation and supports
/// playback while the audio foreground service keeps the process running.
class NeteaseTogetherController extends ChangeNotifier {
  NeteaseTogetherController({
    required this.music,
    required this.player,
    required this.messages,
    required this.isCurrent,
    this.automaticTimer = true,
    this.locationGateway = const TogetherLocationGateway(),
  });
  final NeteaseMusicRepository music;
  final NeteaseTogetherPlayer player;
  final NeteaseMessagesRepository messages;
  final bool Function() isCurrent;
  final bool automaticTimer;
  final TogetherLocationGateway locationGateway;
  TogetherDistance distance = const TogetherDistance();
  String? presenceNotice;
  bool locationEnabled = false, locating = false;
  Duration? _togetherDuration;
  final _presenceClock = Stopwatch();
  DateTime? _presenceFetchedAt;
  int _locationEpoch = 0;
  NeteasePerson get self => NeteasePerson(
    music.api.session?.userId ?? '',
    music.api.session?.nickname ?? '我',
    music.api.session?.avatarUrl ?? '',
  );
  List<NeteasePerson> get peers =>
      members.where((p) => p.id.isNotEmpty && p.id != self.id).toList();
  Duration? get togetherDuration => _togetherDuration == null
      ? null
      : _togetherDuration! + _presenceClock.elapsed;
  String? roomId, error, notice;
  List<NeteasePerson> members = [];
  List<Track> sharedTracks = [];
  bool busy = false, _disposed = false, _ticking = false, _applying = false;
  bool ending = false;
  int _syncEpoch = 0;
  int _sequence = 1;
  String _formerSong = '-1', _lastRemote = '';
  Timer? _timer;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _tail = Future.value();
  bool get current => !_disposed && isCurrent();
  bool get active => roomId != null;
  bool _syncCurrent(int epoch) => current && !ending && epoch == _syncEpoch;
  void _resetPresence() {
    _locationEpoch++;
    distance = const TogetherDistance();
    locationEnabled = locating = false;
    presenceNotice = null;
    _togetherDuration = null;
    _presenceClock.reset();
    _presenceClock.stop();
    _presenceFetchedAt = null;
  }

  /// A location request never holds the playback mutation queue or suppresses
  /// heartbeats while the user is choosing a permission. Late fixes are bound
  /// to both this account and this exact room generation.
  Future<void> enableLocation() async {
    if (!current || ending || roomId == null || locating) return;
    final room = roomId, epoch = ++_locationEpoch;
    locating = true;
    presenceNotice = null;
    _notify();
    bool valid() => current && roomId == room && epoch == _locationEpoch;
    try {
      final fix = await locationGateway.requestFix();
      if (!valid()) return;
      final report = await _call('/listentogether/user/gps/report', {
        'roomId': room,
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'opened': true,
        'privacy': true,
      });
      if (!valid()) return;
      if (report['success'] == false ||
          NeteaseMusicRepository.object(report['data'])['success'] == false) {
        throw const MusicPlatformException('平台未确认位置共享，请重试');
      }
      locationEnabled = true;
      await _refreshPresence(force: true);
    } catch (e) {
      if (valid()) {
        presenceNotice = e is PlatformException
            ? e.message ?? '位置暂不可用，请稍后重试'
            : '位置共享未获确认，请重试';
      }
    } finally {
      if (valid()) {
        locating = false;
        _notify();
      }
    }
  }

  Future<void> disableLocation() async {
    if (!current || ending || roomId == null || locating) return;
    final room = roomId;
    ++_locationEpoch;
    locating = true;
    _notify();
    try {
      final report = await _call('/listentogether/user/gps/report', {
        'roomId': room,
        'opened': false,
        'privacy': true,
      });
      if (!current || roomId != room) return;
      if (report['success'] == false ||
          NeteaseMusicRepository.object(report['data'])['success'] == false) {
        throw const MusicPlatformException('平台未确认关闭位置共享');
      }
      locationEnabled = false;
      distance = const TogetherDistance();
      presenceNotice = '已关闭本次房间的位置共享';
    } catch (_) {
      if (current && roomId == room) presenceNotice = '关闭位置共享未获确认，请重试';
    } finally {
      if (current && roomId == room) {
        locating = false;
        _notify();
      }
    }
  }

  Future<void> _refreshPresence({bool force = false}) async {
    final epoch = _syncEpoch;
    final room = roomId, peer = peers.firstOrNull;
    if (!_syncCurrent(epoch) || room == null || peer == null) return;
    if (!force &&
        _presenceFetchedAt != null &&
        DateTime.now().difference(_presenceFetchedAt!).inSeconds < 30) {
      return;
    }
    _presenceFetchedAt = DateTime.now();
    bool valid() =>
        _syncCurrent(epoch) &&
        roomId == room &&
        peers.any((p) => p.id == peer.id);
    try {
      final response = await _call('/listentogether/relation/statistics/get', {
        'roomId': room,
        'roomUserIds': [peer.id],
      });
      if (!valid()) return;
      final data = NeteaseMusicRepository.object(response['data']);
      // Official total/currentConnectionTime fields are seconds, not ms.
      // Never infer historical time from when this widget happened to mount.
      final seconds = int.tryParse(
        '${data['totalConnectionTime'] ?? data['currentConnectionTime']}',
      );
      if (seconds != null && seconds >= 0 && seconds < 100 * 366 * 86400) {
        _togetherDuration = Duration(seconds: seconds);
        _presenceClock
          ..reset()
          ..start();
      }
    } catch (_) {
      /* Presence failure must not stop audio synchronization. */
    }
    if (locationEnabled && valid()) {
      try {
        final response = await _call('/listentogether/distance/get', {
          'roomId': room,
          'otherUserId': peer.id,
        });
        if (valid() && locationEnabled) {
          distance = TogetherDistance.parse(response['data']);
          presenceNotice = null;
        }
      } catch (_) {
        if (valid()) presenceNotice = '距离暂时无法刷新，仍在同步播放';
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _call(
    String route, [
    Map<String, Object?> query = const {},
  ]) {
    if (!current) throw const MusicPlatformException('账号已变化，一起听已停止');
    final c = neteaseCompleteContract(route, query)!;
    return music.api.request(
      c.path,
      c.data,
      weapi: c.weapi,
      expectedCredential: music.credential,
    );
  }

  Future<void> _action(Future<void> Function() action) async {
    if (busy || !current) return;
    busy = true;
    error = null;
    notice = null;
    _notify();
    try {
      await action();
    } catch (e) {
      if (current) error = '$e\n请刷新房间状态核对结果后再操作。';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> restore() => _action(() async {
    await _refresh();
    if (roomId != null) {
      await _loadQueue();
      _start();
    }
  });
  Future<void> _ensureRoom() async {
    if (roomId != null) return;
    if (player.track?.source != TrackSource.netease) {
      throw const MusicPlatformException('请先播放一首网易云歌曲，再邀请朋友');
    }
    // Adopt an existing official room before creating another one.
    await _refresh();
    if (roomId != null) {
      await _loadQueue();
      _start();
      return;
    }
    final response = NeteaseMusicRepository.object(
      (await _call('/listentogether/room/create'))['data'],
    );
    final room = NeteaseMusicRepository.object(response['roomInfo']);
    final id = '${room['roomId'] ?? response['roomId'] ?? ''}';
    if (id.isEmpty) throw const MusicPlatformException('平台未返回一起听房间');
    if (!current) return;
    roomId = id;
    _start();
    await _publishQueue();
    await _report('GOTO');
    await _refresh();
  }

  Future<void> create() => _action(_ensureRoom);
  String get invitationLink => roomId == null
      ? ''
      : Uri.https('st.music.163.com', '/listen-together/share/', {
          'songId':
              player.track?.platformSongId ??
              sharedTracks.firstOrNull?.platformSongId ??
              '0',
          'roomId': roomId!,
          'inviterId': music.api.session!.userId,
        }).toString();
  Future<void> invite(NeteasePerson peer) => _action(() async {
    await _ensureRoom();
    if (!current || roomId == null) return;
    await messages.sendText(
      peer.id,
      '邀请你一起听${player.track == null ? '' : '《${player.track!.title}》'}\n$invitationLink',
    );
    if (current) notice = '已邀请${peer.name}，等待对方加入';
  });
  Future<void> join(String input) => _action(() async {
    final invitation = NeteaseTogetherInvitation.parse(input);
    if (invitation == null) throw const MusicPlatformException('请粘贴网易云一起听邀请链接');
    await _call('/listentogether/accept', {
      'roomId': invitation.room,
      'inviterId': invitation.inviter,
    });
    if (!current) return;
    roomId = invitation.room;
    await _refresh();
    await _loadQueue();
    final songId =
        sharedTracks.any((t) => t.platformSongId == invitation.songId)
        ? invitation.songId
        : sharedTracks.firstOrNull?.platformSongId;
    if (current && songId != null) {
      _applying = true;
      try {
        await player.apply(sharedTracks, songId, Duration.zero, true);
      } finally {
        _applying = false;
      }
    }
    _start();
    if (current) await _report('PLAY', heartbeat: true);
    notice = '已加入一起听';
  });
  Future<void> end() => _action(() async {
    if (roomId == null) return;
    final room = roomId;
    // Invalidate outstanding reads/queued commands before sending the one-shot
    // exit. A slow status response must not recreate the room or change audio.
    ++_syncEpoch;
    ++_locationEpoch;
    locating = false;
    ending = true;
    _notify();
    try {
      final r = await _call('/listentogether/end', {'roomId': room});
      if (r['success'] == false ||
          NeteaseMusicRepository.object(r['data'])['success'] == false) {
        throw const MusicPlatformException('平台未确认退出一起听');
      }
      if (!current || roomId != room) return;
      _stop();
      roomId = null;
      _lastRemote = '';
      _resetPresence();
      members = [];
      sharedTracks = [];
      notice = '已退出一起听，保留本机播放';
    } finally {
      // Rejected/unknown exits retain the room and allow explicit refresh.
      ending = false;
    }
  });
  Future<void> shareCurrentQueue() => _action(_publishQueue);
  Future<void> _publishQueue() async {
    final epoch = _syncEpoch, room = roomId;
    if (!_syncCurrent(epoch)) return;
    final queue = player.tracks
        .where((t) => t.source == TrackSource.netease)
        .toList();
    if (roomId == null || queue.isEmpty) return;
    final ids = queue
        .map((t) => t.platformSongId)
        .where((id) => RegExp(r'^\d+$').hasMatch(id))
        .join(',');
    await _call('/listentogether/sync/list/command', {
      'roomId': roomId,
      'commandType': 'REPLACE',
      'userId': music.api.session!.userId,
      'version': _sequence++,
      'playMode': 'ORDER_LOOP',
      'randomList': ids,
      'displayList': ids,
    });
    if (_syncCurrent(epoch) && roomId == room) sharedTracks = queue;
  }

  Future<void> _refresh() async {
    final epoch = _syncEpoch;
    final data = NeteaseMusicRepository.object(
      (await _call('/listentogether/status'))['data'],
    );
    if (!_syncCurrent(epoch)) return;
    if (data['inRoom'] == false) {
      _stop();
      roomId = null;
      _resetPresence();
      members = [];
      sharedTracks = [];
      return;
    }
    final room = NeteaseMusicRepository.object(data['roomInfo']);
    final id = '${room['roomId'] ?? ''}';
    if (id.isNotEmpty) {
      if (id != roomId) _resetPresence();
      roomId = id;
    }
    final previousPeers = peers.map((p) => p.id).toSet();
    final users = NeteaseMusicRepository.rows(
      room['roomUsers'] ?? data['roomUsers'],
    );
    members = users.map((u) => NeteasePerson.parse(u['user'] ?? u)).toList();
    final nextPeers = peers.map((p) => p.id).toSet();
    if (!setEquals(previousPeers, nextPeers)) {
      distance = const TogetherDistance();
      _togetherDuration = null;
      _presenceClock
        ..stop()
        ..reset();
      _presenceFetchedAt = null;
    }
    if (roomId != null) {
      final check = NeteaseMusicRepository.object(
        (await _call('/listentogether/room/check', {'roomId': roomId}))['data'],
      );
      if (!_syncCurrent(epoch)) return;
      await _remote(check);
      if (!_syncCurrent(epoch)) return;
    }
    await _remote({...data, ...room});
    if (peers.isEmpty || error != null) _presenceClock.stop();
    if (_syncCurrent(epoch)) await _refreshPresence();
  }

  Future<void> _loadQueue() async {
    if (roomId == null) return;
    final epoch = _syncEpoch, room = roomId;
    final data = NeteaseMusicRepository.object(
      (await _call('/listentogether/sync/playlist/get', {
        'roomId': roomId,
      }))['data'],
    );
    if (!_syncCurrent(epoch) || roomId != room) return;
    final playlist = NeteaseMusicRepository.object(data['playlist']);
    final display = playlist['displayList'];
    final raw = display is List
        ? display
        : NeteaseMusicRepository.object(display)['result'];
    final ids = (raw is List ? raw : const [])
        .map((v) => '$v')
        .where((id) => RegExp(r'^\d+$').hasMatch(id))
        .toList();
    if (ids.isNotEmpty) {
      final r = await music.call('/song/detail', {
        'ids': ids.take(500).toList(),
      });
      if (!_syncCurrent(epoch) || roomId != room) return;
      sharedTracks = NeteaseMusicRepository.tracks(r['songs']);
    }
    await _remote(data);
  }

  void _start() {
    if (_subscriptions.isNotEmpty || !current || roomId == null) return;
    _formerSong = player.track?.platformSongId ?? '-1';
    _subscriptions.add(
      player.commands.listen((command) {
        if (_applying || !current || roomId == null) return;
        final action = command == 'seek'
            ? 'seek'
            : command == 'pause'
            ? 'PAUSE'
            : command == 'play'
            ? 'PLAY'
            : 'GOTO';
        _enqueue(action, queue: command == 'replaceQueue');
      }),
    );
    _subscriptions.add(
      player.trackChanges.listen((id) {
        if (!_applying && player.track?.platformSongId != _formerSong) {
          _enqueue('GOTO');
        }
      }),
    );
    if (automaticTimer) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => tick());
    }
  }

  void _enqueue(String action, {bool queue = false}) {
    final epoch = _syncEpoch;
    _tail = _tail
        .then((_) async {
          if (!_syncCurrent(epoch) || roomId == null) return;
          if (queue) await _publishQueue();
          if (!_syncCurrent(epoch) || roomId == null) return;
          await _report(action);
        })
        .catchError((Object e) {
          if (_syncCurrent(epoch) && roomId != null) {
            error = '同步请求未获确认，正在刷新房间状态';
            _notify();
          }
        });
  }

  Future<void> _report(String action, {bool heartbeat = false}) async {
    final epoch = _syncEpoch;
    final track = player.track;
    if (!_syncCurrent(epoch) ||
        roomId == null ||
        track?.source != TrackSource.netease) {
      return;
    }
    final r = await _call(
      heartbeat ? '/listentogether/heatbeat' : '/listentogether/play/command',
      {
        'roomId': roomId,
        'songId': track!.platformSongId,
        'progress': player.position.inMilliseconds,
        'playStatus': player.playing ? 'PLAY' : 'PAUSE',
        if (!heartbeat) ...{
          'commandType': action,
          'formerSongId': _formerSong,
          'targetSongId': track.platformSongId,
          'clientSeq': _sequence++,
        },
      },
    );
    if (!_syncCurrent(epoch)) return;
    _formerSong = track.platformSongId;
    await _remote(NeteaseMusicRepository.object(r['data']));
  }

  Future<void> tick() async {
    if (_ticking || busy || !current || roomId == null) return;
    final epoch = _syncEpoch;
    _ticking = true;
    try {
      await _refresh();
      if (roomId != null && _syncCurrent(epoch)) {
        await _report('PLAY', heartbeat: true);
      }
      if (_syncCurrent(epoch)) error = null;
    } catch (_) {
      if (_syncCurrent(epoch) && roomId != null) {
        error = '一起听连接暂时中断，正在重连';
        _presenceClock.stop();
      }
    } finally {
      _ticking = false;
      _notify();
    }
  }

  /// Servers may include a command in room/status/heartbeat responses. Apply
  /// only an explicit versioned command, never infer a play state from member
  /// data, and suppress local echoes while applying it to the audio handler.
  Future<void> _remote(Map<String, dynamic> data) async {
    final epoch = _syncEpoch, room = roomId;
    if (!_syncCurrent(epoch) || room == null) return;
    Object? raw =
        data['commandInfo'] ?? data['playCommand'] ?? data['playingInfo'];
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return;
      }
    }
    final command = NeteaseMusicRepository.object(raw);
    final seq = command['serverSeq'] ?? command['version'] ?? data['serverSeq'];
    if (seq == null || command.isEmpty || !current) return;
    final token = '$roomId:$seq';
    final songId = '${command['targetSongId'] ?? command['songId'] ?? ''}';
    if (token == _lastRemote ||
        songId.isEmpty ||
        '${command['userId'] ?? ''}' == music.api.session?.userId) {
      return;
    }
    _lastRemote = token;
    _applying = true;
    try {
      if (!sharedTracks.any((t) => t.platformSongId == songId)) {
        await _loadQueue();
      }
      if (_syncCurrent(epoch) && roomId == room) {
        await player.apply(
          sharedTracks,
          songId,
          Duration(milliseconds: int.tryParse('${command['progress']}') ?? 0),
          command['playStatus'] != 'PAUSE',
        );
      }
    } finally {
      _applying = false;
    }
  }

  Future<void> settle() => _tail;
  void _stop() {
    _timer?.cancel();
    _timer = null;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _resetPresence();
    _stop();
    super.dispose();
  }
}
