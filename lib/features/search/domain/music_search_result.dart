import '../../../shared/models/track.dart';

class MusicSearchResult {
  const MusicSearchResult({
    required this.query,
    required this.localTracks,
    required this.onlineTracks,
    this.warnings = const [],
    this.fromCache = false,
  });

  final String query;
  final List<Track> localTracks;
  final List<Track> onlineTracks;
  final List<String> warnings;
  final bool fromCache;

  bool get isEmpty => localTracks.isEmpty && onlineTracks.isEmpty;
}
