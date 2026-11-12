import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/audio_output_controller.dart';
import 'package:mesting_music/core/audio/media_volume_controller.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/persistence/playback_persistence_controller.dart';
import 'package:mesting_music/features/experience/presentation/apple_player_controls.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

Track _song(TrackSource source) => Track(
  id: '${source.name}_210',
  title: '进度恢复样本',
  artist: '测试数据',
  album: '',
  duration: const Duration(minutes: 4),
  source: source,
  audioAsset: 'assets/fixture.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

class _Volume extends MediaVolumeController {
  @override
  MediaVolumeState build() =>
      const MediaVolumeState(value: .5, available: true);
}

class _Output extends AudioOutputController {
  @override
  AudioOutput build() => const AudioOutput(available: true);
}

// The widget fixture controls only presentation events. Real restoration,
// persistence and native seek ordering are exercised below without fake time.
class _PresentationHandler implements MestingAudioHandler {
  Duration at = const Duration(seconds: 77);
  bool playing = false;
  void Function(Duration)? publish;
  @override
  Duration get currentPosition => at;
  @override
  PlaybackOrder get playbackOrder => const PlaybackOrder();
  @override
  Future<void> seek(Duration position, {bool Function()? togetherGuard}) async {
    at = position;
    publish?.call(position);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SlowPlayer extends DeterministicAudioPlayer {
  final first = Completer<void>();
  final started = Completer<void>();
  final requested = <Duration>[];
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    requested.add(position!);
    if (requested.length == 1) {
      started.complete();
      await first.future;
    }
    at = position;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('mesting210_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
  });

  for (final source in [TrackSource.netease, TrackSource.kugou]) {
    testWidgets(
      '$source restored Apple presentation displays progress while idle and keeps paused seek',
      (tester) async {
        final handler = _PresentationHandler();
        final positions = StreamController<Duration>.broadcast();
        handler.publish = positions.add;
        final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
        final container = ProviderContainer(
          overrides: [
            audioHandlerProvider.overrideWithValue(handler),
            currentTrackProvider.overrideWithValue(_song(source)),
            playbackStateProvider.overrideWith(
              (_) => Stream.value(
                PlaybackState(processingState: AudioProcessingState.idle),
              ),
            ),
            positionProvider.overrideWith((_) => positions.stream),
            durationProvider.overrideWith(
              (_) => Stream.value(const Duration(minutes: 4)),
            ),
            playbackOrderProvider.overrideWith(
              (_) => Stream.value(const PlaybackOrder()),
            ),
            sharedPreferencesProvider.overrideWithValue(prefs),
            mediaVolumeProvider.overrideWith(_Volume.new),
            audioOutputProvider.overrideWith(_Output.new),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
          // Drain Riverpod's asynchronous Stream.multi cancellation in the
          // simulated clock before closing the real handler outside it.
          await tester.pump();
          await positions.close();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                backgroundColor: Colors.black,
                body: ApplePlayerControls(
                  onToggleLyrics: () {},
                  onToggleQueue: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        positions.add(const Duration(seconds: 77));
        await tester.pump(const Duration(milliseconds: 100));
        Slider slider() => tester.widget<Slider>(
          find.byKey(const ValueKey('playback-seek-slider')),
        );
        expect(slider().value, 77000);
        expect(find.text('1:17'), findsOneWidget);
        expect(handler.playing, isFalse);
        slider().onChangeStart!(90000);
        slider().onChanged!(120000);
        await tester.pump();
        expect(slider().value, 120000);
        expect(handler.currentPosition, const Duration(seconds: 77));
        await tester.runAsync(() async {
          slider().onChangeEnd!(120000);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(slider().value, 120000);
        expect(find.text('2:00'), findsOneWidget);
        expect(handler.currentPosition, const Duration(minutes: 2));
        expect(handler.playing, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    test(
      '$source paused seek survives another process-style restore',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final first = MestingAudioHandler(
          tracks: [],
          player: DeterministicAudioPlayer(),
        );
        final persistence = PlaybackPersistenceController(
          database: db,
          audioHandler: first,
        );
        final owner = '${source.name}:fixture210';
        await db.savePlaybackSession(
          ownerId: owner,
          queue: [_song(source)],
          currentIndex: 0,
          position: const Duration(seconds: 77),
          playbackMode: 'list',
        );
        await persistence.activateOwner(owner);
        await first.seek(const Duration(seconds: 123));
        await persistence.saveBeforeUpdate();
        final secondPlayer = DeterministicAudioPlayer();
        final second = MestingAudioHandler(tracks: [], player: secondPlayer);
        var resolutions = 0;
        second.configureTrackPlaybackResolver((track) async {
          resolutions++;
          return track;
        });
        final restored = PlaybackPersistenceController(
          database: db,
          audioHandler: second,
        );
        try {
          await restored.activateOwner(owner);
          expect(second.currentPosition, const Duration(seconds: 123));
          expect(second.playbackState.value.playing, isFalse);
          expect(
            await second.positionStream.first,
            const Duration(seconds: 123),
          );
          expect(resolutions, 0);
          await second.play();
          expect(resolutions, 1);
          expect(secondPlayer.at, const Duration(seconds: 123));
          expect(secondPlayer.active, isTrue);
        } finally {
          await restored.dispose();
          await second.debugDispose();
          await persistence.dispose();
          await first.debugDispose();
          await db.close();
        }
      },
    );
  }

  test(
    'slow native seeks finish in release order with latest target winning',
    () async {
      final player = _SlowPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      await handler.replaceQueue([_song(TrackSource.netease)], autoplay: false);
      final first = handler.seek(const Duration(seconds: 90));
      await player.started.future;
      final second = handler.seek(const Duration(seconds: 30));
      final last = handler.seek(const Duration(seconds: 60));
      await handler.pause();
      player.first.complete();
      await Future.wait([first, second, last]);
      expect(player.requested, [
        const Duration(seconds: 90),
        const Duration(seconds: 60),
      ]);
      expect(player.at, const Duration(seconds: 60));
      expect(await handler.positionStream.first, const Duration(seconds: 60));
    },
  );
}
