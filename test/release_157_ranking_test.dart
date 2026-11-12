import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/music_platform/data/platform_library_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_ranking.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/models/track_page.dart';
import 'release_148_data_test.dart' show Metadata148;

const rank157 = PlatformExploreItem(
  id: '8888',
  title: '测试榜',
  cover: '',
  kind: PlatformExploreKind.rank,
);
const owner157 = PlatformSession(userId: '7', token: 'synthetic-only');

class Server157 implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:15700');
}

Track song157(int n) => Track(
  id: 'kugou_${n.toRadixString(16).padLeft(32, '0')}',
  title: '测试歌曲 $n',
  artist: '样本歌手',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'mesting-platform://kugou/$n',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.kugou,
  platformSongId: '${1000 + n}',
);
MusicPlatformApi api157(Future<http.Response> Function(http.Request) reply) =>
    MusicPlatformApi(server: Server157(), client: MockClient(reply))
      ..session = owner157;
http.Response reply157(Map<String, Object?> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Pages extends PlatformExploreRepository {
  _Pages(super.api, this.read);
  final Future<TrackPage> Function(PlatformExploreItem, int) read;
  @override
  Future<TrackPage> tracksPage(
    PlatformExploreItem item, {
    int offset = 0,
    int limit = 30,
  }) => read(item, offset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Kugou paging follows raw source rows when one song record is incomplete',
    () async {
      final api = api157(
        (_) async => reply157({
          'status': 1,
          'data': {
            'total': 31,
            'songlist': [
              for (var n = 0; n < 29; n++)
                {
                  'hash': n.toRadixString(16).padLeft(32, '0'),
                  'songname': '测试$n',
                },
              {'songname': '缺少录音标识'},
            ],
          },
        }),
      );
      final page = await PlatformExploreRepository(api).tracksPage(rank157);
      expect(page.items.length, 29);
      expect(page.nextOffset, 30);
      expect(page.hasMore, isTrue);
      expect(page.total, 31);
    },
  );
  test(
    'Play All walks the whole chart in order and preserves the selected edition',
    () async {
      final api = api157((_) async => reply157({'status': 1}));
      final repository = PlatformRankingRepository(
        api: api,
        owner: owner157,
        isCurrent: () => true,
      );
      final pages = <int>[];
      final all = await repository.complete(
        _Pages(api, (item, offset) async {
          pages.add(offset);
          expect(item.rankCid, '42');
          final end = (offset + 30).clamp(0, 77);
          return TrackPage(
            [for (var n = offset; n < end; n++) song157(n)],
            offset: offset,
            nextOffset: end,
            total: 77,
            hasMore: end < 77,
          );
        }),
        const PlatformExploreItem(
          id: '8888',
          title: '测试榜',
          cover: '',
          kind: PlatformExploreKind.rank,
          rankCid: '42',
        ),
      );
      expect(pages, [0, 30, 60]);
      expect(all.map((t) => t.id), [
        for (var n = 0; n < 77; n++) song157(n).id,
      ]);
    },
  );
  test(
    'repeated pages fail rather than presenting a partial chart as complete',
    () async {
      final api = api157((_) async => reply157({'status': 1}));
      final repository = PlatformRankingRepository(
        api: api,
        owner: owner157,
        isCurrent: () => true,
      );
      await expectLater(
        repository.complete(
          _Pages(
            api,
            (_, offset) async => TrackPage(
              [song157(1)],
              offset: offset,
              nextOffset: offset + 1,
              hasMore: true,
            ),
          ),
          rank157,
        ),
        throwsA(isA<MusicPlatformException>()),
      );
    },
  );
  test(
    'account change rejects a late complete chart before a caller can play it',
    () async {
      final api = api157((_) async => reply157({'status': 1}));
      var current = true;
      final pending = Completer<TrackPage>();
      final operation = PlatformRankingRepository(
        api: api,
        owner: owner157,
        isCurrent: () => current,
      ).complete(_Pages(api, (_, _) => pending.future), rank157);
      current = false;
      pending.complete(
        TrackPage([song157(1)], offset: 0, nextOffset: 1, hasMore: false),
      );
      await expectLater(operation, throwsA(isA<MusicPlatformException>()));
    },
  );
  test(
    'NetEase chart uses its real playlist identifier, counts and subscription route',
    () async {
      final api = api157((_) async => reply157({'status': 1}));
      final music = Metadata148(
        (route, query) async => route == '/playlist/detail'
            ? {
                'playlist': {
                  'trackCount': 200,
                  'subscribedCount': 13234000,
                  'commentCount': 319000,
                  'shareCount': 67679,
                  'subscribed': true,
                  'description': '平台榜单',
                },
              }
            : {'code': 200},
      );
      final repository = PlatformRankingRepository(
        api: api,
        owner: const PlatformSession(
          userId: '7',
          token: 'synthetic-only',
          platform: MusicPlatform.netease,
        ),
        isCurrent: () => true,
        netease: music,
      );
      final info = await repository.info(rank157);
      expect(info.total, 200);
      expect(info.subscribed, isTrue);
      expect(info.comments, 319000);
      await repository.subscribe(rank157, false);
      expect(music.calls.last.$1, '/playlist/subscribe');
      expect(music.calls.last.$2, {'id': '8888', 'subscribe': false});
      expect(info.shareUri.host, 'music.163.com');
    },
  );
  test(
    'Kugou metadata preserves edition without guessing a playlist or comment ID',
    () async {
      final api = api157((r) async {
        expect(r.url.queryParameters['rankid'], '8888');
        return reply157({
          'status': 1,
          'data': {'rankname': '测试榜', 'rank_cid': 42, 'intro': '每日更新'},
        });
      });
      final info = await PlatformRankingRepository(
        api: api,
        owner: owner157,
        isCurrent: () => true,
      ).info(rank157);
      expect(info.period, '42');
      expect(info.comments, isNull);
      expect(
        info.snapshotName(DateTime(2026, 11, 5)),
        '测试榜 · 2026-11-05 · 第42期',
      );
      expect(info.shareUri.path, '/yy/rank/home/1-8888.html');
    },
  );

  for (final ambiguous in [false, true]) {
    test(
      'cloud chart snapshot ${ambiguous ? 'reconciles a lost reply without repeating it' : 'saves complete content and never duplicates a retry'}',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        var created = false, creates = 0, writes = 0;
        String name = '';
        final songs = <String, Map<String, Object?>>{};
        final api = api157((r) async {
          final q = r.url.queryParameters;
          switch (r.url.path) {
            case '/user/playlist':
              return reply157({
                'status': 1,
                'data': {
                  'info': [
                    if (created)
                      {
                        'listid': 9,
                        'name': name,
                        'type': 0,
                        'source': 1,
                        'list_create_userid': 7,
                        'global_collection_id': 'collection_fixture',
                      },
                  ],
                },
              });
            case '/playlist/add':
              created = true;
              creates++;
              name = q['name']!;
              return reply157({'status': 1});
            case '/playlist/track/all/new':
              return reply157({
                'status': 1,
                'data': {'songs': songs.values.toList()},
              });
            case '/playlist/tracks/add':
              writes++;
              for (final record in q['data']!.split(',')) {
                final fields = record.split('|');
                songs[fields[1]] = {
                  'hash': fields[1],
                  'songname': fields[0],
                  'singername': '样本歌手',
                  'mixsongid': fields[3],
                };
              }
              if (ambiguous && writes == 1) {
                throw TimeoutException('synthetic lost reply');
              }
              return reply157({'status': 1});
          }
          throw StateError('Unexpected endpoint ${r.url.path}');
        });
        final repository = PlatformLibraryRepository(
          database,
          api: api,
          identity: owner157,
        );
        addTearDown(repository.dispose);
        final tracks = [
          for (var n = 0; n < (ambiguous ? 8 : 35); n++) song157(n),
        ];
        Future<String> save() => repository.saveRankingSnapshot(
          draftId: 'test-chart',
          name: '测试榜 · 今日',
          tracks: tracks,
        );
        if (ambiguous) await expectLater(save(), throwsA(isA<Object>()));
        expect(await save(), 'kg:9');
        expect(await save(), 'kg:9');
        expect(creates, 1);
        expect(writes, ambiguous ? 1 : 4);
        expect(songs.length, tracks.length);
        expect(await repository.commentId('kg:9'), 'collection_fixture');
      },
    );
  }
}
