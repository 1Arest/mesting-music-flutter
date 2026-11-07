import '../../../shared/models/track.dart';

enum CuratedPlaylistTrackSource { online, local, unavailable }

class CuratedPlaylistTracks {
  CuratedPlaylistTracks({
    required List<Track> tracks,
    required this.source,
    List<String> warnings = const <String>[],
  }) : tracks = List<Track>.unmodifiable(tracks),
       warnings = List<String>.unmodifiable(warnings);

  final List<Track> tracks;
  final CuratedPlaylistTrackSource source;
  final List<String> warnings;

  bool get isLocal => source == CuratedPlaylistTrackSource.local;
  bool get isUnavailable => source == CuratedPlaylistTrackSource.unavailable;
}
