import 'package:just_audio/just_audio.dart';
import '../../../shared/models/track.dart';
import 'qishui_api.dart';

/// Track-specific failures may advance an existing queue. Transport, sign-in,
/// signer and cancelled operations must stop rather than sweep a whole library.
/// The reported 301 is handled only in Qishui playback, not as a global HTTP
/// redirect rule or an assumption about another platform's business codes.
bool qishuiCanSkipPlaybackFailure(Track track, Object error) {
  if (track.source != TrackSource.qishui) return false;
  if (error is QishuiException) {
    if (error.code == 'signer' || error.unknownWrite) return false;
    return error.kind == QishuiFailureKind.entitlement ||
        error.kind == QishuiFailureKind.format ||
        error.kind == QishuiFailureKind.refused &&
            {'301', 'http_301', 'http_404', 'http_410'}.contains(error.code);
  }
  if (error is PlayerException) return {301, 404, 410}.contains(error.code);
  return error is FormatException;
}
