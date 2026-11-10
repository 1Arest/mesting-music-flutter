import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_activity.dart';
import 'package:mesting_music/core/diagnostics/glass_lab_run.dart';
import 'package:mesting_music/core/diagnostics/glass_lab_store.dart';
import 'package:mesting_music/features/settings/presentation/glass_lab_page.dart';
import 'package:mesting_music/shared/widgets/beta_music_chrome_scope.dart';

class _Recorder implements GlassLabRecorder {
  @override
  bool busy = false;
  int starts = 0, stops = 0;
  @override
  void begin(double hz, Map<String, Object> environment) {
    busy = true;
    starts++;
  }

  @override
  Future<Map<String, Object>> finish() async {
    busy = false;
    stops++;
    return {'samples': <Object>[], 'timingsDrained': true};
  }
}

class _Store extends GlassLabReportStore {
  final saved = <Map<String, Object?>>[];
  @override
  Future<void> save(Map<String, Object?> report) async {
    saved.add(report);
  }

  @override
  Future<File> reportFile() async => File('synthetic-glass-lab-report.json');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () async => LiquidGlassWidgets.initialize(enablePerformanceMonitor: false),
  );
  tearDown(() {
    expect(diagnosticRunActive.value, isFalse);
  });
  Future<void> mount(
    WidgetTester tester,
    _Recorder recorder,
    _Store store, {
    double width = 411.43,
    double scale = 1,
    BetaMusicChromeController? chrome,
  }) async {
    tester.view.physicalSize = Size(width, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: BetaMusicChromeScope(
            controller: chrome ?? BetaMusicChromeController(),
            child: GlassLabPage(
              environment: const {'appVersion': '1.0.90', 'buildNumber': '111'},
              displayHz: 120,
              recorder: recorder,
              store: store,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final config in [(411.43, 1.0), (320.0, 1.6)]) {
    testWidgets('eight independent scenes and controls fit $config', (
      tester,
    ) async {
      final recorder = _Recorder(),
          store = _Store(),
          chrome = BetaMusicChromeController();
      await mount(
        tester,
        recorder,
        store,
        width: config.$1,
        scale: config.$2,
        chrome: chrome,
      );
      expect(chrome.covered, isTrue);
      final dropdown = tester.widget<DropdownButton<GlassLabScenario>>(
        find.byType(DropdownButton<GlassLabScenario>),
      );
      expect(dropdown.items, hasLength(8));
      for (final scene in GlassLabScenario.values) {
        dropdown.onChanged!(scene);
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('glass-lab-${scene.name}')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      expect(chrome.covered, isFalse);
    });
  }
  testWidgets(
    'selected scene saves separately and uses the fixed glass export method',
    (tester) async {
      final recorder = _Recorder(), store = _Store();
      await mount(tester, recorder, store);
      final calls = <MethodCall>[];
      const channel = MethodChannel('com.mesting.music/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.tap(find.text('运行当前场景'));
      for (var i = 0; i < 75; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(recorder.starts, 1);
      expect(recorder.stops, 1);
      expect(store.saved, hasLength(1));
      expect(store.saved.single['acceptedAsProductPerformanceResult'], isFalse);
      await tester.tap(find.text('导出本轮 JSON 报告'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'shareGlassLabDiagnosticJson');
      expect(find.text('已打开系统分享，可保存实验报告'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('background cancels the current scene and skips later scenes', (
    tester,
  ) async {
    final recorder = _Recorder(), store = _Store();
    await mount(tester, recorder, store);
    await tester.tap(find.text('依次运行八场景'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 50));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(recorder.starts, lessThanOrEqualTo(1));
    expect(diagnosticRunActive.value, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'disposing an active page releases capture without touching disposed motion',
    (tester) async {
      final recorder = _Recorder(), store = _Store();
      await mount(tester, recorder, store);
      await tester.tap(find.text('运行当前场景'));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(diagnosticRunActive.value, isFalse);
    },
  );
}
