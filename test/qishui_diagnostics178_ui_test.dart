import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostic_export.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostics_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/release_147_qa.dart' show load147IconFonts;

const _capture = bool.fromEnvironment('CAPTURE_178');

class _Exporter extends QishuiDiagnosticExport {
  _Exporter({this.pending, this.fail = false});
  final Completer<void>? pending;
  final bool fail;
  int calls = 0;
  QishuiDiagnosticGroup? selected;

  @override
  Future<void> share({
    required QishuiDiagnostics diagnostics,
    QishuiDiagnosticGroup group = QishuiDiagnosticGroup.all,
  }) async {
    calls++;
    selected = group;
    if (pending != null) await pending!.future;
    if (fail) throw const FormatException('private-platform-exception-178');
  }
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_capture) {
      await load147IconFonts();
      await (FontLoader('SodaQA178')..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  QishuiDiagnostics sample() {
    final diagnostics = QishuiDiagnostics(
      now: () => DateTime.utc(2026, 11, 8, 5, 30),
    );
    diagnostics.record(
      feature: QishuiDiagnosticFeature.following,
      stage: QishuiDiagnosticStage.parse,
      outcome: QishuiDiagnosticOutcome.format,
      reason: QishuiDiagnosticReason.missingFields,
      response: const {
        'data': {'items': <Object>[]},
      },
    );
    diagnostics.record(
      feature: QishuiDiagnosticFeature.officialListening,
      stage: QishuiDiagnosticStage.parse,
      outcome: QishuiDiagnosticOutcome.format,
      reason: QishuiDiagnosticReason.missingFields,
    );
    diagnostics.record(
      feature: QishuiDiagnosticFeature.coverUpload,
      stage: QishuiDiagnosticStage.apply,
      outcome: QishuiDiagnosticOutcome.http,
      httpStatus: 400,
      serviceCode: 'InvalidAuthorization',
    );
    return diagnostics;
  }

  Future<void> mount(
    WidgetTester tester,
    QishuiDiagnostics diagnostics, {
    _Exporter? exporter,
    bool dark = false,
    bool large = false,
    GlobalKey? boundary,
  }) async {
    final width = large ? 320.0 : 390.0;
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'app_haptics_enabled_v1': false});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          qishuiNavigationProvider.overrideWithValue(true),
          currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
          audioHandlerProvider.overrideWith(
            (ref) => throw StateError(
              'Opening diagnostics must not construct a player',
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: _capture ? 'SodaQA178' : null,
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(large ? 2 : 1),
            ),
            child: RepaintBoundary(
              key: boundary,
              child: QishuiDiagnosticsPage(
                key: ObjectKey(diagnostics),
                diagnostics: diagnostics,
                exporter: exporter ?? _Exporter(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    if (!_capture) return;
    await tester.runAsync(() async {
      final picture =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      try {
        final bytes = (await picture.toByteData(
          format: ui.ImageByteFormat.png,
        ))!;
        final target = File(
          '.codex-artifacts/2026-11-08-release178/ui/qishui-diagnostics-$name.png',
        );
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes.buffer.asUint8List());
      } finally {
        picture.dispose();
      }
    });
  }

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'diagnostic filters and targets fit dark=$dark large=$large',
        (tester) async {
          final diagnostics = sample();
          final exporter = _Exporter();
          final boundary = GlobalKey();
          await mount(
            tester,
            diagnostics,
            exporter: exporter,
            dark: dark,
            large: large,
            boundary: boundary,
          );
          expect(find.text('本组 3 条记录'), findsOneWidget);
          final bar = tester.widget<BetaMusicBottomBar>(
            find.byType(BetaMusicBottomBar),
          );
          expect(bar.selectedIndex, 3);
          expect(bar.soda, isTrue);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            boundary,
            '${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
          );
          await tester.ensureVisible(find.text('歌单封面'));
          await tester.tap(find.text('歌单封面'));
          await tester.pumpAndSettle();
          expect(find.text('本组 1 条记录'), findsOneWidget);
          if (large) {
            // Capture the controls after a real scroll, alongside the retained
            // glass navigation. Top-of-page images alone cannot prove that
            // large-text copy/export actions clear the bottom overlay.
            await tester.ensureVisible(find.text('复制精简记录'));
            await tester.pumpAndSettle();
            final chrome = tester.getRect(find.byType(BetaMusicBottomBar));
            for (final label in ['复制精简记录', '导出 JSON 文件']) {
              final target = tester.getRect(
                find.widgetWithText(BetaGlassButton, label),
              );
              expect(target.bottom, lessThanOrEqualTo(chrome.top));
            }
            await capture(
              tester,
              boundary,
              '${dark ? 'dark' : 'light'}-large-actions',
            );
          }
          await tester.ensureVisible(find.text('导出 JSON 文件'));
          final button = tester.widget<BetaGlassButton>(
            find.widgetWithText(BetaGlassButton, '导出 JSON 文件'),
          );
          expect(button.height, greaterThanOrEqualTo(48));
          await tester.tap(find.text('导出 JSON 文件'));
          await tester.pumpAndSettle();
          expect(exporter.calls, 1);
          expect(exporter.selected, QishuiDiagnosticGroup.cover);
          expect(find.text('已打开系统分享，可保存或发送 JSON 文件。'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('copy uses only the selected group and verifies the clipboard', (
    tester,
  ) async {
    String? clipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
            return null;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await mount(tester, sample());
    await tester.tap(find.text('听歌时长'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('复制精简记录'));
    await tester.tap(find.text('复制精简记录'));
    await tester.pumpAndSettle();
    final report = jsonDecode(clipboard!) as Map;
    expect(report['group'], 'listening');
    expect(report['eventCount'], 1);
    expect(report['events'][0]['feature'], 'officialListening');
    expect(find.text('已复制并核对，可粘贴发送。'), findsOneWidget);
  });

  testWidgets(
    'pending export disables further actions without duplicate calls',
    (tester) async {
      final pending = Completer<void>();
      final exporter = _Exporter(pending: pending);
      await mount(tester, sample(), exporter: exporter);
      final exportButton = find.widgetWithText(BetaGlassButton, '导出 JSON 文件');
      final copyButton = find.widgetWithText(BetaGlassButton, '复制精简记录');
      final coverChip = find.widgetWithText(ChoiceChip, '歌单封面');
      final scrollable = find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      );
      try {
        await tester.ensureVisible(find.text('导出 JSON 文件'));
        await tester.tap(find.text('导出 JSON 文件'));
        await tester.pump();
        expect(tester.widget<BetaGlassButton>(exportButton).onPressed, isNull);
        // A second activation while IO is pending must not invoke sharing.
        await tester.tap(find.text('导出 JSON 文件'), warnIfMissed: false);
        await tester.pump();
        expect(exporter.calls, 1);

        // ListView disposes offscreen children. Build each target explicitly
        // instead of relying on fonts or a previous capture's scroll position.
        await tester.scrollUntilVisible(
          copyButton,
          -120,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(tester.widget<BetaGlassButton>(copyButton).onPressed, isNull);
        await tester.scrollUntilVisible(
          coverChip,
          -120,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(coverChip).onSelected, isNull);
        expect(exporter.selected, QishuiDiagnosticGroup.all);
        expect(exporter.calls, 1);
      } finally {
        // This fixture has no timer: settling widget frames must not await the
        // unfinished IO future, and every assertion path releases it once.
        if (!pending.isCompleted) pending.complete();
      }
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'empty group disables export and failure does not reveal platform text',
    (tester) async {
      await mount(tester, QishuiDiagnostics());
      expect(
        tester
            .widget<BetaGlassButton>(
              find.widgetWithText(BetaGlassButton, '导出 JSON 文件'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('本组暂无记录，请返回汽水页面复现一次问题。'), findsOneWidget);
      await mount(tester, sample(), exporter: _Exporter(fail: true));
      await tester.ensureVisible(find.text('导出 JSON 文件'));
      await tester.tap(find.text('导出 JSON 文件'));
      await tester.pumpAndSettle();
      expect(find.text('文件暂未导出，请重试或复制精简记录。'), findsOneWidget);
      expect(
        find.textContaining('private-platform-exception-178'),
        findsNothing,
      );
    },
  );
}
