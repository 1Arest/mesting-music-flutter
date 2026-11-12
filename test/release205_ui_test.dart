import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/music_rhythm.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_report_extras.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_report_extras_view.dart';
import 'package:mesting_music/features/player/presentation/player_visual_stages.dart';
import 'package:mesting_music/features/player/presentation/official_vinyl_parts.dart';
import 'package:mesting_music/features/player/presentation/vinyl_disc.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/themes/personal_style.dart';
import 'package:mesting_music/features/themes/personal_style_page.dart';
import 'package:mesting_music/features/themes/profile_effect_picker.dart';
import 'package:mesting_music/features/themes/profile_effect_style.dart';
import 'package:mesting_music/features/themes/progress_outfit_picker.dart';
import 'package:mesting_music/features/themes/style_option_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'song_share_test.dart' show song;
import 'support/personal_profile_fixture.dart';
import 'support/ui_fix_capture.dart';

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });
  for (final spec in [
    (width: 390.0, height: 844.0, scale: 1.0, dark: true),
    (width: 320.0, height: 720.0, scale: 1.6, dark: false),
    (width: 820.0, height: 1100.0, scale: 1.3, dark: false),
  ]) {
    testWidgets('style, effects, vinyl and official report surfaces $spec', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(spec.width, spec.height));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({
        'music_personal_style_v1': '{"frame":"stamp"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final meter = MusicRhythmSampler((_) async => {'available': false});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentTrackProvider.overrideWithValue(
            song(cover: profileFixtureCover),
          ),
          playbackStateProvider.overrideWith(
            (_) => Stream.value(PlaybackState(playing: false)),
          ),
          musicRhythmSamplerProvider.overrideWithValue(meter),
          platformAccountProvider.overrideWith(SyntheticProfileAccount.new),
        ],
      );
      addTearDown(() {
        container.dispose();
        meter.dispose();
      });
      var theme = buildMestingTheme(
        musicThemePresetById(spec.dark ? 'classic-dark' : 'classic'),
      );
      theme = theme.copyWith(
        scaffoldBackgroundColor: theme.colorScheme.surface,
      );
      if (uiFixCaptureDirectory.isNotEmpty) {
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'UiFixCJK'),
        );
      }
      Widget host(Widget child) => UncontrolledProviderScope(
        container: container,
        child: LiquidGlassWidgets.wrap(
          brightnessResolver: Theme.maybeBrightnessOf,
          adaptiveQuality: false,
          child: MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(spec.width, spec.height),
                textScaler: TextScaler.linear(spec.scale),
                disableAnimations: true,
              ),
              child: RepaintBoundary(key: uiFixCaptureKey, child: child),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
      }

      final suffix = '${spec.width.toInt()}-${spec.scale}-${spec.dark}';
      await tester.pumpWidget(host(const PersonalStylePage()));
      await settle();
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(StyleOptionGrid), findsWidgets);
      expect(find.text('专辑封面相框'), findsNothing);
      expect(container.read(personalStyleProvider).frame, CoverFrame.none);
      await captureUiFix(tester, '205-style-$suffix', settleAnimations: false);
      for (final key in [
        'poster-original',
        'keepsake-original',
        'mini-original',
        'atmosphere-off',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(key)),
          220,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 30,
        );
        await settle();
        await captureUiFix(tester, '205-$key-$suffix', settleAnimations: false);
      }
      await tester.tap(find.text('歌词').first);
      await settle();
      final lyricSettings = find.byKey(
        const ValueKey('style-slider-lyricSize'),
      );
      await tester.scrollUntilVisible(
        lyricSettings,
        240,
        scrollable: find
            .descendant(
              of: find.byType(ListView).hitTestable().last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await settle();
      expect(tester.getSize(lyricSettings).width, greaterThan(spec.width * .7));
      await captureUiFix(
        tester,
        '208-lyric-settings-$suffix',
        settleAnimations: false,
      );
      expect(tester.takeException(), isNull);
      await container
          .read(profileEffectProvider.notifier)
          .select(ProfileEffectStyle.aurora);
      await tester.pumpWidget(
        host(
          const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(22),
              child: Column(
                children: [
                  ProgressOutfitPicker(collapsible: true),
                  SizedBox(height: 18),
                  ProfileEffectPicker(),
                ],
              ),
            ),
          ),
        ),
      );
      await settle();
      await captureUiFix(tester, '207-aurora-$suffix', settleAnimations: false);
      expect(find.text('极光音浪'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: spec.width.clamp(0, 400) - 40,
                child: ClassicVinylArtwork(
                  track: song(cover: profileFixtureCover),
                  playing: false,
                ),
              ),
            ),
          ),
        ),
      );
      await settle();
      await captureUiFix(tester, '205-vinyl-$suffix', settleAnimations: false);
      expect(tester.takeException(), isNull);
      const report = OfficialReportExtras(
        achievement: '红心收藏家',
        achievementDetail: '官方返回的合成样本',
        covers: [
          profileFixtureCover,
          profileFixtureCover,
          profileFixtureCover,
          profileFixtureCover,
        ],
        songCount: 163,
        songs: [
          OfficialReportItem(
            title: '合成歌曲',
            detail: '2次 · 收听TOP1',
            cover: profileFixtureCover,
          ),
        ],
        genres: [OfficialReportItem(title: '流行', percent: 57)],
        languages: [
          OfficialReportItem(title: '华语', percent: 74),
          OfficialReportItem(title: '英语', percent: 30),
        ],
      );
      await tester.pumpWidget(
        host(
          const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(22),
              child: OfficialReportExtrasView(
                data: report,
                period: '2026-11-01 – 2026-11-07',
                weekly: true,
              ),
            ),
          ),
        ),
      );
      await settle();
      await captureUiFix(tester, '205-report-$suffix', settleAnimations: false);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -650),
      );
      await settle();
      await captureUiFix(
        tester,
        '205-report-stats-$suffix',
        settleAnimations: false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'vinyl pause preserves its angle and resumes while the arm changes state',
    (tester) async {
      Widget host(bool playing) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 320,
              child: ClassicVinylArtwork(
                track: song(cover: profileFixtureCover),
                playing: playing,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(true));
      await tester.pump(const Duration(milliseconds: 900));
      final angle = tester
          .widget<RotationTransition>(
            find.descendant(
              of: find.byType(VinylDisc),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns
          .value;
      expect(angle, greaterThan(0));
      await tester.pumpWidget(host(false));
      await tester.pump(const Duration(seconds: 1));
      final paused = tester
          .widget<RotationTransition>(
            find.descendant(
              of: find.byType(VinylDisc),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns
          .value;
      expect(paused, angle);
      expect(
        tester
            .widget<AnimatedRotation>(
              find.descendant(
                of: find.byType(OfficialVinylTonearm),
                matching: find.byType(AnimatedRotation),
              ),
            )
            .turns,
        officialTonearmPauseTurns,
      );
      await tester.pumpWidget(host(true));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<RotationTransition>(
              find.descendant(
                of: find.byType(VinylDisc),
                matching: find.byType(RotationTransition),
              ),
            )
            .turns
            .value,
        greaterThan(paused),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
