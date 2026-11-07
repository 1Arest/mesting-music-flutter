import 'dart:async';

import '../../../shared/models/track.dart';
import 'qishui_api.dart';
import 'qishui_history_repository.dart';

enum QishuiHistorySyncPhase { idle, sending, confirmed, unconfirmed, failed }

class QishuiHistorySyncStatus {
  const QishuiHistorySyncStatus({
    this.phase = QishuiHistorySyncPhase.idle,
    this.message = '',
  });
  final QishuiHistorySyncPhase phase;
  final String message;
}

/// Consumes the player's confirmed-play event, never metadata/position ticks.
/// The audio handler emits that event only after ready + playing for one
/// second. This reporter does not create another timer or infer listening from
/// a restored queue, so merely opening the app cannot upload old history.
class QishuiHistoryReporter {
  QishuiHistoryReporter({required this.history, this.onStatus});
  final QishuiHistoryRepository history;
  final void Function(QishuiHistorySyncStatus)? onStatus;
  final _seen = <String>{};
  bool _disposed = false;
  Future<void> _tail = Future.value();

  void _status(QishuiHistorySyncPhase phase, String message) {
    if (!_disposed) {
      onStatus?.call(QishuiHistorySyncStatus(phase: phase, message: message));
    }
  }

  /// Playback revisions distinguish a later replay from duplicate deliveries
  /// of one confirmed event. This bounded in-memory set is not a replay queue.
  Future<void> confirmPlayed(Track track, {required int playbackRevision}) {
    if (_disposed ||
        !history.current ||
        track.source != TrackSource.qishui ||
        track.platformSongId.isEmpty) {
      return Future.value();
    }
    final event = '$playbackRevision:${track.platformSongId}';
    if (!_seen.add(event)) return Future.value();
    if (_seen.length > 128) _seen.remove(_seen.first);
    final result = _tail.then((_) async {
      if (_disposed || !history.current) return;
      _status(QishuiHistorySyncPhase.sending, '正在同步本次汽水播放历史');
      try {
        await history.record(track);
        if (history.current) {
          _status(QishuiHistorySyncPhase.confirmed, '本次汽水播放历史已在云端读回');
        }
      } on QishuiException catch (error) {
        if (!history.current) return;
        _status(
          error.unknownWrite
              ? QishuiHistorySyncPhase.unconfirmed
              : QishuiHistorySyncPhase.failed,
          error.message,
        );
      } on Object {
        if (!history.current) return;
        _status(
          QishuiHistorySyncPhase.unconfirmed,
          '汽水历史同步结果尚未确认，请刷新或到官版核对；不会自动重发',
        );
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void dispose() {
    _disposed = true;
    history.dispose();
  }
}
