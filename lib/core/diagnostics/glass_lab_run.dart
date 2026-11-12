import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../performance/frame_timing_probe.dart';

/// Fixed synthetic scenes. IDs and labels contain no real library/account data.
enum GlassLabScenario {
  staticSingle('静止背景 / 单玻璃'),
  scrollSingle('滚动背景 / 单玻璃'),
  peersSeparate('滚动背景 / 双玻璃独立'),
  peersShared('滚动背景 / 双玻璃共享'),
  peersSharedMixedFilters('共享背景 / 不同滤镜'),
  overlap('滚动背景 / 重叠玻璃独立'),
  menuMorph('菜单尺寸形变'),
  pageSlide('双页面滑动过渡');

  const GlassLabScenario(this.label);
  final String label;
}

class GlassLabCancelled implements Exception {}

/// Cancellation races awaited work as well as guarding every subsequent action.
/// A timeout alone does not cancel its original future or prevent late gestures.
class GlassLabTicket {
  final _cancelled = Completer<void>();
  bool get cancelled => _cancelled.isCompleted;
  void cancel() {
    if (!cancelled) _cancelled.complete();
  }

  void check() {
    if (cancelled) throw GlassLabCancelled();
  }

  Future<void> wait(Future<void> action) => Future.any([
    action,
    _cancelled.future.then<void>((_) => throw GlassLabCancelled()),
  ]);
}

abstract interface class GlassLabDriver {
  Future<void> prepare(GlassLabScenario scenario, GlassLabTicket ticket);
  Future<void> exercise(GlassLabScenario scenario, GlassLabTicket ticket);
  void stopMotion();
}

abstract interface class GlassLabRecorder {
  bool get busy;
  void begin(double displayHz, Map<String, Object> environment);
  Future<Map<String, Object>> finish();
}

abstract interface class GlassLabReportSink {
  Future<void> save(Map<String, Object?> report);
}

/// Adapt the existing bounded recorder; keep the eight-scene orchestration
/// independent of widgets, platform channels and actual rendering support.
class FrameProbeGlassLabRecorder implements GlassLabRecorder {
  bool _ownsCapture = false;
  @override
  bool get busy =>
      FrameTimingProbe.recording.value || FrameTimingProbe.draining.value;
  @override
  void begin(double displayHz, Map<String, Object> environment) {
    if (busy) throw StateError('capture_busy');
    FrameTimingProbe.beginSession(displayHz, environment: environment);
    _ownsCapture = true;
  }

  @override
  Future<Map<String, Object>> finish() async {
    if (!_ownsCapture) return {};
    await FrameTimingProbe.stopSession();
    _ownsCapture = false;
    return FrameTimingProbe.sessionReport();
  }
}

/// A closed environment vocabulary prevents future callers from accidentally
/// exporting credentials, arbitrary paths, URLs or application content.
Map<String, Object> glassLabEnvironment(Map<String, Object> source) => {
  for (final key in ['appVersion', 'buildNumber'])
    if (source[key] case final String value
        when RegExp(r'^[0-9A-Za-z.+_-]{1,64}$').hasMatch(value))
      key: value,
  if (source['theme'] case final String value
      when {'light', 'dark'}.contains(value))
    'theme': value,
  for (final key in ['physicalWidth', 'physicalHeight', 'devicePixelRatio'])
    if (source[key] case final num value when value.isFinite && value > 0)
      key: value,
  'shaderFilterSupported': source['shaderFilterSupported'] == true,
  'reduceMotion': source['reduceMotion'] == true,
  'requestedRendererBackend':
      {
        'auto',
        'opengles',
        'vulkan',
      }.contains(source['requestedRendererBackend'])
      ? source['requestedRendererBackend']!
      : 'unknown',
};

/// Each scene saves a detached report before advancing. UI work stays in the
/// driver; timing ownership, cancellation, suppression and persistence stay here.
class GlassLabRunController extends ChangeNotifier {
  GlassLabRunController({
    required this.recorder,
    required this.sink,
    required this.setActive,
    required this.isOtherDiagnosticActive,
    this.stageTimeout = const Duration(seconds: 20),
  });
  final GlassLabRecorder recorder;
  final GlassLabReportSink sink;
  final ValueChanged<bool> setActive;
  final bool Function() isOtherDiagnosticActive;
  final Duration stageTimeout;
  final List<Map<String, Object?>> _records = [];
  GlassLabTicket? _ticket;
  GlassLabDriver? _driver;
  bool _disposed = false;
  bool running = false;
  bool savingFailed = false;
  GlassLabScenario? current;
  String phase = '尚未运行';
  Map<String, Object> _environment = {};

  List<Map<String, Object?>> get records => [
    for (final row in _records) Map.of(row),
  ];
  Map<String, Object?> report() =>
      jsonDecode(
            jsonEncode({
              'schema': 1,
              'diagnosticScope': 'synthetic_glass_lab',
              'syntheticContentOnly': true,
              'backendVerified': false,
              'acceptedAsProductPerformanceResult': false,
              'buildMode': kReleaseMode
                  ? 'release'
                  : kProfileMode
                  ? 'profile'
                  : 'debug',
              'measurementKind':
                  !kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android &&
                      !kDebugMode &&
                      _environment['shaderFilterSupported'] == true
                  ? 'androidEngineTimingNeedsBackendVerification'
                  : 'hostOrDebugStructureOnly',
              'environment': _environment,
              'records': _records,
            }),
          )
          as Map<String, Object?>;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    _ticket?.cancel();
    _driver?.stopMotion();
  }

  Future<bool> run(
    Iterable<GlassLabScenario> scenarios, {
    required GlassLabDriver driver,
    required double displayHz,
    required Map<String, Object> environment,
    Future<void> Function()? beforeRun,
  }) async {
    if (_disposed || running || recorder.busy || isOtherDiagnosticActive()) {
      return false;
    }
    final cases = scenarios.toSet().toList();
    if (cases.isEmpty) return false;
    final ticket = _ticket = GlassLabTicket();
    _driver = driver;
    _environment = glassLabEnvironment(environment);
    _records.clear();
    running = true;
    savingFailed = false;
    phase = '准备场景';
    setActive(true);
    _notify();
    try {
      if (beforeRun != null) {
        await ticket.wait(beforeRun()).timeout(stageTimeout);
      }
      for (final scenario in cases) {
        ticket.check();
        current = scenario;
        phase = '准备场景';
        _notify();
        var captured = false;
        var status = 'completed';
        Map<String, Object> timing = {};
        try {
          await ticket
              .wait(driver.prepare(scenario, ticket))
              .timeout(stageTimeout);
          ticket.check();
          recorder.begin(displayHz, {
            ..._environment,
            'diagnosticScope': 'synthetic_glass_lab',
            'scenarioId': scenario.name,
          });
          captured = true;
          phase = '采集中';
          _notify();
          await ticket
              .wait(driver.exercise(scenario, ticket))
              .timeout(stageTimeout);
          ticket.check();
        } on GlassLabCancelled {
          status = 'cancelled';
        } on TimeoutException {
          status = 'timeout';
          ticket.cancel();
        } on Object {
          status = 'failed';
          ticket.cancel();
        } finally {
          driver.stopMotion();
          if (captured) {
            phase = '收齐本段报告';
            _notify();
            timing = await recorder.finish();
          }
        }
        _records.add({
          'scenario': scenario.name,
          'label': scenario.label,
          'status': status,
          'timing': timing,
        });
        try {
          await sink.save(report());
        } on Object {
          savingFailed = true;
        }
        _notify();
        if (ticket.cancelled) break;
      }
    } on GlassLabCancelled {
      phase = '已停止';
    } on Object {
      // Closed status only: do not expose a raw exception or a private path.
      phase = '准备未完成';
    } finally {
      driver.stopMotion();
      _driver = null;
      _ticket = null;
      running = false;
      if (phase != '准备未完成') phase = ticket.cancelled ? '已停止' : '本轮完成';
      setActive(false);
      _notify();
    }
    return true;
  }

  @override
  void dispose() {
    cancel();
    _disposed = true;
    super.dispose();
  }
}
