import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FramePhase;

import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/glass_render_diagnostics.dart';
import 'package:mesting_music/app/router/app_router.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/experience/presentation/apple_player_controls.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/experience/presentation/beta_now_playing_page.dart';
import 'package:mesting_music/features/experience/presentation/immersive_lyrics.dart';
import 'package:mesting_music/features/experience/presentation/player_queue_panel.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/main.dart' as app;
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fixed, account-free navigation workload for an isolated native profile APK.
/// The build wrapper must verify .beta.benchmark and use --keep-app-running.
/// The same file and generated lyric fixture run on both frozen and new code.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'rapid tabs, lists, player, lyrics and queue',
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
      // This workload explicitly measures 8.33ms and 16.67ms budgets below.
      // Record the library's advisory warning separately from functional failures;
      // it is not an exception in the shipped release (the monitor is debug/profile).
      // All other Flutter errors still reach the normal integration-test binding.
      final originalError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'liquid_glass_widgets' &&
            details.exception.toString() ==
                'Exception: GlassQuality.premium performance budget exceeded') {
          // ignore: avoid_print
          print('MESTING_NAV_BUDGET_WARNING ${details.context}');
        } else {
          originalError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = originalError);
      await _wait(tester, const Duration(seconds: 12));
      expect(find.byKey(const ValueKey('entry-app')), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BetaMusicShell)),
        listen: false,
      );
      const cover = 'assets/images/theme_playlists/shinchan/cover-01.jpg';
      final tracks = List.generate(
        160,
        (i) => Track(
          id: 'isolated121-$i',
          title: '本地测试歌曲 $i',
          artist: '固定测试内容',
          album: '性能采样',
          duration: const Duration(minutes: 4),
          audioAsset: '',
          coverAsset: cover,
          lyricsAsset: 'integration_test/fixtures/native_lyrics.lrc',
        ),
      );
      final owner = container.read(activeLibraryOwnerProvider);
      final db = container.read(appDatabaseProvider);
      // Only the isolated package's own database is populated. Batch inserts keep
      // fixture setup outside the measured windows and never enqueue cloud writes.
      await db.transaction(() async {
        await db.batch((batch) {
          for (var i = 0; i < tracks.length; i++) {
            final track = tracks[i];
            batch.insertAllOnConflictUpdate(db.favoriteTracks, [
              FavoriteTracksCompanion.insert(
                ownerId: Value(owner),
                trackId: track.id,
                trackSnapshot: jsonEncode(track.toJson()),
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            ]);
            batch.insertAllOnConflictUpdate(db.userPlaylistTracks, [
              UserPlaylistTracksCompanion.insert(
                ownerId: Value(owner),
                playlistId: 'isolated121',
                trackId: track.id,
                trackSnapshot: jsonEncode(track.toJson()),
                sortOrder: i,
                addedAt: DateTime(2026),
              ),
            ]);
          }
          batch.insertAllOnConflictUpdate(db.userPlaylists, [
            UserPlaylistsCompanion.insert(
              ownerId: Value(owner),
              id: 'isolated121',
              name: '固定性能测试歌单',
              coverAsset: const Value(cover),
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ]);
        });
      });
      final handler = container.read(audioHandlerProvider);
      final media = tracks
          .take(40)
          .map(
            (track) => MediaItem(
              id: track.id,
              title: track.title,
              artist: track.artist,
              duration: track.duration,
              extras: {
                'coverAsset': cover,
                'source': 'local',
                'lyricsAsset': track.lyricsAsset,
              },
            ),
          )
          .toList();
      handler.queue.add(media);
      handler.mediaItem.add(media.first);
      await _wait(tester, const Duration(seconds: 2));

      await _measure(tester, 'rapid_tabs', () async {
        for (var cycle = 0; cycle < 10; cycle++) {
          for (final index in [2, 3, 0, 1]) {
            tester
                .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
                .onTabSelected(index);
            await _wait(tester, const Duration(milliseconds: 110));
          }
        }
        await _wait(tester, const Duration(milliseconds: 800));
        expect(appRouter.routeInformationProvider.value.uri.path, '/music');
      });

      appRouter.go('/music/library?view=favorites');
      await _wait(tester, const Duration(seconds: 2));
      expect(find.text('本地测试歌曲 0'), findsWidgets);
      await _measure(tester, 'song_list_scroll', () => _scroll(tester, 8));

      appRouter.push('/music/playlists/isolated121');
      await _wait(tester, const Duration(seconds: 2));
      expect(find.text('固定性能测试歌单'), findsWidgets);
      await _measure(tester, 'playlist_scroll', () => _scroll(tester, 8));

      await _measure(tester, 'player_entry_exit', () async {
        for (var cycle = 0; cycle < 8; cycle++) {
          appRouter.push('/player');
          await _wait(tester, const Duration(milliseconds: 190));
          expect(find.byType(BetaNowPlayingPage), findsOneWidget);
          appRouter.pop();
          await _wait(tester, const Duration(milliseconds: 190));
        }
        await _wait(tester, const Duration(milliseconds: 900));
      });
      appRouter.push('/player');
      await _wait(tester, const Duration(seconds: 1));
      await _measure(tester, 'player_lyrics_queue', () async {
        for (var cycle = 0; cycle < 8; cycle++) {
          tester
              .widget<ApplePlayerControls>(find.byType(ApplePlayerControls))
              .onToggleLyrics!();
          await _wait(tester, const Duration(milliseconds: 110));
          tester
              .widget<ApplePlayerControls>(find.byType(ApplePlayerControls))
              .onToggleQueue!();
          await _wait(tester, const Duration(milliseconds: 110));
          tester
              .widget<ApplePlayerControls>(find.byType(ApplePlayerControls))
              .onToggleLyrics!();
          await _wait(tester, const Duration(milliseconds: 110));
        }
        await _wait(tester, const Duration(seconds: 1));
        expect(find.byType(ImmersiveLyrics), findsOneWidget);
      });
      await _measure(tester, 'lyrics_scroll', () => _scroll(tester, 8));
      tester
          .widget<ApplePlayerControls>(find.byType(ApplePlayerControls))
          .onToggleQueue!();
      await _wait(tester, const Duration(milliseconds: 600));
      expect(find.byType(PlayerQueuePanel), findsOneWidget);
      await _measure(tester, 'queue_scroll', () => _scroll(tester, 8));
      // ignore: avoid_print
      print('MESTING_DEVICE_CAPTURE v121-navigation-complete');
      await _wait(tester, const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _wait(WidgetTester tester, Duration duration) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {
    await Future<void>.delayed(const Duration(milliseconds: 8));
    await tester.pump();
  }
}

Future<void> _scroll(WidgetTester tester, int cycles) async {
  final positions = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .map((state) => state.position)
      .where(
        (p) =>
            axisDirectionToAxis(p.axisDirection) == Axis.vertical &&
            p.maxScrollExtent > 100,
      )
      .toList();
  expect(
    positions,
    isNotEmpty,
    reason: 'The actual populated page must scroll.',
  );
  final position = positions.first;
  final target = math.min(position.maxScrollExtent, 1300.0);
  for (var cycle = 0; cycle < cycles; cycle++) {
    for (final offset in [target, 0.0]) {
      final moving = position.animateTo(
        offset,
        duration: const Duration(milliseconds: 120),
        curve: Curves.linear,
      );
      await _wait(tester, const Duration(milliseconds: 160));
      await moving;
    }
  }
}

Future<void> _measure(
  WidgetTester tester,
  String name,
  Future<void> Function() exercise,
) async {
  final samples = <FrameTiming>[];
  final start =
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
  void collect(List<FrameTiming> batch) => samples.addAll(
    batch.where(
      (f) => f.timestampInMicroseconds(FramePhase.vsyncStart) > start,
    ),
  );
  SchedulerBinding.instance.addTimingsCallback(collect);
  GlassRenderDiagnostics.begin();
  try {
    await exercise();
    await _wait(tester, const Duration(milliseconds: 1100));
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    GlassRenderDiagnostics.stop();
  }
  expect(samples, isNotEmpty);
  final builds =
      samples.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
        ..sort();
  final rasters =
      samples.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
        ..sort();
  double percentile(List<double> sorted, double p) =>
      sorted[((sorted.length - 1) * p).round()];
  final counters = <String, int>{};
  for (final row in GlassRenderDiagnostics.report()) {
    for (final metric in GlassRenderMetric.values) {
      counters.update(
        metric.name,
        (old) => old + (row[metric.name] as int? ?? 0),
        ifAbsent: () => row[metric.name] as int? ?? 0,
      );
    }
  }
  // Bound each output record so Android logcat cannot truncate a JSON line.
  // ignore: avoid_print
  print(
    'MESTING_NAV_PERF ${jsonEncode({
      'scene': name,
      'frames': samples.length,
      'buildMs': {
        for (final p in [.5, .95, .99]) '${(p * 100).round()}': percentile(builds, p),
      },
      'rasterMs': {
        for (final p in [.5, .95, .99]) '${(p * 100).round()}': percentile(rasters, p),
      },
      'rasterOver8_33': rasters.where((v) => v > 1000 / 120).length,
      'rasterOver16_67': rasters.where((v) => v > 1000 / 60).length,
    })}',
  );
  // ignore: avoid_print
  print('MESTING_NAV_GLASS ${jsonEncode({'scene': name, ...counters})}');
}
