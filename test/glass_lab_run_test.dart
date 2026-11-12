import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/diagnostics/glass_lab_run.dart';

class _Recorder implements GlassLabRecorder {
  @override
  bool busy = false;
  int begins = 0, finishes = 0;
  Completer<void>? drain;
  @override
  void begin(double displayHz, Map<String, Object> environment) {
    begins++;
    busy = true;
  }

  @override
  Future<Map<String, Object>> finish() async {
    finishes++;
    if (drain != null) await drain!.future;
    busy = false;
    return {'schema': 2, 'timingsDrained': true, 'samples': <Object>[]};
  }
}

class _Sink implements GlassLabReportSink {
  final reports = <Map<String, Object?>>[];
  bool fail = false;
  @override
  Future<void> save(Map<String, Object?> report) async {
    if (fail) throw StateError('private-path-token');
    reports.add(report);
  }
}

class _Driver implements GlassLabDriver {
  Completer<void>? prepareGate, exerciseGate;
  bool fail = false;
  int opened = 0, exercised = 0, stopped = 0;
  @override
  Future<void> prepare(GlassLabScenario scenario, GlassLabTicket ticket) async {
    opened++;
    if (prepareGate != null) await prepareGate!.future;
    ticket.check();
  }

  @override
  Future<void> exercise(
    GlassLabScenario scenario,
    GlassLabTicket ticket,
  ) async {
    if (fail) throw StateError('private-account-secret');
    if (exerciseGate != null) await exerciseGate!.future;
    ticket.check();
    exercised++;
  }

  @override
  void stopMotion() {
    stopped++;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Recorder recorder;
  late _Sink sink;
  late _Driver driver;
  late List<bool> activity;
  late GlassLabRunController controller;
  setUp(() {
    recorder = _Recorder();
    sink = _Sink();
    driver = _Driver();
    activity = [];
    controller = GlassLabRunController(
      recorder: recorder,
      sink: sink,
      setActive: activity.add,
      isOtherDiagnosticActive: () => false,
    );
  });
  tearDown(() => controller.dispose());

  test('catalogue contains exactly eight fixed independent scenes', () {
    expect(GlassLabScenario.values, hasLength(8));
    expect(GlassLabScenario.values.map((s) => s.name).toSet(), hasLength(8));
  });
  test(
    'environment export drops private vocabulary and non-finite dimensions',
    () {
      final data = glassLabEnvironment({
        'appVersion': '1.0.90',
        'buildNumber': '111',
        'token': 'secret',
        'account': 'account',
        'url': 'https://private',
        'requestedRendererBackend': 'credentials',
        'physicalWidth': double.infinity,
        'reduceMotion': true,
      });
      expect(data.keys, isNot(contains('token')));
      expect(data.keys, isNot(contains('account')));
      expect(data.keys, isNot(contains('url')));
      expect(data.keys, isNot(contains('physicalWidth')));
      expect(data['requestedRendererBackend'], 'unknown');
      expect(data['reduceMotion'], isTrue);
    },
  );
  test(
    'eight scenes persist independently and never imply performance acceptance',
    () async {
      await controller.run(
        GlassLabScenario.values,
        driver: driver,
        displayHz: 120,
        environment: {},
      );
      expect(activity, [true, false]);
      expect(recorder.begins, 8);
      expect(recorder.finishes, 8);
      expect(sink.reports, hasLength(8));
      expect(sink.reports.first['records'], hasLength(1));
      expect(controller.records, hasLength(8));
      final report = controller.report();
      expect(report['acceptedAsProductPerformanceResult'], isFalse);
      (report['records'] as List).clear();
      expect(controller.records, hasLength(8));
    },
  );
  test('busy recorder is never borrowed or stopped', () async {
    recorder.busy = true;
    expect(
      await controller.run(
        [GlassLabScenario.scrollSingle],
        driver: driver,
        displayHz: 120,
        environment: {},
      ),
      isFalse,
    );
    expect(activity, isEmpty);
    expect(recorder.begins, 0);
    expect(recorder.finishes, 0);
  });
  test(
    'cancellation during prepare stops promptly and blocks late work',
    () async {
      driver.prepareGate = Completer<void>();
      final run = controller.run(
        GlassLabScenario.values,
        driver: driver,
        displayHz: 120,
        environment: {},
      );
      await _flush();
      controller.cancel();
      await run;
      expect(recorder.begins, 0);
      expect(activity, [true, false]);
      driver.prepareGate!.complete();
      await _flush();
      expect(driver.exercised, 0);
      expect(controller.records.single['status'], 'cancelled');
    },
  );
  test(
    'cancellation retains the activity latch until the owned batch drains',
    () async {
      driver.exerciseGate = Completer<void>();
      recorder.drain = Completer<void>();
      final run = controller.run(
        GlassLabScenario.values,
        driver: driver,
        displayHz: 120,
        environment: {},
      );
      await _flush();
      controller.cancel();
      await _flush();
      expect(activity, [true]);
      expect(controller.running, isTrue);
      expect(recorder.finishes, 1);
      recorder.drain!.complete();
      await run;
      expect(activity, [true, false]);
      expect(controller.records.single['status'], 'cancelled');
      driver.exerciseGate!.complete();
      await _flush();
      expect(driver.exercised, 0);
    },
  );
  test('driver failures export only a closed status', () async {
    driver.fail = true;
    await controller.run(
      GlassLabScenario.values,
      driver: driver,
      displayHz: 120,
      environment: {},
    );
    expect(controller.records.single['status'], 'failed');
    expect(
      jsonEncode(controller.report()),
      isNot(contains('private-account-secret')),
    );
    expect(activity, [true, false]);
    expect(recorder.finishes, 1);
  });
  test(
    'save failure is visible and does not strand the suppression latch',
    () async {
      sink.fail = true;
      await controller.run(
        [GlassLabScenario.staticSingle],
        driver: driver,
        displayHz: 120,
        environment: {},
      );
      expect(controller.savingFailed, isTrue);
      expect(activity, [true, false]);
      expect(
        jsonEncode(controller.report()),
        isNot(contains('private-path-token')),
      );
    },
  );
  test('a timeout invalidates late driver actions and later scenes', () async {
    controller.dispose();
    controller = GlassLabRunController(
      recorder: recorder,
      sink: sink,
      setActive: activity.add,
      isOtherDiagnosticActive: () => false,
      stageTimeout: const Duration(milliseconds: 10),
    );
    driver.exerciseGate = Completer<void>();
    await controller.run(
      GlassLabScenario.values,
      driver: driver,
      displayHz: 120,
      environment: {},
    );
    expect(controller.records.single['status'], 'timeout');
    expect(driver.opened, 1);
    driver.exerciseGate!.complete();
    await _flush();
    expect(driver.exercised, 0);
    expect(activity, [true, false]);
  });
}
