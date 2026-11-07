import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/app/mesting_music_app.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/playback_persistence_controller.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/history/listening_replay.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'support/test_tracks.dart';

class _OwnerRecorder extends PlaybackPersistenceController {
  _OwnerRecorder(AppDatabase db)
    : super(
        database: db,
        audioHandler: MestingAudioHandler(tracks: []),
      );
  final owners = <String>[];
  @override
  Future<void> activateOwner(String ownerId) async {
    owners.add(ownerId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlaybackDailyHistory day(
    String date,
    int index,
    int minutes, {
    String? snapshot,
  }) => PlaybackDailyHistory(
    ownerId: 'owner',
    dayKey: date,
    trackId: testTracks[index].id,
    trackSnapshot: snapshot ?? jsonEncode(testTracks[index].toJson()),
    playCount: 1,
    totalPlayedMs: minutes * 60000,
    lastPlayedAt: DateTime.parse(date),
  );

  test(
    'replay sums real calendar days, without assigning legacy totals to months',
    () {
      final records = [
        day('2026-09-30', 0, 10),
        day('2026-10-01', 0, 7),
        day('2026-10-25', 0, 8),
        day('2026-10-25', 1, 5),
        day('2025-10-25', 1, 90),
      ];
      final month = ListeningReplay.fromDays(records, 2026, 10);
      expect(month.milliseconds, 20 * 60000);
      expect(month.tracks.first.track.id, testTracks[0].id);
      expect(month.tracks.first.plays, 2);
      expect(
        ListeningReplay.fromDays(records, 2026, null).milliseconds,
        30 * 60000,
      );
      expect(ListeningReplay.fromDays(records, 2026, 1).tracks, isEmpty);
    },
  );

  test('replay periods follow January, October, December and past years', () {
    expect(replayMonthsForYear(2026, DateTime(2026, 1, 3)), [null, 1]);
    expect(replayMonthsForYear(2026, DateTime(2026, 10, 26)), [
      null,
      ...List.generate(10, (i) => i + 1),
    ]);
    expect(replayMonthsForYear(2025, DateTime(2026, 1, 3)).length, 13);
    expect(replayMonthsForYear(2026, DateTime(2026, 12, 31)).length, 13);
    expect(replayMonthsForYear(2027, DateTime(2026, 12, 31)), [null]);
  });

  test(
    'obsolete snapshots retain total listening time without hiding valid rankings',
    () {
      final result = ListeningReplay.fromDays(
        [
          day('2026-10-01', 0, 6, snapshot: '{bad'),
          day('2026-10-02', 1, 4),
          day('2026-10-03', 1, -2),
        ],
        2026,
        10,
      );
      expect(result.milliseconds, 10 * 60000);
      expect(result.tracks.single.milliseconds, 4 * 60000);
    },
  );

  test(
    'daily storage keeps Kugou, Mesting and guest histories independent',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.recordPlayback(
        'kugou:7',
        testTracks[0],
        const Duration(minutes: 3),
      );
      await db.recordPlayback(
        'mesting-user',
        testTracks[1],
        const Duration(minutes: 5),
      );
      await db.recordPlayback(
        legacyLibraryOwnerId,
        testTracks[2],
        const Duration(minutes: 2),
      );
      for (final owner in ['kugou:7', 'mesting-user', legacyLibraryOwnerId]) {
        final days = await db.watchPlaybackDays(owner).first;
        expect(days, hasLength(1));
        expect(days.single.ownerId, owner);
      }
    },
  );

  test('owner binding activates a guest on the first subscription', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final recorder = _OwnerRecorder(db);
    final container = ProviderContainer(
      overrides: [
        playbackPersistenceControllerProvider.overrideWithValue(recorder),
        activeLibraryOwnerProvider.overrideWithValue(legacyLibraryOwnerId),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    container.read(playbackOwnerBindingProvider);
    expect(recorder.owners, [legacyLibraryOwnerId]);
  });
}
