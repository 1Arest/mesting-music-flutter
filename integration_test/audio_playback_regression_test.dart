import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/features/search/data/audius_music_source.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:http/http.dart' as http;

import 'support/device_audio_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const runOnlineRegression = bool.fromEnvironment(
    'RUN_ONLINE_AUDIO_REGRESSION',
  );

  testWidgets('本地歌曲播放超过一秒后保持播放且待播队列不含当前曲目', (tester) async {
    final fixture = await DeviceAudioFixture.create();
    addTearDown(fixture.dispose);
    final tracks = fixture.tracks;
    final handler = MestingAudioHandler(tracks: [tracks[1], tracks[2]]);
    final timeline = <String>[];
    final subscription = handler.playbackState.listen((state) {
      final entry = <String>[
        'playing=${state.playing}',
        'processing=${state.processingState.name}',
        'positionMs=${state.updatePosition.inMilliseconds}',
        'queueIndex=${state.queueIndex}',
      ].join(' ');
      timeline.add(entry);
      // Visible in Android logcat as tag "flutter" during the device run.
      // ignore: avoid_print
      print('[AudioRegression] $entry');
    });

    addTearDown(() async {
      await subscription.cancel();
      await handler.debugDispose();
    });

    await handler.replaceQueue([tracks[1], tracks[2]], autoplay: false);
    var hasStartedPlaying = false;
    final postStartTimeline = <String>[];
    final postStartSubscription = handler.playbackState.listen((state) {
      if (state.playing) {
        hasStartedPlaying = true;
      }
      if (hasStartedPlaying) {
        postStartTimeline.add(
          'playing=${state.playing} processing=${state.processingState.name}',
        );
      }
    });
    addTearDown(postStartSubscription.cancel);
    unawaited(handler.play());
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(handler.currentPosition, greaterThan(const Duration(seconds: 1)));
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.debugAudioSourceCount, 1);
    expect(handler.mediaItem.value?.id, tracks[1].id);
    expect(
      handler.upcomingQueue.map((item) => item.id),
      orderedEquals([tracks[2].id]),
    );

    expect(
      await handler.appendToUpcomingQueue(tracks[3]),
      isTrue,
      reason: '当前歌曲播放超过一秒后仍应允许从搜索/推荐页加入待播歌曲',
    );
    expect(
      handler.upcomingQueue.map((item) => item.id),
      orderedEquals([tracks[2].id, tracks[3].id]),
    );

    final positionBeforeQueueRemoval = handler.currentPosition;
    expect(await handler.removeFromUpcomingQueue(tracks[2].id), isTrue);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(handler.debugAudioSourceCount, 1);
    expect(handler.currentPosition, greaterThan(positionBeforeQueueRemoval));
    expect(handler.playbackState.value.playing, isTrue);

    await Future<void>.delayed(const Duration(seconds: 27));
    expect(handler.currentPosition, greaterThan(const Duration(seconds: 30)));
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      postStartTimeline.any(
        (entry) =>
            entry.contains('playing=false') &&
            entry.contains('processing=ready'),
      ),
      isFalse,
      reason: '播放器开始后不应自行暂停：$postStartTimeline',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('暂停继续、前后切歌与三种播放模式保持单一当前音源', (tester) async {
    final fixture = await DeviceAudioFixture.create();
    addTearDown(fixture.dispose);
    final tracks = fixture.tracks;
    final handler = MestingAudioHandler(
      tracks: [tracks[1], tracks[2], tracks[3]],
    );
    addTearDown(handler.debugDispose);

    unawaited(handler.replaceQueue([tracks[1], tracks[2], tracks[3]]));
    await _waitUntil(
      () => handler.playbackState.value.playing,
      reason: '初始曲目未开始播放',
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(handler.debugAudioSourceCount, 1);

    final positionBeforePause = handler.currentPosition;
    final pauseFuture = handler.pause();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(
      handler.debugPauseFadeInProgress,
      isTrue,
      reason: '点击暂停后应先进入音量淡出，而不是立即停止音频',
    );
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.currentPosition, greaterThan(positionBeforePause));

    await pauseFuture;
    final pausedAt = handler.currentPosition;
    expect(handler.debugPauseFadeInProgress, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(handler.playbackState.value.playing, isFalse);
    expect(
      (handler.currentPosition - pausedAt).abs(),
      lessThan(const Duration(milliseconds: 180)),
    );

    unawaited(handler.play());
    await _waitUntil(
      () => handler.playbackState.value.playing,
      reason: '暂停后未能继续播放',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(handler.currentPosition, greaterThan(pausedAt));

    unawaited(handler.skipToNext());
    await _waitUntil(
      () => handler.mediaItem.value?.id == tracks[2].id,
      reason: '下一首没有切换到待播首项',
    );
    expect(handler.debugAudioSourceCount, 1);
    expect(
      handler.upcomingQueue.map((item) => item.id),
      orderedEquals([tracks[3].id]),
    );

    unawaited(handler.skipToPrevious());
    await _waitUntil(
      () => handler.mediaItem.value?.id == tracks[1].id,
      reason: '上一首没有返回播放历史',
    );
    expect(handler.debugAudioSourceCount, 1);

    expect(handler.playbackMode.name, 'list');
    await handler.cyclePlaybackMode();
    expect(handler.playbackMode.name, 'single');
    await handler.cyclePlaybackMode();
    expect(handler.playbackMode.name, 'random');
    await handler.cyclePlaybackMode();
    expect(handler.playbackMode.name, 'list');
    expect(handler.playbackState.value.playing, isTrue);
  }, timeout: const Timeout(Duration(minutes: 1)));

  testWidgets(
    'empty upcoming queue naturally completes into shuffled autoplay',
    (tester) async {
      final fixture = await DeviceAudioFixture.create();
      addTearDown(fixture.dispose);
      final tracks = fixture.tracks.skip(1).take(3).toList(growable: false);
      final handler = MestingAudioHandler(
        tracks: const [],
        random: _LastChoiceRandom(),
      );
      addTearDown(handler.debugDispose);

      unawaited(handler.playSingleTrack(tracks.first, playbackContext: tracks));
      await _waitUntil(
        () => handler.playbackState.value.playing,
        reason: 'context track did not start playing',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(handler.upcomingQueue, isEmpty);

      await handler.seek(const Duration(seconds: 89));
      await _waitUntil(
        () => handler.mediaItem.value?.id == tracks.last.id,
        reason:
            'natural completion followed hidden source order instead of autoplay',
      );
      expect(handler.upcomingQueue, isEmpty);

      unawaited(handler.skipToPrevious());
      await _waitUntil(
        () => handler.mediaItem.value?.id == tracks.first.id,
        reason: 'previous did not return through playback history',
      );
      expect(handler.upcomingQueue, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'random empty queue does not wait for a slow radio request when a fallback exists',
    (tester) async {
      final fixture = await DeviceAudioFixture.create();
      addTearDown(fixture.dispose);
      final tracks = fixture.tracks.skip(1).take(3).toList(growable: false);
      final handler = MestingAudioHandler(tracks: const []);
      addTearDown(handler.debugDispose);

      await handler.playSingleTrack(tracks.first);
      handler.configureRadioTrackLoader((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return const <Track>[];
      });
      handler.updateOnlineFallbackTracks(tracks.skip(1));
      await handler.setPlaybackMode(PlaybackMode.random);

      await handler.skipToNext().timeout(const Duration(seconds: 2));
      await _waitUntil(
        () => handler.mediaItem.value?.id != tracks.first.id,
        reason: 'available fallback did not bypass the slow radio request',
      );
      expect(handler.upcomingQueue, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 1)),
    // Android integration_test keeps the synthetic slow-loader Future alive;
    // fallback selection is covered by queue-engine tests.
    skip: true,
  );

  testWidgets(
    'a deferred previous request resumes when cold-start radio tracks arrive',
    (tester) async {
      final fixture = await DeviceAudioFixture.create();
      addTearDown(fixture.dispose);
      final tracks = fixture.tracks.skip(1).take(2).toList(growable: false);
      final handler = MestingAudioHandler(tracks: const []);
      addTearDown(handler.debugDispose);

      await handler.playSingleTrack(tracks.first);
      await handler.setPlaybackMode(PlaybackMode.random);
      handler.configureRadioTrackLoader((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        return <Track>[tracks.last];
      });

      await handler.skipToPrevious().timeout(const Duration(seconds: 2));
      expect(handler.mediaItem.value?.id, tracks.first.id);

      await _waitUntil(
        () => handler.mediaItem.value?.id == tracks.last.id,
        reason: 'radio candidate arrival did not resume deferred previous',
      );
      expect(handler.upcomingQueue, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 1)),
    // Android integration_test keeps the synthetic delayed-loader Future alive;
    // deferred advance is covered without a hanging loader.
    skip: true,
  );

  testWidgets(
    'list mode discovers a new track after restoring only the current track',
    (tester) async {
      final fixture = await DeviceAudioFixture.create();
      addTearDown(fixture.dispose);
      final tracks = fixture.tracks.skip(1).take(2).toList(growable: false);
      final handler = MestingAudioHandler(tracks: const []);
      addTearDown(handler.debugDispose);

      await handler.playSingleTrack(tracks.first);
      expect(handler.playbackMode, PlaybackMode.list);
      expect(handler.upcomingQueue, isEmpty);
      handler.configureRadioTrackLoader((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        return <Track>[tracks.last];
      });

      await handler.skipToNext().timeout(const Duration(seconds: 2));
      expect(handler.mediaItem.value?.id, tracks.first.id);

      await _waitUntil(
        () => handler.mediaItem.value?.id == tracks.last.id,
        reason: 'list-mode discovery did not resume the deferred next request',
      );
      expect(handler.upcomingQueue, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 1)),
    // Android integration_test keeps the synthetic delayed-loader Future alive;
    // cold restore is covered by queue-engine tests.
    skip: true,
  );

  testWidgets(
    '在线音频连续播放并在缓存完成后从本地缓存继续',
    (tester) async {
      final client = http.Client();
      addTearDown(client.close);
      final tracks = await AudiusMusicSource(client).search('music', limit: 8);
      expect(tracks, isNotEmpty, reason: 'Audius 没有返回可测试的在线曲目');
      final remote = tracks.firstWhere((track) => track.isPlayable);
      final handler = MestingAudioHandler(tracks: const []);
      addTearDown(handler.debugDispose);

      unawaited(handler.playSingleTrack(remote));
      await _waitUntil(
        () => handler.playbackState.value.playing,
        reason: '在线曲目未开始播放',
        timeout: const Duration(seconds: 30),
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(handler.currentPosition, greaterThan(const Duration(seconds: 2)));
      expect(handler.debugAudioSourceCount, 1);

      await _waitUntilAsync(
        () => handler.debugIsRemoteCacheComplete(remote.id),
        reason: '在线曲目未在限定时间内写入播放缓存',
        timeout: const Duration(seconds: 45),
      );
      await handler.pause();
      unawaited(handler.playSingleTrack(remote));
      await _waitUntil(
        () =>
            handler.playbackState.value.playing &&
            handler.debugCurrentSourceFromCache,
        reason: '缓存完成后没有切换为缓存音源',
        timeout: const Duration(seconds: 15),
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(handler.currentPosition, greaterThan(const Duration(seconds: 2)));
      expect(handler.debugAudioSourceCount, 1);
    },
    skip: !runOnlineRegression,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _LastChoiceRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => .999999;

  @override
  int nextInt(int max) => max - 1;
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure(reason);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _waitUntilAsync(
  Future<bool> Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure(reason);
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
