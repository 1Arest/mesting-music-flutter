import 'dart:async';
import 'package:flutter/services.dart';
import 'network.dart';

class RingSharingFacts {
  RingSharingFacts._(
    this.network,
    this.battery,
    this.temperature,
    this.healthy,
    this.powerSave,
    this.thermal,
    this.known,
  );
  final String network;
  final int? battery, temperature, thermal;
  final bool healthy, powerSave, known;

  factory RingSharingFacts.parse(Object? value) {
    if (value is! Map) {
      return RingSharingFacts._(
        'unknown',
        null,
        null,
        false,
        true,
        null,
        false,
      );
    }
    int? integer(String name, int min, int max) {
      final v = value[name];
      return v is int && v >= min && v <= max ? v : null;
    }

    final battery = integer('battery_percent', 0, 100);
    final temperature = integer('temperature_deci_c', 1, 999);
    final thermal = integer('thermal_status', 0, 6);
    final supported = value['thermal_supported'];
    final known =
        value['observing'] == true &&
        battery != null &&
        temperature != null &&
        value['battery_healthy'] is bool &&
        value['power_save'] is bool &&
        supported is bool &&
        (!supported || thermal != null);
    return RingSharingFacts._(
      value['network'] is String ? value['network'] as String : 'unknown',
      battery,
      temperature,
      value['battery_healthy'] == true,
      value['power_save'] != false,
      thermal,
      known,
    );
  }
}

/// One foreground observation owner. Negative transitions revoke synchronously;
/// late native replies never re-enable a different lifecycle generation.
class RingSharingResourcesOwner {
  RingSharingResourcesOwner({
    required this.onAllowedChanged,
    Future<Object?> Function()? read,
    Stream<dynamic>? resourceEvents,
    Stream<dynamic>? networkEvents,
    this.pollEvery = const Duration(seconds: 30),
  }) : _read = read ?? _nativeRead,
       _resourceEvents = resourceEvents ?? _resources,
       _networkEvents = networkEvents ?? RingNetwork.events;

  static const _method = MethodChannel('ring_download_sdk/network');
  static const _event = EventChannel('ring_download_sdk/sharing_resources');
  static Stream<dynamic>? _nativeEvents;
  static Stream<dynamic> get _resources =>
      _nativeEvents ??= _event.receiveBroadcastStream();
  static Future<Object?> _nativeRead() =>
      _method.invokeMapMethod<String, dynamic>('getSharingResources');
  final void Function(bool) onAllowedChanged;
  final Future<Object?> Function() _read;
  final Stream<dynamic> _resourceEvents, _networkEvents;
  final Duration pollEvery;
  final _changes = StreamController<bool>.broadcast();
  Stream<bool> get changes => _changes.stream;
  bool _enabled = false, _foreground = true, _closed = false, _watching = false;
  bool _allowed = false, _hot = false, _low = false, _refreshAgain = false;
  int _revision = 0, _factsRevision = 0, _networkRevision = 0;
  String _network = 'unknown';
  RingSharingFacts? _facts;
  StreamSubscription<dynamic>? _resourcesSub, _networkSub;
  Timer? _timer;
  Future<void>? _starting, _closing;
  Future<bool>? _refreshing;
  final _stopping = <Future<void>>{};
  bool get allowed => _allowed;
  bool get _wanted => !_closed && _enabled && _foreground;

  void setEnabled(bool enabled) {
    if (_enabled == enabled || _closed) return;
    _enabled = enabled;
    if (_wanted) {
      _start();
    } else {
      _stop();
    }
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground || _closed) return;
    _foreground = foreground;
    if (_wanted) {
      _start();
    } else {
      _stop();
    }
  }

  void _publish(bool value) {
    if (_allowed == value) return;
    _allowed = value;
    try {
      onAllowedChanged(value);
    } catch (_) {}
    if (!_changes.isClosed) _changes.add(value);
  }

  void _evaluate() {
    final facts = _facts;
    if (facts == null || !facts.known) {
      _publish(false);
      return;
    }
    if (facts.battery! < 30) {
      _low = true;
    } else if (facts.battery! >= 32) {
      _low = false;
    }
    if (facts.temperature! >= 400 || (facts.thermal ?? 0) >= 2) {
      _hot = true;
    } else if (facts.temperature! <= 380 && (facts.thermal ?? 0) < 2) {
      _hot = false;
    }
    _publish(
      _wanted &&
          _watching &&
          _network == 'wifi_unmetered' &&
          facts.healthy &&
          !facts.powerSave &&
          !_low &&
          !_hot,
    );
  }

  void _start() {
    final owner = ++_revision;
    _starting = () async {
      await Future.wait(_stopping.toList());
      if (!_wanted || owner != _revision) return;
      _watching = true;
      _resourcesSub = _resourceEvents.listen(
        (value) {
          if (!_wanted || owner != _revision) return;
          _factsRevision++;
          _facts = RingSharingFacts.parse(value);
          _evaluate();
        },
        onError: (Object _) {
          if (owner == _revision) {
            _factsRevision++;
            _facts = null;
            _publish(false);
          }
        },
      );
      _networkSub = _networkEvents.listen(
        (value) {
          if (!_wanted || owner != _revision) return;
          _networkRevision++;
          _network = value is String ? value : 'unknown';
          _evaluate();
          if (_network == 'wifi_unmetered') unawaited(refresh());
        },
        onError: (Object _) {
          if (owner == _revision) {
            _networkRevision++;
            _network = 'unknown';
            _publish(false);
          }
        },
      );
      _timer = Timer.periodic(pollEvery, (_) {
        unawaited(refresh());
      });
      unawaited(refresh());
    }();
  }

  Future<bool> ensureCurrent() async {
    await _starting;
    if (!_wanted) return false;
    if (_facts == null || _network == 'unknown') return refresh();
    return _allowed;
  }

  Future<bool> refresh() {
    if (!_wanted || !_watching) return Future.value(false);
    final running = _refreshing;
    if (running != null) {
      _refreshAgain = true;
      return running;
    }
    final owner = _revision, facts = _factsRevision, network = _networkRevision;
    late final Future<bool> flight;
    flight =
        () async {
          try {
            final value = await _read().timeout(const Duration(seconds: 1));
            if (!_wanted || owner != _revision) return false;
            final parsed = RingSharingFacts.parse(value);
            if (facts == _factsRevision) _facts = parsed;
            if (network == _networkRevision) _network = parsed.network;
            _evaluate();
          } catch (_) {
            if (owner == _revision && facts == _factsRevision) {
              _facts = null;
              _publish(false);
            }
          }
          return _allowed;
        }().whenComplete(() {
          if (identical(_refreshing, flight)) _refreshing = null;
          if (_refreshAgain && _wanted && _watching) {
            _refreshAgain = false;
            unawaited(refresh());
          }
        });
    _refreshing = flight;
    return flight;
  }

  void _stop() {
    _revision++;
    _watching = false;
    _timer?.cancel();
    _timer = null;
    _facts = null;
    _network = 'unknown';
    _factsRevision++;
    _networkRevision++;
    _publish(false);
    final resources = _resourcesSub, network = _networkSub;
    _resourcesSub = null;
    _networkSub = null;
    late final Future<void> stopping;
    stopping =
        Future.wait<void>([
              if (resources != null) resources.cancel(),
              if (network != null) network.cancel(),
            ])
            .then<void>((_) {}, onError: (Object _) {})
            .whenComplete(() => _stopping.remove(stopping));
    _stopping.add(stopping);
  }

  Future<void> close() => _closing ??= () async {
    _closed = true;
    _stop();
    await _starting;
    await _refreshing;
    await Future.wait(_stopping.toList());
    await _changes.close();
  }();
}
