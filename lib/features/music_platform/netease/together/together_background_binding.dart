import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'together_sync_diagnostics.dart';

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
    TogetherSyncDiagnostics? diagnostics,
  }) : supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       journal = diagnostics ?? TogetherSyncDiagnostics.shared {
    if (!this.supported) return;
    _owner = this;
    _channel.setMethodCallHandler(_receive);
    journal.record(TogetherSyncPhase.bindingStarted);
    _recordLifecycle(WidgetsBinding.instance.lifecycleState);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _recordLifecycle(state);
        _synchronize();
      },
    );
    changes.addListener(_synchronize);
    _synchronize();
  }
  final Listenable changes;
  final bool Function() active;
  final Future<void> Function() poll;
  final bool supported;
  final TogetherSyncDiagnostics journal;
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

  void _recordLifecycle(AppLifecycleState? state) => journal.record(
    TogetherSyncPhase.lifecycle,
    lifecycle: TogetherSyncLifecycle.values.byName(
      (state ?? AppLifecycleState.detached).name,
    ),
    active: active(),
    background: state != AppLifecycleState.resumed,
  );

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
    journal.record(
      TogetherSyncPhase.configurationSent,
      configuration: revision,
      attempt: _configurationRetry,
      active: enabled,
      background: background,
    );
    if (!enabled || !background) {
      // There is no background job to establish while browsing or playing
      // alone. A stop still reaches native with an ordered revision, but never
      // creates acknowledgement/retry timers for ordinary foreground pages.
      try {
        final response = await _channel.invokeMethod<Object?>('configure', {
          'lease': '$revision',
          'revision': revision,
          'active': false,
          'background': false,
          'diagnosticLogging': journal.logEvents,
        });
        journal.record(
          TogetherSyncPhase.configurationAccepted,
          configuration: revision,
          active: false,
          accepted: response is Map && response['accepted'] == true,
        );
      } catch (_) {
        // A disconnected engine also has a bounded native room/wake lease.
        journal.record(
          TogetherSyncPhase.configurationFailed,
          configuration: revision,
          reason: TogetherSyncReason.unavailable,
          active: false,
        );
      }
      return;
    }
    try {
      final response = await _configurationReply({
        'lease': '$revision',
        'revision': revision,
        'active': enabled,
        'background': background,
        'diagnosticLogging': journal.logEvents,
      });
      if (_disposed || !identical(_owner, this) || revision != _configuration) {
        journal.record(
          TogetherSyncPhase.configurationRetired,
          configuration: revision,
        );
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
        journal.record(
          TogetherSyncPhase.configurationAccepted,
          configuration: revision,
          accepted: true,
          active: enabled,
          background: background,
        );
        _retry?.cancel();
      }
    } on MissingPluginException {
      _configurationFailed(
        revision,
        enabled,
        background,
        TogetherSyncReason.unavailable,
      );
    } on PlatformException {
      _configurationFailed(
        revision,
        enabled,
        background,
        TogetherSyncReason.unconfirmed,
      );
    } on TimeoutException {
      _configurationFailed(
        revision,
        enabled,
        background,
        TogetherSyncReason.timeout,
      );
    }
  }

  void _configurationFailed(
    int revision,
    bool enabled,
    bool background,
    TogetherSyncReason reason,
  ) {
    _configurationFailures++;
    journal.record(
      TogetherSyncPhase.configurationFailed,
      configuration: revision,
      reason: reason,
      attempt: _configurationRetry,
    );
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
    journal.record(
      TogetherSyncPhase.configurationRetry,
      configuration: revision,
      attempt: _configurationRetry,
      durationMs: delay.inMilliseconds,
    );
    _retry = Timer(delay, () {
      unawaited(_configure(revision, enabled, background));
    });
  }

  Future<bool> _receive(MethodCall call) async {
    final argument = call.arguments;
    final lease = argument is Map ? argument['lease'] : argument;
    final request = argument is Map ? argument['request'] : null;
    final reason = _disposed || !identical(_owner, this)
        ? TogetherSyncReason.staleOwner
        : call.method != 'poll'
        ? TogetherSyncReason.unsupportedMethod
        : lease != _lease
        ? TogetherSyncReason.staleLease
        : _lastBackground != true || !active()
        ? TogetherSyncReason.inactive
        : argument is Map && (request is! int || request <= _lastRequest)
        ? TogetherSyncReason.staleRequest
        : null;
    journal.record(
      TogetherSyncPhase.pulseReceived,
      request: request is int ? request : null,
      accepted: reason == null,
    );
    if (reason != null) {
      journal.record(TogetherSyncPhase.pulseRejected, reason: reason);
      return false;
    }
    if (request is int) _lastRequest = request;
    _pulses++;
    if (argument is Map) {
      // This ACK confirms delivery only. Export HTTP/application events
      // separately; a blocked async phase must never look like a successful
      // synchronization just because the native callback was acknowledged.
      unawaited(_runPoll(request is int ? request : null));
    } else {
      // Preserve the completion contract of older local lease-only probes.
      await _runPoll(null);
    }
    return true;
  }

  Future<void> _runPoll(int? request) async {
    final clock = Stopwatch()..start();
    try {
      await poll();
      journal.record(
        TogetherSyncPhase.pulsePollCompleted,
        request: request,
        durationMs: clock.elapsedMilliseconds,
      );
    } catch (_) {
      _pollFailures++;
      journal.record(
        TogetherSyncPhase.pulsePollFailed,
        request: request,
        durationMs: clock.elapsedMilliseconds,
      );
    }
  }

  /// Manually invoked by the local preview/copy page. This only asks the
  /// existing native worker for its in-memory journal, never an account API.
  static Future<Map<String, Object>> captureDiagnostics({
    Map<String, int> synchronization = const {},
    TogetherSyncDiagnostics? journal,
  }) async {
    final current = _owner;
    var native = <String, Object>{'available': false};
    final supported =
        current?.supported ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    if (supported) {
      try {
        final raw = await _channel
            .invokeMethod<Object?>('diagnosticSnapshot')
            .timeout(const Duration(seconds: 2));
        native = TogetherSyncDiagnostics.sanitizeNative(raw);
      } catch (_) {
        // Native absence is explicit, and cannot break audio or room state.
      }
    }
    return {
      'format': 'mesting-together-sync-v1',
      'diagnosticLoggingEnabled':
          TogetherSyncDiagnostics.diagnosticLoggingEnabled,
      'generatedUtcMs': DateTime.now().toUtc().millisecondsSinceEpoch,
      'dart': (journal ?? current?.journal ?? TogetherSyncDiagnostics.shared)
          .snapshot(),
      'bindingCounts': {
        'configurationAttempts': current?._configurationAttempts ?? 0,
        'configurationAccepted': current?._configurationAccepted ?? 0,
        'configurationFailures': current?._configurationFailures ?? 0,
        'dartPulses': current?._pulses ?? 0,
        'pollFailures': current?._pollFailures ?? 0,
      },
      'synchronizationCounts': {
        for (final key in ['remoteReceived', 'remoteApplied', 'remoteTimeouts'])
          if (synchronization[key] != null) key: synchronization[key]!,
      },
      'native': native,
    };
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
    journal.record(TogetherSyncPhase.bindingDisposed);
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
              'diagnosticLogging': journal.logEvents,
            })
            .catchError((Object _) {}),
      );
      _channel.setMethodCallHandler(null);
      _owner = null;
    }
  }
}
