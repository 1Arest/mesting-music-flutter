import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/recommendation/presentation/recommendation_page.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/glass_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_tracks.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  Widget app({ThemeMode themeMode = ThemeMode.light}) {
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: themeMode,
        home: const Scaffold(body: RecommendationPage()),
      ),
    );
  }

  test('每日推荐日期徽章按自然日稳定轮换高对比配色', () {
    final date = DateTime(2026, 7, 26, 8);
    final sameDay = DateTime(2026, 7, 26, 23, 59);
    final light = dailyDateBadgePaletteFor(Brightness.light, date: date);
    final dark = dailyDateBadgePaletteFor(Brightness.dark, date: date);

    expect(light.day, const Color(0xFFFFFAF0));
    expect(light.month, const Color(0xFFF2CB7C));
    expect(dark.background, isNot(light.background));
    expect(
      dailyDateBadgePaletteFor(Brightness.light, date: sameDay).background,
      light.background,
    );
    for (final brightness in Brightness.values) {
      final consecutiveColors = List<Color>.generate(
        7,
        (offset) => dailyDateBadgePaletteFor(
          brightness,
          date: date.add(Duration(days: offset)),
        ).background,
      );
      expect(consecutiveColors.toSet(), hasLength(7));
      for (var index = 0; index < consecutiveColors.length; index += 1) {
        expect(
          _contrastRatio(consecutiveColors[index], const Color(0xFFFFFAF0)),
          greaterThan(4.5),
        );
        if (index > 0) {
          expect(consecutiveColors[index], isNot(consecutiveColors[index - 1]));
        }
      }
    }
  });

  test('今日私人混合使用心动红播放按钮和协调的深梅紫背景', () {
    final palette = dailyMixHeroPaletteFor(MestingPalette.primary);

    expect(palette.playButton, MestingPalette.heart);
    expect(palette.backgroundStart, isNot(MestingPalette.primary));
    expect(palette.backgroundEnd, isNot(MestingPalette.primaryStrong));
    expect(
      _contrastRatio(Colors.white, palette.playButton),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(Colors.white, palette.backgroundStart),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('随手点一首按自然日稳定更新', () {
    final today = recommendationTracksForDate(
      DateTime(2026, 7, 23),
      localTracks: testTracks,
    );
    final sameDay = recommendationTracksForDate(
      DateTime(2026, 7, 23, 23, 59),
      localTracks: testTracks,
    );
    final tomorrow = recommendationTracksForDate(
      DateTime(2026, 7, 24),
      localTracks: testTracks,
    );

    expect(today.map((track) => track.id), sameDay.map((track) => track.id));
    expect(
      today.map((track) => track.id).join('|'),
      isNot(tomorrow.map((track) => track.id).join('|')),
    );
  });

  test('每日推荐在在线资源可用时混合本地与在线歌曲', () {
    const online = Track(
      id: 'kugou_daily',
      title: '实时热门歌曲',
      artist: '在线歌手',
      album: '实时榜',
      duration: Duration(minutes: 3),
      audioAsset: 'https://example.com/hot.mp3',
      coverAsset: 'https://example.com/hot.jpg',
      lyricsAsset: 'mesting-lyrics://kugou/hash',
      source: TrackSource.kugou,
      provider: '酷狗概念版',
    );

    final tracks = recommendationTracksForDate(
      DateTime(2026, 7, 23),
      localTracks: testTracks,
      onlineTracks: const [online],
    );

    expect(tracks.any((track) => track.source == TrackSource.local), isTrue);
    expect(tracks.any((track) => track.id == online.id), isTrue);
    expect(tracks.every((track) => track.isPlayable), isTrue);
  });

  test('顶部短句按六个时间段从离线文案池轮换', () {
    for (final hour in <int>[1, 8, 12, 16, 20, 23]) {
      final time = DateTime(2026, 7, 23, hour);
      final pool = recommendationGreetingsForTime(time);
      expect(pool, hasLength(greaterThanOrEqualTo(4)));
      expect(pool, contains(recommendationGreetingForTime(time)));
    }

    final slot = DateTime(2026, 7, 23, 8, 6, 12);
    expect(
      recommendationGreetingForTime(slot),
      recommendationGreetingForTime(DateTime(2026, 7, 23, 8, 8, 59)),
    );
    expect(
      recommendationGreetingForTime(slot),
      isNot(recommendationGreetingForTime(DateTime(2026, 7, 23, 8, 9))),
    );
    expect(recommendationGreetingNextUpdate(slot), DateTime(2026, 7, 23, 8, 9));
  });

  testWidgets('推荐首页提供无需搜索即可开始播放的内容入口', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('今日私人混合'), findsOneWidget);
    expect(find.text('每日推荐'), findsOneWidget);
    expect(find.text('现在适合听什么'), findsOneWidget);
    expect(find.text('通勤醒脑'), findsOneWidget);
    expect(find.text('放松一下'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('daily-mix-hero-background')),
      findsOneWidget,
    );
    final playButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('daily-mix-play')),
    );
    expect(
      playButton.style?.backgroundColor?.resolve(const {}),
      MestingPalette.heart,
    );
    expect(playButton.style?.foregroundColor?.resolve(const {}), Colors.white);
    expect(
      find.byKey(const ValueKey('textured-solid-个人中心与设置')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('textured-solid-搜索音乐')), findsOneWidget);
    final greetingSwitcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey('music-hub-title-switcher')),
    );
    const newTitle = Text('新短句');
    const oldTitle = Text('旧短句');
    expect(
      greetingSwitcher.layoutBuilder(newTitle, const [oldTitle]),
      same(newTitle),
      reason: '短句切换时布局只保留当前层，避免新旧文字双层残影',
    );
    expect(find.byKey(const ValueKey('mood-glyph-commute')), findsOneWidget);
    expect(find.byKey(const ValueKey('mood-glyph-unwind')), findsOneWidget);
    expect(find.byKey(const ValueKey('mood-glyph-focus')), findsOneWidget);
    expect(find.byKey(const ValueKey('mood-glyph-sleep')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mood-grid-visual-boundary')),
      findsOneWidget,
    );
    for (final visual in ['commute', 'unwind', 'focus', 'sleep']) {
      expect(
        find.byKey(ValueKey('mood-glyph-design-v2-$visual')),
        findsOneWidget,
      );
    }
    final moodGlyph = tester.widget<Container>(
      find.byKey(const ValueKey('mood-glyph-commute')),
    );
    final moodGlyphDecoration = moodGlyph.decoration! as BoxDecoration;
    expect(
      tester.getSize(find.byKey(const ValueKey('mood-glyph-commute'))),
      const Size.square(46),
    );
    expect(moodGlyphDecoration.shape, BoxShape.rectangle);
    expect(moodGlyphDecoration.borderRadius, BorderRadius.circular(15));
    expect(moodGlyphDecoration.gradient, isA<LinearGradient>());
    expect(moodGlyphDecoration.boxShadow, hasLength(1));
    expect(
      find.byKey(const ValueKey('mood-glyph-art-commute')),
      findsOneWidget,
    );
    expect(
      find.byType(BackdropFilter),
      findsNothing,
      reason: '推荐页滚动内容不应实时模糊背景，以满足 120Hz 帧预算',
    );
    final lightMoodCard = tester.widget<GlassCard>(
      find.byKey(const ValueKey('mood-card-commute')),
    );
    expect(lightMoodCard.color, const Color(0xFFF5F6FA));
    expect(lightMoodCard.borderColor, const Color(0x3D596784));
    expect(lightMoodCard.shadows, isNotEmpty);
    final dateBadge = tester.widget<Container>(
      find.byKey(const ValueKey('daily-recommendation-date-badge')),
    );
    final badgeDecoration = dateBadge.decoration! as BoxDecoration;
    expect(
      badgeDecoration.color,
      dailyDateBadgePaletteFor(
        Brightness.light,
        date: DateTime.now(),
      ).background,
    );
    expect(badgeDecoration.gradient, isNull);
    expect(badgeDecoration.boxShadow, isNotEmpty);
    await tester.scrollUntilVisible(
      find.text('随手点一首'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('随手点一首'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('推荐首页在窄屏暗色模式下可以完整滚动', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    final darkMoodCard = tester.widget<GlassCard>(
      find.byKey(const ValueKey('mood-card-commute')),
    );
    expect(darkMoodCard.color, isNull);
    expect(darkMoodCard.borderColor, isNull);
    await tester.scrollUntilVisible(
      find.text('猜你喜欢'),
      420,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('猜你喜欢'), findsOneWidget);
    expect(find.text('换一批'), findsOneWidget);
    expect(find.byKey(const ValueKey('recommendation-grid-0')), findsOneWidget);
    final firstCard = find.byKey(
      const ValueKey('recommendation-card-ratio-featured-1'),
    );
    final firstCardSize = tester.getSize(firstCard);
    expect(firstCardSize.width, closeTo(firstCardSize.height, .01));
    final firstArtwork = tester.widget<ArtworkImage>(
      find.descendant(of: firstCard, matching: find.byType(ArtworkImage)),
    );
    expect(firstArtwork.fit, BoxFit.cover);
    expect(firstArtwork.decodeWidth, firstArtwork.decodeHeight);
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const ValueKey('recommendation-grid-switcher')),
    );
    expect(switcher.duration, const Duration(milliseconds: 520));
    expect(switcher.reverseDuration, const Duration(milliseconds: 520));

    await tester.ensureVisible(find.text('换一批'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('换一批'));
    await tester.pump();
    await tester.tap(find.text('换一批'));
    await tester.pump(const Duration(milliseconds: 250));

    final outgoing = tester.widget<FadeTransition>(
      find.byKey(
        const ValueKey('recommendation-grid-fade-recommendation-grid-0'),
      ),
    );
    final incoming = tester.widget<FadeTransition>(
      find.byKey(
        const ValueKey('recommendation-grid-fade-recommendation-grid-1'),
      ),
    );
    expect(outgoing.opacity.value, lessThan(.15));
    expect(incoming.opacity.value, lessThan(.15));

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('recommendation-grid-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('recommendation-grid-2')), findsNothing);
    expect(
      find.byKey(const ValueKey('recommendation-card-layer-featured-1')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('平板推荐场景入口使用四列布局', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('mood-card-commute')),
      240,
      scrollable: find.byType(Scrollable).first,
    );

    final cards = [
      find.byKey(const ValueKey('mood-card-commute')),
      find.byKey(const ValueKey('mood-card-unwind')),
      find.byKey(const ValueKey('mood-card-focus')),
      find.byKey(const ValueKey('mood-card-sleep')),
    ];
    final tops = cards
        .map(tester.getTopLeft)
        .map((offset) => offset.dy)
        .toList();
    final lefts = cards
        .map(tester.getTopLeft)
        .map((offset) => offset.dx)
        .toSet();
    expect(tops.every((top) => (top - tops.first).abs() < .1), isTrue);
    expect(lefts, hasLength(4));
    expect(tester.takeException(), isNull);
  });
}

double _contrastRatio(Color first, Color second) {
  final lighter = [
    first.computeLuminance(),
    second.computeLuminance(),
  ].reduce((a, b) => a > b ? a : b);
  final darker = [
    first.computeLuminance(),
    second.computeLuminance(),
  ].reduce((a, b) => a < b ? a : b);
  return (lighter + .05) / (darker + .05);
}
