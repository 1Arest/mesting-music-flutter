import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';
import 'package:mesting_music/features/player/presentation/music_rhythm_artwork.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/music_rhythm.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/app_update/presentation/beta_app_update_sheet.dart';
import 'package:mesting_music/features/settings/presentation/playback_preferences_page.dart';
import 'package:mesting_music/features/themes/theme_gallery_page.dart';
import 'package:mesting_music/features/themes/profile_effect_picker.dart';
import 'package:mesting_music/features/themes/profile_effect_style.dart';
import 'package:mesting_music/features/music_platform/default_playback_quality.dart';
import 'package:mesting_music/features/music_platform/presentation/rhythm_platform_avatar.dart';
import 'package:mesting_music/features/music_platform/netease/netease_official_ranking_page.dart';
import 'support/ui_fix_capture.dart';
import 'support/personal_profile_fixture.dart';

class _Handler implements MestingAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Update extends AppUpdateController {
  @override
  AppUpdateState build() => AppUpdateState(
    phase: AppUpdatePhase.downloading,
    currentVersion: const AppVersionInfo(
      packageName: 'com.mesting.music',
      versionName: '1.0.92',
      versionCode: 113,
    ),
    receivedBytes: 8000000,
    totalBytes: 120000000,
    manifest: AppUpdateManifest(
      packageName: 'com.mesting.music',
      versionName: '1.0.93',
      versionCode: 114,
      minimumVersionCode: 1,
      mandatory: false,
      title: '发现新版本',
      releaseNotes: List.generate(12, (i) => '本次更新改善装扮、设置与网易云内容展示，更新说明可以滚动阅读。'),
      apkUrl: Uri.parse('https://example.test/music.apk'),
      sha256: 'a' * 64,
      sizeBytes: 120000000,
      publishedAt: DateTime(2026),
    ),
  );
}

ThemeData capture193Theme(bool dark) {
  final base = buildMestingTheme(
    musicThemePresetById(dark ? 'classic-dark' : 'classic'),
  );
  if (uiFixCaptureDirectory.isEmpty) return base;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'UiFixCJK'),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
        fontFamily: 'UiFixCJK',
      ),
      subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
        fontFamily: 'UiFixCJK',
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });
  for (final spec in [
    (width: 390.0, scale: 1.0, dark: true),
    (width: 320.0, scale: 1.6, dark: false),
    (width: 820.0, scale: 1.3, dark: false),
  ]) {
    testWidgets(
      'fixed update actions, preview gallery and glass selectors $spec',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(spec.width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            platformAccountProvider.overrideWith(SyntheticProfileAccount.new),
            appUpdateControllerProvider.overrideWith(_Update.new),
            audioHandlerProvider.overrideWithValue(_Handler()),
            playbackOrderProvider.overrideWith(
              (ref) => Stream.value(const PlaybackOrder()),
            ),
          ],
        );
        addTearDown(container.dispose);
        Future<void> mount(Widget child) async {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: capture193Theme(spec.dark),
                builder: (context, child) => RepaintBoundary(
                  key: uiFixCaptureKey,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(spec.scale),
                      disableAnimations: true,
                    ),
                    child: child!,
                  ),
                ),
                home: Scaffold(
                  backgroundColor: spec.dark
                      ? const Color(0xFF121316)
                      : Colors.white,
                  body: child,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await mount(
          const Align(
            alignment: Alignment.bottomCenter,
            child: BetaAppUpdateSheet(),
          ),
        );
        final primary = find.byKey(const ValueKey('app-update-primary'));
        final before = tester.getRect(primary);
        final progress = find.byKey(const ValueKey('app-update-progress'));
        final progressBefore = tester.getRect(progress);
        expect(progressBefore.bottom, lessThan(before.top));
        await tester.drag(
          find.byKey(const ValueKey('app-update-notes-scroll')),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(primary), before);
        expect(tester.getRect(progress), progressBefore);
        expect(before.bottom, lessThanOrEqualTo(900));
        expect(find.text('查看此次更新'), findsNothing);
        expect(tester.takeException(), isNull);
        await captureUiFix(tester, '193-update-${spec.width}-${spec.scale}');
        await mount(const ThemeGalleryPage());
        expect(find.text('播放器样式'), findsOneWidget);
        expect(find.text('选择角色'), findsNothing);
        await captureUiFix(
          tester,
          '199-dress-gallery-${spec.width}-${spec.scale}',
        );
        final catalog = find.byKey(const ValueKey('progress-outfit-catalog'));
        final gallery = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(catalog, 300, scrollable: gallery);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(catalog), alignment: .42);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('progress-outfit-preview')),
          findsOneWidget,
        );
        await tester.tap(catalog);
        await tester.pumpAndSettle();
        expect(find.text('选择角色'), findsOneWidget);
        await Scrollable.ensureVisible(tester.element(catalog), alignment: .42);
        await tester.tap(catalog);
        await tester.pumpAndSettle();
        expect(find.text('选择角色'), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('profile-effect-preview')),
          220,
          scrollable: gallery,
        );
        expect(find.byType(ProfileEffectPicker), findsOneWidget);
        final orbit = find.byKey(const ValueKey('profile-effect-orbit'));
        await tester.ensureVisible(orbit);
        await tester.tap(orbit);
        await tester.pumpAndSettle();
        expect(container.read(profileEffectProvider), ProfileEffectStyle.orbit);
        expect(tester.takeException(), isNull);
        await captureUiFix(
          tester,
          '199-profile-preview-${spec.width}-${spec.scale}',
        );
        await mount(const PlaybackPreferencesPage());
        expect(find.text('最高可用音质（自动）'), findsWidgets);
        expect(tester.takeException(), isNull);
        final quality = find.byKey(const ValueKey('playback-choice-默认音质'));
        await tester.ensureVisible(quality);
        await tester.tap(quality);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('beta13-glass-menu-surface')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        await captureUiFix(
          tester,
          '199-quality-menu-${spec.width}-${spec.scale}',
        );
        final last = DefaultPlaybackQuality.options(TrackSource.netease).last;
        final row = find.text(last.label);
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(
          container.read(defaultPlaybackQualityProvider)[TrackSource.netease],
          last.code,
        );
        final platform = find.byKey(const ValueKey('playback-choice-音乐平台'));
        // The expanded settings page can lazily dispose the earlier selector
        // after the quality menu scrolls its trigger into view.
        await tester.scrollUntilVisible(
          platform,
          -300,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(platform);
        await tester.tap(platform);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('beta13-glass-menu-surface')),
          findsOneWidget,
        );
        await tester.tap(find.text('酷狗'));
        await tester.pumpAndSettle();
        expect(find.text('最高可用音质（自动）'), findsOneWidget);
        expect(
          container.read(defaultPlaybackQualityProvider)[TrackSource.netease],
          last.code,
        );
        await mount(
          Center(
            child: SizedBox.square(
              dimension: spec.width > 500 ? 400 : spec.width - 40,
              child: const MusicRhythmArtwork(
                preview: true,
                track: Track(
                  id: 'preview',
                  title: '合成预览',
                  artist: '',
                  album: '',
                  duration: Duration.zero,
                  audioAsset: '',
                  lyricsAsset: '',
                  coverAsset: profileFixtureCover,
                ),
              ),
            ),
          ),
        );
        await captureUiFix(
          tester,
          '199-player-ring-${spec.width}-${spec.scale}',
        );
      },
    );
  }
  testWidgets(
    'small avatar shares audio choice and stops on background, offscreen and reduced motion',
    (tester) async {
      SharedPreferences.setMockInitialValues({'profile_effect_193': 'rhythm'});
      final prefs = await SharedPreferences.getInstance();
      final calls = <bool>[];
      final meter = MusicRhythmSampler((enabled) async {
        calls.add(enabled);
        return {'available': enabled, 'rms': .2, 'peak': .4};
      });
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          musicRhythmSamplerProvider.overrideWithValue(meter),
          playbackStateProvider.overrideWith(
            (ref) => Stream.value(
              PlaybackState(
                playing: true,
                processingState: AudioProcessingState.ready,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  const Center(child: RhythmPlatformAvatar(url: '', size: 42)),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(calls, contains(true));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls.last, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(calls.last, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      meter.dispose();
      await tester.pump();
    },
  );
  testWidgets('retained hidden surface detaches shared repaint subscription', (
    tester,
  ) async {
    var visibleBuilds = 0, hiddenBuilds = 0;
    final meter = MusicRhythmSampler(
      (enabled) async => {'available': enabled, 'rms': .1},
    );
    final container = ProviderContainer(
      overrides: [
        musicRhythmSamplerProvider.overrideWithValue(meter),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(
            PlaybackState(
              playing: true,
              processingState: AudioProcessingState.ready,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                BetaTabVisibility(
                  visible: true,
                  child: MusicRhythmSurface(
                    builder: (c, frame) {
                      visibleBuilds++;
                      return const SizedBox(height: 40);
                    },
                  ),
                ),
                BetaTabVisibility(
                  visible: false,
                  child: MusicRhythmSurface(
                    builder: (c, frame) {
                      hiddenBuilds++;
                      return const SizedBox(height: 40);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    final visible = visibleBuilds, hidden = hiddenBuilds;
    meter.value = const MusicRhythmFrame(level: .7, peak: .9, available: true);
    await tester.pump();
    expect(visibleBuilds, greaterThan(visible));
    expect(hiddenBuilds, hidden);
    await tester.pumpWidget(const SizedBox());
    meter.dispose();
    await tester.pump();
  });
  testWidgets(
    'official ranking entry changes period without leaking previous results',
    (tester) async {
      final fixture = await PersonalProfileFixture.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await fixture.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: const MaterialApp(
            home: Scaffold(body: NeteaseOfficialRankingPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('最近一周'), findsOneWidget);
      expect(find.text('累计排行'), findsOneWidget);
      await tester.tap(find.text('累计排行'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
