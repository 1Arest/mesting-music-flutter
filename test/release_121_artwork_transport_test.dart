import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/shared/media/artwork_network_image.dart';

const _publicUrl = 'https://p1.music.126.net/fixture.jpg?param=180y180';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

// The base implementation creates a real IO client. TestWidgets' normal
// override blocks network traffic; this zone only reaches our loopback server.
class _LoopbackHttpOverrides extends HttpOverrides {}

/// Preserve the outgoing headers while redirecting the fixture to loopback.
/// This exercises package:http's actual IO header handling, not a map mock.
class _LoopbackClient extends http.BaseClient {
  _LoopbackClient(this.destination);
  final Uri destination;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(
    http.Request('GET', destination)..headers.addAll(request.headers),
  );

  @override
  void close() => _inner.close();
}

Future<void> _decode(ArtworkNetworkImage provider) async {
  final completer = provider.loadImage(
    provider,
    (buffer, {getTargetSize}) =>
        ui.instantiateImageCodecWithSize(buffer, getTargetSize: getTargetSize),
  );
  final ready = Completer<void>();
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, synchronous) {
      image.dispose();
      if (!ready.isCompleted) ready.complete();
    },
    onError: (Object error, StackTrace? trace) {
      if (!ready.isCompleted) ready.completeError(error, trace);
    },
  );
  completer.addListener(listener);
  try {
    await ready.future.timeout(const Duration(seconds: 5));
  } finally {
    completer.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only the public NetEase CDN selects the replacement transport', () {
    expect(networkArtworkProvider(_publicUrl), isA<ArtworkNetworkImage>());
    expect(
      networkArtworkProvider('https://music.126.net.other.test/signed?token=a'),
      isA<NetworkImage>(),
    );
    expect(
      networkArtworkProvider('https://imge.kugou.com/signed?token=a'),
      isA<NetworkImage>(),
    );
  });

  test(
    'URL, thumbnail size and explicit transport identify decoded cache rows',
    () {
      expect(
        const ArtworkNetworkImage(_publicUrl),
        const ArtworkNetworkImage(_publicUrl),
      );
      expect(
        const ArtworkNetworkImage(_publicUrl),
        isNot(const ArtworkNetworkImage('$_publicUrl&revision=2')),
      );
    },
  );

  testWidgets(
    'real IO sends one application User-Agent and decodes the image',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final client = _LoopbackClient(
            Uri.parse('http://127.0.0.1:${server.port}/cover'),
          );
          final headers = Completer<List<String>>();
          server.listen((request) async {
            headers.complete(request.headers[HttpHeaders.userAgentHeader]!);
            request.response.headers.contentType = ContentType('image', 'png');
            request.response.add(_png);
            await request.response.close();
          });
          try {
            await _decode(ArtworkNetworkImage(_publicUrl, client: client));
            expect(await headers.future, ['MestingMusic/1.0 (Artwork)']);
          } finally {
            client.close();
            await server.close(force: true);
          }
        }, _LoopbackHttpOverrides()),
      );
    },
  );

  testWidgets(
    'a CDN rejection retains its status and a later attempt can decode',
    (tester) async {
      await tester.runAsync(() async {
        var attempts = 0;
        final client = MockClient((request) async {
          expect(request.headers['User-Agent'], 'MestingMusic/1.0 (Artwork)');
          return ++attempts == 1
              ? http.Response('rejected', 403)
              : http.Response.bytes(_png, 200);
        });
        final provider = ArtworkNetworkImage(_publicUrl, client: client);
        try {
          await expectLater(
            _decode(provider),
            throwsA(
              isA<NetworkImageLoadException>().having(
                (e) => e.statusCode,
                'status',
                403,
              ),
            ),
          );
          await _decode(provider);
          expect(attempts, 2);
        } finally {
          client.close();
        }
      });
    },
  );
}
