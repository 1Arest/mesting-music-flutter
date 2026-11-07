import '../../shared/models/track.dart';
import '../music_platform/data/platform_artwork.dart';
import '../music_platform/data/music_platform_api.dart';

/// Long-audio contracts from md3Music a69503b (AGPL-3.0), kept separate
/// from music search so an album ID never masquerades as an audio hash.
String bookText(Map row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value is String || value is num) {
      final text = '$value'.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

List<Map<String, dynamic>> bookRows(Object? payload, [int depth = 0]) {
  if (depth > 6) return [];
  if (payload is List) {
    return payload.whereType<Map>().map(MusicPlatformApi.objectMap).toList();
  }
  final row = MusicPlatformApi.objectMap(payload);
  for (final key in const [
    'data',
    'data_list',
    'list',
    'lists',
    'info',
    'audios',
    'audio_list',
    'albums',
    'items',
  ]) {
    final value = row[key];
    if (value is List) {
      return value.whereType<Map>().map(MusicPlatformApi.objectMap).toList();
    }
    if (value is Map) {
      final result = bookRows(value, depth + 1);
      if (result.isNotEmpty) return result;
    }
  }
  return [];
}

class BookAlbum {
  const BookAlbum({
    required this.id,
    required this.name,
    this.author = '',
    this.cover = '',
    this.intro = '',
    this.chapterCount = 0,
  });
  final String id, name, author, cover, intro;
  final int chapterCount;
  factory BookAlbum.fromJson(Map<String, dynamic> json) {
    final row = {
      ...MusicPlatformApi.objectMap(json['album_info']),
      ...MusicPlatformApi.objectMap(json['album']),
      ...json,
    };
    return BookAlbum(
      id: bookText(row, ['album_id', 'AlbumID', 'albumid', 'id']),
      name: bookText(row, [
        'album_name',
        'AlbumName',
        'albumname',
        'name',
        'title',
      ]),
      author: bookText(row, ['author_name', 'author', 'singer', 'SingerName']),
      cover: PlatformArtwork.fromPayload(row),
      intro: bookText(row, ['intro', 'mix_intro', 'full_intro']),
      chapterCount:
          int.tryParse(
            bookText(row, [
              'audio_count',
              'audiocount',
              'audio_total',
              'songcount',
            ]),
          ) ??
          0,
    );
  }
  Map<String, Object?> toJson() => {
    'album_id': id,
    'album_name': name,
    'author': author,
    'sizable_cover': cover,
    'intro': intro,
    'audio_count': chapterCount,
  };
}

class BookCategory {
  const BookCategory(this.id, this.name);
  final String id, name;
}

class BookChapter {
  const BookChapter({
    required this.album,
    required this.hash,
    required this.mixId,
    required this.name,
    this.author = '',
    this.cover = '',
    this.duration = Duration.zero,
    this.canPlay = true,
  });
  final BookAlbum album;
  final String hash, mixId, name, author, cover;
  final Duration duration;
  final bool canPlay;
  factory BookChapter.fromJson(Map<String, dynamic> row, BookAlbum album) {
    final milliseconds =
        int.tryParse(
          bookText(row, [
            'duration_ms',
            'timelength',
            'timelength_128',
            'timelength_320',
          ]),
        ) ??
        0;
    final seconds =
        int.tryParse(bookText(row, ['duration', 'time_length'])) ?? 0;
    bool failed(Object? value) {
      if (value == null) return false;
      if (value is List) return value.isNotEmpty;
      return '$value' != '0' && '$value'.isNotEmpty;
    }

    return BookChapter(
      album: album,
      hash: bookText(row, ['hash', 'play_hash', 'FileHash']),
      mixId: bookText(row, ['album_audio_id', 'mixsongid', 'MixSongID']),
      name: bookText(row, [
        'audio_name',
        'filename',
        'song_name',
        'SongName',
        'title',
        'name',
      ]),
      author: bookText(row, ['author_name', 'singer_name', 'SingerName']),
      cover: PlatformArtwork.fromPayload(row),
      // Explicit millisecond fields never change units for short chapters.
      duration: Duration(
        milliseconds: milliseconds > 0 ? milliseconds : seconds * 1000,
      ),
      canPlay: !failed(row['fail_process_128']) && !failed(row['fail_process']),
    );
  }
  bool get valid => hash.isNotEmpty || mixId.isNotEmpty;
  Track get track => Track(
    // Stable IDs retain enough identity for a signed URL to be refreshed after
    // restart. The URL itself must not be the only copy of chapter identity.
    id: 'audiobooks_${album.id}_${mixId.isEmpty ? '0' : mixId}_${hash.isEmpty ? 'none' : hash}',
    title: name.isEmpty ? '听书章节' : name,
    artist: author.isEmpty ? album.author : author,
    album: album.name,
    duration: duration,
    audioAsset: Uri(
      scheme: 'mesting-audiobook',
      host: 'chapter',
      path: '/${album.id}',
      queryParameters: {'hash': hash, 'mixsongid': mixId},
    ).toString(),
    coverAsset: cover.isEmpty ? album.cover : cover,
    lyricsAsset: '',
    source: TrackSource.kugou,
    provider: '酷狗听书',
    platformSongId: mixId,
    availabilityMessage: canPlay ? '联网获取章节播放地址' : '此章节需要相应购买或会员权限',
  );
}

class BookPage<T> {
  const BookPage(this.items, {required this.hasMore, required this.page});
  final List<T> items;
  final bool hasMore;
  final int page;
}

/// Parses only Mesting's own stable chapter identities, never an arbitrary URL.
({String albumId, String mixId, String hash})? bookIdentity(Track track) {
  if (!track.id.startsWith('audiobooks_')) return null;
  final parts = track.id.substring('audiobooks_'.length).split('_');
  if (parts.length != 3 ||
      !RegExp(r'^\d+$').hasMatch(parts[0]) ||
      !RegExp(r'^\d+$').hasMatch(parts[1]) ||
      parts[2] != 'none' && !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(parts[2])) {
    return null;
  }
  return (
    albumId: parts[0],
    mixId: parts[1] == '0' ? '' : parts[1],
    hash: parts[2] == 'none' ? '' : parts[2],
  );
}
