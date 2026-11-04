import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_background_binding.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer;
import 'release_142_together_sync_test.dart' show SyntheticTogetherRoom;
import 'support/deterministic_audio_player.dart';

const _channel = MethodChannel('com.mesting.music/together_background');
const _codec = StandardMethodCodec();
Future<void> _pulse(String lease) {
  final completion = Completer<void>();
  ui.channelBuffers.push(
    _channel.name,
    _codec.encodeMethodCall(MethodCall('poll', lease)),
    (_) => completion.complete(),
  );
  return completion.future;
}

void _background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _foreground(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Track _song(String id) => Track(
  id: 'netease_$id',
  platformSongId: id,
  source: TrackSource.netease,
  title: '合成歌曲$id',
  artist: '合成',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
);

void main() {
  testWidgets(
    'production Together adapter loads audio through the shared handler without frames',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      _foreground(tester);
      final configurations = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        configurations.add(Map<Object?, Object?>.from(call.arguments as Map));
        return null;
      });
      final room = SyntheticTogetherRoom();
      final music = room.music('8');
      // Decoding is deterministic. No audio host, source API or filesystem read
      // is needed, but selection still crosses the production provider/adapter.
      final (player, handler) = (await tester.runAsync(() async {
        final player = DeterministicAudioPlayer();
        final value = MestingAudioHandler(tracks: [], player: player);
        value.configureTrackPlaybackResolver(
          (track) async => track.copyWith(
            audioAsset: 'file:///synthetic/${track.platformSongId}.mp3',
          ),
        );
        await value
            .replaceQueue([_song('17')], autoplay: false)
            .timeout(const Duration(seconds: 10));
        return (player, value);
      }))!;
      final messages = NeteaseMessagesRepository(music);
      final container = ProviderContainer(
        overrides: [
          usesNeteaseProvider.overrideWithValue(true),
          audioHandlerProvider.overrideWithValue(handler),
          neteaseMusicRepositoryProvider.overrideWithValue(music),
          neteaseMessagesRepositoryProvider.overrideWithValue(messages),
        ],
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          container.dispose();
          messages.dispose();
          await handler.debugDispose();
        });
        _foreground(tester);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        );
        for (final c in room.clients) {
          c.close();
        }
      });
      final controller = (await tester.runAsync(() async {
        final value = container.read(neteaseTogetherControllerProvider)!;
        await value.restore();
        return value;
      }))!;
      _background(tester);
      await tester.idle();
      room.latest = {
        'serverSeq': 1,
        'userId': '7',
        'targetSongId': '18',
        'songId': '18',
        'playStatus': 'PLAY',
        'commandType': 'GOTO',
        'progress': 0,
      };
      // Asset-bundle metadata uses real asynchronous I/O even with a synthetic
      // decoder. Let that I/O run while still producing no render frames.
      expect(configurations.last['background'], true);
      await tester.runAsync(
        () => controller.tick().timeout(const Duration(seconds: 10)),
      );
      expect(handler.mediaItem.value?.id, 'netease_18');
      expect(player.active, true);
      expect(player.loads, greaterThan(0));
      expect(controller.error, isNull);
      expect(
        room.writes,
        isEmpty,
        reason: 'Applying a remote selection is not a new user action.',
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final remotePlaying in [false, true]) {
    testWidgets(
      'native pulse applies remote song/play state with rendering paused playing=$remotePlaying',
      (tester) async {
        final room = SyntheticTogetherRoom();
        final players = [FakeTogetherPlayer(), FakeTogetherPlayer()];
        final controllers = <NeteaseTogetherController>[];
        final configurations = <Map<Object?, Object?>>[];
        _foreground(tester);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          (call) async {
            configurations.add(
              Map<Object?, Object?>.from(call.arguments as Map),
            );
            return null;
          },
        );
        TogetherBackgroundBinding? binding;
        addTearDown(() async {
          binding?.dispose();
          _foreground(tester);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            _channel,
            null,
          );
          for (final c in controllers) {
            c.dispose();
          }
          for (final p in players) {
            await p.close();
          }
          for (final c in room.clients) {
            c.close();
          }
        });
        for (var i = 0; i < 2; i++) {
          players[i]
            ..track = _song('17')
            ..tracks = [_song('17'), _song('18')];
          final music = room.music('${7 + i}');
          final c = NeteaseTogetherController(
            music: music,
            player: players[i],
            messages: NeteaseMessagesRepository(music),
            isCurrent: () => true,
            automaticTimer: false,
          );
          controllers.add(c);
          await c.restore();
        }
        binding = TogetherBackgroundBinding(
          changes: controllers[1],
          active: () =>
              controllers[1].current &&
              controllers[1].active &&
              !controllers[1].ending,
          poll: controllers[1].poll,
          supported: true,
        );
        // No pump follows this lifecycle event. Remote application may not wait
        // for a frame, a visible player, or an Activity resume notification.
        _background(tester);
        await tester.idle();
        expect(configurations.last['active'], true);
        expect(configurations.last['background'], true);
        final lease = configurations.last['lease'] as String;
        players[0]
          ..track = _song('18')
          ..playing = remotePlaying;
        players[0].trackController.add('netease_18');
        await controllers[0].settle();
        expect(players[1].track?.platformSongId, '17');
        await _pulse(lease);
        expect(players[1].track?.platformSongId, '18');
        expect(players[1].playing, remotePlaying);
        final writes = room.writes.length;
        await _pulse(lease);
        expect(
          room.writes.length,
          writes,
          reason: 'A second pulse cannot echo the remote action.',
        );
        binding.dispose();
        await tester.idle();
        expect(configurations.last['active'], false);
      },
    );
  }

  testWidgets(
    'old leases cannot poll a new owner and exit releases the native lease',
    (tester) async {
      final changes = ValueNotifier(false);
      final configurations = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        configurations.add(Map<Object?, Object?>.from(call.arguments as Map));
        return null;
      });
      _background(tester);
      var first = 0, second = 0;
      final old = TogetherBackgroundBinding(
        changes: changes,
        active: () => true,
        poll: () async {
          first++;
        },
        supported: true,
      );
      await tester.idle();
      final oldLease = configurations.last['lease'] as String;
      final current = TogetherBackgroundBinding(
        changes: changes,
        active: () => changes.value,
        poll: () async {
          second++;
        },
        supported: true,
      );
      changes.value = true;
      await tester.idle();
      old.dispose();
      await _pulse(oldLease);
      expect(first, 0);
      expect(second, 0);
      await _pulse(configurations.last['lease'] as String);
      expect(second, 1);
      changes.value = false;
      await tester.idle();
      expect(configurations.last['active'], false);
      current.dispose();
      changes.dispose();
      _foreground(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      );
    },
  );
}
