import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

// Flutter's test binding normally replaces HttpClient with a synthetic 400.
// Calling the base implementation creates real sockets only in this fixture.
class _RealHttp extends HttpOverrides {}

class PayloadExchange {
  PayloadExchange(this.uri, this.tag, this.start, this.end, this.headers);
  final Uri uri;
  final String tag;
  final int start, end;
  final Map<String, String> headers;
  int offeredBytes = 0;
  bool truncated = false, disconnected = false, finished = false;
}

/// Real loopback HTTP payloads. Logical HTTPS origins are mapped here by the
/// test-only adapter; this verifies neither TLS nor native RTC/public networks.
class LoopbackPayload {
  LoopbackPayload(this.bytes);
  final Uint8List bytes;
  final exchanges = <PayloadExchange>[];
  final errors = <String>[];
  final _handlers = <Future<void>>{};
  final firstTruncation = Completer<void>();
  late final HttpServer _server;
  bool truncateFirstPiece = false;
  int active = 0, peakActive = 0;
  Duration headerDelay = const Duration(milliseconds: 10);
  Duration chunkDelay = const Duration(milliseconds: 4);
  Duration bootstrapPause = const Duration(milliseconds: 300);

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/payload');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) {
      late final Future<void> handler;
      handler = _serve(request).whenComplete(() => _handlers.remove(handler));
      _handlers.add(handler);
    });
  }

  Future<void> _serve(HttpRequest request) async {
    active++;
    if (active > peakActive) peakActive = active;
    PayloadExchange? exchange;
    try {
      final rawRange = request.headers.value('range');
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(rawRange ?? '');
      if (rawRange != null && match == null) {
        throw StateError('Unexpected fixture range');
      }
      final start = match == null ? 0 : int.parse(match[1]!);
      final end = match == null || match[2]!.isEmpty
          ? bytes.length - 1
          : int.parse(match[2]!);
      if (start < 0 || end < start || end >= bytes.length) {
        throw StateError('Fixture range out of bounds');
      }
      final headers = <String, String>{};
      request.headers.forEach((key, values) => headers[key] = values.join(','));
      exchange = PayloadExchange(
        Uri.parse(request.uri.queryParameters['source']!),
        request.uri.queryParameters['task'] ?? '',
        start,
        end,
        headers,
      );
      exchanges.add(exchange);
      final current = exchange;
      unawaited(
        request.response.done.then<void>(
          (_) {},
          onError: (Object _) {
            current.disconnected = true;
          },
        ),
      );
      await Future<void>.delayed(headerDelay);
      request.response.statusCode = match == null ? 200 : 206;
      request.response.contentLength = end - start + 1;
      request.response.headers.set('etag', '"release-test"');
      request.response.headers.set('x-download-session-id', '0123456789abcdef');
      if (match != null) {
        request.response.headers.set(
          'content-range',
          'bytes $start-$end/${bytes.length}',
        );
      }
      final bounded = end - start + 1 <= 1048576;
      if (truncateFirstPiece && bounded && !firstTruncation.isCompleted) {
        current.truncated = true;
        final count = (end - start + 1).clamp(1, 32768);
        // Detach before sending headers. This creates an incomplete wire body
        // without triggering HttpResponse's own Content-Length validation.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.add(
          utf8.encode(
            'HTTP/1.1 206 Partial Content\r\n'
            'Content-Length: ${end - start + 1}\r\n'
            'Content-Range: bytes $start-$end/${bytes.length}\r\n'
            'ETag: "release-test"\r\nConnection: close\r\n\r\n',
          ),
        );
        socket.add(Uint8List.sublistView(bytes, start, start + count));
        current.offeredBytes += count;
        await socket.flush();
        socket.destroy();
        firstTruncation.complete();
        return;
      }
      for (var offset = start; offset <= end;) {
        if (current.disconnected) return;
        final next = (offset + 65536).clamp(offset, end + 1);
        request.response.add(Uint8List.sublistView(bytes, offset, next));
        current.offeredBytes += next - offset;
        await request.response.flush();
        offset = next;
        if (start == 0 && end == bytes.length - 1 && offset == 1048576) {
          // Leave a deterministic handoff boundary for the actual SDK writer.
          await Future<void>.delayed(bootstrapPause);
        }
        await Future<void>.delayed(chunkDelay);
      }
    } on SocketException {
      exchange?.disconnected = true;
    } on HttpException {
      exchange?.disconnected = true;
    } catch (error) {
      errors.add(error.toString());
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
      exchange?.finished = true;
      active--;
    }
  }

  Future<void> waitIdle() async {
    final deadline = Stopwatch()..start();
    while (active != 0 && deadline.elapsed < const Duration(seconds: 4)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (active != 0) throw StateError('Payload handlers remained active');
  }

  Future<void> close() async {
    await _server.close(force: true);
    await Future.wait(_handlers.toList());
  }
}

class LoopbackPayloadAdapter implements HttpClientAdapter {
  LoopbackPayloadAdapter(this.origin, {this.tag = ''}) {
    _transport = IOHttpClientAdapter(
      createHttpClient: () {
        final client = _RealHttp().createHttpClient(null);
        client.findProxy = (_) => 'DIRECT';
        return client;
      },
    );
  }
  final LoopbackPayload origin;
  final String tag;
  late final IOHttpClientAdapter _transport;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final local = origin.uri.replace(
      queryParameters: {'source': options.uri.toString(), 'task': tag},
    );
    return _transport.fetch(
      options.copyWith(
        path: local.toString(),
        baseUrl: '',
        queryParameters: {},
      ),
      requestStream,
      cancelFuture,
    );
  }

  @override
  void close({bool force = false}) => _transport.close(force: force);
}
