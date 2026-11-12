import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';

/// Exercise retained shell + redirected query view + third-level page, rather
/// than merely checking the primary tween of an isolated Navigator route.
void main() {
  for (final systemBack in [false, true]) {
    testWidgets(
      'retained parent and two levels reverse their actual travel; system=$systemBack',
      (tester) async {
        Widget page(String id) => Scaffold(
          body: Center(child: Text(id, key: ValueKey(id))),
        );
        final router = GoRouter(
          initialLocation: '/music',
          routes: [
            ShellRoute(
              builder: (_, _, child) => child,
              routes: [
                ...betaTabShellRoutes([
                  GoRoute(
                    path: '/music',
                    pageBuilder: (_, state) => state.uri.path.endsWith('/view')
                        ? BetaContentTransitionPage<void>(
                            key: state.pageKey,
                            child: page('second'),
                          )
                        : NoTransitionPage<void>(
                            key: state.pageKey,
                            child: page('root'),
                          ),
                  ),
                ]),
                GoRoute(
                  path: '/third',
                  pageBuilder: (_, state) => BetaContentTransitionPage<void>(
                    key: state.pageKey,
                    child: page('third'),
                  ),
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        unawaited(router.push('/music?view=favorites'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          tester.getCenter(find.byKey(const ValueKey('second'))).dx,
          greaterThan(400),
        );
        // The existing root moves left, and the SAME root returns from the left.
        expect(
          tester.getCenter(find.byKey(const ValueKey('root'))).dx,
          lessThan(400),
        );
        await tester.pumpAndSettle();
        unawaited(router.push('/third'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          tester.getCenter(find.byKey(const ValueKey('third'))).dx,
          greaterThan(400),
        );
        expect(
          tester.getCenter(find.byKey(const ValueKey('second'))).dx,
          lessThan(400),
        );
        await tester.pumpAndSettle();
        for (final pair in [('third', 'second'), ('second', 'root')]) {
          if (systemBack) {
            await tester.binding.handlePopRoute();
          } else {
            router.pop();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 90));
          final outgoing = tester.getCenter(find.byKey(ValueKey(pair.$1))).dx;
          final returning = tester.getCenter(find.byKey(ValueKey(pair.$2))).dx;
          expect(outgoing, greaterThan(400));
          expect(returning, lessThan(400));
          await tester.pump(const Duration(milliseconds: 80));
          expect(
            tester.getCenter(find.byKey(ValueKey(pair.$1))).dx,
            greaterThan(outgoing),
          );
          expect(
            tester.getCenter(find.byKey(ValueKey(pair.$2))).dx,
            greaterThan(returning),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getCenter(find.byKey(ValueKey(pair.$2))).dx,
            closeTo(400, 1),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      },
    );
  }
  testWidgets(
    'reduced motion leaves both page layers at their natural coordinates',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BetaPageMotion(
              animation: const AlwaysStoppedAnimation(.3),
              secondaryAnimation: const AlwaysStoppedAnimation(.4),
              child: const Center(child: Text('still')),
            ),
          ),
        ),
      );
      expect(tester.getCenter(find.text('still')).dx, 400);
    },
  );
}
