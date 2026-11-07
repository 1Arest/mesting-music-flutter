import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/playing_equalizer.dart';

void main() {
  test('不同动画相位会生成不同的五根音柱高度', () {
    final firstFrame = List.generate(
      5,
      (index) => playingEqualizerBarHeight(
        progress: 0,
        index: index,
        canvasHeight: 22,
      ),
    );
    final nextFrame = List.generate(
      5,
      (index) => playingEqualizerBarHeight(
        progress: .24,
        index: index,
        canvasHeight: 22,
      ),
    );

    expect(nextFrame, isNot(equals(firstFrame)));
    expect(firstFrame.toSet(), hasLength(greaterThan(2)));
    expect(nextFrame.toSet(), hasLength(greaterThan(2)));
  });

  testWidgets('播放状态挂载独立重绘的动态音柱', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: PlayingEqualizer(animate: true))),
      ),
    );

    expect(find.bySemanticsLabel('正在播放'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('playing-equalizer-repaint-boundary')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('playing-equalizer-repaint-boundary')),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('停止动画时保留静态状态语义', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: PlayingEqualizer(animate: false))),
      ),
    );

    expect(find.bySemanticsLabel('播放已暂停'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('playing-equalizer-repaint-boundary')),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}
