import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/mesting_audio_handler.dart';
import '../../core/audio/playback_providers.dart';
import '../../shared/models/track.dart';
import '../auth/auth_providers.dart';
import 'data/listen_together_repository.dart';
import 'domain/listen_together.dart';
import 'domain/social_models.dart';
import 'social_providers.dart';

// A session is the only time that needs near-real-time playback polling.
// When no session is active, checking every two minutes is sufficient to pick
// up invitations without keeping a high-frequency CloudBase request loop
// alive for every signed-in user.
const listenTogetherPollInterval = Duration(seconds: 3);
const listenTogetherIdlePollInterval = Duration(minutes: 2);
const listenTogetherDriftTolerance = Duration(milliseconds: 1200);

final listenTogetherPollIntervalProvider = Provider<Duration>(
  (ref) => listenTogetherPollInterval,
);

final listenTogetherRepositoryProvider = Provider<ListenTogetherRepository>((
  ref,
) {
  final repository = ref.watch(socialRepositoryProvider);
  if (repository is ListenTogetherRepository) {
    return repository as ListenTogetherRepository;
  }
  return const UnsupportedListenTogetherRepository();
});

final listenTogetherControllerProvider =
    AsyncNotifierProvider<ListenTogetherController, ListenTogetherSession?>(
      ListenTogetherController.new,
    );

class ListenTogetherController extends AsyncNotifier<ListenTogetherSession?> {
  static const _passiveMutationDelay = Duration(seconds: 3);

  Timer? _pollTimer;
  Timer? _localMutationTimer;
  StreamSubscription<String>? _commandSubscription;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<MediaItem?>? _mediaSubscription;
  StreamSubscription<List<MediaItem>>? _queueSubscription;
  bool _polling = false;
  bool _pushing = false;
  bool _pushAgain = false;
  bool _userMutationPending = false;
  int _userMutationGeneration = 0;
  int _userConflictRetryCount = 0;
  bool _applyingRemote = false;
  String _lastLocalFingerprint = '';
  int _lastObservedRevision = -1;
  DateTime _suppressPassiveMutationsUntil = DateTime.fromMillisecondsSinceEpoch(
    0,
  );

  ListenTogetherRepository get _repository =>
      ref.read(listenTogetherRepositoryProvider);
  MestingAudioHandler get _handler => ref.read(audioHandlerProvider);
  String? get _currentUid => ref.read(currentUserProvider)?.uid;

  @override
  Future<ListenTogetherSession?> build() async {
    _cancelRuntime();
    ref.onDispose(_cancelRuntime);
    final user = ref.watch(currentUserProvider);
    if (user == null) return null;
    final repository = ref.watch(listenTogetherRepositoryProvider);
    if (repository is UnsupportedListenTogetherRepository) return null;
    ref.watch(audioHandlerProvider);

    _listenToPlaybackMutations();
    final session = await _repository.getListenTogetherSession();
    if (session?.isActive == true) {
      final shouldApply =
          session!.playback.lastActorUid != user.uid ||
          session.inviteeUid == user.uid;
      if (shouldApply) await _applyRemotePlayback(session);
      _lastObservedRevision = session.playback.revision;
    }
    _lastLocalFingerprint = _localFingerprint();
    _startPolling(session: session);
    return session;
  }

  Future<ListenTogetherSession> invite(String uid) async {
    final user = _currentUid;
    if (user == null) {
      throw StateError('登录后才能邀请好友一起听');
    }
    final snapshot = _localPlaybackSnapshot(actorUid: user);
    if (snapshot.currentTrack == null) {
      throw StateError('请先播放一首音乐，再邀请好友一起听');
    }
    final session = await _repository.inviteToListenTogether(
      uid,
      playback: snapshot,
    );
    state = AsyncData(session);
    _lastObservedRevision = session.playback.revision;
    _lastLocalFingerprint = _localFingerprint();
    _startPolling(session: session);
    ref
      ..invalidate(socialConversationsProvider)
      ..invalidate(socialMessagesProvider(uid));
    return session;
  }

  Future<ListenTogetherSession> accept(String invitationId) async {
    final session = await _repository.respondToListenTogetherInvite(
      invitationId,
      accept: true,
    );
    await _applyRemotePlayback(session);
    state = AsyncData(session);
    _lastObservedRevision = session.playback.revision;
    _lastLocalFingerprint = _localFingerprint();
    _startPolling(session: session);
    ref.invalidate(socialConversationsProvider);
    ref.invalidate(socialMessagesProvider(session.peer.uid));
    return session;
  }

  Future<ListenTogetherSession> decline(String invitationId) async {
    final session = await _repository.respondToListenTogetherInvite(
      invitationId,
      accept: false,
    );
    state = AsyncData(session);
    _startPolling(session: session);
    ref.invalidate(socialConversationsProvider);
    ref.invalidate(socialMessagesProvider(session.peer.uid));
    return session;
  }

  Future<ListenTogetherSession> leave() async {
    final session = await _repository.leaveListenTogether();
    state = AsyncData(session);
    _lastObservedRevision = session.playback.revision;
    _startPolling(session: session);
    return session;
  }

  Future<List<ListenTogetherTrackRecord>> records(String uid) {
    return _repository.listListenTogetherRecords(uid);
  }

  Future<void> refreshNow() => _poll();

  void _listenToPlaybackMutations() {
    final handler = _handler;
    _commandSubscription = handler.userCommandStream.listen(
      (command) => _scheduleLocalMutation(
        command == 'play' || command == 'pause' || command == 'stop'
            ? const Duration(milliseconds: 1000)
            : const Duration(milliseconds: 650),
        userCommand: true,
      ),
    );
    _playbackSubscription = handler.playbackState.listen(
      (_) => _scheduleLocalMutation(_passiveMutationDelay),
    );
    _mediaSubscription = handler.mediaItem.listen(
      (_) => _scheduleLocalMutation(_passiveMutationDelay),
    );
    _queueSubscription = handler.queue.listen(
      (_) => _scheduleLocalMutation(_passiveMutationDelay),
    );
  }

  void _startPolling({ListenTogetherSession? session}) {
    _pollTimer?.cancel();
    final interval = session?.isActive == true
        ? ref.read(listenTogetherPollIntervalProvider)
        : listenTogetherIdlePollInterval;
    if (interval <= Duration.zero) return;
    _pollTimer = Timer(interval, () async {
      await _poll();
      if (state.hasValue) _startPolling(session: state.value);
    });
  }

  Future<void> _poll() async {
    if (_polling || _currentUid == null) return;
    _polling = true;
    try {
      final previous = state.value;
      final session = await _repository.getListenTogetherSession();
      if (session == null) {
        state = const AsyncData(null);
        _lastObservedRevision = -1;
        return;
      }
      final becameActive =
          previous?.status != ListenTogetherStatus.active && session.isActive;
      final remoteRevision =
          session.playback.revision > _lastObservedRevision &&
          session.playback.lastActorUid != _currentUid;
      if (session.isActive &&
          (becameActive || remoteRevision) &&
          !_userMutationPending) {
        await _applyRemotePlayback(session);
      }
      _lastObservedRevision = session.playback.revision;
      state = AsyncData(session);
    } on Object {
      // Keep the last usable session during a transient poll failure.
    } finally {
      _polling = false;
    }
  }

  void _scheduleLocalMutation(
    Duration delay, {
    bool userCommand = false,
    bool resetConflictRetry = true,
  }) {
    if (_applyingRemote || state.value?.isActive != true) return;
    if (userCommand) {
      _userMutationPending = true;
      _userMutationGeneration += 1;
      if (resetConflictRetry) _userConflictRetryCount = 0;
    } else {
      if (_userMutationPending ||
          DateTime.now().isBefore(_suppressPassiveMutationsUntil) ||
          _localMutationTimer != null ||
          _localFingerprint() == _lastLocalFingerprint) {
        return;
      }
    }
    _localMutationTimer?.cancel();
    _localMutationTimer = Timer(delay, () {
      _localMutationTimer = null;
      unawaited(_pushLocalPlayback());
    });
  }

  Future<void> _pushLocalPlayback() async {
    if (_applyingRemote || state.value?.isActive != true) return;
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    final fingerprint = _localFingerprint();
    final explicitUserMutation = _userMutationPending;
    final mutationGeneration = _userMutationGeneration;
    if (fingerprint == _lastLocalFingerprint) {
      if (_userMutationGeneration == mutationGeneration) {
        _userMutationPending = false;
        _userConflictRetryCount = 0;
      }
      return;
    }
    final current = state.value;
    final uid = _currentUid;
    if (current == null || uid == null) return;

    _pushing = true;
    try {
      var baseRevision = current.playback.revision;
      var session = await _repository.updateListenTogetherPlayback(
        _localPlaybackSnapshot(actorUid: uid),
        baseRevision: baseRevision,
      );
      var conflict =
          session.playback.lastActorUid != uid &&
          session.playback.revision >= baseRevision;

      // A remote position update can win the revision race just before an
      // explicit play/pause command reaches the API. Keep the user's command
      // authoritative and retry it against the newer revision instead of
      // silently applying the other side's playing flag.
      if (explicitUserMutation && conflict) {
        baseRevision = session.playback.revision;
        session = await _repository.updateListenTogetherPlayback(
          _localPlaybackSnapshot(actorUid: uid),
          baseRevision: baseRevision,
        );
        conflict =
            session.playback.lastActorUid != uid &&
            session.playback.revision >= baseRevision;
      }
      if (_userMutationGeneration == mutationGeneration) {
        _userMutationPending = false;
      }
      if (conflict) {
        await _applyRemotePlayback(session);
      }
      _lastObservedRevision = session.playback.revision;
      _lastLocalFingerprint = _localFingerprint();
      state = AsyncData(session);
    } on SocialRequestException catch (error) {
      final isConflict = error.code == 'together_conflict';
      if (explicitUserMutation &&
          isConflict &&
          _userMutationGeneration == mutationGeneration &&
          _userConflictRetryCount < 2) {
        _userConflictRetryCount += 1;
        unawaited(_refreshAfterPlaybackConflict(mutationGeneration));
      } else {
        if (explicitUserMutation &&
            _userMutationGeneration == mutationGeneration) {
          _userMutationPending = false;
        }
        unawaited(_poll());
      }
    } on Object {
      if (explicitUserMutation &&
          _userMutationGeneration == mutationGeneration) {
        _userMutationPending = false;
      }
      unawaited(_poll());
    } finally {
      _pushing = false;
      if (_pushAgain) {
        _pushAgain = false;
        _scheduleLocalMutation(
          const Duration(milliseconds: 220),
          userCommand: _userMutationPending,
        );
      }
    }
  }

  Future<void> _refreshAfterPlaybackConflict(int generation) async {
    try {
      final session = await _repository.getListenTogetherSession();
      if (session == null ||
          !session.isActive ||
          _userMutationGeneration != generation) {
        if (_userMutationGeneration == generation) {
          _userMutationPending = false;
        }
        return;
      }
      _lastObservedRevision = session.playback.revision;
      // Keep the local play/pause state and retry against the server's newest
      // revision. The user command remains pending, so the poller cannot
      // overwrite it while this retry is being prepared.
      state = AsyncData(session);
      _scheduleLocalMutation(
        const Duration(milliseconds: 220),
        userCommand: true,
        resetConflictRetry: false,
      );
    } on Object {
      if (_userMutationGeneration == generation) {
        _userMutationPending = false;
      }
      unawaited(_poll());
    }
  }

  ListenTogetherPlayback _localPlaybackSnapshot({required String actorUid}) {
    final handler = _handler;
    final persisted = handler.persistedQueue;
    final currentId = handler.mediaItem.value?.id;
    final current = currentId == null ? null : handler.trackForId(currentId);
    final tracks = <Track>[];
    final seen = <String>{};
    if (current != null && current.isPlayable) {
      tracks.add(current);
      seen.add(current.id);
    }
    for (final track in persisted) {
      if (track.isPlayable && seen.add(track.id)) tracks.add(track);
      if (tracks.length >= 100) break;
    }
    return ListenTogetherPlayback(
      queue: List<Track>.unmodifiable(tracks),
      playing: handler.playbackState.value.playing,
      position: handler.currentPosition,
      updatedAt: DateTime.now(),
      revision: state.value?.playback.revision ?? 0,
      lastActorUid: actorUid,
    );
  }

  Future<void> _applyRemotePlayback(ListenTogetherSession session) async {
    final remote = session.playback;
    final remoteTrack = remote.currentTrack;
    if (remoteTrack == null || !remoteTrack.isPlayable) return;
    _applyingRemote = true;
    _localMutationTimer?.cancel();
    try {
      final handler = _handler;
      final expectedPosition = session.playbackPositionAt();
      final queueChanged =
          listenTogetherQueueSignature(handler.persistedQueue) !=
          listenTogetherQueueSignature(remote.queue);
      final trackChanged = handler.mediaItem.value?.id != remoteTrack.id;
      if (trackChanged || queueChanged) {
        await handler.applySynchronizedPlayback(
          tracks: remote.queue,
          position: expectedPosition,
          playing: remote.playing,
        );
      } else {
        final drift = listenTogetherPlaybackDrift(
          handler.currentPosition,
          expectedPosition,
        );
        if (drift > listenTogetherDriftTolerance) {
          await handler.seek(expectedPosition);
        }
        if (remote.playing != handler.playbackState.value.playing) {
          if (remote.playing) {
            await handler.play();
          } else {
            await handler.pause();
          }
        }
      }
      _lastLocalFingerprint = _localFingerprint();
      _suppressPassiveMutationsUntil = DateTime.now().add(
        const Duration(milliseconds: 900),
      );
    } finally {
      _applyingRemote = false;
    }
  }

  String _localFingerprint() {
    final handler = _handler;
    final positionBucket = handler.currentPosition.inMilliseconds ~/ 250;
    return [
      handler.mediaItem.value?.id ?? '',
      handler.playbackState.value.playing ? '1' : '0',
      '$positionBucket',
      listenTogetherQueueSignature(handler.persistedQueue),
    ].join('|');
  }

  void _cancelRuntime() {
    _pollTimer?.cancel();
    _localMutationTimer?.cancel();
    unawaited(_commandSubscription?.cancel());
    unawaited(_playbackSubscription?.cancel());
    unawaited(_mediaSubscription?.cancel());
    unawaited(_queueSubscription?.cancel());
    _pollTimer = null;
    _localMutationTimer = null;
    _commandSubscription = null;
    _playbackSubscription = null;
    _mediaSubscription = null;
    _queueSubscription = null;
  }
}
