import '../../../../shared/models/track.dart';
import 'package:http/http.dart' as http;

/// Production sources are created per resolution so a timeout can cancel only
/// its own requests. The positional source list remains useful for pure tests.
class NeteaseSourceFactory {
  const NeteaseSourceFactory(this.create);
  final NeteaseFallbackSource Function(http.Client client) create;
}

abstract interface class NeteaseFallbackSource {
  String get label;
  Future<List<Track>> search(Track original);
  Future<Track?> resolve(Track candidate);
}

/// Only adapters resolving the requested NetEase ID may bypass title matching.
abstract interface class NeteaseExactIdSource
    implements NeteaseFallbackSource {}

/// Video/audio catalogues can prove title, performer, version and duration
/// without carrying an album field. Their parsers must retain version words.
abstract interface class NeteasePublicMetadataSource
    implements NeteaseFallbackSource {}

/// Video containers may add a few seconds of still frames at their edges.
/// This allowance does not relax title, performer, album or edition matching.
abstract interface class NeteaseVideoMetadataSource
    implements NeteasePublicMetadataSource {}

/// A single alternate public search is allowed only after the first query has
/// no usable recording. It shares the provider's overall timeout and limit.
abstract interface class NeteaseAlternativeSearchSource
    implements NeteaseFallbackSource {
  Future<List<Track>> searchAlternative(Track original);
}

Duration recordingDurationTolerance(
  NeteaseFallbackSource source,
  Track original,
) => source is NeteaseVideoMetadataSource
    ? Duration(
        milliseconds: (original.duration.inMilliseconds * .015).round().clamp(
          0,
          4000,
        ),
      )
    : const Duration(seconds: 2);

String normalizeRecordingText(String value) => value.toLowerCase().replaceAll(
  RegExp(r'[\s\p{P}\p{S}]', unicode: true),
  '',
);

bool isSameNeteaseRecording(
  Track original,
  Track candidate, {
  bool allowMissingAlbum = false,
  Duration durationTolerance = const Duration(seconds: 2),
}) {
  Set<String> artists(String value) => value
      .split(RegExp(r'\s*(?:/|&|、|,|，|;|；)\s*'))
      .map(normalizeRecordingText)
      .where((a) => a.isNotEmpty)
      .toSet();
  if (normalizeRecordingText(original.title).isEmpty ||
      normalizeRecordingText(original.title) !=
          normalizeRecordingText(candidate.title)) {
    return false;
  }
  final a = artists(original.artist), b = artists(candidate.artist);
  if (a.isEmpty || a.length != b.length || !a.containsAll(b)) return false;
  if (original.duration <= Duration.zero ||
      candidate.duration <= Duration.zero ||
      (original.duration - candidate.duration).inMilliseconds.abs() >
          durationTolerance.inMilliseconds) {
    return false;
  }
  if (original.album.isNotEmpty &&
      !(allowMissingAlbum && candidate.album.isEmpty) &&
      normalizeRecordingText(original.album) !=
          normalizeRecordingText(candidate.album)) {
    return false;
  }
  return true;
}
