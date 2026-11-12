import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/artwork_reveal_boundary.dart';

/// Advance both real codec/file events and the widget clock. pumpAndSettle
/// alone can exhaust virtual minutes before a real asset decode gets a turn;
/// an intentional unified loader also prevents its old early-settle behavior.
Future<void> pumpArtworkReady(WidgetTester tester) async {
  final pending = <ArtworkRevealController>{};
  for (var i = 0; i < 240; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    pending.clear();
    for (final finder in [
      find.byType(ArtworkImage),
      find.byType(ArtworkPendingContent),
    ]) {
      for (final element in finder.evaluate()) {
        final controller = ArtworkRevealBoundary.of(element);
        if (controller != null && controller.pending.value) {
          pending.add(controller);
        }
      }
    }
    if (pending.isEmpty) return;
  }
  expect(
    pending,
    isEmpty,
    reason: 'Visible content must decode or reach an explicit failure state.',
  );
}
