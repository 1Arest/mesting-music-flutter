import 'dart:convert';

import '../../shared/models/track.dart';
import '../music_platform/data/platform_artwork.dart';

/// Contracts ported from md3Music a69503b (AGPL-3.0). Room identifiers,
/// copyright hashes and mixsong IDs remain separate throughout the adapter.
Map<String, dynamic> togetherMap(Object? value) {
  if (value is String && value.trim().startsWith('{')) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return {};
    }
  }
  return value is Map ? value.map((k, v) => MapEntry('$k', v)) : {};
}

Object? togetherData(Object? value) {
  for (var i = 0; i < 5; i++) {
    final map = togetherMap(value);
    if (!map.containsKey('data')) return value;
    value = map['data'];
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return value;
      }
    }
  }
  return value;
}

String togetherText(Map row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if ((value is String || value is num) && '$value'.trim().isNotEmpty) {
      return '$value'.trim();
    }
  }
  return '';
}

int togetherInt(Map row, List<String> keys, [int fallback = 0]) =>
    int.tryParse(togetherText(row, keys)) ?? fallback;

List<Map<String, dynamic>> togetherRows(Object? payload, [int depth = 0]) {
  if (depth > 5) return [];
  final value = togetherData(payload);
  if (value is List) return value.whereType<Map>().map(togetherMap).toList();
  final row = togetherMap(value);
  for (final key in const [
    'list',
    'songs',
    'song_info',
    'song_infos',
    'songs_info',
    'audios',
    'items',
    'members',
    'member_list',
    'user_list',
    'audio_list',
    'music_list',
    'rooms',
    'room_list',
    'infos',
    'info',
    'room_info',
  ]) {
    final child = row[key];
    if (child is List) return child.whereType<Map>().map(togetherMap).toList();
    if (child is Map || child is String) {
      final result = togetherRows(child, depth + 1);
      if (result.isNotEmpty) return result;
    }
  }
  return [];
}

String togetherNestedText(Object? payload, List<String> keys, [int depth = 0]) {
  if (depth > 6) return '';
  if (payload is Map) {
    final direct = togetherText(payload, keys);
    if (direct.isNotEmpty) return direct;
    for (final value in payload.values) {
      final found = togetherNestedText(value, keys, depth + 1);
      if (found.isNotEmpty) return found;
    }
  } else if (payload is List) {
    for (final value in payload) {
      final found = togetherNestedText(value, keys, depth + 1);
      if (found.isNotEmpty) return found;
    }
  }
  return '';
}

class TogetherRoom {
  const TogetherRoom({
    required this.id,
    required this.name,
    this.ownerId = '',
    this.cover = '',
    this.memberCount,
    this.closed = false,
  });
  final String id, name, ownerId, cover;
  final int? memberCount;
  final bool closed;

  factory TogetherRoom.fromJson(Map<String, dynamic> json) {
    final row = {
      ...togetherMap(json['room_info']),
      ...togetherMap(json['base_info']),
      ...json,
    };
    final owner = {
      ...togetherMap(json['user_info']),
      ...togetherMap(json['owner_info']),
    };
    final name = togetherText(row, [
      'room_name',
      'introduction',
      'room_theme',
      'name',
    ]);
    final nickname = togetherText(owner, ['nick_name', 'nickname']);
    final count = togetherText(row, [
      'member_count',
      'online_count',
      'online_user_count',
      'all_user_count',
      'member_num',
    ]);
    return TogetherRoom(
      id: togetherText(row, ['room_id', 'roomid', 'groupid', 'group_id', 'id']),
      name: name.isNotEmpty
          ? name
          : nickname.isNotEmpty
          ? '$nickname的一起听'
          : '一起听房间',
      ownerId: togetherText(row, ['owner_id', 'owner_userid']).isNotEmpty
          ? togetherText(row, ['owner_id', 'owner_userid'])
          : togetherText(owner, ['userid', 'owner_id', 'uid']),
      cover: PlatformArtwork.fromPayload(row),
      memberCount: int.tryParse(count),
      closed:
          row['is_hide']?.toString() == '1' ||
          row['room_status']?.toString() == '0',
    );
  }
}

class TogetherMember {
  const TogetherMember(this.id, this.name, this.avatar);
  final String id, name, avatar;
  factory TogetherMember.fromJson(Map<String, dynamic> json) {
    final row = {
      ...togetherMap(json['user_info']),
      ...togetherMap(json['member_info']),
      ...json,
    };
    final name = togetherText(row, [
      'nick_name',
      'nickname',
      'username',
      'user_name',
      'name',
    ]);
    return TogetherMember(
      togetherText(row, ['userid', 'user_id', 'uid', 'id']),
      name.isEmpty ? '房间成员' : name,
      PlatformArtwork.normalize(
        togetherText(row, [
          'user_pic',
          'avatar',
          'headimg',
          'head_img',
          'img',
          'pic',
        ]),
      ),
    );
  }
}

class TogetherSong {
  const TogetherSong({
    required this.hash,
    this.originalHash = '',
    this.mixId = '',
    this.title = '',
    this.artist = '',
    this.cover = '',
    this.duration = Duration.zero,
  });
  final String hash, originalHash, mixId, title, artist, cover;
  final Duration duration;
  factory TogetherSong.fromJson(Map<String, dynamic> json) {
    final row = {
      ...togetherMap(json['album_info']),
      ...togetherMap(json['song_info']),
      ...togetherMap(json['audio_info']),
      ...togetherMap(json['audio']),
      ...json,
    };
    final original = togetherText(row, ['genting_hash', 'original_hash']);
    final hash = togetherText(row, ['hash', 'file_hash', 'audio_hash']);
    final milliseconds = togetherInt(row, ['duration_ms', 'timelength']);
    final seconds = togetherInt(row, ['duration', 'time_length']);
    return TogetherSong(
      hash: hash.isEmpty ? original : hash,
      originalHash: original,
      mixId: togetherText(row, [
        'mixsongid',
        'mixSongId',
        'mix_song_id',
        'album_audio_id',
        'genting_album_audio_id',
      ]),
      title: togetherText(row, [
        'songname',
        'song_name',
        'audio_name',
        'filename',
        'name',
        'title',
      ]),
      artist: togetherText(row, [
        'singername',
        'singer_name',
        'author_name',
        'singer',
      ]),
      cover: PlatformArtwork.fromPayload(row),
      duration: Duration(
        milliseconds: milliseconds > 0 ? milliseconds : seconds * 1000,
      ),
    );
  }
  static TogetherSong? fromTrack(Track track) {
    if (track.source != TrackSource.kugou || !track.id.startsWith('kugou_')) {
      return null;
    }
    final hash = track.id.substring(6);
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hash)) return null;
    return TogetherSong(
      hash: hash,
      mixId: track.platformSongId,
      title: track.title,
      artist: track.artist,
      cover: track.coverAsset,
      duration: track.duration,
    );
  }

  bool matches(String otherHash, String otherMix) =>
      otherHash.isNotEmpty &&
          {
            hash.toLowerCase(),
            originalHash.toLowerCase(),
          }.contains(otherHash.toLowerCase()) ||
      mixId.isNotEmpty && mixId != '0' && mixId == otherMix;
  Map<String, Object?> get audio => {
    'hash': hash,
    'mixsongid': mixId,
    'fid': 0,
  };
  Track get track => Track(
    id: 'kugou_$hash',
    title: title.isEmpty ? '房间歌曲' : title,
    artist: artist,
    album: '一起听',
    duration: duration,
    audioAsset: 'mesting-platform://kugou/kugou_$hash',
    coverAsset: cover,
    lyricsAsset: '',
    source: TrackSource.kugou,
    provider: '酷狗一起听',
    platformSongId: mixId,
  );
}

class TogetherPlayerSnapshot {
  const TogetherPlayerSnapshot({
    required this.hash,
    required this.mixId,
    required this.playing,
    required this.position,
    required this.receivedAt,
    this.listVersion = '',
  });
  final String hash, mixId, listVersion;
  final bool playing;
  final Duration position;
  final DateTime receivedAt;
  factory TogetherPlayerSnapshot.parse(Object? payload, {DateTime? now}) {
    final data = togetherMap(togetherData(payload));
    final row = {
      ...togetherMap(data['audio']),
      ...togetherMap(data['current_audio']),
      ...togetherMap(data['song']),
      ...togetherMap(data['progress_info']),
      ...data,
    };
    // The room protocol explicitly uses seconds for progress and 1/2 for pause.
    // Do not infer milliseconds from a long audiobook-sized progress value.
    final progress = togetherInt(row, [
      'progress',
      'play_progress',
      'current_time',
      'position',
    ]);
    final paused = togetherText(row, ['pause']);
    return TogetherPlayerSnapshot(
      hash: togetherText(row, [
        'hash',
        'cur_song',
        'file_hash',
        'genting_hash',
      ]),
      mixId: togetherText(row, ['mixsongid', 'mix_song_id', 'album_audio_id']),
      playing: paused.isNotEmpty
          ? paused == '1'
          : row['playing'] == true || row['is_playing'] == true,
      position: Duration(seconds: progress.clamp(0, 864000)),
      receivedAt: now ?? DateTime.now(),
      listVersion: togetherNestedText(payload, ['list_version']),
    );
  }
  Duration projected(DateTime now) =>
      position +
      (playing && now.isAfter(receivedAt)
          ? now.difference(receivedAt)
          : Duration.zero);
}
