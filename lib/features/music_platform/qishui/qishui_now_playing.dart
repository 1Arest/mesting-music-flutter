import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/track_artwork.dart';

/// The music root reflects the one existing player rather than constructing a
/// second preview player. Offscreen list work stays outside this subscription.
class QishuiNowPlaying extends ConsumerWidget {
  const QishuiNowPlaying({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item?.extras?['source'] != TrackSource.qishui.name) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Text('从下方推荐中选择一首歌，开始连续播放。'),
      );
    }
    final handler = ref.read(audioHandlerProvider);
    final track = handler.trackForId(item!.id);
    if (track == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: TrackArtwork(track: track, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            track.title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(track.artist, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              BetaGlassButton(
                onPressed: handler.skipToPrevious,
                label: '上一首',
                child: const Icon(Icons.skip_previous),
              ),
              BetaGlassButton(
                onPressed: handler.togglePlayPause,
                label: '播放或暂停',
                child: Icon(
                  ref.watch(playbackStateProvider).value?.playing == true
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              BetaGlassButton(
                onPressed: handler.skipToNext,
                label: '下一首',
                child: const Icon(Icons.skip_next),
              ),
              BetaGlassButton(
                onPressed: () => context.push('/player'),
                child: const Text('歌词与队列'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
