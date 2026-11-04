import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import '../../core/cache/cached_browse_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/persistence/app_preferences.dart';
import '../../core/platform/distribution_channel.dart';
import '../../shared/models/track.dart';
import '../auth/auth_providers.dart';
import '../auth/data/auth_repository.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/domain/platform_session.dart';
import '../music_platform/platform_backend_providers.dart';
import '../music_platform/netease/netease_library_repository.dart';
import '../music_platform/data/platform_library_repository.dart';
import '../music_platform/data/cloud_library_repository.dart';
import 'data/library_repository.dart';
import 'data/favorite_track_window.dart';
import 'data/playlist_directory_window.dart';
import 'data/library_sync_api.dart';

const _libraryCloudBootstrapPrefix = 'library_cloud_bootstrapped_v2_';
const _libraryCloudLastPullPrefix = 'library_cloud_last_pull_v1_';
const _libraryCloudPullCooldown = Duration(minutes: 15);

Future<void> _bootstrapAndSynchronizeLibrary({
  required AppDatabase database,
  required LibraryRepository repository,
  required String ownerId,
  required SharedPreferences preferences,
}) async {
  final marker = '$_libraryCloudBootstrapPrefix${Uri.encodeComponent(ownerId)}';
  var bootstrappedNow = false;
  if (preferences.getBool(marker) != true) {
    await database.enqueueLibraryCloudBootstrap(ownerId);
    await preferences.setBool(marker, true);
    bootstrappedNow = true;
  }
  final lastPullMillis = preferences.getInt(
    '$_libraryCloudLastPullPrefix${Uri.encodeComponent(ownerId)}',
  );
  final lastPull = lastPullMillis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastPullMillis);
  final shouldPullCloud =
      bootstrappedNow ||
      lastPull == null ||
      DateTime.now().difference(lastPull) >= _libraryCloudPullCooldown;
  final synchronized = await repository.synchronize(forcePull: shouldPullCloud);
  if (shouldPullCloud && synchronized) {
    await preferences.setInt(
      '$_libraryCloudLastPullPrefix${Uri.encodeComponent(ownerId)}',
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final _localPreviewLibraryImportProvider = FutureProvider<void>((ref) async {
  const marker = 'local_preview_library_imported_v1';
  final preferences = ref.watch(sharedPreferencesProvider);
  if (preferences.getBool(marker) == true) return;
  await ref
      .watch(appDatabaseProvider)
      .importLegacyLibraryTo(localPreviewUserId);
  await preferences.setBool(marker, true);
});

final librarySyncApiProvider = Provider<LibrarySyncApi?>((ref) {
  final backend = ref.watch(authBackendKindProvider);
  if (backend == AuthBackendKind.localPreview) {
    return null;
  }
  if (backend == AuthBackendKind.customApi) {
    return CloudBaseLibrarySyncApi(
      apiBaseUrl: ref.watch(authApiBaseUrlProvider),
      actionPath: '/v1/social/actions',
      skipMediaUpload: true,
      sessionProvider: () =>
          ref.read(authControllerProvider.notifier).ensureFreshSession(),
    );
  }
  return CloudBaseLibrarySyncApi(
    environmentId: cloudBaseEnvironmentId,
    sessionProvider: () =>
        ref.read(authControllerProvider.notifier).ensureFreshSession(),
  );
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  if (DistributionChannel.isBeta) {
    final platform = ref.watch(platformAccountProvider).value;
    if (platform?.platform == MusicPlatform.netease) {
      final repository = NeteaseLibraryRepository(
        ref.watch(appDatabaseProvider),
        music: ref.watch(neteaseMusicRepositoryProvider),
        identity: platform!,
      );
      ref.onDispose(repository.dispose);
      return repository;
    }
    if (platform != null) {
      final repository = PlatformLibraryRepository(
        ref.watch(appDatabaseProvider),
        api: ref.watch(musicPlatformApiProvider),
        identity: platform,
      );
      ref.onDispose(repository.dispose);
      return repository;
    }
  }
  final user = ref.watch(currentUserProvider);
  final ownerId = user?.uid ?? legacyLibraryOwnerId;
  final database = ref.watch(appDatabaseProvider);
  if (ownerId == localPreviewUserId) {
    ref.watch(_localPreviewLibraryImportProvider);
  }
  final syncApi = user == null ? null : ref.watch(librarySyncApiProvider);
  final repository = LibraryRepository(
    database,
    ownerId: ownerId,
    syncApi: syncApi,
    canWrite: DistributionChannel.isBeta
        ? () =>
              ref.mounted &&
              user != null &&
              ref.read(currentUserProvider)?.uid == user.uid
        : null,
  );
  ref.onDispose(repository.dispose);
  if (user != null && syncApi != null) {
    unawaited(
      _bootstrapAndSynchronizeLibrary(
        database: database,
        repository: repository,
        ownerId: ownerId,
        preferences: ref.watch(sharedPreferencesProvider),
      ),
    );
  }
  return repository;
});

/// Playback history belongs to the active account without inventing a Mesting
/// user for a platform login. Guests keep their existing local owner.
final activeLibraryOwnerProvider = Provider<String>((ref) {
  if (DistributionChannel.isBeta) {
    final platform = ref.watch(platformAccountProvider).value;
    if (platform != null) return platform.ownerId;
  }
  return ref.watch(currentUserProvider)?.uid ?? legacyLibraryOwnerId;
});

final favoriteTrackWindowProvider = Provider<FavoriteTrackWindow>((ref) {
  final window = FavoriteTrackWindow(ref.watch(libraryRepositoryProvider));
  ref.onDispose(window.dispose);
  return window;
});

final favoriteTracksProvider = StreamProvider<List<Track>>((ref) {
  if (!ref.watch(isAuthenticatedProvider) && !DistributionChannel.isBeta) {
    return Stream.value(const <Track>[]);
  }
  if (!DistributionChannel.isBeta) {
    return ref.watch(libraryRepositoryProvider).watchFavorites();
  }
  return ref.watch(favoriteTrackWindowProvider).stream;
});

/// Complete membership is cheap IDs, never the subset of loaded detail rows.
/// Keep this separate from viewport pagination and its displayed count.
final _favoriteMembershipRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(favoriteTrackWindowProvider).revisions;
});

final completeFavoriteIdsProvider = FutureProvider<Set<String>>((ref) async {
  if (!ref.exists(favoriteTrackWindowProvider)) {
    return {
      for (final track
          in ref.watch(favoriteTracksProvider).value ?? const <Track>[])
        track.id,
    };
  }
  await ref.watch(_favoriteMembershipRevisionProvider.future);
  return ref.watch(libraryRepositoryProvider).favoriteIds();
});

final favoriteTrackIdsProvider = Provider<Set<String>>((ref) {
  final tracks = ref.watch(favoriteTracksProvider).value ?? const <Track>[];
  return {
    ...?ref.watch(completeFavoriteIdsProvider).value,
    ...tracks.map((track) => track.id),
  };
});

final favoriteCollectionCountProvider = Provider<int>((ref) {
  final tracks = ref.watch(favoriteTracksProvider).value ?? const <Track>[];
  return ref.exists(favoriteTrackWindowProvider)
      ? ref.read(favoriteTrackWindowProvider).total ?? tracks.length
      : tracks.length;
});

final playlistsProvider = StreamProvider<List<UserPlaylist>>((ref) {
  if (!ref.watch(isAuthenticatedProvider) && !DistributionChannel.isBeta) {
    return Stream.value(const <UserPlaylist>[]);
  }
  if (!DistributionChannel.isBeta) {
    return ref.watch(libraryRepositoryProvider).watchPlaylists();
  }
  return ref.watch(playlistDirectoryWindowProvider).stream;
});

final playlistDirectoryWindowProvider =
    ChangeNotifierProvider<PlaylistDirectoryWindow>(
      (ref) => PlaylistDirectoryWindow(ref.watch(libraryRepositoryProvider)),
    );

final playlistProvider = FutureProvider.family<UserPlaylist?, String>((
  ref,
  id,
) {
  if (!ref.watch(isAuthenticatedProvider) && !DistributionChannel.isBeta) {
    return null;
  }
  return cachedBrowse(
    ref,
    () => ref.watch(libraryRepositoryProvider).getPlaylist(id),
  );
});

final playlistTracksProvider = StreamProvider.family<List<Track>, String>((
  ref,
  playlistId,
) {
  if (!ref.watch(isAuthenticatedProvider) && !DistributionChannel.isBeta) {
    return Stream.value(const <Track>[]);
  }
  if (!DistributionChannel.isBeta) {
    return ref.watch(libraryRepositoryProvider).watchPlaylistTracks(playlistId);
  }
  final repository = ref.watch(libraryRepositoryProvider);
  // Reordering a local playlist needs its complete ordering; its DB snapshot
  // is cached/decoded separately. Cloud browsing has no implicit full read.
  if (repository is! CloudLibraryRepository) {
    return repository.watchPlaylistTracks(playlistId);
  }
  return ref.watch(playlistTrackWindowProvider(playlistId)).stream;
});

final playlistTrackWindowProvider = Provider.autoDispose
    .family<FavoriteTrackWindow, String>((ref, id) {
      final window = FavoriteTrackWindow(
        ref.watch(libraryRepositoryProvider),
        playlistId: id,
      );
      ref.onDispose(window.dispose);
      return window;
    });
