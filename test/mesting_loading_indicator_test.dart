import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:math_curve_loaders/math_curve_loaders.dart';
import 'package:mesting_music/shared/widgets/mesting_loading_indicator.dart';

void main() {
  testWidgets(
    'shared loading indicator is animated, text-free and accessible',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: MestingLoadingIndicator(semanticLabel: '正在加载好友主页'),
            ),
          ),
        ),
      );

      final indicator = find.byType(MestingLoadingIndicator);
      expect(indicator, findsOneWidget);
      expect(tester.widget<MestingLoadingIndicator>(indicator).size, 60);
      expect(
        find.descendant(of: indicator, matching: find.byType(ShaderMask)),
        findsOneWidget,
      );
      expect(find.textContaining('正在加载'), findsNothing);
      expect(find.bySemanticsLabel('正在加载好友主页'), findsOneWidget);

      final loader = tester.widget<MathCurveLoader>(
        find.byType(MathCurveLoader),
      );
      expect(loader.duration, const Duration(milliseconds: 2800));
      expect(loader.respectReducedMotion, isTrue);
      expect(loader.style.particleCount, 62);
      expect(loader.style.trailSpan, .34);
    },
  );
}
