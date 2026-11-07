import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../music_platform/presentation/platform_feedback.dart';

/// Plays a selection immediately. Single tracks retain the manual upcoming
/// queue, and Play All replaces it with a snapshot of the selected collection.
Future<bool> playBetaSelection(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  List<Track>? playAll,
  bool Function()? stillCurrent,
}) async {
  try {
    if (stillCurrent?.call() == false) return false;
    final handler = ref.read(audioHandlerProvider);
    bool current() => context.mounted && stillCurrent?.call() != false;
    if (playAll != null) {
      await handler.replaceQueue([...playAll], togetherGuard: current);
    } else {
      await handler.playSingleTrack(
        track,
        playbackContext: [track],
        discardRecommendations: true,
        isCurrent: current,
      );
    }
    return true;
  } catch (error) {
    if (context.mounted && stillCurrent?.call() != false) {
      showPlatformFailure(context, error);
    }
    return false;
  }
}
