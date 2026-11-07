import 'package:just_audio/just_audio.dart';

/// Decides whether a network source has reached a state that cannot produce
/// audible playback. The elapsed timeout is owned by the audio handler; this
/// class deliberately stays side-effect free so the decision is testable.
class PlaybackStartGuard {
  const PlaybackStartGuard({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  /// A ready player which is still at the start after the guard timeout has
  /// most likely received an unusable remote response. A missing duration is
  /// valid for live streams, but live playback must still advance its
  /// position once it has started.
  bool shouldReportStalled({
    required bool isNetworkSource,
    required bool playing,
    required ProcessingState processingState,
    required Duration position,
  }) {
    return isNetworkSource &&
        playing &&
        processingState == ProcessingState.ready &&
        position == Duration.zero;
  }
}
