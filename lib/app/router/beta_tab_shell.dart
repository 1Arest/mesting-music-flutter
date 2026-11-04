import 'package:go_router/go_router.dart';
import '../../shared/widgets/beta_root_tab_viewport.dart';
import '../../shared/widgets/beta_page_route_observer.dart';

/// Retained root branches live under the existing music Navigator. Query views
/// (daily, favorites, etc.) are secondary pages, not another instance of the
/// stateful shell: pushing a second shell would reuse its global Navigator key.
/// Keep old links valid through an internal view alias and preserve parameters.
List<RouteBase> betaTabShellRoutes(List<GoRoute> roots) => [
  StatefulShellRoute(
    pageBuilder: (context, state, shell) =>
        NoTransitionPage<void>(key: state.pageKey, child: shell),
    navigatorContainerBuilder: (context, shell, children) =>
        BetaRootTabViewport(
          index: shell.currentIndex,
          locations: roots.map((r) => r.path).toList(),
          children: children,
        ),
    branches: [
      for (final route in roots)
        StatefulShellBranch(
          observers: [BetaPageRouteObserver()],
          initialLocation: route.path,
          preload: true,
          routes: [
            GoRoute(
              path: route.path,
              builder: route.builder,
              pageBuilder: route.pageBuilder,
              redirect: (context, state) => state.uri.hasQuery
                  ? state.uri.replace(path: '${route.path}/view').toString()
                  : null,
            ),
          ],
        ),
    ],
  ),
  for (final route in roots)
    GoRoute(
      path: '${route.path}/view',
      builder: route.builder,
      pageBuilder: route.pageBuilder,
    ),
];
