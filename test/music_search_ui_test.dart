import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/recommendation/recommendation_providers.dart';
import 'package:mesting_music/features/search/data/hot_music_repository.dart';
import 'package:mesting_music/features/search/presentation/music_search_page.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/social_providers.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_tracks.dart';

class _ReadySearchController extends MusicSearchController {
  @override
  MusicSearchState build() => const MusicSearchState();

  @override
  void setQuery(String rawQuery, {bool composing = false}) {
    state = MusicSearchState(
      query: rawQuery.trim(),
      onlineTracks: [testTracks.first],
      fromCache: true,
    );
  }

  @override
  Future<void> submit(String rawQuery) async {
    state = MusicSearchState(
      query: rawQuery.trim(),
      onlineTracks: [testTracks.first],
      fromCache: true,
    );
  }
}

class _ReadyHotMusicController extends HotMusicController {
  @override
  Future<HotMusicSnapshot> build() async => HotMusicSnapshot(
    tracks: [testTracks[0], testTracks[2]],
    popularTracks: [testTracks[1]],
    risingTracks: [testTracks[3]],
    updatedAt: DateTime(2026, 7, 24),
    sourceLabel: '酷狗实时榜',
  );
}

class _GuestAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Widget searchApp({
    bool showReadyResults = false,
    bool showColdStartRanking = false,
    List<SocialUser> userResults = const [],
    Set<String> favoriteTrackIds = const <String>{},
    String? activeTrackId,
  }) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        platformAccountProvider.overrideWith(_GuestAccount.new),
        if (showColdStartRanking) ...[
          hotMusicControllerProvider.overrideWith(_ReadyHotMusicController.new),
          listeningSignalsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          favoriteTracksProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        if (showReadyResults) ...[
          musicSearchControllerProvider.overrideWith(
            _ReadySearchController.new,
          ),
          socialUserSearchProvider.overrideWith(
            (ref, query) async => userResults,
          ),
          currentMediaItemProvider.overrideWith(
            (ref) => Stream.value(
              activeTrackId == null
                  ? null
                  : testTracks
                        .firstWhere((track) => track.id == activeTrackId)
                        .toMediaItem(),
            ),
          ),
          favoriteTrackIdsProvider.overrideWithValue(favoriteTrackIds),
        ],
      ],
      child: const MaterialApp(home: Scaffold(body: MusicSearchPage())),
    );
  }

  test('点击单条搜索结果只生成该歌曲的播放选择', () {
    final selected = testTracks[2];
    final queue = selectedSearchPlaybackQueue(selected);

    expect(queue, hasLength(1));
    expect(queue.single.id, selected.id);
  });

  testWidgets('输入搜索词时显示定制等待状态，清空后立即返回搜索首页', (tester) async {
    await tester.pumpWidget(searchApp());
    await tester.pump();

    expect(find.text('猜你喜欢'), findsOneWidget);
    expect(find.text('热搜榜'), findsWidgets);
    expect(find.text('热歌榜'), findsOneWidget);
    expect(find.text('飙升榜'), findsOneWidget);
    expect(find.text('我的热榜'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-submit-action')), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(GlassTabBar), findsOneWidget);
    expect(find.byType(EditableText), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '海洋Bo');
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('正在加载...'), findsNothing);
    expect(
      find.byKey(const ValueKey('search-loading-animation')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('正在加载“海洋Bo”的搜索结果'), findsOneWidget);
    expect(find.textContaining('正在搜索'), findsNothing);
    expect(find.textContaining('正在连接在线试听库'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.enterText(find.byType(EditableText), '');
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('猜你喜欢'), findsOneWidget);
    expect(find.text('正在加载...'), findsNothing);
  });

  testWidgets('底部玻璃搜索按钮提交当前输入并进入结果页', (tester) async {
    await tester.pumpWidget(searchApp(showReadyResults: true));
    await tester.pump();

    await tester.enterText(find.byType(EditableText), '测试');
    await tester.tap(find.byKey(const ValueKey('search-submit-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-submit-action')), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(find.byKey(const ValueKey('search-result-tabs')), findsOneWidget);
    expect(find.text('在线音乐'), findsOneWidget);
  });

  testWidgets('四个榜单可以在同一张榜单卡片内切换', (tester) async {
    await tester.pumpWidget(searchApp());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ranking-tab-popular')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('ranking-card-popular')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ranking-tab-rising')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('ranking-card-rising')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ranking-tab-personal')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('ranking-card-personal')), findsOneWidget);
    expect(find.textContaining('专属排行'), findsOneWidget);
  });

  testWidgets('榜单选中标签、播放按钮和首位标记统一使用心动红', (tester) async {
    await tester.pumpWidget(searchApp(showColdStartRanking: true));
    await tester.pumpAndSettle();

    final selectedTab = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('ranking-tab-surface-search')),
    );
    final tabDecoration = selectedTab.decoration! as BoxDecoration;
    expect(tabDecoration.color, MestingPalette.heart.withValues(alpha: .14));
    expect(
      tabDecoration.border!.top.color,
      MestingPalette.heart.withValues(alpha: .28),
    );

    final playButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('ranking-play-button')),
    );
    expect(
      playButton.style?.backgroundColor?.resolve(const {}),
      MestingPalette.heart,
    );
    expect(playButton.style?.foregroundColor?.resolve(const {}), Colors.white);

    final leaderBadge = tester.widget<Container>(
      find.byKey(const ValueKey('ranking-leader-badge')),
    );
    expect(
      (leaderBadge.decoration! as BoxDecoration).color,
      MestingPalette.heart,
    );
  });

  testWidgets('首次使用时猜你喜欢展示近期榜单歌手', (tester) async {
    await tester.pumpWidget(searchApp(showColdStartRanking: true));
    await tester.pumpAndSettle();

    expect(find.text('近期热门歌手'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.text('Another Artist'), findsOneWidget);
    expect(find.byKey(const ValueKey('artist-suggestion-0')), findsOneWidget);
  });

  testWidgets('在线音乐标题与首条结果之间不再继承系统顶部留白', (tester) async {
    await tester.pumpWidget(searchApp(showReadyResults: true));
    await tester.pump();

    await tester.enterText(find.byType(EditableText), '测试');
    tester.widget<EditableText>(find.byType(EditableText)).onSubmitted!('测试');
    await tester.pumpAndSettle();

    final trackList = tester.widget<ListView>(
      find.byKey(const ValueKey('search-track-list')),
    );
    expect(trackList.padding, EdgeInsets.zero);

    final titleBottom = tester.getBottomLeft(find.text('在线音乐')).dy;
    final artworkTop = tester.getTopLeft(find.byType(Image).first).dy;
    expect(artworkTop - titleBottom, lessThan(36));
  });

  testWidgets('搜索结果当前歌曲标题使用与我的喜欢一致的心动红', (tester) async {
    await tester.pumpWidget(
      searchApp(showReadyResults: true, activeTrackId: testTracks.first.id),
    );
    await tester.enterText(find.byType(EditableText), '测试');
    tester.widget<EditableText>(find.byType(EditableText)).onSubmitted!('测试');
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text(testTracks.first.title));
    expect(title.style?.color, MestingPalette.heart);
  });

  testWidgets('搜索预览按网易云风格分层展示歌手、歌曲和联想词', (tester) async {
    final artist = SocialUser(
      uid: 'artist-chen-li',
      nickname: '陈粒',
      followerCount: 7303000,
    );
    await tester.pumpWidget(
      searchApp(showReadyResults: true, userResults: [artist]),
    );
    await tester.enterText(find.byType(EditableText), '陈粒');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('netease-search-overview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('netease-search-artist-result')),
      findsOneWidget,
    );
    expect(find.text('艺人 · 730.3万粉丝'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('netease-search-suggestion-陈粒')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('netease-search-track-test_track_one')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('search-result-tabs')), findsNothing);
  });

  testWidgets('联想预览标记已收藏歌曲的红色爱心', (tester) async {
    await tester.pumpWidget(
      searchApp(
        showReadyResults: true,
        favoriteTrackIds: {testTracks.first.id},
      ),
    );
    await tester.enterText(find.byType(EditableText), '陈粒');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('netease-search-track-test_track_one')),
        matching: find.byIcon(Icons.favorite_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('netease-search-suggestion-Test Track One'),
        ),
        matching: find.byIcon(Icons.favorite_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('搜索结果只保留单曲和用户并默认停留单曲', (tester) async {
    final users = List.generate(
      5,
      (index) => SocialUser(
        uid: 'user-$index',
        nickname: '用户${index + 1}',
        followerCount: index + 1,
      ),
    );
    await tester.pumpWidget(
      searchApp(showReadyResults: true, userResults: users),
    );
    await tester.enterText(find.byType(EditableText), '用户1');
    tester.widget<EditableText>(find.byType(EditableText)).onSubmitted!('用户1');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-result-tabs')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('search-result-tab-indicator-tracks')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('search-result-tab-all')), findsNothing);
    expect(find.text('综合'), findsNothing);
    expect(find.text('在线音乐'), findsOneWidget);
    final selectedTab = tester.widget<Text>(find.text('单曲'));
    expect(selectedTab.style?.color, MestingPalette.heart);
    final resultScroll = find.byKey(const ValueKey('search-results-scroll'));
    for (final user in users) {
      expect(
        find.descendant(of: resultScroll, matching: find.text(user.nickname)),
        findsNothing,
      );
    }

    await tester.tap(find.byKey(const ValueKey('search-result-tab-users')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('search-result-tab-indicator-users')),
      findsOneWidget,
    );
    expect(find.text('在线音乐'), findsNothing);
    expect(find.text('5 位'), findsOneWidget);
    for (final user in users) {
      expect(
        find.descendant(of: resultScroll, matching: find.text(user.nickname)),
        findsOneWidget,
      );
    }

    await tester.tap(find.byKey(const ValueKey('search-result-tab-tracks')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('search-result-tab-indicator-tracks')),
      findsOneWidget,
    );
    expect(find.text('在线音乐'), findsOneWidget);
    expect(
      find.descendant(of: resultScroll, matching: find.text('用户1')),
      findsNothing,
    );
  });
}
