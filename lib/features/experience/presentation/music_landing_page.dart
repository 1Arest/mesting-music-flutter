import 'music_discovery_sections.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../music_platform/platform_recommendation_providers.dart';
import 'package:flutter/material.dart';
import '../../music_platform/platform_browse_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../music_platform/platform_catalog_providers.dart';
import '../../music_platform/presentation/platform_design.dart';
import 'editorial_widgets.dart';
import '../../music_platform/presentation/platform_recommendations_page.dart';
import '../../music_platform/data/platform_explore.dart';
import '../../music_platform/platform_explore_providers.dart';
import 'music_home_catalogues.dart';
import '../../music_platform/netease/netease_features_page.dart';

/// Home and discovery share presentation primitives, never the same content
/// composition. All recommendation data still comes from the concept adapter.
class MusicLandingPage extends ConsumerWidget {
  const MusicLandingPage({this.discovery = false, super.key});
  final bool discovery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(usesNeteaseProvider)) return const NeteaseDiscoveryPage();
    if (discovery) return const PlatformRecommendationHome();
    return PlatformStyle(
      child: EditorialScroll(
        onRefresh: () => refreshBrowse(ref, [
          () => ref.refresh(platformDailyProvider.future),
          if (ref.exists(platformFmProvider))
            () => ref.refresh(platformFmProvider.future),
          if (ref.exists(platformDiscoveryProvider))
            () => ref.refresh(platformDiscoveryProvider.future),
          if (ref.exists(platformNewSongsProvider))
            () => ref.refresh(platformNewSongsProvider.future),
          if (ref.exists(platformFeaturedProvider))
            () => ref.refresh(platformFeaturedProvider.future),
          for (final kind in musicHomeCatalogueOrder)
            if (ref.exists(platformExploreProvider(kind)))
              () => ref.refresh(platformExploreProvider(kind).future),
        ]),
        children: const [
          EditorialHeader('发现'),
          MusicDiscoveryHighlights(),
          KugouDiscoveryPlaylists(),
          MusicDiscoverySongGroups(),
          MusicHomeCatalogueShelf(PlatformExploreKind.rank),
          PlatformRecommendedSection(title: '新歌首发', newSongs: true),
          MusicHomeCatalogueShelf(PlatformExploreKind.album),
          MusicHomeCatalogueShelf(PlatformExploreKind.theme),
          MusicHomeCatalogueShelf(PlatformExploreKind.scene),
        ],
      ),
    );
  }
}
