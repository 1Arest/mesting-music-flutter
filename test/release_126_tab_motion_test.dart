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
                      for (var i = 0; i < 4; i++) Center(child: Text('tab-$i')),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        final controller = tester
            .widget<PageView>(
              find.byKey(const ValueKey('beta-root-tab-viewport')),
            )
            .controller!;
        for (final target in [1, 2, 3, 2, 1, 0, 3, 0]) {
          final previous = selected;
          update(() => selected = target);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          final page = controller.page!;
          if (reduced) {
            expect(page, target.toDouble());
          } else {
            expect(
              page,
              greaterThan(
                previous < target ? previous.toDouble() : target.toDouble(),
              ),
            );
            expect(
              page,
              lessThan(
                previous > target ? previous.toDouble() : target.toDouble(),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(controller.page, closeTo(target.toDouble(), .001));
          expect(find.text('tab-$target').hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
