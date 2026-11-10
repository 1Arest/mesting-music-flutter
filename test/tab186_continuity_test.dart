import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/beta_tab_motion.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';

void main() {
  test(
    'critical retarget preserves visible geometry and never leaves a blank edge or overshoots',
    () {
      for (final initialProgress in [.01, .3, .5, .9, .99]) {
        for (final next in [0, 2, 3]) {
          final g = BetaTabMotion(0)..retarget(1, 1);
          final before = g.positions(initialProgress);
          g.retarget(next, initialProgress);
          final start = g.positions(0);
          for (final e in before.entries.where((e) => e.value.abs() < 1)) {
            expect(start[e.key], e.value);
          }
          for (final speed in [-20.0, -3.0, 0.0, 3.0, 20.0]) {
            final safe = g.safeVelocity(speed);
            final spring = SpringSimulation(
              const SpringDescription(mass: 1, stiffness: 400, damping: 40),
              0,
              1,
              safe / g.distance,
            );
            var crossed = false;
            final x0 = start[next]!;
            for (var ms = 0; ms <= 1200; ms += 4) {
              final p = g.positions(spring.x(ms / 1000));
              final values = p.values.toList()..sort();
              expect(values.first, lessThanOrEqualTo(.00001));
              expect(values.last, greaterThanOrEqualTo(-.00001));
              for (var i = 1; i < values.length; i++) {
                expect(values[i] - values[i - 1], closeTo(1, .00001));
              }
              if (p[next]! * x0 < -.0000001) crossed = true;
            }
            expect(
              crossed,
              isFalse,
              reason:
                  'The destination may brake but must never cross zero and spring back',
            );
          }
        }
      }
    },
  );
  testWidgets(
    'rapid third/reverse selections keep every visible tile continuous and latest destination wins',
    (tester) async {
      final selected = ValueNotifier(0);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: selected,
            builder: (_, i, _) => BetaRootTabViewport(
              index: i,
              children: [
                for (var n = 0; n < 4; n++)
                  SizedBox.expand(
                    key: ValueKey('surface$n'),
                    child: Text('page$n'),
                  ),
              ],
            ),
          ),
        ),
      );
      final viewport = tester.state<BetaRootTabViewportState>(
        find.byType(BetaRootTabViewport),
      );
      double left(int i) =>
          tester.getTopLeft(find.byKey(ValueKey('surface$i'))).dx;
      for (final next in [1, 3, 0, 2, 1, 3, 2, 0]) {
        final before = {for (final i in viewport.paintedIndices) i: left(i)};
        selected.value = next;
        await tester.pump();
        for (final e in before.entries) {
          expect(
            left(e.key),
            closeTo(e.value, .001),
            reason: 'A new target must not swap or reset a visible tile',
          );
        }
        await tester.pump(const Duration(milliseconds: 55));
        final bounds = tester.getRect(find.byType(BetaRootTabViewport));
        final positions = [for (final i in viewport.paintedIndices) left(i)]
          ..sort();
        expect(positions.first, lessThanOrEqualTo(bounds.left + .001));
        expect(
          positions.last + bounds.width,
          greaterThanOrEqualTo(bounds.right - .001),
        );
        expect(viewport.selectedIndex, next);
      }
      await tester.pumpAndSettle();
      expect(viewport.paintedIndices, {0});
      expect(viewport.motionSettled, isTrue);
      expect(left(0), closeTo(0, .001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      selected.dispose();
    },
  );
}
