import 'dart:convert';

import '../../../core/network/music_network_diagnostics.dart';
import '../domain/platform_audio_quality.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';

/// Only first-party player-info origins may be followed. The exact Luna VOD
/// origin appears in the retained official response, independently of a signer.
/// Redirects and arbitrary URLs from a DTO do not gain credential privileges.
bool qishuiTrustedPlayerInfo(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    !uri.hasFragment &&
    (uri.host == 'vod-luna.douyin.com' ||
        uri.host == 'open.bytedanceapi.com' ||
        uri.host.endsWith('.volcvod.com') ||
        uri.host.endsWith('.douyinvod.com') ||
        uri.host.endsWith('.bytecdn.cn'));

/// A bounded DTO scan finds player-info links without persisting their signed
/// query strings. The loader resolves these links anonymously, outside the API
/// account session. Media selection remains a separate, independently testable
/// policy below.
List<Uri> qishuiPlayerInfoUris(Object? data) {
  final result = <Uri>{};
  var remaining = 12000;
  void visit(Object? value, int depth) {
    if (depth > 12 || --remaining < 0) return;
    if (value is String &&
        value.length <= 2 * 1024 * 1024 &&
        value.trimLeft().startsWith('{')) {
      // Some player containers carry their JSON as a string. Inspect that
      // bounded container using the same explicit field/origin rules below.
      try {
        visit(jsonDecode(value), depth + 1);
      } on FormatException {
        /* Not a JSON player container. */
      }
    } else if (value is List) {
      for (final child in value) {
        visit(child, depth + 1);
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        if ({'url_player_info', 'urlPlayerInfo'}.contains(entry.key) &&
            entry.value is String) {
          final uri = Uri.tryParse((entry.value as String).trim());
          if (uri != null) result.add(uri);
        } else if (entry.value is Map ||
            entry.value is List ||
            entry.value is String &&
                {
                  'track_player',
                  'trackPlayer',
                  'video_model',
                  'videoModel',
                  'player_info',
                }.contains(entry.key)) {
          visit(entry.value, depth + 1);
        }
      }
    }
  }

  visit(data, 0);
  return result.take(3).toList(growable: false);
}

/// Selection describes the actual authorized stream, not the catalog length.
/// A free-listening entitlement must be expressed by the official media reply;
/// it is never synthesized from a membership label or a screenshot.
class QishuiPlaybackSelection {
  const QishuiPlaybackSelection(this.media, {required this.isPreview});
  final QishuiMedia media;
  final bool isPreview;

  static QishuiPlaybackSelection choose(
    List<QishuiMedia> streams, {
    required Duration catalogDuration,
    required bool download,
    PlatformAudioQuality? quality,
    required bool requireQuality,
  }) {
    final decodable = streams.where((m) => m.canDecodeOfficial).toList();
    void record(MusicNetworkOutcome outcome) =>
        MusicNetworkDiagnostics.shared.record(
          platform: 'qishui',
          operation: MusicNetworkOperation.playbackUrl,
          outcome: outcome,
          transport: 'local',
          phase: MusicDiagnosticPhase.mediaSelection,
          streamCandidates: streams.length,
          decodableStreams: decodable.length,
        );
    if (streams.isEmpty) {
      record(MusicNetworkOutcome.format);
      throw const QishuiException(
        '汽水播放资料中没有可识别的音频地址，请导出连接诊断核对媒体解析阶段',
        kind: QishuiFailureKind.format,
      );
    }
    if (decodable.isEmpty) {
      record(MusicNetworkOutcome.format);
      throw const QishuiException(
        '汽水返回了加密音频，但缺少播放授权或加密方式暂不支持',
        kind: QishuiFailureKind.format,
      );
    }
    final timed = decodable.where((m) => m.duration > Duration.zero).toList();
    if (timed.isEmpty) {
      record(MusicNetworkOutcome.format);
      throw const QishuiException(
        '汽水未返回音频片段的实际时长，暂不能确认播放范围',
        kind: QishuiFailureKind.format,
      );
    }
    bool full(QishuiMedia media) =>
        media.duration + const Duration(seconds: 5) >= catalogDuration;
    final complete = timed.where(full).toList();
    if (download && complete.isEmpty) {
      record(MusicNetworkOutcome.business);
      throw const QishuiException(
        '汽水当前只返回试听音频，暂不能按完整歌曲下载',
        kind: QishuiFailureKind.entitlement,
      );
    }
    // Completeness precedes bitrate: a high-bitrate preview must not displace
    // a complete recording already granted to this account by the server.
    final pool = complete.isNotEmpty ? complete : timed;
    pool.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    bool matches(QishuiMedia media) =>
        quality == null ||
        quality == PlatformAudioQuality.high && media.bitrate > 220000 ||
        quality == PlatformAudioQuality.standard &&
            media.bitrate > 0 &&
            media.bitrate <= 220000;
    final matching = pool.where(matches).firstOrNull;
    final selected = matching ?? (requireQuality ? null : pool.first);
    if (selected == null) {
      record(MusicNetworkOutcome.business);
      throw const QishuiException(
        '汽水未提供所选音质',
        kind: QishuiFailureKind.entitlement,
      );
    }
    record(MusicNetworkOutcome.success);
    return QishuiPlaybackSelection(selected, isPreview: !full(selected));
  }
}
