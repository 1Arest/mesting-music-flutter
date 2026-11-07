import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/queue/presentation/queue_page.dart';

void main() {
  testWidgets(
    'empty queue keeps only the neutral title and recenters content',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PlaybackQueueEmptyState())),
      );

      expect(find.text('播放列表还是空的'), findsOneWidget);
      expect(find.textContaining('本地音乐'), findsNothing);
      expect(find.byType(Text), findsOneWidget);
      expect(
        tester.getCenter(find.text('播放列表还是空的')).dy,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio / 2 +
              60,
        ),
      );
    },
  );
}
