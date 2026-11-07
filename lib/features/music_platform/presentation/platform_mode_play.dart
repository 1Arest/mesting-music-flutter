import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../data/platform_recommendations.dart';
import '../netease/netease_features_page.dart';
import '../netease/netease_features_repository.dart';
import '../platform_catalog_providers.dart';
import '../platform_recommendation_providers.dart';
import 'platform_collection_play.dart';

enum PlatformHighlightMode { daily, heart, fm }

/// A preview supplies artwork only. The explicit action reads the full finite
/// recommendation or starts the existing FM/refill path, without navigating.
class PlatformModePlayButton extends StatelessWidget {
  const PlatformModePlayButton({
    required this.mode,
    required this.title,
    super.key,
  });
  final PlatformHighlightMode mode;
  final String title;

  Future<List<Track>> _load(WidgetRef ref, bool Function() current) async {
    if (!current()) return const [];
    if (mode == PlatformHighlightMode.heart) {
      final batch = await ref
          .read(neteaseFeaturesProvider)
          .load(NeteaseFeed.intelligence);
      if (!current()) return const [];
      // This endpoint supplies one fixed official recommendation batch. It is
      // not a paginated liked-song list or a fabricated endless collection.
      final seen = <String>{};
      return [
        for (final item in batch.items)
          if (item.track case final Track track)
            if (seen.add(track.id)) track,
      ];
    }
    final tracks = await ref.read(
      (mode == PlatformHighlightMode.daily
              ? platformDailyProvider
              : platformFmProvider)
          .future,
    );
    return current() ? tracks : const [];
  }

  @override
  Widget build(BuildContext context) => PlatformSelectionPlayButton(
    selectionKey: 'cover-play-mode-${mode.name}',
    label: mode == PlatformHighlightMode.fm ? '播放$title' : '播放$title全部歌曲',
    load: _load,
    stream: mode == PlatformHighlightMode.fm
        ? PlatformRecommendationKind.fm
        : null,
  );
}
