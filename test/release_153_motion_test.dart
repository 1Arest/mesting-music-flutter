import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/auth/presentation/beta_companion_stage.dart';

void main() {
  testWidgets(
    'six-second character loop sleeps in static pauses and stops when covered',
    (tester) async {
      Future<void> mount(bool enabled, {bool reduced = false}) =>
          tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                  enabled: enabled,
                  child: const Scaffold(body: BetaCompanionStage(height: 238)),
                ),
              ),
            ),
          );
      await mount(true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, false);
      var scheduledFrames = 0;
      // Sample at 120 Hz; unlike a permanently repeating controller, the idle
      // intervals must not request a new frame on every display refresh.
      for (var i = 0; i < 720; i++) {
        if (tester.binding.hasScheduledFrame) scheduledFrames++;
        await tester.pump(const Duration(microseconds: 8333));
      }
      expect(scheduledFrames, greaterThan(170));
      expect(scheduledFrames, lessThan(230));
      final output = Directory('.codex-artifacts/2026-11-04-release153')
        ..createSync(recursive: true);
      File('${output.path}/welcome-frame-scheduling.json').writeAsStringSync(
        jsonEncode({
          'sampleDisplayHz': 120,
          'sampleIntervals': 720,
          'scheduledFrames': scheduledFrames,
          'priorContinuousControllerFrameDemand': 720,
          'physicalGpuMeasured': false,
        }),
      );
      await mount(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      expect(tester.binding.hasScheduledFrame, false);
      await mount(true, reduced: true);
      await tester.pump(const Duration(seconds: 8));
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'tap greeting still animates, finishes and returns to scheduled loop',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BetaCompanionStage(height: 238)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('beta21-companions-stage')));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, true);
      for (var i = 0; i < 125; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
