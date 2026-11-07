import 'dart:async';
import 'dart:math' as math;

typedef PauseFadeDelay = Future<void> Function(Duration duration);
typedef PauseFadeVolumeSetter = Future<void> Function(double volume);
typedef PauseFadePauseAction = Future<void> Function();

/// Coordinates a cancellable volume fade before pausing audio.
///
/// The original volume is restored only after playback has paused, so the next
/// play starts at the user's normal volume instead of remaining silent.
class PauseFadeController {
  PauseFadeController({
    required PauseFadeVolumeSetter setVolume,
    required PauseFadePauseAction pause,
    this.duration = const Duration(milliseconds: 700),
    this.steps = 14,
    PauseFadeDelay delay = _defaultDelay,
  }) : assert(steps > 0),
       _setVolume = setVolume,
       _pause = pause,
       _delay = delay;

  final Duration duration;
  final int steps;
  final PauseFadeVolumeSetter _setVolume;
  final PauseFadePauseAction _pause;
  final PauseFadeDelay _delay;

  int _operationGeneration = 0;
  Future<void>? _operation;
  double? _restoreVolume;

  bool get isFading => _operation != null;

  Future<void> fadeOutAndPause(double currentVolume) {
    final running = _operation;
    if (running != null) return running;

    final restoreVolume = currentVolume.clamp(0.0, 1.0).toDouble();
    final generation = ++_operationGeneration;
    _restoreVolume = restoreVolume;
    final operation = _runFade(
      generation: generation,
      restoreVolume: restoreVolume,
    );
    _operation = operation;
    return operation;
  }

  /// Cancels an active fade and restores the volume after the in-flight step
  /// has finished. This prevents a stale lower-volume platform call from
  /// winning after a user resumes or changes tracks.
  Future<void> cancel({bool restoreVolume = true}) async {
    final running = _operation;
    final volume = _restoreVolume;
    if (running == null) return;

    _operationGeneration += 1;
    await running;
    if (restoreVolume && volume != null) {
      await _setVolume(volume);
    }
  }

  Future<void> _runFade({
    required int generation,
    required double restoreVolume,
  }) async {
    var volumeWasChanged = false;
    try {
      if (restoreVolume <= 0.001 || duration <= Duration.zero) {
        if (generation == _operationGeneration) {
          await _pause();
        }
        return;
      }

      final stepDuration = Duration(
        microseconds: math.max(1, duration.inMicroseconds ~/ steps),
      );
      for (var step = 1; step <= steps; step += 1) {
        await _delay(stepDuration);
        if (generation != _operationGeneration) return;

        final remaining = pauseFadeRemainingVolume(step / steps);
        await _setVolume(restoreVolume * remaining);
        volumeWasChanged = true;
        if (generation != _operationGeneration) return;
      }

      await _pause();
    } finally {
      if (generation == _operationGeneration) {
        try {
          if (volumeWasChanged) {
            await _setVolume(restoreVolume);
          }
        } finally {
          _operation = null;
          _restoreVolume = null;
        }
      } else {
        _operation = null;
        _restoreVolume = null;
      }
    }
  }
}

/// Returns the remaining volume for an ease-in-out cubic fade.
double pauseFadeRemainingVolume(double progress) {
  final t = progress.clamp(0.0, 1.0).toDouble();
  final faded = t < 0.5
      ? 4 * t * t * t
      : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
  return (1 - faded).clamp(0.0, 1.0).toDouble();
}

Future<void> _defaultDelay(Duration duration) => Future<void>.delayed(duration);
