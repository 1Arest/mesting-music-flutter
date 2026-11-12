import 'dart:async';
import 'package:flutter/foundation.dart';

enum MusicSleepMode { off, countdown, endOfTrack }

/// An in-process timer owned by the music service, not a page. Its only action
/// is pausing the existing owner; it never exits Android or clears an account.
/// A deadline is checked against wall time after delayed/background ticks.
class MusicSleepTimer extends ChangeNotifier {
  MusicSleepTimer({required this.onExpire, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final Future<void> Function() onExpire;
  final DateTime Function() _now;
  MusicSleepMode _mode = MusicSleepMode.off;
  DateTime? _deadline;
  Timer? _timer;
  bool _disposed = false;
  bool _expiring = false;
  bool get expiring => _expiring;
  MusicSleepMode get mode => _mode;
  DateTime? get deadline => _deadline;
  bool get active => _mode != MusicSleepMode.off;
  Duration get remaining {
    final value = _deadline?.difference(_now()) ?? Duration.zero;
    return value.isNegative ? Duration.zero : value;
  }

  void start(Duration duration) {
    if (duration < const Duration(minutes: 1) ||
        duration > const Duration(hours: 24)) {
      throw ArgumentError('Timer must be between 1 minute and 24 hours');
    }
    _timer?.cancel();
    _mode = MusicSleepMode.countdown;
    _deadline = _now().add(duration);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!checkDeadline() && !_disposed) notifyListeners();
    });
    notifyListeners();
  }

  void afterCurrentTrack() {
    _timer?.cancel();
    _deadline = null;
    _mode = MusicSleepMode.endOfTrack;
    notifyListeners();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _mode = MusicSleepMode.off;
    _deadline = null;
    if (!_disposed) notifyListeners();
  }

  bool checkDeadline() {
    if (_mode != MusicSleepMode.countdown ||
        _deadline == null ||
        _now().isBefore(_deadline!)) {
      return false;
    }
    _expire();
    return true;
  }

  /// Called before automatic Next. The caller suppresses that advance so a
  /// queue/radio continuation cannot race the pause at the natural boundary.
  bool consumeTrackCompletion() {
    if (_mode == MusicSleepMode.endOfTrack) {
      _expire();
      return true;
    }
    return checkDeadline();
  }

  void _expire() {
    _expiring = true;
    cancel();
    unawaited(onExpire());
    _expiring = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
