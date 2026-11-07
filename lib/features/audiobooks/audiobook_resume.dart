import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/app_preferences.dart';
import '../../shared/models/track.dart';
import '../music_platform/music_platform_providers.dart';
import 'audiobook_models.dart';

final audiobookResumeStoreProvider = Provider<AudiobookResumeStore>((ref) {
  final owner =
      ref.watch(
        platformAccountProvider.select((account) => account.value?.userId),
      ) ??
      'guest';
  final store = AudiobookResumeStore(
    ref.watch(sharedPreferencesProvider),
    owner,
  );
  ref.onDispose(store.dispose);
  return store;
});

class BookResume {
  const BookResume({
    required this.album,
    required this.track,
    required this.position,
    required this.updatedAt,
    this.nextPage = 2,
    this.hasMore = false,
    this.chapterPage = 1,
    this.pages = const {},
  });
  final BookAlbum album;
  final Track track;
  final Duration position;
  final DateTime updatedAt;
  final int nextPage;
  final int chapterPage;
  final bool hasMore;
  final Map<String, int> pages;
  Map<String, Object?> toJson() => {
    'album': album.toJson(),
    'track': track.toJson(),
    'positionMs': position.inMilliseconds,
    'updatedAt': updatedAt.toIso8601String(),
    'nextPage': nextPage,
    'chapterPage': chapterPage,
    'pages': pages,
    'hasMore': hasMore,
  };
  factory BookResume.fromJson(Map<String, dynamic> row) => BookResume(
    album: BookAlbum.fromJson(Map<String, dynamic>.from(row['album'] as Map)),
    track: Track.fromJson(Map<String, Object?>.from(row['track'] as Map)),
    position: Duration(
      milliseconds: (row['positionMs'] as num).toInt().clamp(0, 864000000),
    ),
    updatedAt: DateTime.parse(row['updatedAt'] as String),
    nextPage: (row['nextPage'] as num?)?.toInt() ?? 2,
    hasMore: row['hasMore'] == true,
    chapterPage: (row['chapterPage'] as num?)?.toInt() ?? 1,
    pages: row['pages'] is Map
        ? (row['pages'] as Map).map(
            (key, value) => MapEntry(
              '$key',
              value is num ? value.toInt().clamp(1, 100000) : 1,
            ),
          )
        : const {},
  );
}

/// Small, account-scoped resume snapshots. Writes are serialized and confirmed
/// before notifying; temporary signed playback URLs are never persisted here.
class AudiobookResumeStore extends ChangeNotifier {
  AudiobookResumeStore(this.preferences, String owner)
    : key = 'audiobook.resume.v1.$owner' {
    try {
      final raw = jsonDecode(preferences.getString(key) ?? '[]');
      if (raw is List) {
        for (final row in raw.take(50).whereType<Map>()) {
          try {
            final entry = BookResume.fromJson(Map<String, dynamic>.from(row));
            if (bookIdentity(entry.track)?.albumId == entry.album.id) {
              _entries[entry.album.id] = entry;
            }
          } on Object {
            /* A damaged row cannot hide other books. */
          }
        }
      }
    } on Object {
      /* Preserve the original preference until a valid save. */
    }
  }
  final SharedPreferences preferences;
  final String key;
  final Map<String, BookResume> _entries = {};
  Future<void> _writes = Future.value();
  bool _disposed = false;
  BookResume? forAlbum(String id) => _entries[id];
  List<BookResume> get entries =>
      _entries.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  Future<void> save(BookResume entry) {
    final operation = _writes.then((_) async {
      if (_disposed) return;
      final identity = bookIdentity(entry.track);
      if (identity == null || identity.albumId != entry.album.id) return;
      final stable = entry.track.copyWith(
        audioAsset: Uri(
          scheme: 'mesting-audiobook',
          host: 'chapter',
          path: '/${identity.albumId}',
          queryParameters: {'hash': identity.hash, 'mixsongid': identity.mixId},
        ).toString(),
      );
      final next = {
        ..._entries,
        entry.album.id: BookResume(
          album: entry.album,
          track: stable,
          position: entry.position,
          updatedAt: entry.updatedAt,
          nextPage: entry.nextPage,
          hasMore: entry.hasMore,
          chapterPage: entry.chapterPage,
          pages: entry.pages,
        ),
      };
      final ordered = next.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final retained = ordered.take(50).toList();
      final written = await preferences.setString(
        key,
        jsonEncode(retained.map((e) => e.toJson()).toList()),
      );
      if (!written) throw StateError('听书进度未保存');
      if (_disposed) return;
      _entries
        ..clear()
        ..addEntries(retained.map((e) => MapEntry(e.album.id, e)));
      notifyListeners();
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
