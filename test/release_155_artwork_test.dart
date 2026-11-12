import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/media/artwork_refresh_coordinator.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';

final _png155 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// Real image streams and real loopback HTTP; fixtures never reach a CDN.
void main() {
  for (final automatic in [false, true]) {
    testWidgets(
      '155 same-URL artwork ${automatic ? 'automatic' : 'manual'} retry succeeds in the current widget',
      (tester) async {
        final previous = HttpOverrides.current;
        HttpOverrides.global = null;
        HttpServer? server;
        final counts = <String, int>{};
        await tester.runAsync(() async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server!.listen((request) async {
            request.response.persistentConnection = false;
            final path = request.uri.path;
            final count = counts.update(path, (n) => n + 1, ifAbsent: () => 1);
            if (path == '/retry.png' && count == 1) {
              request.response.statusCode = 503;
            } else {
              request.response.headers.contentType = ContentType(
                'image',
                'png',
              );
              request.response.add(_png155);
            }
            await request.response.close();
          });
        });
        addTearDown(() async {
          HttpOverrides.global = previous;
          await server?.close(force: true);
          artworkRefreshCoordinator.dispose();
          PaintingBinding.instance.imageCache.clear();
        });
        final base = 'http://127.0.0.1:${server!.port}';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  ArtworkImage(
                    key: const ValueKey('neighbor155'),
                    uri: '$base/neighbor.png',
                    width: 72,
                    height: 72,
                  ),
                  ArtworkImage(
                    key: const ValueKey('retry155'),
                    uri: '$base/retry.png',
                    width: 72,
                    height: 72,
                    retryOnNetworkError: automatic,
                  ),
                ],
              ),
            ),
          ),
        );
        final element = tester.element(find.byKey(const ValueKey('retry155')));
        for (var i = 0; i < 60 && find.text('重试').evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text('重试'), findsOneWidget);
        expect(counts['/retry.png'], 1);
        final neighbor = find.descendant(
          of: find.byKey(const ValueKey('neighbor155')),
          matching: find.byType(RawImage),
        );
        for (var i = 0; i < 60 && neighbor.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(tester.widget<RawImage>(neighbor).image, isNotNull);
        final retainedNeighbor = tester.widget<RawImage>(neighbor).image;
        if (automatic) {
          await tester.pump(const Duration(milliseconds: 700));
        } else {
          await tester.tap(find.text('重试'));
        }
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
          final raw = find.descendant(
            of: find.byKey(const ValueKey('retry155')),
            matching: find.byType(RawImage),
          );
          if (raw.evaluate().isNotEmpty &&
              tester.widget<RawImage>(raw).image != null) {
            break;
          }
        }
        final raw = find.descendant(
          of: find.byKey(const ValueKey('retry155')),
          matching: find.byType(RawImage),
        );
        expect(tester.widget<RawImage>(raw).image, isNotNull);
        expect(
          identical(
            tester.element(find.byKey(const ValueKey('retry155'))),
            element,
          ),
          isTrue,
        );
        expect(counts['/retry.png'], 2);
        expect(counts['/neighbor.png'], 1);
        expect(tester.widget<RawImage>(neighbor).image, same(retainedNeighbor));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
