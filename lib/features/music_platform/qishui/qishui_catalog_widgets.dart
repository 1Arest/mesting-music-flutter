import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_feedback.dart';
import '../presentation/song_actions_sheet.dart';
import 'qishui_providers.dart';

/// Search and artist lists use the retained shared player. A row inserts only
/// its selected recording; a separate explicit action replaces the full queue.
class QishuiCatalogTrackTile extends ConsumerWidget {
  const QishuiCatalogTrackTile({required this.track, super.key});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: TrackArtwork(track: track, width: 52, height: 52),
    ),
    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: SongActionsButton(track: track),
    onTap: () async {
      final account = ref.read(platformAccountProvider).value;
      final music = ref.read(qishuiRepositoryProvider);
      bool current() =>
          context.mounted &&
          music.current &&
          ref.read(platformAccountProvider).value?.token == account?.token;
      try {
        await ref
            .read(audioHandlerProvider)
            .playSingleTrack(
              track,
              playbackContext: [track],
              discardRecommendations: true,
              isCurrent: current,
            );
      } on Object catch (error) {
        if (context.mounted && current()) showPlatformFailure(context, error);
      }
    },
  );
}

/// A failed later page leaves the loaded rows above it usable. A bad cursor is
/// visible and stops further dispatch instead of creating an endless spinner.
class QishuiCatalogFooter extends StatelessWidget {
  const QishuiCatalogFooter({
    required this.loading,
    required this.hasMore,
    required this.loadMore,
    this.error,
    this.continuationProblem,
    super.key,
  });
  final bool loading, hasMore;
  final VoidCallback loadMore;
  final Object? error;
  final String? continuationProblem;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          Semantics(
            label: '正在加载',
            liveRegion: true,
            child: const MusicActivityIndicator(),
          )
        else if (error != null) ...[
          Semantics(liveRegion: true, child: Text('$error')),
          const SizedBox(height: 12),
          BetaGlassButton(onPressed: loadMore, child: const Text('重试加载')),
        ] else if (continuationProblem != null)
          Semantics(liveRegion: true, child: Text(continuationProblem!))
        else if (hasMore)
          BetaGlassButton(onPressed: loadMore, child: const Text('加载更多'))
        else
          Text('没有更多结果', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
