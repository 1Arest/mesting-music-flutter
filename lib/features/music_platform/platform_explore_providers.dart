import 'platform_backend_providers.dart';
import '../../core/cache/cached_browse_provider.dart';
import 'netease/netease_catalog_adapters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/platform_explore.dart';
import 'music_platform_providers.dart';

/// Shared catalogues for Home and Search. Providers belong to the data boundary,
/// so a presentation route never has to import another page to fetch its data.
final platformExploreRepositoryProvider = Provider<PlatformExploreRepository>((
  ref,
) {
  final api = ref.watch(musicPlatformApiProvider);
  return ref.watch(usesNeteaseProvider)
      ? NeteaseExploreAdapter(api, ref.watch(neteaseMusicRepositoryProvider))
      : PlatformExploreRepository(api);
});

final platformExploreProvider =
    FutureProvider.family<List<PlatformExploreItem>, PlatformExploreKind>((
      ref,
      kind,
    ) async {
      await ref.watch(platformAccountProvider.future);
      return cachedBrowse(
        ref,
        () => ref.watch(platformExploreRepositoryProvider).list(kind),
      );
    });
