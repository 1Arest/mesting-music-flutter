import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/beta_root_tab_viewport.dart';
import '../../shared/widgets/beta_page_route_observer.dart';
import '../../shared/widgets/beta_tab_navigation.dart';
import '../../shared/widgets/beta_page_motion.dart';

/// Retained root branches live under the existing music Navigator. Query views
/// (daily, favorites, etc.) are secondary pages, not another instance of the
/// stateful shell: pushing a second shell would reuse its global Navigator key.
/// Keep old links valid through an internal view alias and preserve parameters.
List<RouteBase> betaTabShellRoutes(List<GoRoute> roots) {
  final observers = [for (final _ in roots) BetaPageRouteObserver()];
  return [
    StatefulShellRoute(
      pageBuilder: (context, state, shell) =>
          BetaRootTransitionPage<void>(key: state.pageKey, child: shell),
      navigatorContainerBuilder: (context, shell, children) =>
          _BetaTabStackBinding(
            index: shell.currentIndex,
            observers: observers,
            child: BetaRootTabViewport(
              index: shell.currentIndex,
              locations: roots.map((r) => r.path).toList(),
              children: children,
            ),
          ),
      branches: [
        for (var i = 0; i < roots.length; i++)
          StatefulShellBranch(
            observers: [observers[i]],
            initialLocation: roots[i].path,
            preload: true,
            routes: [
              GoRoute(
                path: roots[i].path,
                builder: roots[i].builder,
                pageBuilder: roots[i].pageBuilder,
                redirect: (context, state) => state.uri.hasQuery
                    ? state.uri
                          .replace(path: '${roots[i].path}/view')
                          .toString()
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
}

/// Connects the retained branch stacks to the same coordinator as both music
/// navigation bars. A programmatic root shortcut also resets its destination;
/// regular pushes and Back within the selected tab retain their normal motion.
class _BetaTabStackBinding extends StatefulWidget {
  const _BetaTabStackBinding({
    required this.index,
    required this.observers,
    required this.child,
  });
  final int index;
  final List<BetaPageRouteObserver> observers;
  final Widget child;
  @override
  State<_BetaTabStackBinding> createState() => _BetaTabStackBindingState();
}

class _BetaTabStackBindingState extends State<_BetaTabStackBinding> {
  // The route factory is also usable by small, provider-free navigation hosts.
  // Production binds to the existing app coordinator; those hosts need only
  // the local programmatic-switch reset, not a second ProviderScope.
  late final _navigation =
      context
          .findAncestorWidgetOfExactType<UncontrolledProviderScope>()
          ?.container
          .read(betaTabNavigationProvider) ??
      BetaTabNavigation();
  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.observers.length; i++) {
      final observer = widget.observers[i];
      _navigation.bindBranch(
        i,
        owner: this,
        hasSecondaryPages: () => observer.hasSecondaryPages,
        returnToRoot: observer.returnToRoot,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _BetaTabStackBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) _navigation.returnToRoot(widget.index);
  }

  @override
  void dispose() {
    for (var i = 0; i < widget.observers.length; i++) {
      _navigation.unbindBranch(i, this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
