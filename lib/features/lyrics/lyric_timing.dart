import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/playback_providers.dart';
import '../../shared/models/track.dart';
import 'domain/lyrics_document.dart';
import 'lyrics_providers.dart';

String lyricTimingKey(Track track) => '${track.source.name}:${track.id}';

final lyricTimingProvider =
    AsyncNotifierProvider.family<LyricTimingController, int, String>(
      LyricTimingController.new,
    );

class LyricTimingController extends AsyncNotifier<int> {
  LyricTimingController(this.song);
  final String song;
  Future<void> _pending = Future.value();
  String get _key => 'lyrics_offset_ms_v1:$song';

  @override
  Future<int> build() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_key) ?? 0;
  }

  Future<void> adjust(int milliseconds) => _save(milliseconds);
  Future<void> reset() => _save(null);

  Future<void> _save(int? delta) {
    final operation = _pending.then((_) async {
      final current = await future;
      final preferences = await SharedPreferences.getInstance();
      final next = delta == null ? 0 : current + delta;
      final saved = next == 0
          ? await preferences.remove(_key)
          : await preferences.setInt(_key, next);
      if (!saved) throw StateError('歌词时间未能保存，请重试');
      if (ref.mounted) state = AsyncData(next);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}

/// Apply the same per-song timestamps to rendering, preview seek and overlays.
final currentTimedLyricsProvider = FutureProvider<LyricsDocument>((ref) async {
  final track = ref.watch(currentTrackProvider);
  final original = ref.watch(lyricsProvider(track.resolvedLyricsAsset).future);
  final timing = ref.watch(lyricTimingProvider(lyricTimingKey(track)).future);
  final document = await original;
  final milliseconds = await timing;
  if (!document.isSynced || milliseconds == 0) return document;
  return LyricsDocument(
    isSynced: true,
    lines: [
      for (final line in document.lines)
        LyricsLine(
          time: line.time + Duration(milliseconds: milliseconds),
          text: line.text,
        ),
    ],
  );
});
