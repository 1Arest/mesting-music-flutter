import 'dart:async';
import 'package:flutter/foundation.dart';

/// Serializes scroll-driven capsule geometry changes without changing their
/// 300ms animation. Very fast opposite scrolls retain the latest target, rather
/// than restarting several expensive width/height morphs within one transition.
/// Explicit navigation/search changes bypass the queue through [show].
class BetaScrollChrome extends ValueNotifier<bool> {
  BetaScrollChrome({this.motionDuration = const Duration(milliseconds: 300)})
    : super(false);
  final Duration motionDuration;
  Timer? _motion;
  bool? _pending;
  bool get requestedCompact => _pending ?? value;

  void request(bool compact) {
    if (_motion?.isActive == true) {
      _pending = compact;
      return;
    }
    if (value == compact) return;
    value = compact;
    _motion = Timer(motionDuration, () {
      _motion = null;
      final next = _pending;
      _pending = null;
      if (next != null) request(next);
    });
  }

  void show(bool compact) {
    _motion?.cancel();
    _motion = null;
    _pending = null;
    value = compact;
  }

  @override
  void dispose() {
    _motion?.cancel();
    super.dispose();
  }
}
