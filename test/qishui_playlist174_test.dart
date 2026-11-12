import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playlist_paging.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_search_catalog.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'qishui_search173_test.dart' show searchTrack173;
import 'qishui_signed_api167_test.dart' show account;

class _PlaylistReader174 extends QishuiRepository {
  _PlaylistReader174(this.readPage, {this.cache})
    : super(
        QishuiApi(MockClient((_) async => throw StateError('no live request')))
          ..configure(account()),
      );

  final Future<Map<String, dynamic>> Function(String cursor) readPage;
  final BrowseResponseCache? cache;
  final requested = <String>[];
  final counts = <Object?>[];

  @override
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    bool get = false,
    bool write = false,
    Future<void>? abortTrigger,
  }) {
    expect(path, '/luna/playlist/detail');
    expect(write, isFalse);
    final cursor = '${body['cursor'] ?? ''}';
    requested.add(cursor);
    counts.add(body['count']);
    return cache?.read(
          scope: 'synthetic174',
          route: path,
          query: body,
          load: () => readPage(cursor),
          checkCurrent: () {},
        ) ??
        readPage(cursor);
  }
}

Map<String, dynamic> _page174(
  List<String> ids, {
  bool more = false,
  String next = '',
  String playlist = 'list174',
}) => {
  'playlist': {'id': playlist},
  'tracks': ids.map(searchTrack173).toList(),
  'has_more': more,
  'next_cursor': next,
};

QishuiCatalogPage<Track> _typed174(
  String cursor,
  List<String> ids, {
  bool more = false,
  String? next,
}) => QishuiCatalogPage(
  cursor: cursor,
  items: ids
      .map(
        (id) => Track(
          id: 'qishui_$id',
          platformSongId: id,
          title: 'synthetic-$id',
          artist: '',
          album: '',
          duration: Duration.zero,
          audioAsset: '',
          coverAsset: '',
          lyricsAsset: '',
          source: TrackSource.qishui,
        ),
      )
      .toList(),
  hasMore: more,
  nextCursor: next,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first page makes one bounded request; explicit full read enumerates all',
    () async {
      final music = _PlaylistReader174(
        (cursor) async => cursor.isEmpty
            ? _page174(['1', '2'], more: true, next: 'after-first')
            : _page174(['2', '3']),
      );
      addTearDown(music.api.dispose);
      final first = await music.playlistPage('list174');
      expect(first.items.map((t) => t.platformSongId), ['1', '2']);
      expect(first.hasMore, isTrue);
      expect(music.requested, ['']);
      expect(music.counts, [100]);
      music.requested.clear();
      final full = await music.playlist('list174');
      expect(full.map((t) => t.platformSongId), ['1', '2', '3']);
      expect(music.requested, ['', 'after-first']);
    },
  );

  test(
    'mismatched playlist and invalid cursors cannot become a complete collection',
    () async {
      final mismatch = _PlaylistReader174(
        (_) async => _page174(['1'], playlist: 'other-owner-list'),
      );
      addTearDown(mismatch.api.dispose);
      await expectLater(
        mismatch.playlistPage('list174'),
        throwsA(isA<QishuiException>()),
      );
      final loop = _PlaylistReader174(
        (cursor) async =>
            _page174(['1'], more: true, next: cursor.isEmpty ? 'loop' : cursor),
      );
      addTearDown(loop.api.dispose);
      await expectLater(
        loop.playlist('list174'),
        throwsA(isA<QishuiException>()),
      );
      expect(loop.requested, ['', 'loop']);
      await expectLater(
        loop.playlistPage('list174', count: 101),
        throwsA(isA<QishuiException>()),
      );
      expect(loop.requested, ['', 'loop']);
    },
  );

  test(
    'presentation waits for viewport demand and coalesces next-page demand',
    () async {
      final calls = <String>[];
      final second = Completer<QishuiCatalogPage<Track>>();
      final pager = QishuiPlaylistPaging(
        request: (cursor, _) async {
          calls.add(cursor);
          return cursor.isEmpty
              ? _typed174('', ['1', '2'], more: true, next: 'next')
              : second.future;
        },
        current: () => true,
        pageAbort: Completer<void>().future,
      );
      addTearDown(pager.dispose);
      await pager.reload();
      expect(calls, ['']);
      expect(pager.items.length, 2);
      final demand = pager.loadMore();
      await pager.loadMore();
      expect(calls, ['', 'next']);
      expect(pager.items.length, 2);
      second.complete(_typed174('next', ['2', '3']));
      await demand;
      expect(pager.items.map((t) => t.platformSongId), ['1', '2', '3']);
      expect(pager.complete, isTrue);
    },
  );

  test(
    'refresh cancels an old generation without discarding visible data on failure',
    () async {
      var active = true;
      final first = Completer<QishuiCatalogPage<Track>>();
      final fresh = Completer<QishuiCatalogPage<Track>>();
      var calls = 0;
      var cancelled = false;
      final pager = QishuiPlaylistPaging(
        request: (cursor, abort) {
          calls++;
          if (calls == 1) {
            unawaited(abort.then((_) => cancelled = true));
            return first.future;
          }
          return fresh.future;
        },
        current: () => active,
        pageAbort: Completer<void>().future,
      );
      addTearDown(pager.dispose);
      final initial = pager.reload();
      final refresh = pager.reload();
      fresh.complete(_typed174('', ['new']));
      await refresh;
      first.complete(_typed174('', ['old']));
      await initial;
      expect(cancelled, isTrue);
      expect(pager.items.single.platformSongId, 'new');
      active = false;
      await pager.loadMore();
      expect(calls, 2);
    },
  );

  test('a later page error keeps the first page usable', () async {
    final pager = QishuiPlaylistPaging(
      request: (cursor, _) async => cursor.isEmpty
          ? _typed174('', ['1'], more: true, next: 'next')
          : throw const QishuiException('synthetic offline'),
      current: () => true,
      pageAbort: Completer<void>().future,
    );
    addTearDown(pager.dispose);
    await pager.reload();
    await pager.loadMore();
    expect(pager.items.single.platformSongId, '1');
    expect(pager.error, 'synthetic offline');
    expect(pager.complete, isFalse);
  });

  test(
    'cached first page displays immediately and changed continuation removes the obsolete tail',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting-playlist174-',
      );
      final cache = BrowseResponseCache(
        directory: () async => directory,
        initializeOnRead: true,
      );
      var fresh = false;
      final incoming = Completer<Map<String, dynamic>>();
      final music = _PlaylistReader174((cursor) async {
        if (cursor.isEmpty) {
          return fresh
              ? incoming.future
              : _page174(['1'], more: true, next: 'old-next');
        }
        return _page174(['2']);
      }, cache: cache);
      final pager = QishuiPlaylistPaging(
        request: (cursor, abort) =>
            music.playlistPage('list174', cursor: cursor, abortTrigger: abort),
        current: () => true,
        pageAbort: Completer<void>().future,
      );
      try {
        await pager.reload();
        await pager.loadMore();
        expect(pager.items.map((t) => t.platformSongId), ['1', '2']);
        fresh = true;
        cache.revalidateScope('synthetic174');
        await pager.reload();
        expect(pager.items.map((t) => t.platformSongId), ['1', '2']);
        final published = Completer<void>();
        pager.addListener(() {
          if (pager.items.firstOrNull?.platformSongId == '9' &&
              !published.isCompleted) {
            published.complete();
          }
        });
        incoming.complete(_page174(['9'], more: true, next: 'new-next'));
        await published.future.timeout(const Duration(seconds: 3));
        expect(pager.items.map((t) => t.platformSongId), ['9']);
        expect(pager.hasMore, isTrue);
        expect(pager.complete, isFalse);
        expect(music.requested, ['', 'old-next', '', '']);
      } finally {
        pager.dispose();
        music.api.dispose();
        await cache.settleRefreshes('synthetic174');
        await cache.invalidateScope('synthetic174');
        expect(
          directory.parent.absolute.path,
          Directory.systemTemp.absolute.path,
        );
        expect(
          directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
          startsWith('mesting-playlist174-'),
        );
        await directory.delete(recursive: true);
      }
    },
  );
}
