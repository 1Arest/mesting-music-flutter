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
    this.configurationTimeout = const Duration(seconds: 3),
    this.retryDelay = const Duration(milliseconds: 500),
    this.configurationProbeDelay = const Duration(seconds: 15),
    this.leaseRefreshInterval = const Duration(seconds: 45),
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
  final Duration configurationTimeout, retryDelay;
  final Duration configurationProbeDelay, leaseRefreshInterval;
  static const _channel = MethodChannel(
    'com.mesting.music/together_background',
  );
  static TogetherBackgroundBinding? _owner;
  static int _revision = 0;
  AppLifecycleListener? _lifecycle;
  String? _lease;
  bool? _lastActive, _lastBackground;
  int _configuration = 0, _confirmedConfiguration = -1, _lastRequest = -1;
  int _configurationAttempts = 0, _configurationFailures = 0;
  int _configurationAccepted = 0, _pulses = 0, _pollFailures = 0;
  Timer? _retry;
  final _configurationCancellations = <VoidCallback>{};
  final Stopwatch _clock = Stopwatch()..start();
  Duration _confirmedAt = Duration.zero, _probeAt = Duration.zero;
  int _configurationRetry = 0;
  bool _disposed = false;

  void _synchronize() {
    if (_disposed || !identical(_owner, this)) return;
    final enabled = active();
    final background =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    if (_lastActive == enabled && _lastBackground == background) {
      // A successful fallback tick is also a chance to renew/recover an expired
      // native lease. An unresponsive engine cannot renew it by itself.
      final renew =
          enabled &&
          background &&
          _confirmedConfiguration == _configuration &&
          _clock.elapsed - _confirmedAt >= leaseRefreshInterval;
      final probe =
          enabled &&
          background &&
          _confirmedConfiguration != _configuration &&
          _configurationRetry >= 3 &&
          _clock.elapsed >= _probeAt;
      if (!renew && !probe) return;
    }
    _lastActive = enabled;
    _lastBackground = background;
    _configuration = ++_revision;
    _lease = '$_configuration';
    _lastRequest = -1;
    _configurationRetry = 0;
    _retry?.cancel();
    _cancelConfigurationWaits();
    unawaited(_configure(_configuration, enabled, background));
  }

  /// Future.timeout cannot be cancelled when a room/account owner disappears.
  /// Own this small deadline explicitly so teardown also retires its timer;
  /// late platform responses are observed but never confirm a replaced lease.
  Future<Object?> _configurationReply(Map<String, Object?> arguments) {
    final reply = Completer<Object?>();
    final deadline = Timer(configurationTimeout, () {
      if (!reply.isCompleted) {
        reply.completeError(TimeoutException('Together configuration'));
      }
    });
    void cancel() {
      deadline.cancel();
      if (!reply.isCompleted) reply.complete(null);
    }

    _configurationCancellations.add(cancel);
    _channel
        .invokeMethod<Object?>('configure', arguments)
        .then(
          (value) {
            if (!reply.isCompleted) reply.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!reply.isCompleted) reply.completeError(error, stack);
          },
        );
    return reply.future.whenComplete(() {
      deadline.cancel();
      _configurationCancellations.remove(cancel);
    });
  }

  void _cancelConfigurationWaits() {
    for (final cancel in _configurationCancellations.toList()) {
      cancel();
    }
    _configurationCancellations.clear();
  }

  Future<void> _configure(int revision, bool enabled, bool background) async {
    _configurationAttempts++;
    if (!enabled || !background) {
      // There is no background job to establish while browsing or playing
      // alone. A stop still reaches native with an ordered revision, but never
      // creates acknowledgement/retry timers for ordinary foreground pages.
      try {
        await _channel.invokeMethod<void>('configure', {
          'lease': '$revision',
          'revision': revision,
          'active': false,
          'background': false,
        });
      } catch (_) {
        // A disconnected engine also has a bounded native room/wake lease.
      }
      return;
    }
    try {
      final response = await _configurationReply({
        'lease': '$revision',
        'revision': revision,
        'active': enabled,
        'background': background,
      });
      if (_disposed || !identical(_owner, this) || revision != _configuration) {
        return;
      }
      if (response is! Map ||
          response['accepted'] != true ||
          response['revision'] != revision) {
        throw PlatformException(code: 'configuration_unconfirmed');
      }
      if (_configuration == revision) {
        _confirmedConfiguration = revision;
        _confirmedAt = _clock.elapsed;
        _configurationAccepted++;
        _retry?.cancel();
      }
    } on MissingPluginException {
      _configurationFailed(revision, enabled, background);
    } on PlatformException {
      _configurationFailed(revision, enabled, background);
    } on TimeoutException {
      _configurationFailed(revision, enabled, background);
    }
  }

  void _configurationFailed(int revision, bool enabled, bool background) {
    _configurationFailures++;
    // A failed call never becomes an acknowledged configuration. Retry the
    // same opaque revision at a bounded cadence while this owner still needs
    // it; stale results cannot configure the next account/room owner.
    if (_disposed ||
        !identical(_owner, this) ||
        revision != _configuration ||
        revision == _confirmedConfiguration) {
      return;
    }
    _retry?.cancel();
    if (_configurationRetry >= 3) {
      _probeAt = _clock.elapsed + configurationProbeDelay;
      return;
    }
    final delay = retryDelay * (1 << _configurationRetry++);
    _retry = Timer(delay, () {
      unawaited(_configure(revision, enabled, background));
    });
  }

  Future<bool> _receive(MethodCall call) async {
    final argument = call.arguments;
    final lease = argument is Map ? argument['lease'] : argument;
    final request = argument is Map ? argument['request'] : null;
    if (!_disposed &&
        identical(_owner, this) &&
        call.method == 'poll' &&
        lease == _lease &&
        _lastBackground == true &&
        active()) {
      if (argument is Map && (request is! int || request <= _lastRequest)) {
        return false;
      }
      if (request is int) _lastRequest = request;
      _pulses++;
      if (argument is Map) {
        // Acknowledge delivery immediately. Native scheduling must not wait for
        // HTTP, an audio decoder, a page frame, or a complete volume fade.
        unawaited(
          poll().catchError((Object _) {
            _pollFailures++;
          }),
        );
      } else {
        // Legacy local probes used the lease alone. Keep their completion
        // contract without making production pulses depend on audio work.
        try {
          await poll();
        } catch (_) {
          _pollFailures++;
        }
      }
      return true;
    }
    return false;
  }

  /// Only monotonic counters leave this bridge: never tokens, IDs or songs.
  static Future<Map<String, int>> diagnostics() async {
    final current = _owner;
    final counts = <String, int>{
      'configurationAttempts': current?._configurationAttempts ?? 0,
      'configurationAccepted': current?._configurationAccepted ?? 0,
      'configurationFailures': current?._configurationFailures ?? 0,
      'dartPulses': current?._pulses ?? 0,
      'pollFailures': current?._pollFailures ?? 0,
    };
    try {
      final native = await _channel
          .invokeMethod<Object?>('diagnostics')
          .timeout(const Duration(seconds: 2));
      if (native is Map) {
        for (final name in const [
          'nativePulses',
          'nativeAcknowledged',
          'nativeTimeouts',
          'nativeRejected',
        ]) {
          if (native[name] is int) counts[name] = native[name] as int;
        }
      }
    } catch (_) {
      /* Optional diagnostics never affect playback. */
    }
    return counts;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retry?.cancel();
    _cancelConfigurationWaits();
    _lifecycle?.dispose();
    changes.removeListener(_synchronize);
    if (identical(_owner, this)) {
      _configuration = ++_revision;
      _lease = '$_configuration';
      // Disable is fire-and-forget at teardown. A lost reply must not create a
      // new deadline/retry owner after the controller has already been freed.
      unawaited(
        _channel
            .invokeMethod<void>('configure', {
              'lease': _lease,
              'revision': _configuration,
              'active': false,
              'background': false,
            })
            .catchError((Object _) {}),
      );
      _channel.setMethodCallHandler(null);
      _owner = null;
    }
  }
}
