import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'lx_anonymous_transport.dart';
import 'lx_source_catalog.dart';
import 'netease_source_transport.dart';

abstract interface class LxScriptEngine {
  Future<String> resolve(
    LxMusicSource source,
    Map<String, Object?> song,
    String quality,
  );
  void dispose();
}

typedef LxEngineFactory = LxScriptEngine Function(http.Client client);

/// Share the two-worker budget across account/settings provider generations.
final productionLxEnginePool = LxEnginePool();

/// Two short-lived renderers at most. Queue cancellation is checked before a
/// renderer is created, so stale picker/playback work cannot create eleven
/// WebViews after its owning page/account has already gone away.
class LxEnginePool {
  int _running = 0;
  final _waiting = <Completer<void>>[];
  Future<T> run<T>(Future<T> Function() action, bool Function() current) async {
    while (_running >= 2) {
      final wake = Completer<void>();
      _waiting.add(wake);
      await wake.future;
      if (!current()) {
        throw const NeteaseSourceFailure('request_cancelled_or_timed_out');
      }
    }
    if (!current()) {
      throw const NeteaseSourceFailure('request_cancelled_or_timed_out');
    }
    _running++;
    try {
      return await action();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}

/// The WebView runs only Mesting's small host; third-party code executes in a
/// terminable Worker. Neither an infinite loop nor a script timer can outlive
/// the per-source deadline. Ordinary networking and remote scripts are denied
/// by CSP; all HTTP passes through [LxAnonymousTransport].
class WebViewLxScriptEngine implements LxScriptEngine {
  WebViewLxScriptEngine(this.client) {
    if (client is NeteaseSourceClient) {
      (client as NeteaseSourceClient).onClose(dispose);
    }
  }
  final http.Client client;
  WebViewController? _controller;
  final _ready = Completer<List<String>>();
  final _result = Completer<String>();
  bool _disposed = false;
  int _requests = 0;
  final _aborted = <int>{};
  static final _assets = <String, Future<String>>{};
  static Future<String> _asset(String path) =>
      _assets.putIfAbsent(path, () => rootBundle.loadString(path));

  void _fail() {
    if (!_ready.isCompleted) {
      _ready.completeError(
        const NeteaseSourceFailure('lx_initialization_failed'),
      );
    }
    if (!_result.isCompleted) {
      _result.completeError(
        const NeteaseSourceFailure('lx_source_unavailable'),
      );
    }
  }

  @override
  Future<String> resolve(
    LxMusicSource source,
    Map<String, Object?> song,
    String quality,
  ) async {
    // Install error handlers immediately, including initialization failures
    // before resolve() starts awaiting its second-stage result.
    unawaited(_ready.future.then<void>((_) {}, onError: (Object _) {}));
    unawaited(_result.future.then<void>((_) {}, onError: (Object _) {}));
    final deadline = Timer(const Duration(seconds: 9), dispose);
    try {
      final loaded = await Future.wait([
        _asset(source.asset),
        _asset('third_party/lx_music_source/bridge.js'),
        _asset('third_party/lx_music_source/host.js'),
        _asset('third_party/lx_music_source/crypto-js/crypto-js.js'),
      ]);
      if (_disposed) {
        throw const NeteaseSourceFailure('request_cancelled_or_timed_out');
      }
      final page = Completer<void>();
      final controller = WebViewController();
      _controller = controller;
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'MestingLx',
        onMessageReceived: (message) => _message(message.message),
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              request.url == 'about:blank' ||
                  request.url.startsWith('data:text/html')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) {
            if (!page.isCompleted) page.complete();
          },
        ),
      );
      await controller.loadHtmlString(
        '<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\' \'unsafe-eval\'; worker-src blob:; connect-src \'none\'; base-uri \'none\'; form-action \'none\'"></head><body></body></html>',
      );
      await Future.any([page.future, _ready.future.then<void>((_) {})]);
      if (_disposed) {
        throw const NeteaseSourceFailure('request_cancelled_or_timed_out');
      }
      await controller.runJavaScript(loaded[2]);
      await controller.runJavaScript(
        'MestingLxHost.start(${jsonEncode(loaded[0])},${jsonEncode(loaded[1])},${jsonEncode(loaded[3])});',
      );
      final qualities = await _ready.future;
      if (!qualities.contains(quality)) {
        throw const NeteaseSourceFailure('requested_quality_unavailable');
      }
      if (_disposed) {
        throw const NeteaseSourceFailure('request_cancelled_or_timed_out');
      }
      await controller.runJavaScript(
        'MestingLxHost.resolve(${jsonEncode(song)},${jsonEncode(quality)});',
      );
      return await _result.future;
    } finally {
      deadline.cancel();
      dispose();
    }
  }

  void _message(String text) {
    if (_disposed || text.length > 256 * 1024) return;
    try {
      final message = jsonDecode(text);
      if (message is! Map) return;
      switch (message['kind']) {
        case 'ready':
          if (!_ready.isCompleted) {
            _ready.complete(
              (message['qualities'] as List? ?? [])
                  .whereType<String>()
                  .toList(),
            );
          }
        case 'resolved':
          if (!_result.isCompleted) {
            _result.complete(
              message['url'] is String ? message['url'] as String : '',
            );
          }
        case 'failed':
          _fail();
        case 'abort':
          if (message['id'] is int) _aborted.add(message['id'] as int);
        case 'request':
          if (++_requests > 40 ||
              message['id'] is! int ||
              message['url'] is! String) {
            _fail();
            return;
          }
          unawaited(
            _request(
              message['id'] as int,
              message['url'] as String,
              message['options'] is Map ? message['options'] as Map : {},
            ),
          );
      }
    } catch (_) {
      _fail();
    }
  }

  Future<void> _request(int id, String url, Map options) async {
    Object? response;
    var error = false;
    try {
      response = await LxAnonymousTransport(client).request(url, options);
    } catch (_) {
      error = true;
    }
    final controller = _controller;
    if (_disposed || _aborted.contains(id) || controller == null) return;
    try {
      await controller.runJavaScript(
        'MestingLxHost.respond($id,$error,${jsonEncode(response)});',
      );
    } catch (_) {
      if (!_disposed) _fail();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fail();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      // terminate() works even if the source's Worker is stuck in synchronous
      // code. Clear the document too; never retain a hidden playback browser.
      unawaited(() async {
        try {
          await controller.runJavaScript('MestingLxHost.dispose();');
        } catch (_) {
          /* Page may not have initialized. */
        }
        try {
          await controller.removeJavaScriptChannel('MestingLx');
          await controller.loadHtmlString('<html></html>');
        } catch (_) {
          /* Platform teardown. */
        }
      }());
    }
  }
}
