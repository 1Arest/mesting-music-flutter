import 'dart:async';
import '../performance/track_snapshots.dart';
import 'package:audio_service/audio_service.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/track.dart';
import '../../features/library/data/retired_bundled_tracks.dart';
import '../audio/mesting_audio_handler.dart';
import '../audio/playback_mode.dart';
import '../audio/actual_listening_counter.dart';
import '../database/app_database.dart';

final playbackPersistenceControllerProvider =
    Provider<PlaybackPersistenceController>((ref) {
      throw StateError('PlaybackPersistenceController must be overridden.');
    });

/// Bridges the live audio engine with durable, account-scoped playback data.
///
/// It intentionally records only small snapshots and listening deltas. The
/// handler remains the sole owner of actual audio sources, avoiding persistence
/// work that could interrupt a playing track.
class PlaybackPersistenceController with WidgetsBindingObserver {
  static const _playbackCloudSyncInterval = Duration(minutes: 10);

  PlaybackPersistenceController({
    required AppDatabase database,
    required MestingAudioHandler audioHandler,
    ListeningClock? listeningClock,
  }) : _database = database,
       _audioHandler = audioHandler,
       _listeningClock = listeningClock ?? MonotonicListeningClock();

  final AppDatabase _database;
  final MestingAudioHandler _audioHandler;
  final ListeningClock _listeningClock;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  Timer? _saveTimer;
  Timer? _librarySyncTimer;
  String? _sampledTrackId;
  ActualListeningCounter? _listeningCounter;
  int _sampledHeardMs = 0;
  bool _saving = false;
  bool _started = false;
  bool _switchingOwner = false;
  String? _ownerId;
  // Account activation can be requested repeatedly during restore, login and
  // logout. Serializing it prevents an older async restore from overwriting
  // the session selected by a newer account switch.
  Future<void> _ownerSwitch = Future<void>.value();
  Future<bool> Function(String ownerId)? _librarySynchronizer;

  void configureLibrarySynchronizer(
    Future<bool> Function(String ownerId) synchronizer,
  ) {
    _librarySynchronizer = synchronizer;
  }

  /// Selects the active account and restores only that account's playback.
  ///
  /// Empty identifiers intentionally map to the legacy local-library owner so
  /// pre-login playback remains separate from authenticated accounts.
  Future<void> activateOwner(String ownerId) {
    final normalizedOwnerId = ownerId.trim().isEmpty
        ? legacyLibraryOwnerId
        : ownerId.trim();
    final operation = _ownerSwitch.then(
      (_) => _activateOwner(normalizedOwnerId),
    );
    _ownerSwitch = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  /// Called before credentials change. Keep the departing owner's queue and
  /// position; the ordinary owner binding restores the destination only after
  /// its credentials are published. Both directions always remain paused.
  Future<void> preparePlatformSwitch(String nextOwnerId) async {
    await _ownerSwitch;
    await _audioHandler.pause();
    await saveNow();
  }

  Future<void> _activateOwner(String ownerId) async {
    if (_ownerId == ownerId) return;
    _switchingOwner = true;
    final previousOwnerId = _ownerId;
    try {
      if (previousOwnerId != null) {
        await _sampleListeningProgress(ownerId: previousOwnerId);
        await _saveSnapshot(previousOwnerId);
      }
      _ownerId = ownerId;
      _sampledTrackId = null;
      _listeningCounter = null;
      _sampledHeardMs = 0;
      final session = await _database.loadPlaybackSession(ownerId);
      if (session == null) {
        await _audioHandler.clearSession();
        return;
      }
      final restoredTracks = await decodeTrackQueue(session.queueSnapshot);
      final currentId = restoredTracks.isEmpty
          ? null
          : restoredTracks[session.currentIndex.clamp(
                  0,
                  restoredTracks.length - 1,
                )]
                .id;
      final tracks = restoredTracks
          .where((track) => !isRetiredBundledTrackId(track.id))
          .toList(growable: false);
      final restoredIndex = currentId == null
          ? 0
          : tracks.indexWhere((track) => track.id == currentId);
      final order = PlaybackOrder.parse(session.playbackMode);
      if (tracks.isEmpty) {
        await _audioHandler.clearSession();
        return;
      }
      await _audioHandler.restoreSession(
        tracks: tracks,
        currentIndex: restoredIndex < 0 ? 0 : restoredIndex,
        position: restoredIndex < 0
            ? Duration.zero
            : Duration(milliseconds: session.positionMs),
        mode: order.legacy,
        order: order,
      );
    } on Object {
      // A damaged or obsolete snapshot must neither stop startup nor leak the
      // previous account's current track into the newly active account.
      await _audioHandler.clearSession();
    } finally {
      _switchingOwner = false;
      _resetMeasurement();
    }
  }

  /// Starts the single set of audio/lifecycle listeners for this app process.
  void start() {
    if (_started) return;
    _started = true;
    _resetMeasurement();
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(
      _audioHandler.mediaItem.listen((item) async {
        final id = item?.id;
        if (!_switchingOwner && id != _sampledTrackId) {
          final owner = _ownerId;
          // Metadata already names the next song. Settle the old counter
          // against its retained ID before selecting a new decoder interval.
          if (owner != null) {
            unawaited(_sampleListeningProgress(ownerId: owner));
          }
          _sampledTrackId = id;
          _sampledHeardMs = 0;
          _listeningCounter = id == null
              ? null
              : ActualListeningCounter(_listeningClock);
        }
        await saveNow();
      }),
    );
    _subscriptions.add(
      _audioHandler.consumedTrackStream.listen((track) async {
        final ownerId = _ownerId;
        if (ownerId == null || _switchingOwner) return;
        await _database.recordPlayback(ownerId, track, Duration.zero);
        _synchronizeLibrary(ownerId);
      }),
    );
    _subscriptions.add(
      _audioHandler.completedTrackStream.listen((track) async {
        final ownerId = _ownerId;
        if (ownerId == null || _switchingOwner) return;
        await _sampleListeningProgress(ownerId: ownerId);
        await _database.recordCompletedPlayback(ownerId, track);
        _synchronizeLibrary(ownerId);
      }),
    );
    _subscriptions.add(
      _audioHandler.playbackOrderStream.listen((_) => saveNow()),
    );
    _subscriptions.add(
      _audioHandler.playbackState.listen((state) {
        if (!_switchingOwner) {
          _listeningCounter?.update(
            playing: state.playing,
            ready: state.processingState == AudioProcessingState.ready,
            speed: state.speed,
            seeking: _audioHandler.isSeeking,
          );
        }
        if (!state.playing) {
          final ownerId = _ownerId;
          if (ownerId != null && !_switchingOwner) {
            _sampleListeningProgress(ownerId: ownerId);
          }
          saveNow();
        }
      }),
    );
    _subscriptions.add(
      _audioHandler.seekingStream.listen((seeking) {
        if (!_switchingOwner) _listeningCounter?.update(seeking: seeking);
      }),
    );
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final ownerId = _ownerId;
      if (ownerId != null && !_switchingOwner) {
        await _sampleListeningProgress(ownerId: ownerId);
      }
      await saveNow();
    });
  }

  Future<void> _sampleListeningProgress({required String ownerId}) async {
    final currentId = _sampledTrackId;
    final counter = _listeningCounter;
    if (currentId == null || counter == null) return;
    final heard = counter.sample();
    final deltaMs = heard - _sampledHeardMs;
    _sampledHeardMs = heard;
    if (deltaMs <= 0) return;
    await _database.addPlaybackDuration(
      ownerId,
      currentId,
      Duration(milliseconds: deltaMs),
    );
    _synchronizeLibrary(ownerId);
  }

  void _resetMeasurement() {
    final item = _audioHandler.mediaItem.value;
    _sampledTrackId = item?.id;
    _sampledHeardMs = 0;
    final state = _audioHandler.playbackState.value;
    _listeningCounter = item == null
        ? null
        : (ActualListeningCounter(_listeningClock)..update(
            playing: state.playing,
            ready: state.processingState == AudioProcessingState.ready,
            speed: state.speed,
            seeking: _audioHandler.isSeeking,
          ));
  }

  void _synchronizeLibrary(String ownerId) {
    final synchronizer = _librarySynchronizer;
    if (synchronizer == null) return;
    // Coalesce frequent play-history writes. They stay durable locally, while
    // the optional cloud synchronizer runs at most once per interval.
    _librarySyncTimer ??= Timer(_playbackCloudSyncInterval, () {
      _librarySyncTimer = null;
      final currentOwnerId = _ownerId;
      if (currentOwnerId != null) unawaited(synchronizer(currentOwnerId));
    });
  }

  /// Persists the current queue without allowing concurrent snapshot writes.
  ///
  /// During an owner transition the previous owner is saved explicitly before
  /// the new owner loads, so this method never writes a mixed-account queue.
  Future<void> saveNow() async {
    final ownerId = _ownerId;
    final persistedQueue = _audioHandler.persistedQueue;
    if (_saving ||
        _switchingOwner ||
        ownerId == null ||
        persistedQueue.isEmpty) {
      return;
    }
    _saving = true;
    try {
      await _saveSnapshot(ownerId, queue: persistedQueue);
    } finally {
      _saving = false;
    }
  }

  Future<void> _saveSnapshot(String ownerId, {List<Track>? queue}) async {
    final persistedQueue = queue ?? _audioHandler.persistedQueue;
    if (persistedQueue.isEmpty) return;
    final position = _audioHandler.currentPosition;
    final playbackMode = _audioHandler.playbackOrder.serialized;
    await _database.savePlaybackSession(
      ownerId: ownerId,
      queue: persistedQueue,
      currentIndex: 0,
      position: position,
      playbackMode: playbackMode,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      saveNow();
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _librarySyncTimer?.cancel();
    final ownerId = _ownerId;
    if (ownerId != null) {
      await _sampleListeningProgress(ownerId: ownerId);
    }
    await saveNow();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
