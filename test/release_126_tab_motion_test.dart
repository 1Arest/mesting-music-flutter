import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'retained root viewport animates and respects reduced motion reduced=$reduced',
      (tester) async {
        var selected = 0;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return BetaRootTabViewport(
                    index: selected,
                    children: [
                      for (var i = 0; i < 4; i++)
                        SizedBox.expand(
                          key: ValueKey('tab-surface-$i'),
                          child: Center(child: Text('tab-$i')),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        final viewport = tester.state<BetaRootTabViewportState>(
          find.byType(BetaRootTabViewport),
        );
        double left(int i) =>
            tester.getRect(find.byKey(ValueKey('tab-surface-$i'))).left;
        for (final target in [1, 2, 3, 2, 1, 0, 3, 0]) {
          update(() => selected = target);
          await tester.pump();
          final bounds = tester.getRect(find.byType(BetaRootTabViewport));
          final offset = (left(target) - bounds.left) / bounds.width;
          expect(offset.abs(), reduced ? 0 : 1);
          expect(viewport.motionSettled, reduced);
          await tester.pump(const Duration(milliseconds: 180));
          if (reduced) {
            expect(left(target), closeTo(bounds.left, .001));
          } else {
            expect(
              (left(target) - bounds.left).abs(),
              closeTo(
                bounds.width * (1 - Curves.easeInOutCubic.transform(.5)),
                2,
              ),
            );
            expect(viewport.paintedIndices.length, 2);
          }
          await tester.pumpAndSettle();
          expect(left(target), closeTo(bounds.left, .001));
          expect(viewport.selectedIndex, target);
          expect(viewport.motionSettled, isTrue);
          expect(find.text('tab-$target').hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
