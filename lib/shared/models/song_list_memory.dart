import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'track.dart';

/// A list bookmark is presentation state, not a playback queue or a listening
/// report. Store only a stable song identity and display text; never credentials
/// or expiring audio URLs. Keys include both the owner and the logical list.
class SongListBookmark {
  const SongListBookmark({
    required this.trackId,
    required this.title,
    required this.updatedAt,
    this.cover = '',
  });
  final String trackId, title;
  final String cover;
  final int updatedAt;
  Map<String, Object> toJson() => {
    'id': trackId,
    'title': title,
    'at': updatedAt,
    'cover': cover,
  };
}

class SongListMemory extends ChangeNotifier {
  SongListMemory(this.preferences) {
    try {
      final raw = jsonDecode(preferences.getString(storageKey) ?? '{}');
      if (raw is Map) {
        for (final entry in raw.entries) {
          final row = entry.value;
          if (entry.key is String &&
              row is Map &&
              row['id'] is String &&
              row['title'] is String &&
              row['at'] is int) {
            _records[entry.key] = SongListBookmark(
              trackId: row['id'],
              title: row['title'],
              updatedAt: row['at'],
              cover: row['cover'] is String ? row['cover'] : '',
            );
          }
        }
      }
    } catch (_) {
      // Corrupt optional UI state must never prevent the library from opening.
    }
  }
  static const storageKey = 'song-list-bookmarks-v1';
  final SharedPreferences preferences;
  final _records = <String, SongListBookmark>{};
  Future<void> _writes = Future.value();
  String _key(String owner, String list) => jsonEncode([owner, list]);
  SongListBookmark? read(String owner, String list) =>
      _records[_key(owner, list)];
  void remember(String owner, String list, Track track) {
    final key = _key(owner, list);
    _records.remove(key);
    _records[key] = SongListBookmark(
      trackId: track.id,
      title: track.title,
      updatedAt: DateTime.now().microsecondsSinceEpoch,
      cover: track.coverAsset,
    );
    while (_records.length > 256) {
      _records.remove(_records.keys.first);
    }
    final encoded = jsonEncode(
      _records.map((key, record) => MapEntry(key, record.toJson())),
    );
    // Serialize writes so rapid taps cannot restore an older bookmark after a
    // newer one. A preference failure is isolated from successful playback.
    _writes = _writes
        .catchError((Object _) {})
        .then((_) async {
          await preferences.setString(storageKey, encoded);
        })
        .catchError((Object _) {});
    notifyListeners();
  }

  Future<void> flush() => _writes;
}
