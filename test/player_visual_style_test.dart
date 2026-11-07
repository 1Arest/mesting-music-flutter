import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/player/player_visual_style.dart';
import 'package:mesting_music/features/player/presentation/player_visual_stages.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('流光唱片节拍曲线保持克制且缩放不超过安全范围', () {
    final samples = List.generate(
      101,
      (index) => auroraOrbitRhythm(index / 100),
    );

    expect(samples.every((value) => value >= 0 && value <= 1), isTrue);
    expect(
      auroraOrbitDiscScale(progress: .38, energy: 0, reduceMotion: false),
      1,
    );
    expect(
      auroraOrbitDiscScale(progress: .38, energy: 1, reduceMotion: false),
      inInclusiveRange(1.004, 1.015),
    );
    expect(
      auroraOrbitDiscScale(progress: .38, energy: 1, reduceMotion: true),
      1,
    );
  });

  test('两套新播放器的节拍与核心缩放保持在安全范围', () {
    final samples = List.generate(
      101,
      (index) => reactiveStageRhythm(index / 100),
    );

    expect(samples.every((value) => value >= 0 && value <= 1), isTrue);
    expect(
      reactiveStageCoreScale(progress: .43, energy: 0, reduceMotion: false),
      1,
    );
    expect(
      reactiveStageCoreScale(progress: .43, energy: 1, reduceMotion: false),
      inInclusiveRange(1.003, 1.021),
    );
    expect(
      reactiveStageCoreScale(
        progress: .43,
        energy: 1,
        reduceMotion: false,
        liquid: true,
      ),
      inInclusiveRange(1.003, 1.015),
    );
    expect(
      reactiveStageCoreScale(progress: .43, energy: 1, reduceMotion: true),
      1,
    );
  });

  test('播放器样式默认回退经典并可持久化', () async {
    SharedPreferences.setMockInitialValues({'player_visual_style': 'unknown'});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(playerVisualStyleProvider),
      PlayerVisualStyle.classic,
    );

    await container
        .read(playerVisualStyleProvider.notifier)
        .select(PlayerVisualStyle.cassette);

    expect(
      container.read(playerVisualStyleProvider),
      PlayerVisualStyle.cassette,
    );
    expect(preferences.getString('player_visual_style'), 'cassette');
  });

  testWidgets('流光唱片与两套新播放器拥有独立可点击舞台', (tester) async {
    tester.view.physicalSize = const Size(390, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const track = Track(
      id: 'visual-test',
      title: '夜航星河',
      artist: '林深时见鹿',
      album: '测试专辑',
      duration: Duration(minutes: 4),
      audioAsset: '',
      coverAsset: '',
      lyricsAsset: '',
    );
    var lyricTapCount = 0;
    var favoriteTapCount = 0;

    Future<void> pumpStyle(
      PlayerVisualStyle style, {
      bool favorite = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: AlternativePlayerStage(
                style: style,
                track: track,
                vinylRotating: false,
                routeAnimation: kAlwaysCompleteAnimation,
                favorite: favorite,
                onToggleFavorite: () => favoriteTapCount += 1,
                onShowLyrics: () => lyricTapCount += 1,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    void expectFavoriteAlignedWithTitle(PlayerVisualStyle style) {
      final titleRect = tester.getRect(find.text(track.title));
      final favoriteRect = tester.getRect(
        find.byKey(ValueKey('alternative-player-favorite-${style.id}')),
      );
      expect(
        (titleRect.center.dy - favoriteRect.center.dy).abs(),
        lessThan(16),
      );
      expect(favoriteRect.right, closeTo(368, .001));
    }

    await pumpStyle(PlayerVisualStyle.aurora);
    expect(find.byKey(const ValueKey('aurora-player-disc')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('aurora-player-disc'))),
      const Size.square(340),
    );
    expect(find.text('AURORA ORBIT'), findsOneWidget);
    expect(find.text('沿着光轨进入歌词'), findsNothing);
    expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('alternative-player-favorite-aurora')),
      findsOneWidget,
    );
    expectFavoriteAlignedWithTitle(PlayerVisualStyle.aurora);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    final unfavoriteIcon = tester.widget<Icon>(
      find.byIcon(Icons.favorite_border_rounded),
    );
    expect(unfavoriteIcon.color, MestingPalette.favorite);
    final unfavoriteButton = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('alternative-player-favorite-aurora')),
    );
    final unfavoriteDecoration = unfavoriteButton.decoration! as BoxDecoration;
    expect(
      unfavoriteDecoration.color,
      MestingPalette.favorite.withValues(alpha: .10),
    );
    await tester.tap(
      find.byKey(const ValueKey('alternative-player-favorite-aurora')),
    );
    await tester.tap(find.byKey(const ValueKey('aurora-player-disc')));

    await pumpStyle(PlayerVisualStyle.cassette);
    expect(find.byKey(const ValueKey('cosmic-pulse-stage')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('cosmic-pulse-stage'))),
      const Size.square(332),
    );
    expect(find.text('COSMIC PULSE'), findsOneWidget);
    expect(find.text('CASSETTE RADIO'), findsNothing);
    expect(find.text('穿过星环进入歌词'), findsNothing);
    expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('alternative-player-favorite-cassette')),
      findsOneWidget,
    );
    expectFavoriteAlignedWithTitle(PlayerVisualStyle.cassette);
    await tester.tap(
      find.byKey(const ValueKey('alternative-player-favorite-cassette')),
    );
    await tester.tap(find.byKey(const ValueKey('cosmic-pulse-stage')));

    await pumpStyle(PlayerVisualStyle.lyricStage);
    expect(find.byKey(const ValueKey('liquid-spectrum-stage')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('liquid-spectrum-stage'))),
      const Size.square(332),
    );
    expect(find.text('LIQUID SPECTRUM'), findsOneWidget);
    expect(find.text('LYRIC STAGE'), findsNothing);
    expect(find.text('潜入流体声场查看歌词'), findsNothing);
    expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('alternative-player-favorite-lyricStage')),
      findsOneWidget,
    );
    expectFavoriteAlignedWithTitle(PlayerVisualStyle.lyricStage);
    await tester.tap(
      find.byKey(const ValueKey('alternative-player-favorite-lyricStage')),
    );
    await tester.tap(find.byKey(const ValueKey('liquid-spectrum-stage')));

    expect(lyricTapCount, 3);
    expect(favoriteTapCount, 3);

    await pumpStyle(PlayerVisualStyle.aurora, favorite: true);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    final favoriteIcon = tester.widget<Icon>(
      find.byIcon(Icons.favorite_rounded),
    );
    expect(favoriteIcon.color, MestingPalette.favorite);
    final favoriteButton = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('alternative-player-favorite-aurora')),
    );
    final favoriteDecoration = favoriteButton.decoration! as BoxDecoration;
    expect(
      favoriteDecoration.color,
      MestingPalette.favorite.withValues(alpha: .20),
    );
  });

  testWidgets('星环脉冲与液态频谱随播放律动并在暂停后归位', (tester) async {
    tester.view.physicalSize = const Size(390, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const track = Track(
      id: 'reactive-stage-test',
      title: '夜航星河',
      artist: '林深时见鹿',
      album: '测试专辑',
      duration: Duration(minutes: 4),
      audioAsset: '',
      coverAsset: '',
      lyricsAsset: '',
    );

    Future<void> pumpStage({
      required PlayerVisualStyle style,
      required bool playing,
      bool reduceMotion = false,
    }) {
      return tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
            home: Scaffold(
              backgroundColor: Colors.black,
              body: AlternativePlayerStage(
                style: style,
                track: track,
                vinylRotating: playing,
                routeAnimation: kAlwaysCompleteAnimation,
                favorite: false,
                onToggleFavorite: () {},
                onShowLyrics: () {},
              ),
            ),
          ),
        ),
      );
    }

    for (final data in [
      (
        style: PlayerVisualStyle.cassette,
        scaleKey: 'cosmic-pulse-core-scale',
        boundaryKey: 'cosmic-pulse-repaint-boundary',
        painterKey: 'cosmic-pulse-painter',
        shapeKey: 'cosmic-pulse-visible-shape',
      ),
      (
        style: PlayerVisualStyle.lyricStage,
        scaleKey: 'liquid-spectrum-core-scale',
        boundaryKey: 'liquid-spectrum-repaint-boundary',
        painterKey: 'liquid-spectrum-painter',
        shapeKey: 'liquid-spectrum-visible-shape',
      ),
    ]) {
      double currentScale() {
        final transform = tester.widget<Transform>(
          find.byKey(ValueKey(data.scaleKey)),
        );
        return transform.transform.getMaxScaleOnAxis();
      }

      await pumpStage(style: data.style, playing: false);
      expect(find.byKey(ValueKey(data.boundaryKey)), findsOneWidget);
      expect(find.byKey(ValueKey(data.painterKey)), findsOneWidget);
      final visibleShape = tester.widget<Container>(
        find.byKey(ValueKey(data.shapeKey)),
      );
      final visibleDecoration = visibleShape.decoration as BoxDecoration;
      expect(visibleDecoration.shape, BoxShape.circle);
      expect(visibleDecoration.borderRadius, isNull);
      expect(currentScale(), closeTo(1, .0001));

      await pumpStage(style: data.style, playing: true);
      await tester.pump(const Duration(milliseconds: 540));
      expect(currentScale(), greaterThan(1.002));

      await pumpStage(style: data.style, playing: false);
      await tester.pump(const Duration(milliseconds: 900));
      expect(currentScale(), closeTo(1, .0001));

      await pumpStage(style: data.style, playing: true, reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(currentScale(), closeTo(1, .0001));
    }
  });

  testWidgets('装扮页复用真实播放器舞台并只运行有限预览动效', (tester) async {
    tester.view.physicalSize = const Size(160, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpPreview(PlayerVisualStyle style, {required bool active}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.expand(
              child: PlayerVisualStagePreview(
                style: style,
                active: active,
                coverAsset:
                    'assets/images/theme_playlists/shinchan/cover-01.jpg',
              ),
            ),
          ),
        ),
      );
    }

    for (final style in [
      PlayerVisualStyle.aurora,
      PlayerVisualStyle.cassette,
      PlayerVisualStyle.lyricStage,
    ]) {
      await pumpPreview(style, active: false);
      expect(
        find.byKey(ValueKey('player-style-real-preview-${style.id}')),
        findsOneWidget,
      );
    }

    await pumpPreview(PlayerVisualStyle.cassette, active: true);
    double currentScale() {
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('cosmic-pulse-core-scale')),
      );
      return transform.transform.getMaxScaleOnAxis();
    }

    expect(currentScale(), closeTo(1, .0001));
    await tester.pump(const Duration(milliseconds: 540));
    expect(currentScale(), greaterThan(1.002));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('player-style-real-preview-cassette')),
      findsOneWidget,
    );
  });

  testWidgets('流光唱片随播放律动，暂停与减少动态效果时平滑归位', (tester) async {
    const track = Track(
      id: 'aurora-rhythm-test',
      title: '夜航星河',
      artist: '林深时见鹿',
      album: '测试专辑',
      duration: Duration(minutes: 4),
      audioAsset: '',
      coverAsset: '',
      lyricsAsset: '',
    );

    Future<void> pumpAurora({
      required bool playing,
      bool reduceMotion = false,
    }) {
      return tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
            home: Scaffold(
              backgroundColor: Colors.black,
              body: AlternativePlayerStage(
                style: PlayerVisualStyle.aurora,
                track: track,
                vinylRotating: playing,
                routeAnimation: kAlwaysCompleteAnimation,
                favorite: false,
                onToggleFavorite: () {},
                onShowLyrics: () {},
              ),
            ),
          ),
        ),
      );
    }

    double currentScale() {
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('aurora-disc-rhythm-scale')),
      );
      return transform.transform.getMaxScaleOnAxis();
    }

    await pumpAurora(playing: false);
    expect(
      find.byKey(const ValueKey('aurora-orbit-repaint-boundary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('aurora-rhythm-painter')), findsOneWidget);
    expect(currentScale(), closeTo(1, .0001));

    await pumpAurora(playing: true);
    await tester.pump(const Duration(milliseconds: 520));
    expect(currentScale(), greaterThan(1.003));

    await pumpAurora(playing: false);
    await tester.pump(const Duration(milliseconds: 900));
    expect(currentScale(), closeTo(1, .0001));
    await tester.pump(const Duration(milliseconds: 300));
    expect(currentScale(), closeTo(1, .0001));

    await pumpAurora(playing: true, reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 800));
    expect(currentScale(), closeTo(1, .0001));
  });

  testWidgets('tablet cosmic pulse stage centers the disc vertically', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2048);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const track = Track(
      id: 'tablet-stage-test',
      title: '陈粒 - 光',
      artist: 'Johnaa Erobertsh',
      album: '测试专辑',
      duration: Duration(minutes: 4),
      audioAsset: '',
      coverAsset: '',
      lyricsAsset: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlternativePlayerStage(
            style: PlayerVisualStyle.cassette,
            track: track,
            vinylRotating: false,
            routeAnimation: kAlwaysCompleteAnimation,
            favorite: false,
            onToggleFavorite: () {},
            onShowLyrics: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final discCenter = tester.getCenter(
      find.byKey(const ValueKey('cosmic-pulse-stage')),
    );
    expect(discCenter.dy, inInclusiveRange(900, 1050));
    expect(tester.takeException(), isNull);
  });
}
