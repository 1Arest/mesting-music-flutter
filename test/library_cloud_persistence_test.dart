import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/sync/library_sync_models.dart';

import 'support/test_tracks.dart';

void main() {
  test(
    'cloud snapshot restores playlist cover and playback aggregates',
    () async {
      const ownerId = 'cloud-user';
      final track = testTracks.first;
      final now = DateTime.utc(2026, 7, 26, 12);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      await database.recordPlayback(ownerId, track, Duration.zero);
      await database.addPlaybackDuration(
        ownerId,
        track.id,
        const Duration(seconds: 12),
      );
      await database.recordCompletedPlayback(ownerId, track);
      final pending = await database.pendingLibraryMutations(ownerId);
      expect(
        pending.map((item) => item.entityType),
        containsAll(['playback_history', 'playback_daily_history']),
      );
      expect(
        pending.where((item) => item.entityType == 'playback_history'),
        hasLength(1),
      );

      final snapshot = CloudLibrarySnapshot(
        favorites: const [],
        playlists: [
          CloudPlaylist(
            id: 'playlist-1',
            name: '云端歌单',
            description: '',
            coverAsset: 'https://download.example/cover.png',
            coverCloudId:
                'cloud://music/user-playlist-covers/cloud-user/playlist-1/cover.png',
            createdAt: now,
            updatedAt: now,
            tracks: const [],
          ),
        ],
        playbackHistories: [
          CloudPlaybackHistory(
            track: track,
            playCount: 8,
            completedPlayCount: 5,
            totalPlayedMs: 420000,
            lastPlayedAt: now,
          ),
        ],
        playbackDailyHistories: [
          CloudPlaybackDailyHistory(
            dayKey: '2026-07-26',
            track: track,
            playCount: 3,
            totalPlayedMs: 126000,
            lastPlayedAt: now,
          ),
        ],
        includesPlaybackHistories: true,
        includesPlaybackDailyHistories: true,
      );
      expect(
        await database.completeLibrarySync(
          ownerId,
          acknowledgedMutationIds: pending.map((item) => item.localId),
          snapshot: snapshot,
        ),
        isTrue,
      );

      final playlist = (await database.watchPlaylists(ownerId).first).single;
      expect(playlist.coverAsset, contains('download.example'));
      expect(playlist.coverCloudId, startsWith('cloud://'));
      final history =
          (await database.watchPlaybackHistory(ownerId).first).single;
      expect(history.playCount, 8);
      expect(history.completedPlayCount, 5);
      expect(history.totalPlayedMs, 420000);
      final daily =
          (await database
                  .watchPlaybackHistoryForDay(ownerId, DateTime(2026, 7, 26))
                  .first)
              .single;
      expect(daily.playCount, 3);
      expect(daily.totalPlayedMs, 126000);
    },
    skip: Platform.isWindows
        ? 'Windows 系统 SQLite 缺少 sqlite3_prepare_v3'
        : false,
  );
}
