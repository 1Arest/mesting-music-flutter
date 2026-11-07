import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';

import 'support/test_tracks.dart';

void main() {
  const ownerId = 'test-user';
  final skipNativeDatabase = Platform.isWindows
      ? 'Windows 测试进程的系统 SQLite 过旧；数据库在 Android 集成测试中验证。'
      : false;

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('favorite state is persisted and removable', () async {
    final track = testTracks.first;

    expect(await database.isFavorite(ownerId, track.id), isFalse);
    await database.setFavorite(ownerId, track, favorite: true);
    expect(await database.isFavorite(ownerId, track.id), isTrue);
    expect(
      (await database.watchFavorites(ownerId).first).single.trackId,
      track.id,
    );

    await database.setFavorite(ownerId, track, favorite: false);
    expect(await database.isFavorite(ownerId, track.id), isFalse);
  }, skip: skipNativeDatabase);

  test(
    'favorite toggle reads and writes the latest state atomically',
    () async {
      final track = testTracks[1];

      expect(await database.toggleFavorite(ownerId, track), isTrue);
      expect(await database.isFavorite(ownerId, track.id), isTrue);
      expect(await database.toggleFavorite(ownerId, track), isFalse);
      expect(await database.isFavorite(ownerId, track.id), isFalse);
    },
    skip: skipNativeDatabase,
  );

  test('playlist keeps snapshots and supports ordering', () async {
    await database.createPlaylist(
      ownerId: ownerId,
      id: 'road-trip',
      name: '公路歌单',
    );
    await database.addTrackToPlaylist(ownerId, 'road-trip', testTracks[0]);
    await database.addTrackToPlaylist(ownerId, 'road-trip', testTracks[1]);

    var rows = await database.watchPlaylistTracks(ownerId, 'road-trip').first;
    expect(rows.map((row) => row.trackId), [
      testTracks[0].id,
      testTracks[1].id,
    ]);

    await database.reorderPlaylistTracks(ownerId, 'road-trip', [
      testTracks[1].id,
      testTracks[0].id,
    ]);
    rows = await database.watchPlaylistTracks(ownerId, 'road-trip').first;
    expect(rows.map((row) => row.trackId), [
      testTracks[1].id,
      testTracks[0].id,
    ]);

    await database.removeTrackFromPlaylist(
      ownerId,
      'road-trip',
      testTracks[1].id,
    );
    rows = await database.watchPlaylistTracks(ownerId, 'road-trip').first;
    expect(rows.single.trackId, testTracks[0].id);
  }, skip: skipNativeDatabase);

  test('personal playlists only accept favorite tracks', () async {
    final repository = LibraryRepository(database, ownerId: ownerId);
    final track = testTracks.first;
    await repository.createPlaylist(id: 'favorites-only', name: '收藏歌单');

    await expectLater(
      repository.addTrackToPlaylist('favorites-only', track),
      throwsA(isA<FavoriteTrackRequiredException>()),
    );
    expect(
      await repository.watchPlaylistTracks('favorites-only').first,
      isEmpty,
    );

    await repository.setFavorite(track, favorite: true);
    await repository.addTrackToPlaylist('favorites-only', track);
    expect(
      (await repository.watchPlaylistTracks('favorites-only').first).single.id,
      track.id,
    );
  }, skip: skipNativeDatabase);

  test('favorites are isolated by account owner', () async {
    final track = testTracks.first;
    await database.setFavorite('user-a', track, favorite: true);

    expect(await database.isFavorite('user-a', track.id), isTrue);
    expect(await database.isFavorite('user-b', track.id), isFalse);
    expect(await database.watchFavorites('user-b').first, isEmpty);
  }, skip: skipNativeDatabase);

  test(
    'legacy favorites can be copied into a signed-in account',
    () async {
      final track = testTracks.first;
      await database.setFavorite(legacyLibraryOwnerId, track, favorite: true);

      expect(await database.countLegacyFavorites(), 1);
      await database.importLegacyLibraryTo(ownerId);

      expect(await database.isFavorite(ownerId, track.id), isTrue);
      expect(await database.isFavorite(legacyLibraryOwnerId, track.id), isTrue);
    },
    skip: skipNativeDatabase,
  );

  test('playback session restores queue, position and mode', () async {
    await database.savePlaybackSession(
      ownerId: ownerId,
      queue: testTracks,
      currentIndex: 3,
      position: const Duration(seconds: 42),
      playbackMode: 'random',
    );

    final session = await database.loadPlaybackSession(ownerId);
    expect(session, isNotNull);
    expect(session!.currentIndex, 3);
    expect(session.positionMs, 42000);
    expect(session.playbackMode, 'random');
  }, skip: skipNativeDatabase);

  test('playback sessions are isolated by account owner', () async {
    await database.savePlaybackSession(
      ownerId: 'user-a',
      queue: [testTracks.first],
      currentIndex: 0,
      position: const Duration(seconds: 12),
      playbackMode: 'list',
    );

    expect(await database.loadPlaybackSession('user-b'), isNull);
    expect((await database.loadPlaybackSession('user-a'))?.positionMs, 12000);
  }, skip: skipNativeDatabase);

  test(
    'playback history keeps a natural-day aggregate for recommendations',
    () async {
      final track = testTracks.first;
      await database.recordPlayback(ownerId, track, Duration.zero);
      await database.addPlaybackDuration(
        ownerId,
        track.id,
        const Duration(seconds: 35),
      );

      final rows = await database
          .watchPlaybackHistoryForDay(ownerId, DateTime.now())
          .first;
      expect(rows, hasLength(1));
      expect(rows.single.trackId, track.id);
      expect(rows.single.playCount, 1);
      expect(rows.single.totalPlayedMs, 35000);
    },
    skip: skipNativeDatabase,
  );

  test(
    'listening ranking only increments explicit completed plays',
    () async {
      final completedTrack = testTracks.first;
      final partialTrack = testTracks[1];
      await database.recordPlayback(ownerId, completedTrack, Duration.zero);
      await database.recordPlayback(ownerId, partialTrack, Duration.zero);

      var ranking = await database.watchListeningRanking(ownerId).first;
      expect(
        ranking
            .firstWhere((row) => row.trackId == completedTrack.id)
            .completedPlayCount,
        0,
      );
      expect(
        ranking
            .firstWhere((row) => row.trackId == partialTrack.id)
            .completedPlayCount,
        0,
      );

      await database.recordCompletedPlayback(ownerId, completedTrack);
      await database.recordCompletedPlayback(ownerId, completedTrack);
      ranking = await database.watchListeningRanking(ownerId).first;

      expect(ranking.first.trackId, completedTrack.id);
      expect(ranking.first.completedPlayCount, 2);
      expect(
        ranking
            .firstWhere((row) => row.trackId == partialTrack.id)
            .completedPlayCount,
        0,
      );
    },
    skip: skipNativeDatabase,
  );

  test(
    'recent playback is de-duplicated and ordered by latest play',
    () async {
      await database.recordPlayback(ownerId, testTracks[0], Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await database.recordPlayback(ownerId, testTracks[1], Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await database.recordPlayback(ownerId, testTracks[0], Duration.zero);

      final recent = await database.watchPlaybackHistory(ownerId).first;
      expect(recent.map((row) => row.trackId), [
        testTracks[0].id,
        testTracks[1].id,
      ]);
      expect(recent.first.playCount, 2);
    },
    skip: skipNativeDatabase,
  );

  test('playback history is isolated by account owner', () async {
    await database.recordPlayback('user-a', testTracks.first, Duration.zero);

    expect(await database.watchPlaybackHistory('user-b').first, isEmpty);
    expect(
      (await database.watchPlaybackHistory('user-a').first).single.trackId,
      testTracks.first.id,
    );
  }, skip: skipNativeDatabase);
}
