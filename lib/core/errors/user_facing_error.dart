import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Converts internal exceptions into short, actionable Chinese copy.
///
/// UI code should never render [Object.toString] directly because platform and
/// network exceptions commonly contain English implementation details.
String userFacingErrorMessage(Object? error, {String fallback = '操作失败，请稍后重试'}) {
  if (error == null) return fallback;

  final raw = error.toString().trim();
  final lower = raw.toLowerCase();

  if (error is HandshakeException ||
      lower.contains('handshakeexception') ||
      lower.contains('during handshake') ||
      lower.contains('certificate_verify_failed') ||
      lower.contains('certificate verify failed') ||
      lower.contains('tls')) {
    return '安全连接建立失败，请切换网络后重试';
  }

  if (error is TimeoutException ||
      lower.contains('timeoutexception') ||
      lower.contains('timed out') ||
      lower.contains('timeout')) {
    return '网络响应超时，请稍后重试';
  }

  if (error is SocketException ||
      error is http.ClientException ||
      lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('connection reset') ||
      lower.contains('connection terminated') ||
      lower.contains('connection refused') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable')) {
    return '网络连接不可用，请检查网络后重试';
  }

  final message = raw.replaceFirst(
    RegExp(r'^(?:Exception|Error|StateError):\s*', caseSensitive: false),
    '',
  );
  if (RegExp(r'[\u3400-\u9fff]').hasMatch(message)) return message;

  return fallback;
}
