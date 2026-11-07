import 'dart:async';
import 'package:http/http.dart' as http;

/// A public, stable failure reason. Raw bodies, URLs and exception messages
/// must never enter the user-copyable source diagnostics.
class NeteaseSourceFailure implements Exception {
  const NeteaseSourceFailure(this.reason, {this.httpStatus});
  final String reason;
  final int? httpStatus;
}

/// Each provider attempt owns an abort scope, while the parent HTTP pool stays
/// shared. Closing a timed-out attempt cancels its sockets and prevents queued
/// follow-up requests; it cannot close another playback/download's transport.
class NeteaseSourceClient extends http.BaseClient {
  NeteaseSourceClient(
    this.inner, {
    this.timeout = const Duration(seconds: 10),
    this.maximumBytes = 1024 * 1024,
  });
  final http.Client inner;
  final Duration timeout;
  final int maximumBytes;
  final Set<Completer<void>> _pending = {};
  bool _closed = false;
  bool get isClosed => _closed;
  final _closeListeners = <void Function()>[];

  /// Native/script adapters share this attempt's cancellation without owning
  /// or closing the resolver's shared HTTP pool.
  void onClose(void Function() callback) {
    if (_closed) {
      callback();
    } else {
      _closeListeners.add(callback);
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.RequestAbortedException();
    final abort = Completer<void>();
    _pending.add(abort);
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    final timer = Timer(timeout, cancel);
    void finish() {
      timer.cancel();
      _pending.remove(abort);
    }

    try {
      final outgoing =
          http.AbortableRequest(
              request.method,
              request.url,
              abortTrigger: abort.future,
            )
            ..headers.addAll(request.headers)
            ..followRedirects = request.followRedirects
            ..maxRedirects = request.maxRedirects
            ..persistentConnection = request.persistentConnection
            ..bodyBytes = await request.finalize().toBytes();
      if (_closed || abort.isCompleted) throw http.RequestAbortedException();
      final response = await inner.send(outgoing);
      Stream<List<int>> boundedBody() async* {
        var bytes = 0;
        var complete = false;
        try {
          await for (final chunk in response.stream) {
            bytes += chunk.length;
            if (bytes > maximumBytes) {
              throw const NeteaseSourceFailure('response_too_large');
            }
            yield chunk;
          }
          complete = true;
        } finally {
          // A Range-ignoring CDN must stop when the probe has enough bytes.
          if (!complete) cancel();
          finish();
        }
      }

      return http.StreamedResponse(
        boundedBody(),
        response.statusCode,
        headers: response.headers,
        request: outgoing,
        isRedirect: response.isRedirect,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      cancel();
      finish();
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final callback in _closeListeners) {
      callback();
    }
    _closeListeners.clear();
    for (final abort in _pending.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    // The resolver owns [inner], not this individual source attempt.
    super.close();
  }
}
