import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/history/listening_replay.dart';
import 'package:mesting_music/features/local_music/domain/local_music.dart';
import 'package:mesting_music/features/local_music/data/local_music_repository.dart';
import 'package:mesting_music/shared/models/track.dart';

Map<Object?, Object?> _catalog(int count) => {
  'permissionGranted': true,
  'notice': 'synthetic device snapshot',
  'entries': [
    for (var index = 0; index < count; index++)
      {
        'id': 'local_$index',
        'uri': 'content://media/external/audio/media/$index',
        'title': 'Song ${(count - index).toString().padLeft(5, '0')}.flac',
        'artist': index == count - 1 ? 'needle-last' : 'Artist ${index % 64}',
        'album': 'Album ${index % 70}',
        'durationMs': 180000 + index,
        'folderId': 'folder-${index % 32}',
        'folderName': 'Folder ${(index % 32).toString().padLeft(2, '0')}',
        'folderPath': 'Music/${index % 32}',
        'available': index % 13 != 0,
      },
  ],
};

Track _track(int index) => Track(
  id: 'local_$index',
  title: 'History $index',
  artist: 'Artist ${index % 64}',
  album: 'Album',
  duration: const Duration(minutes: 3),
  audioAsset: 'content://media/external/audio/media/$index',
  coverAsset: '',
  lyricsAsset: '',
);

List<PlaybackDailyHistory> _days(int count) => [
  for (var index = 0; index < count; index++)
    PlaybackDailyHistory(
      ownerId: 'synthetic-owner',
      dayKey: '2026-11-${(index % 28 + 1).toString().padLeft(2, '0')}',
      trackId: 'local_$index',
      trackSnapshot: jsonEncode(_track(index).toJson()),
      playCount: index % 3 + 1,
      totalPlayedMs: 60000 + index % 11 * 1000,
      lastPlayedAt: DateTime.utc(2026, 11, index % 28 + 1),
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final count in [3000, 10000]) {
    test('baseline local snapshot and replay $count rows', () {
      final catalog = _catalog(count);
      final days = _days(count);
      final clock = Stopwatch()..start();
      final library = LocalMusicLibrary.fromMap(catalog);
      final parse = clock.elapsedMicroseconds;
      clock.reset();
      final folders = library.folders;
      final repeatedFolders = library.folders;
      expect(identical(folders, repeatedFolders), isTrue);
      final grouping = clock.elapsedMicroseconds;
      clock.reset();
      final matches = library.entries.where(
        (entry) => entry.matches('needle-last'),
      );
      expect(matches.single.id, 'local_${count - 1}');
      final search = clock.elapsedMicroseconds;
      clock.reset();
      final replay = ListeningReplay.fromDays(days, 2026, 11);
      final repeatedReplay = ListeningReplay.fromDays(days, 2026, 11);
      expect(identical(replay, repeatedReplay), isTrue);
      final replayTime = clock.elapsedMicroseconds;
      expect(library.entries, hasLength(count));
      expect(replay.tracks, hasLength(count));
      // ignore: avoid_print
      print(
        'BASELINE147 rows=$count parseUs=$parse folders2Us=$grouping '
        'searchUs=$search replay2Us=$replayTime '
        'folderIdentity=${identical(folders, repeatedFolders)} '
        'replayIdentity=${identical(replay, repeatedReplay)}',
      );
    });
    test(
      'worker prepares complete local and replay snapshots $count rows',
      () async {
        final library = await decodeLocalMusicLibrarySnapshot(_catalog(count));
        expect(library.entries, hasLength(count));
        final cache = LocalMusicViewCache();
        final first = cache.select(library, query: 'needle-last');
        expect(first.entries.single.id, 'local_${count - 1}');
        expect(
          identical(first, cache.select(library, query: 'needle-last')),
          isTrue,
        );
        final days = await preparePlaybackDays(_days(count));
        final replay = ListeningReplay.fromDays(days, 2026, 11);
        expect(replay.tracks, hasLength(count));
        expect(
          identical(replay, ListeningReplay.fromDays(days, 2026, 11)),
          isTrue,
        );
        expect(
          ListeningReplay.fromDays(days, 2026, null).milliseconds,
          replay.milliseconds,
        );
        expect(ListeningReplay.fromDays(days, 2025, null).milliseconds, 0);
      },
    );
  }
}
