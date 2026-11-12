import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// These enums are the complete export vocabulary. Callers cannot attach a
/// room, account, song, URL, response body, exception or arbitrary wire token.
enum TogetherSyncPhase {
  bindingStarted,
  bindingDisposed,
  lifecycle,
  configurationSent,
  configurationAccepted,
  configurationFailed,
  configurationRetired,
  configurationRetry,
  pulseReceived,
  pulseRejected,
  pulsePollCompleted,
  pulsePollFailed,
  pollEntered,
  pollSkipped,
  tickStarted,
  tickCompleted,
  tickFailed,
  httpStarted,
  httpCompleted,
  httpTimedOut,
  httpFailed,
  commandReceived,
  commandSkipped,
  applicationQueued,
  applicationStarted,
  applicationCompleted,
  applicationCancelled,
  applicationTimedOut,
  applicationFailed,
  controllerStopped,
}

enum TogetherSyncOperation {
  status,
  roomCheck,
  heartbeat,
  playCommand,
  playlistRead,
  playlistWrite,
  songDetail,
  statistics,
  distance,
  location,
  roomAction,
  other,
}

enum TogetherSyncReason {
  cadence,
  inFlight,
  busy,
  inactive,
  accountEnded,
  roomMissing,
  staleOwner,
  staleLease,
  staleRequest,
  unsupportedMethod,
  timeout,
  unavailable,
  unconfirmed,
  noCommand,
  olderSequence,
  duplicate,
  ownCommand,
  newerCommand,
  userControl,
  queueMissing,
  stopped,
}

enum TogetherSyncLifecycle { detached, resumed, inactive, hidden, paused }

enum TogetherSyncOrder { first, newer, equal, older, opaque }

/// A bounded, process-local diagnostic journal. UTC timestamps correlate the
/// native/Dart streams; monotonic elapsed time exposes scheduling gaps even if
/// the wall clock changes. Reading/exporting never starts a room/network job.
class TogetherSyncDiagnostics {
  TogetherSyncDiagnostics({
    this.capacity = 768,
    DateTime Function()? utcNow,
    this.logEvents = diagnosticLoggingEnabled,
    void Function(String)? logLine,
  }) : assert(capacity > 0),
       _utcNow = utcNow ?? DateTime.now,
       _logLine = logLine ?? _printLine;

  /// Only an explicitly built private diagnostic candidate emits logcat data.
  /// Normal builds retain the bounded manual report with logging disabled.
  static const diagnosticLoggingEnabled = bool.fromEnvironment(
    'TOGETHER_SYNC_DIAGNOSTICS',
  );
  static const logTag = 'MestingTogetherSync';
  static final shared = TogetherSyncDiagnostics();
  final int capacity;
  final bool logEvents;
  final DateTime Function() _utcNow;
  final void Function(String) _logLine;
  final Stopwatch _clock = Stopwatch()..start();
  final _events = Queue<Map<String, Object>>();
  final _counts = <String, int>{};
  int _index = 0, _dropped = 0;

  static void _printLine(String line) => debugPrint(line, wrapWidth: null);

  void record(
    TogetherSyncPhase phase, {
    TogetherSyncOperation? operation,
    TogetherSyncReason? reason,
    TogetherSyncLifecycle? lifecycle,
    TogetherSyncOrder? order,
    int? request,
    int? configuration,
    int? attempt,
    int? durationMs,
    int? application,
    bool? active,
    bool? background,
    bool? accepted,
    bool? numericSequence,
  }) {
    _counts.update(phase.name, (n) => n + 1, ifAbsent: () => 1);
    if (_events.length == capacity) {
      _events.removeFirst();
      _dropped++;
    }
    final event = <String, Object>{
      'index': ++_index,
      'utcMs': _utcNow().toUtc().millisecondsSinceEpoch,
      'elapsedMs': _clock.elapsedMilliseconds,
      'phase': phase.name,
      if (operation != null) 'operation': operation.name,
      if (reason != null) 'reason': reason.name,
      if (lifecycle != null) 'lifecycle': lifecycle.name,
      if (order != null) 'order': order.name,
      'request': ?request,
      'configuration': ?configuration,
      'attempt': ?attempt,
      'durationMs': ?durationMs,
      'application': ?application,
      'active': ?active,
      'background': ?background,
      'accepted': ?accepted,
      'numericSequence': ?numericSequence,
    };
    _events.addLast(event);
    if (logEvents) {
      try {
        _logLine(jsonEncode({'tag': logTag, 'source': 'dart', ...event}));
      } catch (_) {
        // Diagnostics never own playback progress, even if a log sink fails.
      }
    }
  }

  Map<String, Object> snapshot() => {
    'capacity': capacity,
    'dropped': _dropped,
    'loggingEnabled': logEvents,
    'counts': Map<String, int>.from(_counts),
    'events': _events.map(Map<String, Object>.from).toList(),
  };

  /// The channel is an export boundary too. Reject unknown native keys and
  /// values instead of trusting a map that could later gain sensitive fields.
  static Map<String, Object> sanitizeNative(Object? raw) {
    if (raw is! Map) return {'available': false};
    final result = <String, Object>{'available': true};
    for (final key in ['capacity', 'dropped']) {
      final value = raw[key];
      if (value is int && value >= 0) result[key] = value;
    }
    for (final key in ['enabled', 'pending', 'loggingEnabled']) {
      final value = raw[key];
      if (value is bool) result[key] = value;
    }
    final counts = <String, int>{};
    final rawCounts = raw['counts'];
    if (rawCounts is Map) {
      for (final key in [
        'nativePulses',
        'nativeAcknowledged',
        'nativeTimeouts',
        'nativeRejected',
      ]) {
        final value = rawCounts[key];
        if (value is int && value >= 0) counts[key] = value;
      }
    }
    result['counts'] = counts;
    final events = <Map<String, Object>>[];
    final rawEvents = raw['events'];
    if (rawEvents is List) {
      for (final rawEvent in rawEvents.take(256)) {
        if (rawEvent is! Map || !_nativePhases.contains(rawEvent['phase'])) {
          continue;
        }
        final event = <String, Object>{'phase': rawEvent['phase'] as String};
        for (final key in [
          'index',
          'utcMs',
          'elapsedMs',
          'revision',
          'request',
        ]) {
          final value = rawEvent[key];
          if (value is int) event[key] = value;
        }
        for (final key in ['enabled', 'accepted']) {
          final value = rawEvent[key];
          if (value is bool) event[key] = value;
        }
        events.add(event);
      }
    }
    result['events'] = events;
    return result;
  }

  static const _nativePhases = {
    'engineAttached',
    'configuration',
    'configurationRejected',
    'pulseScheduled',
    'pulseSent',
    'pulseUndeliverable',
    'acknowledged',
    'rejected',
    'staleAcknowledgement',
    'acknowledgementTimeout',
    'leaseExpired',
    'mediaServicePresent',
    'mediaServiceMissing',
    'wakeAcquired',
    'wakeReleased',
    'stopped',
  };
}
