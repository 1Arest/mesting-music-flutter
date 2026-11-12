import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/library/data/song_favorite_count.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/presentation/favorite_toggle_button.dart';
import 'package:mesting_music/features/library/presentation/song_favorite_count_badge.dart';
import 'package:mesting_music/features/player/player_visual_style.dart';
import 'package:mesting_music/features/player/presentation/player_visual_stages.dart';
import 'package:mesting_music/shared/models/track.dart';

void main() {
  test('读取网易云歌曲红心人数，包括合法的零', () {
    expect(
      songFavoriteCount(
        {
          'code': 200,
          'data': {'count': 5902129},
        },
        (TrackSource.netease, '362937'),
      ),
      5902129,
    );
    expect(
      songFavoriteCount(
        {
          'code': 200,
          'data': {'count': 0},
        },
        (TrackSource.netease, '362937'),
      ),
      0,
    );
    for (final value in [null, -1, true, 1.5, '100w+']) {
      expect(
        songFavoriteCount(
          {
            'code': 200,
            'data': {'count': value},
          },
          (TrackSource.netease, '362937'),
        ),
        isNull,
      );
    }
    expect(
      songFavoriteCount(
        {
          'code': 500,
          'data': {'count': 1},
        },
        (TrackSource.netease, '362937'),
      ),
      isNull,
    );
  });

  test('酷狗只读取当前 mixsongid 的收藏总数', () {
    final payload = {
      'status': 1,
      'data': {
        'list': [
          {'mixsongid': 368015985, 'count': 397620, 'count_text': '39w'},
          {'mixsongid': 368015986, 'count': 0},
        ],
      },
    };
    expect(
      songFavoriteCount(payload, (TrackSource.kugou, '368015985')),
      397620,
    );
    expect(songFavoriteCount(payload, (TrackSource.kugou, '368015986')), 0);
    expect(songFavoriteCount(payload, (TrackSource.kugou, '999')), isNull);
    expect(
      songFavoriteCount(
        {'status': 0, 'data': {}},
        (TrackSource.kugou, '368015985'),
      ),
      isNull,
    );
  });

  test('错误结构、评论点赞与个人收藏数量不作为歌曲总数', () {
    for (final payload in <Map<String, dynamic>>[
      {},
      {
        'code': 200,
        'data': {'likedCount': 31},
      },
      {
        'status': 1,
        'data': {'favoriteCount': 100},
      },
      {'code': 200, 'data': []},
    ]) {
      expect(songFavoriteCount(payload, (TrackSource.netease, '1')), isNull);
      expect(songFavoriteCount(payload, (TrackSource.kugou, '1')), isNull);
    }
    expect(songCountIdentity(_track), (TrackSource.netease, '362937'));
    expect(formatSongFavoriteCount(5902129), '590.2w');
    expect(formatSongFavoriteCount(397620), '39.7w');
  });

  test('万单位截断且显示上限为999w+', () {
    expect(formatSongFavoriteCount(9999), '9999');
    expect(formatSongFavoriteCount(10000), '1w');
    expect(formatSongFavoriteCount(9989999), '998.9w');
    expect(formatSongFavoriteCount(9990000), '999w+');
    expect(formatSongFavoriteCount(100000000), '999w+');
  });

  test('搜索与播放器读取合并，后续读取使用缓存', () async {
    final cache = SongFavoriteCountCache();
    final reply = Completer<Map<String, dynamic>>();
    var requests = 0;
    Future<Map<String, dynamic>> request() {
      requests++;
      return reply.future;
    }

    const song = (TrackSource.netease, '1');
    final a = cache.load(song, request, () => true);
    final b = cache.load(song, request, () => true);
    reply.complete({
      'code': 200,
      'data': {'count': 12},
    });
    expect(await a, 12);
    expect(await b, 12);
    expect(await cache.load(song, request, () => true), 12);
    expect(requests, 1);
    cache.invalidate(song);
    expect(await cache.load(song, request, () => true), 12);
    expect(requests, 2);
  });

  testWidgets('独立红心显示上限，保留触摸；无数据保持原样', (tester) async {
    var taps = 0;
    for (final inline in [false, true]) {
      for (final count in <int?>[10000000, null]) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('$inline-$count'),
            overrides: [
              songFavoriteCountProvider.overrideWith(
                (ref, song) async => count,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 100,
                    child: SongFavoriteCountBadge(
                      track: _track,
                      inline: inline,
                      child: IconButton(
                        icon: const Icon(Icons.favorite),
                        onPressed: () => taps++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('999w+'),
          count == null ? findsNothing : findsOneWidget,
        );
        await tester.tap(find.byIcon(Icons.favorite));
        expect(tester.takeException(), isNull);
      }
    }
    expect(taps, 4);
  });

  testWidgets('有总数时展示数字，缺失时原有收藏按钮继续显示', (tester) async {
    for (final count in <int?>[5902129, null, 0]) {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(count),
          overrides: [
            favoriteTrackIdsProvider.overrideWithValue(const <String>{}),
            songFavoriteCountProvider.overrideWith((ref, song) async => count),
          ],
          child: const MaterialApp(
            home: Scaffold(body: FavoriteToggleButton(track: _track)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('收藏歌曲'), findsOneWidget);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('favorite-button-netease_362937')),
        ),
        const Size.square(48),
      );
      expect(
        find.byKey(const ValueKey('song-favorite-count-netease_362937')),
        count == null ? findsNothing : findsOneWidget,
      );
      if (count != null) {
        expect(find.text(formatSongFavoriteCount(count)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('三套独立播放器显示歌曲总数且红心仍可点击', (tester) async {
    tester.view.physicalSize = const Size(390, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    for (final style in [
      PlayerVisualStyle.aurora,
      PlayerVisualStyle.cassette,
      PlayerVisualStyle.lyricStage,
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(style),
          overrides: [
            songFavoriteCountProvider.overrideWith(
              (ref, song) async => 10000000,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AlternativePlayerStage(
                style: style,
                track: _track,
                vinylRotating: false,
                routeAnimation: kAlwaysCompleteAnimation,
                favorite: false,
                onToggleFavorite: () => taps++,
                onShowLyrics: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('999w+'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('alternative-player-favorite-${style.id}')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(taps, 3);
  });
}

const _track = Track(
  id: 'netease_362937',
  title: '歌曲',
  artist: '歌手',
  album: '',
  duration: Duration.zero,
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
);
