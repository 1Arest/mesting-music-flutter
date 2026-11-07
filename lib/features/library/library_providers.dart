import '../music_platform/qishui/qishui_library_repository.dart';
import '../music_platform/qishui/qishui_providers.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import '../../core/cache/cached_browse_provider.dart';

import '../../core/database/app_database.dart';
import '../../core/platform/distribution_channel.dart';
import '../../shared/models/track.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/domain/platform_session.dart';
import '../music_platform/platform_backend_providers.dart';
import '../music_platform/netease/netease_library_repository.dart';
import '../music_platform/data/platform_library_repository.dart';
import '../music_platform/data/cloud_library_repository.dart';
import 'data/library_repository.dart';
import 'data/favorite_track_window.dart';
import 'data/playlist_directory_window.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  {
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
    if (platform?.platform == MusicPlatform.qishui) {
      final repository = QishuiLibraryRepository(
        ref.watch(appDatabaseProvider),
        music: ref.watch(qishuiRepositoryProvider),
        owner: platform!.ownerId,
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
  // The guest owner is the existing local namespace. Do not migrate, merge
  // or delete rows belonging to another identity during source retirement.
  final repository = LibraryRepository(
    ref.watch(appDatabaseProvider),
    ownerId: legacyLibraryOwnerId,
    canWrite: () => false,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Playback history belongs to the active account without inventing a Mesting
/// user for a platform login. Guests keep their existing local owner.
final activeLibraryOwnerProvider = Provider<String>((ref) {
  {
    final platform = ref.watch(platformAccountProvider).value;
    if (platform != null) return platform.ownerId;
  }
  return legacyLibraryOwnerId;
});

final favoriteTrackWindowProvider = Provider<FavoriteTrackWindow>((ref) {
  final window = FavoriteTrackWindow(ref.watch(libraryRepositoryProvider));
  ref.onDispose(window.dispose);
  return window;
});

final favoriteTracksProvider = StreamProvider<List<Track>>((ref) {
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
  return cachedBrowse(
    ref,
    () => ref.watch(libraryRepositoryProvider).getPlaylist(id),
  );
});

final playlistTracksProvider = StreamProvider.family<List<Track>, String>((
  ref,
  playlistId,
) {
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
