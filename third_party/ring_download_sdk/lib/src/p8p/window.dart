/// Additive capabilities for the legacy v1 file channel. Negotiation never
/// changes frame encoding or increases its four-piece memory upper bound.
abstract final class P8PWindowProtocol {
  static const maxWindow = 4;

  static bool advertised(Object? value) =>
      value is Map &&
      value['version'] is int &&
      value['version'] == 1 &&
      value['max_window'] is int &&
      value['max_window'] == maxWindow &&
      value['features'] is List &&
      (value['features'] as List).contains('adaptive_window_v1');

  static int? requested(Object? value, {required bool enabled}) {
    if (!enabled ||
        value is! Map ||
        value['version'] != 1 ||
        value['version'] is! int) {
      return null;
    }
    final window = value['window'];
    if (window is! int || window < 1 || window > maxWindow) {
      throw const FormatException('invalid_p8p_window');
    }
    return window;
  }

  static bool acknowledged(Object? value) =>
      value is Map &&
      value['max_window'] == maxWindow &&
      value['max_window'] is int &&
      requested(value, enabled: true) != null;

  static Map<String, int> request(int window) {
    if (window < 1 || window > maxWindow) {
      throw ArgumentError.value(window, 'window');
    }
    return {'version': 1, 'window': window};
  }

  static Map<String, int> echo(int window) => {
    ...request(window),
    'max_window': maxWindow,
  };
}

/// Consumer-driven queue sizing, not a replacement for SCTP congestion
/// control. Ready-but-unconsumed pieces still consume the negotiated budget.
/// A slow consumer reduces prefetch; sustained empty queues may grow it.
class P8PWindowController {
  P8PWindowController({int initial = 4}) : _window = initial {
    if (initial < 1 || initial > P8PWindowProtocol.maxWindow) {
      throw ArgumentError.value(initial, 'initial');
    }
  }

  int _window;
  int _networkPressure = 0, _consumerPressure = 0, _cooldown = 0;
  int get window => _window;

  void observe({
    required int waitMicros,
    required int consumeMicros,
    required int readyPieces,
  }) {
    if (waitMicros < 0 ||
        consumeMicros < 0 ||
        readyPieces < 0 ||
        readyPieces > P8PWindowProtocol.maxWindow) {
      throw ArgumentError('invalid_window_sample');
    }
    if (_cooldown > 0) {
      _cooldown--;
      return;
    }
    // Ignore sub-10ms consumer differences: timer noise and callback overhead
    // must not continually shrink a healthy link's request pipeline.
    final consumerBound =
        readyPieces > 0 &&
        consumeMicros >= 10000 &&
        consumeMicros > waitMicros * 2;
    final networkBound =
        readyPieces == 0 && waitMicros > 1000 && waitMicros > consumeMicros * 2;
    _consumerPressure = consumerBound ? _consumerPressure + 1 : 0;
    _networkPressure = networkBound ? _networkPressure + 1 : 0;
    // Keep a prefetched piece while the consumer persists the current piece.
    // A one-piece automatic floor serialized network and disk in the model.
    if (_consumerPressure >= 2 && _window > 2) {
      _window--;
      _changed();
    } else if (_networkPressure >= 2 && _window < P8PWindowProtocol.maxWindow) {
      _window++;
      _changed();
    }
  }

  void _changed() {
    _networkPressure = _consumerPressure = 0;
    _cooldown = 2;
  }
}
