import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Engine-owned Android pulses supplement Dart timers while an active room is
/// backgrounded. The bridge carries an opaque lease only, never account data.
/// Neither callback nor teardown waits for a rendered frame or a visible page.
class TogetherBackgroundBinding {
  TogetherBackgroundBinding({
    required this.changes,
    required this.active,
    required this.poll,
    bool? supported,
  }) : supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (!this.supported) return;
    _owner = this;
    _channel.setMethodCallHandler(_receive);
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _synchronize());
    changes.addListener(_synchronize);
    _synchronize();
  }
  final Listenable changes;
  final bool Function() active;
  final Future<void> Function() poll;
  final bool supported;
  static const _channel = MethodChannel(
    'com.mesting.music/together_background',
  );
  static TogetherBackgroundBinding? _owner;
  static int _revision = 0;
  AppLifecycleListener? _lifecycle;
  String? _lease;
  bool? _lastActive, _lastBackground;
  bool _disposed = false;

  void _synchronize() {
    if (_disposed || !identical(_owner, this)) return;
    final enabled = active();
    final background =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    if (_lastActive == enabled && _lastBackground == background) return;
    _lastActive = enabled;
    _lastBackground = background;
    _lease = '${++_revision}';
    unawaited(_configure(enabled, background));
  }

  Future<void> _configure(bool enabled, bool background) async {
    try {
      await _channel.invokeMethod<void>('configure', {
        'lease': _lease,
        'revision': _revision,
        'active': enabled,
        'background': background,
      });
    } on MissingPluginException {
      // Other hosts retain the controller's normal Dart polling.
    } on PlatformException {
      // The existing polling and foreground refresh remain available.
    }
  }

  Future<void> _receive(MethodCall call) async {
    if (!_disposed &&
        identical(_owner, this) &&
        call.method == 'poll' &&
        call.arguments == _lease &&
        _lastBackground == true &&
        active()) {
      await poll();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifecycle?.dispose();
    changes.removeListener(_synchronize);
    if (identical(_owner, this)) {
      _lease = '${++_revision}';
      unawaited(_configure(false, false));
      _channel.setMethodCallHandler(null);
      _owner = null;
    }
  }
}
