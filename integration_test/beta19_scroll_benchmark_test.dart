import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/glass_render_diagnostics.dart';
import 'package:mesting_music/app/router/app_router.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/experience/presentation/floating_playback_pill.dart';
import 'package:mesting_music/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// Run only in the isolated com.mesting.music.beta.benchmark package, with
/// --keep-app-running. Both before/after binaries use this identical harness.
/// Preferences are memory-only and the paused media fixture never opens audio.
/// This measures real production UI/Impeller, not authentication or playback.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'isolated production scroll and capsule benchmark',
    (tester) async {
      expect(const bool.fromEnvironment('MESTING_ISOLATED_BENCHMARK'), isTrue);
      SharedPreferences.setMockInitialValues({
        'beta_active_account_v2': 'guest',
        'mesting_first_launch_auth_completed_v1': true,
        'mesting_disclaimer_accepted_v1': true,
        'mesting_disclaimer_read_v1': true,
        'mesting_user_agreement_accepted_v1': true,
        'mesting_privacy_policy_accepted_v1': true,
        'mesting_legal_documents_read_v1': true,
        'beta12_startup_style': 'classic',
        'beta19_static_startup_migrated': true,
      });
      await app.main();
      await _wait(tester, const Duration(seconds: 12));
      expect(find.byKey(const ValueKey('entry-app')), findsOneWidget);
      expect(find.byType(BetaMusicShell), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BetaMusicShell)),
        listen: false,
      );
      final handler = container.read(audioHandlerProvider);
      const media = MediaItem(
        id: 'isolated-paused-glass-benchmark',
        title: '玻璃性能测试',
        artist: '静止封面 · 不播放音频',
        duration: Duration(minutes: 3),
        extras: {
          'coverAsset': 'assets/images/theme_playlists/shinchan/cover-01.jpg',
          'source': 'local',
        },
      );
      handler.queue.add(const [media]);
      handler.mediaItem.add(media);
      appRouter.go('/music/recommend');
      await _wait(tester, const Duration(seconds: 5));
      expect(
        find.byKey(const ValueKey('beta6-official-play-pill')),
        findsOneWidget,
      );

      final shell = tester.getRect(find.byType(BetaMusicShell));
      final positions = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byType(BetaMusicShell),
              matching: find.byType(Scrollable),
            ),
          )
          .map((state) => state.position)
          .where(
            (p) =>
                axisDirectionToAxis(p.axisDirection) == Axis.vertical &&
                p.maxScrollExtent > 100,
          )
          .toList();
      expect(positions, isNotEmpty);
      final position = positions.first;
      final destination = math.min(
        position.maxScrollExtent,
        shell.height * .60,
      );
      Future<void> moveTo(double offset, {required bool compact}) async {
        // Drive the production ScrollPosition with real wall-clock vsync. This
        // avoids gesture/fling variability while retaining scroll notifications,
        // the actual raster work and the complete native capsule transition.
        final motion = position.animateTo(
          offset,
          duration: const Duration(milliseconds: 360),
          curve: Curves.linear,
        );
        await _wait(tester, const Duration(milliseconds: 820));
        await motion;
        expect(
          tester
              .widget<FloatingPlaybackPill>(find.byType(FloatingPlaybackPill))
              .compact,
          compact,
        );
        expect((position.pixels - offset).abs(), lessThan(1));
      }

      Future<void> up() => moveTo(destination, compact: true);
      Future<void> down() => moveTo(0, compact: false);
      await down();

      // Record actual visible states outside the measured interval. A mounted
      // home hidden behind entry UI, or a missing capsule, must fail this test.
      await _capture(tester, shell, 'benchmark-expanded');
      await up();
      await _capture(tester, shell, 'benchmark-compact');
      await down();
      await _wait(tester, const Duration(seconds: 1));
      final samples = <FrameTiming>[];
      void collect(List<FrameTiming> batch) => samples.addAll(batch);
      SchedulerBinding.instance.addTimingsCallback(collect);
      GlassRenderDiagnostics.begin();
      try {
        for (var cycle = 0; cycle < 8; cycle++) {
          await up();
          await down();
        }
        await _wait(tester, const Duration(milliseconds: 250));
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(collect);
        GlassRenderDiagnostics.stop();
      }
      expect(samples, isNotEmpty, reason: 'Native timing collection must run.');
      final glassTotals = <String, int>{};
      for (final row in GlassRenderDiagnostics.report()) {
        for (final metric in GlassRenderMetric.values) {
          final count = row[metric.name] as int? ?? 0;
          glassTotals.update(
            metric.name,
            (old) => old + count,
            ifAbsent: () => count,
          );
        }
      }
      double percentile(List<double> values, double p) {
        values.sort();
        return values[(p * (values.length - 1)).round()];
      }

      final build = [
        for (final f in samples) f.buildDuration.inMicroseconds / 1000,
      ];
      final raster = [
        for (final f in samples) f.rasterDuration.inMicroseconds / 1000,
      ];
      final durations = [
        for (final f in samples)
          math.max(
                f.buildDuration.inMicroseconds,
                f.rasterDuration.inMicroseconds,
              ) /
              1000,
      ];
      final result = {
        'frames': samples.length,
        'glassPaintCounters': glassTotals,
        'buildMs': {
          for (final p in [.5, .95, .99])
            '${(p * 100).round()}': percentile(build, p),
        },
        'rasterMs': {
          for (final p in [.5, .95, .99])
            '${(p * 100).round()}': percentile(raster, p),
        },
        'over8_33ms': durations.where((t) => t > 1000 / 120).length,
        'over16_67ms': durations.where((t) => t > 1000 / 60).length,
        'fixture':
            'isolated guest, paused asset cover, controlled 360ms scroll, visible gate and both capsule states asserted',
      };
      // ignore: avoid_print
      print(
        'MESTING_DEVICE_PERF home_scroll_and_capsule ${jsonEncode(result)}',
      );
      // Anonymous bounded samples explain whether rebuilds follow real shape
      // changes or only floating-point transforms; never a visual FPS claim.
      // ignore: avoid_print
      for (final sample in GlassRenderDiagnostics.matteSamples()) {
        // ignore: avoid_print
        print('MESTING_MATTE_SAMPLE ${jsonEncode(sample)}');
      }
      await _capture(tester, shell, 'benchmark-after');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _wait(WidgetTester tester, Duration duration) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await tester.pump();
  }
}

Future<void> _capture(WidgetTester tester, Rect rect, String name) async {
  final scale = tester.view.devicePixelRatio;
  // ignore: avoid_print
  print(
    'MESTING_DEVICE_CAPTURE $name ${jsonEncode({'left': rect.left * scale, 'top': rect.top * scale, 'width': rect.width * scale, 'height': rect.height * scale})}',
  );
  await _wait(tester, const Duration(milliseconds: 900));
}
