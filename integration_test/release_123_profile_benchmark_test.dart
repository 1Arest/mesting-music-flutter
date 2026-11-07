import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/glass_render_diagnostics.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/experience/presentation/floating_playback_pill.dart';
import 'package:mesting_music/features/experience/presentation/music_library_page.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_scroll_behavior.dart';
import '../test/support/personal_profile_fixture.dart';

/// Synthetic logged-in data, real production library/My widgets and native
/// premium shaders. Never runs with the daily package or accesses its account.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'isolated library to logged-in My native workload',
    (tester) async {
      expect(const bool.fromEnvironment('MESTING_ISOLATED_BENCHMARK'), isTrue);
      await LiquidGlassWidgets.initialize();
      final handler = MestingAudioHandler(tracks: []);
      final fixture = await PersonalProfileFixture.create(
        audioHandler: handler,
      );
      const media = MediaItem(
        id: 'isolated123',
        title: '固定测试歌曲',
        artist: '合成数据',
        extras: {'coverAsset': profileFixtureCover, 'source': 'local'},
      );
      handler.queue.add([media]);
      handler.mediaItem.add(media);
      final router = GoRouter(
        initialLocation: '/music/library',
        routes: [
          ShellRoute(
            builder: (_, state, child) =>
                BetaMusicShell(location: state.uri.path, child: child),
            routes: [
              GoRoute(
                path: '/music/library',
                builder: (_, _) => const Scaffold(body: MusicLibraryPage()),
              ),
              GoRoute(
                path: '/profile',
                builder: (_, _) => const Scaffold(body: BetaPersonalProfile()),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildMestingTheme(musicThemePresetById('classic')),
            scrollBehavior: const BetaScrollBehavior(),
          ),
        ),
      );
      await _wait(tester, const Duration(seconds: 3));
      // The handler finishes its empty initial queue asynchronously. Publish
      // the paused media after that initialization, as production restore does.
      handler.queue.add([media]);
      handler.mediaItem.add(media);
      await _wait(tester, const Duration(seconds: 1));
      expect(find.byType(BetaMusicBottomBar), findsOneWidget);
      expect(find.byType(FloatingPlaybackPill), findsOneWidget);
      final samples = <ui.FrameTiming>[];
      void collect(List<ui.FrameTiming> rows) => samples.addAll(rows);
      SchedulerBinding.instance.addTimingsCallback(collect);
      GlassRenderDiagnostics.begin();
      try {
        for (var cycle = 0; cycle < 12; cycle++) {
          router.go('/music/library');
          await _wait(tester, const Duration(milliseconds: 550));
          final library = find.byType(Scrollable).first;
          await tester.timedDrag(
            library,
            const Offset(0, -220),
            const Duration(milliseconds: 220),
          );
          router.go('/profile');
          await _wait(tester, const Duration(milliseconds: 550));
          expect(find.text('674 首喜欢  ·  5 个歌单'), findsOneWidget);
          expect(find.byType(BetaMusicBottomBar), findsOneWidget);
          expect(find.byType(FloatingPlaybackPill), findsOneWidget);
          for (final ms in [450, 80, 180]) {
            for (final dy in [-570.0, 570.0]) {
              await tester.timedDrag(
                find.byType(CustomScrollView).first,
                Offset(0, dy),
                Duration(milliseconds: ms),
              );
              await _wait(tester, const Duration(milliseconds: 180));
            }
          }
          // Real wall clock lets native snapshot tasks and GPU fences drain.
          await _wait(tester, const Duration(milliseconds: 300));
        }
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(collect);
        GlassRenderDiagnostics.stop();
      }
      expect(samples, isNotEmpty);
      expect(tester.takeException(), isNull);
      double percentile(Iterable<double> input, double p) {
        final values = input.toList()..sort();
        return values[(p * (values.length - 1)).round()];
      }

      final totals = <String, int>{};
      for (final row in GlassRenderDiagnostics.report()) {
        for (final m in GlassRenderMetric.values) {
          totals.update(
            m.name,
            (v) => v + (row[m.name] as int? ?? 0),
            ifAbsent: () => row[m.name] as int? ?? 0,
          );
        }
      }
      final data = <String, Object>{
        'cycles': 12,
        'frames': samples.length,
        'shaderFiltersSupported': ui.ImageFilter.isShaderFilterSupported,
        'glassCounters': totals,
        for (final p in [.5, .95, .99])
          'rasterP${(p * 100).round()}Ms': percentile(
            samples.map((f) => f.rasterDuration.inMicroseconds / 1000),
            p,
          ),
        'over16ms': samples
            .where(
              (f) =>
                  math.max(
                    f.rasterDuration.inMicroseconds,
                    f.buildDuration.inMicroseconds,
                  ) >
                  16667,
            )
            .length,
      };
      // ignore: avoid_print
      print('MESTING_123_NATIVE ${jsonEncode(data)}');
      binding.reportData = data;
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await fixture.dispose();
      await handler.debugDispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _wait(WidgetTester tester, Duration duration) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await tester.pump();
  }
}
