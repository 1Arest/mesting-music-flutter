import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum MusicNetworkOperation {
  playbackUrl,
  audio,
  sms,
  login,
  qr,
  restore,
  storage,
  read,
  other,

  // Reward stages use fixed names so an exported receipt can distinguish a
  // qualification failure from a submitted claim without exposing its payload.
  rewardBalance,
  rewardProgress,
  rewardQualification,
  rewardClaim,
  rewardSignIn,
}

enum MusicNetworkOutcome {
  success,
  dns,
  connection,
  tls,
  timeout,
  http,
  business,
  format,
  cancelled,
  storage,
}

/// Closed vocabularies keep authentication diagnostics useful without exporting
/// raw platform exceptions, key names, credential fields or request payloads.
enum MusicDiagnosticPhase {
  credentialValidate,
  storageRead,
  storageDecode,
  storageWrite,
  storageVerify,
  recoveryWrite,
  accountPublish,
  networkPrepare,
  networkSend,
  responseDecode,
  responseValidate,
}

enum MusicFailureFamily {
  timeout,
  keyUnavailable,
  keyInvalidated,
  decrypt,
  io,
  pluginUnavailable,
  format,
  credentialIncomplete,
  unknown,
}

/// Only fixed categories and numeric receipts enter the diagnostic buffer.
/// URLs, cookies, account IDs, phone numbers and raw exceptions never enter it.
class MusicNetworkDiagnostics extends ChangeNotifier {
  static final shared = MusicNetworkDiagnostics();
  final List<Map<String, Object>> _rows = [];
  List<Map<String, Object>> get rows => List.unmodifiable(_rows);

  void record({
    required String platform,
    required MusicNetworkOperation operation,
    required MusicNetworkOutcome outcome,
    int elapsedMs = 0,
    int attempt = 1,
    int? status,
    String transport = 'dart',
    MusicDiagnosticPhase? phase,
    MusicFailureFamily? family,
  }) {
    _rows.add(
      Map.unmodifiable({
        'at': DateTime.now().toUtc().toIso8601String(),
        'platform': {'netease', 'kugou', 'audio'}.contains(platform)
            ? platform
            : 'other',
        'operation': operation.name,
        'outcome': outcome.name,
        'elapsedMs': elapsedMs.clamp(0, 3600000),
        'attempt': attempt.clamp(1, 2),
        'transport':
            {
              'system',
              'dart',
              'nativeAudio',
              'cache',
              'local',
            }.contains(transport)
            ? transport
            : 'other',
        if (status != null && status >= 0 && status <= 999999) 'status': status,
        if (phase != null) 'phase': phase.name,
        if (family != null) 'family': family.name,
      }),
    );
    if (_rows.length > 80) _rows.removeAt(0);
    notifyListeners();
  }

  String export() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'schema': 2, 'memoryOnly': true, 'events': _rows});
  void clear() {
    _rows.clear();
    notifyListeners();
  }
}

MusicNetworkOutcome classifyMusicNetworkError(Object error) {
  if (error is http.RequestAbortedException) {
    return MusicNetworkOutcome.cancelled;
  }
  if (error is MusicTransportException) return error.outcome;
  if (error is TimeoutException) return MusicNetworkOutcome.timeout;
  if (error is HandshakeException || error is TlsException) {
    return MusicNetworkOutcome.tls;
  }
  // Inspect for classification only; the raw value is never persisted/displayed.
  final text = error.toString().toLowerCase();
  if (text.contains('failed host lookup') ||
      text.contains('unknownhost') ||
      text.contains('name or service not known') ||
      text.contains('dns')) {
    return MusicNetworkOutcome.dns;
  }
  if (text.contains('handshake') ||
      text.contains('certificate') ||
      text.contains('ssl')) {
    return MusicNetworkOutcome.tls;
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return MusicNetworkOutcome.timeout;
  }
  if (error is FormatException) return MusicNetworkOutcome.format;
  return MusicNetworkOutcome.connection;
}

String musicNetworkMessage(MusicNetworkOutcome outcome) => switch (outcome) {
  MusicNetworkOutcome.dns => '音乐服务地址解析失败，请重试；可在连接诊断中查看记录',
  MusicNetworkOutcome.tls => '与音乐服务的安全连接失败，请重试',
  MusicNetworkOutcome.timeout => '音乐服务响应超时，请重试；已停止本次等待',
  MusicNetworkOutcome.http => '音乐服务暂时不可用，请稍后重试',
  MusicNetworkOutcome.format => '音乐服务返回格式异常，请稍后重试',
  MusicNetworkOutcome.cancelled => '本次操作已取消',
  _ => '与音乐服务的连接中断，请重试',
};

class MusicTransportException implements Exception {
  const MusicTransportException(this.outcome);
  final MusicNetworkOutcome outcome;
  String get message => musicNetworkMessage(outcome);
  @override
  String toString() => message;
}
