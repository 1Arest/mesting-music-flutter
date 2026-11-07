import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';
import 'package:mesting_music/shared/media/artwork_refresh_coordinator.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/retained_artwork_frame.dart';

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.red, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(192, 192);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a capsule reuses the larger search thumbnail without another request',
    () async {
      final directory = await Directory.systemTemp.createTemp('artwork129-');
      final bytes = await _png();
      var requests = 0;
      final cache = PersistentNetworkImageCache(
        directoryProvider: () async => directory,
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      final first = await cache.resolve(
        cacheKey: 'public-artwork-v1',
        url: 'https://p1.music.126.net/same.jpg?param=192y192',
      );
      final capsule = await cache.resolve(
        cacheKey: 'public-artwork-v1',
        url: 'https://p1.music.126.net/same.jpg?param=108y108',
      );
      expect(capsule?.path, first?.path);
      expect(requests, 1);
      await directory.delete(recursive: true);
    },
  );

  for (final broken in [false, true]) {
    test(
      'restart reuses the durable HD index and repairs corrupt aliases: $broken',
      () async {
        final root = await Directory.systemTemp.createTemp('artwork129-index-');
        final bytes = await _png();
        final before = PersistentNetworkImageCache(
          directoryProvider: () async => root,
          client: MockClient((_) async => http.Response.bytes(bytes, 200)),
        );
        final original = await before.resolve(
          cacheKey: 'public-artwork-v1',
          url: 'https://p1.music.126.net/indexed.jpg?param=1024y1024',
        );
        if (broken) await original!.writeAsString('invalid-image');
        var requests = 0;
        final after = PersistentNetworkImageCache(
          directoryProvider: () async => root,
          client: MockClient((_) async {
            requests++;
            return http.Response.bytes(bytes, 200);
          }),
        );
        await after.initialize();
        final restored = await after.resolve(
          cacheKey: 'public-artwork-v1',
          url: 'https://p2.music.126.net/indexed.jpg?param=192y192',
        );
        expect(restored, isNotNull);
        expect(requests, broken ? 1 : 0);
        expect(await restored!.readAsBytes(), bytes);
        await root.delete(recursive: true);
      },
    );
  }

  testWidgets(
    'a newly mounted song page receives the disk thumbnail while HD waits',
    (tester) async {
      late Directory directory;
      late PersistentNetworkImageCache cache;
      final hd = Completer<http.Response>();
      await tester.runAsync(() async {
        final fixtures = Directory(
          '.codex-artifacts/2026-11-01-release129/artwork-fixtures',
        );
        await fixtures.create(recursive: true);
        directory = await fixtures.createTemp('page-');
        final bytes = await _png();
        cache = PersistentNetworkImageCache(
          directoryProvider: () async => directory,
          client: MockClient(
            (request) async => request.url.queryParameters['param'] == '192y192'
                ? http.Response.bytes(bytes, 200)
                : hd.future,
          ),
        );
        await cache.resolve(
          cacheKey: 'public-artwork-v1',
          url: 'https://p1.music.126.net/unique-page.jpg?param=192y192',
        );
      });
      Widget app(double size, String surface) => MaterialApp(
        home: Center(
          child: ArtworkImage(
            key: ValueKey(surface),
            uri: 'https://p1.music.126.net/unique-page.jpg',
            width: size,
            height: size,
            persistentNetworkCacheKey: 'public-artwork-v1',
            networkImageCache: cache,
          ),
        ),
      );
      // Let the real search image decode and register its shared frame, then
      // mount an entirely new player image element while HD is still blocked.
      await tester.pumpWidget(app(52, 'search'));
      for (
        var attempt = 0;
        attempt < 30 && find.byType(RawImage).evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await tester.pumpWidget(app(300, 'song-page'));
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        isNotNull,
        reason:
            'The new player element must have real pixels in its very first frame.',
      );
      final frame = tester.widget<RetainedArtworkFrame>(
        find.byType(RetainedArtworkFrame),
      );
      expect(
        frame.image,
        isNotNull,
        reason:
            'The existing thumbnail must be available in the first build, even before HD completes.',
      );
      hd.complete(http.Response('', 503));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.runAsync(() async {
        await cache.flush();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      artworkRefreshCoordinator.dispose();
      imageCache.clear();
      imageCache.clearLiveImages();
      // Keep the tiny synthetic fixture as render evidence. Windows' test
      // engine can retain the FileImage mmap until this test process exits.
    },
  );
}
