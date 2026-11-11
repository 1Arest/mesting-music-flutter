import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/core/audio/audio_output_controller.dart';
import 'package:mesting_music/core/audio/media_volume_controller.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/features/queue/presentation/playback_mode_button.dart';
import 'package:mesting_music/features/experience/presentation/player_output_dialog.dart';
import 'package:mesting_music/features/experience/presentation/apple_output_volume_slider.dart';
import 'package:mesting_music/features/experience/presentation/player_queue_panel.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

const _track = Track(
  id: 'fixture',
  title: '小半',
  artist: '陈粒',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: 'assets/fixture.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    final folder = await Directory.systemTemp.createTemp('mesting_beta17_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => folder.path,
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await folder.delete(recursive: true);
    });
  });

  testWidgets(
    'one queue entry selects and announces exactly four playback modes',
    (tester) async {
      final handler = (await tester.runAsync(() async {
        final value = MestingAudioHandler(
          tracks: [],
          player: DeterministicAudioPlayer(),
        );
        await value.replaceQueue([_track], autoplay: false);
        return value;
      }))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            audioHandlerProvider.overrideWithValue(handler),
          ],
          child: const MaterialApp(
            home: Scaffold(
              backgroundColor: Color(0xFF263C50),
              body: PlayerQueuePanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('queue-playback-mode'));
      expect(find.byKey(const ValueKey('player-repeat')), findsNothing);
      expect(find.byKey(const ValueKey('player-shuffle')), findsNothing);
      expect(find.byKey(const ValueKey('queue-random-upcoming')), findsNothing);
      expect(handler.playbackMode, PlaybackMode.sequential);
      for (final mode in [
        PlaybackMode.list,
        PlaybackMode.single,
        PlaybackMode.random,
        PlaybackMode.sequential,
      ]) {
        await tester.tap(picker);
        await tester.pumpAndSettle();
        for (final option in PlaybackMode.values) {
          expect(
            find.byKey(ValueKey('queue-mode-${option.name}')),
            findsOneWidget,
          );
        }
        await tester.tap(find.byKey(ValueKey('queue-mode-${mode.name}')));
        await tester.pumpAndSettle();
        expect(handler.playbackMode, mode);
        expect(find.text('已切换为${mode.label}'), findsOneWidget);
        expect(
          tester
              .widget<Icon>(
                find.descendant(of: picker, matching: find.byType(Icon)).first,
              )
              .icon,
          queueModeIcon(mode),
        );
      }
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(handler.debugDispose);
    },
  );

  testWidgets(
    'device card follows route events and keeps Beta selection in its glass card',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var chooses = 0, volume = .4;
      MockStreamHandlerEventSink? routeEvents;
      messenger.setMockMethodCallHandler(AudioOutputController.methods, (
        call,
      ) async {
        if (call.method == 'choose') {
          chooses++;
          return true;
        }
        return {
          'name': 'vivo TWS 5',
          'kind': 'headphones',
          'available': true,
          'routes': [
            {
              'id': 'earbuds',
              'name': 'vivo TWS 5',
              'kind': 'headphones',
              'selected': true,
              'selectable': false,
            },
          ],
        };
      });
      messenger.setMockStreamHandler(
        AudioOutputController.events,
        MockStreamHandler.inline(
          onListen: (_, events) {
            routeEvents = events;
          },
        ),
      );
      messenger.setMockMethodCallHandler(MediaVolumeController.methods, (
        call,
      ) async {
        if (call.method == 'setVolume') {
          volume = (call.arguments as Map)['value'] as double;
        }
        return volume;
      });
      messenger.setMockStreamHandler(
        MediaVolumeController.events,
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            currentTrackProvider.overrideWithValue(_track),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showPlayerOutputDialog(context, ref),
                  child: const Text('设备'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('设备'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('apple-output-picker')), findsOneWidget);
      expect(find.text('vivo TWS 5'), findsOneWidget);
      expect(chooses, 0);
      routeEvents!.success({
        'name': '通勤耳机',
        'kind': 'headphones',
        'available': true,
        'routes': [
          {
            'id': 'earbuds',
            'name': '通勤耳机',
            'kind': 'headphones',
            'selected': true,
            'selectable': false,
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('通勤耳机'), findsOneWidget);
      final slider = tester.widget<AppleOutputVolumeSlider>(
        find.byKey(const ValueKey('output-volume-slider')),
      );
      slider.onChanged!(.8);
      await tester.pump();
      slider.onChangeEnd?.call(.8);
      await tester.pump();
      expect(volume, .8);
      if (DistributionChannel.isBeta) {
        expect(chooses, 0);
        expect(find.text('播放设备'), findsOneWidget);
        expect(find.text('切换设备'), findsNothing);
        expect(find.text('系统设备管理'), findsNothing);
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
      } else {
        await tester.tap(
          find.byKey(const ValueKey('output-open-system-picker')),
        );
        await tester.pumpAndSettle();
      }
      expect(chooses, DistributionChannel.isBeta ? 0 : 1);
      expect(find.byKey(const ValueKey('apple-output-picker')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      messenger.setMockMethodCallHandler(AudioOutputController.methods, null);
      messenger.setMockStreamHandler(AudioOutputController.events, null);
      messenger.setMockMethodCallHandler(MediaVolumeController.methods, null);
      messenger.setMockStreamHandler(MediaVolumeController.events, null);
    },
  );
}
