import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AbortableJsonClient {
  const AbortableJsonClient(this.client);

  final http.Client client;

  Future<Object?> get(
    Uri uri, {
    Future<void>? abortTrigger,
    Duration timeout = const Duration(seconds: 9),
  }) async {
    final requestAbort = Completer<void>();
    var timedOut = false;

    final timer = Timer(timeout, () {
      timedOut = true;
      if (!requestAbort.isCompleted) {
        requestAbort.complete();
      }
    });
    abortTrigger?.then((_) {
      if (!requestAbort.isCompleted) {
        requestAbort.complete();
      }
    });

    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: requestAbort.future,
      );
      request.headers['accept'] = 'application/json';
      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('HTTP ${response.statusCode}', uri);
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on http.RequestAbortedException {
      if (timedOut) {
        throw TimeoutException('请求超时', timeout);
      }
      rethrow;
    } finally {
      timer.cancel();
    }
  }
}
