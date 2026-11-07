import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_qr_login.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_qr_login_page.dart';
import 'qishui_qr_protocol_test.dart' show FixtureQrGateway;
import 'support/release_152_qa.dart' show theme152;
import 'support/release_147_qa.dart' show load147IconFonts;

const captureQr164 = bool.fromEnvironment('CAPTURE_QR164');
const qrCaptureDirectory = String.fromEnvironment(
  'QR_CAPTURE_DIR',
  defaultValue: '.codex-artifacts/2026-11-06-release164/ui',
);
const captureKey = ValueKey('qishui-qr164-capture');
void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (captureQr164) {
      await load147IconFonts();
      for (final name in [
        'SodaQA',
        'Microsoft YaHei',
        'Noto Sans SC',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(name)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  Future<void> shot(WidgetTester tester, String name) async {
    if (!captureQr164) return;
    final paint = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    await tester.runAsync(() async {
      final image = await paint.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$qrCaptureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> mount(
    WidgetTester tester,
    FixtureQrGateway gateway, {
    double width = 390,
    double scale = 1,
    bool dark = false,
    DateTime Function()? now,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = theme152(dark).copyWith(
      textTheme: theme152(
        dark,
      ).textTheme.apply(fontFamily: captureQr164 ? 'SodaQA' : null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qishuiQrLoginFactoryProvider.overrideWithValue(
            () => QishuiQrLogin(gateway, now: now),
          ),
        ],
        child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const QishuiQrLoginPage(),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  for (final variant in [
    (390.0, 1.0, false),
    (320.0, 1.8, true),
    (768.0, 1.0, false),
  ]) {
    testWidgets('QR waiting fits ${variant.$1} scale ${variant.$2}', (
      tester,
    ) async {
      final gateway = FixtureQrGateway();
      await mount(
        tester,
        gateway,
        width: variant.$1,
        scale: variant.$2,
        dark: variant.$3,
      );
      expect(find.text('等待抖音扫码'), findsOneWidget);
      expect(find.text('登录原有汽水账号'), findsOneWidget);
      expect(gateway.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await shot(tester, 'waiting-${variant.$1.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(gateway.closes, 1);
    });
  }
  testWidgets('QR security verification is explicit and stops polling', (
    tester,
  ) async {
    final gateway = FixtureQrGateway()
      ..polls.add({
        'error_code': 2046,
        'biz_params': {'key': 'fixture'},
      });
    await mount(tester, gateway);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('完成安全验证'), findsOneWidget);
    expect(gateway.verifications, 0);
    await shot(tester, 'verification');
    await tester.pump(const Duration(seconds: 15));
    expect(gateway.requests, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('expired QR hides the live symbol and offers regeneration', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 6);
    final gateway = FixtureQrGateway();
    await mount(tester, gateway, now: () => now);
    now = now.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('二维码已过期，请重新生成'), findsOneWidget);
    expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
    await shot(tester, 'expired');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
    'late QR creation after leaving does not update a disposed page',
    (tester) async {
      final gate = Completer<void>();
      final gateway = FixtureQrGateway()..beginGate = gate;
      await mount(tester, gateway);
      expect(find.text('正在生成登录二维码…'), findsOneWidget);
      await shot(tester, 'generating');
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(gateway.requests, isEmpty);
    },
  );
}
