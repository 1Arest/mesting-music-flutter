import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/together/together_background_binding.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer, eapiBody;
import 'release_142_together_sync_test.dart' show SyntheticTogetherRoom;
import 'support/deterministic_audio_player.dart';

const _channel = MethodChannel('com.mesting.music/together_background');
const _codec = StandardMethodCodec();
Track _song(String id) => Track(
  id: 'netease_$id',
  platformSongId: id,
  source: TrackSource.netease,
  title: '合成$id',
  artist: '合成测试',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'file:///synthetic/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

Future<Object?> _pulse(Object arguments) {
  final completion = Completer<Object?>();
  ui.channelBuffers.push(
    _channel.name,
    _codec.encodeMethodCall(MethodCall('poll', arguments)),
    (bytes) {
      completion.complete(bytes == null ? null : _codec.decodeEnvelope(bytes));
    },
  );
  return completion.future;
}

void _lifecycle(WidgetTester tester, bool background) {
  final binding = tester.binding;
  if (!background) {
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  } else {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }
}

class _DelayedPlayer extends FakeTogetherPlayer
    implements NeteaseTogetherCancelablePlayer {
  final first = Completer<void>();
  final started = Completer<void>();
  int _generation = 0, cancellations = 0, attempts = 0;
  @override
  void cancelPendingApplication() {
    _generation++;
    cancellations++;
  }

  @override
  Future<void> apply(
    List<Track> queue,
    String id,
    Duration at,
    bool play,
  ) async {
    final generation = ++_generation;
    if (++attempts == 1) {
      started.complete();
      await first.future;
    }
    if (generation == _generation) await super.apply(queue, id, at, play);
  }
}

class _HeartbeatClient extends http.BaseClient {
  _HeartbeatClient(this.inner);
  final http.Client inner;
  final heartbeats = <Map<String, dynamic>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.endsWith('/heartbeat')) {
      heartbeats.add(eapiBody(request as http.Request));
    }
    return inner.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'disposing an unacknowledged configuration cancels its deadline',
    (tester) async {
      _lifecycle(tester, true);
      final response = Completer<Object?>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (_) => response.future,
      );
      final changes = ValueNotifier(true);
      final binding = TogetherBackgroundBinding(
        changes: changes,
        active: () => true,
        supported: true,
        poll: () async {},
      );
      await tester.idle();
      binding.dispose();
      changes.dispose();
      await tester.idle();
      // Late completion must not re-arm retries or confirm the retired lease.
      response.complete({'accepted': true, 'revision': -1});
      await tester.idle();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      );
      _lifecycle(tester, false);
    },
  );

  testWidgets('native acknowledgement does not wait for a blocked Dart poll', (
    tester,
  ) async {
    _lifecycle(tester, true);
    final changes = ValueNotifier(true);
    final configurations = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      final value = Map<Object?, Object?>.from(call.arguments as Map);
      configurations.add(value);
      return {'accepted': true, 'revision': value['revision']};
    });
    final gate = Completer<void>();
    var polls = 0;
    final binding = TogetherBackgroundBinding(
      changes: changes,
      active: () => true,
      supported: true,
      poll: () {
        polls++;
        return gate.future;
      },
    );
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      binding.dispose();
      changes.dispose();
      _lifecycle(tester, false);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      );
    });
    await tester.idle();
    final lease = configurations.last['lease'];
    expect(await _pulse({'lease': lease, 'request': 1}), true);
    expect(polls, 1);
    expect(gate.isCompleted, false);
    expect(await _pulse({'lease': lease, 'request': 1}), false);
    expect(await _pulse({'lease': 'old-owner', 'request': 2}), false);
    expect(polls, 1);
  });

  testWidgets('configuration failure retries with a confirmed revision', (
    tester,
  ) async {
    _lifecycle(tester, true);
    final changes = ValueNotifier(true);
    var attempts = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      final map = call.arguments as Map;
      if (++attempts < 3) throw PlatformException(code: 'temporary_fixture');
      return {'accepted': true, 'revision': map['revision']};
    });
    final binding = TogetherBackgroundBinding(
      changes: changes,
      active: () => true,
      poll: () async {},
      supported: true,
      retryDelay: const Duration(milliseconds: 10),
    );
    addTearDown(() {
      binding.dispose();
      changes.dispose();
      _lifecycle(tester, false);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      );
    });
    await tester.idle();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
    expect(attempts, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 3);
  });

  testWidgets(
    'failed configuration has bounded retries and later activity recovers it',
    (tester) async {
      _lifecycle(tester, true);
      final changes = ChangeNotifier();
      var attempts = 0, available = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        attempts++;
        if (!available) throw PlatformException(code: 'temporary_fixture');
        return {
          'accepted': true,
          'revision': (call.arguments as Map)['revision'],
        };
      });
      final binding = TogetherBackgroundBinding(
        changes: changes,
        active: () => true,
        poll: () async {},
        supported: true,
        retryDelay: const Duration(milliseconds: 10),
        configurationProbeDelay: const Duration(milliseconds: 20),
      );
      addTearDown(() {
        binding.dispose();
        changes.dispose();
        _lifecycle(tester, false);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        );
      });
      await tester.idle();
      for (final duration in [10, 20, 40]) {
        await tester.pump(Duration(milliseconds: duration));
      }
      expect(attempts, 4);
      await tester.pump(const Duration(seconds: 1));
      expect(
        attempts,
        4,
        reason: 'No perpetual retry timer after one bounded batch.',
      );
      // Stopwatch is intentionally real/monotonic, independent of a fake frame clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      available = true;
      changes.notifyListeners();
      await tester.idle();
      expect(attempts, 5);
    },
  );

  testWidgets('fallback activity renews a confirmed expired native lease', (
    tester,
  ) async {
    _lifecycle(tester, true);
    final changes = ChangeNotifier();
    final revisions = <int>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      final revision = (call.arguments as Map)['revision'] as int;
      revisions.add(revision);
      return {'accepted': true, 'revision': revision};
    });
    final binding = TogetherBackgroundBinding(
      changes: changes,
      active: () => true,
      poll: () async {},
      supported: true,
      leaseRefreshInterval: const Duration(milliseconds: 10),
    );
    addTearDown(() {
      binding.dispose();
      changes.dispose();
      _lifecycle(tester, false);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      );
    });
    await tester.idle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    changes.notifyListeners();
    await tester.idle();
    expect(revisions.length, 2);
    expect(revisions.last, greaterThan(revisions.first));
  });

  Future<
    (
      SyntheticTogetherRoom,
      _DelayedPlayer,
      NeteaseTogetherController,
      _HeartbeatClient,
    )
  >
  prepare() async {
    final room = SyntheticTogetherRoom();
    final original = room.music('8');
    final client = _HeartbeatClient(original.api.client);
    final music = NeteaseMusicRepository(
      NeteaseApi(client)..configure(original.api.session),
    );
    final player = _DelayedPlayer()
      ..track = _song('17')
      ..tracks = [_song('17'), _song('18')];
    final controller = NeteaseTogetherController(
      music: music,
      player: player,
      messages: NeteaseMessagesRepository(music),
      isCurrent: () => true,
      automaticTimer: false,
      remoteApplicationTimeout: const Duration(milliseconds: 60),
    );
    await controller.restore();
    addTearDown(() async {
      controller.dispose();
      if (!player.first.isCompleted) player.first.complete();
      await Future<void>.delayed(Duration.zero);
      await player.close();
      for (final value in room.clients) {
        value.close();
      }
    });
    return (room, player, controller, client);
  }

  test(
    'background heartbeat continues with the pending new song and accepts a newer command',
    () async {
      final (room, player, controller, client) = await prepare();
      room.latest = {
        'serverSeq': 1,
        'userId': '7',
        'targetSongId': '18',
        'playStatus': 'PLAY',
        'progress': 2000,
      };
      await controller.tick(waitForPlayback: false);
      await player.started.future;
      expect(client.heartbeats.last['songId'], '18');
      expect(client.heartbeats.last['playStatus'], 'PLAY');
      expect(player.applications, 0);
      await controller.tick(waitForPlayback: false);
      expect(client.heartbeats.length, 2);
      expect(client.heartbeats.last['songId'], '18');
      room.latest = {
        'serverSeq': 2,
        'userId': '7',
        'targetSongId': '17',
        'playStatus': 'PAUSE',
        'progress': 8000,
      };
      await controller.tick();
      expect(player.playing, false);
      expect(player.cancellations, 1);
      player.first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.track?.platformSongId, '17');
      expect(
        player.playing,
        false,
        reason: 'Late superseded PLAY must not resume audio.',
      );
      expect(room.writes, isEmpty);
    },
  );

  test(
    'application timeout cancels ownership and retries the same unconsumed command',
    () async {
      final (room, player, controller, _) = await prepare();
      room.latest = {
        'serverSeq': 1,
        'userId': '7',
        'targetSongId': '18',
        'playStatus': 'PAUSE',
        'progress': 0,
      };
      await controller.tick();
      expect(player.cancellations, 1);
      expect(controller.synchronizationDiagnostics['remoteTimeouts'], 1);
      await controller.tick();
      expect(player.track?.platformSongId, '18');
      expect(player.playing, false);
      expect(controller.synchronizationDiagnostics['remoteApplied'], 1);
      player.first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.applications, 1);
    },
  );

  test(
    'a distinct opaque version cancels old application before its deadline',
    () async {
      final (room, player, controller, _) = await prepare();
      room.latest = {
        'serverSeq': 'opaque-a',
        'userId': '7',
        'targetSongId': '18',
        'playStatus': 'PLAY',
        'progress': 0,
      };
      await controller.tick(waitForPlayback: false);
      await player.started.future;
      room.latest = {
        'serverSeq': 'opaque-b',
        'userId': '7',
        'targetSongId': '17',
        'playStatus': 'PAUSE',
        'progress': 0,
      };
      await controller.tick();
      expect(player.cancellations, 1);
      expect(player.track?.platformSongId, '17');
      expect(player.playing, false);
      player.first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, false);
    },
  );

  testWidgets(
    'real media controls supersede a pending remote source without an echo',
    (tester) async {
      await tester.runAsync(() async {
        final room = SyntheticTogetherRoom();
        final music = room.music('8');
        final player = DeterministicAudioPlayer();
        final handler = MestingAudioHandler(tracks: [], player: player);
        final messages = NeteaseMessagesRepository(music);
        final gate = Completer<Track>(), started = Completer<void>();
        handler.configureTrackPlaybackResolver((track) {
          if (track.platformSongId == '18') {
            started.complete();
            return gate.future;
          }
          return Future.value(_song(track.platformSongId));
        });
        await handler.replaceQueue([_song('17')]);
        final container = ProviderContainer(
          overrides: [
            usesNeteaseProvider.overrideWithValue(true),
            audioHandlerProvider.overrideWithValue(handler),
            neteaseMusicRepositoryProvider.overrideWithValue(music),
            neteaseMessagesRepositoryProvider.overrideWithValue(messages),
          ],
        );
        try {
          final controller = container.read(neteaseTogetherControllerProvider)!;
          await controller.restore();
          room.latest = {
            'serverSeq': 1,
            'userId': '7',
            'targetSongId': '18',
            'playStatus': 'PLAY',
            'progress': 0,
          };
          await controller.tick(waitForPlayback: false);
          await started.future;
          expect(room.writes, isEmpty);
          await handler.pause();
          await controller.settle();
          expect(room.writes.last['playStatus'], 'PAUSE');
          gate.complete(_song('18'));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(player.active, false);
        } finally {
          if (!gate.isCompleted) gate.complete(_song('18'));
          container.dispose();
          messages.dispose();
          await handler.debugDispose();
          for (final client in room.clients) {
            client.close();
          }
        }
      });
    },
  );

  testWidgets(
    'real handler rejects late resolved selection and protects a newer transport',
    (tester) async {
      await tester.runAsync(() async {
        final player = DeterministicAudioPlayer();
        final handler = MestingAudioHandler(tracks: [], player: player);
        final gate = Completer<Track>(), started = Completer<void>();
        handler.configureTrackPlaybackResolver((track) {
          if (track.platformSongId == '18') {
            started.complete();
            return gate.future;
          }
          return Future.value(track);
        });
        try {
          await handler.replaceQueue([_song('17')], autoplay: false);
          var valid = true;
          final old = handler.replaceQueue([
            _song('18'),
          ], togetherGuard: () => valid);
          final owned = handler.transportRevision;
          await started.future;
          valid = false;
          expect(handler.cancelPendingTogetherPlayback(owned), true);
          await handler.replaceQueue([_song('19')]);
          expect(handler.cancelPendingTogetherPlayback(owned), false);
          gate.complete(_song('18'));
          await old;
          expect(handler.mediaItem.value?.id, 'netease_19');
          expect(player.active, true);
          final play = handler.play(togetherGuard: () => true);
          final pause = handler.pause(togetherGuard: () => true);
          await Future.wait([play, pause]);
          expect(
            player.active,
            false,
            reason:
                'An older guarded play cannot outlive the newer pause revision.',
          );
        } finally {
          if (!gate.isCompleted) gate.complete(_song('18'));
          await handler.debugDispose();
        }
      });
    },
  );
}
