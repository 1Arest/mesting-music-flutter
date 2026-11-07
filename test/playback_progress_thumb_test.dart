import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/player/presentation/ip_progress_decoration.dart';
import 'package:mesting_music/features/player/presentation/playback_controls.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('IP progress characters replace the classic slider thumb', () {
    expect(usesClassicProgressThumb(MusicThemeIp.classic), isTrue);
    expect(usesClassicProgressThumb(MusicThemeIp.shinchan), isFalse);
    expect(usesClassicProgressThumb(MusicThemeIp.helloKitty), isFalse);
    expect(usesClassicProgressThumb(MusicThemeIp.kuromi), isFalse);
  });

  testWidgets('IP settings install their themed rail and character companion', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'music_progress_style': 'helloKitty',
      'music_progress_character': 'helloKitty',
    });
    final preferences = await SharedPreferences.getInstance();
    final handler = _RecordingHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(handler),
          positionProvider.overrideWith(
            (_) => Stream.value(const Duration(seconds: 25)),
          ),
          durationProvider.overrideWith(
            (_) => Stream<Duration?>.value(const Duration(seconds: 100)),
          ),
          playbackStateProvider.overrideWith(
            (_) => Stream.value(
              PlaybackState(processingState: AudioProcessingState.ready),
            ),
          ),
          playbackModeProvider.overrideWith(
            (_) => Stream.value(PlaybackMode.list),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlaybackControls(immersive: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final slider = find.byKey(const ValueKey('playback-seek-slider'));
    final sliderTheme = tester.widget<SliderTheme>(
      find.ancestor(of: slider, matching: find.byType(SliderTheme)),
    );
    expect(sliderTheme.data.trackHeight, ipProgressTrackHeight);
    expect(sliderTheme.data.trackShape, isA<IpProgressTrackShape>());
    expect(
      find.byKey(const ValueKey('ip-progress-companion-helloKitty')),
      findsOneWidget,
    );
    final leadingDot = find.byKey(
      const ValueKey('ip-progress-leading-dot-helloKitty'),
    );
    expect(leadingDot, findsNothing);
    final head = find.byKey(const ValueKey('hello-kitty-progress-character'));
    expect(tester.getSize(head), const Size(24, 24));
    expect(
      tester.getCenter(head).dy,
      closeTo(tester.getCenter(slider).dy, .01),
    );
  });

  testWidgets('shared seek bar has a 48dp hit target and keeps local scrub', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final positions = StreamController<Duration>.broadcast();
    addTearDown(positions.close);
    final handler = _RecordingHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(handler),
          positionProvider.overrideWith((_) => positions.stream),
          durationProvider.overrideWith(
            (_) => Stream<Duration?>.value(const Duration(seconds: 100)),
          ),
          playbackStateProvider.overrideWith(
            (_) => Stream.value(
              PlaybackState(processingState: AudioProcessingState.ready),
            ),
          ),
          playbackModeProvider.overrideWith(
            (_) => Stream.value(PlaybackMode.list),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlaybackControls(immersive: true)),
        ),
      ),
    );
    positions.add(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump();

    expect(find.text('0:10'), findsNothing);
    expect(find.text('1:40'), findsOneWidget);
    expect(find.text('高音质'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('playback-seek-touch-target')))
          .height,
      48,
    );
    final sliderFinder = find.byKey(const ValueKey('playback-seek-slider'));
    final rect = tester.getRect(sliderFinder);
    await tester.tapAt(Offset(rect.left + rect.width * .6, rect.center.dy));
    await tester.pump();
    expect(handler.seeks, hasLength(1));
    expect(handler.seeks.single.inSeconds, inInclusiveRange(50, 70));
    handler.seeks.clear();
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * .25, rect.center.dy + 12),
    );
    await gesture.moveTo(Offset(rect.left + rect.width * .75, rect.center.dy));
    positions.add(const Duration(seconds: 5));
    await tester.pump();
    expect(tester.widget<Slider>(sliderFinder).value, greaterThan(60 * 1000));
    await gesture.up();
    await tester.pump();

    expect(handler.seeks, hasLength(1));
    expect(handler.seeks.single.inSeconds, inInclusiveRange(65, 85));

    positions.add(const Duration(seconds: 150));
    await tester.pump();
    expect(tester.widget<Slider>(sliderFinder).value, 100 * 1000);
    positions.add(const Duration(seconds: -5));
    await tester.pump();
    expect(tester.widget<Slider>(sliderFinder).value, 0);
  });

  testWidgets('buffering media uses an accessible audio pulse loader', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final handler = _RecordingHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(handler),
          positionProvider.overrideWith(
            (_) => Stream.value(const Duration(seconds: 30)),
          ),
          durationProvider.overrideWith((_) => Stream.value(Duration.zero)),
          playbackStateProvider.overrideWith(
            (_) => Stream.value(
              PlaybackState(processingState: AudioProcessingState.buffering),
            ),
          ),
          playbackModeProvider.overrideWith(
            (_) => Stream.value(PlaybackMode.list),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlaybackControls(immersive: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('playback-buffering-progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('playback-buffering-pulse')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('正在缓冲音乐'), findsOneWidget);
    expect(find.byKey(const ValueKey('playback-seek-slider')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('正在缓冲'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    expect(find.byKey(const ValueKey('playback-primary-icon')), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('playback-primary-control')),
          )
          .onTap,
      isNull,
    );
    expect(handler.seeks, isEmpty);
  });

  testWidgets('unavailable media is not presented as a zero-length song', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final handler = _RecordingHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(handler),
          positionProvider.overrideWith((_) => Stream.value(Duration.zero)),
          durationProvider.overrideWith((_) => Stream<Duration?>.value(null)),
          playbackStateProvider.overrideWith(
            (_) => Stream.value(
              PlaybackState(
                processingState: AudioProcessingState.error,
                errorMessage: '当前音源不可播放，请切换歌曲后重试',
              ),
            ),
          ),
          playbackModeProvider.overrideWith(
            (_) => Stream.value(PlaybackMode.list),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlaybackControls(immersive: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('playback-source-unavailable-label')),
      findsOneWidget,
    );
    expect(find.text('--:--'), findsOneWidget);
    expect(find.text('正在缓冲'), findsNothing);
  });

  testWidgets(
    'lyrics controls restore elapsed time without changing record view',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final handler = _RecordingHandler();

      Widget controls({required bool showElapsed}) {
        return ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            audioHandlerProvider.overrideWithValue(handler),
            positionProvider.overrideWith(
              (_) => Stream.value(const Duration(seconds: 14)),
            ),
            durationProvider.overrideWith(
              (_) => Stream<Duration?>.value(const Duration(minutes: 3)),
            ),
            playbackStateProvider.overrideWith(
              (_) => Stream.value(
                PlaybackState(processingState: AudioProcessingState.ready),
              ),
            ),
            playbackModeProvider.overrideWith(
              (_) => Stream.value(PlaybackMode.list),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PlaybackControls(immersive: true, showElapsed: showElapsed),
            ),
          ),
        );
      }

      await tester.pumpWidget(controls(showElapsed: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('playback-elapsed-time')), findsNothing);
      expect(find.text('0:14'), findsNothing);

      await tester.pumpWidget(controls(showElapsed: true));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('playback-elapsed-time')),
        findsOneWidget,
      );
      expect(find.text('0:14'), findsOneWidget);
      expect(find.text('3:00'), findsOneWidget);
    },
  );
}

class _RecordingHandler extends MestingAudioHandler {
  _RecordingHandler() : super(tracks: const []);

  final seeks = <Duration>[];

  @override
  Future<void> seek(Duration position, {bool Function()? togetherGuard}) async {
    if (togetherGuard?.call() == false) return;
    seeks.add(position);
  }
}
