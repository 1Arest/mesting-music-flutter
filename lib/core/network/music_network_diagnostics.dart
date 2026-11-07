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
  // Playback stages remain closed names; exported diagnostics never contain
  // a media URL, PlayAuth, signing headers or account credentials.
  playerInfoRead,
  mediaModelParse,
  mediaSelection,
  audioRead,
  audioDecode,
  audioVerify,
  accountSigning,
  entitlementRead,
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

/// Matches the native audio bridge's closed, credential-free vocabulary.
/// Candidate eligibility is separate from successful native preparation.
enum MusicNativeAudioStep {
  cachePath,
  sourceRead,
  authorization,
  containerParse,
  sampleDecrypt,
  cacheWrite,
  metadataRead,
}

enum MusicNativeAudioReason {
  cachePathInvalid,
  cacheFileMissing,
  cacheOutputExists,
  sourceReadFailed,
  authorizationInvalid,
  mediaStructureUnsupported,
  encryptionUnsupported,
  sampleTableInvalid,
  sampleDecryptFailed,
  cacheWriteFailed,
  metadataUnsupported,
  operationInvalid,
  bridgeUnavailable,
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
    int? streamCandidates,
    int? decodableStreams,
    int? playerInfoUrls,
    MusicNativeAudioStep? nativeStep,
    MusicNativeAudioReason? nativeReason,
    bool? accountCookieSigned,
    bool? freeListeningActive,
    bool? membershipActive,
    bool? preview,
    int? catalogDurationMs,
    int? mediaDurationMs,
    int? mediaCandidateAttempt,
  }) {
    _rows.add(
      Map.unmodifiable({
        'at': DateTime.now().toUtc().toIso8601String(),
        'platform': {'netease', 'kugou', 'qishui', 'audio'}.contains(platform)
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
        'accountCookieSigned': ?accountCookieSigned,
        'freeListeningActive': ?freeListeningActive,
        'membershipActive': ?membershipActive,
        'preview': ?preview,
        if (catalogDurationMs != null)
          'catalogDurationMs': catalogDurationMs.clamp(0, 86400000),
        if (mediaDurationMs != null)
          'mediaDurationMs': mediaDurationMs.clamp(0, 86400000),
        if (mediaCandidateAttempt != null)
          'mediaCandidateAttempt': mediaCandidateAttempt.clamp(1, 4),
        if (family != null) 'family': family.name,
        if (nativeStep != null) 'nativeStep': nativeStep.name,
        if (nativeReason != null) 'nativeReason': nativeReason.name,
        if (streamCandidates != null)
          'streamCandidates': streamCandidates.clamp(0, 1000),
        if (decodableStreams != null)
          'decodableStreams': decodableStreams.clamp(0, 1000),
        if (playerInfoUrls != null)
          'playerInfoUrls': playerInfoUrls.clamp(0, 1000),
      }),
    );
    if (_rows.length > 80) _rows.removeAt(0);
    notifyListeners();
  }

  String export() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'schema': 2, 'memoryOnly': true, 'events': _rows});

  /// Copy a complete, small JSON snapshot centred on the latest failure.
  /// Whole events are removed from the front to fit; text is never truncated
  /// mid-string. This reduces damage from clipboard/sync size limits without
  /// claiming that we control another app's eventual paste operation.
  String exportCompact() {
    final snapshot = List<Map<String, Object>>.of(_rows);
    final failure = snapshot.lastIndexWhere(
      (row) => !{'success', 'cancelled'}.contains(row['outcome']),
    );
    final end = failure < 0 ? snapshot.length - 1 : failure;
    final platform = end < 0 ? null : snapshot[end]['platform'];
    final rows = snapshot
        .take(end + 1)
        .where((row) => row['platform'] == platform)
        .toList();
    if (rows.length > 10) rows.removeRange(0, rows.length - 10);
    String encode() => jsonEncode({
      'schema': 2,
      'memoryOnly': true,
      'scope': failure < 0 ? 'recent' : 'latestFailure',
      'eventCount': rows.length,
      'events': rows,
      'complete': true,
    });
    var result = encode();
    while (result.length > 4096 && rows.length > 1) {
      rows.removeAt(0);
      result = encode();
    }
    return result;
  }

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
