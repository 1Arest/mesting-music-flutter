import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../shared/models/track.dart';

List<Track> _decodeTracks(List<String> snapshots) => [
  for (final raw in snapshots)
    Track.fromJson((jsonDecode(raw) as Map).cast<String, Object?>()),
];

Future<List<Track>> decodeTrackSnapshots(List<String> snapshots) =>
    snapshots.length < 100
    ? Future.value(_decodeTracks(snapshots))
    : compute(_decodeTracks, snapshots, debugLabel: 'library-track-snapshots');

List<Track> _decodeQueue(String raw) => [
  for (final value in jsonDecode(raw) as List)
    Track.fromJson((value as Map).cast<String, Object?>()),
];

Future<List<Track>> decodeTrackQueue(String raw) => raw.length < 128 * 1024
    ? Future.value(_decodeQueue(raw))
    : compute(_decodeQueue, raw, debugLabel: 'playback-queue-restore');

String _encodeQueue(List<Track> tracks) =>
    jsonEncode(tracks.map((track) => track.toJson()).toList());
Future<String> encodeTrackQueue(List<Track> tracks) => tracks.length < 100
    ? Future.value(_encodeQueue(tracks))
    : compute(_encodeQueue, tracks, debugLabel: 'playback-queue-persist');
