/// A modal video borrows audio focus without owning/rebuilding the music queue.
/// Only the pause issued by this lease may be undone. A later timer, hardware
/// key, seek or song change supersedes it and prevents a surprise resume.
class MusicPlaybackInterruption {
  MusicPlaybackInterruption({
    required this.mediaId,
    required this.revision,
    required this.playing,
    required this.pause,
    required this.play,
  });
  final String? Function() mediaId;
  final int Function() revision;
  final bool Function() playing;
  final Future<void> Function() pause, play;
  String? _id;
  int? _revision;
  bool _wasPlaying = false, _acquired = false, _released = false;
  bool get isCurrent =>
      _acquired && !_released && _id == mediaId() && _revision == revision();
  Future<void> acquire() async {
    if (_acquired) return;
    _acquired = true;
    _id = mediaId();
    _wasPlaying = playing();
    if (_wasPlaying) {
      // pause() records its transport command synchronously before its first
      // await. Capture that ticket now, not after a possible later user action.
      final pending = pause();
      _revision = revision();
      await pending;
    } else {
      _revision = revision();
    }
  }

  Future<void> release() async {
    if (_released) return;
    final resume = _wasPlaying && isCurrent;
    _released = true;
    if (resume) await play();
  }
}
