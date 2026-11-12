import 'package:flutter/foundation.dart';
import '../../../shared/models/track.dart';

/// A small user-visible memory of skipped songs. Only public song metadata and
/// closed reason/phase labels are retained, never URLs, account IDs, PlayAuth,
/// raw exceptions or request payloads. Account changes clear the whole list.
class QishuiSkippedSong {
  const QishuiSkippedSong(this.title, this.artist, this.reason, this.phase);
  final String title, artist, reason, phase;
}

class QishuiPlaybackFailures extends ChangeNotifier {
  static final shared = QishuiPlaybackFailures();
  String? _owner;
  final _rows = <QishuiSkippedSong>[];
  List<QishuiSkippedSong> get rows => List.unmodifiable(_rows);

  void beginOwner(String? credential) {
    if (_owner == credential) return;
    _owner = credential;
    _rows.clear();
    // Account configuration can occur during a provider build. Clear private
    // ownership immediately, then repaint after that synchronous build ends.
    Future<void>.microtask(notifyListeners);
  }

  void clear() {
    _rows.clear();
    notifyListeners();
  }

  void record(Track track, {required String reason, required String phase}) {
    if (track.source != TrackSource.qishui) return;
    String bounded(String value) => String.fromCharCodes(value.runes.take(120));
    _rows.insert(
      0,
      QishuiSkippedSong(
        bounded(track.title),
        bounded(track.artist),
        reason,
        phase,
      ),
    );
    if (_rows.length > 20) _rows.removeLast();
    notifyListeners();
  }
}
