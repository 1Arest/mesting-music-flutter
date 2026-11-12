import 'package:flutter/widgets.dart';

/// The visible page can remain underneath a popup. ModalRoute.isCurrent alone
/// confuses that popup with a replacement full page and releases its chrome.
/// Every production Beta Navigator owns its own observer and route history.
class BetaPageRouteObserver extends NavigatorObserver with ChangeNotifier {
  final _routes = <Route<dynamic>>[];

  /// A tab's declarative root remains mounted so its scroll and loaded data
  /// survive. Only ordinary Navigator.push pages above it are disposable when
  /// a destination is selected; GoRouter still owns all Page-based routes.
  bool get hasSecondaryPages =>
      _routes.skip(1).any((route) => route.settings is! Page && route.isActive);

  void returnToRoot() {
    final owner = navigator;
    if (owner == null) return;
    // Remove, rather than pop, because the tab viewport owns this transition.
    // A reverse detail animation would briefly expose the old page over the
    // target tab, especially when the user switches back within one frame.
    for (final route in _routes.skip(1).toList().reversed) {
      if (route.settings is! Page && route.isActive) owner.removeRoute(route);
    }
  }

  static BetaPageRouteObserver? maybeOf(BuildContext context) =>
      Navigator.maybeOf(
        context,
      )?.widget.observers.whereType<BetaPageRouteObserver>().firstOrNull;

  bool isTopPage(ModalRoute<dynamic>? route) {
    if (route == null) return true;
    if (route is! PageRoute<dynamic>) return route.isCurrent;
    final top = _routes.whereType<PageRoute<dynamic>>().lastOrNull;
    return top == null ? route.isCurrent : identical(top, route);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _routes.add(route);
    notifyListeners();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    notifyListeners();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    notifyListeners();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index < 0) {
      if (newRoute != null) _routes.add(newRoute);
    } else if (newRoute == null) {
      _routes.removeAt(index);
    } else {
      _routes[index] = newRoute;
    }
    notifyListeners();
  }
}
