import 'package:just_audio/just_audio.dart';
import '../../../shared/models/track.dart';
import 'qishui_api.dart';
import 'qishui_playback_failures.dart';
import '../../../core/network/music_network_diagnostics.dart';

/// Track-specific failures may advance an existing queue. Transport, sign-in,
/// signer and cancelled operations must stop rather than sweep a whole library.
/// The reported 301 is handled only in Qishui playback, not as a global HTTP
/// redirect rule or an assumption about another platform's business codes.
bool qishuiCanSkipPlaybackFailure(Track track, Object error) {
  if (track.source != TrackSource.qishui) return false;
  bool remember(bool eligible, String reason) {
    if (eligible) {
      final events = MusicNetworkDiagnostics.shared.rows;
      final last = events
          .where((row) => row['platform'] == 'qishui')
          .lastOrNull;
      QishuiPlaybackFailures.shared.record(
        track,
        reason: reason,
        phase: '${last?['phase'] ?? 'playback'}',
      );
    }
    return eligible;
  }

  if (error is QishuiException) {
    if (error.code == 'signer' || error.unknownWrite) return false;
    return remember(
      error.kind == QishuiFailureKind.entitlement ||
          error.kind == QishuiFailureKind.format ||
          error.kind == QishuiFailureKind.refused &&
              {
                '301',
                'http_301',
                'media_http_403',
                'http_404',
                'http_410',
              }.contains(error.code),
      error.kind == QishuiFailureKind.entitlement
          ? '官方返回的播放资格或音质受限'
          : error.kind == QishuiFailureKind.format
          ? '媒体资料、容器或音频格式尚未通过核验'
          : '本曲媒体请求被拒绝（${error.code}）',
    );
  }
  if (error is PlayerException) {
    return remember({301, 404, 410}.contains(error.code), '播放器未能打开本曲音频');
  }
  return remember(error is FormatException, '媒体资料格式尚未识别');
}
