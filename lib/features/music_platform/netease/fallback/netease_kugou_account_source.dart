import '../../../../shared/models/track.dart';
import '../../data/embedded_kugou_music_source.dart';
import '../../domain/platform_audio_quality.dart';
import 'netease_fallback_source.dart';
import 'netease_source_transport.dart';

/// Uses the existing Concept account playback protocol, in a private request
/// scope. The outer resolver still enforces exact recording/version matching,
/// probes the CDN and returns the original NetEase identity to the queue.
class AccountKugouFallback implements NeteaseFallbackSource {
  AccountKugouFallback(this.source, {required this.current});
  final EmbeddedKugouMusicSource source;
  final bool Function() current;
  static const sourceLabel = '酷狗概念版账号';
  @override
  String get label => sourceLabel;
  void _guard() {
    if (!current()) {
      throw const NeteaseSourceFailure('account_changed');
    }
  }

  @override
  Future<List<Track>> search(Track original) async {
    _guard();
    final tracks = await source.search(
      '${original.title} ${original.artist}',
      limit: 12,
    );
    _guard();
    return tracks;
  }

  @override
  Future<Track?> resolve(Track candidate) async {
    _guard();
    final wanted = PlatformAudioQuality.fromCode(candidate.playbackQuality);
    final result = await source.resolveTrack(
      candidate,
      quality: wanted == null || wanted.neteaseOnly
          ? PlatformAudioQuality.high
          : wanted,
    );
    _guard();
    return result.isPreview || !result.isPlayable ? null : result;
  }
}
