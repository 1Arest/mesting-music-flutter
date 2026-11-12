import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'support/test_tracks.dart';

class _RetainedStore implements PlatformSessionStore {
  PlatformSession? session = const PlatformSession(
    userId: 'retained',
    token: 'fixture',
  );
  int reads = 0, writes = 0, clears = 0;
  @override
  Future<PlatformSession?> read() async {
    reads++;
    return session;
  }

  @override
  Future<void> write(PlatformSession value) async {
    writes++;
    session = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    session = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'retired saved choice becomes guest without activating or clearing retained credentials',
    () async {
      SharedPreferences.setMockInitialValues({
        BetaAccountChoiceController.preferenceKey: 'mesting',
        'mesting_first_launch_auth_completed_v1': true,
        'unrelated_local_preference': 'preserve',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = _RetainedStore();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          platformSessionStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(betaAccountChoiceProvider),
        BetaAccountChoice.guest,
      );
      expect(await container.read(platformAccountProvider.future), isNull);
      expect(container.read(activeLibraryOwnerProvider), legacyLibraryOwnerId);
      expect([store.reads, store.writes, store.clears], [0, 0, 0]);
      expect(store.session?.userId, 'retained');
      expect(preferences.getString('unrelated_local_preference'), 'preserve');
      expect(
        preferences.getBool('mesting_first_launch_auth_completed_v1'),
        isTrue,
      );
    },
  );

  test(
    'current three-platform selections retain their exact persisted names',
    () async {
      for (final choice in [
        BetaAccountChoice.kugou,
        BetaAccountChoice.netease,
        BetaAccountChoice.qishui,
      ]) {
        SharedPreferences.setMockInitialValues({
          BetaAccountChoiceController.preferenceKey: choice.name,
        });
        final preferences = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        );
        expect(container.read(betaAccountChoiceProvider), choice);
        expect(
          preferences.getString(BetaAccountChoiceController.preferenceKey),
          choice.name,
        );
        container.dispose();
      }
    },
  );

  test(
    'local rows survive database reopen by owner, without a retired cloud journal',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting175-local-',
      );
      final file = File('${directory.path}/library.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        // Only remove the exact private directory this test created.
        expect(
          directory.absolute.path.startsWith(
            Directory.systemTemp.absolute.path,
          ),
          isTrue,
        );
        await directory.delete(recursive: true);
      });
      final owners = [
        legacyLibraryOwnerId,
        'kugou:fixture',
        'netease:fixture',
        'qishui:fixture',
      ];
      for (var i = 0; i < owners.length; i++) {
        final track = testTracks[i];
        final repository = LibraryRepository(database, ownerId: owners[i]);
        await repository.setFavorite(track, favorite: true);
        await repository.createPlaylist(id: 'same-id', name: 'owner$i');
        await repository.addTrackToPlaylist('same-id', track);
        await database.recordPlayback(
          owners[i],
          track,
          const Duration(seconds: 8),
        );
        await database.addPlaybackDuration(
          owners[i],
          track.id,
          const Duration(seconds: 2),
        );
        await database.savePlaybackSession(
          ownerId: owners[i],
          queue: [track],
          currentIndex: 0,
          position: const Duration(seconds: 5),
          playbackMode: 'list',
        );
        repository.dispose();
      }
      expect(await database.select(database.syncMutations).get(), isEmpty);
      await database.close();
      database = AppDatabase(NativeDatabase(file));
      for (var i = 0; i < owners.length; i++) {
        final repository = LibraryRepository(database, ownerId: owners[i]);
        expect(
          (await repository.watchFavorites().first).single.id,
          testTracks[i].id,
        );
        expect(
          (await repository.watchPlaylists().first).single.name,
          'owner$i',
        );
        expect(
          (await repository.watchPlaylistTracks('same-id').first).single.id,
          testTracks[i].id,
        );
        expect(
          (await database.loadPlaybackSession(owners[i]))?.positionMs,
          5000,
        );
        expect(
          (await database.watchPlaybackHistory(owners[i]).first)
              .single
              .totalPlayedMs,
          10000,
        );
        repository.dispose();
      }
      expect(await database.select(database.syncMutations).get(), isEmpty);
    },
  );
}
