import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/distribution_channel.dart';
import '../../../shared/models/track.dart';
import '../../../shared/utils/duration_format.dart';
import '../../music_platform/data/platform_track_duration_repository.dart';
import '../../music_platform/music_platform_providers.dart';

final queueDurationRepositoryProvider = Provider((ref) {
  // Account invalidation disposes the old cache and aborts its pending requests.
  ref.watch(platformAccountProvider);
  final repository = PlatformTrackDurationRepository(
    ref.watch(musicPlatformApiProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final queueTrackDurationProvider = FutureProvider.autoDispose
    .family<Duration?, Track>((ref, track) {
      return ref.watch(queueDurationRepositoryProvider).resolve(track);
    });

Duration? positiveTrackDuration(Duration? value) =>
    value != null && value > Duration.zero ? value : null;

/// Each visible row updates independently. A zero MediaItem duration must not
/// hide a positive catalogue duration; loading metadata never blocks the queue.
class QueueTrackDuration extends ConsumerWidget {
  const QueueTrackDuration({
    required this.track,
    required this.mediaDuration,
    required this.style,
    super.key,
  });
  final Track? track;
  final Duration? mediaDuration;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A preview decoder measures its permitted excerpt, not the full song.
    var duration = track?.isPreview == true
        ? positiveTrackDuration(track?.duration)
        : positiveTrackDuration(mediaDuration) ??
              positiveTrackDuration(track?.duration);
    if (DistributionChannel.isBeta && duration == null && track != null) {
      duration = positiveTrackDuration(
        ref.watch(queueTrackDurationProvider(track!)).value,
      );
    }
    return Text(
      duration == null && DistributionChannel.isBeta
          ? '--:--'
          : formatDuration(duration ?? Duration.zero),
      key: ValueKey('queue-duration-${track?.id ?? "unknown"}'),
      style: style,
    );
  }
}
