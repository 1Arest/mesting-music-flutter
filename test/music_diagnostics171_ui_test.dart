import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/settings/presentation/music_network_diagnostics_page.dart';
import 'support/release_152_qa.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initialize151QA);
  final diagnostics = MusicNetworkDiagnostics.shared;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(diagnostics.clear);
  tearDown(() {
    diagnostics.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
  void failure() => diagnostics.record(
    platform: 'qishui',
    operation: MusicNetworkOperation.audio,
    outcome: MusicNetworkOutcome.format,
    phase: MusicDiagnosticPhase.audioDecode,
    nativeStep: MusicNativeAudioStep.cachePath,
    nativeReason: MusicNativeAudioReason.cachePathInvalid,
    family: MusicFailureFamily.format,
  );
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      for (final corrupted in [false, true]) {
        testWidgets('171 diagnostics $dark large=$large corrupted=$corrupted', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          addTearDown(tester.view.reset);
          failure();
          String? copied;
          messenger.setMockMethodCallHandler(SystemChannels.platform, (
            call,
          ) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'Clipboard.getData') {
              return {'text': corrupted ? 'garbled' : copied};
            }
            return null;
          });
          await tester.pumpWidget(
            MaterialApp(
              theme: theme152(dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: capture151Builder(child!),
              ),
              home: const MusicNetworkDiagnosticsPage(),
            ),
          );
          await tester.pump(const Duration(milliseconds: 350));
          await tester.tap(find.text('复制精简记录'));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(jsonDecode(copied!)['complete'], isTrue);
          expect(
            find.text(
              corrupted ? '剪贴板内容核对不一致，请重试复制精简记录。' : '已复制并核对。粘贴后请确认内容末尾完整。',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('私有缓存路径校验'), findsOneWidget);
          await shot151(
            tester,
            '171-diagnostics-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}-${corrupted ? 'mismatch' : 'verified'}',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
  testWidgets(
    'copy readback is bounded and duplicate taps do not overwrite snapshot',
    (tester) async {
      failure();
      final readback = Completer<Object?>();
      var writes = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') writes++;
        if (call.method == 'Clipboard.getData') return readback.future;
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: theme152(false),
          home: const MusicNetworkDiagnosticsPage(),
        ),
      );
      await tester.tap(find.text('复制精简记录'));
      await tester.pump();
      await tester.tap(find.text('复制诊断记录'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 4));
      expect(writes, 1);
      expect(find.text('未能核对剪贴板内容，请重试复制精简记录。'), findsOneWidget);
      readback.complete(null);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
