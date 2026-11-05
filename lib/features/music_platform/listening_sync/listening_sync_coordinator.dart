import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';

import '../../../core/audio/mesting_audio_handler.dart';
import '../../../shared/models/track.dart';
import '../domain/platform_session.dart';
import '../data/kugou_v4_grade_repository.dart';
import 'listening_clock.dart';
import 'listening_daily_readback.dart';
import 'listening_sync_models.dart';
import 'listening_sync_repository.dart';
import 'listening_sync_store.dart';
import 'listening_sync_worker.dart';

class ListeningPlaybackSnapshot {
  const ListeningPlaybackSnapshot({
    required this.playing,
    required this.ready,
    this.completed = false,
    this.speed = 1,
  });
  final bool playing, ready, completed;
  final double speed;
}

abstract interface class ListeningAudioFeed {
  Track? get currentTrack;
  ListeningPlaybackSnapshot get currentState;
  bool get isSeeking;
  Stream<Track?> get tracks;
  Stream<ListeningPlaybackSnapshot> get states;
  Stream<bool> get seeks;
  Stream<void> get repeatBoundaries;
}

class HandlerListeningAudioFeed implements ListeningAudioFeed {
  HandlerListeningAudioFeed(this.handler);
  final MestingAudioHandler handler;
  ListeningPlaybackSnapshot _state(PlaybackState value) =>
      ListeningPlaybackSnapshot(
        playing: value.playing,
        ready: value.processingState == AudioProcessingState.ready,
        completed: value.processingState == AudioProcessingState.completed,
        speed: value.speed,
      );
  @override
  Track? get currentTrack =>
      handler.trackForId(handler.mediaItem.value?.id ?? '');
  @override
  ListeningPlaybackSnapshot get currentState =>
      _state(handler.playbackState.value);
  @override
  bool get isSeeking => handler.isSeeking;
  @override
  Stream<Track?> get tracks => handler.mediaItem.map((_) => currentTrack);
  @override
  Stream<ListeningPlaybackSnapshot> get states =>
      handler.playbackState.map(_state);
  @override
  Stream<bool> get seeks => handler.seekingStream;
  @override
  Stream<void> get repeatBoundaries => handler.nativeRepeatBoundaryStream;
}

/// Owns measurement and journal scheduling, not audio playback or account
/// storage. Network latency never serializes decoder events or UI state.
class ListeningSyncCoordinator with WidgetsBindingObserver {
  ListeningSyncCoordinator({
    required this.feed,
    required this.store,
    required this.gateway,
    required this.currentIdentity,
    required this.prepareOwner,
    this.officialDayReader,
    this.standardGradeGateway,
    ListeningClock? clock,
    this.observeLifecycle = true,
    this.automaticTimers = true,
  }) : clock = clock ?? MonotonicListeningClock() {
    _subscriptions.add(feed.tracks.listen(_onTrack));
    _subscriptions.add(feed.states.listen(_onState));
    _subscriptions.add(
      feed.seeks.listen((seeking) {
        _counter?.update(seeking: seeking);
      }),
    );
    _subscriptions.add(
      feed.repeatBoundaries.listen((_) {
        _finish('完整播放');
        _instance = _id('play');
        _maybeOpen();
      }),
    );
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    if (automaticTimers) {
      _checkpointTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => sample(),
      );
      _flushTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        final worker = _worker;
        if (worker != null) unawaited(worker.flush());
      });
    }
  }

  final ListeningAudioFeed feed;
  final ListeningSyncStore store;
  final ListeningPlatformGateway gateway;
  final PlatformSession? Function() currentIdentity;
  final Future<void> Function(String owner) prepareOwner;
  final OfficialListeningDayReader? officialDayReader;
  final KugouStandardGradeGateway? standardGradeGateway;
  final ListeningClock clock;
  final bool observeLifecycle, automaticTimers;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _checkpointTimer, _flushTimer;
  Future<void> _writes = Future.value();
  ListeningSyncWorker? _worker;
  ListeningSyncEntry? _segment;
  ActualListeningCounter? _counter;
  Track? _track;
  ListeningPlaybackSnapshot _state = const ListeningPlaybackSnapshot(
    playing: false,
    ready: false,
  );
  bool _ready = false, _disposed = false;
  int _epoch = 0, _serial = 0, _lastFlushMs = 0;
  String _instance = '';

  String _id(String prefix) =>
      '$prefix:${clock.now.microsecondsSinceEpoch}:${++_serial}';

  void _write(Future<void> Function() operation) {
    _writes = _writes.then((_) => operation()).catchError((Object _) {
      // Do not log raw database/transport values. A failed durable write may
      // lose an interval; it must never cause a fabricated replacement delta.
    });
  }

  /// Called on login/logout/token changes or the persisted cloud-sync toggle.
  /// The old segment is settled synchronously before any async owner restore.
  Future<void> activate(
    PlatformSession? identity, {
    bool enabled = true,
  }) async {
    final epoch = ++_epoch;
    _ready = false;
    _worker?.dispose();
    _finish('账号或同步设置变化', live: false);
    _worker = null;
    _instance = '';
    if (identity == null || !enabled || _disposed) return;
    bool valid() =>
        !_disposed &&
        epoch == _epoch &&
        currentIdentity()?.userId == identity.userId &&
        currentIdentity()?.token == identity.token &&
        currentIdentity()?.kugouStandardToken == identity.kugouStandardToken;
    try {
      final owner = 'kugou:${identity.userId}';
      // This reuses the existing serialized owner switch. It prevents a last
      // frame of account A's track being charged to account B during restore.
      await prepareOwner(owner);
      await _writes;
      if (!valid()) return;
      await store.recoverInterrupted(owner, clock.now);
      await store.bootstrapHistory(owner, clock.now);
      if (!valid()) return;
      _worker = ListeningSyncWorker(
        store: store,
        gateway: gateway,
        identity: identity,
        currentIdentity: currentIdentity,
        officialDayReader: officialDayReader,
        standardGradeGateway: standardGradeGateway,
        now: () => clock.now,
      );
      _track = feed.currentTrack;
      _state = feed.currentState;
      _ready = true;
      _instance = _id('play');
      _maybeOpen();
      unawaited(_worker!.flush());
    } on Object {
      // Startup and playback remain available if the journal cannot initialize.
    }
  }

  void _onTrack(Track? track) {
    if (_track?.id == track?.id) {
      _track = track;
      return;
    }
    _finish('切歌');
    _track = track;
    _instance = _id('play');
    // The metadata is committed before setAudioSources. Wait for the new
    // decoder state instead of borrowing the previous song's ready flag.
    _state = const ListeningPlaybackSnapshot(playing: false, ready: false);
  }

  void _onState(ListeningPlaybackSnapshot state) {
    _state = state;
    _counter?.update(
      playing: state.playing,
      ready: state.ready,
      speed: state.speed,
      seeking: feed.isSeeking,
    );
    if (state.completed) {
      _finish('完整播放');
    } else if (!state.playing) {
      _finish('暂停或停止');
    } else {
      _maybeOpen();
    }
  }

  void _maybeOpen() {
    final worker = _worker;
    final track = _track;
    if (!_ready ||
        _disposed ||
        worker == null ||
        !worker.current ||
        _counter != null ||
        track == null ||
        !isOfficialMusicTrack(track) ||
        !_state.ready ||
        !_state.playing ||
        feed.isSeeking) {
      return;
    }
    final id = _id('segment');
    final now = clock.now;
    final payload = <String, Object?>{
      'segmentId': id,
      'instanceId': _instance,
      'trackId': track.id,
      'recordingId': listeningRecordingId(track),
      'heardMs': 0,
      'allocatedMs': 0,
      'time': now.millisecondsSinceEpoch ~/ 1000,
      if (worker.identity.kugouAppId == 1005 &&
          standardGradeGateway != null) ...{
        'gradeProtocol': kugouStandardGradeProtocol,
        'credentialAppId': 1005,
      },
    };
    final segment = ListeningSyncEntry(
      ownerId: worker.owner,
      id: id,
      kind: 'segment',
      payload: payload,
      state: ListeningSyncState.open,
      createdAt: now,
      updatedAt: now,
    );
    _segment = segment;
    _counter = ActualListeningCounter(clock)
      ..update(playing: true, ready: true, speed: _state.speed);
    _lastFlushMs = 0;
    worker.registerLiveSegment(id);
    _write(() async {
      await store.put(
        owner: worker.owner,
        id: id,
        kind: 'segment',
        payload: payload,
        now: now,
        state: ListeningSyncState.open,
      );
      await store.put(
        owner: worker.owner,
        id: 'cscc:start:$id',
        kind: 'cscc',
        payload: {...payload, 'event': 'start'},
        now: now,
      );
      unawaited(worker.flush());
    });
  }

  /// Public for deterministic host verification; production uses a 5s timer.
  void sample() {
    final segment = _segment;
    final counter = _counter;
    if (segment == null || counter == null) return;
    final heard = counter.sample();
    final worker = _worker;
    final flush =
        (heard >= 15000 && _lastFlushMs == 0) ||
        heard ~/ 60000 > _lastFlushMs ~/ 60000;
    if (flush) _lastFlushMs = heard;
    _write(() async {
      await store.checkpointSegment(segment, heard, clock.now);
      if (flush && worker != null) unawaited(worker.flush());
    });
  }

  void _finish(String reason, {bool live = true}) {
    final segment = _segment;
    final counter = _counter;
    _segment = null;
    _counter = null;
    if (segment == null || counter == null) return;
    final heard = counter.sample();
    final now = clock.now;
    final worker = _worker;
    _write(() async {
      await store.closeSegment(segment, heard, now, live: live, reason: reason);
      if (worker != null) unawaited(worker.flush());
    });
  }

  Future<void> get settled => _writes;

  /// Explicit status refresh is read-only against the official service. It
  /// does not flush queued writes or repeat a timed-out start/end/grade event.
  Future<void> verifyPending() async {
    await _writes;
    await _worker?.verifyPending();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) sample();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _epoch++;
    _checkpointTimer?.cancel();
    _flushTimer?.cancel();
    _worker?.dispose();
    _finish('进程结束', live: false);
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _writes;
  }
}
