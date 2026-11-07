import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_search_catalog.dart';
import 'package:mesting_music/shared/models/track.dart';

const searchId173 = '9d88b93b-80ca-4d2d-a018-390c2a0cf9fd';

Map<String, dynamic> searchTrack173(String id, [String? name]) => {
  'id': id,
  'name': name ?? '歌曲 $id',
  'duration': 180000,
  'artists': [
    {'id': 'artist-1', 'name': '测试歌手'},
  ],
};

Map<String, dynamic> searchResponse173({
  String kind = 'tracks',
  List<Map<String, dynamic>> rows = const [],
  bool more = false,
  String? next,
}) => {
  'status_code': 0,
  'extra': {'search_id': searchId173},
  'result_groups': [
    {'id': kind, 'data': rows, 'has_more': more, 'next_cursor': ?next},
  ],
};

void main() {
  test('search parses grouped track-wrapper and direct track entities', () {
    final page = QishuiSearchCatalog.parseTrackSearch(
      searchResponse173(
        rows: [
          {
            'entity': {
              'track_wrapper': {'track': searchTrack173('one')},
            },
          },
          {
            'entity': {'track': searchTrack173('two')},
          },
          {
            'entity': {'track': searchTrack173('one', '更新后的歌曲名')},
          },
        ],
        more: true,
        next: '20',
      ),
      cursor: '0',
    );
    expect(page.items.map((t) => t.platformSongId), ['one', 'two']);
    expect(page.items.first.title, '更新后的歌曲名');
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, '20');
    expect(page.searchId, searchId173);
  });

  test('search keeps requested entity kind separate from mixed groups', () {
    final root = searchResponse173(
      rows: [
        {
          'entity': {'track': searchTrack173('one')},
        },
      ],
    );
    (root['result_groups'] as List).insert(0, {
      'id': 'artists',
      'has_more': true,
      'next_cursor': '99',
      'data': [
        {
          'entity': {
            'artist': {'id': 'artist-1', 'name': '歌手'},
          },
        },
      ],
    });
    final tracks = QishuiSearchCatalog.parseTrackSearch(root, cursor: '0');
    final artists = QishuiSearchCatalog.parseArtistSearch(root, cursor: '0');
    expect(tracks.items.single.platformSongId, 'one');
    expect(tracks.hasMore, isFalse);
    expect(artists.items.single.id, 'artist-1');
    expect(artists.nextCursor, '99');
  });

  test(
    'artist parser preserves zero and unknown totals without song inference',
    () {
      final page = QishuiSearchCatalog.parseArtistSearch(
        searchResponse173(
          kind: 'artists',
          rows: [
            {
              'entity': {
                'artist': {'id': 'zero', 'name': '零歌曲歌手', 'count_tracks': '0'},
              },
            },
            {
              'entity': {
                'artist': {'id': 'unknown', 'name': '未知数量'},
              },
            },
            {
              'entity': {'track': searchTrack173('not-an-artist')},
            },
          ],
        ),
        cursor: '0',
      );
      expect(page.items.length, 2);
      expect(page.items.first.trackCount, 0);
      expect(page.items.last.trackCount, isNull);
      expect(page.items.first.albumCount, isNull);
    },
  );

  test('named groups of another type do not enter legacy flat parsing', () {
    final page = QishuiSearchCatalog.parseTrackSearch(
      searchResponse173(
        kind: 'artists',
        rows: [
          {
            'entity': {
              'artist': {'id': 'one', 'name': '歌手'},
            },
          },
        ],
      ),
      cursor: '0',
    );
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('unnamed official nullable group supports known requested entities', () {
    final page = QishuiSearchCatalog.parseTrackSearch({
      'result_groups': [
        {
          'data': [
            {
              'entity': {'track': searchTrack173('one')},
            },
          ],
        },
      ],
    }, cursor: '0');
    expect(page.items.single.platformSongId, 'one');
  });

  test('duplicate requested groups fail instead of mixing pagination', () {
    expect(
      () => QishuiSearchCatalog.parseArtistSearch({
        'result_groups': [
          {'id': 'artists'},
          {'id': 'artists'},
        ],
      }, cursor: '0'),
      throwsA(isA<QishuiException>()),
    );
  });

  test('flat legacy rows still parse with data wrapper', () {
    final page = QishuiSearchCatalog.parseTrackSearch({
      'data': {
        'tracks': [searchTrack173('one')],
      },
    }, cursor: '0');
    expect(page.items.single.platformSongId, 'one');
  });

  test(
    'request forwards stable search ID, exact keyword, cursor and cancellation',
    () async {
      final abort = Completer<void>();
      final recorded = <Map<String, Object?>>[];
      final catalog = QishuiSearchCatalog(
        request:
            (
              path, {
              body = const {},
              query = const {},
              get = false,
              abortTrigger,
            }) async {
              recorded.add({
                'path': path,
                'get': get,
                'query': query,
                'body': body,
                'abort': identical(abortTrigger, abort.future),
              });
              return searchResponse173(
                kind: path.endsWith('/artist') ? 'artists' : 'tracks',
              );
            },
      );
      await catalog.searchTracks(
        ' 天空 & moon ',
        searchId: searchId173,
        abortTrigger: abort.future,
      );
      await catalog.searchArtists(
        '天空 & moon',
        cursor: '20',
        searchId: searchId173,
      );
      expect(recorded.first['path'], '/luna/search/track');
      expect(recorded.last['path'], '/luna/search/artist');
      expect(recorded.first['get'], isTrue);
      expect(recorded.first['body'], isEmpty);
      expect(recorded.first['abort'], isTrue);
      final query = recorded.first['query'] as Map<String, String>;
      expect(query['q'], '天空 & moon');
      expect(query['cursor'], '0');
      expect(query['search_id'], searchId173);
      expect(query['search_method'], 'input');
      expect(query.keys, isNot(contains('cookie')));
      expect((recorded.last['query'] as Map)['cursor'], '20');
    },
  );

  test('query validation happens before transport', () async {
    var requests = 0;
    final catalog = QishuiSearchCatalog(
      request:
          (
            path, {
            body = const {},
            query = const {},
            get = false,
            abortTrigger,
          }) async {
            requests++;
            return {};
          },
    );
    for (final keyword in ['', 'bad\nquery', '长' * 200]) {
      await expectLater(
        catalog.searchTracks(keyword, searchId: searchId173),
        throwsA(isA<QishuiException>()),
      );
    }
    expect(requests, 0);
  });

  test('search IDs are per-operation UUIDs instead of account identifiers', () {
    final first = QishuiSearchCatalog.newSearchId();
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(QishuiSearchCatalog.newSearchId(), isNot(first));
  });

  test(
    'empty middle page continues and duplicate rows preserve stable order',
    () {
      final rows = QishuiCatalogAccumulator<String>(keyOf: (s) => s);
      rows.accept(
        QishuiCatalogPage(
          items: ['one'],
          cursor: '0',
          hasMore: true,
          nextCursor: '20',
        ),
      );
      rows.accept(
        QishuiCatalogPage(
          items: [],
          cursor: '20',
          hasMore: true,
          nextCursor: '40',
        ),
      );
      expect(rows.hasMore, isTrue);
      expect(rows.nextCursor, '40');
      rows.accept(QishuiCatalogPage(items: ['one', 'two'], cursor: '40'));
      expect(rows.items, ['one', 'two']);
      expect(rows.hasMore, isFalse);
    },
  );

  test('repeated cursor stops while retaining newly received usable rows', () {
    final rows = QishuiCatalogAccumulator<String>(keyOf: (s) => s);
    rows.accept(
      QishuiCatalogPage(
        items: ['one'],
        cursor: '0',
        hasMore: true,
        nextCursor: '20',
      ),
    );
    rows.accept(
      QishuiCatalogPage(
        items: ['two'],
        cursor: '20',
        hasMore: true,
        nextCursor: '0',
      ),
    );
    expect(rows.items, ['one', 'two']);
    expect(rows.hasMore, isFalse);
    expect(rows.continuationProblem, isNotNull);
  });

  test(
    'missing continuation is explicit and does not claim all rows were loaded',
    () {
      final page = QishuiSearchCatalog.parseTrackSearch(
        searchResponse173(
          rows: [
            {
              'entity': {'track': searchTrack173('one')},
            },
          ],
          more: true,
        ),
        cursor: '0',
      );
      final rows = QishuiCatalogAccumulator<Track>(keyOf: (t) => t.id)
        ..accept(page);
      expect(rows.items, hasLength(1));
      expect(rows.hasMore, isFalse);
      expect(rows.continuationProblem, isNotNull);
    },
  );

  test('wrong page cannot replace a current accumulator', () {
    final rows = QishuiCatalogAccumulator<String>(keyOf: (s) => s);
    expect(
      () => rows.accept(QishuiCatalogPage(items: ['old'], cursor: '20')),
      throwsA(isA<QishuiException>()),
    );
    expect(rows.items, isEmpty);
  });

  test('bounded page count stops duplicate-only pages with fresh cursors', () {
    final rows = QishuiCatalogAccumulator<String>(keyOf: (s) => s);
    for (var i = 0; i < 1000; i++) {
      rows.accept(
        QishuiCatalogPage(
          items: ['one'],
          cursor: '$i',
          hasMore: true,
          nextCursor: '${i + 1}',
        ),
      );
    }
    expect(rows.pageCount, 1000);
    expect(rows.items, ['one']);
    expect(rows.hasMore, isFalse);
    expect(rows.continuationProblem, contains('上限'));
  });

  test('artist details verify ID and keep explicit count semantics', () async {
    final catalog = QishuiSearchCatalog(
      request:
          (
            path, {
            body = const {},
            query = const {},
            get = false,
            abortTrigger,
          }) async => {
            'artist_info': {
              'id': 'artist-1',
              'name': '完整歌手名',
              'count_tracks': '65',
              'count_albums': 0,
            },
          },
    );
    final artist = await catalog.artistDetail('artist-1');
    expect(artist.trackCount, 65);
    expect(artist.albumCount, 0);
    await expectLater(
      catalog.artistDetail('different'),
      throwsA(isA<QishuiException>()),
    );
  });

  test('artist ID cannot inject another route', () async {
    var requests = 0;
    final catalog = QishuiSearchCatalog(
      request:
          (
            path, {
            body = const {},
            query = const {},
            get = false,
            abortTrigger,
          }) async {
            requests++;
            return {};
          },
    );
    await expectLater(
      catalog.artistDetail('../me'),
      throwsA(isA<QishuiException>()),
    );
    await expectLater(
      catalog.artistTracks('artist?other=1'),
      throwsA(isA<QishuiException>()),
    );
    expect(requests, 0);
  });

  test('PC artist works use exact GET and fixed page offsets', () async {
    final recorded = <Map<String, Object?>>[];
    final catalog = QishuiSearchCatalog(
      request:
          (
            path, {
            body = const {},
            query = const {},
            get = false,
            abortTrigger,
          }) async {
            recorded.add({'path': path, 'query': query, 'get': get});
            return {
              'tracks': [searchTrack173('one')],
              'has_more': true,
            };
          },
    );
    final page = await catalog.artistTracks('artist-1', cursor: '50');
    expect(recorded.single['path'], '/luna/artists/artist-1/tracks');
    expect(recorded.single['get'], isTrue);
    expect(recorded.single['query'], {'cursor': '50', 'count': '50'});
    expect(page.nextCursor, '100');
    expect(page.items, hasLength(1));
  });

  test(
    'artist metadata merge rejects a different artist and preserves missing values',
    () {
      const old = QishuiArtist(
        id: 'one',
        name: '歌手',
        trackCount: 65,
        artwork: 'https://example.test/cover',
      );
      final merged = old.merge(
        const QishuiArtist(id: 'one', name: '新名字', albumCount: 0),
      );
      expect(merged.trackCount, 65);
      expect(merged.albumCount, 0);
      expect(merged.artwork, old.artwork);
      expect(
        () => old.merge(const QishuiArtist(id: 'two', name: '其他人')),
        throwsA(isA<QishuiException>()),
      );
    },
  );
}
