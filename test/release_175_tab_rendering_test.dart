import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';
import 'package:mesting_music/shared/widgets/beta_tab_motion.dart';

/// Paint observations cover a real viewport rather than merely asserting its
/// selected index: a distant tab must never paint unrelated intermediate pages.
class _PaintProbe extends CustomPainter {
  _PaintProbe(this.index, this.painted);
  final int index;
  final Set<int> painted;
  @override
  void paint(Canvas canvas, Size size) {
    painted.add(index);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(covariant _PaintProbe oldDelegate) => false;
}

void main() {
  test(
    'retarget preserves both positions on reversal and keeps the visible strip adjacent through bursts',
    () {
      final motion = BetaTabMotion(0);
      motion.retarget(3, 1);
      final before = motion.positions(.35);
      motion.retarget(0, .35);
      expect(motion.positions(0), before);
      for (final index in [2, 1, 3, 0, 3, 1, 0]) {
        motion.retarget(index, .25);
        final positions = motion.positions(.5).values.toList()..sort();
        expect(positions.length, lessThanOrEqualTo(3));
        expect(positions.last - positions.first, lessThanOrEqualTo(2.00001));
        expect(positions.first, lessThanOrEqualTo(0));
        expect(positions.last, greaterThanOrEqualTo(0));
      }
      motion.settle();
      expect(motion.positions(1), {0: 0});
    },
  );
  testWidgets('distant root selection paints only its two endpoints', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    final painted = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (_, index, _) => BetaRootTabViewport(
            index: index,
            children: [
              for (var i = 0; i < 4; i++)
                CustomPaint(
                  painter: _PaintProbe(i, painted),
                  child: Text('tab$i'),
                ),
            ],
          ),
        ),
      ),
    );
    painted.clear();
    selected.value = 3;
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      painted.difference({0, 3}),
      isEmpty,
      reason: 'Root shortcuts must not paint unrelated intermediate pages',
    );
    expect(find.text('tab3').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    selected.dispose();
  });

  testWidgets(
    'hidden visited tabs do not rebuild for another tabs settling or keep ticking',
    (tester) async {
      final selected = ValueNotifier(0);
      var hiddenBuilds = 0;
      final children = <Widget>[
        const Text('zero'),
        Builder(
          builder: (context) {
            BetaTabVisibility.of(context);
            BetaTabVisibility.settledOf(context);
            hiddenBuilds++;
            return const Text('one');
          },
        ),
        const Text('two'),
        const Text('three'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: selected,
            builder: (_, index, _) =>
                BetaRootTabViewport(index: index, children: children),
          ),
        ),
      );
      selected.value = 1;
      await tester.pumpAndSettle();
      selected.value = 0;
      await tester.pumpAndSettle();
      final before = hiddenBuilds;
      selected.value = 3;
      await tester.pumpAndSettle();
      expect(hiddenBuilds, before);
      expect(find.text('three').hitTestable(), findsOneWidget);
      expect(find.text('one').hitTestable(), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      selected.dispose();
    },
  );
}
