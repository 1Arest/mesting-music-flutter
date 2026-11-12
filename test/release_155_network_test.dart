import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/core/network/system_music_io_client.dart';
import 'package:mesting_music/shared/media/artwork_network_image.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/kugou_official_api.dart';
import 'package:mesting_music/features/music_platform/data/kugou_listening_profile_repository.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/domain/kugou_listening_profile.dart';
import 'package:mesting_music/features/music_platform/kugou_listening_profile_providers.dart';

/// Preserve the real request/headers/abort contract while limiting all fixtures
/// to loopback. The production TLS factory still verifies its fixture hostname.
class _LoopbackRoute155 extends http.BaseClient {
  _LoopbackRoute155(this.inner, this.port, this.host);
  final http.Client inner;
  final int port;
  final String host;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final clone =
        http.AbortableRequest(
            request.method,
            request.url.replace(host: host, port: port),
            abortTrigger: request is http.Abortable
          ? request.abortTrigger
                : null,
          )
          ..followRedirects = request.followRedirects
          ..headers.addAll(request.headers)
          ..bodyBytes = body;
    return inner.send(clone);
  }
}

class _NoRemoteServer155 implements MusicServer {
  @override
  Future<Uri> start() async =>
      throw StateError('No embedded server is used by these official fixtures');
}

/// Real TLS over loopback exercises the Android-specific connection factory.
/// HTTP-only or MockClient fixtures cannot detect a missing TLS handshake.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final overrides = HttpOverrides.current;
  const channel = MethodChannel('com.mesting.music/network');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() {
    HttpOverrides.global = null;
    SecurityContext.defaultContext.setTrustedCertificates(
      'test/support/tls155/certificate.pem',
    );
  });
  tearDownAll(() => HttpOverrides.global = overrides);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<HttpServer> serve() async {
    final context = SecurityContext()
      ..useCertificateChain('test/support/tls155/certificate.pem')
      ..usePrivateKey('test/support/tls155/public-test-key.pem');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    addTearDown(() => server.close(force: true));
    return server;
  }

  SystemMusicIoClient client({int generation = 1}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'policy') {
        return {'generation': generation, 'proxy': 'DIRECT'};
      }
      expect(call.method, 'resolve');
      return ['127.0.0.1'];
    });
    final value = SystemMusicIoClient(
      network: MusicSystemNetwork(android: true),
    );
    addTearDown(value.close);
    return value;
  }

  test(
    'Android direct HTTPS performs TLS and preserves the original host',
    () async {
      final server = await serve();
      var received = 0;
      server.listen((request) async {
        received++;
        expect(request.certificate, isNull); // No client certificate is needed.
        expect(request.headers.host, 'music.fixture.test');
        request.response.write('encrypted-response');
        await request.response.close();
      }, onError: (Object _) {});
      final response = await client()
          .get(Uri.parse('https://music.fixture.test:${server.port}/profile'))
          .timeout(const Duration(seconds: 5));
      expect(response.statusCode, 200);
      expect(response.body, 'encrypted-response');
      expect(received, 1);
    },
  );

  test(
    'Android HTTPS rejects a certificate for a different hostname',
    () async {
      final server = await serve();
      var received = 0;
      server.listen((request) async {
        received++;
        await request.response.close();
      }, onError: (Object _) {});
      await expectLater(
        client().get(Uri.parse('https://wrong.fixture.test:${server.port}/')),
        throwsA(anyOf(isA<HandshakeException>(), isA<http.ClientException>())),
      );
      expect(received, 0);
    },
  );

  test(
    'HTTPS through an HTTP CONNECT proxy keeps exactly one TLS layer',
    () async {
      final origin = await serve();
      var received = 0;
      origin.listen((request) async {
        received++;
        expect(request.headers.host, 'music.fixture.test');
        request.response.write('tunnel-ok');
        await request.response.close();
      }, onError: (Object _) {});
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      final sockets = <Socket>[];
      addTearDown(() {
        for (final socket in sockets) {
          socket.destroy();
        }
      });
      var tunnels = 0;
      proxy.listen((request) async {
        expect(request.method, 'CONNECT');
        tunnels++;
        final incoming = await request.response.detachSocket(
          writeHeaders: false,
        );
        final outgoing = await Socket.connect(
          InternetAddress.loopbackIPv4,
          origin.port,
        );
        sockets.addAll([incoming, outgoing]);
        incoming.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        await incoming.flush();
        unawaited(
          outgoing
              .cast<List<int>>()
              .pipe(incoming)
              .then<void>((_) {}, onError: (Object _) {}),
        );
        unawaited(
          incoming
              .cast<List<int>>()
              .pipe(outgoing)
              .then<void>((_) {}, onError: (Object _) {}),
        );
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'policy');
        return {'generation': 4, 'proxy': 'PROXY 127.0.0.1:${proxy.port}'};
      });
      final transport = SystemMusicIoClient(
        network: MusicSystemNetwork(android: true),
      );
      addTearDown(transport.close);
      final response = await transport.get(
        Uri.parse('https://music.fixture.test:${origin.port}/proxied'),
      );
      expect(response.body, 'tunnel-ok');
      expect(received, 1);
      expect(tunnels, 1);
    },
  );

  test(
    'network-generation change preserves an already-started DNS/TLS POST without replay',
    () async {
      final server = await serve();
      final seen = <String>[];
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          [],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        seen.add(String.fromCharCodes(body));
        request.response.write('received');
        await request.response.close();
      }, onError: (Object _) {});
      final resolving = Completer<void>();
      final release = Completer<List<String>>();
      var generation = 1;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'policy') {
          return {'generation': generation, 'proxy': 'DIRECT'};
        }
        if (generation == 1) {
          resolving.complete();
          return release.future;
        }
        return ['127.0.0.1'];
      });
      final transport = SystemMusicIoClient(
        network: MusicSystemNetwork(android: true),
      );
      addTearDown(transport.close);
      final uri = Uri.parse('https://music.fixture.test:${server.port}/write');
      final first = transport.post(uri, body: 'first-write');
      await resolving.future;
      generation = 2;
      expect((await transport.post(uri, body: 'second-write')).statusCode, 200);
      release.complete(['127.0.0.1']);
      expect((await first).statusCode, 200);
      expect(seen, ['second-write', 'first-write']);
    },
  );

  test(
    'large HTTPS response remains a complete stream beyond the JSON bridge cap',
    () async {
      final server = await serve();
      const total = 18 * 1024 * 1024 + 31;
      server.listen((request) async {
        request.response.contentLength = total;
        final chunk = List<int>.filled(65536, 17);
        for (var offset = 0; offset < total; offset += chunk.length) {
          request.response.add(
            offset + chunk.length <= total
                ? chunk
                : chunk.sublist(0, total - offset),
          );
        }
        await request.response.close();
      }, onError: (Object _) {});
      final response = await client().send(
        http.Request(
          'GET',
          Uri.parse('https://music.fixture.test:${server.port}/large'),
        ),
      );
      var bytes = 0, sum = 0;
      await for (final chunk in response.stream) {
        bytes += chunk.length;
        sum += chunk.fold<int>(0, (value, byte) => value + byte);
      }
      expect(bytes, total);
      expect(sum, total * 17);
    },
  );

  test(
    'closing during TLS handshake releases the connection without issuing HTTP',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final accepted = Completer<Socket>();
      final disconnected = Completer<void>();
      server.listen((socket) {
        accepted.complete(socket);
        socket.listen(
          (_) {},
          onDone: () {
            if (!disconnected.isCompleted) disconnected.complete();
          },
          onError: (Object _) {},
        );
      });
      final transport = client();
      final pending = expectLater(
        transport.get(
          Uri.parse(
            'https://music.fixture.test:${server.port}/never-dispatched',
          ),
        ),
        throwsA(anyOf(isA<SocketException>(), isA<http.ClientException>())),
      );
      final socket = await accepted.future;
      addTearDown(socket.destroy);
      transport.close();
      await pending;
      await disconnected.future.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'first NetEase artwork decode succeeds over the Android HTTPS factory',
    () async {
      final server = await serve();
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      var received = 0;
      server.listen((request) async {
        received++;
        expect(request.headers[HttpHeaders.userAgentHeader], [
          'MestingMusic/1.0 (Artwork)',
        ]);
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
        await request.response.close();
      }, onError: (Object _) {});
      final provider = ArtworkNetworkImage(
        'https://p1.music.126.net/synthetic-cover.png',
        client: _LoopbackRoute155(client(), server.port, 'images.fixture.test'),
      );
      final stream = provider.loadImage(
        provider,
        (buffer, {getTargetSize}) => ui.instantiateImageCodecWithSize(
          buffer,
          getTargetSize: getTargetSize,
        ),
      );
      final ready = Completer<void>();
      final listener = ImageStreamListener(
        (info, _) {
          expect(info.image.width, 1);
          info.dispose();
          if (!ready.isCompleted) ready.complete();
        },
        onError: (Object error, StackTrace? stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      try {
        await ready.future.timeout(const Duration(seconds: 5));
      } finally {
        stream.removeListener(listener);
      }
      expect(received, 1);
    },
  );

  test(
    'official statistics, grade/music-age and medals load through real Android TLS',
    () async {
      const owner = PlatformSession(
        userId: '155',
        token: 'synthetic-lite',
        kugouStandardToken: 'synthetic-standard',
      );
      final now = DateTime(2026, 11, 5);
      final server = await serve();
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        expect(request.uri.queryParameters['appid'], '1005');
        expect(request.uri.queryParameters['token'], owner.kugouStandardToken);
        await request.drain<void>();
        final data = request.uri.path.endsWith('my_info')
            ? {
                'grade': {'p_grade': 9, 'reg_time': '2016-01-01 00:00:00'},
                'timestamp': now.millisecondsSinceEpoch ~/ 1000,
              }
            : request.uri.path.endsWith('my_medals')
            ? {'total': 3, 'list': []}
            : {
                'grade_info': {'duration': 120},
                'listen_duration': 300,
              };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 1, 'data': data}));
        await request.response.close();
      }, onError: (Object _) {});
      final transport = _LoopbackRoute155(
        client(),
        server.port,
        'official.fixture.test',
      );
      final reader = KugouListeningProfileReader(
        owner: owner,
        repository: KugouListeningProfileRepository(
          api: MusicPlatformApi(
            server: _NoRemoteServer155(),
            client: transport,
          ),
          official: KugouOfficialApi(
            client: transport,
            currentIdentity: () => owner,
            device: () async => {
              'mid': 'fixture-mid',
              'uuid': 'fixture-uuid',
              'dfid': 'fixture-dfid',
            },
          ),
          clock: () => now,
        ),
      );
      addTearDown(reader.dispose);
      await reader.loadOverview();
      expect(reader.grade.error, isNull);
      expect(reader.grade.value?.level, 9);
      expect(reader.grade.value?.musicAge, isNotNull);
      expect(reader.medals.value?.total, 3);
      expect(
        reader.statistics(KugouListenPeriod.month, now).value?.totalSeconds,
        7200,
      );
      expect(paths.toSet(), {
        '/v1/listen_statistics',
        '/v1/listen_level/my_info',
        '/medal/v2/user_center/my_medals',
      });
      expect(paths.length, 3);
    },
  );
}
