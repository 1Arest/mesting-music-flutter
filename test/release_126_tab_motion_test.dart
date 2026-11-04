import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'package:mesting_music/shared/widgets/beta_tab_navigation.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'root replacement moves both surfaces in the approved direction reduced=$reduced',
      (tester) async {
        final queue = BetaTabNavigation();
        var selected = 0;
        late StateSetter update;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [betaTabNavigationProvider.overrideWithValue(queue)],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    final tab = selected;
                    return Navigator(
                      onDidRemovePage: (_) {},
                      pages: [
                        CustomTransitionPage<void>(
                          key: ValueKey(selected),
                          transitionDuration: const Duration(milliseconds: 360),
                          child: BetaTabRouteReady(
                            index: selected,
                            child: Text('tab-$selected'),
                          ),
                          transitionsBuilder:
                              (context, animation, secondary, child) =>
                                  BetaRootTabMotion(
                                    index: tab,
                                    animation: animation,
                                    secondary: secondary,
                                    child: child,
                                  ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        void go(int index) => queue.request(
          index: index,
          currentIndex: selected,
          navigate: (value) => update(() => selected = value),
        );
        double offset(int index) => tester
            .widget<FractionalTranslation>(
              find.byKey(
                ValueKey('beta-root-tab-motion-$index'),
                skipOffstage: false,
              ),
            )
            .translation
            .dx;
        // Exercise every adjacent direction and jumps in the actual page
        // replacement, not only the sign of a helper's direction getter.
        for (final target in [1, 2, 3, 2, 1, 0, 3, 0]) {
          final previous = selected;
          go(target);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          if (!reduced) {
            final sign = target > previous ? 1 : -1;
            expect(offset(target) * sign, greaterThan(0));
            expect(offset(previous) * sign, lessThan(0));
            expect(
              (offset(target) - offset(previous)) * sign,
              closeTo(1, .001),
            );
          } else {
            expect(
              find.byKey(ValueKey('beta-root-tab-motion-$target')),
              findsNothing,
            );
          }
          await tester.pumpAndSettle();
          expect(find.text('tab-$target'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        queue.dispose();
      },
    );
  }
}
