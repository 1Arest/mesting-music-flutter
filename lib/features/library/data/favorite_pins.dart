import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/models/track.dart';

/// Local presentation order only. Server order, membership and pagination
/// cursors remain owned by the original library repository.
class FavoritePins extends ChangeNotifier {
  FavoritePins(this.preferences) {
    try {
      final raw = jsonDecode(preferences.getString(storageKey) ?? '{}');
      if (raw is Map) {
        for (final entry in raw.entries) {
          if (entry.key is! String || entry.value is! List) continue;
          final seen = <String>{};
          _owners[entry.key] = [
            for (final row in entry.value)
              if (row is Map) ..._restore(row).where((t) => seen.add(t.id)),
          ];
        }
      }
    } catch (_) {
      // Optional ordering can be corrupt without breaking the user's library.
    }
  }
  static const storageKey = 'favorite-local-pins-v1';
  final SharedPreferences preferences;
  final _owners = <String, List<Track>>{};
  Future<void> _writes = Future.value();
  bool _disposed = false;
  static Iterable<Track> _restore(Map row) sync* {
    try {
      yield Track.fromJson(Map<String, Object?>.from(row));
    } catch (_) {}
  }

  bool contains(String owner, String id) =>
      _owners[owner]?.any((t) => t.id == id) ?? false;
  bool hasPins(String owner) => _owners[owner]?.isNotEmpty ?? false;

  /// Save a safe catalogue reference, never an expiring audio URL, cookie,
  /// fallback recording or playback/reporting state. A local file keeps its
  /// already-granted content URI; this creates no new storage permission.
  static Track _snapshot(Track track) => Track.fromJson({
    ...track.toJson(),
    if (track.source != TrackSource.local)
      'audioAsset':
          'mesting-platform://${track.source.name}/${track.source == TrackSource.netease
              ? track.platformSongId.isNotEmpty
                    ? track.platformSongId
                    : track.id.replaceFirst('netease_', '')
              : track.id}',
    'audioHeaders': <String, String>{},
    'audioOrigin': null,
    'playbackQuality': '',
    'audioBitrate': 0,
  });

  Future<void> toggle(String owner, Track track) {
    // Compute after the previous write, so rapid taps and account switches
    // cannot overwrite each other's successful ordering with an older copy.
    final task = _writes.catchError((Object _) {}).then((_) async {
      final old = _owners[owner] ?? const <Track>[];
      final next = old.where((t) => t.id != track.id).toList();
      if (!old.any((t) => t.id == track.id)) next.insert(0, _snapshot(track));
      final updated = {..._owners, owner: next};
      if (!await preferences.setString(
        storageKey,
        jsonEncode(
          updated.map(
            (key, tracks) =>
                MapEntry(key, tracks.map((t) => t.toJson()).toList()),
          ),
        ),
      )) {
        throw StateError('置顶未保存，请重试');
      }
      _owners[owner] = next;
      if (!_disposed) notifyListeners();
    });
    _writes = task;
    return task;
  }

  List<Track> apply(String owner, List<Track> loaded, Set<String> membership) {
    final fresh = {for (final track in loaded) track.id: track};
    final pins = [
      for (final pin in _owners[owner] ?? const <Track>[])
        if (membership.contains(pin.id)) fresh[pin.id] ?? pin,
    ];
    final ids = pins.map((t) => t.id).toSet();
    return [...pins, ...loaded.where((t) => !ids.contains(t.id))];
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
