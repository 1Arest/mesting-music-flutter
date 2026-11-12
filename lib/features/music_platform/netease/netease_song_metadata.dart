import '../../../shared/utils/media_uri.dart';

Map<String, dynamic> _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

/// Heartbeat, history and recommendations wrap songs differently. Prefer the
/// innermost recording over an outer recommendation/record ID; retain aliases
/// only when the upstream actually supplied them.
Map<String, dynamic> neteaseSongMetadata(Map<String, dynamic> row) {
  var song = row;
  for (var depth = 0; depth < 5; depth++) {
    Map<String, dynamic>? next;
    for (final key in ['songInfo', 'song', 'simpleSongInfo']) {
      if (song[key] is Map) {
        next = _object(song[key]);
        break;
      }
    }
    if (next == null || next.isEmpty) break;
    song = next;
  }
  return {
    ...song,
    'id': song['id'] ?? song['songId'],
    'name': song['name'] ?? song['songName'],
    'al': song['al'] ?? song['album'],
    'ar': song['ar'] ?? song['artists'],
  };
}

/// Empty/zero/image-ID DTO fields must not hide a later valid CDN URL.
String neteaseArtwork(Map<String, dynamic> row) {
  final album = _object(row['al'] ?? row['album']);
  final cover = _object(row['cover']);
  return firstArtworkUri([
    row['coverImgUrl'],
    row['coverUrl'],
    row['picUrl'],
    row['avatarUrl'],
    row['img1v1Url'],
    row['cover'],
    row['imageUrl'],
    row['imgUrl'],
    cover['url'],
    cover['picUrl'],
    cover['imageUrl'],
    album['picUrl'],
    album['coverImgUrl'],
    album['coverUrl'],
  ]);
}
