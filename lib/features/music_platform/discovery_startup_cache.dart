import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/cache/browse_response_cache.dart';
import '../../shared/media/artwork_refresh_coordinator.dart';
import '../../shared/models/track.dart';
import '../history/listening_history_providers.dart';
import '../library/library_providers.dart';
import 'data/platform_explore.dart';
import 'music_platform_providers.dart';
import 'netease/netease_features_page.dart';
import 'netease/netease_features_repository.dart';
import 'platform_backend_providers.dart';
import 'platform_catalog_providers.dart';
import 'platform_explore_providers.dart';
import 'platform_recommendation_providers.dart';

/// Keeps the very same provider elements alive from disk hydration to the
/// routed app. A second ProviderScope would discard their AsyncData and expose
/// the loading frames again. No authentication or playback write lives here.
class DiscoveryStartupCache {
  final _subscriptions = <ProviderSubscription<Object?>>[];
  final _refresh = <void Function()>[];
  bool _resumed = false;
  bool _disposed = false;

  Future<T?> _prime<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
    void Function() refresh,
  ) async {
    final restored = Completer<T?>();
    _subscriptions.add(
      container.listen<AsyncValue<T>>(provider, (_, next) {
        if (restored.isCompleted) return;
        if (next.hasValue) {
          restored.complete(next.value);
        } else if (next.hasError) {
          // Riverpod may schedule retries while keeping .future pending. A disk
          // miss is already a final answer for hydration; it must not make a
          // perfectly healthy offline startup wait for that retry backoff.
          restored.complete(null);
        }
      }, fireImmediately: true),
    );
    _refresh.add(refresh);
    try {
      return await restored.future;
    } on Object {
      // Missing/corrupt snapshots are first visits, not a reason to hold the
      // startup screen for a live request or turn a storage failure into logout.
      return null;
    }
  }

  /// Called after the restored app's first painted frame, outside restoreOnly.
  /// FutureProvider refresh preserves AsyncData; cover preparation already
  /// guards each replacement before the browse cache notifies its subscribers.
  void resume() {
    if (_resumed || _disposed) return;
    _resumed = true;
    for (final refresh in _refresh) {
      refresh();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
  }

  static Future<DiscoveryStartupCache> prepare(
    ProviderContainer container, {
    ArtworkRefreshCoordinator? artwork,
  }) async {
    final lease = DiscoveryStartupCache();
    final covers = <String>[];
    final localCovers = <String>[];
    try {
      await container.read(platformAccountProvider.future);
      lease._subscriptions.add(
        container.listen(
          platformAccountProvider.select(
            (v) => (v.value?.ownerId, v.value?.token),
          ),
          (before, after) {
            if (before != after) lease.dispose();
          },
        ),
      );
      final netease = container.read(usesNeteaseProvider);
      await BrowseResponseCache.restoreOnly(() async {
        Future<void> tracks(
          ProviderListenable<AsyncValue<List<Track>>> provider,
          void Function() refresh,
        ) async {
          final value = await lease._prime(container, provider, refresh);
          covers.addAll(
            (value ?? const <Track>[]).take(4).map((t) => t.coverAsset),
          );
        }

        // Restore lower shelves first, then pin the actual first-screen covers
        // together. Warming every cover in a long library would evict that
        // first screen and undo the very guarantee startup needs to provide.
        final kinds = netease
            ? [PlatformExploreKind.rank]
            : [
                PlatformExploreKind.rank,
                PlatformExploreKind.album,
                PlatformExploreKind.theme,
                PlatformExploreKind.scene,
              ];
        for (final kind in kinds) {
          final provider = platformExploreProvider(kind);
          await lease._prime(
            container,
            provider,
            () => container.invalidate(provider),
          );
        }
        if (netease) {
          for (final feed in [
            NeteaseFeed.recommended,
            NeteaseFeed.premium,
            NeteaseFeed.albums,
            NeteaseFeed.artists,
            NeteaseFeed.mvs,
          ]) {
            final provider = neteaseFeedPreviewProvider(feed);
            await lease._prime(
              container,
              provider,
              () => container.invalidate(provider),
            );
          }
        } else {
          await lease._prime(
            container,
            platformFeaturedProvider,
            () => container.invalidate(platformFeaturedProvider),
          );
          await tracks(
            platformDiscoveryProvider,
            () => container.invalidate(platformDiscoveryProvider),
          );
          // Local history is also on the discovery screen. Its first SQLite
          // emission must arrive before the screen becomes visible.
          final recent = await lease._prime(
            container,
            recentPlaybackProvider,
            () {},
          );
          covers.addAll((recent ?? []).take(2).map((v) => v.track.coverAsset));
          localCovers.addAll(
            (recent ?? []).take(2).map((v) => v.track.coverAsset),
          );
          final favorites = await lease._prime(
            container,
            favoriteTracksProvider,
            () => container.invalidate(favoriteTracksProvider),
          );
          if (favorites?.isNotEmpty == true) {
            localCovers.add(favorites!.first.coverAsset);
          }
        }
        await tracks(
          platformNewSongsProvider,
          () => container.invalidate(platformNewSongsProvider),
        );
        // Top modules go last, so their decoded pixels are available when the
        // native startup surface yields to the routed discovery screen.
        covers.clear();
        await tracks(
          platformDailyProvider,
          () => container.invalidate(platformDailyProvider),
        );
        covers.addAll(localCovers);
        if (container.read(platformAccountProvider).value != null) {
          await tracks(
            platformFmProvider,
            () => container.invalidate(platformFmProvider),
          );
        }
      });
      // Restored playback mounts its capsule after the first app frame. Warm
      // that one saved cover locally too; do not predecode the whole queue or
      // start any audio/network work to obtain it.
      final owner = container.read(activeLibraryOwnerProvider);
      final playback = await container
          .read(appDatabaseProvider)
          .loadPlaybackSession(owner);
      if (playback != null) {
        try {
          final queue = jsonDecode(playback.queueSnapshot) as List;
          if (queue.isNotEmpty) {
            final track = Track.fromJson(
              Map<String, Object?>.from(
                queue[playback.currentIndex.clamp(0, queue.length - 1)] as Map,
              ),
            );
            covers.insert(0, track.coverAsset);
          }
        } on Object {
          /* Invalid playback bytes cannot hide a valid feed. */
        }
      }
      await (artwork ?? artworkRefreshCoordinator).prepareCached({
        'covers': [
          for (final uri in covers.take(12)) {'picUrl': uri},
        ],
      });
    } on Object {
      // Existing account-restoration UI remains authoritative on storage error.
      // An unreadable account is never hydrated using another account's cache.
    }
    return lease;
  }
}
