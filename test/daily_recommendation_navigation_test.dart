import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/presentation/music_home_page.dart';
import 'package:mesting_music/features/recommendation/presentation/recommendation_page.dart';
import 'package:mesting_music/features/recommendation/recommendation_providers.dart';
import 'package:mesting_music/features/search/data/hot_music_repository.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReadyHotMusicController extends HotMusicController {
  @override
  Future<HotMusicSnapshot> build() async => HotMusicSnapshot(
    tracks: _dailyTracks,
    recommendationTracks: _dailyTracks,
    updatedAt: DateTime(2026, 7, 26),
    sourceLabel: '测试推荐',
  );
}

final _dailyTracks = List<Track>.generate(
  4,
  (index) => Track(
    id: 'daily-track-$index',
    title: '每日测试歌曲 ${index + 1}',
    artist: '测试歌手 ${index + 1}',
    album: '每日推荐',
    duration: const Duration(minutes: 3),
    audioAsset: 'https://example.com/daily-$index.mp3',
    coverAsset: 'assets/images/theme_gallery/shinchan-avatar-v2.png',
    lyricsAsset: '',
    source: TrackSource.kugou,
    provider: '测试音乐',
  ),
  growable: false,
);

void main() {
  testWidgets('昨日推荐会切换日期和推荐队列', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/music?view=daily',
      routes: [
        GoRoute(
          path: '/music',
          builder: (_, _) => const Scaffold(body: MusicHomePage()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            const UnconfiguredAuthRepository(),
          ),
          favoriteTracksProvider.overrideWith((ref) => Stream.value(const [])),
          listeningSignalsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          listeningSignalsForDayProvider.overrideWith(
            (ref, day) => Stream.value(const []),
          ),
          hotMusicControllerProvider.overrideWith(_ReadyHotMusicController.new),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('昨日推荐'), findsOneWidget);
    final firstTrack = find.byKey(const ValueKey('daily-track-0'));
    final firstTrackInkWell = tester.widget<InkWell>(firstTrack);
    expect(firstTrackInkWell.borderRadius, BorderRadius.circular(18));
    final addButton = find.byKey(const ValueKey('daily-track-add-0'));
    expect(tester.getSize(addButton), const Size.square(48));
    expect(
      tester.getSize(
        find.descendant(of: addButton, matching: find.byType(IconButton)),
      ),
      const Size.square(44),
    );
    final firstTrackMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('daily-track-material-0')),
    );
    expect(firstTrackMaterial.clipBehavior, Clip.antiAlias);
    expect(firstTrackMaterial.shape, isA<RoundedRectangleBorder>());
    expect(
      (firstTrackMaterial.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(18),
    );
    final selector = find.byKey(const ValueKey('daily-day-selector'));
    final heroSwitcher = find.byKey(const ValueKey('daily-hero-switcher'));
    final queueSwitcher = find.byKey(const ValueKey('daily-queue-switcher'));
    expect(
      tester.widget<AnimatedSwitcher>(heroSwitcher).duration,
      const Duration(milliseconds: 420),
    );
    expect(
      tester.widget<AnimatedSwitcher>(queueSwitcher).duration,
      const Duration(milliseconds: 420),
    );

    await tester.tap(
      find.descendant(of: selector, matching: find.text('昨日推荐')),
    );
    await tester.pump();

    expect(
      tester
          .widget<AnimatedAlign>(
            find.byKey(const ValueKey('daily-day-selector-indicator')),
          )
          .alignment,
      Alignment.centerRight,
    );
    expect(find.byKey(const ValueKey(('hero', 0))), findsOneWidget);
    expect(find.byKey(const ValueKey(('hero', 1))), findsOneWidget);
    expect(find.byKey(const ValueKey(('queue', 0))), findsOneWidget);
    expect(find.byKey(const ValueKey(('queue', 1))), findsOneWidget);
    expect(
      find.descendant(of: heroSwitcher, matching: find.byType(SlideTransition)),
      findsWidgets,
    );

    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(
      find.descendant(of: selector, matching: find.text('今日推荐')),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(
      find.descendant(of: selector, matching: find.text('昨日推荐')),
    );
    await tester.pumpAndSettle();

    expect(find.text('昨日推荐'), findsNWidgets(2));
    expect(find.byKey(const ValueKey(('hero', 0))), findsNothing);
    expect(find.byKey(const ValueKey(('hero', 1))), findsOneWidget);
    expect(find.byKey(const ValueKey(('queue', 0))), findsNothing);
    expect(find.byKey(const ValueKey(('queue', 1))), findsOneWidget);
    expect(find.byTooltip('加入播放列表'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从推荐首页进入每日推荐会保留返回栈', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/music/recommend',
      routes: [
        GoRoute(
          path: '/music/recommend',
          builder: (_, _) => const Scaffold(body: RecommendationPage()),
        ),
        GoRoute(
          path: '/music',
          builder: (_, _) => const Scaffold(body: Text('每日推荐页面')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('每日推荐'));
    await tester.pumpAndSettle();
    expect(find.text('每日推荐页面'), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('今日私人混合'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
