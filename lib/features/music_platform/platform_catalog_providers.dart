import 'platform_backend_providers.dart';
import '../library/data/favorite_track_window.dart';
import '../library/library_providers.dart';
import '../../core/cache/cached_browse_provider.dart';
import 'netease/netease_catalog_adapters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/track.dart';
import 'data/platform_catalog.dart';
import 'music_platform_providers.dart';
import 'platform_recommendation_providers.dart';

final platformCatalogProvider = Provider<PlatformCatalog>((ref) {
  ref.watch(
    platformAccountProvider.select(
      (value) => (value.value?.ownerId, value.value?.token),
    ),
  );
  final api = ref.watch(musicPlatformApiProvider);
  return ref.watch(usesNeteaseProvider)
      ? NeteaseCatalogAdapter(api, ref.watch(neteaseMusicRepositoryProvider))
      : PlatformCatalog(api);
});

// Await secure local restoration, never CloudBase. Providers rebuild on account
// change, so a former user's recommendations cannot survive a new login.
final platformDailyProvider = FutureProvider<List<Track>>((ref) async {
  await ref.watch(platformAccountProvider.future);
  return cachedBrowse(ref, () => ref.watch(platformCatalogProvider).daily());
});
final platformNewSongsProvider = FutureProvider<List<Track>>((ref) async {
  await ref.watch(platformAccountProvider.future);
  return cachedBrowse(ref, () => ref.watch(platformCatalogProvider).newSongs());
});
final platformDiscoveryProvider = FutureProvider<List<Track>>((ref) async {
  await ref.watch(platformAccountProvider.future);
  final repository = ref.watch(platformRecommendationsProvider);
  return cachedRecommendationPreview(ref, 'discovery', () async {
    await repository.discover();
    return repository.discoverySongs;
  });
});
final platformFeaturedProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  await ref.watch(platformAccountProvider.future);
  return cachedBrowse(ref, () => ref.watch(platformCatalogProvider).featured());
});
final platformPublicPlaylistProvider = FutureProvider.autoDispose
    .family<List<Track>, String>((ref, id) async {
      await ref.watch(platformAccountProvider.future);
      return ref.watch(publicPlaylistWindowProvider(id)).stream.first;
    });

final publicPlaylistWindowProvider = Provider.autoDispose
    .family<FavoriteTrackWindow, String>((ref, id) {
      final catalog = ref.watch(platformCatalogProvider);
      final first = cachedBrowse(ref, () => catalog.publicPlaylistPage(id));
      final window = FavoriteTrackWindow(
        ref.watch(libraryRepositoryProvider),
        preview: Stream.fromFuture(first),
        readPage: (offset, limit) =>
            catalog.publicPlaylistPage(id, offset: offset, limit: limit),
      );
      ref.onDispose(window.dispose);
      return window;
    });
