import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Per-request Android policy with streamed Dart bodies. Large libraries, cache
/// audio and uploads do not pass through the small JSON method-channel limit.
/// The actual socket still uses the OS default route, including its VPN.
class MusicSystemNetwork {
  MusicSystemNetwork({bool? android, MethodChannel? channel})
    : _android = android ?? (!kIsWeb && Platform.isAndroid),
      _channel = channel ?? const MethodChannel('com.mesting.music/network');
  static final shared = MusicSystemNetwork();
  final bool _android;
  final MethodChannel _channel;
  final _lookups = <String, Future<List<InternetAddress>>>{};

  static bool local(Uri uri) =>
      const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host);

  Future<MusicNetworkPolicy> policy(Uri uri) async {
    if (!_android || local(uri)) return const MusicNetworkPolicy(0, 'DIRECT');
    // This precedes request finalization/dispatch, so retrying a missing plugin
    // cannot duplicate a remote SMS, login or write. No permanent missing cache.
    for (var attempt = 0; ; attempt++) {
      try {
        final value = await _channel
            .invokeMapMethod<String, Object?>('policy', {'url': uri.toString()})
            .timeout(const Duration(seconds: 8));
        if (value?['generation'] is! int || value?['proxy'] is! String) {
          throw const FormatException('Invalid system network policy');
        }
        return MusicNetworkPolicy(
          value!['generation']! as int,
          value['proxy']! as String,
        );
      } on MissingPluginException {
        if (attempt >= 15) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<List<InternetAddress>> _lookup(String host, int generation) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return [literal];
    if (!_android || host == 'localhost') return InternetAddress.lookup(host);
    final key = '$generation:$host';
    var operation = _lookups[key];
    if (operation == null) {
      operation = _channel
          .invokeListMethod<String>('resolve', {'host': host})
          .then((rows) {
            final addresses = (rows ?? const [])
                .map(InternetAddress.tryParse)
                .nonNulls
                .toList();
            if (addresses.isEmpty) {
              throw const SocketException('DNS returned no addresses');
            }
            return addresses;
          });
      _lookups[key] = operation;
      final current = operation;
      unawaited(
        operation.then<void>(
          (_) {
            if (identical(_lookups[key], current)) _lookups.remove(key);
          },
          onError: (Object _, StackTrace stack) {
            if (identical(_lookups[key], current)) _lookups.remove(key);
          },
        ),
      );
    }
    return operation.timeout(const Duration(seconds: 8));
  }

  HttpClient client(MusicNetworkPolicy policy) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 5)
      ..findProxy = ((uri) => local(uri) ? 'DIRECT' : policy.proxy);
    if (_android) {
      client.connectionFactory = (uri, proxyHost, proxyPort) async {
        final host = proxyHost ?? uri.host;
        final port = proxyPort ?? uri.port;
        final addresses = await _lookup(host, policy.generation);
        return happyEyeballsConnect(addresses, port);
      };
    }
    return client;
  }

  Future<HttpClient> cacheClient(Uri uri) async => client(await policy(uri));
}

class MusicNetworkPolicy {
  const MusicNetworkPolicy(this.generation, this.proxy);
  final int generation;
  final String proxy;
}

/// Race OS-provided IPv6/IPv4 addresses with a short stagger. DNS and routing
/// remain unchanged; only a dead family stops blocking the other for seconds.
/// Cancellation closes every losing socket, including late connect completions.
ConnectionTask<Socket> happyEyeballsConnect(
  List<InternetAddress> addresses,
  int port, {
  Future<ConnectionTask<Socket>> Function(InternetAddress, int)? start,
  Duration stagger = const Duration(milliseconds: 200),
}) {
  final result = Completer<Socket>();
  final tasks = <ConnectionTask<Socket>>[];
  final timers = <Timer>[];
  var remaining = addresses.length;
  final v4 = addresses
      .where((a) => a.type == InternetAddressType.IPv4)
      .toList();
  final v6 = addresses
      .where((a) => a.type == InternetAddressType.IPv6)
      .toList();
  final ordered = <InternetAddress>[];
  final firstV6 =
      addresses.isNotEmpty && addresses.first.type == InternetAddressType.IPv6;
  for (var i = 0; i < (v4.length > v6.length ? v4.length : v6.length); i++) {
    if (firstV6 && i < v6.length) ordered.add(v6[i]);
    if (i < v4.length) ordered.add(v4[i]);
    if (!firstV6 && i < v6.length) ordered.add(v6[i]);
  }
  void closeLosers([ConnectionTask<Socket>? winner]) {
    for (final timer in timers) {
      timer.cancel();
    }
    for (final task in tasks) {
      if (!identical(task, winner)) task.cancel();
    }
  }

  void cancel() {
    if (!result.isCompleted) {
      result.completeError(const SocketException('Connection cancelled'));
    }
    closeLosers();
  }

  Future<void> attempt(InternetAddress address) async {
    if (result.isCompleted) return;
    try {
      final task = await (start ?? Socket.startConnect)(address, port);
      tasks.add(task);
      if (result.isCompleted) {
        task.cancel();
        unawaited(
          task.socket.then<void>(
            (socket) => socket.destroy(),
            onError: (Object _, StackTrace stack) {},
          ),
        );
        return;
      }
      final socket = await task.socket;
      if (result.isCompleted) {
        socket.destroy();
        return;
      }
      result.complete(socket);
      closeLosers(task);
    } on Object catch (error, stack) {
      remaining--;
      if (!result.isCompleted && remaining == 0) {
        result.completeError(error, stack);
      }
    }
  }

  if (ordered.isEmpty) {
    result.completeError(const SocketException('DNS returned no addresses'));
  } else {
    unawaited(attempt(ordered.first));
    for (var i = 1; i < ordered.length; i++) {
      timers.add(Timer(stagger * i, () => unawaited(attempt(ordered[i]))));
    }
  }
  final deadline = Timer(const Duration(seconds: 8), cancel);
  unawaited(
    result.future.then<void>(
      (_) => deadline.cancel(),
      onError: (Object _, StackTrace stack) {
        deadline.cancel();
        closeLosers();
      },
    ),
  );
  return ConnectionTask.fromSocket(result.future, cancel);
}

class SystemMusicIoClient extends http.BaseClient {
  SystemMusicIoClient({MusicSystemNetwork? network})
    : _network = network ?? MusicSystemNetwork.shared;
  final MusicSystemNetwork _network;
  final _clients = <String, (HttpClient, IOClient)>{};
  int _generation = -1;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var policy = await _network.policy(request.url);
    if (_closed) throw http.ClientException('Client closed');
    if (!MusicSystemNetwork.local(request.url)) {
      if (policy.generation < _generation) {
        policy = await _network.policy(request.url);
      }
      if (policy.generation != _generation) {
        // Retire idle old-route connections; existing streams can finish. Never
        // delete a session or replay an in-flight mutation on a network change.
        for (final pair in _clients.values) {
          pair.$1.close(force: false);
        }
        _clients.clear();
        _generation = policy.generation;
      }
    }
    if (_closed) throw http.ClientException('Client closed');
    final key = '${policy.generation}:${policy.proxy}';
    final pair = _clients.putIfAbsent(key, () {
      final client = _network.client(policy);
      return (client, IOClient(client));
    });
    return pair.$2.send(request);
  }

  @override
  void close() {
    _closed = true;
    for (final pair in _clients.values) {
      pair.$1.close(force: true);
    }
    _clients.clear();
  }
}
