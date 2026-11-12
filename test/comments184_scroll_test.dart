import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/presentation/expandable_comment_body.dart';

void main() {
  testWidgets(
    'long comment expands without an inner scrollable and drags its parent list',
    (tester) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                ExpandableCommentBody(
                  text: List.filled(80, '一行长评论内容').join('\n'),
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(Scrollable), findsOneWidget);
      expect(find.text('展开'), findsOneWidget);
      expect(tester.widget<Text>(find.byType(Text).first).maxLines, 6);
      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollable), findsOneWidget);
      expect(tester.widget<Text>(find.byType(Text).first).maxLines, isNull);
      await tester.dragFrom(const Offset(200, 250), const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('short comment has no expand action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExpandableCommentBody(
            text: '短评论',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    expect(find.text('展开'), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
  });
}
