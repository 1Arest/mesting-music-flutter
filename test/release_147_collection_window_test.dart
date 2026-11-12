import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/performance/background_json.dart';
import 'package:mesting_music/features/library/data/favorite_track_window.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/music_platform/data/kugou_favorite_index.dart';
import 'package:mesting_music/features/music_platform/data/kugou_playlist_paging.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/models/track_page.dart';
import 'package:mesting_music/features/history/listening_history_providers.dart';

Track _track(int i) => Track(
  id: 'local_$i',
  title: 'Song $i',
  artist: i == 2999 ? 'needle last' : 'artist',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
);

class _Pages extends LibraryRepository {
  _Pages(super.db) : super(ownerId: 'fixture');
  final previews = StreamController<TrackPage>();
  final requests = <int>[];
  Completer<TrackPage>? pending;
  @override
  Stream<TrackPage> watchFavoritePreview() => previews.stream;
  @override
  Future<TrackPage> favoritePage({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async {
    requests.add(offset);
    if (pending != null) return pending!.future;
    final end = (offset + limit).clamp(offset, 95);
    return TrackPage(
      [for (var i = offset; i < end; i++) _track(i)],
      offset: offset,
      nextOffset: end,
      total: 95,
      hasMore: end < 95,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'history SQL pages use complete ordering with an independent full count',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime(2026, 11, 3);
      await db.batch(
        (batch) => batch.insertAll(db.playbackHistories, [
          for (var i = 0; i < 3000; i++)
            PlaybackHistoriesCompanion.insert(
              ownerId: const Value('history-owner'),
              trackId: 'local_$i',
              trackSnapshot: jsonEncode(_track(i).toJson()),
              completedPlayCount: Value(i),
              lastPlayedAt: now.subtract(Duration(seconds: i)),
            ),
        ]),
      );
      final recent = await db.playbackHistoryPage('history-owner');
      expect(recent, hasLength(30));
      expect(recent.first.trackId, 'local_0');
      final next = await db.playbackHistoryPage('history-owner', offset: 30);
      expect(next.first.trackId, 'local_30');
      final rank = await db.playbackHistoryPage('history-owner', ranking: true);
      expect(rank.first.trackId, 'local_2999');
      expect(await db.playbackHistoryCount('history-owner'), 3000);
      expect(await db.playbackHistoryCount('another-owner'), 0);
      expect(
        (await decodeListeningHistory(rank)).first.completedPlayCount,
        2999,
      );
    },
  );
  test(
    'SQL favorites page/search/count/membership include unloaded rows and isolate owners',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime(2026, 11, 3);
      await db.batch(
        (batch) => batch.insertAll(db.favoriteTracks, [
          for (var i = 0; i < 3000; i++)
            FavoriteTracksCompanion.insert(
              ownerId: const Value('owner'),
              trackId: 'local_$i',
              trackSnapshot: jsonEncode(_track(i).toJson()),
              createdAt: now.subtract(Duration(seconds: i)),
              updatedAt: now,
            ),
        ]),
      );
      final repo = LibraryRepository(db, ownerId: 'owner');
      final first = await repo.favoritePage();
      expect(first.items, hasLength(30));
      expect(first.total, 3000);
      expect(first.hasMore, isTrue);
      final hit = await repo.favoritePage(query: 'needle last');
      expect(hit.items.single.id, 'local_2999');
      expect(hit.total, 1);
      expect(hit.hasMore, isFalse);
      expect(await repo.favoriteIds(), contains('local_2999'));
      expect(
        (await LibraryRepository(db, ownerId: 'another').favoritePage()).items,
        isEmpty,
      );
    },
  );

  test(
    'window requests one page, explicit complete keeps all and late disposed results are ignored',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = _Pages(db);
      final window = FavoriteTrackWindow(repo);
      addTearDown(() async {
        await repo.previews.close();
        await db.close();
      });
      final first = window.stream.first;
      repo.previews.add(await repo.favoritePage());
      expect(await first, hasLength(30));
      expect(repo.requests, [0]);
      await window.loadMore();
      expect(window.items, hasLength(60));
      expect(repo.requests, [0, 30]);
      expect(await window.complete(), hasLength(95));
      expect(window.items, hasLength(60));
      final pending = repo.pending = Completer<TrackPage>();
      final load = window.loadMore();
      window.dispose();
      pending.complete(
        TrackPage(
          [_track(94)],
          offset: 60,
          nextOffset: 95,
          total: 95,
          hasMore: false,
        ),
      );
      await load;
      expect(window.items, hasLength(60));
    },
  );

  test(
    'official collecttime orders globally, with stable ties and per-track file IDs',
    () async {
      final index = await buildKugouFavoriteIndex([
        for (var i = 0; i < 3000; i++)
          {
            'hash': 'HASH$i',
            'songname': i == 2999 ? 'newest' : 'old $i',
            'fileid': i + 1,
            'collecttime': 1700000000 + i,
          },
        {
          'hash': 'TIE',
          'songname': 'same-time',
          'fileid': 3001,
          'collecttime': 1700002999,
        },
      ]);
      expect(index.tracks.first.title, 'newest');
      expect(index.tracks[1].id, 'kugou_TIE');
      expect(index.tracks.last.id, 'kugou_HASH0');
      expect(index.fileIds['kugou_HASH2999'], '3000');
    },
  );

  test(
    'remote count/version change cannot mix two collection snapshots',
    () async {
      var version = 1;
      final pager = KugouPlaylistPaging(
        read: (path, query) async => {
          'data': {
            'count': 65,
            'list_ver': version,
            'info': [
              for (var i = 0; i < 30; i++) {'hash': '${query['page']}-$i'},
            ],
          },
        },
        rows: (payload) => ((payload as Map)['data']['info'] as List)
            .cast<Map<String, dynamic>>(),
      );
      expect(
        (await pager.page('/fixture', {}, offset: 0)).items,
        hasLength(30),
      );
      version = 2;
      await expectLater(
        pager.page('/fixture', {}, offset: 30),
        throwsException,
      );
    },
  );

  test('large JSON uses detached values and preserves all records', () async {
    final value = {
      'rows': [
        for (var i = 0; i < 10000; i++) {'id': i, 'text': 'Song $i'},
      ],
    };
    expect(largeJsonValue(value), isTrue);
    final bytes = await encodeJsonBytes(value);
    final decoded = await decodeJsonBytes(bytes) as Map;
    expect(decoded['rows'], hasLength(10000));
    final copied = await copyJsonValueAsync(decoded) as Map;
    (copied['rows'] as List).clear();
    expect(decoded['rows'], hasLength(10000));
  });
}
