import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/app/router/beta_tab_shell.dart';
import 'package:mesting_music/shared/widgets/beta_tab_navigation.dart';

const _paths = ['/discover', '/functions', '/library', '/profile'];

class _Root extends StatefulWidget {
  const _Root(this.index);
  final int index;
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Center(
    key: ValueKey('root-${widget.index}'),
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('root${widget.index}:$count'),
    ),
  );
}

void main() {
  testWidgets(
    'all retained tabs discard two pushed pages on return while keeping their root state',
    (tester) async {
      final container = ProviderContainer();
      final navigation = container.read(betaTabNavigationProvider);
      final router = GoRouter(
        initialLocation: _paths.first,
        routes: [
          ShellRoute(
            builder: (context, state, child) => Scaffold(
              body: child,
              bottomNavigationBar: Row(
                children: [
                  for (var i = 0; i < _paths.length; i++)
                    TextButton(
                      onPressed: () => navigation.request(
                        index: i,
                        currentIndex: _paths.indexOf(state.uri.path),
                        navigate: (target) => context.go(_paths[target]),
                      ),
                      child: Text('tab$i'),
                    ),
                ],
              ),
            ),
            routes: [
              ...betaTabShellRoutes([
                for (var i = 0; i < _paths.length; i++)
                  GoRoute(path: _paths[i], builder: (_, _) => _Root(i)),
              ]),
              GoRoute(
                path: '/declared-detail',
                builder: (_, _) => const Text('declared-detail'),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < _paths.length; i++) {
        router.go(_paths[i]);
        await tester.pumpAndSettle();
        await tester.tap(find.text('root$i:0').hitTestable());
        await tester.pump();
        final root = tester.element(
          find.byKey(ValueKey('root-$i')).hitTestable(),
        );
        final navigator = Navigator.of(root);
        final first = navigator.push<void>(
          MaterialPageRoute(builder: (_) => Text('detail$i:first')),
        );
        await tester.pumpAndSettle();
        final second = navigator.push<void>(
          MaterialPageRoute(builder: (_) => Text('detail$i:second')),
        );
        await tester.pumpAndSettle();
        expect(find.text('detail$i:second').hitTestable(), findsOneWidget);
        expect(navigation.hasSecondaryPages(i), true);

        await tester.tap(find.text('tab${(i + 1) % 4}'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('tab$i'));
        await tester.pump();
        expect(find.text('detail$i:second').hitTestable(), findsNothing);
        await tester.pumpAndSettle();
        expect(find.text('root$i:1').hitTestable(), findsOneWidget);
        expect(navigation.hasSecondaryPages(i), false);
        await Future.wait([first, second]);
      }

      // Declarative details still belong to GoRouter; selecting a destination
      // must clear that route without trying to imperatively remove its Page.
      unawaited(router.push('/declared-detail'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab0'));
      await tester.pumpAndSettle();
      expect(find.text('declared-detail').hitTestable(), findsNothing);
      expect(find.text('root0:1').hitTestable(), findsOneWidget);
      final root = tester.element(
        find.byKey(const ValueKey('root-0')).hitTestable(),
      );
      final sameTab = Navigator.of(root).push<void>(
        MaterialPageRoute(builder: (_) => const Text('same-tab-detail')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('tab0'));
      await tester.pumpAndSettle();
      expect(find.text('same-tab-detail').hitTestable(), findsNothing);
      expect(find.text('root0:1').hitTestable(), findsOneWidget);
      await sameTab;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      container.dispose();
    },
  );

  testWidgets(
    'programmatic shortcuts and same-frame retargeting cannot restore an old branch page',
    (tester) async {
      final container = ProviderContainer();
      final navigation = container.read(betaTabNavigationProvider);
      final router = GoRouter(
        initialLocation: _paths.first,
        routes: betaTabShellRoutes([
          for (var i = 0; i < _paths.length; i++)
            GoRoute(path: _paths[i], builder: (_, _) => _Root(i)),
        ]),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final root = tester.element(find.byKey(const ValueKey('root-0')));
      final pushed = Navigator.of(root).push<void>(
        MaterialPageRoute(builder: (_) => const Text('old-pushed-page')),
      );
      await tester.pumpAndSettle();
      router.go(_paths[3]);
      await tester.pumpAndSettle();
      // No navigation-bar callback is involved in a feature shortcut.
      router.go(_paths[0]);
      await tester.pumpAndSettle();
      expect(find.text('old-pushed-page').hitTestable(), findsNothing);
      await pushed;

      void select(int index) => navigation.request(
        index: index,
        currentIndex: 0,
        navigate: (target) => router.go(_paths[target]),
      );
      select(3);
      select(1);
      select(0);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, _paths[0]);
      expect(find.text('root0:0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      container.dispose();
    },
  );
}
