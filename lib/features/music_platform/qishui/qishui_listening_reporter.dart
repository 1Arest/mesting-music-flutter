import 'dart:async';

import '../../../core/audio/actual_listening_counter.dart';
import '../../../shared/models/track.dart';
import 'qishui_listening_repository.dart';

enum QishuiListeningPhase { idle, listening, sending, submitted, unconfirmed }

class QishuiListeningStatus {
  const QishuiListeningStatus({
    this.phase = QishuiListeningPhase.idle,
    this.heardMilliseconds = 0,
    this.transportAcceptedMilliseconds = 0,
    this.unconfirmedMilliseconds = 0,
    this.message = '',
  });

  final QishuiListeningPhase phase;
  final int heardMilliseconds;
  final int transportAcceptedMilliseconds;
  final int unconfirmedMilliseconds;
  final String message;
}

/// One binding consumes the existing player's real state. This class never
/// owns an audio player or infers hearing from a restored position. Each state
/// edge settles the preceding monotonic interval before eligibility changes.
/// Seek/buffering/pause intervals contribute to neither hearing nor reporting.
class QishuiListeningReporter {
  QishuiListeningReporter({
    required this.repository,
    ListeningClock? clock,
    this.onStatus,
  }) : clock = clock ?? MonotonicListeningClock();

  final QishuiListeningRepository repository;
  final ListeningClock clock;
  final void Function(QishuiListeningStatus)? onStatus;
  Track? _track;
  ActualListeningCounter? _counter, _foregroundCounter;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false, _started = false, _progressed = false;
  bool _hadSeek = false;
  bool _disposed = false;
  int _heard = 0, _accepted = 0, _uncertain = 0;
  int _segmentBase = 0, _foregroundBase = 0;
  Future<void> _tail = Future.value();

  bool get _current => !_disposed && repository.current;
  int get heardMilliseconds =>
      _heard + (_counter?.sample() ?? 0) - _segmentBase;

  void _status(QishuiListeningPhase phase, String message) {
    if (_current) {
      onStatus?.call(
        QishuiListeningStatus(
          phase: phase,
          heardMilliseconds: heardMilliseconds,
          transportAcceptedMilliseconds: _accepted,
          unconfirmedMilliseconds: _uncertain,
          message: message,
        ),
      );
    }
  }

  Map<String, Object> _media(Track track) => {
    'group_type': 'track',
    'group_id': track.platformSongId,
    'media_type': 'track',
  };

  void _enqueue(
    List<QishuiListeningEvent> events, {
    int heardMilliseconds = 0,
    bool playing = false,
  }) {
    if (!_current) return;
    final operation = _tail.then((_) async {
      if (heardMilliseconds > 0) {
        _status(QishuiListeningPhase.sending, '正在提交本次汽水实际听歌时长');
      }
      final delivery = await repository.submit(
        events,
        heardMilliseconds: heardMilliseconds,
        playing: playing,
      );
      if (!_current) return;
      if (heardMilliseconds > 0) {
        if (delivery == QishuiListeningDelivery.accepted) {
          _accepted += heardMilliseconds;
          _status(QishuiListeningPhase.submitted, '本次时长请求已提交，官版累计入账仍需刷新核对');
        } else {
          _uncertain += heardMilliseconds;
          _status(
            QishuiListeningPhase.unconfirmed,
            '本次实际时长已记在本机，上报结果未确认；不会自动重发',
          );
        }
      }
    });
    _tail = operation.catchError((Object _) {
      if (heardMilliseconds > 0) {
        _uncertain += heardMilliseconds;
        _status(QishuiListeningPhase.unconfirmed, '本次时长保存或提交未完成，请核对本机记录');
      }
    });
  }

  void _startAndProgress() {
    final track = _track;
    final heard = (_counter?.sample() ?? 0) - _segmentBase;
    if (track == null || heard <= 0 || !_current) return;
    if (!_started) {
      _started = true;
      _enqueue([
        QishuiListeningEvent('audio_play', _media(track), clock.now),
      ], playing: true);
    }
    if (!_progressed && _position > Duration.zero) {
      _progressed = true;
      _enqueue([
        QishuiListeningEvent('player_metrics', {
          ..._media(track),
          'type': 'progressed',
          'extra_data': '${_position.inMilliseconds / 1000}',
          'duration': _duration.inMilliseconds / 1000,
        }, clock.now),
      ], playing: true);
    }
  }

  void update({
    required Track? track,
    required bool playing,
    required bool ready,
    required bool seeking,
    double speed = 1,
    Duration position = Duration.zero,
    Duration? duration,
    bool foreground = true,
  }) {
    if (!_current) return;
    final valid =
        track != null &&
        track.source == TrackSource.qishui &&
        RegExp(r'^\d{1,30}$').hasMatch(track.platformSongId);
    final next = valid ? track : null;
    final changed = next?.id != _track?.id;
    if (changed) {
      _endSegment('change_queue');
      _track = next;
      _counter = next == null ? null : ActualListeningCounter(clock);
      _foregroundCounter = next == null ? null : ActualListeningCounter(clock);
      _segmentBase = 0;
      _foregroundBase = 0;
      _started = false;
      _progressed = false;
      _hadSeek = false;
    }
    // Counter.update samples the old state first, preventing a pause/seek
    // notification from discarding the just-heard interval or charging it
    // under the new track/visibility state.
    _counter?.update(
      playing: playing,
      ready: ready,
      seeking: seeking,
      speed: speed,
    );
    _foregroundCounter?.update(
      playing: playing && foreground,
      ready: ready,
      seeking: seeking,
      speed: speed,
    );
    _position = position;
    _duration = duration ?? next?.duration ?? Duration.zero;
    if (seeking) _hadSeek = true;
    _startAndProgress();
    if (!playing && _playing && !changed) _endSegment('pause');
    _playing = playing;
    if (_counter?.audible == true) {
      _status(QishuiListeningPhase.listening, '正在记录汽水实际播放时长');
    }
  }

  void _endSegment(String reason) {
    final track = _track;
    final counter = _counter;
    if (track == null || counter == null) return;
    final total = counter.sample();
    final heard = total - _segmentBase;
    final foregroundTotal = _foregroundCounter?.sample() ?? 0;
    final front = (foregroundTotal - _foregroundBase).clamp(
      0,
      heard < 0 ? 0 : heard,
    );
    _startAndProgress();
    _segmentBase = total;
    _foregroundBase = foregroundTotal;
    _started = false;
    _progressed = false;
    if (heard <= 0) return;
    _heard += heard;
    final media = _media(track);
    final pct = _duration.inMilliseconds > 0
        ? (heard / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final events = <QishuiListeningEvent>[
      QishuiListeningEvent('audio_over', {
        ...media,
        'duration': heard,
        'duration_pct': pct,
        'audio_over_status': reason,
      }, clock.now),
      if (reason != 'pause') ...[
        QishuiListeningEvent('audio_finish', {
          ...media,
          'duration': heard,
          'duration_pct': pct,
          'audio_finish_status': reason,
          'foreground_dur': front,
          'background_dur': heard - front,
          'is_progress_bar_move': _hadSeek ? 1 : 0,
        }, clock.now),
        QishuiListeningEvent('player_metrics', {
          ...media,
          'type': 'finish',
          'cost': heard,
          'duration': _duration.inMilliseconds / 1000,
          'extra_data': '',
        }, clock.now),
      ],
    ];
    _hadSeek = false;
    _enqueue(events, heardMilliseconds: heard);
  }

  /// A native repeat boundary ends one genuine occurrence without replacing
  /// its source. The caller can then continue update() for the same track.
  Future<void> finish({String reason = 'change_queue'}) {
    if (!_current) return Future.value();
    if (!{
      'finished',
      'next',
      'previous',
      'change_queue',
      'pause',
      'shift',
    }.contains(reason)) {
      throw ArgumentError.value(reason, 'reason');
    }
    _counter?.update(playing: false);
    _foregroundCounter?.update(playing: false);
    _endSegment(reason);
    _playing = false;
    return settle();
  }

  Future<void> settle() => _tail;

  /// Account switching cancels queued old-account sends. It cannot turn them
  /// into writes under the new account and never replays pending old events.
  void dispose() {
    if (_disposed) return;
    _counter?.update(playing: false);
    _foregroundCounter?.update(playing: false);
    final remainder = (_counter?.sample() ?? 0) - _segmentBase;
    if (remainder > 0) {
      unawaited(repository.rememberUnsent(remainder).catchError((Object _) {}));
    }
    _disposed = true;
    repository.dispose();
  }
}
