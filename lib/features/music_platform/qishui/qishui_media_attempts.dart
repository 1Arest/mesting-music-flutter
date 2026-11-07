import 'qishui_api.dart';
import 'qishui_playback_media.dart';

/// Bounded same-recording recovery, separate from queue continuation. Only an
/// address/container failure may try another already granted candidate. Login,
/// signer, network, cancellation and unknown writes stop immediately.
Future<T> prepareQishuiMediaCandidates<T>(
  List<QishuiPlaybackSelection> candidates, {
  required bool Function() current,
  required Future<T> Function(QishuiPlaybackSelection, int attempt) prepare,
  int maximumAttempts = 4,
}) async {
  final limit = maximumAttempts.clamp(1, 4);
  Object? lastError;
  StackTrace? lastStack;
  final seen = <String>{};
  var attempt = 0;
  for (final selected in candidates) {
    if (!current()) {
      throw const QishuiException(
        '账号或播放选择已变化，操作已取消',
        kind: QishuiFailureKind.cancelled,
      );
    }
    if (!seen.add(selected.media.url)) continue;
    if (++attempt > limit) break;
    try {
      return await prepare(selected, attempt);
    } on Object catch (error, stack) {
      if (!current()) {
        throw const QishuiException(
          '账号或播放选择已变化，操作已取消',
          kind: QishuiFailureKind.cancelled,
        );
      }
      final recoverable =
          error is QishuiException &&
          !error.unknownWrite &&
          error.code != 'signer' &&
          (error.kind == QishuiFailureKind.format ||
              error.kind == QishuiFailureKind.refused &&
                  const {
                    'http_301',
                    'media_http_403',
                    'http_404',
                    'http_410',
                  }.contains(error.code));
      if (!recoverable) rethrow;
      lastError = error;
      lastStack = stack;
    }
  }
  if (lastError != null) Error.throwWithStackTrace(lastError, lastStack!);
  throw const QishuiException('汽水未返回可以准备的音频候选', kind: QishuiFailureKind.format);
}
