import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/experience/presentation/player_pull_to_dismiss.dart';
import 'package:mesting_music/features/experience/presentation/player_swipe_to_comments.dart';

Widget _page({
  required Future<void> Function() open,
  bool enabled = true,
  Widget child = const SizedBox.expand(),
}) => MaterialApp(
  home: Scaffold(
    body: PlayerSwipeToComments(
      enabled: enabled,
      onOpenComments: open,
      child: child,
    ),
  ),
);

void main() {
  testWidgets('封面上滑进入评论，返回后再次上滑仍可进入', (tester) async {
    var opens = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: PlayerSwipeToComments(
            enabled: true,
            onOpenComments: () async {
              opens++;
              await navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('当前歌曲评论')),
                ),
              );
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(find.text('当前歌曲评论'), findsOneWidget);
    expect(opens, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(opens, 2);
  });

  testWidgets('下滑、横滑、短距离和取消手势不进入评论', (tester) async {
    var opens = 0;
    await tester.pumpWidget(_page(open: () async => opens++));
    for (final movement in [
      const Offset(0, 150),
      const Offset(150, 0),
      const Offset(0, -30),
      const Offset(140, -90),
    ]) {
      await tester.timedDragFrom(
        const Offset(200, 300),
        movement,
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(opens, 0, reason: 'movement: $movement');
    }
    final drag = await tester.startGesture(const Offset(200, 400));
    await drag.moveBy(const Offset(0, -140));
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(opens, 0);
  });

  testWidgets('打开中不重复进入，完成后恢复手势', (tester) async {
    var opens = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      _page(
        open: () {
          opens++;
          return opens == 1 ? pending.future : Future.value();
        },
      ),
    );
    for (var i = 0; i < 2; i++) {
      await tester.dragFrom(const Offset(200, 400), const Offset(0, -160));
      await tester.pump();
    }
    expect(opens, 1);
    pending.complete();
    await tester.pump();
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -160));
    await tester.pump();
    expect(opens, 2);
  });

  testWidgets('歌词状态关闭手势，歌词列表正常滚动', (tester) async {
    var opens = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _page(
        enabled: false,
        open: () async => opens++,
        child: ListView.builder(
          controller: scroll,
          itemExtent: 70,
          itemCount: 40,
          itemBuilder: (_, index) => Text('歌词 $index'),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(100));
    expect(opens, 0);
  });

  testWidgets('短屏封面布局的内部滚动优先，不打开评论', (tester) async {
    var opens = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _page(
        open: () async => opens++,
        child: SingleChildScrollView(
          controller: scroll,
          child: const SizedBox(height: 1500, width: double.infinity),
        ),
      ),
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(100));
    expect(opens, 0);
  });

  testWidgets('进度条横向拖动和封面点击继续响应', (tester) async {
    var opens = 0, taps = 0;
    var progress = .2;
    await tester.pumpWidget(
      _page(
        open: () async => opens++,
        child: Column(
          children: [
            GestureDetector(
              onTap: () => taps++,
              child: const SizedBox(height: 200, width: 200, child: Text('封面')),
            ),
            Slider(value: progress, onChanged: (next) => progress = next),
          ],
        ),
      ),
    );
    await tester.tap(find.text('封面'));
    await tester.drag(find.byType(Slider), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(progress, greaterThan(.2));
    expect(opens, 0);
  });

  testWidgets('顶部下拉收起手柄继续工作，不与评论手势竞争', (tester) async {
    var opens = 0, dismisses = 0;
    await tester.pumpWidget(
      _page(
        open: () async => opens++,
        child: PlayerPullToDismiss(
          onDismiss: () => dismisses++,
          child: Column(
            children: [
              PlayerDismissHandle(onTap: () {}),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('player-dismiss-handle')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    expect(dismisses, 1);
    expect(opens, 0);
  });
}
