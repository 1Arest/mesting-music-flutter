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
        go(3);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        if (!reduced) {
          expect(offset(3), lessThan(0));
          expect(offset(0), greaterThan(0));
          expect(offset(0) - offset(3), closeTo(1, .001));
        } else {
          expect(
            find.byKey(const ValueKey('beta-root-tab-motion-3')),
            findsNothing,
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('tab-3'), findsOneWidget);
        go(0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        if (!reduced) {
          expect(offset(0), greaterThan(0));
          expect(offset(3), lessThan(0));
          expect(offset(0) - offset(3), closeTo(1, .001));
        }
        await tester.pumpAndSettle();
        expect(find.text('tab-0'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        queue.dispose();
      },
    );
  }
}
