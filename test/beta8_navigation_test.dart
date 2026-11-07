import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/beta_edge_back.dart';
import 'package:mesting_music/features/experience/presentation/player_pull_to_dismiss.dart';

void main() {
  for (final left in [true, false]) {
    testWidgets('secondary page returns from ${left ? 'left' : 'right'} edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BetaEdgeBack(
                      child: Scaffold(body: Center(child: Text('详情'))),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(BetaEdgeBack));
      await tester.dragFrom(
        Offset(left ? 5 : size.width - 5, size.height * .5),
        Offset(left ? 140 : -140, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('详情'), findsNothing);
      expect(find.text('打开'), findsOneWidget);
    });
  }
  testWidgets(
    'player dismissal starts only on the handle and cancels short pulls',
    (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPullToDismiss(
            onDismiss: () => closed++,
            child: Scaffold(
              body: Column(
                children: [
                  PlayerDismissHandle(onTap: () => closed++),
                  const Expanded(child: Center(child: Text('歌词与封面区域'))),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.text('歌词与封面区域'), const Offset(0, 240));
      await tester.pumpAndSettle();
      expect(closed, 0);
      await tester.timedDrag(
        find.byKey(const ValueKey('player-dismiss-handle')),
        const Offset(0, 30),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(closed, 0);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('player-dismiss-handle')))
            .dy,
        0,
      );
      await tester.timedDrag(
        find.byKey(const ValueKey('player-dismiss-handle')),
        const Offset(0, 260),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(closed, 1);
    },
  );
}
