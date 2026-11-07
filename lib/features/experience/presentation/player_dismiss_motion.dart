import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Implemented by the player route, so the handle can drive its actual route
/// controller instead of moving a second surface and replaying pop afterwards.
abstract interface class PlayerDismissRoute {
  PlayerDismissMotion get playerDismissMotion;
}

class PlayerDismissMotion extends ChangeNotifier {
  PlayerDismissMotion(this.controller);
  final AnimationController controller;
  bool dragDriven = false;
  bool committed = false;
  int _gesture = 0;
  bool _disposed = false;

  double get progress => (1 - controller.value).clamp(0.0, 1.0);

  void update(double delta, double height) {
    if (committed || height <= 0 || _disposed) return;
    if (!dragDriven && controller.status != AnimationStatus.completed) return;
    _gesture++;
    if (!dragDriven) {
      dragDriven = true;
      notifyListeners();
    }
    controller.stop();
    controller.value = (controller.value - delta / height).clamp(0.0, 1.0);
  }

  Future<void> finish({
    required double speed,
    required double height,
    required VoidCallback onDismiss,
    bool cancelled = false,
    bool reduceMotion = false,
  }) async {
    if (!dragDriven || committed || _disposed) return;
    final close =
        !cancelled &&
        (progress > .18 || (progress * height > 16 && speed > 650));
    if (close) {
      committed = true;
      // Navigator reverses from the current value, completing only the part
      // still on screen. No separate full-height gesture animation precedes it.
      controller.reverseDuration = reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240);
      onDismiss();
      return;
    }
    final gesture = ++_gesture;
    try {
      await controller
          .animateTo(
            1,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      if (!_disposed && gesture == _gesture && !committed) {
        dragDriven = false;
        notifyListeners();
      }
    } on TickerCanceled {
      // A new drag, system Back or route disposal owns the next frame.
    }
  }

  void markPopped() {
    committed = true;
    _gesture++;
  }

  @override
  void dispose() {
    _disposed = true;
    _gesture++;
    super.dispose();
  }
}
