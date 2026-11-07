import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/mesting_audio_handler.dart';
import '../../../../core/audio/playback_providers.dart';
import '../../../../shared/models/track.dart';
import '../../data/music_platform_api.dart';
import '../../platform_backend_providers.dart';
import '../netease_music_repository.dart';
import '../netease_fallback.dart';
import '../messages/netease_messages_repository.dart';
import '../full/netease_manual_routes.dart';
import 'together_presence.dart';
import 'together_cumulative.dart';
import 'together_playback_command.dart';
import 'together_background_binding.dart';
import 'together_sync_diagnostics.dart';
import 'together_shared_playlist.dart';

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
    player: _HandlerTogetherPlayer(
      ref.watch(audioHandlerProvider),
      () => ref.read(neteasePlaybackRequestsProvider).cancel(),
    ),
    messages: ref.read(neteaseMessagesRepositoryProvider),
    isCurrent: () => music.api.session?.credentialId == music.credential,
  );
  // Returning from the background refreshes the official room snapshot even
  // when its last foreground poll was recent. The listener never exits a room.
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(controller.resume()),
  );
  final background = TogetherBackgroundBinding(
    changes: controller,
    active: () => controller.current && controller.active && !controller.ending,
    poll: controller.poll,
    diagnostics: controller.diagnostics,
  );
  ref.onDispose(() {
    background.dispose();
    lifecycle.dispose();
    controller.dispose();
  });
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

/// Optional cancellation boundary; old platform/fake adapters keep the stable
/// [NeteaseTogetherPlayer] contract. Production invalidates its exact transport
/// and source-request generation before another remote application can start.
abstract interface class NeteaseTogetherCancelablePlayer {
  void cancelPendingApplication();
}

class _HandlerTogetherPlayer
    implements NeteaseTogetherPlayer, NeteaseTogetherCancelablePlayer {
  _HandlerTogetherPlayer(this.handler, this.cancelSourceRequest);
  final MestingAudioHandler handler;
  final VoidCallback cancelSourceRequest;
  int _application = 0;
  int? _ownedTransportRevision;

  @override
  void cancelPendingApplication() {
    ++_application;
    final owned = _ownedTransportRevision;
    _ownedTransportRevision = null;
    if (owned != null && handler.cancelPendingTogetherPlayback(owned)) {
      cancelSourceRequest();
    }
  }

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
  Stream<String> get commands => handler.togetherUserCommandStream;
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
    final application = ++_application;
    _ownedTransportRevision = handler.transportRevision;
    bool current() =>
        application == _application &&
        handler.transportRevision == _ownedTransportRevision;
    Future<void> own(Future<void> Function() action) {
      // The dedicated handler stream labels origin before async delivery.
      // Real media/user controls remain visible during a remote source load.
      final operation = action();
      _ownedTransportRevision = handler.transportRevision;
      return operation;
    }

    if (track?.platformSongId != songId) {
      final index = queue.indexWhere((t) => t.platformSongId == songId);
      if (index < 0) return;
      await own(
        () => handler.replaceQueue(
          queue,
          initialIndex: index,
          initialPosition: position,
          autoplay: playing,
          togetherGuard: current,
        ),
      );
    } else {
      if ((handler.currentPosition - position).inMilliseconds.abs() > 1500) {
        await own(() => handler.seek(position, togetherGuard: current));
      }
      if (!current()) return;
      if (playing && !this.playing) {
        await own(() => handler.play(togetherGuard: current));
      }
      if (!current()) return;
      if (!playing && this.playing) {
        await own(() => handler.pause(togetherGuard: current));
      }
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
    this.remoteApplicationTimeout = const Duration(seconds: 30),
    TogetherCumulativeClock? cumulativeClock,
    TogetherSyncDiagnostics? diagnostics,
  }) : _cumulativeClock = cumulativeClock ?? TogetherCumulativeClock(),
       diagnostics = diagnostics ?? TogetherSyncDiagnostics.shared;
  final NeteaseMusicRepository music;
  final NeteaseTogetherPlayer player;
  final NeteaseMessagesRepository messages;
  final bool Function() isCurrent;
  final bool automaticTimer;
  final Duration remoteApplicationTimeout;
  final TogetherSyncDiagnostics diagnostics;
  final TogetherLocationGateway locationGateway;
  TogetherDistance distance = const TogetherDistance();
  String? presenceNotice;
  bool locationEnabled = false, locating = false;
  final TogetherCumulativeClock _cumulativeClock;
  DateTime? _presenceFetchedAt;
  int _locationEpoch = 0;
  NeteasePerson get self => NeteasePerson(
    music.api.session?.userId ?? '',
    music.api.session?.nickname ?? '我',
    music.api.session?.avatarUrl ?? '',
  );
  List<NeteasePerson> get peers =>
      members.where((p) => p.id.isNotEmpty && p.id != self.id).toList();

  /// Ordinary Together rooms have two seats. Keep the action contract in the
  /// controller too, so a stale menu or another navigation entry cannot send
  /// an invitation after a friend has joined.
  bool get canInvitePeer => !ending && peers.isEmpty;
  Duration? get togetherDuration => current ? _cumulativeClock.duration : null;
  bool get togetherDurationIsStale => _cumulativeClock.isStale;
  String get togetherDurationLabel {
    final duration = togetherDuration;
    if (duration == null) return '累计时长暂未获取';
    final label = formatTogetherDuration(duration);
    return togetherDurationIsStale ? '$label（上次同步）' : label;
  }

  String? roomId, error, notice;
  List<NeteasePerson> members = [];
  List<Track> sharedTracks = [];
  bool busy = false, _disposed = false, _ticking = false, _applying = false;
  bool ending = false;
  int _syncEpoch = 0;
  int _playlistReadRevision = 0;
  int _sequence = 1;
  String _formerSong = '-1', _lastRemote = '';
  String? _remoteRoom;
  int? _highestRemoteSequence;
  final _pendingRemote = <String>{};
  Future<void> _remoteTail = Future.value();
  int _applicationRevision = 0;
  Completer<void>? _applicationAbort;
  String? _activeRemoteToken;
  int? _activeRemoteSequence;
  TogetherPlaybackCommand? _activeRemoteCommand;
  int _remoteReceived = 0, _remoteApplied = 0, _remoteTimeouts = 0;
  int _requestOrdinal = 0;
  bool _remoteApplicationFailed = false;

  /// Diagnostics expose counts only, with no room, account, friend or song.
  Map<String, int> get synchronizationDiagnostics => {
    'remoteReceived': _remoteReceived,
    'remoteApplied': _remoteApplied,
    'remoteTimeouts': _remoteTimeouts,
  };
  Timer? _timer;
  DateTime? _lastPoll;
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
    _cumulativeClock.clear();
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
    final accountId = self.id;
    final userIds = togetherRelationUserIds(accountId, peer.id);
    if (userIds == null) {
      _cumulativeClock.markStale();
      return;
    }
    if (!force &&
        _presenceFetchedAt != null &&
        DateTime.now().difference(_presenceFetchedAt!).inSeconds < 30) {
      return;
    }
    _presenceFetchedAt = DateTime.now();
    bool valid() =>
        _syncCurrent(epoch) &&
        roomId == room &&
        self.id == accountId &&
        peers.any((p) => p.id == peer.id);
    try {
      final response = await _call('/listentogether/relation/statistics/get', {
        'roomId': room,
        // The official v2 request uses [friend, self], both numeric IDs.
        // Omitting self queries a different/incomplete relation scope.
        'roomUserIds': userIds,
      });
      if (!valid()) return;
      final cumulative = parseTogetherCumulativeDuration(response['data']);
      if (cumulative != null) {
        // Replace this account/friend snapshot, never accumulate refreshes or
        // add a session value already represented in the official total.
        _cumulativeClock.replace(cumulative);
      } else {
        _cumulativeClock.markStale();
      }
    } catch (_) {
      // Keep a same-friend confirmed value as visibly stale; do not continue
      // inventing time while statistics are unavailable. Audio is independent.
      if (valid()) {
        _cumulativeClock.markStale();
      }
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

  /// Observe only a fixed operation label and timing. The journal cannot see
  /// the route, query, credentials, response body or exception text.
  Future<Map<String, dynamic>> _observeRequest(
    TogetherSyncOperation operation,
    Future<Map<String, dynamic>> Function() request,
  ) async {
    final ordinal = ++_requestOrdinal;
    final clock = Stopwatch()..start();
    diagnostics.record(
      TogetherSyncPhase.httpStarted,
      operation: operation,
      request: ordinal,
    );
    try {
      final result = await request();
      diagnostics.record(
        TogetherSyncPhase.httpCompleted,
        operation: operation,
        request: ordinal,
        durationMs: clock.elapsedMilliseconds,
        accepted: current,
      );
      return result;
    } catch (failure) {
      diagnostics.record(
        failure is TimeoutException
            ? TogetherSyncPhase.httpTimedOut
            : TogetherSyncPhase.httpFailed,
        operation: operation,
        request: ordinal,
        durationMs: clock.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _call(
    String route, [
    Map<String, Object?> query = const {},
  ]) {
    if (!current) throw const MusicPlatformException('账号已变化，一起听已停止');
    final c = neteaseCompleteContract(route, query)!;
    final operation = switch (route) {
      '/listentogether/status' => TogetherSyncOperation.status,
      '/listentogether/room/check' => TogetherSyncOperation.roomCheck,
      '/listentogether/heatbeat' => TogetherSyncOperation.heartbeat,
      '/listentogether/play/command' => TogetherSyncOperation.playCommand,
      '/listentogether/sync/playlist/get' => TogetherSyncOperation.playlistRead,
      '/listentogether/sync/list/command' =>
        TogetherSyncOperation.playlistWrite,
      '/listentogether/relation/statistics/get' =>
        TogetherSyncOperation.statistics,
      '/listentogether/distance/get' => TogetherSyncOperation.distance,
      '/listentogether/user/gps/report' => TogetherSyncOperation.location,
      '/listentogether/room/create' ||
      '/listentogether/accept' ||
      '/listentogether/end' => TogetherSyncOperation.roomAction,
      _ => TogetherSyncOperation.other,
    };
    return _observeRequest(
      operation,
      () => music.api.request(
        c.path,
        c.data,
        weapi: c.weapi,
        expectedCredential: music.credential,
      ),
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
    // Explicit refresh/entry may retry missing totals immediately. Background
    // room polling retains its 30-second statistics throttle.
    await _refresh(forcePresence: true);
    if (roomId != null) {
      await _loadQueue();
      _start();
    }
  });

  /// OS resume invalidates the polling throttle. If a room action is already
  /// running, the next normal tick still has to fetch fresh official totals.
  Future<void> resume() {
    _presenceFetchedAt = null;
    return restore();
  }

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
    if (!canInvitePeer) {
      notice = '已有好友正在一起听';
      return;
    }
    await _ensureRoom();
    if (!current || roomId == null) return;
    // Membership may change while creating/restoring the room. Re-read before
    // the explicit user's send, and never substitute a different invitee.
    await _refresh();
    if (!current || roomId == null) return;
    if (!canInvitePeer) {
      notice = '已有好友正在一起听';
      return;
    }
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

  Future<void> _refresh({
    bool forcePresence = false,
    bool waitForPlayback = true,
  }) async {
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
      _cumulativeClock.clear();
      _presenceFetchedAt = null;
    }
    if (roomId != null) {
      final check = NeteaseMusicRepository.object(
        (await _call('/listentogether/room/check', {'roomId': roomId}))['data'],
      );
      if (!_syncCurrent(epoch)) return;
      await _remote(check, waitForPlayback: waitForPlayback);
      if (!_syncCurrent(epoch)) return;
    }
    await _remote({...data, ...room}, waitForPlayback: waitForPlayback);
    if (peers.isEmpty || error != null) _cumulativeClock.markStale();
    if (_syncCurrent(epoch)) {
      final presence = _refreshPresence(force: forcePresence);
      if (waitForPlayback) {
        await presence;
      } else {
        // Statistics/location may wait on their own network request. Neither
        // owns the room's command reception or protocol heartbeat cadence.
        unawaited(presence);
      }
    }
  }

  Future<void> _loadQueue({
    bool applyRemote = true,
    bool waitForPlayback = true,
    bool reuseKnownTracks = false,
  }) async {
    if (roomId == null) return;
    final epoch = _syncEpoch, room = roomId;
    final revision = ++_playlistReadRevision;
    bool valid() =>
        _syncCurrent(epoch) &&
        roomId == room &&
        revision == _playlistReadRevision;
    final data = NeteaseMusicRepository.object(
      (await _call('/listentogether/sync/playlist/get', {
        'roomId': roomId,
      }))['data'],
    );
    if (!valid()) return;
    final playlist = TogetherSharedPlaylist(data);
    final cached = reuseKnownTracks ? playlist.reuse(sharedTracks) : null;
    if (cached != null) {
      sharedTracks = cached;
    } else if (playlist.ids.isNotEmpty) {
      final r = await _observeRequest(
        TogetherSyncOperation.songDetail,
        () => music.call('/song/detail', {'ids': playlist.ids}),
      );
      if (!valid()) return;
      sharedTracks = NeteaseMusicRepository.tracks(r['songs']);
    }
    // A command applying itself may need this queue. Do not recursively await
    // another command on that same serialized remote-application queue.
    if (applyRemote && valid()) {
      await _remote(data, waitForPlayback: waitForPlayback);
    }
  }

  void _start() {
    if (_subscriptions.isNotEmpty || !current || roomId == null) return;
    _formerSong = player.track?.platformSongId ?? '-1';
    _subscriptions.add(
      player.commands.listen((command) {
        if (!current || roomId == null) return;
        if (_applying) {
          if (player is _HandlerTogetherPlayer) {
            _cancelRemoteApplication(reason: TogetherSyncReason.userControl);
          } else {
            return;
          }
        }
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
          // A direct song/search/album selection need not emit replaceQueue.
          // Make the selected recording available to the peer before GOTO;
          // ordinary next/previous within the shared queue needs no list write.
          final songId = player.track?.platformSongId;
          _enqueue(
            'GOTO',
            queue:
                songId != null &&
                !sharedTracks.any((track) => track.platformSongId == songId),
          );
        }
      }),
    );
    if (automaticTimer) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => poll());
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

  Future<void> _report(
    String action, {
    bool heartbeat = false,
    bool waitForPlayback = true,
  }) async {
    final epoch = _syncEpoch;
    final track = player.track;
    if (!_syncCurrent(epoch) ||
        roomId == null ||
        track?.source != TrackSource.netease) {
      return;
    }
    // Command reception is independent of decoder completion. Until the
    // selected peer command settles, heartbeat its synchronization snapshot;
    // publishing the superseded local song/state here could undo that command.
    // Listening-history accounting continues to use actual audio exclusively.
    final pending = heartbeat ? _activeRemoteCommand : null;
    final reportedSong = pending?.songId ?? track!.platformSongId;
    final reportedPosition = pending?.position ?? player.position;
    final reportedPlaying = pending?.playing ?? player.playing;
    final r = await _call(
      heartbeat ? '/listentogether/heatbeat' : '/listentogether/play/command',
      {
        'roomId': roomId,
        'songId': reportedSong,
        'progress': reportedPosition.inMilliseconds,
        // Native pause fades complete after the intent event. Report what the
        // user requested, not that still-playing audio snapshot. Heartbeats
        // continue to report the actual settled player state.
        'playStatus': !heartbeat && action == 'PAUSE'
            ? 'PAUSE'
            : !heartbeat && action == 'PLAY'
            ? 'PLAY'
            : reportedPlaying
            ? 'PLAY'
            : 'PAUSE',
        if (!heartbeat) ...{
          'commandType': action,
          'formerSongId': _formerSong,
          'targetSongId': track!.platformSongId,
          'clientSeq': _sequence++,
        },
      },
    );
    if (!_syncCurrent(epoch)) return;
    _formerSong = reportedSong;
    await _remote(
      NeteaseMusicRepository.object(r['data']),
      waitForPlayback: waitForPlayback,
    );
  }

  /// Both background engine pulses and the Dart fallback use one cadence.
  /// Explicit room refreshes bypass this coalescing; duplicate timer sources
  /// must not send concurrent heartbeats or replay a playback mutation.
  Future<void> poll() async {
    diagnostics.record(TogetherSyncPhase.pollEntered, active: active);
    final now = DateTime.now();
    if (_lastPoll != null &&
        now.difference(_lastPoll!) < const Duration(seconds: 4)) {
      diagnostics.record(
        TogetherSyncPhase.pollSkipped,
        reason: TogetherSyncReason.cadence,
      );
      return;
    }
    _lastPoll = now;
    await tick(waitForPlayback: false);
  }

  Future<void> tick({bool waitForPlayback = true}) async {
    if (_ticking || busy || !current || roomId == null) {
      diagnostics.record(
        TogetherSyncPhase.pollSkipped,
        reason: _ticking
            ? TogetherSyncReason.inFlight
            : busy
            ? TogetherSyncReason.busy
            : !current
            ? TogetherSyncReason.accountEnded
            : TogetherSyncReason.roomMissing,
      );
      return;
    }
    final epoch = _syncEpoch;
    _ticking = true;
    final clock = Stopwatch()..start();
    diagnostics.record(TogetherSyncPhase.tickStarted);
    try {
      await _refresh(waitForPlayback: waitForPlayback);
      if (roomId != null && _syncCurrent(epoch)) {
        // Device trace: status/check/heartbeat kept returning successfully in
        // the background without commands; only the resume-only playlist read
        // returned the newer playback snapshot. Poll that same authoritative
        // source in every tick, before reporting our (possibly stale) player.
        await _loadQueue(
          reuseKnownTracks: true,
          waitForPlayback: waitForPlayback,
        );
      }
      if (roomId != null && _syncCurrent(epoch)) {
        await _report(
          'PLAY',
          heartbeat: true,
          waitForPlayback: waitForPlayback,
        );
      }
      if (_syncCurrent(epoch) && !_remoteApplicationFailed) error = null;
      diagnostics.record(
        TogetherSyncPhase.tickCompleted,
        durationMs: clock.elapsedMilliseconds,
        accepted: _syncCurrent(epoch),
      );
    } catch (_) {
      diagnostics.record(
        TogetherSyncPhase.tickFailed,
        durationMs: clock.elapsedMilliseconds,
        accepted: _syncCurrent(epoch),
      );
      if (_syncCurrent(epoch) && roomId != null) {
        error = '一起听连接暂时中断，正在重连';
        _cumulativeClock.markStale();
      }
    } finally {
      _ticking = false;
      _notify();
    }
  }

  /// Servers may include a command in room/status/heartbeat responses. Apply
  /// only an explicit versioned command, never infer a play state from member
  /// data, and suppress local echoes while applying it to the audio handler.
  Future<void> _remote(
    Map<String, dynamic> data, {
    bool waitForPlayback = true,
  }) async {
    final epoch = _syncEpoch, room = roomId;
    if (!_syncCurrent(epoch) || room == null) return;
    final command = TogetherPlaybackCommand.parse(data, room);
    if (command == null) {
      diagnostics.record(
        TogetherSyncPhase.commandSkipped,
        reason: TogetherSyncReason.noCommand,
      );
      return;
    }
    if (_remoteRoom != room) {
      _remoteRoom = room;
      _highestRemoteSequence = null;
      _lastRemote = '';
    }
    final sequence = command.sequence;
    final previousSequence = _highestRemoteSequence;
    final order = sequence == null
        ? TogetherSyncOrder.opaque
        : previousSequence == null
        ? TogetherSyncOrder.first
        : sequence > previousSequence
        ? TogetherSyncOrder.newer
        : sequence == previousSequence
        ? TogetherSyncOrder.equal
        : TogetherSyncOrder.older;
    diagnostics.record(
      TogetherSyncPhase.commandReceived,
      numericSequence: sequence != null,
      order: order,
    );
    if (sequence != null) {
      if (_highestRemoteSequence != null &&
          sequence < _highestRemoteSequence!) {
        diagnostics.record(
          TogetherSyncPhase.commandSkipped,
          reason: TogetherSyncReason.olderSequence,
        );
        return;
      }
      // Own acknowledgements are barriers too: an older peer packet cannot
      // undo a newer local action already accepted by the server.
      _highestRemoteSequence = sequence;
      if (_activeRemoteToken != null &&
          _activeRemoteSequence != null &&
          sequence > _activeRemoteSequence!) {
        _cancelRemoteApplication(reason: TogetherSyncReason.newerCommand);
      }
    }
    if (command.token == _lastRemote ||
        _pendingRemote.contains(command.token) ||
        command.userId == music.api.session?.userId) {
      diagnostics.record(
        TogetherSyncPhase.commandSkipped,
        reason: command.userId == music.api.session?.userId
            ? TogetherSyncReason.ownCommand
            : TogetherSyncReason.duplicate,
      );
      return;
    }
    // Opaque version tokens are supported by the existing wire decoder too.
    // A distinct accepted command still invalidates an active old operation;
    // do not leave its audio guard alive merely because it is not numeric.
    if (_activeRemoteToken != null && _activeRemoteToken != command.token) {
      _cancelRemoteApplication(reason: TogetherSyncReason.newerCommand);
    }
    _pendingRemote.add(command.token);
    _remoteReceived++;
    final application = ++_applicationRevision;
    final clock = Stopwatch()..start();
    diagnostics.record(
      TogetherSyncPhase.applicationQueued,
      application: application,
    );
    final abort = Completer<void>();
    _applicationAbort = abort;
    _activeRemoteToken = command.token;
    _activeRemoteSequence = sequence;
    _activeRemoteCommand = command;
    bool valid() =>
        _syncCurrent(epoch) &&
        roomId == room &&
        application == _applicationRevision &&
        !(sequence != null &&
            _highestRemoteSequence != null &&
            sequence < _highestRemoteSequence!);
    final operation = _remoteTail.then((_) async {
      if (!valid()) {
        diagnostics.record(
          TogetherSyncPhase.applicationCancelled,
          application: application,
          reason: TogetherSyncReason.staleOwner,
        );
        return;
      }
      _applying = true;
      diagnostics.record(
        TogetherSyncPhase.applicationStarted,
        application: application,
      );
      try {
        if (!sharedTracks.any((t) => t.platformSongId == command.songId)) {
          await _loadQueue(applyRemote: false);
        }
        if (!valid() ||
            !sharedTracks.any((t) => t.platformSongId == command.songId)) {
          diagnostics.record(
            valid()
                ? TogetherSyncPhase.applicationFailed
                : TogetherSyncPhase.applicationCancelled,
            application: application,
            reason: valid()
                ? TogetherSyncReason.queueMissing
                : TogetherSyncReason.staleOwner,
            durationMs: clock.elapsedMilliseconds,
          );
          return;
        }
        await player.apply(
          sharedTracks,
          command.songId,
          command.position ??
              (player.track?.platformSongId == command.songId
                  ? player.position
                  : Duration.zero),
          command.playing,
        );
        if (valid()) {
          _formerSong = command.songId;
          // Consume only successfully applied state. A failed source lookup
          // can retry the same server command on the next read.
          _lastRemote = command.token;
          _remoteApplied++;
          _remoteApplicationFailed = false;
          diagnostics.record(
            TogetherSyncPhase.applicationCompleted,
            application: application,
            durationMs: clock.elapsedMilliseconds,
          );
        }
      } finally {
        if (application == _applicationRevision) _applying = false;
      }
    });
    // The background receiver/heartbeat never waits for an audio decoder.
    // Timeout means invalidate that exact audio/source generation, rather than
    // merely abandoning a Future that could autoplay an old selection later.
    Object? applicationFailure;
    final bounded = Future.any<void>([operation, abort.future])
        .timeout(remoteApplicationTimeout)
        .catchError((Object failure) {
          if (!valid()) return;
          applicationFailure = failure;
          _remoteApplicationFailed = true;
          diagnostics.record(
            failure is TimeoutException
                ? TogetherSyncPhase.applicationTimedOut
                : TogetherSyncPhase.applicationFailed,
            application: application,
            durationMs: clock.elapsedMilliseconds,
          );
          if (failure is TimeoutException) {
            _remoteTimeouts++;
            _cancelRemoteApplication(reason: TogetherSyncReason.timeout);
          }
          error = '一起听播放同步暂未完成，正在重试';
          _notify();
        })
        .whenComplete(() {
          _pendingRemote.remove(command.token);
          if (application == _applicationRevision) {
            _applicationAbort = null;
            _activeRemoteToken = null;
            _activeRemoteSequence = null;
            _activeRemoteCommand = null;
          }
        });
    _remoteTail = bounded;
    if (waitForPlayback) {
      await bounded;
      final failure = applicationFailure;
      if (failure != null) throw failure;
    }
  }

  void _cancelRemoteApplication({
    TogetherSyncReason reason = TogetherSyncReason.stopped,
  }) {
    diagnostics.record(
      TogetherSyncPhase.applicationCancelled,
      application: _applicationRevision,
      reason: reason,
    );
    ++_applicationRevision;
    final abort = _applicationAbort;
    _applicationAbort = null;
    if (abort?.isCompleted == false) abort!.complete();
    final adapter = player;
    if (adapter is NeteaseTogetherCancelablePlayer) {
      (adapter as NeteaseTogetherCancelablePlayer).cancelPendingApplication();
    }
    _activeRemoteToken = null;
    _activeRemoteSequence = null;
    _activeRemoteCommand = null;
    _applying = false;
    _remoteTail = Future.value();
  }

  Future<void> settle() => _tail;
  void _stop() {
    diagnostics.record(TogetherSyncPhase.controllerStopped);
    if (_activeRemoteToken != null) _cancelRemoteApplication();
    _lastPoll = null;
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
