import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'retained root viewport follows approved direction reduced=$reduced',
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
          final previous = selected;
          update(() => selected = target);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          final bounds = tester.getRect(find.byType(BetaRootTabViewport));
          final offset = (left(target) - bounds.left) / bounds.width;
          if (reduced) {
            expect(offset, 0);
          } else {
            // Observe the real painted surface, independently of a particular
            // scroll widget: distant destinations now travel one screen.
            expect(offset, previous < target ? greaterThan(0) : lessThan(0));
            expect(offset.abs(), lessThan(1));
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
