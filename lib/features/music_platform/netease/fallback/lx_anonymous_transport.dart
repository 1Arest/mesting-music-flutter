import 'dart:convert';
import 'package:http/http.dart' as http;
import 'netease_source_transport.dart';

/// HTTP is supplied explicitly instead of giving a script a browser session.
/// This object has no access to platform repositories, cookies or token stores.
class LxAnonymousTransport {
  LxAnonymousTransport(this.client);
  final http.Client client;

  static bool publicUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        !host.contains('.') ||
        host.contains(':')) {
      return false;
    }
    final octets = host.split('.').map(int.tryParse).toList();
    if (octets.length == 4 && octets.every((x) => x != null)) {
      final a = octets[0]!, b = octets[1]!;
      if (octets.any((x) => x! < 0 || x > 255) ||
          a == 0 ||
          a == 10 ||
          a == 127 ||
          a >= 224 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 100 && b >= 64 && b <= 127) ||
          (a == 198 && (b == 18 || b == 19))) {
        return false;
      }
    }
    return true;
  }

  static Map<String, String> anonymousHeaders(Object? supplied) {
    if (supplied is! Map) return {};
    // Public source-specific keys remain in their own adapter request only.
    // Browser cookies, proxy auth, referrer credentials and hop-by-hop state
    // must not escape through this bridge or cross-host redirects.
    const blocked = {
      'cookie',
      'cookie2',
      'authorization',
      'proxy-authorization',
      'host',
      'connection',
      'content-length',
      'set-cookie',
      'origin',
    };
    return {
      for (final item in supplied.entries)
        if (item.key is String &&
            item.value is String &&
            !blocked.contains((item.key as String).toLowerCase()) &&
            RegExp(r'^[A-Za-z0-9-]{1,80}$').hasMatch(item.key) &&
            (item.value as String).length < 4096 &&
            !(item.value as String).contains(RegExp(r'[\r\n]')))
          item.key as String: item.value as String,
    };
  }

  Future<Map<String, Object?>> request(String url, Map options) async {
    if (url.length > 16384) throw const NeteaseSourceFailure('lx_url_invalid');
    var uri = Uri.tryParse(url);
    if (uri == null || !publicUri(uri)) {
      throw const NeteaseSourceFailure('lx_url_invalid');
    }
    var method = '${options['method'] ?? 'GET'}'.toUpperCase();
    if (!{'GET', 'POST', 'HEAD'}.contains(method)) {
      throw const NeteaseSourceFailure('lx_method_rejected');
    }
    var headers = anonymousHeaders(options['headers']);
    String? body;
    if (options['form'] is Map) {
      body = Uri(
        queryParameters: {
          for (final entry in (options['form'] as Map).entries)
            '${entry.key}': '${entry.value}',
        },
      ).query;
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    } else if (options['body'] != null || options['data'] != null) {
      final data = options['body'] ?? options['data'];
      body = data is String ? data : jsonEncode(data);
      if (data is! String) headers['Content-Type'] = 'application/json';
    }
    if ((body?.length ?? 0) > 128 * 1024) {
      throw const NeteaseSourceFailure('lx_body_too_large');
    }
    for (var hop = 0; hop < 4; hop++) {
      if (!publicUri(uri!)) {
        throw const NeteaseSourceFailure('lx_redirect_rejected');
      }
      final outgoing = http.Request(method, uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (body != null) outgoing.body = body;
      final response = await client.send(outgoing);
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.take(1).drain<void>();
        if (location == null) {
          throw const NeteaseSourceFailure('lx_redirect_rejected');
        }
        final target = uri.resolve(location);
        if (target.origin != uri.origin) headers = {};
        uri = target;
        if (response.statusCode == 303 || response.statusCode == 302) {
          method = 'GET';
          body = null;
        }
        continue;
      }
      final data = <int>[];
      await for (final chunk in response.stream) {
        if (data.length + chunk.length > 512 * 1024) {
          throw const NeteaseSourceFailure('response_too_large');
        }
        data.addAll(chunk);
      }
      final text = utf8.decode(data, allowMalformed: true);
      Object? decoded = text;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        /* Text APIs are supported too. */
      }
      return {
        'statusCode': response.statusCode,
        'headers': {
          for (final e in response.headers.entries)
            if (e.key.toLowerCase() != 'set-cookie') e.key: e.value,
        },
        'body': decoded,
      };
    }
    throw const NeteaseSourceFailure('lx_redirect_rejected');
  }
}
