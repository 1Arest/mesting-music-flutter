// The pinned local cache API is exercised through actual HTTP byte streams.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

class _CacheFailsPlayer extends DeterministicAudioPlayer {
  final attempts = <AudioSource>[];
  Completer<void>? beforeDirect;
  bool failPrimaryDirect = false;
  Object? cacheFailure;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    if (audioSources.isNotEmpty) {
      attempts.add(audioSources.first);
      if (failPrimaryDirect &&
          audioSources.first is UriAudioSource &&
          (audioSources.first as UriAudioSource).uri.host ==
              'cdn.example.test') {
        throw const SocketException('primary CDN unavailable');
      }
      if (audioSources.first is LockCachingAudioSource) {
        await beforeDirect?.future;
        throw cacheFailure ?? const SocketException('cache socket failed');
      }
    }
    return super.setAudioSources(
      audioSources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
  }
}

Track _track(String id) => Track(
  id: id,
  title: 'fixture',
  artist: 'fixture',
  album: 'fixture',
  duration: const Duration(minutes: 3),
  audioAsset: 'https://cdn.example.test/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  HttpOverrides? retainedOverrides;
  const path = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    retainedOverrides = HttpOverrides.current;
    HttpOverrides.global =
        null; // Real isolated loopback, never an external host.
    directory = await Directory.systemTemp.createTemp('mesting153-audio-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(path, (_) async => directory.path);
  });
  tearDown(() async {
    HttpOverrides.global = retainedOverrides;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(path, null);
    await directory.delete(recursive: true);
  });
  test(
    'initial cache preparation failure retries same recording directly without skipping queue',
    () async {
      final player = _CacheFailsPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      await handler.replaceQueue([
        _track('netease_1'),
        _track('netease_2'),
      ], autoplay: false);
      expect(player.attempts.length, 2);
      expect(player.attempts.first, isA<LockCachingAudioSource>());
      final direct = player.attempts.last as UriAudioSource;
      expect(direct.uri.toString(), 'https://cdn.example.test/netease_1.mp3');
      expect(direct.headers, null); // Empty headers must not reactivate proxy.
      expect(handler.mediaItem.value!.id, 'netease_1');
      expect(handler.queue.value.map((e) => e.id), ['netease_1', 'netease_2']);
      expect(player.active, false);
    },
  );
  test('a programming failure is surfaced without network replay', () async {
    final player = _CacheFailsPlayer()
      ..cacheFailure = StateError('fixture program failure');
    final handler = MestingAudioHandler(tracks: [], player: player);
    addTearDown(handler.debugDispose);
    await expectLater(
      handler.replaceQueue([_track('netease_1')], autoplay: false),
      throwsA(isA<StateError>()),
    );
    expect(player.attempts.length, 1);
    expect(player.active, false);
  });
  test(
    'only platform-supplied alternatives recover without changing recording or quality',
    () async {
      final player = _CacheFailsPlayer()..failPrimaryDirect = true;
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      final track = _track('netease_1').copyWith(
        playbackQuality: '320',
        audioAlternatives: ['https://backup.example.test/same-recording.mp3'],
      );
      await handler.replaceQueue([track], autoplay: false);
      expect(handler.mediaItem.value!.id, track.id);
      expect(handler.trackForId(track.id)!.playbackQuality, '320');
      expect(
        handler.trackForId(track.id)!.audioAsset,
        'https://backup.example.test/same-recording.mp3',
      );
      expect(player.active, false);
      expect(
        track
            .copyWith(audioAsset: 'https://different-source.test/song.mp3')
            .audioAlternatives,
        isEmpty,
      );
      expect(
        Track.fromJson(track.toJson()).audioAlternatives,
        track.audioAlternatives,
      );
    },
  );
  test(
    'a superseded cache failure cannot overwrite a newer selection',
    () async {
      final player = _CacheFailsPlayer()..beforeDirect = Completer<void>();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      final old = handler.replaceQueue([_track('netease_1')], autoplay: false);
      while (player.attempts.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final newer = handler.replaceQueue([
        _track('netease_2'),
      ], autoplay: false);
      player.beforeDirect!.complete();
      await Future.wait([old, newer]);
      expect(handler.mediaItem.value!.id, 'netease_2');
      expect(
        player.attempts.whereType<UriAudioSource>().map((e) => e.uri.path),
        ['/netease_2.mp3'],
      );
    },
  );
  test(
    'cache header deadline fails its consumer once without unhandled fetch errors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <HttpRequest>[];
      server.listen(requests.add);
      final cache = File('${directory.path}/stalled.mp3');
      final source = LockCachingAudioSource(
        Uri.http('127.0.0.1:${server.port}', '/audio'),
        cacheFile: cache,
        networkTimeout: const Duration(milliseconds: 60),
      );
      await expectLater(source.request(), throwsA(isA<TimeoutException>()));
      expect(cache.existsSync(), false);
      expect(requests.length, 1);
      // Catching the range future must also consume the shared fetch failure.
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );
  test('stalled chunks fail instead of publishing a truncated cache', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.contentLength = 100;
      request.response.headers.set('accept-ranges', 'bytes');
      request.response.add(List.filled(10, 1));
      unawaited(request.response.flush().catchError((_) {}));
    });
    final cache = File('${directory.path}/partial.mp3');
    final source = LockCachingAudioSource(
      Uri.http('127.0.0.1:${server.port}', '/audio'),
      cacheFile: cache,
      networkTimeout: const Duration(milliseconds: 500),
    );
    final operation = source.request().then(
      (response) => response.stream.drain<void>(),
    );
    await expectLater(operation, throwsA(anything));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(cache.existsSync(), false);
  });
  test('complete cache is flushed before it becomes reusable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final payload = List.generate(1024, (i) => i % 256);
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.contentLength = payload.length;
      request.response.add(payload);
      await request.response.close();
    });
    final cache = File('${directory.path}/complete.mp3');
    final source = LockCachingAudioSource(
      Uri.http('127.0.0.1:${server.port}', '/audio'),
      cacheFile: cache,
    );
    final response = await source.request();
    final bytes = await response.stream.fold<List<int>>(
      [],
      (a, b) => a..addAll(b),
    );
    expect(bytes, payload);
    for (var i = 0; !cache.existsSync() && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await cache.readAsBytes(), payload);
  });
}
