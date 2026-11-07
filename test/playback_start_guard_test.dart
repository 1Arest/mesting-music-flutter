import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesting_music/core/audio/playback_start_guard.dart';

void main() {
  const guard = PlaybackStartGuard();

  test('reports a remote source that remains at zero after startup', () {
    expect(
      guard.shouldReportStalled(
        isNetworkSource: true,
        playing: true,
        processingState: ProcessingState.ready,
        position: Duration.zero,
      ),
      isTrue,
    );
  });

  test('uses playback progress instead of duration to identify a stall', () {
    final successfulUnknownDuration = guard.shouldReportStalled(
      isNetworkSource: true,
      playing: true,
      processingState: ProcessingState.ready,
      position: const Duration(milliseconds: 1),
    );
    final stalledWithKnownDuration = guard.shouldReportStalled(
      isNetworkSource: true,
      playing: true,
      processingState: ProcessingState.ready,
      position: Duration.zero,
    );
    final paused = guard.shouldReportStalled(
      isNetworkSource: true,
      playing: false,
      processingState: ProcessingState.ready,
      position: Duration.zero,
    );
    final buffering = guard.shouldReportStalled(
      isNetworkSource: true,
      playing: true,
      processingState: ProcessingState.buffering,
      position: Duration.zero,
    );
    final local = guard.shouldReportStalled(
      isNetworkSource: false,
      playing: true,
      processingState: ProcessingState.ready,
      position: Duration.zero,
    );

    expect(stalledWithKnownDuration, isTrue);
    expect(<bool>[
      successfulUnknownDuration,
      paused,
      buffering,
      local,
    ], everyElement(isFalse));
  });
}
