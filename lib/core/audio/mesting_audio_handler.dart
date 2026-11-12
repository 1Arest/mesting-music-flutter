import 'playback_preferences.dart';
import 'playback_transition.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../shared/models/track.dart';
import 'pause_fade_controller.dart';
import 'playback_completion_gate.dart';
import 'playback_mode.dart';
import 'playback_start_guard.dart';
import 'queue_engine.dart';
import 'music_sleep_timer.dart';
import '../platform/distribution_channel.dart';
import '../network/music_network_diagnostics.dart';
import '../network/system_music_io_client.dart';

part 'prepared_playback.dart';

typedef RadioTrackLoader =
    Future<List<Track>> Function(Set<String> excludedTrackKeys);
typedef TrackPlaybackResolver = Future<Track> Function(Track track);
typedef TrackLoadFailurePolicy = bool Function(Track track, Object error);

/// The only owner of the active `just_audio` source and media-session state.
///
/// The logical queue is separate from the active decoder. A silent prepared
/// decoder and a brief draining tail remain private to this same owner.
/// In particular, removing a track from the upcoming queue after one second of
/// real playback must not recreate the current audio source, which would cause
/// an audible pause on some devices.
class MestingAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MestingAudioHandler({
    required List<Track> tracks,
    Random? random,
    AudioPlayer? player,
    AudioPlayer Function()? preparedPlayerFactory,
  }) : _libraryTracks = List.of(tracks),
       _player =
           player ??
           AudioPlayer(
             // Android forwards public CDN headers natively; a fallback must
             // not re-enter the Dart loopback proxy, especially under a VPN.
             useProxyForRequestHeaders: false,
             androidAudioOutputOwner: DistributionChannel.isBeta
                 ? 'mesting-music'
                 : null,
           ),
       _preparedPlayerFactory = preparedPlayerFactory,
       _random = random ?? Random(),
       _knownTracks = <String, Track>{
         for (final track in tracks) track.id: track,
       },
       _tracks = tracks.isEmpty ? <Track>[] : <Track>[tracks.first] {
    _pauseFadeController = PauseFadeController(
      setVolume: (volume) => _player.setVolume(volume),
      pause: () => _player.pause(),
    );
    sleepTimer.addListener(_syncSleepBoundary);
    if (!kIsWeb && Platform.isAndroid) {
      // The pinned local fork exposes this tested application transport hook.
      // ignore: experimental_member_use
      LockCachingAudioSource.networkClientFactory =
          MusicSystemNetwork.shared.cacheClient;
    }
    _bindPlayer(_player);
    _ready = _initialize();
  }

  void configurePlaybackPreferences(PlaybackPreferences value) =>
      _setPlaybackPreferences(value);
  void configureSynchronizedPlayback(bool Function() active) =>
      _setSynchronizedPlayback(active);

  final List<Track> _libraryTracks;
  List<Track> _playbackContextTracks = const <Track>[];
  List<Track> _onlineFallbackTracks = const <Track>[];
  List<Track> _radioFallbackTracks = const <Track>[];
  final Map<String, Track> _knownTracks;
  List<Track> _tracks;
  AudioPlayer _player;
  final AudioPlayer Function()? _preparedPlayerFactory;
  final _transition = PlaybackTransition();
  StreamSubscription<AudioInterruptionEvent>? _transitionInterruptions;
  double _interruptionGain = 1;
  PlaybackPreferences _playbackPreferences = const PlaybackPreferences();
  bool Function()? _synchronizedPlayback;
  String? _effectConfig;
  final _nativeSubscriptions = <StreamSubscription<dynamic>>[];
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _sessions = StreamController<int?>.broadcast();
  final _repeatBoundaries = StreamController<void>.broadcast();
  void _bindPlayer(AudioPlayer player) {
    for (final subscription in _nativeSubscriptions) {
      unawaited(subscription.cancel());
    }
    _nativeSubscriptions.clear();
    _nativeSubscriptions.add(
      player.playbackEventStream.listen(
        (event) {
          if (identical(_player, player)) _broadcastState(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          // Source preparation owns its own failure. Native events from the
          // previous stream must not auto-skip a newly visible selection.
          if (!identical(_player, player) ||
              _pendingQueueEpoch != null ||
              mediaItem.value?.id != _loadedTrackId) {
            return;
          }
          unawaited(
            _handlePlaybackFailure(
              error,
              stackTrace: stackTrace,
              origin: 'playback-event',
            ),
          );
        },
      ),
    );
    _nativeSubscriptions.add(
      player.currentIndexStream.listen((index) {
        if (identical(_player, player)) _handleCurrentIndex(index);
      }),
    );
    _nativeSubscriptions.add(
      player.positionStream.listen((position) {
        if (identical(_player, player)) {
          _positions.add(position);
          _handlePosition(position);
        }
      }),
    );
    _nativeSubscriptions.add(
      player.durationStream.listen((duration) {
        if (identical(_player, player)) {
          _durations.add(duration);
          _handleDuration(duration);
        }
      }),
    );
    _nativeSubscriptions.add(
      player.processingStateStream.listen((state) {
        if (!identical(_player, player)) return;
        if (state == ProcessingState.completed) {
          if (_sleepStoppedAtCompletion ||
              _pendingQueueEpoch != null ||
              _transition.crossing) {
            return;
          }
          final completedTrack = trackForId(mediaItem.value?.id ?? '');
          if (_completionGate.takeCompletion() && completedTrack != null) {
            _completedTrackController.add(completedTrack);
          }
          if (sleepTimer.consumeTrackCompletion()) {
            _sleepStoppedAtCompletion = true;
            return;
          }
          unawaited(_advancePlayback(forward: true, automatic: true));
        }
      }),
    );
    _nativeSubscriptions.add(
      player.androidAudioSessionIdStream.listen((id) {
        if (identical(_player, player)) _sessions.add(id);
      }),
    );
    _nativeSubscriptions.add(
      player.positionDiscontinuityStream.listen((event) {
        if (identical(_player, player) &&
            event.reason == PositionDiscontinuityReason.autoAdvance) {
          _repeatBoundaries.add(null);
        }
      }),
    );
  }

  late final MusicSleepTimer sleepTimer = MusicSleepTimer(onExpire: pause);
  bool _sleepStoppedAtCompletion = false;
  bool _sleepBoundaryRequested = false;

  void _syncSleepBoundary() {
    final boundary = sleepTimer.mode == MusicSleepMode.endOfTrack;
    if (boundary == _sleepBoundaryRequested) return;
    _sleepBoundaryRequested = boundary;
    // ExoPlayer's native repeat-one never emits Completed. Temporarily wait
    // for a real boundary without changing the user's saved playback order.
    // Expiry already pauses the owner; defer restoring its loop until play.
    if (!sleepTimer.expiring) unawaited(_applyPlaybackOrder());
  }

  final Random _random;
  final StreamController<PlaybackMode> _modeController =
      StreamController<PlaybackMode>.broadcast();
  final StreamController<List<MediaItem>> _upcomingQueueController =
      StreamController<List<MediaItem>>.broadcast();
  final StreamController<Track> _consumedTrackController =
      StreamController<Track>.broadcast();
  final StreamController<Track> _completedTrackController =
      StreamController<Track>.broadcast();
  final StreamController<String> _userCommandController =
      StreamController<String>.broadcast();
  // Together distinguishes originating user/media controls from its own
  // received commands before async stream delivery can blur that boundary.
  final StreamController<String> _togetherUserCommandController =
      StreamController<String>.broadcast(sync: true);
  final StreamController<bool> _seekingController =
      StreamController<bool>.broadcast(sync: true);
  bool _isSeeking = false;
  int _seeksInFlight = 0;
  final Map<String, Uri> _artworkUriCache = <String, Uri>{};
  // Existing pinned audio/cache or schema migration API; covered by regression tests.
  // ignore: experimental_member_use
  final Map<String, LockCachingAudioSource> _remoteCachingSources =
      // Existing pinned audio/cache or schema migration API; covered by regression tests.
      // ignore: experimental_member_use
      <String, LockCachingAudioSource>{};

  late final Future<void> _ready;
  late final PauseFadeController _pauseFadeController;
  PlaybackOrder _order = const PlaybackOrder();
  List<String> _unshuffledUpcomingIds = const [];
  PlaybackMode get _mode => _order.legacy;
  final _orderController = StreamController<PlaybackOrder>.broadcast();
  bool _randomUpcoming = false;
  String? _explicitNextId;
  final _randomUpcomingController = StreamController<bool>.broadcast();
  bool get randomUpcoming => _randomUpcoming;
  Stream<bool> get randomUpcomingStream async* {
    yield _randomUpcoming;
    yield* _randomUpcomingController.stream;
  }

  /// This chooses from remaining pending recordings, never shuffles the
  /// displayed list or changes the playing source/global repeat order.
  Future<void> setRandomUpcoming(bool enabled) async {
    if (_randomUpcoming == enabled) return;
    _randomUpcoming = enabled;
    _randomUpcomingController.add(enabled);
  }

  PlaybackOrder get playbackOrder => _order;
  Stream<PlaybackOrder> get playbackOrderStream async* {
    yield _order;
    yield* _orderController.stream;
  }

  List<MediaItem> _upcomingMediaItems = const <MediaItem>[];
  bool _currentFavorite = false;
  bool _lyricsOverlayVisible = false;
  bool _lyricsOverlayLocked = false;
  final List<Track> _playbackHistory = <Track>[];
  bool _historyNavigation = false;
  bool _completionInFlight = false;
  _PendingAdvanceRequest? _pendingAdvanceRequest;
  final PlaybackCompletionGate _completionGate = PlaybackCompletionGate();
  int _consecutiveLoadFailures = 0;
  // Async artwork/source resolution may finish after a new tap. These epochs
  // make stale results harmless instead of allowing them to replace a newer
  // user-selected queue or restored session.
  int _queueLoadEpoch = 0;
  // Logical selection is visible while transport is still resolving. Mask old
  // native events so they cannot become progress/history for the new song.
  int? _pendingQueueEpoch;
  String? _loadedTrackId;
  ({String id, Duration position})? _deferredRestore;
  final _deferredPositions = StreamController<Duration>.broadcast();
  String? _resolutionError;
  int _userCommandEpoch = 0;
  // Separate transport intent from serialized Next taps and queue edits. A
  // delayed source lookup must never undo a later Pause, Stop or Seek command.
  int _transportIntentEpoch = 0;
  Timer? _consumptionTimer;
  Timer? _playbackStartTimer;
  String? _confirmedConsumedMediaId;
  String? _lastFailedTrackId;
  int? _lastFailedLoadEpoch;
  bool _handlingPlaybackFailure = false;
  bool? _lastLoggedPlaying;
  ProcessingState? _lastLoggedProcessingState;
  bool _currentSourceFromCache = false;
  final Set<String> _directRemoteSourceIds = <String>{};
  RadioTrackLoader? _radioTrackLoader;
  bool _preserveServerOrder = false;
  bool _explicitPlaybackContext = false;
  bool _continueAfterExplicitQueue = false;
  final Set<String> _recommendedUpcomingIds = {};

  /// Generated continuation must not trigger a destructive-queue confirmation.
  List<MediaItem> get manuallyQueuedItems => List.unmodifiable(
    _upcomingMediaItems.where(
      (item) => !_recommendedUpcomingIds.contains(item.id),
    ),
  );
  bool isAutomaticallyQueued(String id) => _recommendedUpcomingIds.contains(id);
  void Function()? _onExplicitPlayback;
  TrackPlaybackResolver? _trackPlaybackResolver;
  TrackLoadFailurePolicy? _skipUnplayableTrack;
  bool _refreshingSource = false;

  /// A provider may refresh expiring URLs without coupling this audio owner to
  /// a particular account system, server transport or music catalogue.
  void configureTrackPlaybackResolver(
    TrackPlaybackResolver? resolver, {
    TrackLoadFailurePolicy? skipUnplayableTrack,
  }) {
    _invalidatePreparation();
    _trackPlaybackResolver = resolver;
    _skipUnplayableTrack = skipUnplayableTrack;
  }

  /// Refresh the current stream without rebuilding the logical queue, history,
  /// playback mode or consumed-track timer. Resolve while the old stream keeps
  /// playing; a newer seek/pause/skip/account reset makes this result stale.
  /// Only this audio owner may swap sources. UI never creates another player.
  Future<bool> refreshCurrentSource() => _refreshCurrentSource();

  /// Keep the original refresh contract for other controllers. Only this audio
  /// owner may install a preflighted quality source, using the same epoch gate.
  Future<bool> refreshVerifiedSource(TrackPlaybackResolver resolve) =>
      _refreshCurrentSource(resolveSource: resolve);

  Future<bool> _refreshCurrentSource({
    TrackPlaybackResolver? resolveSource,
  }) async {
    await _ready;
    final current = trackForId(mediaItem.value?.id ?? '');
    final resolver = resolveSource ?? _trackPlaybackResolver;
    if (current == null || resolver == null) return false;
    if (resolveSource != null &&
        (_resolutionError != null || current.id != _loadedTrackId)) {
      return false;
    }
    if (_resolutionError != null || current.id != _loadedTrackId) {
      await playSingleTrack(current);
      return mediaItem.value?.id == current.id &&
          _loadedTrackId == current.id &&
          _resolutionError == null;
    }
    _markUserCommand('changeQuality');
    final command = _userCommandEpoch;
    final epoch = _queueLoadEpoch;
    bool currentRequest() =>
        command == _userCommandEpoch &&
        epoch == _queueLoadEpoch &&
        mediaItem.value?.id == current.id;
    final resolved = await resolver(current);
    if (resolved.id != current.id) return false;
    if (!currentRequest()) return false;
    final item = await _mediaItemFor(resolved);
    final source = await _audioSourceFor(resolved, item);
    if (!currentRequest()) return false;
    final position = _player.position;
    final playing = _player.playing;
    _cancelPlaybackStartGuard();
    _refreshingSource = true;
    try {
      await _player.setAudioSources([source], initialPosition: position);
      if (!currentRequest()) return false;
      _knownTracks[resolved.id] = resolved;
      _tracks = [
        for (final track in _tracks)
          if (track.id == resolved.id) resolved else track,
      ];
      queue.add([
        for (final old in queue.value)
          if (old.id == resolved.id) item else old,
      ]);
      mediaItem.add(item);
      if (playing) _startPlayer();
      return true;
    } on Object {
      // A failed decoder must not auto-skip a user's song. Restore the working
      // source and position once, only if no newer command has taken ownership.
      if (currentRequest()) {
        final previousItem = await _mediaItemFor(current);
        final previousSource = await _audioSourceFor(current, previousItem);
        if (currentRequest()) {
          await _player.setAudioSources([
            previousSource,
          ], initialPosition: position);
          if (playing && currentRequest()) _startPlayer();
        }
      }
      rethrow;
    } finally {
      _refreshingSource = false;
    }
  }

  Future<void>? _radioLoadInFlight;
  final Set<String> _autoplaySessionTrackKeys = <String>{};
  int _radioRecommendationGeneration = 0;
  int _consecutiveRadioRefillMisses = 0;

  static const _recentFallbackWindow = 8;
  static const _radioPrefetchThreshold = 24;
  static const _radioRefillAttemptLimit = 3;
  static const _lyricsOverlayChannel = MethodChannel(
    'com.mesting.music/lyrics_overlay',
  );
  static const _maximumRadioPoolSize = 360;
  static const _playbackStartGuard = PlaybackStartGuard();

  static const notificationToggleFavoriteAction = 'notificationToggleFavorite';
  static const notificationToggleLyricsAction = 'notificationToggleLyrics';

  List<Track> get tracks => List.unmodifiable(_tracks);

  Stream<Duration> get positionStream => Stream<Duration>.multi((events) {
    var completed = 0;
    void done() {
      if (++completed == 2) events.close();
    }

    final native = _positions.stream.listen(
      (position) => events.add(_deferredPosition ?? position),
      onError: events.addError,
      onDone: done,
    );
    final restored = _deferredPositions.stream.listen(
      events.add,
      onError: events.addError,
      onDone: done,
    );
    events.add(_deferredPosition ?? currentPosition);
    events.onCancel = () async {
      await native.cancel();
      await restored.cancel();
    };
  }, isBroadcast: true);

  Duration? get _deferredPosition => _deferredRestore?.id == mediaItem.value?.id
      ? _deferredRestore?.position
      : null;
  Stream<Duration?> get durationStream async* {
    yield _player.duration;
    yield* _durations.stream;
  }

  /// Explicit seek work can leave just_audio's playing flag true. Listening
  /// accounting observes this edge instead of charging decoder seek latency.
  Stream<bool> get seekingStream => _seekingController.stream;
  bool get isSeeking => _isSeeking;
  Stream<void> get nativeRepeatBoundaryStream => _repeatBoundaries.stream;
  int? get androidAudioSessionId => _player.androidAudioSessionId;

  /// The existing single player owns this PCM effect and its native lifetime.
  /// A UI meter never changes playback, audio focus, routing or permissions.
  Future<Map<String, Object?>> musicRhythmFrame(bool enabled) =>
      _player.musicRhythmFrame(enabled);

  /// Account/entitlement checks belong to the Soda effect controller.
  Future<Map<String, Object?>> setQishuiAudioEffect(String? config) {
    _effectConfig = config;
    _invalidatePreparation();
    return _player.setSodaAudioEffect(config);
  }

  Future<Map<String, Object?>> qishuiAudioEffectStatus() =>
      _player.sodaAudioEffectStatus();
  Stream<int?> get androidAudioSessionIdStream async* {
    yield _player.androidAudioSessionId;
    yield* _sessions.stream;
  }

  /// A modal MV may resume only while no later transport command supersedes it.
  int get transportRevision => _userCommandEpoch;

  /// Invalidates only the transport still owned by one Together application.
  /// A timeout cannot cancel a newer tap, account request or normally playing
  /// source. Epoch invalidation stops a late lookup from loading/autoplaying;
  /// it intentionally never issues a delayed stop against the next selection.
  bool cancelPendingTogetherPlayback(int expectedTransportRevision) {
    if (_userCommandEpoch != expectedTransportRevision) return false;
    ++_userCommandEpoch;
    ++_transportIntentEpoch;
    ++_queueLoadEpoch;
    if (_pendingQueueEpoch != null) {
      _pendingQueueEpoch = null;
      _resolutionError = '一起听播放同步等待重试';
      _cancelPlaybackStartGuard();
      _broadcastState(_player.playbackEvent);
    }
    return true;
  }

  bool _togetherCurrent(bool Function()? guard, int revision) =>
      guard == null || guard() && transportRevision == revision;
  Stream<PlaybackMode> get playbackModeStream async* {
    yield _mode;
    yield* _modeController.stream;
  }

  Stream<List<MediaItem>> get upcomingQueueStream async* {
    yield upcomingQueue;
    yield* _upcomingQueueController.stream;
  }

  /// Emits after a track has played continuously for one second. Queue restore
  /// and source preloading do not emit, so it is safe for recent-play history.
  Stream<Track> get consumedTrackStream => _consumedTrackController.stream;

  /// Emits only when the audio engine reaches the natural end of a track.
  Stream<Track> get completedTrackStream => _completedTrackController.stream;
  Stream<String> get userCommandStream => _userCommandController.stream;
  Stream<String> get togetherUserCommandStream =>
      _togetherUserCommandController.stream;

  PlaybackMode get playbackMode => _mode;
  Duration get currentPosition =>
      _pendingQueueEpoch == null &&
          _resolutionError == null &&
          mediaItem.value?.id == _loadedTrackId
      ? _player.position
      : _deferredPosition ?? Duration.zero;
  int get currentIndex => _player.currentIndex ?? 0;
  @visibleForTesting
  int get debugAudioSourceCount => _player.sequence.length;
  @visibleForTesting
  bool get debugCurrentSourceFromCache => _currentSourceFromCache;
  @visibleForTesting
  bool get debugPauseFadeInProgress => _pauseFadeController.isFading;
  @visibleForTesting
  Future<bool> debugIsRemoteCacheComplete(String trackId) async {
    final source = _remoteCachingSources[trackId];
    if (source == null) return false;
    return (await source.cacheFile).exists();
  }

  @visibleForTesting
  Future<void> debugDispose() async {
    _transition.invalidate();
    await _cancelTransition();
    await _transition.clearPreparation();
    for (final sub in _nativeSubscriptions) {
      await sub.cancel();
    }
    await _positions.close();
    await _durations.close();
    await _sessions.close();
    await _repeatBoundaries.close();
    await _transitionInterruptions?.cancel();
    sleepTimer.dispose();
    _cancelPlaybackStartGuard();
    _consumptionTimer?.cancel();
    await _pauseFadeController.cancel();
    await _cancelTransition();
    await _userCommandController.close();
    await _togetherUserCommandController.close();
    await _seekingController.close();
    await _deferredPositions.close();
    await _randomUpcomingController.close();
    await _player.dispose();
  }

  List<MediaItem> get upcomingQueue =>
      List<MediaItem>.unmodifiable(_upcomingMediaItems);

  /// Snapshot used for persistence: current track followed by upcoming tracks.
  ///
  /// It intentionally excludes historical/fallback pools and de-duplicates by
  /// id, so restoration reproduces what the listener can actually play next.
  List<Track> get persistedQueue {
    final currentId = mediaItem.value?.id;
    final result = <Track>[];
    final seen = <String>{};
    if (currentId != null) {
      final current = trackForId(currentId);
      if (current != null) {
        result.add(current);
        seen.add(current.id);
      }
    }
    for (final item in _upcomingMediaItems) {
      final track = trackForId(item.id);
      if (track != null && seen.add(track.id)) result.add(track);
    }
    return List<Track>.unmodifiable(result);
  }

  Future<void> _initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _transitionInterruptions = session.interruptionEventStream.listen((event) {
      _interruptionGain =
          event.begin && event.type == AudioInterruptionType.duck ? .5 : 1;
      if (event.begin) {
        _invalidatePreparation();
        // Let each decoder process its ordinary session interruption first.
        // An envelope must not undo system ducking or revive paused audio.
        unawaited(
          Future<void>.microtask(_cancelTransition).catchError((Object _) {}),
        );
      }
    });
    await _loadQueue(_tracks);
    await _applyPlaybackOrder();
  }

  /// Replaces the logical queue while protecting against stale async loads.
  ///
  /// [requiredUserCommandEpoch] is used by cold-session restoration: if the
  /// listener taps a track before the restore finishes, the restore is dropped
  /// rather than taking control back from that explicit command.
  Future<bool> _loadQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool preload = true,
    bool deferSource = false,
    int? requiredUserCommandEpoch,
    int? requiredTransportIntentEpoch,
    bool Function()? ownerCurrent,
    bool allowFailureRecovery = false,
  }) async {
    // Resolve one bounded queue snapshot, in order, without recursive loads or
    // recommendation refills. Each failed identity is removed for this round.
    // A newer tap, Pause, account change or failed global service cancels it.
    final intent = requiredTransportIntentEpoch ?? _transportIntentEpoch;
    var remaining = tracks;
    var index = initialIndex;
    var position = initialPosition;
    final attempted = <String>{};
    while (true) {
      final attemptEpoch = _queueLoadEpoch + 1;
      try {
        return await _loadQueueOnce(
          remaining,
          initialIndex: index,
          initialPosition: position,
          preload: preload,
          deferSource: deferSource,
          requiredUserCommandEpoch: requiredUserCommandEpoch,
          requiredTransportIntentEpoch: intent,
          ownerCurrent: ownerCurrent,
        );
      } on Object catch (error) {
        if (remaining.isEmpty ||
            !allowFailureRecovery ||
            deferSource ||
            intent != _transportIntentEpoch ||
            attemptEpoch != _queueLoadEpoch ||
            ownerCurrent?.call() == false ||
            (requiredUserCommandEpoch != null &&
                requiredUserCommandEpoch != _userCommandEpoch)) {
          rethrow;
        }
        final safeIndex = index.clamp(0, remaining.length - 1);
        final failed = remaining[safeIndex];
        if (_skipUnplayableTrack?.call(failed, error) != true) rethrow;
        attempted.add(failed.id);
        remaining = [
          ...remaining.skip(safeIndex + 1),
          ...remaining.take(safeIndex),
        ].where((track) => !attempted.contains(track.id)).toList();
        if (remaining.isEmpty) {
          _resolutionError = '本轮队列没有可播放的歌曲，已停止，请稍后重试';
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              playing: false,
              errorMessage: _resolutionError,
            ),
          );
          throw PlaybackContinuationException(_resolutionError!);
        }
        index = 0;
        position = Duration.zero;
      }
    }
  }

  Future<bool> _loadQueueOnce(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool preload = true,
    bool deferSource = false,
    int? requiredUserCommandEpoch,
    int? requiredTransportIntentEpoch,
    bool Function()? ownerCurrent,
  }) async {
    final transportEpoch =
        requiredTransportIntentEpoch ?? _transportIntentEpoch;
    // A delayed, already superseded command must not invalidate the newer load.
    if (ownerCurrent?.call() == false ||
        transportEpoch != _transportIntentEpoch ||
        (requiredUserCommandEpoch != null &&
            requiredUserCommandEpoch != _userCommandEpoch)) {
      return false;
    }
    await _cancelTransition();
    if (transportEpoch != _transportIntentEpoch ||
        ownerCurrent?.call() == false ||
        (requiredUserCommandEpoch != null &&
            requiredUserCommandEpoch != _userCommandEpoch)) {
      return false;
    }
    final loadEpoch = ++_queueLoadEpoch;
    bool isCurrent() =>
        ownerCurrent?.call() != false &&
        loadEpoch == _queueLoadEpoch &&
        transportEpoch == _transportIntentEpoch &&
        (requiredUserCommandEpoch == null ||
            requiredUserCommandEpoch == _userCommandEpoch);
    if (!isCurrent()) return false;
    _cancelPlaybackStartGuard();
    _resolutionError = null;
    for (final track in tracks) {
      _knownTracks[track.id] = track;
    }
    if (tracks.isEmpty) {
      _deferredRestore = null;
      _pendingQueueEpoch = null;
      _loadedTrackId = null;
      _tracks = <Track>[];
      queue.add(const <MediaItem>[]);
      _upcomingMediaItems = const <MediaItem>[];
      _publishUpcomingQueue();
      mediaItem.add(null);
      _resetConsumptionConfirmation();
      _completionGate.reset();
      await _player.setAudioSources(const []);
      _trace('load-empty');
      return true;
    }

    final safeIndex = initialIndex.clamp(0, tracks.length - 1);
    final orderedTracks = <Track>[
      tracks[safeIndex],
      ...tracks.skip(safeIndex + 1),
      ...tracks.take(safeIndex),
    ];
    if (deferSource) {
      // Publish a paused, saved queue before resolving a short-lived audio URL.
      // Offline startup and expired sessions must leave the resume UI usable.
      _pendingQueueEpoch = null;
      _loadedTrackId = null;
      _deferredRestore = (
        id: orderedTracks.first.id,
        position: initialPosition,
      );
      _resetConsumptionConfirmation();
      _completionGate.reset();
      await _player.stop();
      if (!isCurrent()) return false;
      await _player.setAudioSources(const []);
      if (!isCurrent()) return false;
      _tracks = orderedTracks;
      final items = orderedTracks.map((track) => track.toMediaItem()).toList();
      queue.add(items);
      _upcomingMediaItems = items.skip(1).toList(growable: false);
      mediaItem.add(items.first);
      _publishUpcomingQueue();
      _deferredPositions.add(initialPosition);
      _broadcastState(_player.playbackEvent);
      return true;
    }
    if (_deferredRestore?.id != orderedTracks.first.id) _deferredRestore = null;
    _pendingQueueEpoch = loadEpoch;
    _resetConsumptionConfirmation();
    _completionGate.reset();
    final prepared = _transition.ready;
    if (initialPosition == Duration.zero &&
        prepared != null &&
        prepared.track.id == orderedTracks.first.id) {
      _transition.ready = null;
      final previous = _player;
      _player = prepared.player;
      _bindPlayer(_player);
      _currentSourceFromCache = false;
      final restore = _player.setVolume(_interruptionGain);
      orderedTracks[0] = prepared.track;
      final publication = _publishPrepared(
        orderedTracks,
        isCurrent,
      ).catchError((Object _) => false);
      await previous.stop();
      await previous.dispose();
      await restore;
      final published = await publication;
      if (!isCurrent()) return false;
      await _player.setMusicOutputOwner('mesting-music');
      return published;
    }
    _invalidatePreparation();
    // Stop is issued before any network work. Publish loading before changing
    // identity so listening reporters never attribute the old audio to it.
    final stopped = _player.stop();
    _broadcastState(_player.playbackEvent);
    _tracks = orderedTracks;
    final selectedItems = orderedTracks.map((t) => t.toMediaItem()).toList();
    queue.add(selectedItems);
    _upcomingMediaItems = selectedItems.skip(1).toList(growable: false);
    mediaItem.add(selectedItems.first);
    _publishUpcomingQueue();
    try {
      await stopped;
      if (!isCurrent()) return false;
      final resolver = _trackPlaybackResolver;
      if (resolver != null) {
        final Track active;
        try {
          active = await resolver(orderedTracks.first);
        } catch (_) {
          // A newer tap/pause can cancel the previous HTTP lookup. Ignore that
          // stale failure just as we ignore a stale success; the live command
          // retains its own error reporting and audio state.
          if (!isCurrent()) return false;
          rethrow;
        }
        if (!isCurrent()) {
          return false;
        }
        orderedTracks[0] = active;
        _knownTracks[active.id] = active;
      }
      final mediaItems = await Future.wait(orderedTracks.map(_mediaItemFor));
      if (!isCurrent()) {
        _trace('load-stale-before-source epoch=$loadEpoch');
        return false;
      }

      final activeSource = await _audioSourceFor(
        orderedTracks.first,
        mediaItems.first,
      );
      if (!isCurrent()) {
        _trace('load-stale-after-source-resolution epoch=$loadEpoch');
        return false;
      }
      // Refine the selected metadata with the resolved source, keeping its identity.
      _tracks = orderedTracks;
      queue.add(mediaItems);
      _upcomingMediaItems = mediaItems.skip(1).toList(growable: false);
      mediaItem.add(mediaItems.first);
      await _configureLoudness(_player, orderedTracks.first);
      try {
        await _player.setAudioSources(
          <AudioSource>[activeSource],
          preload: preload,
          initialIndex: 0,
          initialPosition: initialPosition,
        );
      } on Object catch (error) {
        if (!isCurrent()) return false;
        final selected = orderedTracks.first;
        MusicNetworkDiagnostics.shared.record(
          platform: 'audio',
          operation: MusicNetworkOperation.audio,
          outcome: classifyMusicNetworkError(error),
          transport: 'cache',
        );
        // Initial preparation errors were excluded by the playback-event guard,
        // so the existing direct retry never ran for this common failure path.
        // Retry the same recording/quality once; no skip or listening is added.
        // Existing pinned cache API; the fork has bounded network regressions.
        // ignore: experimental_member_use
        if (activeSource is! LockCachingAudioSource ||
            !_recoverableNetworkLoad(error) ||
            !selected.isRemote ||
            !_directRemoteSourceIds.add(selected.id)) {
          rethrow;
        }
        final direct = await _audioSourceFor(selected, mediaItems.first);
        if (!isCurrent()) return false;
        try {
          await _player.setAudioSources(
            [direct],
            preload: preload,
            initialIndex: 0,
            initialPosition: initialPosition,
          );
        } on Object {
          if (!isCurrent()) return false;
          var restored = false;
          // Alternatives are supplied by this exact resolved recording, never
          // guessed from CDN patterns or borrowed from another source/quality.
          for (final backup in publicAudioAlternatives(
            selected.audioAlternatives,
          )) {
            if (!isCurrent()) return false;
            final candidate = selected.copyWith(audioAsset: backup);
            final candidateItem = await _mediaItemFor(candidate);
            final candidateSource = await _audioSourceFor(
              candidate,
              candidateItem,
            );
            if (!isCurrent()) return false;
            try {
              await _player.setAudioSources(
                [candidateSource],
                preload: preload,
                initialIndex: 0,
                initialPosition: initialPosition,
              );
            } on Object {
              if (!isCurrent()) return false;
              continue;
            }
            if (!isCurrent()) return false;
            orderedTracks[0] = candidate;
            _knownTracks[candidate.id] = candidate;
            mediaItems[0] = candidateItem;
            queue.add(List.of(mediaItems));
            mediaItem.add(candidateItem);
            restored = true;
            break;
          }
          if (!restored) rethrow;
        }
        MusicNetworkDiagnostics.shared.record(
          platform: 'audio',
          operation: MusicNetworkOperation.audio,
          outcome: MusicNetworkOutcome.success,
          attempt: 2,
          transport: 'nativeAudio',
        );
      }
      if (!isCurrent()) {
        _trace('load-stale-after-source epoch=$loadEpoch');
        return false;
      }
      _pendingQueueEpoch = null;
      _loadedTrackId = orderedTracks.first.id;
      _deferredRestore = null;
      _handleDuration(_player.duration);
      _broadcastState(_player.playbackEvent);
      _publishUpcomingQueue();
      // The native engine has one active source. Its index often stays at zero,
      // so distinct currentIndex events cannot own the logical playback history.
      _recordPlaybackHistory(orderedTracks.first);
      await _applyPlaybackOrder();
      _scheduleConsumptionConfirmation();
      _trace(
        'load-current id=${mediaItems.first.id} '
        'upcoming=${_upcomingMediaItems.length} sourceCount=${_player.sequence.length}',
      );
      return true;
    } catch (_) {
      if (isCurrent()) {
        _pendingQueueEpoch = null;
        _resolutionError = '歌曲加载失败，请重试或选择其他音源';
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
            updatePosition: _deferredPosition ?? Duration.zero,
            errorMessage: '歌曲加载失败，请重试或选择其他音源',
          ),
        );
      }
      rethrow;
    }
  }

  Future<MediaItem> _mediaItemFor(Track track) async {
    if (track.isRemote) return track.toMediaItem();
    final localArtwork = Uri.tryParse(track.coverAsset);
    if (localArtwork != null &&
        (localArtwork.scheme == 'file' || localArtwork.scheme == 'content')) {
      return track.toMediaItem(artUri: localArtwork);
    }
    final cached = _artworkUriCache[track.coverAsset];
    if (cached != null) return track.toMediaItem(artUri: cached);

    try {
      final bytes = await rootBundle.load(track.coverAsset);
      final cacheDirectory = await getTemporaryDirectory();
      final artworkDirectory = Directory(
        '${cacheDirectory.path}${Platform.pathSeparator}notification_artwork',
      );
      await artworkDirectory.create(recursive: true);
      final extension = _fileExtension(track.coverAsset);
      final safeId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final artworkFile = File(
        '${artworkDirectory.path}${Platform.pathSeparator}$safeId$extension',
      );
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      if (!await artworkFile.exists() ||
          await artworkFile.length() != data.length) {
        await artworkFile.writeAsBytes(data, flush: true);
      }
      final uri = artworkFile.uri;
      _artworkUriCache[track.coverAsset] = uri;
      return track.toMediaItem(artUri: uri);
    } on Object {
      // Playback should remain available even if an individual artwork asset
      // cannot be prepared for the Android media notification.
      return track.toMediaItem();
    }
  }

  String _fileExtension(String path) {
    final cleanPath = path.split('?').first;
    final dot = cleanPath.lastIndexOf('.');
    if (dot < 0 || dot < cleanPath.lastIndexOf('/')) return '.png';
    return cleanPath.substring(dot).toLowerCase();
  }

  /// A programming/decoder failure must not be converted into a successful
  /// network retry. Android's pinned player reports source I/O as type 0;
  /// renderer/codec failures use different ExoPlaybackException types.
  static bool _recoverableNetworkLoad(Object error) =>
      error is SocketException ||
      error is HttpException ||
      error is TlsException ||
      error is TimeoutException ||
      error is PlayerException && error.code == 0;

  Future<AudioSource> _audioSourceFor(Track track, MediaItem item) async {
    if (track.isRemote) {
      final remoteUri = Uri.parse(track.audioAsset);
      if (_directRemoteSourceIds.contains(track.id)) {
        _currentSourceFromCache = false;
        _trace('source-remote id=${track.id} strategy=direct');
        return AudioSource.uri(
          remoteUri,
          headers: track.audioHeaders.isEmpty
              ? null
              : publicAudioHeaders(track.audioHeaders),
          tag: item,
        );
      }
      // Existing pinned audio/cache or schema migration API; covered by regression tests.
      // ignore: experimental_member_use
      final cachingSource = LockCachingAudioSource(
        remoteUri,
        headers: publicAudioHeaders(track.audioHeaders),
        tag: item,
      );
      _remoteCachingSources[track.id] = cachingSource;
      final resolved = await cachingSource.resolve();
      _currentSourceFromCache = !identical(resolved, cachingSource);
      _trace(
        'source-remote id=${track.id} strategy=cache '
        'cacheHit=$_currentSourceFromCache',
      );
      return resolved;
    }
    _currentSourceFromCache = false;
    final localUri = Uri.tryParse(track.audioAsset);
    if (localUri != null &&
        (localUri.scheme == 'file' || localUri.scheme == 'content')) {
      return AudioSource.uri(localUri, tag: item);
    }
    return AudioSource.asset(track.audioAsset, tag: item);
  }

  void _handleCurrentIndex(int? index) {
    if (_refreshingSource ||
        _pendingQueueEpoch != null ||
        mediaItem.value?.id != _loadedTrackId) {
      return;
    }
    final items = queue.value;
    if (index == null || index < 0 || index >= items.length) return;
    final current = items[index];
    mediaItem.add(current);
    if (!_continueAfterExplicitQueue) {
      final track = trackForId(current.id);
      if (track != null) _recordPlaybackHistory(track);
    }
    _scheduleConsumptionConfirmation();
    _broadcastState(_player.playbackEvent);
  }

  void _recordPlaybackHistory(Track currentTrack) {
    if (!_historyNavigation &&
        (_playbackHistory.isEmpty ||
            _playbackHistory.last.id != currentTrack.id)) {
      _playbackHistory.add(currentTrack);
      if (_playbackHistory.length > 100) _playbackHistory.removeAt(0);
    }
    _historyNavigation = false;
  }

  void _resetConsumptionConfirmation() {
    _consumptionTimer?.cancel();
    _consumptionTimer = null;
    _confirmedConsumedMediaId = null;
  }

  void _scheduleConsumptionConfirmation() {
    final currentId = mediaItem.value?.id;
    if (_pendingQueueEpoch != null ||
        _player.processingState != ProcessingState.ready ||
        !_player.playing ||
        currentId == null ||
        currentId == _confirmedConsumedMediaId ||
        _consumptionTimer != null) {
      if (!_player.playing) {
        _consumptionTimer?.cancel();
        _consumptionTimer = null;
      }
      return;
    }
    _consumptionTimer = Timer(const Duration(seconds: 1), () {
      _consumptionTimer = null;
      if (!_player.playing || mediaItem.value?.id != currentId) return;
      _confirmCurrentConsumed(currentId);
    });
  }

  void _confirmCurrentConsumed(String currentId) {
    if (_confirmedConsumedMediaId == currentId) return;
    _confirmedConsumedMediaId = currentId;
    final consumedTrack = trackForId(currentId);
    if (consumedTrack != null) {
      _consumedTrackController.add(consumedTrack);
    }

    // Update application-level queue metadata only. Do not call
    // setAudioSources here: the active source must keep playing while the UI
    // removes the consumed track from its pending-queue representation.
    final previousUpcomingLength = _upcomingMediaItems.length;
    _upcomingMediaItems = QueueEngine.withoutId(
      _upcomingMediaItems,
      currentId,
      idOf: (item) => item.id,
    );
    _tracks = QueueEngine.keepCurrentAndRemoveDuplicate(
      _tracks,
      currentId,
      idOf: (track) => track.id,
    );
    queue.add(
      QueueEngine.keepCurrentAndRemoveDuplicate(
        queue.value,
        currentId,
        idOf: (item) => item.id,
      ),
    );
    if (_upcomingMediaItems.length != previousUpcomingLength) {
      _publishUpcomingQueue();
    }
    _trace(
      'consumed id=$currentId upcoming=${_upcomingMediaItems.length} '
      'sourceCount=${_player.sequence.length}',
    );
  }

  void _publishUpcomingQueue() {
    if (_continueAfterExplicitQueue) {
      // Manual additions take priority in BOTH the visible queue and actual
      // playback; the old grouped sheet already presented this ordering.
      _upcomingMediaItems = [
        ..._upcomingMediaItems.where(
          (item) => !_recommendedUpcomingIds.contains(item.id),
        ),
        ..._upcomingMediaItems.where(
          (item) => _recommendedUpcomingIds.contains(item.id),
        ),
      ];
    }
    _upcomingQueueController.add(upcomingQueue);
    if (_transition.ready?.queueKey != null &&
        _transition.ready!.queueKey != _nextQueueKey()) {
      _invalidatePreparation();
    }
  }

  void _handleDuration(Duration? duration) {
    if (_pendingQueueEpoch != null || mediaItem.value?.id != _loadedTrackId) {
      return;
    }
    final current = mediaItem.value;
    if (current == null || duration == null || current.duration == duration) {
      return;
    }
    mediaItem.add(current.copyWith(duration: duration));
    final known = trackForId(current.id);
    // Decoder measurements belong to this exact recording. Persist a complete
    // source's duration, but never replace full-song metadata with a preview.
    if (known != null && !known.isPreview && duration > Duration.zero) {
      _knownTracks[current.id] = known.copyWith(duration: duration);
      var changed = false;
      _upcomingMediaItems = _upcomingMediaItems
          .map((item) {
            if (item.id != current.id || item.duration == duration) return item;
            changed = true;
            return item.copyWith(duration: duration);
          })
          .toList(growable: false);
      if (changed) _publishUpcomingQueue();
    }
  }

  void _handlePosition(Duration position) {
    sleepTimer.checkDeadline();
    _tickPreparation(position);
    if (position <= Duration.zero) return;
    _cancelPlaybackStartGuard();
    // Source replacement can update the current index before any bytes have
    // played. Count a failure as recovered only after real progress arrives.
    _consecutiveLoadFailures = 0;
  }

  bool _isNetworkTrack(Track track) {
    final uri = Uri.tryParse(track.audioAsset);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  void _cancelPlaybackStartGuard() {
    _playbackStartTimer?.cancel();
    _playbackStartTimer = null;
  }

  void _armPlaybackStartGuard() {
    _cancelPlaybackStartGuard();
    final trackId = mediaItem.value?.id;
    final track = trackId == null ? null : trackForId(trackId);
    if (trackId == null || track == null || !_isNetworkTrack(track)) return;

    final loadEpoch = _queueLoadEpoch;
    _playbackStartTimer = Timer(_playbackStartGuard.timeout, () {
      _playbackStartTimer = null;
      if (mediaItem.value?.id != trackId || _queueLoadEpoch != loadEpoch) {
        return;
      }
      if (!_playbackStartGuard.shouldReportStalled(
        isNetworkSource: true,
        playing: _player.playing,
        processingState: _player.processingState,
        position: _player.position,
      )) {
        return;
      }
      _trace('start-watchdog-stalled id=$trackId');
      unawaited(
        _handlePlaybackFailure(
          StateError('音源未返回可播放的音频数据'),
          origin: 'start-watchdog',
          expectedTrackId: trackId,
          expectedLoadEpoch: loadEpoch,
        ),
      );
    });
  }

  Future<void> _handlePlaybackFailure(
    Object error, {
    StackTrace? stackTrace,
    required String origin,
    String? expectedTrackId,
    int? expectedLoadEpoch,
  }) async {
    final failedTrackId = expectedTrackId ?? mediaItem.value?.id;
    final failureEpoch = expectedLoadEpoch ?? _queueLoadEpoch;
    if (_refreshingSource ||
        failedTrackId == null ||
        (expectedTrackId != null && mediaItem.value?.id != expectedTrackId) ||
        (expectedLoadEpoch != null && _queueLoadEpoch != expectedLoadEpoch) ||
        _handlingPlaybackFailure ||
        (_lastFailedTrackId == failedTrackId &&
            _lastFailedLoadEpoch == failureEpoch)) {
      return;
    }

    _handlingPlaybackFailure = true;
    _lastFailedTrackId = failedTrackId;
    _lastFailedLoadEpoch = failureEpoch;
    try {
      _cancelPlaybackStartGuard();
      _completionGate.reset();
      _resetConsumptionConfirmation();
      final failedTrack = trackForId(failedTrackId);
      // The cache proxy improves repeat playback, but a few source hosts do
      // not cooperate with its HTTP/range requests. Retry the same source once
      // directly before treating the link itself as unavailable.
      if (failedTrack != null &&
          _isNetworkTrack(failedTrack) &&
          _directRemoteSourceIds.add(failedTrackId)) {
        _trace('playback-retry-direct id=$failedTrackId origin=$origin');
        try {
          final applied = await _loadQueue(_tracks);
          if (applied) {
            await _applyPlaybackOrder();
            _startPlayer();
            return;
          }
        } on Object catch (retryError, retryStackTrace) {
          developer.log(
            'direct-playback-retry-failed',
            name: 'MestingAudio',
            error: retryError,
            stackTrace: retryStackTrace,
          );
        }
      }

      if (mediaItem.value?.id != failedTrackId) return;
      try {
        await _player.pause();
      } on Object {
        // The terminal error state below is still more useful than leaving the
        // UI looking as though a zero-length song is currently playing.
      }
      developer.log(
        'playback-failed origin=$origin',
        name: 'MestingAudio',
        error: error,
        stackTrace: stackTrace,
      );
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
          errorMessage: '当前音源不可播放，请切换歌曲后重试',
        ),
      );
      _consecutiveLoadFailures += 1;
      _trace(
        'playback-failed id=$failedTrackId origin=$origin '
        'failures=$_consecutiveLoadFailures',
      );
      if (failedTrack?.source == TrackSource.qishui) {
        // Native failures share the same bounded recovery as lookup failures.
        // Consume only the remaining snapshot; do not wrap to failed tracks or
        // fetch an unbounded recommendation chain after the entire queue fails.
        if (_skipUnplayableTrack?.call(failedTrack!, error) != true) return;
        final remaining = _tracks
            .skip(1)
            .where((track) => track.id != failedTrackId)
            .toList();
        if (remaining.isEmpty) {
          _resolutionError = '本轮队列没有可播放的歌曲，已停止，请稍后重试';
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              playing: false,
              errorMessage: _resolutionError,
            ),
          );
          return;
        }
        final intent = _transportIntentEpoch;
        final command = _userCommandEpoch;
        try {
          final applied = await _loadQueue(
            remaining,
            requiredTransportIntentEpoch: intent,
            requiredUserCommandEpoch: command,
            allowFailureRecovery: true,
          );
          if (applied &&
              intent == _transportIntentEpoch &&
              command == _userCommandEpoch) {
            _startPlayer();
          }
        } on Object {
          // The source loader has already published its classified terminal
          // state. Runtime recovery has no UI awaiting this Future to catch it.
        }
        return;
      }
      if (_consecutiveLoadFailures <= 4) {
        // A broken source must not be repeated forever in single-track mode.
        unawaited(
          _advancePlayback(
            forward: true,
            automatic: true,
            bypassSingleRepeat: true,
          ),
        );
      }
    } finally {
      _handlingPlaybackFailure = false;
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final bound =
        _pendingQueueEpoch == null &&
        _resolutionError == null &&
        mediaItem.value?.id == _loadedTrackId;
    _scheduleConsumptionConfirmation();
    if (_lastLoggedPlaying != _player.playing ||
        _lastLoggedProcessingState != _player.processingState) {
      _lastLoggedPlaying = _player.playing;
      _lastLoggedProcessingState = _player.processingState;
      _trace(
        'state playing=${_player.playing} '
        'processing=${_player.processingState.name} '
        'positionMs=${_player.position.inMilliseconds}',
      );
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.custom(
            androidIcon: _currentFavorite
                ? 'drawable/ic_notification_favorite'
                : 'drawable/ic_notification_favorite_border',
            label: _currentFavorite ? '取消收藏' : '收藏',
            name: notificationToggleFavoriteAction,
          ),
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.custom(
            androidIcon: _lyricsOverlayVisible
                ? 'drawable/ic_notification_lyrics_on'
                : 'drawable/ic_notification_lyrics',
            label: _lyricsOverlayLocked
                ? '解锁桌面歌词'
                : _lyricsOverlayVisible
                ? '关闭桌面歌词'
                : '打开桌面歌词',
            name: notificationToggleLyricsAction,
          ),
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [1, 2, 3],
        processingState: _resolutionError != null
            ? AudioProcessingState.error
            : _pendingQueueEpoch != null
            ? AudioProcessingState.loading
            : !bound
            ? AudioProcessingState.idle
            : switch (_player.processingState) {
                ProcessingState.idle => AudioProcessingState.idle,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              },
        playing: bound && _player.playing,
        errorMessage: _resolutionError,
        updatePosition: bound
            ? _player.position
            : _deferredPosition ?? Duration.zero,
        bufferedPosition: bound ? _player.bufferedPosition : Duration.zero,
        speed: _player.speed,
        queueIndex: mediaItem.value == null ? null : 0,
        repeatMode: switch (_order.repeat) {
          PlaybackRepeat.off => AudioServiceRepeatMode.none,
          PlaybackRepeat.all => AudioServiceRepeatMode.all,
          PlaybackRepeat.one => AudioServiceRepeatMode.one,
        },
        shuffleMode: _order.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  Future<void> updateNotificationExtras({
    required bool favorite,
    required bool lyricsOverlayVisible,
    required bool lyricsOverlayLocked,
  }) async {
    if (_currentFavorite == favorite &&
        _lyricsOverlayVisible == lyricsOverlayVisible &&
        _lyricsOverlayLocked == lyricsOverlayLocked) {
      return;
    }
    _currentFavorite = favorite;
    _lyricsOverlayVisible = lyricsOverlayVisible;
    _lyricsOverlayLocked = lyricsOverlayLocked;
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == notificationToggleLyricsAction) {
      final permissionRequestLaunched =
          await _requestOverlayPermissionFromNotification();
      customEvent.add(<String, Object?>{
        'action': name,
        'permissionRequestLaunched': permissionRequestLaunched,
      });
      return;
    }
    if (name == notificationToggleFavoriteAction) {
      customEvent.add(<String, Object?>{'action': name});
      return;
    }
    await super.customAction(name, extras);
  }

  Future<bool> _requestOverlayPermissionFromNotification() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _lyricsOverlayChannel.invokeMethod<bool>(
            'requestPermissionFromNotification',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> play({bool Function()? togetherGuard}) async {
    if (togetherGuard?.call() == false) return;
    final restartAfterSleep = _sleepStoppedAtCompletion;
    _markUserCommand('play', together: togetherGuard != null);
    final togetherRevision = transportRevision;
    await _ready;
    if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    await _pauseFadeController.cancel();
    await _cancelTransition();
    if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    if (restartAfterSleep) {
      _completionGate.reset();
      await _seekPlayer(Duration.zero);
      if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
      await _applyPlaybackOrder();
      if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    }
    _consecutiveLoadFailures = 0;
    if (_resolutionError != null || mediaItem.value?.id != _loadedTrackId) {
      final resumePosition = _deferredPosition;
      final applied = await _loadQueue(
        _tracks,
        initialPosition: resumePosition ?? Duration.zero,
        // If a resumed track needs a new login or network, keep that track and
        // its checkpoint so the user can retry it after recovering access.
        allowFailureRecovery: togetherGuard == null && resumePosition == null,
      );
      if (!applied || !_togetherCurrent(togetherGuard, togetherRevision)) {
        return;
      }
    }
    _startPlayer();
  }

  void _startPlayer() {
    _trace('command-play id=${mediaItem.value?.id}');
    _completionGate.onPlay(_player.position);
    final expectedTrackId = mediaItem.value?.id;
    final expectedLoadEpoch = _queueLoadEpoch;
    _armPlaybackStartGuard();
    // just_audio deliberately completes play() only when playback completes,
    // pauses, or stops. Awaiting that Future while _advancePlayback owns its
    // command lock prevents every later next/previous request for the entire
    // duration of the newly selected track.
    unawaited(
      _player.play().onError((Object error, StackTrace stackTrace) {
        unawaited(
          _handlePlaybackFailure(
            error,
            stackTrace: stackTrace,
            origin: 'play-command',
            expectedTrackId: expectedTrackId,
            expectedLoadEpoch: expectedLoadEpoch,
          ),
        );
      }),
    );
  }

  @override
  Future<void> pause({bool Function()? togetherGuard}) async {
    if (togetherGuard?.call() == false) return;
    _markUserCommand('pause', together: togetherGuard != null);
    final togetherRevision = transportRevision;
    await _ready;
    if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    _cancelPlaybackStartGuard();
    if (togetherGuard != null) {
      // A received pause is already a settled peer intent. Apply it directly
      // rather than keeping the room's command queue behind a UI-style fade.
      await _pauseFadeController.cancel();
      await _cancelTransition();
      if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
      await _player.pause();
      return;
    }
    if (!_player.playing || _player.processingState != ProcessingState.ready) {
      await _pauseFadeController.cancel();
      await _cancelTransition();
      _trace(
        'command-pause-immediate id=${mediaItem.value?.id} '
        'processing=${_player.processingState.name}',
      );
      await _player.pause();
      return;
    }
    _trace(
      'command-pause-fade id=${mediaItem.value?.id} '
      'durationMs=${_pauseFadeController.duration.inMilliseconds}',
    );
    await _pauseFadeController.fadeOutAndPause(_player.volume);
  }

  @override
  Future<void> stop() async {
    sleepTimer.cancel();
    _markUserCommand('stop');
    await _ready;
    _cancelPlaybackStartGuard();
    await _pauseFadeController.cancel();
    await _cancelTransition();
    _resetConsumptionConfirmation();
    _trace('command-stop id=${mediaItem.value?.id}');
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position, {bool Function()? togetherGuard}) async {
    if (togetherGuard?.call() == false) return;
    _markUserCommand('seek', together: togetherGuard != null);
    final togetherRevision = transportRevision;
    await _ready;
    if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    await _pauseFadeController.cancel();
    await _cancelTransition();
    if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    if (_deferredPosition != null && _pendingQueueEpoch == null) {
      // A lyric/progress selection before Play changes only the resume point.
      _deferredRestore = (id: mediaItem.value!.id, position: position);
      _deferredPositions.add(position);
      _broadcastState(_player.playbackEvent);
      return;
    }
    final current = _player.position;
    _completionGate.onSeek(from: current, to: position);
    await _seekPlayer(position);
  }

  Future<void> _seekPlayer(Duration position) async {
    _seeksInFlight++;
    _isSeeking = true;
    _seekingController.add(true);
    try {
      await _player.seek(position);
    } finally {
      _seeksInFlight--;
      _isSeeking = _seeksInFlight > 0;
      _seekingController.add(_isSeeking);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _markUserCommand('skipToQueueItem');
    await _ready;
    await _pauseFadeController.cancel();
    await _cancelTransition();
    if (index < 0 || index >= _tracks.length) return;
    if (index == 0) {
      await _seekPlayer(Duration.zero);
      return;
    }
    await playSingleTrack(_tracks[index]);
  }

  @override
  Future<void> skipToNext() => _skip(forward: true);

  @override
  Future<void> skipToPrevious() => _skip(forward: false);

  Future<void> _skip({required bool forward}) async {
    _markUserCommand(forward ? 'skipNext' : 'skipPrevious');
    await _ready;
    _consecutiveLoadFailures = 0;
    await _pauseFadeController.cancel();
    await _cancelTransition();
    if (!_continueAfterExplicitQueue) {
      await _advancePlayback(forward: forward);
      return;
    }
    final completion = Completer<void>();
    // Keep the user's command alive while recommendation discovery runs. Its
    // eventual failure must reach the same visible control that initiated it.
    unawaited(_advancePlayback(forward: forward, completion: completion));
    await completion.future;
  }

  /// Serializes next/previous/auto-advance decisions into one transition.
  ///
  /// Network radio discovery is deferred outside this lock so a slow refill
  /// cannot discard later next/previous commands from the listener.
  Future<void> _advancePlayback({
    required bool forward,
    bool automatic = false,
    bool bypassSingleRepeat = false,
    Completer<void>? completion,
  }) async {
    final request = _PendingAdvanceRequest(
      forward: forward,
      automatic: automatic,
      bypassSingleRepeat: bypassSingleRepeat,
      completion: completion,
    );
    if (_completionInFlight) {
      _deferAdvance(request);
      return;
    }
    _completionInFlight = true;
    var advanced = false;
    var deferred = false;
    try {
      if (automatic &&
          _order.repeat == PlaybackRepeat.one &&
          !bypassSingleRepeat) {
        await seek(Duration.zero);
        await play();
        return;
      }

      if (!forward &&
          _playbackHistory.length > 1 &&
          (!_explicitPlaybackContext || _continueAfterExplicitQueue)) {
        // An interrupted selection can be visible before it owns a source.
        // History still belongs to the last successfully bound recording.
        final current = trackForId(_loadedTrackId ?? mediaItem.value?.id ?? '');
        final previous = _playbackHistory[_playbackHistory.length - 2];
        await playSingleTrack(
          previous,
          fromHistory: true,
          preservePendingAdvance: true,
          returnToUpcoming: current,
        );
        // Commit the history cursor only after the recording changes. A Pause
        // during lookup leaves both the live source and its history intact.
        advanced =
            mediaItem.value?.id == previous.id && _loadedTrackId == previous.id;
        if (advanced && _playbackHistory.last.id == current?.id) {
          _playbackHistory.removeLast();
        }
        return;
      }

      if (!forward && _continueAfterExplicitQueue) {
        await seek(Duration.zero);
        return;
      }

      if (!forward && _explicitPlaybackContext) {
        // Cold/restored queues may have no previous playback history. Resolve
        // Previous from their ordered list BEFORE considering forward Up Next.
        final context = _playbackContextTracks;
        final current = trackForId(mediaItem.value?.id ?? '');
        final index = context.indexWhere((t) => t.id == current?.id);
        if (context.length > 1 && index >= 0) {
          final previous = context[(index - 1) % context.length];
          await playSingleTrack(
            previous,
            preservePendingAdvance: true,
            returnToUpcoming: current,
          );
          advanced = true;
        } else {
          await seek(Duration.zero);
        }
        return;
      }

      if (!forward && _preserveServerOrder) {
        // A newly opened FM session has no previous song yet. Restart its
        // current song; never consume the next recommendation as Previous.
        await seek(Duration.zero);
        return;
      }

      if (_upcomingMediaItems.isNotEmpty) {
        final manual = manuallyQueuedItems;
        final candidates = _continueAfterExplicitQueue && manual.isNotEmpty
            ? manual
            : _upcomingMediaItems;
        final forcedIndex = candidates.indexWhere(
          (item) => item.id == _explicitNextId,
        );
        final preparedIndex = candidates.indexWhere(
          (item) => item.id == _transition.ready?.track.id,
        );
        final targetIndex = forcedIndex >= 0
            ? forcedIndex
            : preparedIndex >= 0
            ? preparedIndex
            : QueueEngine.resolveUpcomingIndex(
                length: candidates.length,
                // Shuffle is materialized in the visible queue when enabled, so
                // Next must play the first displayed candidate instead of rolling
                // another independent random index behind the user's back.
                mode: _randomUpcoming ? PlaybackMode.random : PlaybackMode.list,
                random: _random,
              );
        final target = trackForId(candidates[targetIndex].id);
        if (target != null) {
          _explicitNextId = null;
          await playSingleTrack(target, preservePendingAdvance: true);
          advanced = true;
          if (_preserveServerOrder) unawaited(_ensureRadioFallbackTracks());
          return;
        }
      }

      if (forward &&
          _order.repeat == PlaybackRepeat.off &&
          _explicitPlaybackContext &&
          !_continueAfterExplicitQueue) {
        if (automatic) await _player.pause();
        return;
      }

      final fallback = _fallbackTrack(
        avoidRecent: automatic || _order.shuffle,
        forward: forward,
      );
      if (fallback != null) {
        _rememberAutoplaySelection(fallback);
        await playSingleTrack(fallback, preservePendingAdvance: true);
        advanced = true;
        unawaited(_ensureRadioFallbackTracks());
        return;
      }

      if (_canDiscoverRadioFallback) {
        // Never hold the shared advance lock while online discovery runs. A
        // cold-restored session may contain only the current track, and the
        // discovery round can take several seconds. Holding the lock here
        // used to drop previous/next taps and the natural-completion request.
        _deferAdvance(request);
        deferred = true;
        if (_player.processingState == ProcessingState.completed) {
          await _player.pause();
        }
        unawaited(_ensureRadioFallbackTracks());
      } else {
        _trace(
          'advance-unavailable direction=${forward ? 'next' : 'previous'} '
          'mode=${_mode.name} upcoming=${_upcomingMediaItems.length} '
          'fallback=${_fallbackPool.length} misses=$_consecutiveRadioRefillMisses',
        );
      }
    } catch (error, stack) {
      if (completion != null && !completion.isCompleted) {
        completion.completeError(error, stack);
      } else if (automatic) {
        // Completion and recovery run without a UI awaiting their Future.
        // A failed network lookup here used to rethrow into the root isolate.
        // Manual commands still propagate errors to their initiating control.
        developer.log(
          'automatic-advance-failed',
          name: 'MestingAudio',
          error: error,
          stackTrace: stack,
        );
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
            errorMessage: error is PlaybackContinuationException
                ? error.message
                : '下一首音源解析失败，请重新选择歌曲',
          ),
        );
      } else if (!_continueAfterExplicitQueue) {
        rethrow;
      } else {
        _trace('advance-failed error=$error');
      }
    } finally {
      _completionInFlight = false;
      if (!deferred && completion != null && !completion.isCompleted) {
        completion.complete();
      }
      // A failed/aborted source must not strand a newer deliberate tap.
      if (advanced || _pendingAdvanceRequest != null) _resumePendingAdvance();
    }
  }

  void _deferAdvance(_PendingAdvanceRequest request) {
    final pending = _pendingAdvanceRequest;
    // A deliberate previous/next tap takes precedence over an automatic
    // completion that happened while another source was being loaded.
    if (!request.automatic || pending == null) {
      if (pending?.completion != request.completion &&
          pending?.completion?.isCompleted == false) {
        pending!.completion!.complete();
      }
      _pendingAdvanceRequest = request;
    }
  }

  void _resumePendingAdvance() {
    if (_completionInFlight) return;
    final pending = _pendingAdvanceRequest;
    if (pending == null) return;
    // A pending Next waiting for the network is not runnable yet. Resuming it
    // synchronously here caused a recursive defer/resume loop on empty queues.
    if (pending.forward &&
        _upcomingMediaItems.isEmpty &&
        _fallbackTrack(avoidRecent: pending.automatic, forward: true) == null) {
      return;
    }
    _pendingAdvanceRequest = null;
    unawaited(
      _advancePlayback(
        forward: pending.forward,
        automatic: pending.automatic,
        bypassSingleRepeat: pending.bypassSingleRepeat,
        completion: pending.completion,
      ),
    );
  }

  void _cancelPendingAdvance() {
    final pending = _pendingAdvanceRequest;
    _pendingAdvanceRequest = null;
    if (pending?.completion?.isCompleted == false) {
      pending!.completion!.complete();
    }
  }

  Track? _fallbackTrack({required bool avoidRecent, required bool forward}) {
    // Beta's radio loader is installed for the whole app. Ordinary search and
    // library playback still need their own ordered context when Up Next is
    // empty; a radio-only fallback previously made both skip buttons no-ops.
    if (_preserveServerOrder &&
        _explicitPlaybackContext &&
        !_continueAfterExplicitQueue) {
      final context = _playbackContextTracks;
      if (context.isEmpty) return null;
      final current = context.indexWhere((t) => t.id == mediaItem.value?.id);
      if (context.length == 1) return null;
      if (_order.shuffle) {
        final candidates = context
            .where((t) => t.id != mediaItem.value?.id)
            .toList();
        return candidates.isEmpty
            ? null
            : candidates[_random.nextInt(candidates.length)];
      }
      final index = current < 0
          ? 0
          : (current + (forward ? 1 : -1)) % context.length;
      return context[index];
    }
    final pool = _fallbackPool;
    if (pool.isEmpty) return null;
    final currentId = mediaItem.value?.id;
    final currentTrack = currentId == null ? null : trackForId(currentId);
    final currentKey = currentTrack == null
        ? null
        : _semanticTrackKey(currentTrack);
    if (currentTrack != null) _rememberAutoplaySelection(currentTrack);
    final unplayedPool = pool
        .where(
          (track) =>
              _semanticTrackKey(track) != currentKey &&
              !_autoplaySessionTrackKeys.contains(_semanticTrackKey(track)),
        )
        .toList(growable: false);
    // Do not immediately recycle the first discovery batch. Give the online
    // loader several rotating query rounds to expand the session catalogue;
    // only fall back to an older song when those rounds found nothing new.
    if (unplayedPool.isEmpty &&
        _radioTrackLoader != null &&
        _consecutiveRadioRefillMisses < _radioRefillAttemptLimit) {
      return null;
    }
    if (_preserveServerOrder) {
      // Platform batches already carry recommendation order. Never shuffle or
      // mix in history/library tracks after the explicit queue is exhausted.
      return unplayedPool.firstOrNull;
    }
    final candidates = unplayedPool.isEmpty ? pool : unplayedPool;
    final recentIds = _playbackHistory.reversed
        .take(_recentFallbackWindow)
        .map((track) => track.id);
    final index = QueueEngine.resolveFallbackIndex(
      candidateIds: candidates.map((track) => track.id).toList(growable: false),
      recentIds: recentIds,
      currentId: currentId,
      avoidRecent: avoidRecent,
      mode: _order.shuffle ? PlaybackMode.random : PlaybackMode.list,
      forward: forward,
      // Reaching this branch means the explicit Up Next queue is empty.
      // Treat that state as Autoplay even when the visible mode is list:
      // hidden page context and a stable hot-ranking snapshot must not create
      // a deterministic sequence that always starts with the same song.
      randomize: true,
      random: _random,
    );
    return index < 0 ? null : candidates[index];
  }

  List<Track> get _fallbackPool {
    if (_preserveServerOrder) return _radioFallbackTracks;
    final result = <Track>[];
    final seen = <String>{};
    final candidates = _order.shuffle
        ? <Track>[
            ..._radioFallbackTracks,
            ..._onlineFallbackTracks,
            ..._playbackContextTracks,
            ..._knownTracks.values,
            ..._libraryTracks,
          ]
        : <Track>[
            ..._playbackContextTracks,
            ..._onlineFallbackTracks,
            ..._radioFallbackTracks,
            ..._knownTracks.values,
            ..._libraryTracks,
          ];
    for (final track in candidates) {
      if (track.isPlayable && seen.add(_semanticTrackKey(track))) {
        result.add(track);
      }
    }
    return result;
  }

  void _replacePlaybackContext(Iterable<Track> tracks) {
    final next = <Track>[];
    final seen = <String>{};
    for (final track in tracks) {
      if (!track.isPlayable || !seen.add(track.id)) continue;
      next.add(track);
      _knownTracks[track.id] = track;
    }
    _playbackContextTracks = List<Track>.unmodifiable(next);
    _trace('playback-context tracks=${next.length}');
  }

  void updateOnlineFallbackTracks(Iterable<Track> tracks) {
    final next = <Track>[];
    final seen = <String>{};
    for (final track in tracks) {
      if (!track.isRemote || !track.isPlayable || !seen.add(track.id)) continue;
      next.add(track);
      _knownTracks[track.id] = track;
    }
    _onlineFallbackTracks = List<Track>.unmodifiable(next);
    if (next.isNotEmpty) _resumePendingAdvance();
  }

  void configureRadioTrackLoader(
    RadioTrackLoader loader, {
    bool preserveServerOrder = false,
    void Function()? onExplicitPlayback,
    bool continueAfterExplicitQueue = false,
  }) {
    _continueAfterExplicitQueue = continueAfterExplicitQueue;
    _preserveServerOrder = preserveServerOrder;
    _onExplicitPlayback = onExplicitPlayback;
    _radioTrackLoader = loader;
    unawaited(_ensureRadioFallbackTracks());
  }

  Future<void> prefetchRadioTracks({bool force = false}) =>
      _ensureRadioFallbackTracks(force: force);

  Future<void> refreshRadioRecommendations() async {
    invalidateRadioRecommendations();
    await _ensureRadioFallbackTracks(force: true);
  }

  void invalidateRadioRecommendations() {
    _radioFallbackTracks = const <Track>[];
    _consecutiveRadioRefillMisses = 0;
    _radioRecommendationGeneration += 1;
  }

  Future<void> _ensureRadioFallbackTracks({bool force = false}) async {
    if (_continueAfterExplicitQueue && mediaItem.value == null) return;
    final loader = _radioTrackLoader;
    if (loader == null) return;
    final threshold = _preserveServerOrder ? 4 : _radioPrefetchThreshold;
    if (!force && _availableRadioTrackCount >= threshold) return;
    final active = _radioLoadInFlight;
    if (active != null) return active;

    final generation = _radioRecommendationGeneration;
    late final Future<void> request;
    request = () async {
      try {
        var attempts = 0;
        while (attempts < _radioRefillAttemptLimit &&
            _availableRadioTrackCount < threshold) {
          attempts += 1;
          final excluded = <String>{
            ..._autoplaySessionTrackKeys,
            for (final track in _radioFallbackTracks) _semanticTrackKey(track),
          };
          final currentId = mediaItem.value?.id;
          final currentTrack = currentId == null ? null : trackForId(currentId);
          if (currentTrack != null) {
            excluded.add(_semanticTrackKey(currentTrack));
          }
          final tracks = await loader(Set<String>.unmodifiable(excluded));
          if (generation != _radioRecommendationGeneration) {
            _trace('radio-refill-stale generation=$generation');
            break;
          }
          final added = _preserveServerOrder
              ? await _appendRecommendationBatch(tracks, generation)
              : _mergeRadioFallbackTracks(tracks);
          if (added == 0) {
            _consecutiveRadioRefillMisses += 1;
          } else {
            _consecutiveRadioRefillMisses = 0;
          }
        }
      } on Object catch (error) {
        _trace('radio-refill-failed error=$error');
      } finally {
        if (identical(_radioLoadInFlight, request)) {
          _radioLoadInFlight = null;
        }
        if (generation != _radioRecommendationGeneration &&
            (_pendingAdvanceRequest != null || _continueAfterExplicitQueue)) {
          unawaited(_ensureRadioFallbackTracks(force: true));
        }
        final pending = _pendingAdvanceRequest;
        if (pending != null) {
          final fallback = _fallbackTrack(
            avoidRecent: pending.automatic || _order.shuffle,
            forward: pending.forward,
          );
          if (fallback == null && _upcomingMediaItems.isEmpty) {
            _pendingAdvanceRequest = null;
            if (pending.completion?.isCompleted == false) {
              pending.completion!.completeError(
                const PlaybackContinuationException('暂未获取到可播放的推荐歌曲，请稍后重试'),
              );
            }
            _trace(
              'radio-refill-exhausted direction='
              '${pending.forward ? 'next' : 'previous'} '
              'mode=${_mode.name} misses=$_consecutiveRadioRefillMisses',
            );
          } else {
            _resumePendingAdvance();
          }
        }
      }
    }();
    _radioLoadInFlight = request;
    return request;
  }

  /// Upstream FM/discover prefetch becomes the actual visible upcoming queue,
  /// preserving server order, rather than a hidden randomized fallback pool.
  Future<int> _appendRecommendationBatch(
    List<Track> tracks,
    int generation,
  ) async {
    final ids = {
      mediaItem.value?.id,
      ..._upcomingMediaItems.map((item) => item.id),
    };
    final fresh = tracks
        .where((track) => track.isPlayable && ids.add(track.id))
        .toList();
    final items = await Future.wait(fresh.map(_mediaItemFor));
    if (generation != _radioRecommendationGeneration) return 0;
    for (final track in fresh) {
      _knownTracks[track.id] = track;
      _recommendedUpcomingIds.add(track.id);
    }
    _tracks = [..._tracks, ...fresh];
    queue.add([...queue.value, ...items]);
    _upcomingMediaItems = [..._upcomingMediaItems, ...items];
    _publishUpcomingQueue();
    _resumePendingAdvance();
    return fresh.length;
  }

  int get _availableRadioTrackCount => _preserveServerOrder
      ? _upcomingMediaItems.length
      : _radioFallbackTracks
            .where(
              (track) =>
                  !_autoplaySessionTrackKeys.contains(
                    _semanticTrackKey(track),
                  ) &&
                  track.id != mediaItem.value?.id,
            )
            .length;

  bool get _canDiscoverRadioFallback =>
      _radioTrackLoader != null &&
      mediaItem.value != null &&
      (_continueAfterExplicitQueue ||
          !(_preserveServerOrder && _explicitPlaybackContext));

  int _mergeRadioFallbackTracks(Iterable<Track> tracks) {
    final next = <Track>[];
    final seen = <String>{};
    final previous = <String>{
      for (final track in _radioFallbackTracks) _semanticTrackKey(track),
    };
    var added = 0;
    for (final track in <Track>[..._radioFallbackTracks, ...tracks]) {
      final key = _semanticTrackKey(track);
      if (!track.isRemote ||
          !track.isPlayable ||
          _autoplaySessionTrackKeys.contains(key) ||
          !seen.add(key)) {
        continue;
      }
      next.add(track);
      if (!previous.contains(key)) added += 1;
      _knownTracks[track.id] = track;
    }
    if (next.length > _maximumRadioPoolSize) {
      next.removeRange(0, next.length - _maximumRadioPoolSize);
    }
    _radioFallbackTracks = List<Track>.unmodifiable(next);
    _trace(
      'radio-refill pool=${next.length} added=$added '
      'available=$_availableRadioTrackCount misses=$_consecutiveRadioRefillMisses',
    );
    if (next.isNotEmpty) _resumePendingAdvance();
    return added;
  }

  void _rememberAutoplaySelection(Track track) {
    final key = _semanticTrackKey(track);
    // Keep semantic keys for the full process session. This set contains only
    // short normalized title/artist strings, while the much heavier Track
    // objects remain bounded by the rolling radio pool. Evicting these keys
    // used to make a long-running Autoplay session repeat after a fixed count.
    _autoplaySessionTrackKeys.add(key);
  }

  String _semanticTrackKey(Track track) {
    if (_preserveServerOrder) return track.id;
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^]]*\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
    return '${normalize(track.title)}|${normalize(track.artist)}';
  }

  Future<void> playTrack(String id) async {
    await _ready;
    final track = trackForId(id);
    if (track == null || id == mediaItem.value?.id) return;
    await playSingleTrack(track);
  }

  Future<void> playSingleTrack(
    Track track, {
    bool autoplay = true,
    bool Function()? isCurrent,
    bool fromHistory = false,
    Iterable<Track>? playbackContext,
    bool preservePendingAdvance = false,
    Track? returnToUpcoming,
    bool replaceUpcoming = false,
    bool discardRecommendations = false,
  }) async {
    if (isCurrent != null && !isCurrent()) return;
    _markUserCommand('playSingleTrack');
    if (!preservePendingAdvance) _transportIntentEpoch++;
    final transportEpoch = _transportIntentEpoch;
    if (!preservePendingAdvance) _cancelPendingAdvance();
    if (!preservePendingAdvance) _consecutiveLoadFailures = 0;
    if (_order.shuffle) _rememberAutoplaySelection(track);
    if (playbackContext != null) {
      _onExplicitPlayback?.call();
      _explicitPlaybackContext = true;
      _replacePlaybackContext(playbackContext);
    }
    _knownTracks[track.id] = track;
    await _ready;
    await _pauseFadeController.cancel();
    await _cancelTransition();
    if (isCurrent?.call() == false) return;
    // Returning the current recording to the head makes Previous then Next
    // reversible without mutating the live queue before source resolution.
    final pending = <Track>[
      if (returnToUpcoming != null && returnToUpcoming.id != track.id)
        returnToUpcoming,
    ];
    for (final item in _upcomingMediaItems) {
      if (replaceUpcoming ||
          (discardRecommendations &&
              _recommendedUpcomingIds.contains(item.id))) {
        continue;
      }
      final candidate = trackForId(item.id);
      if (candidate != null &&
          candidate.id != track.id &&
          candidate.id != returnToUpcoming?.id) {
        pending.add(candidate);
      }
    }
    _historyNavigation = fromHistory;
    final applied = await _loadQueue(
      <Track>[track, ...pending],
      requiredTransportIntentEpoch: transportEpoch,
      ownerCurrent: isCurrent,
      allowFailureRecovery: autoplay,
    );
    if (!applied) {
      _historyNavigation = false;
      return;
    }
    await _applyPlaybackOrder();
    if (transportEpoch != _transportIntentEpoch || isCurrent?.call() == false) {
      return;
    }
    if (autoplay) _startPlayer();
    if (_continueAfterExplicitQueue) unawaited(_ensureRadioFallbackTracks());
  }

  Future<bool> appendToUpcomingQueue(Track track) async {
    _markUserCommand('appendUpcoming');
    await _ready;
    final canAppend = QueueEngine.canAppendTrack(
      candidateId: track.id,
      currentId: mediaItem.value?.id,
      upcomingIds: _upcomingMediaItems.map((item) => item.id),
    );
    if (!canAppend) {
      if (_recommendedUpcomingIds.remove(track.id)) _publishUpcomingQueue();
      return false;
    }
    _recommendedUpcomingIds.remove(track.id);

    _knownTracks[track.id] = track;
    final item = await _mediaItemFor(track);
    // Consumption de-duplicates the current queue into a fixed-length list.
    // Rebuild here instead of mutating it so adding from any UI remains valid
    // after the current track has played for more than one second.
    _tracks = <Track>[..._tracks, track];
    queue.add(<MediaItem>[...queue.value, item]);
    _upcomingMediaItems = <MediaItem>[..._upcomingMediaItems, item];
    _publishUpcomingQueue();
    _broadcastState(_player.playbackEvent);
    _trace(
      'append-upcoming id=${track.id} upcoming=${_upcomingMediaItems.length} '
      'sourceCount=${_player.sequence.length}',
    );
    _resumePendingAdvance();
    return true;
  }

  /// Queue next without replacing the playing recording, transport, progress
  /// or the remaining manual queue. Rebase by identity after asynchronous
  /// artwork resolution: playback may have advanced while appending.
  Future<bool> playNextInQueue(Track track) async {
    await appendToUpcomingQueue(track);
    final index = _upcomingMediaItems.indexWhere((item) => item.id == track.id);
    if (index < 0 || mediaItem.value?.id == track.id) return false;
    await reorderUpcoming(index, 0);
    _explicitNextId = track.id;
    return true;
  }

  Future<bool> removeFromUpcomingQueue(String id) async {
    _markUserCommand('removeUpcoming');
    await _ready;
    final pendingIndex = _upcomingMediaItems.indexWhere(
      (item) => item.id == id,
    );
    if (pendingIndex < 0 || id == mediaItem.value?.id) return false;

    _tracks = _tracks.where((track) => track.id != id).toList();
    queue.add(queue.value.where((item) => item.id != id).toList());
    _upcomingMediaItems = _upcomingMediaItems
        .where((item) => item.id != id)
        .toList(growable: false);
    if (_explicitNextId == id) _explicitNextId = null;
    _publishUpcomingQueue();
    _broadcastState(_player.playbackEvent);
    _trace(
      'remove-upcoming id=$id upcoming=${_upcomingMediaItems.length} '
      'sourceCount=${_player.sequence.length}',
    );
    return true;
  }

  /// Applies a remote "一起听" snapshot without marking it as a local user
  /// command. The current track must be the first item in [tracks].
  Future<void> applySynchronizedPlayback({
    required List<Track> tracks,
    required Duration position,
    required bool playing,
  }) async {
    if (tracks.isEmpty) return;
    _pendingAdvanceRequest = null;
    _replacePlaybackContext(tracks);
    await _ready;
    await _pauseFadeController.cancel();
    await _cancelTransition();
    final current = tracks.first;
    final safePosition = Duration(
      milliseconds: position.inMilliseconds.clamp(
        0,
        current.duration.inMilliseconds,
      ),
    );
    final applied = await _loadQueue(
      List<Track>.unmodifiable(tracks),
      initialPosition: safePosition,
    );
    if (!applied) return;
    await _applyPlaybackOrder();
    if (playing) {
      _startPlayer();
    } else {
      await _player.pause();
    }
    _trace(
      'together-snapshot id=${current.id} positionMs='
      '${safePosition.inMilliseconds} playing=$playing '
      'queue=${tracks.length}',
    );
  }

  Future<void> togglePlayPause() async {
    await _ready;
    if (_pauseFadeController.isFading) {
      _markUserCommand('cancelPauseFade');
      await _pauseFadeController.cancel();
      await _cancelTransition();
      return;
    }
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> cyclePlaybackMode() => setPlaybackMode(_mode.next);

  Future<void> replaceQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoplay = true,
    bool recommendationContext = false,
    bool Function()? togetherGuard,
  }) async {
    if (togetherGuard?.call() == false) return;
    _explicitNextId = null;
    if (!recommendationContext) _onExplicitPlayback?.call();
    _recommendedUpcomingIds
      ..clear()
      ..addAll(
        recommendationContext
            ? tracks.map((track) => track.id)
            : const <String>[],
      );
    _explicitPlaybackContext = !recommendationContext;
    _markUserCommand('replaceQueue', together: togetherGuard != null);
    final togetherRevision = transportRevision;
    final transportEpoch = _transportIntentEpoch;
    _consecutiveLoadFailures = 0;
    if (tracks.isNotEmpty) {
      _replacePlaybackContext(tracks);
    }
    await _ready;
    if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    await _pauseFadeController.cancel();
    await _cancelTransition();
    if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    final applied = await _loadQueue(
      tracks,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      requiredTransportIntentEpoch: transportEpoch,
      allowFailureRecovery: autoplay && togetherGuard == null,
    );
    if (!applied || !_togetherCurrent(togetherGuard, togetherRevision)) return;
    if (_order.shuffle) {
      // A newly selected album keeps the tapped recording active and shuffles
      // only its new pending recordings, without losing their original order.
      _unshuffledUpcomingIds = _upcomingMediaItems
          .map((item) => item.id)
          .toList();
      _upcomingMediaItems = [..._upcomingMediaItems]..shuffle(_random);
      _publishUpcomingQueue();
    }
    await _applyPlaybackOrder();
    if (!_togetherCurrent(togetherGuard, togetherRevision)) return;
    if (autoplay && tracks.isNotEmpty) _startPlayer();
  }

  /// Restores a persisted queue only if no newer user command has arrived.
  Future<void> restoreSession({
    required List<Track> tracks,
    required int currentIndex,
    required Duration position,
    required PlaybackMode mode,
    PlaybackOrder? order,
    bool deferSource = false,
  }) async {
    _explicitPlaybackContext = true;
    final restoreEpoch = _userCommandEpoch;
    if (tracks.isNotEmpty) {
      _replacePlaybackContext(tracks);
    }
    await _ready;
    if (tracks.isEmpty || restoreEpoch != _userCommandEpoch) return;
    final applied = await _loadQueue(
      tracks,
      initialIndex: currentIndex,
      initialPosition: position,
      preload: false,
      deferSource:
          deferSource ||
          tracks[currentIndex.clamp(0, tracks.length - 1)].source ==
              TrackSource.qishui,
      requiredUserCommandEpoch: restoreEpoch,
    );
    if (applied) {
      _order = order ?? PlaybackOrder.fromLegacy(mode);
      await _applyPlaybackOrder();
      _trace('restore-applied id=${mediaItem.value?.id}');
    } else {
      _trace('restore-skipped-after-user-command');
    }
  }

  Future<void> clearSession() async {
    _explicitPlaybackContext = false;
    _markUserCommand('clearSession');
    _pendingAdvanceRequest = null;
    _replacePlaybackContext(const <Track>[]);
    _playbackHistory.clear();
    _recommendedUpcomingIds.clear();
    _autoplaySessionTrackKeys.clear();
    invalidateRadioRecommendations();
    await _ready;
    await _pauseFadeController.cancel();
    await _cancelTransition();
    await _player.stop();
    await _loadQueue(const <Track>[]);
    await setPlaybackMode(PlaybackMode.sequential);
    _trace('session-cleared');
  }

  Track? trackForId(String id) {
    return _knownTracks[id];
  }

  Future<void> setPlaybackMode(PlaybackMode mode) async {
    final next = PlaybackOrder.fromLegacy(mode);
    // One app mode owns the visible order; retire the old hidden random picker.
    await setRandomUpcoming(false);
    _changeShuffleOrder(next.shuffle);
    _order = next;
    await _applyPlaybackOrder();
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _changeShuffleOrder(enabled);
    _order = _order.copyWith(shuffle: enabled);
    await _applyPlaybackOrder();
  }

  /// Reordering touches logical pending items only: no active source reload.
  /// Switching shuffle off restores the prior ordering of remaining songs.
  void _changeShuffleOrder(bool enabled) {
    if (enabled == _order.shuffle) return;
    final next = [..._upcomingMediaItems];
    if (enabled) {
      _unshuffledUpcomingIds = next.map((item) => item.id).toList();
      next.shuffle(_random);
      if (next.length > 1 &&
          next.asMap().entries.every(
            (entry) => entry.value.id == _unshuffledUpcomingIds[entry.key],
          )) {
        next.add(next.removeAt(0));
      }
    } else {
      final rank = {
        for (var i = 0; i < _unshuffledUpcomingIds.length; i++)
          _unshuffledUpcomingIds[i]: i,
      };
      final added = {
        for (var i = 0; i < next.length; i++) next[i].id: i + rank.length,
      };
      next.sort(
        (a, b) =>
            (rank[a.id] ?? added[a.id]!).compareTo(rank[b.id] ?? added[b.id]!),
      );
      _unshuffledUpcomingIds = const [];
    }
    _upcomingMediaItems = next;
    _publishUpcomingQueue();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _order = _order.copyWith(
      repeat: switch (repeatMode) {
        AudioServiceRepeatMode.none => PlaybackRepeat.off,
        AudioServiceRepeatMode.one => PlaybackRepeat.one,
        _ => PlaybackRepeat.all,
      },
    );
    await _applyPlaybackOrder();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setShuffleEnabled(shuffleMode != AudioServiceShuffleMode.none);

  Future<void> cycleRepeat() async {
    _order = _order.copyWith(
      repeat: PlaybackRepeat
          .values[(_order.repeat.index + 1) % PlaybackRepeat.values.length],
    );
    await _applyPlaybackOrder();
  }

  /// Logical Up Next owns ordering. ExoPlayer shuffle stays disabled so manual
  /// queue edits, consumed tracks and persisted snapshots share one authority.
  Future<void> _applyPlaybackOrder() async {
    await _readyIfAvailable();
    await _player.setShuffleModeEnabled(false);
    await _player.setLoopMode(
      _order.repeat == PlaybackRepeat.one &&
              sleepTimer.mode != MusicSleepMode.endOfTrack
          ? LoopMode.one
          : LoopMode.off,
    );
    if (_order.shuffle) {
      final current = trackForId(mediaItem.value?.id ?? '');
      if (current != null) _rememberAutoplaySelection(current);
      unawaited(_ensureRadioFallbackTracks());
    }
    _modeController.add(_mode);
    _orderController.add(_order);
    _broadcastState(_player.playbackEvent);
  }

  /// Reorders only pending recordings; the playing source and position remain
  /// intact. Queue listeners also persist this authoritative order.
  Future<void> reorderUpcoming(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _upcomingMediaItems.length) return;
    final next = [..._upcomingMediaItems];
    if (newIndex > oldIndex) newIndex--;
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    _markUserCommand('reorderQueue');
    _upcomingMediaItems = next;
    _publishUpcomingQueue();
  }

  Future<void> _readyIfAvailable() async {
    // During initialisation setPlaybackMode is called from inside _ready itself.
    // At that point the player already has its sources and can be configured
    // directly; later calls await the same completed future in their caller.
  }

  void _markUserCommand(String command, {bool together = false}) {
    // Immediate invalidation prevents a late envelope from reversing a tap.
    _transition.invalidate();
    unawaited(_cancelTransition().catchError((Object _) {}));
    if (command != 'skipNext' &&
        command != 'playSingleTrack' &&
        command != 'appendUpcoming') {
      _invalidatePreparation();
    }
    if (command == 'seek') {
      unawaited(
        _player
            .configureMusicLoudness(
              key: '',
              enabled: _playbackPreferences.balance,
              durationMs: 0,
              invalidate: true,
            )
            .catchError((Object _) {}),
      );
    }
    if (command != 'pause') _sleepStoppedAtCompletion = false;
    if (const {
      'play',
      'pause',
      'stop',
      'seek',
      'skipToQueueItem',
      'replaceQueue',
      'clearSession',
      'changeQuality',
      'cancelPauseFade',
    }.contains(command)) {
      _transportIntentEpoch++;
      _pendingQueueEpoch = null;
    }
    if (command != 'skipNext' &&
        command != 'skipPrevious' &&
        command != 'playSingleTrack') {
      _cancelPendingAdvance();
    }
    _userCommandEpoch += 1;
    if (!_userCommandController.isClosed) {
      _userCommandController.add(command);
    }
    if (!together && !_togetherUserCommandController.isClosed) {
      _togetherUserCommandController.add(command);
    }
    _trace('user-command=$command epoch=$_userCommandEpoch');
  }

  void _trace(String message) {
    developer.log(message, name: 'MestingAudio');
  }
}

class _PendingAdvanceRequest {
  const _PendingAdvanceRequest({
    required this.forward,
    required this.automatic,
    required this.bypassSingleRepeat,
    this.completion,
  });

  final bool forward;
  final bool automatic;
  final bool bypassSingleRepeat;
  final Completer<void>? completion;
}

class PlaybackContinuationException implements Exception {
  const PlaybackContinuationException(this.message);
  final String message;
  @override
  String toString() => message;
}
