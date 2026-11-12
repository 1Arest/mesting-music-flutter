import 'package:flutter/services.dart';

import '../../../core/network/music_network_diagnostics.dart';

/// Decode only known bridge labels. Native exception text/details can contain
/// private paths or media authorization, so unknown values are never echoed.
class QishuiNativeAudioFailure {
  const QishuiNativeAudioFailure(this.step, this.reason, this.family);
  final MusicNativeAudioStep? step;
  final MusicNativeAudioReason reason;
  final MusicFailureFamily family;

  factory QishuiNativeAudioFailure.from(Object error) {
    if (error is MissingPluginException) {
      return const QishuiNativeAudioFailure(
        null,
        MusicNativeAudioReason.bridgeUnavailable,
        MusicFailureFamily.pluginUnavailable,
      );
    }
    final details = error is PlatformException && error.details is Map
        ? error.details as Map
        : const {};
    T? known<T extends Enum>(List<T> values, Object? name) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    final family = known(MusicFailureFamily.values, details['family']);
    return QishuiNativeAudioFailure(
      known(MusicNativeAudioStep.values, details['step']),
      known(MusicNativeAudioReason.values, details['reason']) ??
          MusicNativeAudioReason.unknown,
      {MusicFailureFamily.io, MusicFailureFamily.decrypt}.contains(family)
          ? family!
          : MusicFailureFamily.format,
    );
  }

  String get message => switch (reason) {
    MusicNativeAudioReason.cachePathInvalid => '汽水临时音频路径校验未通过',
    MusicNativeAudioReason.cacheFileMissing => '汽水临时音频文件不存在',
    MusicNativeAudioReason.cacheOutputExists => '汽水临时音频文件冲突，请重新播放',
    MusicNativeAudioReason.sourceReadFailed => '汽水临时音频文件读取未完成',
    MusicNativeAudioReason.authorizationInvalid => '汽水音频播放授权解析未通过',
    MusicNativeAudioReason.mediaStructureUnsupported => '汽水音频容器结构暂不受支持',
    MusicNativeAudioReason.encryptionUnsupported => '汽水音频加密格式暂不受支持',
    MusicNativeAudioReason.sampleTableInvalid => '汽水音频加密分段资料不完整或暂不受支持',
    MusicNativeAudioReason.sampleDecryptFailed => '汽水音频分段解密未通过',
    MusicNativeAudioReason.cacheWriteFailed => '汽水临时音频文件写入未完成',
    MusicNativeAudioReason.metadataUnsupported => '汽水音频格式或时长读取未通过',
    MusicNativeAudioReason.bridgeUnavailable => '汽水本机音频组件尚未就绪，请重开应用后重试',
    _ => '汽水音频解码或完整性核验未通过，请查看连接诊断',
  };
}
