import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/player/presentation/music_navigation.dart';
import 'package:mesting_music/features/player/presentation/persistent_mini_player.dart';

void main() {
  test('胶囊播放器唱片与盒子等高且播放按钮使用紧凑圆形', () {
    expect(miniPlayerVinylDiameter, miniPlayerHeight);
    expect(miniPlayerPlayControlDiameter, lessThan(44));
    expect(miniPlayerPlayControlDiameter, lessThan(miniPlayerVinylDiameter));
    expect(
      miniPlayerPlaySurfaceDiameter,
      lessThan(miniPlayerPlayControlDiameter),
    );
  });

  test('胶囊和底部导航在所有主题下均不生成外层模糊投影', () {
    const accent = Color(0xFFE66B84);

    expect(miniPlayerOuterShadowsFor(Brightness.light, accent), isEmpty);
    expect(miniPlayerOuterShadowsFor(Brightness.dark, accent), isEmpty);
    expect(miniPlayerVinylShadows, isEmpty);
    expect(musicBottomNavigationOuterShadows, isEmpty);
  });

  test('胶囊用内部高光渐变增加立体感且不依赖黑色外投影', () {
    final colors = miniPlayerDepthGradientColorsFor(
      brightness: Brightness.light,
      accent: const Color(0xFFE66B84),
      base: const Color(0xF2FFFCF8),
    );

    expect(colors, hasLength(3));
    expect(colors.toSet(), hasLength(3));
    expect(
      colors.first.computeLuminance(),
      greaterThan(colors.last.computeLuminance()),
    );
  });
  test('浅色播放控件使用白色圆底和深色图标', () {
    final palette = miniPlayerPlayControlPaletteFor(Brightness.light);

    expect(palette.surface, const Color(0xEFFFFFFF));
    expect(palette.icon, const Color(0xFF27242C));
    expect(palette.progressTrack.a, lessThan(.3));
  });

  test('胶囊横滑按位移或速度稳定映射上一首和下一首', () {
    expect(
      resolveMiniPlayerSwipeAction(
        dragDistance: -miniPlayerSwipeDistanceThreshold,
        primaryVelocity: 0,
      ),
      MiniPlayerSwipeAction.next,
    );
    expect(
      resolveMiniPlayerSwipeAction(
        dragDistance: miniPlayerSwipeDistanceThreshold,
        primaryVelocity: 0,
      ),
      MiniPlayerSwipeAction.previous,
    );
    expect(
      resolveMiniPlayerSwipeAction(
        dragDistance: 4,
        primaryVelocity: -miniPlayerSwipeVelocityThreshold,
      ),
      MiniPlayerSwipeAction.next,
    );
    expect(
      resolveMiniPlayerSwipeAction(
        dragDistance: -4,
        primaryVelocity: miniPlayerSwipeVelocityThreshold,
      ),
      MiniPlayerSwipeAction.previous,
    );
    expect(
      resolveMiniPlayerSwipeAction(
        dragDistance: miniPlayerSwipeDistanceThreshold - 1,
        primaryVelocity: miniPlayerSwipeVelocityThreshold - 1,
      ),
      isNull,
    );
  });

  test('胶囊切歌内容按滑动方向从相反两侧交接', () {
    expect(miniPlayerTrackTransitionHorizontalOffset, .26);
    expect(
      miniPlayerTrackTransitionDuration,
      const Duration(milliseconds: 380),
    );
    expect(miniPlayerTrackTransitionStartScale, inExclusiveRange(.95, 1));
    expect(
      miniPlayerTrackTransitionOffset(
        action: MiniPlayerSwipeAction.next,
        incoming: true,
      ).dx,
      greaterThan(0),
    );
    expect(
      miniPlayerTrackTransitionOffset(
        action: MiniPlayerSwipeAction.next,
        incoming: false,
      ).dx,
      lessThan(0),
    );
    expect(
      miniPlayerTrackTransitionOffset(
        action: MiniPlayerSwipeAction.previous,
        incoming: true,
      ).dx,
      lessThan(0),
    );
    expect(
      miniPlayerTrackTransitionOffset(
        action: MiniPlayerSwipeAction.previous,
        incoming: false,
      ).dx,
      greaterThan(0),
    );
  });

  testWidgets('胶囊切歌时旧内容淡出且新内容滑入', (tester) async {
    Widget app({
      required String trackId,
      required MiniPlayerSwipeAction action,
      bool disableAnimations = false,
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Center(
            child: SizedBox(
              width: 240,
              height: miniPlayerHeight,
              child: ClipRect(
                child: MiniPlayerTrackSwitcher(
                  trackKey: ValueKey<String>(trackId),
                  action: action,
                  child: ColoredBox(color: Colors.white, child: Text(trackId)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      app(trackId: 'first', action: MiniPlayerSwipeAction.next),
    );
    await tester.pumpWidget(
      app(trackId: 'second', action: MiniPlayerSwipeAction.next),
    );
    await tester.pump(const Duration(milliseconds: 80));

    final nextIncoming = tester.widget<SlideTransition>(
      find.byKey(const ValueKey<String>('mini-player-track-incoming-slide')),
    );
    final nextOutgoing = tester.widget<SlideTransition>(
      find.byKey(const ValueKey<String>('mini-player-track-outgoing-slide')),
    );
    final nextIncomingScale = tester.widget<ScaleTransition>(
      find.byKey(const ValueKey<String>('mini-player-track-incoming-scale')),
    );
    final nextOutgoingScale = tester.widget<ScaleTransition>(
      find.byKey(const ValueKey<String>('mini-player-track-outgoing-scale')),
    );
    expect(nextIncoming.position.value.dx, greaterThan(0));
    expect(nextOutgoing.position.value.dx, lessThan(0));
    expect(nextIncomingScale.scale.value, inExclusiveRange(.95, 1));
    expect(nextOutgoingScale.scale.value, inExclusiveRange(.95, 1));
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.pumpWidget(
      app(trackId: 'third', action: MiniPlayerSwipeAction.previous),
    );
    await tester.pump(const Duration(milliseconds: 80));

    final previousIncoming = tester.widget<SlideTransition>(
      find.byKey(const ValueKey<String>('mini-player-track-incoming-slide')),
    );
    final previousOutgoing = tester.widget<SlideTransition>(
      find.byKey(const ValueKey<String>('mini-player-track-outgoing-slide')),
    );
    expect(previousIncoming.position.value.dx, lessThan(0));
    expect(previousOutgoing.position.value.dx, greaterThan(0));

    await tester.pumpWidget(
      app(
        trackId: 'static',
        action: MiniPlayerSwipeAction.next,
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('third'), findsNothing);
    expect(find.text('static'), findsOneWidget);
  });

  testWidgets('胶囊连续切歌时始终保留最新歌曲文字层', (tester) async {
    Widget app(String trackId) {
      return MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            height: miniPlayerHeight,
            child: ClipRect(
              child: MiniPlayerTrackSwitcher(
                trackKey: ValueKey<String>(trackId),
                action: MiniPlayerSwipeAction.next,
                child: Text(trackId),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(app('first'));
    await tester.pumpWidget(app('second'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(app('third'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('third'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsNothing);
    expect(find.text('third'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长曲目信息切入时立即可见且继续保留方向滑动', (tester) async {
    Widget app({required String id, required Widget child}) {
      return MaterialApp(
        home: Center(
          child: SizedBox(
            width: 210,
            height: miniPlayerHeight,
            child: ClipRect(
              child: MiniPlayerTrackSwitcher(
                trackKey: ValueKey<String>(id),
                action: MiniPlayerSwipeAction.next,
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(app(id: 'old', child: const Text('上一首歌曲')));
    await tester.pumpWidget(
      app(
        id: 'long-track',
        child: const Column(
          children: [
            MiniPlayerOverflowMarquee(
              text: '薛之谦《陪你去流浪（3D环绕版）》',
              semanticLabel: '歌曲名称',
              style: TextStyle(fontSize: 14),
            ),
            MiniPlayerOverflowMarquee(
              text: '乐贤baby',
              semanticLabel: '歌手名称',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );

    final incomingSlide = tester.widget<SlideTransition>(
      find.byKey(const ValueKey<String>('mini-player-track-incoming-slide')),
    );
    expect(incomingSlide.position.value.dx, greaterThan(0));
    expect(
      find.byKey(const ValueKey('mini-player-marquee-歌曲名称')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mini-player-static-歌手名称')),
      findsOneWidget,
    );
    final marqueeOverflow = tester.widget<OverflowBox>(
      find.byType(OverflowBox),
    );
    expect(marqueeOverflow.minHeight, isNotNull);
    expect(marqueeOverflow.minHeight!.isFinite, isTrue);
    expect(marqueeOverflow.maxHeight, marqueeOverflow.minHeight);
    expect(tester.getSize(find.byType(OverflowBox)).height.isFinite, isTrue);

    await tester.pump(
      miniPlayerTrackTransitionDuration + const Duration(milliseconds: 1),
    );
    await tester.pump();
    expect(find.text('上一首歌曲'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('胶囊左滑切换下一首且右滑切换上一首', (tester) async {
    var previousCount = 0;
    var nextCount = 0;
    var tapCount = 0;
    final dragProgress = <({double progress, bool dragging})>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 280,
            height: miniPlayerHeight,
            child: MiniPlayerSwipeRegion(
              onPrevious: () => previousCount++,
              onNext: () => nextCount++,
              onDragProgressChanged: (progress, dragging) =>
                  dragProgress.add((progress: progress, dragging: dragging)),
              child: GestureDetector(
                onTap: () => tapCount++,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );

    final swipeArea = find.byKey(const ValueKey('mini-player-swipe-area'));
    await tester.drag(swipeArea, const Offset(-80, 0));
    await tester.pump();
    expect(nextCount, 1);
    expect(previousCount, 0);
    expect(tapCount, 0);
    expect(dragProgress.any((event) => event.progress < 0), isTrue);
    expect(dragProgress.last, (progress: 0, dragging: false));

    dragProgress.clear();
    await tester.drag(swipeArea, const Offset(80, 0));
    await tester.pump();
    expect(nextCount, 1);
    expect(previousCount, 1);
    expect(tapCount, 0);
    expect(dragProgress.any((event) => event.progress > 0), isTrue);
    expect(dragProgress.last, (progress: 0, dragging: false));

    await tester.tap(swipeArea);
    await tester.pump();
    expect(tapCount, 1);
    expect(nextCount, 1);
    expect(previousCount, 1);
  });

  testWidgets('胶囊曲目信息跟随手指位移并在松手后平滑复位', (tester) async {
    Widget app(
      double progress, {
      bool dragging = true,
      bool disableAnimations = false,
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Center(
            child: SizedBox(
              width: 220,
              height: miniPlayerHeight,
              child: MiniPlayerDragMotion(
                progress: progress,
                dragging: dragging,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(app(-1));

    final draggedSlide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey('mini-player-drag-slide')),
    );
    final draggedScale = tester.widget<AnimatedScale>(
      find.byKey(const ValueKey('mini-player-drag-scale')),
    );
    final draggedOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('mini-player-drag-opacity')),
    );
    expect(draggedSlide.offset.dx, -miniPlayerDragTravelFraction);
    expect(draggedSlide.duration, Duration.zero);
    expect(draggedScale.scale, 1 - miniPlayerDragScaleReduction);
    expect(draggedOpacity.opacity, 1 - miniPlayerDragOpacityReduction);

    await tester.pumpWidget(app(0, dragging: false));

    final settlingSlide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey('mini-player-drag-slide')),
    );
    expect(settlingSlide.offset, Offset.zero);
    expect(settlingSlide.duration, miniPlayerDragResetDuration);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(app(-1, disableAnimations: true));
    await tester.pumpWidget(app(0, dragging: false, disableAnimations: true));
    expect(
      tester
          .widget<AnimatedSlide>(
            find.byKey(const ValueKey('mini-player-drag-slide')),
          )
          .duration,
      Duration.zero,
    );
  });

  testWidgets('文字仅在实际超出胶囊可用宽度时启用循环滚动', (tester) async {
    Future<void> pumpMarquee({
      required double width,
      required String text,
      bool animate = true,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: MiniPlayerOverflowMarquee(
                text: text,
                semanticLabel: '歌曲名称',
                style: const TextStyle(fontSize: 14),
                animate: animate,
              ),
            ),
          ),
        ),
      );
    }

    await pumpMarquee(width: 220, text: '短歌名');
    expect(find.byKey(const ValueKey('mini-player-static-歌曲名称')), findsOne);
    expect(
      find.byKey(const ValueKey('mini-player-marquee-歌曲名称')),
      findsNothing,
    );

    await pumpMarquee(width: 72, text: '这是一首非常非常长的歌曲名字');
    expect(find.byKey(const ValueKey('mini-player-static-歌曲名称')), findsNothing);
    expect(find.byKey(const ValueKey('mini-player-marquee-歌曲名称')), findsOne);

    await tester.pump(const Duration(milliseconds: 1300));
    final movingTransform = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(const ValueKey('mini-player-marquee-歌曲名称')),
        matching: find.byType(Transform),
      ),
    );
    expect(movingTransform.transform.getTranslation().x, lessThan(0));
  });

  testWidgets('长文本播放期间从动画首帧开始持续移动', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 72,
            child: MiniPlayerOverflowMarquee(
              text: '这是一首需要持续滚动的很长歌曲名字',
              semanticLabel: '歌曲名称',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );

    double translation() {
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byKey(const ValueKey('mini-player-marquee-歌曲名称')),
          matching: find.byType(Transform),
        ),
      );
      return transform.transform.getTranslation().x;
    }

    expect(translation(), 0);
    await tester.pump(const Duration(milliseconds: 100));
    final firstOffset = translation();
    await tester.pump(const Duration(milliseconds: 100));
    final secondOffset = translation();

    expect(firstOffset, lessThan(0));
    expect(secondOffset, lessThan(firstOffset));
  });

  testWidgets('长文本随播放滚动并在暂停时停在当前位置', (tester) async {
    const longTitle = '薛之谦《陪你去流浪（3D环绕版）》';

    Future<void> pumpMarquee(bool animate) {
      return tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 88,
              child: MiniPlayerOverflowMarquee(
                text: longTitle,
                semanticLabel: '歌曲名称',
                style: const TextStyle(fontSize: 14),
                animate: animate,
              ),
            ),
          ),
        ),
      );
    }

    double translation() {
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byKey(const ValueKey('mini-player-marquee-歌曲名称')),
          matching: find.byType(Transform),
        ),
      );
      return transform.transform.getTranslation().x;
    }

    await pumpMarquee(true);
    await tester.pump(const Duration(milliseconds: 1500));
    final playingOffset = translation();
    expect(playingOffset, lessThan(0));

    await pumpMarquee(false);
    await tester.pump();
    final pausedOffset = translation();
    await tester.pump(const Duration(milliseconds: 900));
    expect(translation(), closeTo(pausedOffset, .001));

    await pumpMarquee(true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(translation(), lessThan(pausedOffset));
  });
}
