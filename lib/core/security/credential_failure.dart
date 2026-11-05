import 'dart:async';
import 'package:flutter/services.dart';

import '../network/music_network_diagnostics.dart';

/// A credential failure is local and phase-specific. Remote authentication and
/// incomplete platform responses must not be reported as broken local storage.
class CredentialStoreException implements Exception {
  const CredentialStoreException(this.phase, this.family);
  final MusicDiagnosticPhase phase;
  final MusicFailureFamily family;

  String get message => family == MusicFailureFamily.timeout
      ? '本机登录资料仍在处理中，请稍后重试；原资料已保留'
      : phase == MusicDiagnosticPhase.storageDecode
      ? '本机登录资料暂时无法解析，可重新登录；原资料已保留'
      : '本机登录资料暂时无法${phase == MusicDiagnosticPhase.storageRead ? '读取' : '保存'}，请重试或查看连接诊断；原资料已保留';
  @override
  String toString() => message;
}

MusicFailureFamily credentialFailureFamily(Object error) {
  if (error is CredentialStoreException) return error.family;
  if (error is TimeoutException) return MusicFailureFamily.timeout;
  if (error is MissingPluginException) {
    return MusicFailureFamily.pluginUnavailable;
  }
  if (error is FormatException || error is TypeError) {
    return MusicFailureFamily.format;
  }
  if (error is PlatformException) {
    // The local Android fork exports a closed family only. Never classify from
    // arbitrary messages or export an upstream exception/stack/credential.
    final details = error.details;
    final family = details is Map ? details['family'] : null;
    return switch (family) {
      'keyUnavailable' => MusicFailureFamily.keyUnavailable,
      'keyInvalidated' => MusicFailureFamily.keyInvalidated,
      'decrypt' => MusicFailureFamily.decrypt,
      'io' => MusicFailureFamily.io,
      _ => MusicFailureFamily.unknown,
    };
  }
  return MusicFailureFamily.unknown;
}

/// All repositories use the same safe reporting boundary, including decode and
/// readback. Only fixed enums and measured time enter the memory-only buffer.
Future<T> credentialStep<T>({
  required String platform,
  required MusicDiagnosticPhase phase,
  required Future<T> Function() run,
}) async {
  final watch = Stopwatch()..start();
  try {
    return await run();
  } on Object catch (error) {
    final family = credentialFailureFamily(error);
    MusicNetworkDiagnostics.shared.record(
      platform: platform,
      operation:
          phase == MusicDiagnosticPhase.storageRead ||
              phase == MusicDiagnosticPhase.storageDecode
          ? MusicNetworkOperation.restore
          : MusicNetworkOperation.storage,
      outcome: MusicNetworkOutcome.storage,
      elapsedMs: watch.elapsedMilliseconds,
      phase: phase,
      family: family,
      transport: 'local',
    );
    if (error is CredentialStoreException) rethrow;
    throw CredentialStoreException(phase, family);
  }
}
