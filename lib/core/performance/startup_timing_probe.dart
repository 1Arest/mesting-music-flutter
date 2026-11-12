import 'package:flutter/foundation.dart';

/// Opt-in startup milestones for physical-device diagnostics. Release builds
/// without the define do not start a clock or emit diagnostic messages.
class StartupTimingProbe {
  StartupTimingProbe._();
  static const enabled = bool.fromEnvironment('MESTING_STARTUP_TIMING');
  static final _watch = Stopwatch();
  static void start() {
    if (enabled) _watch.start();
  }

  static void mark(String milestone) {
    if (enabled) {
      debugPrint('MESTING_STARTUP $milestone ${_watch.elapsedMicroseconds}us');
    }
  }
}
