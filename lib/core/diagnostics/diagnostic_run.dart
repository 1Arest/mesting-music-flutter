import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../performance/frame_timing_probe.dart';

enum DiagnosticPhase { normal, fastReverse, pages, transition }

/// Only fixed catalogue IDs and timing categories cross this persistence
/// boundary. Never add a Track, account, URL or raw exception to this model.
class DiagnosticScenario {
  const DiagnosticScenario(this.id, this.label, this.platform);
  final String id, label;
  final String? platform;
}

class DiagnosticSkip implements Exception {
  const DiagnosticSkip(this.reason);
  final String reason;
}

class DiagnosticCancelled implements Exception {}

/// Cooperative cancellation also invalidates a timed-out adapter. Dart's
/// Future.timeout does not cancel its original future; every awaited adapter
/// operation must check this ticket before performing its next navigation.
class DiagnosticTicket {
  bool cancelled = false;
  void check() {
    if (cancelled) throw DiagnosticCancelled();
  }
}

abstract interface class DiagnosticDriver {
  List<DiagnosticScenario> get scenarios;
  Future<void> open(DiagnosticScenario scenario, DiagnosticTicket ticket);
  Future<Map<String, Object>> exercise(
    DiagnosticScenario scenario,
    DiagnosticPhase phase,
    DiagnosticTicket ticket,
  );
  Future<void> close();
  Future<void> restore(DiagnosticTicket ticket);
}

/// One raw timing file per stage keeps the live recorder bounded. Checkpoints
/// contain summaries and a cursor, so a native process death loses at most the
/// in-flight stage. The backup survives a crash between rename operations.
class DiagnosticRunStore {
  DiagnosticRunStore(this.directory);
  final Directory directory;

  static Future<DiagnosticRunStore> open() async {
    final root = await getApplicationSupportDirectory();
    final store = DiagnosticRunStore(
      Directory('${root.path}/flow_diagnostics'),
    );
    await store.directory.create(recursive: true);
    return store;
  }

  Future<Map<String, dynamic>?> load() async {
    for (final name in ['checkpoint.json', 'checkpoint.previous.json']) {
      try {
        final value = jsonDecode(
          await File('${directory.path}/$name').readAsString(),
        );
        if (value is Map<String, dynamic> &&
            value['schema'] == 1 &&
            value['records'] is List &&
            value['runId'] is String &&
            RegExp(r'^run-\d+$').hasMatch(value['runId'] as String) &&
            value['nextScenario'] is int &&
            (value['nextScenario'] as int) >= 0 &&
            value['nextPhase'] is int &&
            (value['nextPhase'] as int) >= 0 &&
            (value['nextPhase'] as int) < DiagnosticPhase.values.length) {
          return value;
        }
      } on Object {
        // A partially written latest checkpoint can fall back to the last
        // durable stage. No credential or raw filesystem error is exported.
      }
    }
    return null;
  }

  Future<void> save(Map<String, Object?> checkpoint) async {
    await directory.create(recursive: true);
    final target = File('${directory.path}/checkpoint.json');
    final backup = File('${directory.path}/checkpoint.previous.json');
    final temporary = File('${directory.path}/checkpoint.next.json');
    await temporary.writeAsString(jsonEncode(checkpoint), flush: true);
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) await target.rename(backup.path);
    await temporary.rename(target.path);
  }

  Future<void> segment(
    String run,
    int index,
    Map<String, Object> report,
  ) async {
    await File(
      '${directory.path}/$run-$index.json',
    ).writeAsString(jsonEncode(report), flush: true);
  }

  /// Stream the whole report rather than retaining an entire long run's raw
  /// frames in memory. The share bridge accepts this fixed local JSON only.
  Future<File> export(Map<String, Object?> checkpoint) async {
    final file = File('${directory.path}/mesting-flow-report.json');
    final sink = file.openWrite();
    try {
      sink.write('{"session":${jsonEncode(checkpoint)},"segments":[');
      final records = (checkpoint['records'] as List?) ?? const [];
      var comma = false;
      for (var i = 0; i < records.length; i++) {
        final frame = File('${directory.path}/${checkpoint['runId']}-$i.json');
        if (!await frame.exists()) continue;
        if (comma) sink.write(',');
        comma = true;
        await sink.addStream(frame.openRead());
      }
      sink.write(']}');
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file;
  }
}

/// Orchestration owns progress/cancellation/persistence, while the production
/// page driver owns only navigation and scroll actions. Tests inject both.
class DiagnosticRunController extends ChangeNotifier {
  DiagnosticRunController(
    this.store, {
    Future<void> Function()? stopCapture,
    void Function(double, Map<String, Object>)? beginCapture,
    Map<String, Object> Function()? captureReport,
    this.pageTimeout = const Duration(seconds: 25),
    this.stageTimeout = const Duration(seconds: 18),
  }) : _stopCapture = stopCapture ?? FrameTimingProbe.stopSession,
       _beginCapture =
           beginCapture ??
           ((hz, env) => FrameTimingProbe.beginSession(hz, environment: env)),
       _captureReport = captureReport ?? FrameTimingProbe.sessionReport;

  final DiagnosticRunStore store;
  final Future<void> Function() _stopCapture;
  final void Function(double, Map<String, Object>) _beginCapture;
  final Map<String, Object> Function() _captureReport;
  Map<String, Object?> checkpoint = {};
  bool running = false;
  bool stopRequested = false;
  String current = '';
  DiagnosticTicket? _ticket;
  final Duration pageTimeout;
  final Duration stageTimeout;

  List<Map<String, dynamic>> get records => [
    for (final row in (checkpoint['records'] as List?) ?? const [])
      Map<String, dynamic>.from(row as Map),
  ];
  bool get resumable =>
      checkpoint.isNotEmpty && checkpoint['status'] != 'completed';

  Future<void> load() async {
    checkpoint = Map<String, Object?>.from(await store.load() ?? {});
    notifyListeners();
  }

  void stop() {
    stopRequested = true;
    _ticket?.cancelled = true;
    notifyListeners();
  }

  Future<void> run(
    DiagnosticDriver driver, {
    required double displayHz,
    required Map<String, Object> environment,
    required String? originalPlatform,
    String? originalAccountChoice,
    required void Function(bool) setActive,
    bool resume = false,
  }) async {
    if (running) return;
    running = true;
    stopRequested = false;
    final scenarios = List<DiagnosticScenario>.unmodifiable(driver.scenarios);
    final oldManifest = checkpoint['scenarioManifest'] as List?;
    // Cursors refer to an exact catalogue order. An upgraded app must not
    // silently skip newly added pages by reusing another version's indices.
    final sameManifest =
        oldManifest != null &&
        listEquals(
          [
            for (final row in oldManifest)
              if (row is Map) row['id'],
          ],
          [for (final scenario in scenarios) scenario.id],
        );
    if (!resume || !resumable || !sameManifest) {
      checkpoint = {
        'schema': 1,
        'runId': 'run-${DateTime.now().microsecondsSinceEpoch}',
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'originalPlatform': originalPlatform,
        'originalAccountChoice': originalAccountChoice,
        'environment': environment,
        'nextScenario': 0,
        'nextPhase': 0,
        'records': <Map<String, Object?>>[],
        'scenarioManifest': [
          for (final scenario in scenarios)
            {
              'id': scenario.id,
              'label': scenario.label,
              'platform': scenario.platform,
            },
        ],
        'playbackNotice': '切换平台会暂停并保存播放；结束恢复原平台，不自动重新播放。',
      };
    }
    // This precedes the first platform switch/page build, including retries.
    setActive(true);
    checkpoint['status'] = 'running';
    try {
      await store.save(checkpoint);
      for (
        var si = checkpoint['nextScenario'] as int;
        si < scenarios.length;
        si++
      ) {
        if (stopRequested) break;
        final scenario = scenarios[si];
        var pi = si == checkpoint['nextScenario']
            ? checkpoint['nextPhase'] as int
            : 0;
        current = scenario.label;
        notifyListeners();
        final ticket = _ticket = DiagnosticTicket();
        try {
          await driver.open(scenario, ticket).timeout(pageTimeout);
          for (; pi < DiagnosticPhase.values.length; pi++) {
            ticket.check();
            final phase = DiagnosticPhase.values[pi];
            final startedAt = DateTime.now().toUtc().toIso8601String();
            current =
                '${scenario.label} · ${switch (phase) {
                  DiagnosticPhase.normal => '正常滚动',
                  DiagnosticPhase.fastReverse => '超快与反向滚动',
                  DiagnosticPhase.pages => '左右分页',
                  DiagnosticPhase.transition => '进入与返回',
                }}';
            notifyListeners();
            _beginCapture(displayHz, {
              ...environment,
              'scenario': scenario.id,
              'phase': phase.name,
            });
            Map<String, Object>? actions;
            Object? failure;
            try {
              actions = await driver
                  .exercise(scenario, phase, ticket)
                  .timeout(stageTimeout);
            } on Object catch (error) {
              failure = error;
              if (error is TimeoutException) ticket.cancelled = true;
            } finally {
              // Preserve the original raw-vsync stop boundary and Release drain.
              await _stopCapture();
            }
            if (stopRequested) break;
            final report = _captureReport();
            final frames = (report['samples'] as List?)?.length ?? 0;
            final status = failure is DiagnosticSkip
                ? 'skipped'
                : failure != null
                ? 'failed'
                : frames == 0
                ? 'failed'
                : 'passed';
            await _record(
              scenario,
              phase.name,
              status,
              reason: failure is DiagnosticSkip
                  ? failure.reason
                  : failure is TimeoutException
                  ? 'stage_timeout'
                  : failure != null
                  ? 'stage_error'
                  : frames == 0
                  ? 'no_frame_timings'
                  : null,
              details: actions,
              report: report,
              startedAt: startedAt,
              nextScenario: pi == DiagnosticPhase.values.length - 1
                  ? si + 1
                  : si,
              nextPhase: (pi + 1) % DiagnosticPhase.values.length,
            );
            if (ticket.cancelled) break;
          }
        } on DiagnosticCancelled {
          if (!stopRequested) {
            await _record(
              scenario,
              'open',
              'failed',
              reason: 'stage_cancelled',
              nextScenario: si + 1,
            );
          }
        } on DiagnosticSkip catch (skip) {
          await _record(
            scenario,
            'open',
            'skipped',
            reason: skip.reason,
            nextScenario: si + 1,
          );
        } on Object catch (error) {
          ticket.cancelled = true;
          await _record(
            scenario,
            'open',
            'failed',
            reason: error is TimeoutException ? 'page_timeout' : 'page_error',
            nextScenario: si + 1,
          );
        } finally {
          ticket.cancelled = true;
          try {
            await driver.close().timeout(const Duration(seconds: 4));
          } on Object {
            await _record(
              scenario,
              'close',
              'failed',
              reason: 'page_close_failed',
              nextScenario: si + 1,
            );
          }
        }
        if (!stopRequested && checkpoint['nextScenario'] == si) {
          // A timed-out action invalidated its adapter. Continue at the next
          // page instead of letting its delayed continuation touch a new page.
          checkpoint['nextScenario'] = si + 1;
          checkpoint['nextPhase'] = 0;
          await store.save(checkpoint);
        }
      }
      checkpoint['status'] = stopRequested ? 'stopped' : 'completed';
    } on Object {
      checkpoint['status'] = 'interrupted';
      checkpoint['persistenceError'] = true;
    } finally {
      final restoreTicket = DiagnosticTicket();
      try {
        await driver
            .restore(restoreTicket)
            .timeout(const Duration(seconds: 12));
        checkpoint['platformRestored'] = true;
      } on Object {
        checkpoint['platformRestored'] = false;
      } finally {
        restoreTicket.cancelled = true;
      }
      setActive(false);
      running = false;
      _ticket = null;
      checkpoint['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      try {
        await store.save(checkpoint);
      } on Object {
        checkpoint['persistenceError'] = true;
      }
      notifyListeners();
    }
  }

  Future<void> _record(
    DiagnosticScenario scenario,
    String phase,
    String status, {
    String? reason,
    Map<String, Object>? details,
    Map<String, Object>? report,
    String? startedAt,
    required int nextScenario,
    int nextPhase = 0,
  }) async {
    final list = List<Map<String, dynamic>>.from(records);
    if (report != null) {
      await store.segment(checkpoint['runId']! as String, list.length, report);
    }
    list.add({
      'scenario': scenario.id,
      'label': scenario.label,
      'platform': scenario.platform,
      'phase': phase,
      'status': status,
      'startedAt': ?startedAt,
      'finishedAt': DateTime.now().toUtc().toIso8601String(),
      'reason': ?reason,
      'actions': ?details,
      if (report != null)
        'timing': {
          'frames': (report['samples'] as List?)?.length ?? 0,
          'summary': report['summary'],
          'displayHz': report['displayHz'],
          'elapsedMs': report['elapsedMs'],
          'timingsDrained': report['timingsDrained'],
          ...diagnosticTimingMetrics(report),
        },
    });
    checkpoint['records'] = list;
    checkpoint['nextScenario'] = nextScenario;
    checkpoint['nextPhase'] = nextPhase;
    await store.save(checkpoint);
    notifyListeners();
  }
}

/// Numeric fields supplement the old compact text so a JSON consumer does not
/// need to parse formatted strings. Budgets come from the display's real Hz.
Map<String, Object> diagnosticTimingMetrics(Map<String, Object> report) {
  final frames = (report['samples'] as List?) ?? const [];
  final hz = (report['displayHz'] as num?)?.toDouble() ?? 0;
  final budget = hz > 0 ? 1000000 / hz : 16667.0;
  List<int> times(String key) => [
    for (final frame in frames)
      if (frame is Map && frame[key] is num) (frame[key] as num).toInt(),
  ]..sort();
  double percentile(List<int> values, double p) =>
      values.isEmpty ? 0 : values[((values.length - 1) * p).floor()] / 1000;
  final build = times('buildUs'), raster = times('rasterUs');
  return {
    'frameBudgetUs': budget,
    for (final entry in {'build': build, 'raster': raster}.entries) ...{
      '${entry.key}P50Ms': percentile(entry.value, .5),
      '${entry.key}P90Ms': percentile(entry.value, .9),
      '${entry.key}P99Ms': percentile(entry.value, .99),
      '${entry.key}OverDisplayBudget': entry.value
          .where((v) => v > budget)
          .length,
      '${entry.key}Over16_67Ms': entry.value.where((v) => v > 16667).length,
    },
  };
}
