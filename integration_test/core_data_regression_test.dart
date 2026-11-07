import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/sync/library_sync_models.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/library/data/library_sync_api.dart';

import '../test/support/test_tracks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android 数据库原子切换收藏并按账号隔离', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final track = testTracks[1];

    expect(await database.toggleFavorite('user-a', track), isTrue);
    expect(await database.isFavorite('user-a', track.id), isTrue);
    expect(await database.isFavorite('user-b', track.id), isFalse);
    expect(await database.toggleFavorite('user-a', track), isFalse);
    expect(await database.isFavorite('user-a', track.id), isFalse);

    for (var index = 0; index < 20; index += 1) {
      await database.toggleFavorite('user-a', track);
    }
    expect(await database.isFavorite('user-a', track.id), isFalse);

    await database.savePlaybackSession(
      ownerId: 'user-a',
      queue: [track],
      currentIndex: 0,
      position: const Duration(seconds: 18),
      playbackMode: 'list',
    );
    expect(await database.loadPlaybackSession('user-b'), isNull);
    expect((await database.loadPlaybackSession('user-a'))?.positionMs, 18000);

    await database.recordPlayback('user-a', track, Duration.zero);
    expect(await database.watchPlaybackHistory('user-b').first, isEmpty);
    expect(
      (await database.watchPlaybackHistory('user-a').first).single.trackId,
      track.id,
    );
  });

  testWidgets('收藏和歌单上传云端后可在清空本地数据库后恢复', (tester) async {
    const ownerId = 'cloud-user';
    final track = testTracks.first;
    final now = DateTime.utc(2026, 7, 26, 8);
    final cloudSnapshot = CloudLibrarySnapshot(
      favorites: [
        CloudFavoriteTrack(track: track, createdAt: now, updatedAt: now),
      ],
      playlists: [
        CloudPlaylist(
          id: 'cloud-playlist',
          name: '云端歌单',
          description: '清数据后仍然存在',
          coverAsset: track.coverAsset,
          coverCloudId:
              'cloud://music/user-playlist-covers/cloud-user/cloud-playlist/cover.png',
          createdAt: now,
          updatedAt: now,
          tracks: [
            CloudPlaylistTrack(track: track, sortOrder: 0, addedAt: now),
          ],
        ),
      ],
      playbackHistories: [
        CloudPlaybackHistory(
          track: track,
          playCount: 4,
          completedPlayCount: 3,
          totalPlayedMs: 185000,
          lastPlayedAt: now,
        ),
      ],
      playbackDailyHistories: [
        CloudPlaybackDailyHistory(
          dayKey: '2026-07-26',
          track: track,
          playCount: 2,
          totalPlayedMs: 92000,
          lastPlayedAt: now,
        ),
      ],
      includesPlaybackHistories: true,
      includesPlaybackDailyHistories: true,
    );
    final api = _RecordingLibrarySyncApi(cloudSnapshot);

    final originalDatabase = AppDatabase(NativeDatabase.memory());
    await originalDatabase.setFavorite(ownerId, track, favorite: true);
    await originalDatabase.createPlaylist(
      ownerId: ownerId,
      id: 'cloud-playlist',
      name: '云端歌单',
      description: '清数据后仍然存在',
      coverAsset: track.coverAsset,
    );
    await originalDatabase.addTrackToPlaylist(ownerId, 'cloud-playlist', track);
    await originalDatabase.recordPlayback(ownerId, track, Duration.zero);
    await originalDatabase.recordCompletedPlayback(ownerId, track);
    final preCloudQueue = await originalDatabase.pendingLibraryMutations(
      ownerId,
    );
    await originalDatabase.acknowledgeLibraryMutations(
      ownerId,
      preCloudQueue.map((mutation) => mutation.localId),
    );
    expect(await originalDatabase.countPendingLibraryMutations(ownerId), 0);
    await originalDatabase.enqueueLibraryCloudBootstrap(ownerId);
    final originalRepository = LibraryRepository(
      originalDatabase,
      ownerId: ownerId,
      syncApi: api,
    );

    expect(await originalRepository.synchronize(), isTrue);
    expect(api.calls.single, isNotEmpty);
    expect(
      api.calls.single.map((mutation) => mutation.entityType),
      containsAll([
        'favorite',
        'playlist',
        'playlist_item',
        'playback_history',
        'playback_daily_history',
      ]),
    );
    expect(await originalDatabase.countPendingLibraryMutations(ownerId), 0);
    await originalDatabase.close();

    final clearedDatabase = AppDatabase(NativeDatabase.memory());
    addTearDown(clearedDatabase.close);
    final restoredRepository = LibraryRepository(
      clearedDatabase,
      ownerId: ownerId,
      syncApi: api,
    );

    expect(await restoredRepository.synchronize(), isTrue);
    expect(api.calls.last, isEmpty);
    expect(
      (await restoredRepository.watchFavorites().first).single.id,
      track.id,
    );
    expect(
      (await restoredRepository.watchPlaylists().first).single.name,
      '云端歌单',
    );
    final restoredPlaylist =
        (await restoredRepository.watchPlaylists().first).single;
    expect(restoredPlaylist.coverCloudId, startsWith('cloud://'));
    expect(
      (await restoredRepository.watchPlaylistTracks('cloud-playlist').first)
          .single
          .id,
      track.id,
    );
    final restoredHistory =
        (await clearedDatabase.watchPlaybackHistory(ownerId).first).single;
    expect(restoredHistory.playCount, 4);
    expect(restoredHistory.completedPlayCount, 3);
    expect(restoredHistory.totalPlayedMs, 185000);
    final restoredDaily =
        (await clearedDatabase
                .watchPlaybackHistoryForDay(ownerId, DateTime(2026, 7, 26))
                .first)
            .single;
    expect(restoredDaily.playCount, 2);
    expect(restoredDaily.totalPlayedMs, 92000);
  });
}

class _RecordingLibrarySyncApi implements LibrarySyncApi {
  _RecordingLibrarySyncApi(this.snapshot);

  final CloudLibrarySnapshot snapshot;
  final List<List<LibrarySyncMutation>> calls = [];

  @override
  Future<CloudLibrarySnapshot> synchronize(
    List<LibrarySyncMutation> mutations,
  ) async {
    calls.add(List<LibrarySyncMutation>.from(mutations));
    return snapshot;
  }
}
