import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/presentation/music_home_page.dart';
import 'package:mesting_music/features/search/data/hot_music_repository.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/playing_equalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReadyHotMusicController extends HotMusicController {
  @override
  Future<HotMusicSnapshot> build() async => HotMusicSnapshot(
    tracks: _hotTracks,
    popularTracks: const [],
    risingTracks: const [],
    updatedAt: DateTime(2026, 7, 25),
    sourceLabel: '测试热歌',
  );
}

class _TestAudioHandler extends MestingAudioHandler {
  _TestAudioHandler() : super(tracks: _hotTracks);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('发现音乐四个区块使用横向滑动且热门音乐每列三首', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      musicThemePreferenceKey: 'kasukabe-sky',
    });
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/music',
      routes: [
        GoRoute(
          path: '/music',
          builder: (_, _) => const Scaffold(body: MusicHomePage()),
        ),
        GoRoute(
          path: '/music/discover',
          builder: (_, _) => const Scaffold(body: Text('发现歌单')),
        ),
        GoRoute(
          path: '/music/discover/:id',
          builder: (_, _) => const Scaffold(body: Text('歌单详情')),
        ),
        GoRoute(
          path: '/music/search',
          builder: (_, _) => const Scaffold(body: Text('搜索')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final audioHandler = _TestAudioHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authRepositoryProvider.overrideWithValue(
            const UnconfiguredAuthRepository(),
          ),
          favoriteTracksProvider.overrideWith((ref) => Stream.value(const [])),
          hotMusicControllerProvider.overrideWith(_ReadyHotMusicController.new),
          audioHandlerProvider.overrideWithValue(audioHandler),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final featuredRail = find.byKey(const ValueKey('playlist-rail-精选歌单'));
    expect(featuredRail, findsOneWidget);
    expect(
      tester.widget<ListView>(featuredRail).scrollDirection,
      Axis.horizontal,
    );
    final featuredCover = find.byKey(
      const ValueKey('playlist-rail-cover-featured-1'),
    );
    final coverSize = tester.getSize(featuredCover);
    expect(coverSize.width, closeTo(coverSize.height, .01));
    final themedArtwork = tester.widget<ArtworkImage>(
      find.descendant(of: featuredCover, matching: find.byType(ArtworkImage)),
    );
    expect(themedArtwork.uri, contains('theme_playlists/shinchan'));
    expect(themedArtwork.decodeWidth, closeTo(coverSize.width, .01));
    expect(themedArtwork.decodeHeight, isNull);
    expect(themedArtwork.fit, BoxFit.cover);
    await _expectHorizontalDragMoves(tester, featuredRail);

    await tester.scrollUntilVisible(
      find.text('热门音乐'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    final popularRail = find.byKey(const ValueKey('popular-music-column-rail'));
    expect(popularRail, findsOneWidget);
    expect(
      tester.widget<ListView>(popularRail).scrollDirection,
      Axis.horizontal,
    );
    final firstColumn = find.byKey(const ValueKey('popular-music-column-0'));
    expect(
      find.descendant(of: firstColumn, matching: find.text('热门歌曲 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstColumn, matching: find.text('热门歌曲 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstColumn, matching: find.text('热门歌曲 3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstColumn, matching: find.text('热门歌曲 4')),
      findsNothing,
    );
    await _expectHorizontalDragMoves(tester, popularRail);

    await tester.scrollUntilVisible(
      find.text('宝藏歌单'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    final treasureRail = find.byKey(const ValueKey('playlist-rail-宝藏歌单'));
    expect(
      tester.widget<ListView>(treasureRail).scrollDirection,
      Axis.horizontal,
    );
    await _expectHorizontalDragMoves(tester, treasureRail);

    await tester.scrollUntilVisible(
      find.text('今日编辑推荐'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    final editorRail = find.byKey(const ValueKey('playlist-rail-今日编辑推荐'));
    expect(
      tester.widget<ListView>(editorRail).scrollDirection,
      Axis.horizontal,
    );
    await _expectHorizontalDragMoves(tester, editorRail);
    expect(tester.takeException(), isNull);
  });

  testWidgets('发现音乐当前歌曲标题与均衡器使用我的喜欢心动红', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      musicThemePreferenceKey: 'kasukabe-sky',
    });
    final preferences = await SharedPreferences.getInstance();
    final audioHandler = _TestAudioHandler();
    final router = GoRouter(
      initialLocation: '/music',
      routes: [
        GoRoute(
          path: '/music',
          builder: (_, _) => MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              disableAnimations: true,
            ),
            child: const Scaffold(body: MusicHomePage()),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authRepositoryProvider.overrideWithValue(
            const UnconfiguredAuthRepository(),
          ),
          favoriteTracksProvider.overrideWith((ref) => Stream.value(const [])),
          hotMusicControllerProvider.overrideWith(_ReadyHotMusicController.new),
          audioHandlerProvider.overrideWithValue(audioHandler),
          currentMediaItemProvider.overrideWith(
            (ref) => Stream.value(_hotTracks.first.toMediaItem()),
          ),
          playbackStateProvider.overrideWith(
            (ref) => Stream.value(PlaybackState(playing: true)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('热门音乐'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final activeTitle = tester.widget<Text>(find.text('热门歌曲 1'));
    expect(activeTitle.style?.color, MestingPalette.heart);
    final equalizer = tester.widget<PlayingEqualizer>(
      find.descendant(
        of: find.byKey(const ValueKey('popular-music-column-0')),
        matching: find.byType(PlayingEqualizer),
      ),
    );
    expect(equalizer.animate, isTrue);
    expect(equalizer.color, MestingPalette.heart);
  });
}

Future<void> _expectHorizontalDragMoves(
  WidgetTester tester,
  Finder rail,
) async {
  final scrollable = find.descendant(
    of: rail,
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  final before = position.pixels;
  await tester.drag(rail, const Offset(-180, 0));
  await tester.pumpAndSettle();
  expect(position.pixels, greaterThan(before));
}

final _hotTracks = List<Track>.generate(
  7,
  (index) => Track(
    id: 'hot-track-$index',
    title: '热门歌曲 ${index + 1}',
    artist: '热门歌手 ${index + 1}',
    album: '热门音乐',
    duration: const Duration(minutes: 3),
    audioAsset: 'assets/audio/hot-$index.mp3',
    coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
    lyricsAsset: '',
  ),
  growable: false,
);
