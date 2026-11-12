import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/experience/presentation/player_swipe_to_comments.dart';
import 'package:mesting_music/features/music_platform/presentation/song_comments_route.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';

const coverKey = ValueKey('route-cover');
const commentsKey = ValueKey('route-comments');

void main() {
  for (final fromPlayer in [true, false]) {
    testWidgets('comments direction: fromPlayer=$fromPlayer', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {TargetPlatform.android: BetaPageTransitionsBuilder()},
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: PlayerSwipeToComments(
                enabled: true,
                onOpenComments: () async {
                  await Navigator.of(context).push(
                    songCommentsRoute<void>(
                      context,
                      fromPlayer: fromPlayer,
                      builder: (_) =>
                          const Scaffold(key: commentsKey, body: Text('歌曲评论')),
                    ),
                  );
                },
                child: const SizedBox.expand(key: coverKey),
              ),
            ),
          ),
        ),
      );
      final cover = tester.getRect(find.byKey(coverKey));
      await tester.dragFrom(const Offset(200, 400), const Offset(0, -160));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final entering = tester.getRect(find.byKey(commentsKey));
      if (fromPlayer) {
        expect(entering.left, closeTo(0, .01));
        expect(entering.top, greaterThan(0));
        expect(entering.top, lessThan(cover.height));
        expect(tester.getRect(find.byKey(coverKey)), cover);
      } else {
        expect(entering.left, greaterThan(0));
        expect(entering.top, closeTo(0, .01));
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(commentsKey)).topLeft, Offset.zero);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final leaving = tester.getRect(find.byKey(commentsKey));
      if (fromPlayer) {
        expect(leaving.left, closeTo(0, .01));
        expect(leaving.top, greaterThan(0));
        expect(tester.getRect(find.byKey(coverKey)), cover);
      } else {
        expect(leaving.left, greaterThan(0));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(commentsKey), findsNothing);
      expect(find.byKey(coverKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion presents comments immediately and keeps back', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    Route<void>? route;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                route = songCommentsRoute<void>(
                  context,
                  fromPlayer: true,
                  builder: (_) => const Scaffold(key: commentsKey),
                );
                Navigator.of(context).push(route!);
              },
              child: const Text('评论'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    expect((route! as PageRoute).transitionDuration, Duration.zero);
    expect((route! as PageRoute).allowSnapshotting, false);
    expect(tester.getRect(find.byKey(commentsKey)).topLeft, Offset.zero);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(commentsKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
