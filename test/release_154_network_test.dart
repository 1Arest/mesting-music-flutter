import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/core/network/system_music_io_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalHttpOverrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = null);
  tearDownAll(() => HttpOverrides.global = originalHttpOverrides);
  const channel = MethodChannel('com.mesting.music/network');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'large streamed response keeps all bytes beyond the JSON bridge limit',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      const size = 18 * 1024 * 1024 + 17;
      server.listen((request) async {
        request.response.contentLength = size;
        final chunk = List<int>.generate(65536, (i) => i % 251);
        for (var offset = 0; offset < size; offset += chunk.length) {
          request.response.add(
            offset + chunk.length <= size
                ? chunk
                : chunk.sublist(0, size - offset),
          );
        }
        await request.response.close();
      });
      final client = SystemMusicIoClient(
        network: MusicSystemNetwork(android: false),
      );
      addTearDown(client.close);
      final reply = await client.send(
        http.Request('GET', Uri.parse('http://127.0.0.1:${server.port}/large')),
      );
      var bytes = 0, checksum = 0;
      await for (final chunk in reply.stream) {
        checksum += chunk.fold<int>(0, (sum, value) => sum + value);
        bytes += chunk.length;
      }
      expect(bytes, size);
      final fullChunkSum = List<int>.generate(
        65536,
        (i) => i % 251,
      ).fold<int>(0, (sum, value) => sum + value);
      expect(checksum, fullChunkSum * (size ~/ 65536) + 136);
    },
  );

  test(
    'system proxy follows generation changes without replaying a POST',
    () async {
      final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => first.close(force: true));
      addTearDown(() => second.close(force: true));
      final seen = <String>[];
      void respond(HttpServer server, String label) =>
          server.listen((request) async {
            expect(request.uri.host, 'route.fixture.test');
            expect(await request.fold<List<int>>([], (a, b) => a..addAll(b)), [
              1,
              2,
              3,
              4,
            ]);
            seen.add(label);
            request.response.write(label);
            await request.response.close();
          });
      respond(first, 'first');
      respond(second, 'second');
      var generation = 1;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'policy');
        return {
          'generation': generation,
          'proxy':
              'PROXY 127.0.0.1:${generation == 1 ? first.port : second.port}',
        };
      });
      final client = SystemMusicIoClient(
        network: MusicSystemNetwork(android: true),
      );
      addTearDown(client.close);
      final uri = Uri.parse('http://route.fixture.test/mutation');
      expect((await client.post(uri, body: [1, 2, 3, 4])).body, 'first');
      generation = 2;
      expect((await client.post(uri, body: [1, 2, 3, 4])).body, 'second');
      expect(seen, ['first', 'second']);
    },
  );

  test(
    'Dart streams use Android resolver addresses while preserving the HTTP host',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(
          request.headers.value('host'),
          'dns.fixture.test:${server.port}',
        );
        request.response.write('resolved');
        await request.response.close();
      });
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'policy') {
          return {'generation': 7, 'proxy': 'DIRECT'};
        }
        expect(call.arguments['host'], 'dns.fixture.test');
        return ['127.0.0.1'];
      });
      final client = SystemMusicIoClient(
        network: MusicSystemNetwork(android: true),
      );
      addTearDown(client.close);
      expect(
        (await client.get(
          Uri.parse('http://dns.fixture.test:${server.port}/'),
        )).body,
        'resolved',
      );
      expect(calls, ['policy', 'resolve']);
    },
  );

  test(
    'a stalled IPv6 attempt cannot delay usable IPv4 and losing sockets cancel',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((socket) => socket.destroy());
      addTearDown(() async {
        await subscription.cancel();
        await server.close();
      });
      final stalled = Completer<Socket>();
      var cancelled = false;
      final watch = Stopwatch()..start();
      final task = happyEyeballsConnect(
        [InternetAddress.loopbackIPv6, InternetAddress.loopbackIPv4],
        server.port,
        stagger: const Duration(milliseconds: 25),
        start: (address, port) async {
          if (address.type == InternetAddressType.IPv6) {
            return ConnectionTask.fromSocket(stalled.future, () {
              cancelled = true;
              if (!stalled.isCompleted) {
                stalled.completeError(
                  const SocketException('cancelled fixture'),
                );
              }
            });
          }
          return Socket.startConnect(address, port);
        },
      );
      final socket = await task.socket;
      socket.destroy();
      expect(watch.elapsedMilliseconds, lessThan(1500));
      expect(cancelled, isTrue);
    },
  );

  test('cancelled address race never starts its delayed alternative', () async {
    final stalled = Completer<Socket>();
    var calls = 0;
    final task = happyEyeballsConnect(
      [InternetAddress.loopbackIPv6, InternetAddress.loopbackIPv4],
      1,
      stagger: const Duration(milliseconds: 50),
      start: (_, port) async {
        calls++;
        return ConnectionTask.fromSocket(stalled.future, () {
          if (!stalled.isCompleted) {
            stalled.completeError(const SocketException('cancelled fixture'));
          }
        });
      },
    );
    final outcome = expectLater(task.socket, throwsA(isA<SocketException>()));
    await Future<void>.delayed(Duration.zero);
    task.cancel();
    await outcome;
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(calls, 1);
  });
}
