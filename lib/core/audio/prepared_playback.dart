part of 'mesting_audio_handler.dart';

/// Private adapter between the logical queue and the isolated transition state.
/// Preparation cannot emit a media item, consume a queue row or record listening.
extension _PreparedPlayback on MestingAudioHandler {
  void _setPlaybackPreferences(PlaybackPreferences value) {
    if (_playbackPreferences.toJson().toString() == value.toJson().toString()) {
      return;
    }
    _playbackPreferences = value;
    _invalidatePreparation();
    unawaited(_cancelTransition().catchError((Object _) {}));
    final current = trackForId(_loadedTrackId ?? '');
    if (current != null) unawaited(_configureLoudness(_player, current));
  }

  void _setSynchronizedPlayback(bool Function() active) =>
      _synchronizedPlayback = active;
  bool get _transitionBlocked =>
      (_synchronizedPlayback?.call() ?? false) ||
      _order.repeat == PlaybackRepeat.one ||
      sleepTimer.mode != MusicSleepMode.off;

  String _loudnessKey(Track t) =>
      '${t.source.name}:${t.id}:${t.playbackQuality}:${t.audioBitrate}:${t.duration.inMilliseconds}';
  Future<void> _configureLoudness(AudioPlayer player, Track track) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await player.configureMusicLoudness(
        key: _loudnessKey(track),
        enabled: _playbackPreferences.balance,
        durationMs: track.duration.inMilliseconds,
      );
    } catch (_) {
      /* An unsupported effect must never interrupt ordinary audio. */
    }
  }

  Track? _nextCandidate() {
    if (_transitionBlocked) return null;
    final manual = manuallyQueuedItems;
    final candidates = _continueAfterExplicitQueue && manual.isNotEmpty
        ? manual
        : _upcomingMediaItems;
    if (candidates.isEmpty) return null;
    final forced = candidates.where((t) => t.id == _explicitNextId).firstOrNull;
    final reserved = candidates
        .where((t) => t.id == _transition.ready?.track.id)
        .firstOrNull;
    final item =
        forced ??
        reserved ??
        candidates[_randomUpcoming ? _random.nextInt(candidates.length) : 0];
    return item.id == mediaItem.value?.id ? null : trackForId(item.id);
  }

  String _nextQueueKey() {
    // Queue order plus exact quality is the validity boundary for preparation.
    // Random mode reserves one prepared candidate; it never rolls again at EOS.
    return '${mediaItem.value?.id}|${_order.repeat}|$_randomUpcoming|$_explicitNextId|${_upcomingMediaItems.map((t) => '${t.id}:${t.extras?['playbackQuality']}').join(',')}';
  }

  void _invalidatePreparation() {
    _transition.invalidate();
    if (_transition.crossing) {
      unawaited(_cancelTransition().catchError((Object _) {}));
    }
    unawaited(_transition.clearPreparation().catchError((Object _) {}));
  }

  AudioPlayer _newPreparedPlayer() =>
      _preparedPlayerFactory?.call() ??
      AudioPlayer(
        useProxyForRequestHeaders: false,
        androidAudioOutputOwner: DistributionChannel.isBeta
            ? 'mesting-prepared'
            : null,
        audioLoadConfiguration: const AudioLoadConfiguration(
          androidLoadControl: AndroidLoadControl(
            minBufferDuration: Duration(seconds: 4),
            maxBufferDuration: Duration(seconds: 8),
            bufferForPlaybackDuration: Duration(milliseconds: 500),
            bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
            targetBufferBytes: 2 * 1024 * 1024,
          ),
        ),
      );
  Future<void> _prepareNext(Track candidate, String key) async {
    _transition.attemptedKey = key;
    final epoch = _transition.epoch;
    AudioPlayer? decoder;
    bool valid() =>
        epoch == _transition.epoch &&
        key == _nextQueueKey() &&
        !_transitionBlocked;
    try {
      final resolved =
          await (_trackPlaybackResolver?.call(candidate) ??
                  Future.value(candidate))
              .timeout(const Duration(seconds: 12));
      if (!valid()) return;
      decoder = _newPreparedPlayer();
      _transition.loading = decoder;
      await decoder.setVolume(0);
      await _configureLoudness(decoder, resolved);
      // Preparation uses a bounded native buffer, not a whole-file Dart cache
      // download. Reuse an already complete cache without changing active flags.
      final uri = Uri.tryParse(resolved.audioAsset);
      AudioSource source;
      if (resolved.isRemote && uri != null) {
        final cached = _remoteCachingSources[resolved.id];
        final file = cached == null ? null : await cached.cacheFile;
        source = file != null && await file.exists()
            ? AudioSource.uri(file.uri, tag: resolved.toMediaItem())
            : AudioSource.uri(
                uri,
                headers: publicAudioHeaders(resolved.audioHeaders),
                tag: resolved.toMediaItem(),
              );
      } else if (uri != null &&
          (uri.scheme == 'file' || uri.scheme == 'content')) {
        source = AudioSource.uri(uri, tag: resolved.toMediaItem());
      } else {
        source = AudioSource.asset(
          resolved.audioAsset,
          tag: resolved.toMediaItem(),
        );
      }
      await decoder.setAudioSource(source).timeout(const Duration(seconds: 12));
      if (_effectConfig != null) {
        await decoder.setSodaAudioEffect(_effectConfig);
      }
      if (!valid() || decoder.processingState != ProcessingState.ready) return;
      _transition.ready = PreparedTrack(resolved, decoder, key);
      _transition.loading = null;
      decoder = null; // ownership is now held only by ready
    } catch (_) {
      /* Speculative failure is silent; normal Next owns retries. */
    } finally {
      if (decoder != null) {
        if (identical(_transition.loading, decoder)) _transition.loading = null;
        await decoder.dispose().catchError((Object _) {});
      }
    }
  }

  void _tickPreparation(Duration position) {
    if (_transitionBlocked) {
      if (_transition.ready != null || _transition.loading != null) {
        _invalidatePreparation();
      }
      if (_transition.crossing) {
        unawaited(_cancelTransition().catchError((Object _) {}));
      }
      return;
    }
    if (!_player.playing ||
        _refreshingSource ||
        _pendingQueueEpoch != null ||
        _transition.crossing ||
        _isSeeking) {
      return;
    }
    final duration =
        _player.duration ?? mediaItem.value?.duration ?? Duration.zero;
    final remaining = duration - position;
    if (duration < const Duration(seconds: 10) || remaining <= Duration.zero) {
      return;
    }
    final preferences = _playbackPreferences;
    if (!preferences.prepareNext && !preferences.crossfade) return;
    final threshold = preferences.prepareNext
        ? const Duration(seconds: 30)
        : Duration(seconds: preferences.seconds + 8);
    final candidate = _nextCandidate();
    if (candidate == null) return;
    final key = _nextQueueKey();
    if (_transition.attemptedKey != key &&
        (_transition.ready != null || _transition.loading != null)) {
      _invalidatePreparation();
    }
    if (remaining <= threshold && _transition.attemptedKey != key) {
      unawaited(_prepareNext(candidate, key));
    }
    final ready = _transition.ready;
    if (preferences.crossfade &&
        ready != null &&
        ready.queueKey == key &&
        (ready.player.duration ?? Duration.zero) >
            Duration(seconds: preferences.seconds + 2) &&
        remaining <= Duration(seconds: preferences.seconds) &&
        remaining > const Duration(milliseconds: 700)) {
      unawaited(_crossfade(ready, remaining));
    }
  }

  Future<bool> _publishPrepared(
    List<Track> tracks,
    bool Function() valid,
  ) async {
    final items = tracks.map((t) => t.toMediaItem()).toList();
    if (!valid()) return false;
    _tracks = tracks;
    for (final t in tracks) {
      _knownTracks[t.id] = t;
    }
    queue.add(items);
    _upcomingMediaItems = items.skip(1).toList();
    _loadedTrackId = tracks.first.id;
    _pendingQueueEpoch = null;
    _deferredRestore = null;
    _resolutionError = null;
    mediaItem.add(items.first);
    _completionGate.reset();
    _completionGate.onPlay(_player.position);
    _resetConsumptionConfirmation();
    _recordPlaybackHistory(tracks.first);
    _publishUpcomingQueue();
    _positions.add(_player.position);
    _durations.add(_player.duration);
    _sessions.add(_player.androidAudioSessionId);
    _handleDuration(_player.duration);
    _broadcastState(_player.playbackEvent);
    await _applyPlaybackOrder();
    if (!valid()) return false;
    _scheduleConsumptionConfirmation();
    return true;
  }

  Future<void> _crossfade(PreparedTrack ready, Duration remaining) async {
    if (_transition.crossing) return;
    _transition.crossing = true;
    _transition.ready = null;
    final epoch = _transition.epoch;
    final previous = _player;
    final incoming = ready.player;
    final completed = trackForId(_loadedTrackId ?? '');
    bool adopted = false;
    bool valid() => epoch == _transition.epoch && !_transitionBlocked;
    try {
      // Start silently and confirm actual decoded progress before touching the
      // current recording or its metadata. Failed preparation cannot cut it off.
      unawaited(incoming.play().catchError((Object _) {}));
      await incoming.positionStream
          .firstWhere((p) => p > Duration.zero)
          .timeout(const Duration(milliseconds: 650));
      if (!valid() ||
          !_player.playing ||
          incoming.processingState != ProcessingState.ready) {
        return;
      }
      final from = previous.duration == null
          ? remaining
          : previous.duration! - previous.position;
      if (from <= Duration.zero) return;
      final qualifies = _completionGate.takeCompletion();
      _transition.tail = previous;
      _pendingQueueEpoch = ++_queueLoadEpoch;
      _resetConsumptionConfirmation();
      _player = incoming;
      adopted = true;
      _bindPlayer(incoming);
      _transition.tailCompletion = previous.processingStateStream
          .where((s) => s == ProcessingState.completed)
          .take(1)
          .listen((_) {
            if (qualifies && completed != null && valid()) {
              _completedTrackController.add(completed);
            }
          });
      // Publish the active identity synchronously with decoder adoption. A
      // Pause/Seek during a slow native route handoff must see the incoming
      // song, never an old media item bound to a different decoder.
      final publication = _publishPrepared([
        ready.track,
        ..._upcomingMediaItems
            .where((i) => i.id != ready.track.id)
            .map((i) => trackForId(i.id))
            .whereType<Track>(),
      ], valid).catchError((Object _) => false);
      await previous.setMusicOutputOwner('mesting-tail');
      if (identical(_player, incoming)) {
        await incoming.setMusicOutputOwner('mesting-music');
      }
      await publication;
      if (!valid()) return;
      // Stopwatch time avoids stretching the fade when a platform volume call
      // is slow. Manual controls invalidate the generation before their awaits.
      final length = Duration(
        milliseconds: min(from.inMilliseconds, remaining.inMilliseconds),
      );
      final fade = () async {
        final clock = Stopwatch()..start();
        while (valid() &&
            incoming.playing &&
            incoming.processingState == ProcessingState.ready) {
          final t = (clock.elapsedMicroseconds / length.inMicroseconds).clamp(
            0.0,
            1.0,
          );
          final gains = crossfadeGains(t);
          await previous.setVolume(gains.$1 * _interruptionGain);
          if (!valid()) break;
          await incoming.setVolume(gains.$2 * _interruptionGain);
          if (t >= 1) break;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }();
      _transition.fading = fade;
      await fade;
    } catch (_) {
      /* Preserve the selected active stream; release only the tail. */
    } finally {
      if (!adopted) await incoming.dispose().catchError((Object _) {});
      if (adopted && identical(_transition.tail, previous)) {
        await previous.stop().catchError((Object _) {});
        await previous.dispose().catchError((Object _) {});
        _transition.tail = null;
      }
      if (identical(_player, incoming) && epoch == _transition.epoch) {
        await incoming.setVolume(_interruptionGain).catchError((Object _) {});
      }
      await _transition.tailCompletion?.cancel();
      _transition.tailCompletion = null;
      _transition.fading = null;
      _transition.crossing = false;
    }
  }

  Future<void> _cancelTransition() async {
    final active = _player;
    final tail = _transition.tail;
    if (_transition.crossing) _transition.invalidate();
    // Stop immediately; wait for the last in-flight gain before restoration.
    if (tail != null) unawaited(tail.stop().catchError((Object _) {}));
    final fading = _transition.fading;
    if (fading != null) {
      try {
        await fading;
      } catch (_) {}
    }
    if (identical(active, _player) && (tail != null || fading != null)) {
      await active.setVolume(_interruptionGain);
    }
  }
}
