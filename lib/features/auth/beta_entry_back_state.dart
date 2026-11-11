import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/beta_back_state_changes.dart';

/// Reports the visible entry stack to Android independently of the app Router.
/// A null result delegates to the Router; false keeps the welcome root's normal
/// exit behavior even if a covered app page still has navigation history.
class BetaEntryBackState extends NavigatorObserver {
  bool _active = false;
  bool _guide = false;

  bool? get canHandlePop =>
      !_active ? null : _guide || (navigator?.canPop() ?? false);

  void update({required bool active, required bool guide}) {
    if (_active == active && _guide == guide) return;
    _active = active;
    _guide = guide;
    BetaBackStateChanges.shared.refresh();
  }

  // Re-read the live Navigator after each frame rather than caching flags from
  // route notifications, which may arrive after a covered route is removed.
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      BetaBackStateChanges.shared.refresh();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      BetaBackStateChanges.shared.refresh();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      BetaBackStateChanges.shared.refresh();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      BetaBackStateChanges.shared.refresh();
}

final betaEntryBackStateProvider = Provider<BetaEntryBackState>(
  (ref) => BetaEntryBackState(),
);
