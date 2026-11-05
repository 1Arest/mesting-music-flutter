import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/features/auth/presentation/beta_welcome_page.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'support/release_144_qa.dart';

/// Platform screens, account/settings entries, declarative music pages and the
/// two legacy Cupertino entries really use different Route classes. Test all
/// adjacent pairs, including their parent coordinates, rather than one tween.
void main() {
  setUpAll(initialize144QA);
  final families = <String, Route<void> Function(Widget)>{
    'platform': (page) => MestingPageRoute<void>(builder: (_) => page),
    'entry': betaEntryRoute<void>,
    'content': betaContentRoute<void>,
    'cupertino-entry': mestingCupertinoRoute<void>,
  };
  for (final first in families.entries) {
    for (final second in families.entries) {
      testWidgets(
        'ordinary stack ${first.key} -> ${second.key} reverses both layers',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.reset);
          Widget page(String name) => Scaffold(
            body: Center(child: Text(name, key: ValueKey(name))),
          );
          final router = GoRouter(
            initialLocation: '/root',
            routes: betaTabShellRoutes([
              GoRoute(
                path: '/root',
                pageBuilder: (_, state) => BetaRootTransitionPage<void>(
                  key: state.pageKey,
                  child: page('root'),
                ),
              ),
            ]),
          );
          await tester.pumpWidget(
            MaterialApp.router(theme: theme144(true), routerConfig: router),
          );
          await tester.pumpAndSettle();
          final navigator = Navigator.of(tester.element(find.text('root')));
          Future<void> enter(
            String name,
            String parent,
            Route<void> route,
          ) async {
            unawaited(navigator.push(route));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.getCenter(find.text(name)).dx, greaterThan(195));
            expect(tester.getCenter(find.text(parent)).dx, lessThan(195));
            await tester.pumpAndSettle();
          }

          await enter('second', 'root', first.value(page('second')));
          await enter('third', 'second', second.value(page('third')));
          for (final pair in [('third', 'second'), ('second', 'root')]) {
            navigator.pop();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 80));
            final outgoing = tester.getCenter(find.text(pair.$1)).dx;
            final returning = tester.getCenter(find.text(pair.$2)).dx;
            expect(outgoing, greaterThan(195));
            expect(returning, lessThan(195));
            await tester.pump(const Duration(milliseconds: 90));
            expect(
              tester.getCenter(find.text(pair.$1)).dx,
              greaterThan(outgoing),
            );
            expect(
              tester.getCenter(find.text(pair.$2)).dx,
              greaterThan(returning),
            );
            await tester.pumpAndSettle();
            expect(tester.getCenter(find.text(pair.$2)).dx, closeTo(195, .5));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          router.dispose();
        },
      );
    }
  }
}
