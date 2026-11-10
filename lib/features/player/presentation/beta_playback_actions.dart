import '../../music_platform/data/music_platform_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../music_platform/presentation/source_login_prompt.dart';
import '../../music_platform/music_platform_providers.dart';

/// Plays a selection immediately. Single tracks retain the manual upcoming
/// queue, and Play All replaces it with a snapshot of the selected collection.
Future<bool> playBetaSelection(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  List<Track>? playAll,
  bool Function()? stillCurrent,
  bool retrySourceLogin = true,
}) async {
  try {
    if (stillCurrent?.call() == false) return false;
    final handler = ref.read(audioHandlerProvider);
    // Local audio has no source credential or transport preflight. Keep this
    // path usable before account restoration and without starting login state.
    if (!track.hasLocalAudio &&
        (track.source == TrackSource.kugou ||
            track.source == TrackSource.netease)) {
      final owner = ref.read(platformAccountProvider).value;
      if (owner != null && owner.platform.name != track.source.name) {
        final revision = handler.transportRevision;
        if (!await ensureSourceLogin(context, ref, track.source)) return false;
        if (!context.mounted ||
            stillCurrent?.call() == false ||
            handler.transportRevision != revision) {
          return false;
        }
      }
    }
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
    if (context.mounted &&
        stillCurrent?.call() != false &&
        retrySourceLogin &&
        error is MusicPlatformException &&
        (error.code == 'source_login_kugou' ||
            error.code == 'source_login_netease')) {
      final handler = ref.read(audioHandlerProvider);
      final revision = handler.transportRevision;
      final source = error.code == 'source_login_kugou'
          ? TrackSource.kugou
          : TrackSource.netease;
      if (await ensureSourceLogin(context, ref, source) &&
          context.mounted &&
          stillCurrent?.call() != false &&
          handler.transportRevision == revision) {
        return playBetaSelection(
          context,
          ref,
          track,
          playAll: playAll,
          stillCurrent: stillCurrent,
          retrySourceLogin: false,
        );
      }
      return false;
    }
    if (context.mounted && stillCurrent?.call() != false) {
      showPlatformFailure(context, error);
    }
    return false;
  }
}
