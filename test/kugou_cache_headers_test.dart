// Exercise the pinned cache implementation with real loopback HTTP only.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in <(String, List<String>, bool)>[
    ('duplicate', ['bytes', 'bytes'], true),
    ('combined', ['bytes, bytes'], true),
    ('case and whitespace', [' Bytes '], true),
    ('none', ['none'], false),
    ('unknown unit', ['items'], false),
    ('missing', [], false),
  ]) {
    test('cache streams audio with ${scenario.$1} Accept-Ranges', () async {
      final retained = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = retained);
      final directory = await Directory.systemTemp.createTemp('kugou-headers-');
      addTearDown(() => directory.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final firstChunk = Completer<void>();
      final finish = Completer<void>();
      addTearDown(() {
        if (!finish.isCompleted) finish.complete();
      });
      final payload = List.generate(131072, (i) => i % 256);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        for (final value in scenario.$2) {
          request.response.headers.add(HttpHeaders.acceptRangesHeader, value);
        }
        request.response.headers.noFolding(HttpHeaders.acceptRangesHeader);
        request.response.contentLength = payload.length;
        request.response.add(payload.sublist(0, 65536));
        await request.response.flush();
        firstChunk.complete();
        await finish.future;
        request.response.add(payload.sublist(65536));
        await request.response.close();
      });
      final cache = File('${directory.path}/audio.mp3');
      final source = LockCachingAudioSource(
        Uri.http('127.0.0.1:${server.port}', '/audio'),
        cacheFile: cache,
      );
      final responseFuture = source.request();
      await firstChunk.future.timeout(const Duration(seconds: 3));
      final response = await responseFuture.timeout(const Duration(seconds: 3));
      expect(response.rangeRequestsSupported, scenario.$3);
      final arrived = Completer<void>();
      final bytes = <int>[];
      final done = Completer<void>();
      response.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          if (!arrived.isCompleted) arrived.complete();
        },
        onError: done.completeError,
        onDone: done.complete,
      );
      // Playback can consume the first chunk before the complete song is cached.
      await arrived.future.timeout(const Duration(seconds: 3));
      expect(bytes, payload.sublist(0, 65536));
      expect(cache.existsSync(), isFalse);
      finish.complete();
      await done.future.timeout(const Duration(seconds: 3));
      expect(bytes, payload);
      for (var i = 0; !cache.existsSync() && i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(await cache.readAsBytes(), payload);
    });
  }
}
