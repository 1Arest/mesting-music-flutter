import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_run.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/audio_downloads_page.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/settings/presentation/production_diagnostic_driver.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'support/deterministic_audio_player.dart';
import 'support/personal_profile_fixture.dart';
import 'support/test_tracks.dart';

class _Driver implements DiagnosticDriver {
  _Driver(this.scenarios);
  @override
  final List<DiagnosticScenario> scenarios;
  final opened = <String>[];
  final phases = <String>[];
  Future<void> Function(DiagnosticScenario, DiagnosticTicket)? onOpen;
  Future<void> Function(DiagnosticScenario, DiagnosticPhase, DiagnosticTicket)?
  onExercise;
  bool closeFails = false;
  bool restored = false;
  @override
  Future<void> open(
    DiagnosticScenario scenario,
    DiagnosticTicket ticket,
  ) async {
    opened.add(scenario.id);
    await onOpen?.call(scenario, ticket);
  }

  @override
  Future<Map<String, Object>> exercise(
    DiagnosticScenario scenario,
    DiagnosticPhase phase,
    DiagnosticTicket ticket,
  ) async {
    phases.add('${scenario.id}/${phase.name}');
    await onExercise?.call(scenario, phase, ticket);
    return {'verifiedAction': true};
  }

  @override
  Future<void> close() async {
    if (closeFails) throw StateError('close');
  }

  @override
  Future<void> restore(DiagnosticTicket ticket) async {
    ticket.check();
    restored = true;
  }
}

const _first = DiagnosticScenario('common/one', '页面一', null);
const _second = DiagnosticScenario('common/two', '页面二', null);
Map<String, Object> _capture() => {
  'samples': [
    {'buildUs': 1000, 'rasterUs': 19000},
  ],
  'summary': 'frames=1 raster_p99_ms=19.00',
  'displayHz': 120.0,
  'elapsedMs': 20,
  'timingsDrained': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  Future<DiagnosticRunController> controller({bool noFrames = false}) async {
    final directory = await Directory.systemTemp.createTemp('diagnostic124-');
    addTearDown(() => directory.delete(recursive: true));
    final result = DiagnosticRunController(
      DiagnosticRunStore(directory),
      beginCapture: (_, _) {},
      stopCapture: () async {},
      captureReport: noFrames ? () => {'samples': <Object>[]} : _capture,
      pageTimeout: const Duration(milliseconds: 20),
      stageTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(result.dispose);
    return result;
  }

  Future<void> run(
    DiagnosticRunController c,
    DiagnosticDriver d, {
    bool resume = false,
  }) => c.run(
    d,
    displayHz: 120,
    environment: const {'appVersion': '1.0.24'},
    originalPlatform: null,
    originalAccountChoice: 'guest',
    setActive: (_) {},
    resume: resume,
  );

  test(
    'page timeout and close failure do not prevent the next real scenario',
    () async {
      final c = await controller();
      final delayed = Completer<void>();
      var lateActions = 0;
      final d = _Driver([_first, _second])..closeFails = true;
      d.onOpen = (s, t) async {
        if (s == _first) {
          await delayed.future;
          t.check();
          lateActions++;
        }
      };
      await run(c, d);
      delayed.complete();
      await Future<void>.delayed(Duration.zero);
      expect(d.opened, [_first.id, _second.id]);
      expect(lateActions, 0);
      expect(c.records.any((r) => r['reason'] == 'page_timeout'), true);
      expect(c.records.any((r) => r['reason'] == 'page_close_failed'), true);
      expect(
        c.records.where(
          (r) => r['scenario'] == _second.id && r['status'] == 'passed',
        ),
        hasLength(4),
      );
      expect(d.restored, true);
      expect(c.checkpoint['status'], 'completed');
    },
  );

  test(
    'unlogged skip and stage timeout are saved separately and execution continues',
    () async {
      final c = await controller();
      final d = _Driver([
        _first,
        _second,
        const DiagnosticScenario('common/three', '三', null),
      ]);
      d.onOpen = (s, _) async {
        if (s == _first) throw const DiagnosticSkip('platform_not_logged_in');
      };
      d.onExercise = (s, p, _) async {
        if (s == _second && p == DiagnosticPhase.normal) {
          await Completer<void>().future;
        }
      };
      final active = <bool>[];
      await c.run(
        d,
        displayHz: 120,
        environment: const {},
        originalPlatform: 'netease',
        setActive: active.add,
      );
      expect(active, [true, false]);
      expect(c.records.first['status'], 'skipped');
      expect(c.records.first['reason'], 'platform_not_logged_in');
      expect(c.records.any((r) => r['reason'] == 'stage_timeout'), true);
      expect(d.phases.any((s) => s.startsWith('common/three/')), true);
      expect(c.checkpoint['nextScenario'], 3);
    },
  );

  test(
    'stop persists current cursor and resume exports all segments without duplication',
    () async {
      final c = await controller();
      final d = _Driver([_first, _second]);
      d.onExercise = (s, phase, _) async {
        if (s == _first && phase == DiagnosticPhase.fastReverse) c.stop();
      };
      await run(c, d);
      expect(c.checkpoint['status'], 'stopped');
      expect(c.checkpoint['nextScenario'], 0);
      expect(c.checkpoint['nextPhase'], 1);
      final fresh = DiagnosticRunController(
        c.store,
        beginCapture: (_, _) {},
        stopCapture: () async {},
        captureReport: _capture,
      );
      addTearDown(fresh.dispose);
      await fresh.load();
      expect(fresh.resumable, true);
      await run(fresh, _Driver([_first, _second]), resume: true);
      expect(fresh.records, hasLength(8));
      expect(
        fresh.records.map((r) => '${r['scenario']}/${r['phase']}').toSet(),
        hasLength(8),
      );
      final exported =
          jsonDecode(
                await (await fresh.store.export(
                  fresh.checkpoint,
                )).readAsString(),
              )
              as Map;
      expect(exported['segments'], hasLength(8));
      final timing = fresh.records.first['timing'] as Map;
      expect(timing['rasterOverDisplayBudget'], 1);
      expect(timing['rasterOver16_67Ms'], 1);
      expect(fresh.checkpoint['originalAccountChoice'], 'guest');
    },
  );

  test(
    'no frame callbacks cannot be reported as a successful capture',
    () async {
      final c = await controller(noFrames: true);
      await run(c, _Driver([_first]));
      expect(c.records.every((r) => r['status'] == 'failed'), true);
      expect(c.records.every((r) => r['reason'] == 'no_frame_timings'), true);
    },
  );

  test('damaged latest checkpoint recovers its durable backup', () async {
    final c = await controller();
    await run(c, _Driver([_first]));
    final expected = await c.store.load();
    await c.store.save(c.checkpoint);
    await File('${c.store.directory.path}/checkpoint.json').writeAsString('{');
    expect(await c.store.load(), expected);
  });

  test(
    'production inventory contains both players and explicit read-only exclusions',
    () {
      final scenarios = productionDiagnosticScenarios();
      expect(scenarios.map((s) => s.id).toSet(), hasLength(scenarios.length));
      for (final platform in ['netease', 'kugou']) {
        for (final page in [
          'player',
          'lyrics',
          'queue',
          'comments',
          'checkin',
          'tabs',
        ]) {
          expect(scenarios.any((s) => s.id == '$platform/$page'), true);
        }
      }
      expect(scenarios.any((s) => s.id == 'common/downloads@1'), true);
      expect(scenarios.any((s) => s.id == 'kugou/effects@2'), true);
      expect(scenarios.any((s) => s.id == 'excluded/commerce'), true);
      final soda = scenarios.where((s) => s.platform == 'qishui').toList();
      expect(soda.map((s) => s.id), [
        'qishui/recommend',
        'qishui/music',
        'qishui/profile',
        'qishui/history',
        'qishui/playlist',
        'qishui/search',
        'qishui/lyrics',
        'qishui/tabs',
      ]);
      expect(scenarios.last.id, 'qishui/tabs');
    },
  );

  testWidgets(
    'production driver opens real downloads, scrolls, swipes and restores the route',
    (tester) async {
      final dependencies = (await tester.runAsync(() async {
        final handler = MestingAudioHandler(
          tracks: testTracks,
          player: DeterministicAudioPlayer(),
        );
        await handler.replaceQueue(testTracks, autoplay: false);
        final manager = AudioDownloadManager(
          client: MockClient((_) async => http.Response('', 500)),
          resolve: (_) async => '',
          publish: (_, _, _, _) async => '',
          currentOwner: () => 'netease:7001',
          directory: () async => Directory.systemTemp,
          persist: (_) async {},
          restored: [
            for (var i = 0; i < 40; i++)
              AudioDownloadTask(
                id: '$i',
                owner: 'netease:7001',
                track: testTracks.first,
                phase: AudioDownloadPhase.completed,
                uri: 'content://audio/$i',
              ),
          ],
        );
        final fixture = await PersonalProfileFixture.create(
          audioHandler: handler,
          extraOverrides: [
            audioDownloadManagerProvider.overrideWithValue(manager),
          ],
        );
        return (handler, manager, fixture);
      }))!;
      final (handler, manager, fixture) = dependencies;
      final navigator = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: navigator,
        initialLocation: '/music/settings',
        routes: [
          GoRoute(
            path: '/music/settings',
            builder: (_, _) => const Scaffold(body: Text('设置根页')),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildMestingTheme(musicThemePresetById('classic')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final driver = ProductionDiagnosticDriver(
        container: fixture.container,
        router: router,
        navigator: navigator.currentState!,
        originalPlatform: null,
        originalAccountChoice: BetaAccountChoice.guest,
      );
      await _pump(
        tester,
        driver.open(
          const DiagnosticScenario('common/downloads', '下载', null),
          DiagnosticTicket(),
        ),
      );
      expect(find.byType(AudioDownloadsPage), findsOneWidget);
      expect(find.byType(BetaMusicBottomBar), findsOneWidget);
      for (final phase in [
        DiagnosticPhase.normal,
        DiagnosticPhase.fastReverse,
      ]) {
        final actions = await _pump(
          tester,
          driver.exercise(
            const DiagnosticScenario('common/downloads', '下载', null),
            phase,
            DiagnosticTicket(),
          ),
        );
        expect(actions['scrollMotions'], greaterThan(0));
      }
      final pages = await _pump(
        tester,
        driver.exercise(
          const DiagnosticScenario('common/downloads', '下载', null),
          DiagnosticPhase.pages,
          DiagnosticTicket(),
        ),
      );
      expect(pages['verifiedDestinations'], true);
      await _pump(tester, driver.close());
      expect(find.byType(AudioDownloadsPage), findsNothing);
      expect(find.text('设置根页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      manager.dispose();
      await tester.runAsync(() async {
        await fixture.dispose();
        await handler.debugDispose();
      });
    },
  );
}

Future<T> _pump<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  T? result;
  Object? failure;
  StackTrace? failureStack;
  future.then(
    (value) {
      result = value;
      done = true;
    },
    onError: (Object error, StackTrace stack) {
      failure = error;
      failureStack = stack;
      done = true;
    },
  );
  for (var i = 0; i < 160 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    done,
    true,
    reason: 'Production adapter must finish within a bounded viewport action',
  );
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return result as T;
}
