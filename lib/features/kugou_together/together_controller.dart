import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/mesting_audio_handler.dart';
import '../../core/audio/playback_providers.dart';
import '../../shared/models/track.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/music_platform_providers.dart';
import 'together_models.dart';
import 'together_repository.dart';

/// Kept alive across page navigation while a room is active. Replacing the
/// platform identity disposes the entire room session and all pending UI work.
final togetherControllerProvider = Provider<TogetherController>((ref) {
  ref.watch(
    platformAccountProvider.select(
      (account) => (account.value?.userId, account.value?.token),
    ),
  );
  final identity = ref.read(platformAccountProvider).value;
  final controller = TogetherController(
    identity == null
        ? null
        : TogetherRepository(ref.watch(musicPlatformApiProvider), identity),
    MestingTogetherPlayback(ref.watch(audioHandlerProvider)),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Small playback port keeps networking/synchronization testable without
/// allocating another audio engine or taking ownership from MestingAudioHandler.
abstract class TogetherPlayback {
  Track? get current;
  List<Track> get queue;
  Duration get position;
  bool get playing;
  Stream<String> get commands;
  Future<void> load(
    TogetherSong song, {
    required bool autoplay,
    required Duration position,
    List<TogetherSong> queue = const [],
  });
  Future<void> setPlaying(bool value);
  Future<void> seek(Duration value);
}

class MestingTogetherPlayback implements TogetherPlayback {
  MestingTogetherPlayback(this.handler);
  final MestingAudioHandler handler;
  @override
  Track? get current => handler.trackForId(handler.mediaItem.value?.id ?? '');
  @override
  List<Track> get queue => handler.persistedQueue;
  @override
  Duration get position => handler.currentPosition;
  @override
  bool get playing => handler.playbackState.value.playing;
  @override
  Stream<String> get commands => handler.userCommandStream;
  @override
  Future<void> load(
    TogetherSong song, {
    required bool autoplay,
    required Duration position,
    List<TogetherSong> queue = const [],
  }) async {
    final tail = queue.where((s) => !s.matches(song.hash, song.mixId));
    await handler.replaceQueue(
      [song.track, ...tail.map((s) => s.track)],
      initialPosition: position,
      autoplay: autoplay,
    );
  }

  @override
  Future<void> setPlaying(bool value) =>
      value ? handler.play() : handler.pause();
  @override
  Future<void> seek(Duration value) => handler.seek(value);
}

enum TogetherFollowAction { none, load, pause, resume, seek }

/// Room hosts are authoritative. Followers seek only outside a 2.5s tolerance;
/// a manually paused/detached guest is never restarted by a polling response.
TogetherFollowAction togetherFollowAction({
  required TogetherPlayerSnapshot remote,
  required TogetherSong? local,
  required bool playing,
  required Duration position,
  required DateTime now,
  required bool detached,
}) {
  if (detached || remote.hash.isEmpty) return TogetherFollowAction.none;
  if (local == null || !local.matches(remote.hash, remote.mixId)) {
    return TogetherFollowAction.load;
  }
  if (!remote.playing && playing) return TogetherFollowAction.pause;
  if (remote.playing && !playing) return TogetherFollowAction.resume;
  if ((remote.projected(now) - position).inMilliseconds.abs() > 2500) {
    return TogetherFollowAction.seek;
  }
  return TogetherFollowAction.none;
}

String parseTogetherRoomId(String input) {
  var value = input.trim();
  final uri = Uri.tryParse(value);
  if (uri?.hasScheme == true) {
    value =
        uri!.queryParameters['room_id'] ?? uri.queryParameters['roomid'] ?? '';
  } else if (value.contains('房间号')) {
    value = value
        .split('房间号')
        .last
        .replaceFirst(RegExp(r'^\s*[:：]\s*'), '')
        .trim();
  }
  return RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value) ? value : '';
}

class TogetherController extends ChangeNotifier with WidgetsBindingObserver {
  TogetherController(this.repository, this.playback) {
    WidgetsBinding.instance.addObserver(this);
    _commands = playback.commands.listen(_onCommand);
  }
  final TogetherRepository? repository;
  final TogetherPlayback playback;
  StreamSubscription<String>? _commands;
  Timer? _pollTimer, _heartbeatTimer, _commandDebounce;
  bool _disposed = false,
      _polling = false,
      _heartbeating = false,
      _applying = false;
  bool _background = false, _adoptOwnerSnapshot = false;
  int _generation = 0, _pollCount = 0;
  TogetherRoom? room;
  List<TogetherRoom> rooms = const [];
  List<TogetherMember> members = const [];
  List<TogetherSong> songs = const [];
  TogetherPlayerSnapshot? remote;
  bool busy = false, loadingRooms = false, owner = false, detached = false;
  String? error, roomsError;
  DateTime? lastSync;
  bool get signedIn => repository != null;
  bool get active => room != null;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  TogetherRepository get _api =>
      repository ?? (throw const MusicPlatformException('请先登录酷狗账号'));

  Future<bool> _run(Future<void> Function() operation) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    _changed();
    try {
      await operation();
      return true;
    } catch (failure) {
      error = failure is MusicPlatformException
          ? failure.message
          : '一起听操作未完成，请重试';
      return false;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> loadRooms() async {
    if (loadingRooms || !signedIn) return;
    final generation = _generation;
    loadingRooms = true;
    roomsError = null;
    _changed();
    try {
      final result = await _api.rooms();
      if (_current(generation)) rooms = result;
    } catch (failure) {
      if (_current(generation)) {
        roomsError = failure is MusicPlatformException
            ? failure.message
            : '房间暂未加载，请重试';
      }
    } finally {
      loadingRooms = false;
      _changed();
    }
  }

  Future<String> _existing() async {
    try {
      return await _api.currentRoom();
    } on MusicPlatformException catch (e) {
      // These are the upstream's explicit no-session/no-room responses.
      if (const {'20002', '55006', '20005'}.contains(e.code)) return '';
      rethrow;
    }
  }

  Future<bool> restore() => _run(() async {
    final id = await _existing();
    if (id.isEmpty) throw const MusicPlatformException('当前账号没有进行中的一起听房间');
    await _enter(id, join: false, adopt: true);
  });

  Future<bool> create(String name) => _run(() async {
    if (name.trim().isEmpty) throw const MusicPlatformException('请填写房间名称');
    final existing = await _existing();
    if (existing.isNotEmpty) {
      await _enter(existing, join: false, adopt: true);
      return;
    }
    final initial = playback.queue
        .map(TogetherSong.fromTrack)
        .whereType<TogetherSong>()
        .take(50)
        .toList();
    if (initial.isEmpty) {
      throw const MusicPlatformException('先播放一首酷狗歌曲，再创建一起听房间');
    }
    final id = await _api.create(name.trim());
    try {
      await _api.initialize(id, initial, {
        'hash': initial.first.hash,
        'album_audio_id': initial.first.mixId,
        'progress': playback.position.inSeconds,
        'pause': playback.playing ? 1 : 2,
        'play_mode': '1',
      });
    } catch (_) {
      // A failed initialization must not leave an unusable room occupying the
      // account. Cleanup is attempted once; a timeout is never blindly retried.
      try {
        await _api.leave(id, owner: true);
      } catch (_) {
        /* Restore remains available. */
      }
      rethrow;
    }
    await _enter(id, join: false, forceOwner: true, initial: initial);
  });

  Future<bool> join(String input) => _run(() async {
    final id = parseTogetherRoomId(input);
    if (id.isEmpty) throw const MusicPlatformException('请输入有效的房间号或邀请链接');
    final existing = await _existing();
    if (existing.isNotEmpty && existing != id) {
      throw const MusicPlatformException('当前账号已有一起听房间，请先恢复并退出该房间');
    }
    await _enter(id, join: existing != id, adopt: true);
  });

  Future<void> _enter(
    String id, {
    required bool join,
    bool adopt = false,
    bool forceOwner = false,
    List<TogetherSong> initial = const [],
  }) async {
    final detail = await _api.detail(id);
    if (detail.closed) throw const MusicPlatformException('房间已解散');
    if (join) await _api.join(id);
    if (_disposed) return;
    _generation++;
    room = detail;
    owner = forceOwner || detail.ownerId == repository?.identity.userId;
    songs = initial;
    members = const [];
    remote = null;
    detached = false;
    _adoptOwnerSnapshot = adopt && owner;
    _pollCount = 0;
    _startTimers();
    _changed();
    await _poll(force: true);
  }

  Future<bool> leave() => _run(() async {
    final current = room;
    if (current == null) return;
    await _api.leave(current.id, owner: owner);
    _generation++;
    _stopTimers();
    room = null;
    remote = null;
    songs = const [];
    members = const [];
    detached = false;
    owner = false;
    lastSync = null;
  });

  void _startTimers() {
    _stopTimers();
    _pollTimer = Timer.periodic(
      Duration(seconds: _background ? 10 : 3),
      (_) => unawaited(_poll()),
    );
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_heartbeat()),
    );
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _commandDebounce?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _stopTimers();
      return;
    }
    // Audio stays on the foreground media service. Keep the room alive while
    // backgrounded, but lower polling rather than running foreground UI work.
    _background = state != AppLifecycleState.resumed;
    if (active) {
      _startTimers();
      if (!_background) unawaited(_poll(force: true));
    }
  }

  void _onCommand(String command) {
    if (!active || _applying) return;
    if (!owner &&
        const {
          'play',
          'pause',
          'stop',
          'seek',
          'skipNext',
          'skipPrevious',
          'playSingleTrack',
          'replaceQueue',
          'clearSession',
        }.contains(command)) {
      detached = true;
      _changed();
    } else if (owner) {
      _commandDebounce?.cancel();
      _commandDebounce = Timer(
        const Duration(milliseconds: 450),
        () => unawaited(_poll()),
      );
    }
  }

  Future<void> _heartbeat() async {
    if (_heartbeating || !active || _disposed) return;
    _heartbeating = true;
    final generation = _generation, id = room!.id;
    try {
      await _api.heartbeat(id);
    } catch (failure) {
      if (_current(generation)) {
        error = failure is MusicPlatformException
            ? failure.message
            : '房间连接暂时中断，正在等待重连';
        _changed();
      }
    } finally {
      _heartbeating = false;
    }
  }

  Future<void> refresh() => _poll(force: true);
  Future<void> follow() async {
    detached = false;
    _changed();
    await _poll(force: true);
  }

  Future<void> _poll({bool force = false}) async {
    if (_polling || !active || _disposed) return;
    _polling = true;
    final generation = _generation, id = room!.id;
    try {
      var snapshot = await _api.player(id);
      if (!_current(generation)) return;
      if (force ||
          songs.isEmpty ||
          snapshot.listVersion != remote?.listVersion) {
        final result = await _api.songs(id);
        if (!_current(generation)) return;
        songs = result;
      }
      if (force || _pollCount++ % 5 == 0) {
        final result = await _api.members(id);
        if (!_current(generation)) return;
        members = result;
      }
      if (owner && !_adoptOwnerSnapshot) {
        await _publishOwner(snapshot, generation);
        if (!_current(generation)) return;
        snapshot = await _api.player(id);
      } else {
        await _applyFollower(snapshot, generation);
        _adoptOwnerSnapshot = false;
      }
      if (!_current(generation)) return;
      remote = snapshot;
      lastSync = DateTime.now();
      error = null;
      _changed();
    } catch (failure) {
      if (_current(generation)) {
        error = failure is MusicPlatformException
            ? failure.message
            : '暂时无法同步房间，请重试';
        _changed();
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _publishOwner(
    TogetherPlayerSnapshot snapshot,
    int generation,
  ) async {
    final track = playback.current;
    final current = track == null ? null : TogetherSong.fromTrack(track);
    if (current == null) {
      throw const MusicPlatformException('当前歌曲无法用于酷狗一起听，请切换到酷狗歌曲');
    }
    final id = room!.id;
    if (!current.matches(snapshot.hash, snapshot.mixId)) {
      var version = snapshot.listVersion;
      if (!songs.any((s) => s.matches(current.hash, current.mixId))) {
        await _api.add(id, [current], version);
        if (!_current(generation)) return;
        // Adding a song can advance list_version. Never send an old optimistic
        // concurrency token in the subsequent switch request.
        version = (await _api.player(id)).listVersion;
      }
      if (!_current(generation)) return;
      await _api.switchSong(id, current, version);
    }
    if (!_current(generation)) return;
    // The host never consumes its own delayed pause/resume echo. Only real
    // player state is written; normal position progression needs no writes.
    if (snapshot.playing != playback.playing) {
      await _api.playing(id, playback.playing);
    }
    if (!_current(generation)) return;
    if ((snapshot.projected(DateTime.now()) - playback.position).inMilliseconds
            .abs() >
        2500) {
      await _api.seek(id, playback.position);
    }
  }

  Future<void> _applyFollower(
    TogetherPlayerSnapshot snapshot,
    int generation,
  ) async {
    final track = playback.current;
    final local = track == null ? null : TogetherSong.fromTrack(track);
    final action = togetherFollowAction(
      remote: snapshot,
      local: local,
      playing: playback.playing,
      position: playback.position,
      now: DateTime.now(),
      detached: detached,
    );
    if (action == TogetherFollowAction.none) return;
    _applying = true;
    try {
      if (action == TogetherFollowAction.load) {
        final song =
            songs
                .where((s) => s.matches(snapshot.hash, snapshot.mixId))
                .firstOrNull ??
            TogetherSong(hash: snapshot.hash, mixId: snapshot.mixId);
        await playback.load(
          song,
          autoplay: false,
          position: snapshot.projected(DateTime.now()),
        );
      }
      if (!_current(generation)) return;
      if (action == TogetherFollowAction.seek ||
          action == TogetherFollowAction.resume) {
        await playback.seek(snapshot.projected(DateTime.now()));
      }
      if (!_current(generation)) return;
      await playback.setPlaying(snapshot.playing);
    } finally {
      _applying = false;
    }
  }

  Future<bool> select(TogetherSong song) => _run(() async {
    if (!owner) throw const MusicPlatformException('房主负责切换歌曲；你可以选择重新跟随房间');
    final id = room?.id;
    if (id == null) return;
    await _api.switchSong(id, song, remote?.listVersion ?? '');
    _applying = true;
    try {
      await playback.load(
        song,
        autoplay: true,
        position: Duration.zero,
        queue: songs,
      );
    } finally {
      _applying = false;
    }
    await refresh();
  });

  Future<bool> addCurrent() => _run(() async {
    if (!owner) throw const MusicPlatformException('只有房主可以修改房间歌单');
    final additions = playback.queue
        .map(TogetherSong.fromTrack)
        .whereType<TogetherSong>()
        .where((s) => !songs.any((old) => old.matches(s.hash, s.mixId)))
        .take(50)
        .toList();
    if (additions.isEmpty) throw const MusicPlatformException('当前待播中没有新的酷狗歌曲');
    await _api.add(room!.id, additions, remote?.listVersion ?? '');
    await refresh();
  });

  /// Called by the app's single playback resolver before ordinary Kugou URLs.
  /// Return null for unrelated tracks; room entitlement failures stay visible.
  Future<Track?> resolveRoomTrack(Track track) async {
    if (!active ||
        track.source != TrackSource.kugou ||
        !track.id.startsWith('kugou_')) {
      return null;
    }
    final hash = track.id.substring(6);
    final song = songs
        .where((s) => s.matches(hash, track.platformSongId))
        .firstOrNull;
    if (song == null &&
        remote?.hash.toLowerCase() != hash.toLowerCase() &&
        track.provider != '酷狗一起听') {
      return null;
    }
    final generation = _generation, id = room!.id;
    final resolved = await _api.resolve(
      id,
      song ?? TogetherSong.fromTrack(track)!,
    );
    if (!_current(generation)) {
      throw const MusicPlatformException('一起听会话已变化，请重新选择歌曲');
    }
    return resolved;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _stopTimers();
    _commands?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
