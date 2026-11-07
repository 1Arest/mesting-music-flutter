import 'dart:async';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Keeps the original six-second wave/blink loop, but schedules frames only
/// during visible motion. Static pauses use one timer rather than a live ticker.
/// The painter listens directly, so an active wave never rebuilds login/glass.
class CompanionMotion extends ChangeNotifier {
  CompanionMotion(TickerProvider vsync)
    : _wave = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 1600),
      ),
      _hello = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 1800),
      ) {
    _wave.addListener(_tick);
    _hello.addListener(notifyListeners);
    _hello.addStatusListener((_) => notifyListeners());
  }
  final AnimationController _wave, _hello;
  Timer? _timer;
  bool _active = false;
  double _seconds = 0;
  double get seconds => _seconds;
  bool get greeting => _hello.isAnimating;
  double get hello => _hello.value;

  void _tick() {
    _seconds = .300001 + _wave.value * 1.6;
    notifyListeners();
  }

  void _after(Duration delay, void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (_active) action();
    });
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _timer?.cancel();
    _wave.stop();
    _hello.stop();
    _seconds = 0;
    if (active) _cycle();
    notifyListeners();
  }

  void _cycle() {
    _seconds = 0;
    _after(const Duration(milliseconds: 300), () {
      _wave.forward(from: 0).whenCompleteOrCancel(() {
        if (!_active || _wave.value < 1) return;
        _seconds = 1.9;
        notifyListeners();
        _after(const Duration(milliseconds: 1900), () {
          _seconds = 3.85;
          notifyListeners();
          _after(const Duration(milliseconds: 140), () {
            _seconds = 3.94;
            notifyListeners();
            _after(const Duration(milliseconds: 2060), _cycle);
          });
        });
      });
    });
  }

  void greet() {
    if (_active) _hello.forward(from: 0);
  }

  @override
  void dispose() {
    _active = false;
    _timer?.cancel();
    _wave.dispose();
    _hello.dispose();
    super.dispose();
  }
}
