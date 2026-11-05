import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'music_network_diagnostics.dart';

/// Android's platform transport owns system DNS/TLS/proxy/VPN routing. It never
/// binds a physical Wi-Fi/mobile network, bypasses a VPN or disables TLS checks.
/// The embedded Kugou loopback and non-Android hosts retain a direct Dart client.
class MusicHttpClient extends http.BaseClient {
  MusicHttpClient({
    http.Client? fallback,
    bool? android,
    MethodChannel? channel,
  }) : _fallback =
           fallback ??
           IOClient(
             HttpClient()
               ..connectionTimeout = const Duration(seconds: 8)
               ..idleTimeout = const Duration(seconds: 5)
               ..findProxy = ((_) => 'DIRECT'),
           ),
       _android = android ?? (!kIsWeb && Platform.isAndroid),
       _channel = channel ?? const MethodChannel('com.mesting.music/network');
  final http.Client _fallback;
  final bool _android;
  final MethodChannel _channel;
  final Set<String> _pending = {};
  static int _sequence = 0;
  bool _closed = false;

  static bool systemHost(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (uri.host == 'music.163.com' ||
          uri.host.endsWith('.music.163.com') ||
          uri.host == 'kugou.com' ||
          uri.host.endsWith('.kugou.com'));
  String transportFor(Uri uri) =>
      _android &&
          systemHost(uri) &&
          // Full playlist DTOs can exceed the bounded platform-message body.
          // Keep their original Dart stream rather than cap an existing library.
          !uri.path.endsWith('/v6/playlist/detail')
      ? 'system'
      : 'dart';

  Future<void> _cancel(String id) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on Object {
      /* Cancellation is best effort when an engine is detaching. */
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client closed');
    if (transportFor(request.url) != 'system') return _fallback.send(request);
    final id = 'music-${++_sequence}';
    // Finalize exactly once. The clone is used only if the platform method is
    // absent, which proves no native request was dispatched; writes never fall
    // back after a timeout/network exception with an uncertain remote outcome.
    final body = await request.finalize().toBytes();
    var cancelled = false;
    _pending.add(id);
    final trigger = request is http.Abortable ? request.abortTrigger : null;
    if (trigger != null) {
      unawaited(
        trigger.then((_) {
          if (!_pending.contains(id)) return;
          cancelled = true;
          unawaited(_cancel(id));
        }),
      );
    }
    try {
      // Let an already-completed abort future run before native dispatch.
      await Future<void>.value();
      if (cancelled || _closed) throw http.RequestAbortedException();
      final result = await _channel.invokeMapMethod<String, Object?>('send', {
        'id': id,
        'url': request.url.toString(),
        'method': request.method,
        'headers': request.headers,
        'body': body,
      });
      if (cancelled || _closed) throw http.RequestAbortedException();
      if (result == null ||
          result['status'] is! int ||
          result['body'] is! Uint8List) {
        throw const MusicTransportException(MusicNetworkOutcome.format);
      }
      return http.StreamedResponse(
        Stream.value(result['body']! as Uint8List),
        result['status']! as int,
        request: request,
        headers: Map<String, String>.from(result['headers']! as Map),
      );
    } on MissingPluginException {
      if (cancelled || _closed) throw http.RequestAbortedException();
      final clone =
          http.AbortableRequest(
              request.method,
              request.url,
              abortTrigger: trigger,
            )
            ..headers.addAll(request.headers)
            ..followRedirects = request.followRedirects
            ..maxRedirects = request.maxRedirects
            ..bodyBytes = body;
      return _fallback.send(clone);
    } on PlatformException catch (error) {
      if (cancelled || error.code == 'cancelled') {
        throw http.RequestAbortedException();
      }
      throw MusicTransportException(switch (error.code) {
        'dns' => MusicNetworkOutcome.dns,
        'tls' => MusicNetworkOutcome.tls,
        'timeout' => MusicNetworkOutcome.timeout,
        'format' => MusicNetworkOutcome.format,
        _ => MusicNetworkOutcome.connection,
      });
    } finally {
      _pending.remove(id);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final id in _pending.toList()) {
      unawaited(_cancel(id));
    }
    _fallback.close();
  }
}

/// The deadline covers headers AND body. Abort closes the underlying request;
/// unlike Future.timeout alone, a failed SMS/login cannot continue silently and
/// publish a late cookie while the user is making another attempt.
Future<http.Response> sendMusicRequest({
  required http.Client client,
  required http.AbortableRequest Function(Future<void> abort) build,
  required String platform,
  required MusicNetworkOperation operation,
  Duration timeout = const Duration(seconds: 18),
  Future<void>? abortTrigger,
  bool retryRead = false,
  bool Function(http.Response response)? retryResponse,
}) async {
  var externallyCancelled = false;
  Completer<void>? activeAbort;
  if (abortTrigger != null) {
    unawaited(
      abortTrigger.then((_) {
        externallyCancelled = true;
        if (activeAbort?.isCompleted == false) activeAbort!.complete();
      }),
    );
  }
  for (var attempt = 1; ; attempt++) {
    await Future<void>.value();
    if (externallyCancelled) throw http.RequestAbortedException();
    final abort = activeAbort = Completer<void>();
    final watch = Stopwatch()..start();
    final request = build(abort.future);
    final transport = client is MusicHttpClient
        ? client.transportFor(request.url)
        : 'dart';
    try {
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            timeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException('music request deadline');
            },
          );
      if (externallyCancelled) throw http.RequestAbortedException();
      MusicNetworkDiagnostics.shared.record(
        platform: platform,
        operation: operation,
        outcome: response.statusCode >= 400
            ? MusicNetworkOutcome.http
            : MusicNetworkOutcome.success,
        elapsedMs: watch.elapsedMilliseconds,
        attempt: attempt,
        status: response.statusCode,
        transport: transport,
      );
      if (retryRead &&
          attempt == 1 &&
          {502, 503, 504}.contains(response.statusCode) &&
          (retryResponse?.call(response) ?? true)) {
        continue;
      }
      return response;
    } on Object catch (error) {
      if (!abort.isCompleted) abort.complete();
      final outcome = externallyCancelled
          ? MusicNetworkOutcome.cancelled
          : classifyMusicNetworkError(error);
      MusicNetworkDiagnostics.shared.record(
        platform: platform,
        operation: operation,
        outcome: outcome,
        elapsedMs: watch.elapsedMilliseconds,
        attempt: attempt,
        transport: transport,
      );
      if (outcome == MusicNetworkOutcome.cancelled) {
        throw http.RequestAbortedException();
      }
      if (retryRead &&
          attempt == 1 &&
          {
            MusicNetworkOutcome.connection,
            MusicNetworkOutcome.dns,
            MusicNetworkOutcome.timeout,
          }.contains(outcome)) {
        continue;
      }
      throw MusicTransportException(outcome);
    }
  }
}
