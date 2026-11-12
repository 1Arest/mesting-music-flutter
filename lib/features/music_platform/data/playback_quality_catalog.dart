import '../../../shared/models/track.dart';
import '../domain/platform_audio_quality.dart';

/// Read old snapshots conservatively. A fallback label proves its provider but
/// does not invent that provider's recording ID or capabilities.
AudioOrigin? playbackAudioOrigin(Track track) {
  if (track.hasLocalAudio) return null;
  if (track.audioOrigin != null) return track.audioOrigin;
  const marker = '备用音源 · ';
  if (track.availabilityMessage.startsWith(marker)) {
    return AudioOrigin(track.availabilityMessage.substring(marker.length), '');
  }
  return switch (track.source) {
    TrackSource.netease => AudioOrigin(AudioOrigin.netease, track.id),
    TrackSource.kugou => AudioOrigin(AudioOrigin.kugou, track.id),
    _ => null,
  };
}

class VerifiedPlaybackQualities {
  VerifiedPlaybackQualities(
    this.track,
    Map<PlatformAudioQuality, Track> values, {
    required this.current,
  }) : values = Map.unmodifiable(values);
  final Track track;
  final Map<PlatformAudioQuality, Track> values;
  final bool Function() current;
  AudioOrigin? get origin => playbackAudioOrigin(track);
}

/// Resource metadata is only a candidate list. Two bounded workers verify the
/// exact recording/provider, actual tier and full stream without touching the
/// player. A preview, downgrade or failed account entitlement is never offered.
Future<Map<PlatformAudioQuality, Track>> verifyPlaybackQualities({
  required Track track,
  required Iterable<PlatformAudioQuality> candidates,
  required Future<Track?> Function(PlatformAudioQuality) resolve,
  required bool Function() current,
}) async {
  final result = <PlatformAudioQuality, Track>{};
  final actual = PlatformAudioQuality.fromCode(track.playbackQuality);
  final origin = playbackAudioOrigin(track);
  bool stream(Track value) {
    final uri = Uri.tryParse(value.audioAsset);
    return !value.isPreview &&
        uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
  }

  if (actual != null && stream(track)) result[actual] = track;
  final queue = candidates.toSet().where((tier) => !result.containsKey(tier)).toList();
  var index = 0;
  Future<void> worker() async {
    while (current() && index < queue.length) {
      final tier = queue[index++];
      try {
        final resolved = await resolve(tier);
        if (current() &&
            resolved != null &&
            resolved.id == track.id &&
            playbackAudioOrigin(resolved) == origin &&
            stream(resolved) &&
            resolved.playbackQuality == tier.code) {
          result[tier] = resolved;
        }
      } catch (_) {
        // An unavailable tier does not suppress other proven capabilities.
      }
    }
  }

  await Future.wait([worker(), worker()]);
  return current() ? Map.unmodifiable(result) : const {};
}
