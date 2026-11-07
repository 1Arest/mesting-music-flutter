import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/library/presentation/music_home_page.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'package:mesting_music/shared/widgets/playing_equalizer.dart';

import 'support/test_tracks.dart';

void main() {
  test('我的喜欢使用独立心动红语义色', () {
    expect(favoriteCollectionAccentFor(Brightness.light), MestingPalette.heart);
    expect(
      favoriteCollectionAccentFor(Brightness.dark),
      MestingPalette.heartBright,
    );
  });

  testWidgets('新版收藏歌曲行显示序号、时长和加入播放列表按钮', (tester) async {
    var playCount = 0;
    var addCount = 0;
    final track = testTracks.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoriteTrackRow(
            track: track,
            index: 0,
            onPlay: () => playCount += 1,
            onAdd: () => addCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('01'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.text('3:12'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    final addButton = find.byKey(
      const ValueKey('favorite-track-add-test_track_one'),
    );
    expect(tester.getSize(addButton), const Size.square(48));
    expect(
      tester.getSize(
        find.descendant(of: addButton, matching: find.byType(IconButton)),
      ),
      const Size.square(36),
    );

    await tester.tap(find.bySemanticsLabel('将Test Track One添加至播放列表'));
    await tester.pump();

    expect(addCount, 1);
    expect(playCount, 0);

    await tester.tap(find.text('Test Track One'));
    await tester.pump();

    expect(playCount, 1);
    expect(addCount, 1);
  });

  testWidgets('新版我的喜欢使用收藏封面和连续曲目列表', (tester) async {
    tester.view.physicalSize = const Size(336, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var playAllCount = 0;
    Track? playedTrack;
    Track? addedTrack;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FavoriteCollectionView(
              tracks: testTracks.take(2).toList(),
              currentTrackId: testTracks[1].id,
              playing: false,
              onPlayAll: () => playAllCount += 1,
              onPlayTrack: (track) => playedTrack = track,
              onAddTrack: (track) => addedTrack = track,
              onExplore: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('favorites-collection-hero')),
      findsOneWidget,
    );
    expect(find.text('心动收藏'), findsOneWidget);
    expect(find.text('把每一首喜欢，收进自己的声音档案'), findsOneWidget);
    expect(find.text('2 首收藏'), findsOneWidget);
    expect(find.textContaining('7 分钟'), findsNothing);
    expect(find.text('收藏曲目'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('favorites-artwork-stack')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('favorite-track-list')), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('3:12'), findsOneWidget);
    expect(find.text('4:08'), findsOneWidget);
    final favoriteListArtwork = tester.widgetList<ArtworkImage>(
      find.descendant(
        of: find.byKey(const ValueKey('favorite-track-list')),
        matching: find.byType(ArtworkImage),
      ),
    );
    final favoriteHeroArtwork = tester.widgetList<ArtworkImage>(
      find.descendant(
        of: find.byKey(const ValueKey('favorites-artwork-stack')),
        matching: find.byType(ArtworkImage),
      ),
    );
    expect(favoriteListArtwork, isNotEmpty);
    expect(favoriteHeroArtwork, isNotEmpty);
    expect(
      favoriteListArtwork.every((artwork) => artwork.retryOnNetworkError),
      isTrue,
    );
    expect(
      favoriteHeroArtwork.every((artwork) => artwork.retryOnNetworkError),
      isTrue,
    );
    expect(find.byType(PlayingEqualizer), findsOneWidget);
    final hero = tester.widget<LiquidGlassSurface>(
      find.byKey(const ValueKey('favorites-collection-hero')),
    );
    expect(hero.blurSigma, 24);
    expect(hero.borderRadius, BorderRadius.circular(30));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('favorites-collection-hero')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    final trackListGlass = tester.widget<LiquidGlassSurface>(
      find.byKey(const ValueKey('favorite-track-list-liquid-glass')),
    );
    expect(trackListGlass.blurSigma, 24);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('favorite-track-list-liquid-glass')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('favorites-play-all')));
    await tester.pump();
    expect(playAllCount, 1);

    await tester.tap(
      find.byKey(const ValueKey('favorite-track-test_track_two')),
    );
    await tester.pump();
    expect(playedTrack, testTracks[1]);

    await tester.tap(find.bySemanticsLabel('将Test Track One添加至播放列表'));
    await tester.pump();
    expect(addedTrack, testTracks[0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前收藏歌曲长标题与歌手播放时滚动且暂停后保持位置', (tester) async {
    const track = Track(
      id: 'long_favorite',
      title: '薛之谦《陪你去流浪（3D环绕版）》特别加长歌曲名称',
      artist: '乐贤baby与一位名字同样很长很长的合作歌手',
      album: 'Long Album',
      duration: Duration(minutes: 4, seconds: 36),
      audioAsset: 'test/audio/long.mp3',
      coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
      lyricsAsset: '',
    );

    Future<void> pumpRow(bool playing) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: FavoriteTrackRow(
                  track: track,
                  active: true,
                  playing: playing,
                  onPlay: () {},
                  onAdd: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    double translation(String key) {
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Transform),
        ),
      );
      return transform.transform.getTranslation().x;
    }

    await pumpRow(true);
    expect(
      find.byKey(const ValueKey('favorite-track-title-long_favorite-marquee')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('favorite-track-artist-long_favorite-marquee')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1500));
    final titleOffset = translation(
      'favorite-track-title-long_favorite-marquee',
    );
    final artistOffset = translation(
      'favorite-track-artist-long_favorite-marquee',
    );
    expect(titleOffset, lessThan(0));
    expect(artistOffset, lessThan(0));

    await pumpRow(false);
    await tester.pump();
    final pausedTitleOffset = translation(
      'favorite-track-title-long_favorite-marquee',
    );
    final pausedArtistOffset = translation(
      'favorite-track-artist-long_favorite-marquee',
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      translation('favorite-track-title-long_favorite-marquee'),
      closeTo(pausedTitleOffset, .001),
    );
    expect(
      translation('favorite-track-artist-long_favorite-marquee'),
      closeTo(pausedArtistOffset, .001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏档案头图在暗色主题下保持独立配色和重叠封面', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FavoriteCollectionView(
            tracks: testTracks.take(3).toList(),
            onPlayAll: () {},
            onPlayTrack: (_) {},
            onAddTrack: (_) {},
            onExplore: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hero = tester.widget<LiquidGlassSurface>(
      find.byKey(const ValueKey('favorites-collection-hero')),
    );
    expect(hero.blurSigma, 24);
    expect(hero.borderRadius, BorderRadius.circular(30));
    expect(find.text('3 首收藏'), findsOneWidget);
    expect(find.textContaining('分钟'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('favorites-artwork-stack')),
        matching: find.byType(Transform),
      ),
      findsAtLeastNWidgets(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('重叠封面复用单轴解码缓存并支持左右滑动循环切换', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FavoriteCollectionView(
              tracks: testTracks,
              onPlayAll: () {},
              onPlayTrack: (_) {},
              onAddTrack: (_) {},
              onExplore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stack = find.byKey(const ValueKey('favorites-artwork-stack'));
    expect(
      find.byKey(const ValueKey('favorites-artwork-front-test_track_one')),
      findsOneWidget,
    );
    for (final artwork in tester.widgetList<ArtworkImage>(
      find.byType(ArtworkImage),
    )) {
      expect(artwork.decodeWidth, favoriteArtworkDecodeWidth);
      expect(artwork.decodeHeight, isNull);
    }

    await tester.drag(stack, const Offset(-72, 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('favorites-artwork-front-test_track_two')),
      findsOneWidget,
    );

    await tester.drag(stack, const Offset(72, 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('favorites-artwork-front-test_track_one')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('空收藏页给出明确的发现音乐入口', (tester) async {
    var exploreCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoriteCollectionView(
            tracks: const [],
            onPlayAll: null,
            onPlayTrack: (_) {},
            onAddTrack: (_) {},
            onExplore: () => exploreCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('还没有喜欢的歌曲'), findsOneWidget);
    expect(find.text('从第一首心动开始'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-track-list')), findsNothing);
    final emptyGlass = tester.widget<LiquidGlassSurface>(
      find.byKey(const ValueKey('favorite-empty-liquid-glass')),
    );
    expect(emptyGlass.blurSigma, 24);
    expect(emptyGlass.borderRadius, BorderRadius.circular(26));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('favorite-empty-liquid-glass')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('favorites-explore')));
    await tester.pump();
    expect(exploreCount, 1);
  });
}
