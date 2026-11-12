import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/music_rhythm.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/themes/profile_effect_style.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'support/personal_profile_fixture.dart';
import 'support/ui_fix_capture.dart';

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    await initializeUiFixCapture();
  });
  for (final style in [
    ProfileEffectStyle.petals,
    ProfileEffectStyle.rhythm,
    ProfileEffectStyle.orbit,
    ProfileEffectStyle.fireflies,
  ]) {
    testWidgets('profile ${style.name} paints and retains account controls', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final meter = MusicRhythmSampler(
        (enabled) async => {'available': enabled, 'rms': .25, 'peak': .65},
      );
      final fixture = await PersonalProfileFixture.create(
        extraOverrides: [
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
      await fixture.container
          .read(profileEffectProvider.notifier)
          .select(style);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await fixture.dispose();
        meter.dispose();
      });
      var theme = buildMestingTheme(musicThemePresetById('classic-dark'));
      if (uiFixCaptureDirectory.isNotEmpty) {
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'UiFixCJK'),
          listTileTheme: theme.listTileTheme.copyWith(
            titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
              fontFamily: 'UiFixCJK',
            ),
            subtitleTextStyle: theme.listTileTheme.subtitleTextStyle?.copyWith(
              fontFamily: 'UiFixCJK',
            ),
          ),
        );
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: uiFixCaptureKey,
              child: const Scaffold(body: BetaPersonalProfile()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('固定测试账号'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is BetaGlassButton &&
              widget.label == '设置' &&
              widget.onPressed != null,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // Pause clocks for the capture. The live ring receives its measured host
      // fixture first; image output is explicitly host-only visual evidence.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await captureUiFix(tester, '193-profile-${style.name}');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
