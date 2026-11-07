import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/features/player/presentation/music_page_transition.dart';

void main() {
  test('底部栏目按照索引决定左右滑动方向', () {
    final toRightTab = MusicPageTransitionIntent.betweenTabs(0, 1);
    final toLeftTab = MusicPageTransitionIntent.betweenTabs(2, 0);

    expect(toRightTab.direction, MusicPageTransitionDirection.forward);
    expect(toRightTab.horizontalOffset, greaterThan(0));
    expect(toLeftTab.direction, MusicPageTransitionDirection.backward);
    expect(toLeftTab.horizontalOffset, lessThan(0));
  });

  test('下一级页面进入和返回使用相反方向', () {
    const forward = MusicPageTransitionIntent.forward();
    const backward = MusicPageTransitionIntent.backward();

    expect(forward.horizontalOffset, musicPageHorizontalOffset);
    expect(backward.horizontalOffset, -musicPageHorizontalOffset);
  });

  test('侧栏入口复用侧栏的左侧滑入转场', () {
    const fromHub = MusicPageTransitionIntent.fromMusicHubPanel();

    expect(fromHub.usesMusicHubPanelTransition, isTrue);
    expect(fromHub.direction, MusicPageTransitionDirection.forward);
    expect(musicHubPanelTransitionDuration, const Duration(milliseconds: 310));
    expect(musicHubPanelTransitionOffset, const Offset(-1, 0));
    expect(musicHubPanelTransitionCurve, Curves.easeOutCubic);
    expect(musicHubPanelReverseTransitionCurve, Curves.easeInCubic);
    expect(
      musicHubDestinationTransitionDuration,
      const Duration(milliseconds: 300),
    );
    expect(
      musicHubDestinationReverseTransitionDuration,
      const Duration(milliseconds: 240),
    );
    expect(musicHubDestinationTransitionOffset.dx, inExclusiveRange(-.1, 0));
  });

  testWidgets('侧栏转场从左侧滑入并同步淡入', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: musicHubPanelTransitionDuration,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicHubPanelTransition(
            animation: controller,
            child: const ColoredBox(
              key: ValueKey('music-hub-transition-destination'),
              color: Colors.red,
            ),
          ),
        ),
      ),
    );

    final transition = find.byType(MusicHubPanelTransition);
    final slideFinder = find.descendant(
      of: transition,
      matching: find.byType(SlideTransition),
    );
    final fadeFinder = find.descendant(
      of: transition,
      matching: find.byType(FadeTransition),
    );
    var slide = tester.widget<SlideTransition>(slideFinder);
    var fade = tester.widget<FadeTransition>(fadeFinder);
    expect(slide.position.value, musicHubPanelTransitionOffset);
    expect(fade.opacity.value, 0);

    controller.value = .5;
    await tester.pump();
    slide = tester.widget<SlideTransition>(slideFinder);
    fade = tester.widget<FadeTransition>(fadeFinder);
    expect(slide.position.value.dx, inInclusiveRange(-1, 0));
    expect(fade.opacity.value, inInclusiveRange(0, 1));

    controller.value = 1;
    await tester.pump();
    slide = tester.widget<SlideTransition>(slideFinder);
    fade = tester.widget<FadeTransition>(fadeFinder);
    expect(slide.position.value, Offset.zero);
    expect(fade.opacity.value, 1);
  });

  testWidgets('侧栏目标页仅在单层交接后开始短距离滑入', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: musicHubDestinationTransitionDuration,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicHubDestinationTransition(
            animation: controller,
            child: const ColoredBox(
              key: ValueKey('music-hub-destination'),
              color: Colors.red,
            ),
          ),
        ),
      ),
    );

    final transition = find.byType(MusicHubDestinationTransition);
    final slideFinder = find.descendant(
      of: transition,
      matching: find.byKey(const ValueKey('music-hub-destination-slide')),
    );
    var slide = tester.widget<SlideTransition>(slideFinder);
    expect(slide.position.value, musicHubDestinationTransitionOffset);
    expect(
      find.byKey(const ValueKey('music-hub-destination-clip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('music-hub-destination-opaque-underlay')),
      findsNothing,
    );
    expect(
      find.descendant(of: transition, matching: find.byType(FadeTransition)),
      findsNothing,
    );

    controller.value = musicPageHandoffProgress - .01;
    await tester.pump();
    slide = tester.widget<SlideTransition>(slideFinder);
    expect(slide.position.value, musicHubDestinationTransitionOffset);

    controller.value = .5;
    await tester.pump();
    slide = tester.widget<SlideTransition>(slideFinder);
    expect(slide.position.value.dx, inExclusiveRange(-.055, 0));

    controller.value = 1;
    await tester.pump();
    slide = tester.widget<SlideTransition>(slideFinder);
    expect(slide.position.value, Offset.zero);
  });

  testWidgets('根导航目标页使用真正不透明的语义底层', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: musicHubDestinationTransitionDuration,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
            surface: const Color(0x8011141B),
          ),
        ),
        home: MusicHubDestinationTransition(
          animation: controller,
          blockUnderlyingContent: true,
          child: const ColoredBox(color: Colors.red),
        ),
      ),
    );

    final underlay = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('music-hub-destination-opaque-underlay')),
    );
    expect(underlay.color.a, 1);
    expect(underlay.color, isNot(Colors.transparent));
  });

  test('侧栏目标路由和根导航免责声明都保留单层交接保护', () {
    final routerSource = File(
      'lib/app/router/app_router.dart',
    ).readAsStringSync();
    final disclaimerSource = File(
      'lib/features/legal/presentation/disclaimer_dialog.dart',
    ).readAsStringSync();

    expect(routerSource, contains('return MusicHubDestinationLayerHandoff('));
    expect(disclaimerSource, contains('? MusicHubDestinationLayerHandoff('));
    expect(disclaimerSource, contains('blockUnderlyingContent: true'));
  });

  test('全部歌单使用集合展开动画而不是横向滑动', () {
    expect(collectionRevealVerticalOffset, greaterThan(0));
    expect(collectionRevealStartScale, lessThan(1));
    expect(collectionRevealDuration, const Duration(milliseconds: 380));
    expect(collectionRevealReverseDuration, const Duration(milliseconds: 340));
  });

  testWidgets(
    'transition clips moving content without painting a fake surface',
    (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 300),
        value: .35,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MusicPageTransitionSurface(
              position: Tween<Offset>(
                begin: const Offset(.08, 0),
                end: Offset.zero,
              ).animate(controller),
              child: const ColoredBox(
                key: ValueKey('destination-content'),
                color: Colors.red,
              ),
            ),
          ),
        ),
      );

      final clip = find.byKey(
        const ValueKey('music-page-transition-content-clip'),
      );
      final movingContent = find.byKey(
        const ValueKey('music-page-transition-moving-content'),
      );
      expect(clip, findsOneWidget);
      expect(tester.getSize(clip), tester.getSize(find.byType(Scaffold)));
      expect(
        find.descendant(of: clip, matching: movingContent),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('music-page-transition-opaque-surface')),
        findsNothing,
      );
    },
  );

  test('route progress creates a smooth strict single-layer handoff', () {
    expect(
      musicPageLayerIsVisible(
        primaryStatus: AnimationStatus.completed,
        primaryValue: 1,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
      ),
      isTrue,
    );
    expect(
      musicPageLayerIsVisible(
        primaryStatus: AnimationStatus.completed,
        primaryValue: 1,
        secondaryStatus: AnimationStatus.forward,
        secondaryValue: .2,
      ),
      isTrue,
    );
    expect(
      musicPageLayerIsVisible(
        primaryStatus: AnimationStatus.completed,
        primaryValue: 1,
        secondaryStatus: AnimationStatus.forward,
        secondaryValue: .5,
      ),
      isFalse,
    );
    expect(
      musicPageLayerIsVisible(
        primaryStatus: AnimationStatus.forward,
        primaryValue: .2,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
      ),
      isFalse,
    );
    expect(
      musicPageLayerIsVisible(
        primaryStatus: AnimationStatus.forward,
        primaryValue: .5,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
      ),
      isTrue,
    );
    expect(
      musicPageLayerIsVisible(
        primaryStatus: AnimationStatus.reverse,
        primaryValue: .8,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
      ),
      isTrue,
    );
    expect(
      musicPageLayerIsVisible(
        primaryStatus: AnimationStatus.reverse,
        primaryValue: .4,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
      ),
      isFalse,
    );
  });

  test('push and pop keep one fully opaque page layer without a flash', () {
    expect(musicPageUsesRouteSnapshotting, isFalse);
    expect(musicPageLayerOpacityFloor, 1);
    for (var step = 0; step <= 100; step += 1) {
      final progress = step / 100;
      final outgoingPush = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.completed,
        primaryValue: 1,
        secondaryStatus: AnimationStatus.forward,
        secondaryValue: progress,
      );
      final incomingPush = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.forward,
        primaryValue: progress,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
      );
      expect(
        outgoingPush > 0 && incomingPush > 0,
        isFalse,
        reason: 'push progress $progress overlaps page content',
      );
      expect(
        outgoingPush > 0 ? outgoingPush : incomingPush,
        1,
        reason: 'push progress $progress composites a translucent page',
      );

      final outgoingPop = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.reverse,
        primaryValue: 1 - progress,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
      );
      final incomingPop = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.completed,
        primaryValue: 1,
        secondaryStatus: AnimationStatus.reverse,
        secondaryValue: 1 - progress,
      );
      expect(
        outgoingPop > 0 && incomingPop > 0,
        isFalse,
        reason: 'pop progress $progress overlaps page content',
      );
      expect(
        outgoingPop > 0 ? outgoingPop : incomingPop,
        1,
        reason: 'pop progress $progress composites a translucent page',
      );
    }
  });

  test('消息页的提前交接仍保持单层内容', () {
    for (var step = 0; step <= 100; step += 1) {
      final progress = step / 100;
      final outgoing = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.completed,
        primaryValue: 1,
        secondaryStatus: AnimationStatus.forward,
        secondaryValue: progress,
        handoffProgress: messagesPageHandoffProgress,
      );
      final incoming = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.forward,
        primaryValue: progress,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
        handoffProgress: messagesPageHandoffProgress,
      );
      expect(
        outgoing > 0 && incoming > 0,
        isFalse,
        reason: 'progress $progress',
      );
      expect(outgoing > 0 ? outgoing : incoming, 1);
    }
  });

  test('从消息列表打开会话后，返回时也保持单层内容', () {
    const conversation = MusicPageTransitionIntent.messagesConversation();
    expect(conversation.handoffProgress, messagesPageHandoffProgress);

    for (var step = 0; step <= 100; step += 1) {
      final progress = step / 100;
      final conversationLayer = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.reverse,
        primaryValue: 1 - progress,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
        handoffProgress: conversation.handoffProgress!,
      );
      final messagesLayer = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.completed,
        primaryValue: 1,
        secondaryStatus: AnimationStatus.reverse,
        secondaryValue: 1 - progress,
        handoffProgress: messagesPageHandoffProgress,
      );
      expect(
        conversationLayer > 0 && messagesLayer > 0,
        isFalse,
        reason: '返回进度 $progress 重叠绘制了会话和消息列表',
      );
      expect(
        conversationLayer > 0 ? conversationLayer : messagesLayer,
        1,
        reason: '返回进度 $progress 暴露了页面背景',
      );
    }
  });

  test('编辑资料页回退使用连续的单层交接', () {
    expect(profileEditPageHandoffProgress, musicPageHandoffProgress);
    expect(
      profileEditPageReverseTransitionDuration,
      lessThan(musicPageReverseTransitionDuration),
    );
    expect(
      profileEditPageHorizontalOffset,
      lessThan(musicPageHorizontalOffset),
    );
    expect(profileEditPageStartScale, lessThan(1));

    for (var step = 0; step <= 100; step += 1) {
      final progress = step / 100;
      final editor = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.reverse,
        primaryValue: 1 - progress,
        secondaryStatus: AnimationStatus.dismissed,
        secondaryValue: 0,
        handoffProgress: profileEditPageHandoffProgress,
      );
      final profile = musicPageLayerOpacity(
        primaryStatus: AnimationStatus.completed,
        primaryValue: 1,
        secondaryStatus: AnimationStatus.reverse,
        secondaryValue: 1 - progress,
      );
      expect(
        editor > 0 && profile > 0,
        isFalse,
        reason: '回退进度 $progress 重叠绘制了两层页面',
      );
      expect(
        editor > 0 ? editor : profile,
        1,
        reason: '回退进度 $progress 暴露了页面背景',
      );
    }
  });

  testWidgets(
    'outgoing page stays opaque before handing off to the next layer',
    (tester) async {
      final secondary = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 300),
      );
      final primary = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 300),
        value: 1,
      );
      addTearDown(secondary.dispose);
      addTearDown(primary.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MusicPageSingleLayerHandoff(
            primaryAnimation: primary,
            secondaryAnimation: secondary,
            child: const ColoredBox(
              key: ValueKey('outgoing-page'),
              color: Colors.red,
            ),
          ),
        ),
      );

      Offstage outgoingLayer() => tester.widget<Offstage>(
        find.byKey(const ValueKey('music-page-outgoing-layer')),
      );
      Opacity layerOpacity() => tester.widget<Opacity>(
        find.byKey(const ValueKey('music-page-layer-opacity')),
      );

      expect(outgoingLayer().offstage, isFalse);
      expect(layerOpacity().opacity, 1);
      secondary.forward();
      await tester.pump();
      expect(secondary.status, AnimationStatus.forward);
      expect(outgoingLayer().offstage, isFalse);
      await tester.pump(const Duration(milliseconds: 80));
      expect(outgoingLayer().offstage, isFalse);
      expect(layerOpacity().opacity, 1);
      await tester.pump(const Duration(milliseconds: 60));
      expect(outgoingLayer().offstage, isTrue);

      await tester.pumpAndSettle();
      expect(outgoingLayer().offstage, isTrue);
      secondary.reverse();
      await tester.pump();
      expect(outgoingLayer().offstage, isTrue);
      await tester.pump(const Duration(milliseconds: 150));
      expect(outgoingLayer().offstage, isFalse);
      expect(layerOpacity().opacity, 1);
      await tester.pumpAndSettle();
      expect(secondary.status, AnimationStatus.dismissed);
      expect(outgoingLayer().offstage, isFalse);
      expect(layerOpacity().opacity, 1);
    },
  );

  testWidgets(
    'a hub destination stops painting when its next route takes over',
    (tester) async {
      final secondary = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 300),
      );
      addTearDown(secondary.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MusicPageOutgoingLayerHandoff(
            secondaryAnimation: secondary,
            child: const ColoredBox(
              key: ValueKey('hub-destination'),
              color: Colors.red,
            ),
          ),
        ),
      );

      Offstage layer() => tester.widget<Offstage>(
        find.byKey(const ValueKey('music-page-outgoing-layer')),
      );

      expect(layer().offstage, isFalse);
      secondary.forward();
      secondary.value = .3;
      await tester.pump();
      expect(layer().offstage, isFalse);
      secondary.value = .5;
      await tester.pump();
      expect(layer().offstage, isTrue);

      secondary.value = 1;
      await tester.pump();
      expect(layer().offstage, isTrue);
      secondary.reverse(from: .5);
      await tester.pump();
      expect(layer().offstage, isFalse);
      secondary.stop();
    },
  );

  testWidgets(
    'the messages hub destination hands off at the messages threshold',
    (tester) async {
      final secondary = AnimationController(
        vsync: tester,
        duration: messagesPageTransitionDuration,
      );
      addTearDown(secondary.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MusicPageOutgoingLayerHandoff(
            secondaryAnimation: secondary,
            handoffProgress: messagesPageHandoffProgress,
            child: const ColoredBox(
              key: ValueKey('messages-hub-destination'),
              color: Colors.red,
            ),
          ),
        ),
      );

      Offstage layer() => tester.widget<Offstage>(
        find.byKey(const ValueKey('music-page-outgoing-layer')),
      );

      secondary.forward();
      secondary.value = messagesPageHandoffProgress - .01;
      await tester.pump();
      expect(layer().offstage, isFalse);
      secondary.value = messagesPageHandoffProgress;
      await tester.pump();
      expect(layer().offstage, isTrue);
      secondary.stop();
    },
  );

  testWidgets('侧栏目标页逐帧切换时始终只绘制一个页面内容层', (tester) async {
    final progress = AnimationController(
      vsync: tester,
      duration: musicHubDestinationTransitionDuration,
    );
    final outgoingPrimary = AnimationController(
      vsync: tester,
      duration: musicHubDestinationTransitionDuration,
      value: 1,
    );
    addTearDown(progress.dispose);
    addTearDown(outgoingPrimary.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            MusicPageSingleLayerHandoff(
              primaryAnimation: outgoingPrimary,
              secondaryAnimation: progress,
              child: const ColoredBox(
                key: ValueKey('recommendation-content'),
                color: Colors.red,
              ),
            ),
            MusicHubDestinationLayerHandoff(
              primaryAnimation: progress,
              secondaryAnimation: const AlwaysStoppedAnimation<double>(0),
              child: const ColoredBox(
                key: ValueKey('settings-content'),
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );

    progress.forward();
    for (var step = 0; step <= 100; step += 1) {
      progress.value = step / 100;
      await tester.pump();
      expect(
        _paintedLayerCount(tester),
        1,
        reason:
            '侧栏目标页进入进度 ${progress.value} 出现内容重叠或空帧：'
            '${_layerStatuses(tester)}',
      );
    }
  });

  testWidgets(
    'four bottom tabs keep exactly one painted page while switching',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/tab/0',
        routes: [
          for (var index = 0; index < 4; index++)
            GoRoute(
              path: '/tab/$index',
              pageBuilder: (context, state) => _ProbeTransitionPage(
                key: state.pageKey,
                child: _TabProbePage(index: index),
              ),
            ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      for (final target in <int>[1, 2, 3, 0]) {
        await tester.tap(find.byKey(ValueKey('switch-to-$target')));
        await tester.pump();
        expect(_paintedLayerCount(tester), 1, reason: _layerStatuses(tester));

        await tester.pump(const Duration(milliseconds: 150));
        expect(
          _paintedLayerCount(tester),
          1,
          reason:
              '切换到第 $target 个底栏页面时只能绘制一个页面内容层：'
              '${_layerStatuses(tester)}',
        );

        await tester.pumpAndSettle();
        expect(find.text('page-$target'), findsOneWidget);
        expect(_paintedLayerCount(tester), 1);
      }
    },
  );
}

int _paintedLayerCount(WidgetTester tester) {
  return tester
      .widgetList<Offstage>(
        find.byKey(const ValueKey('music-page-outgoing-layer')),
      )
      .where((layer) => !layer.offstage)
      .length;
}

String _layerStatuses(WidgetTester tester) {
  return tester
      .widgetList<MusicPageSingleLayerHandoff>(
        find.byType(MusicPageSingleLayerHandoff),
      )
      .map(
        (layer) =>
            '${layer.primaryAnimation.status.name}/'
            '${layer.secondaryAnimation.status.name}',
      )
      .join(', ');
}

class _ProbeTransitionPage extends Page<void> {
  const _ProbeTransitionPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder<void>(
      settings: this,
      opaque: true,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return MusicPageSingleLayerHandoff(
          primaryAnimation: animation,
          secondaryAnimation: secondaryAnimation,
          child: MusicPageTransitionSurface(
            position: Tween<Offset>(
              begin: const Offset(.08, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
    );
  }
}

class _TabProbePage extends StatelessWidget {
  const _TabProbePage({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(child: Text('page-$index')),
      bottomNavigationBar: Row(
        children: [
          for (var target = 0; target < 4; target++)
            Expanded(
              child: TextButton(
                key: ValueKey('switch-to-$target'),
                onPressed: () => context.go('/tab/$target'),
                child: Text('$target'),
              ),
            ),
        ],
      ),
    );
  }
}
