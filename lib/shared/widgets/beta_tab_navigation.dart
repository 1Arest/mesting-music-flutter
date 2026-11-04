import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root selection never waits for an animation. Remember the latest request so
/// several taps within one frame can still return to the starting tab before
/// the router has rebuilt its location. Motion belongs to BetaRootTabViewport.
class BetaTabNavigation {
  int? _requested;
  final _branches = <int, _BetaTabBranch>{};

  /// The route factory binds its real branch Navigators here. Navigation bars
  /// need no global keys, and a replaced shell cannot unregister a newer one.
  void bindBranch(
    int index, {
    required Object owner,
    required bool Function() hasSecondaryPages,
    required void Function() returnToRoot,
  }) =>
      _branches[index] = _BetaTabBranch(owner, hasSecondaryPages, returnToRoot);

  void unbindBranch(int index, Object owner) {
    if (identical(_branches[index]?.owner, owner)) _branches.remove(index);
  }

  bool hasSecondaryPages(int index) =>
      _branches[index]?.hasSecondaryPages() ?? false;

  bool returnToRoot(int index) {
    if (!hasSecondaryPages(index)) return false;
    _branches[index]!.returnToRoot();
    return true;
  }

  void request({
    required int index,
    required int currentIndex,
    required void Function(int) navigate,
  }) {
    final reset = returnToRoot(index);
    if (index == (_requested ?? currentIndex) && !reset) return;
    _requested = index;
    navigate(index);
  }

  /// Only the latest request may acknowledge itself. Router rebuilds for an
  /// earlier tap can arrive after a newer tap; clearing that newer intent would
  /// make a subsequent tap on the old visible tab look like a duplicate.
  void settled(int index) {
    if (_requested == index) _requested = null;
  }

  void cancel() {
    _requested = null;
  }

  void dispose() {
    cancel();
    _branches.clear();
  }
}

class _BetaTabBranch {
  const _BetaTabBranch(this.owner, this.hasSecondaryPages, this.returnToRoot);
  final Object owner;
  final bool Function() hasSecondaryPages;
  final void Function() returnToRoot;
}

final betaTabNavigationProvider = Provider((ref) {
  final navigation = BetaTabNavigation();
  ref.onDispose(navigation.dispose);
  return navigation;
});
