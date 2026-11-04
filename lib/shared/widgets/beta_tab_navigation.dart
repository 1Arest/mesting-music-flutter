import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root selection never waits for an animation. Remember the latest request so
/// several taps within one frame can still return to the starting tab before
/// the router has rebuilt its location. Motion belongs to BetaRootTabViewport.
class BetaTabNavigation {
  int? _requested;
  void request({
    required int index,
    required int currentIndex,
    required void Function(int) navigate,
  }) {
    if (index == (_requested ?? currentIndex)) return;
    _requested = index;
    navigate(index);
  }

  /// The router has published an actual location; the same-frame hint ends.
  void settled(int index) {
    _requested = null;
  }

  void cancel() {
    _requested = null;
  }

  void dispose() => cancel();
}

final betaTabNavigationProvider = Provider((ref) {
  final navigation = BetaTabNavigation();
  ref.onDispose(navigation.dispose);
  return navigation;
});
