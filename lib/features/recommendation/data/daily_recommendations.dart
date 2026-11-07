import 'dart:math';

import '../../../shared/models/track.dart';

/// Creates a stable queue for one natural day. When playable online tracks
/// are available, the queue alternates local complete files and online music
/// instead of allowing either source to take over the whole recommendation.
List<Track> recommendationTracksForDate(
  DateTime date, {
  List<Track>? localTracks,
  List<Track> onlineTracks = const [],
  int limit = 8,
}) {
  final day = DateTime(date.year, date.month, date.day);
  final seed = day.difference(DateTime(2024)).inDays;
  final local = _playableUnique(localTracks ?? const <Track>[])
    ..shuffle(Random(seed));
  final online = _playableUnique(onlineTracks.where((track) => track.isRemote))
    ..shuffle(Random(seed ^ 0x5F3759DF));

  final result = <Track>[];
  var localIndex = 0;
  var onlineIndex = 0;
  while (result.length < limit &&
      (localIndex < local.length || onlineIndex < online.length)) {
    final preferOnline = result.length.isOdd;
    if (preferOnline && onlineIndex < online.length) {
      result.add(online[onlineIndex++]);
    } else if (localIndex < local.length) {
      result.add(local[localIndex++]);
    } else if (onlineIndex < online.length) {
      result.add(online[onlineIndex++]);
    }
  }
  return List<Track>.unmodifiable(result);
}

List<Track> _playableUnique(Iterable<Track> tracks) {
  final seen = <String>{};
  return tracks
      .where((track) {
        if (!track.isPlayable) return false;
        final key = '${_normalize(track.title)}|${_normalize(track.artist)}';
        return seen.add(key);
      })
      .toList(growable: true);
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^]]*\]'), '')
    .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
