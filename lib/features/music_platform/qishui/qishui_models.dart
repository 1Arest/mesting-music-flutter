import 'dart:convert';
import '../../../shared/models/track.dart';

Map<String, dynamic> sodaMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
List<Map<String, dynamic>> sodaRows(Object? value) =>
    value is List ? value.whereType<Map>().map(sodaMap).toList() : const [];
int sodaInt(Object? value) => num.tryParse('$value')?.toInt() ?? 0;

class QishuiFeedMode {
  const QishuiFeedMode(this.id, this.name, this.preference);
  final String id, name;
  final Map<String, Object?> preference;
  static List<QishuiFeedMode> parse(Map<String, dynamic> value) {
    final modes = <String, QishuiFeedMode>{};
    final rows = [
      ...sodaRows(sodaMap(value['feed_mode_bar'])['feed_mode']),
      for (final block in sodaRows(value['feed_mode_block']))
        ...sodaRows(block['feed_mode']),
    ];
    for (final row in rows) {
      final name = '${row['text'] ?? ''}';
      final entity = sodaMap(row['entity']);
      final preference = sodaMap(entity['preference_mode']);
      final scene = sodaMap(entity['feed_scene_mode']);
      final mode = '${preference['mode'] ?? ''}';
      if (name.isEmpty) continue;
      if (row['type'] == 'preference_mode' && mode.isNotEmpty) {
        modes['pref:$mode'] = QishuiFeedMode('pref:$mode', name, {
          'preference_mode': mode,
        });
      } else if (row['type'] == 'scene_mode' && scene['scene_mode_id'] is num) {
        final id = sodaInt(scene['scene_mode_id']);
        if (id >= 0) {
          modes['scene:$id'] = QishuiFeedMode('scene:$id', name, {
            'scene_mode_id': id,
          });
        }
      }
    }
    return List.unmodifiable(modes.values);
  }
}

String sodaPicture(Object? value) {
  if (value == null) return '';
  if (value is String) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'https' && uri!.userInfo.isEmpty ? value : '';
  }
  if (value is List) {
    for (final entry in value) {
      final image = sodaPicture(entry);
      if (image.isNotEmpty) return image;
    }
  }
  final image = sodaMap(value);
  if (image.isEmpty) return '';
  final urls = image['urls'] ?? image['url_list'];
  if (urls is List && urls.isNotEmpty) {
    final base = sodaPicture(urls.first);
    final uri = '${image['uri'] ?? ''}';
    if (base.endsWith('/img/') && uri.isEmpty) return '';
    if (base.endsWith('/img/') && uri.isNotEmpty) {
      final template = '${image['template_prefix'] ?? ''}';
      return '$base$uri${template.isEmpty ? '' : '~$template-resize:960:960.png'}';
    }
    return base;
  }
  return sodaPicture(image['url']);
}

/// Catalog duration is milliseconds. Do not infer full playback or quality
/// from a catalog row; media resolution performs independent checks later.
Track? sodaTrack(Map<String, dynamic> row) {
  final wrapper = sodaMap(row['track_wrapper'] ?? row['trackWrapper']);
  if (wrapper.isNotEmpty) return sodaTrack(sodaMap(wrapper['track']));
  if (row['track'] is Map) return sodaTrack(sodaMap(row['track']));
  final id = '${row['id'] ?? row['track_id'] ?? ''}';
  final name = '${row['name'] ?? row['title'] ?? ''}';
  if (id.isEmpty ||
      name.isEmpty ||
      !(row.containsKey('duration') ||
          row.containsKey('artists') ||
          row.containsKey('artist'))) {
    return null;
  }
  final album = sodaMap(row['album']);
  final artists = sodaRows(row['artists']);
  return Track(
    id: 'qishui_$id',
    platformSongId: id,
    title: name,
    artist: artists.isEmpty
        ? '${sodaMap(row['artist'])['name'] ?? ''}'
        : artists
              .map((a) => '${a['name'] ?? ''}')
              .where((s) => s.isNotEmpty)
              .join(' / '),
    album: '${album['name'] ?? ''}',
    duration: Duration(
      milliseconds: sodaInt(row['duration'] ?? row['duration_ms']),
    ),
    coverAsset: sodaPicture(
      row['url_cover'] ?? row['cover_url'] ?? album['url_cover'],
    ),
    audioAsset: 'mesting-platform://qishui/$id',
    lyricsAsset: 'mesting-lyrics://qishui/$id',
    provider: '汽水音乐',
    source: TrackSource.qishui,
  );
}

/// Only recognized track-bearing DTOs are traversed, never arbitrary URLs.
List<Track> sodaTracks(Object? value) {
  final result = <String, Track>{};
  void visit(Object? value, int depth) {
    if (depth > 12) return;
    if (value is List) {
      for (final row in value) {
        visit(row, depth + 1);
      }
      return;
    }
    if (value is! Map) return;
    final row = sodaMap(value);
    final track = sodaTrack(row);
    if (track != null) {
      result[track.id] = track;
      return;
    }
    for (final key in [
      'data',
      'tracks',
      'media',
      'items',
      'entity',
      'entities',
      'track_wrapper',
      'track',
      'results',
      'result',
      'resources',
      'media_resources',
    ]) {
      visit(row[key], depth + 1);
    }
  }

  visit(value, 0);
  return List.unmodifiable(result.values);
}

class QishuiPlaylist {
  const QishuiPlaylist(
    this.id,
    this.name,
    this.cover, {
    this.count = 0,
    this.kind = 0,
  });
  final String id, name, cover;
  final int count;
  final int kind;
  static List<QishuiPlaylist> parse(Object? value) {
    final lists = <String, QishuiPlaylist>{};
    void visit(Object? value, int depth) {
      if (depth > 12) return;
      if (value is List) {
        for (final row in value) {
          visit(row, depth + 1);
        }
        return;
      }
      if (value is! Map) return;
      final row = sodaMap(value);
      final style = sodaMap(row['style']);
      final id =
          '${row['id'] ?? row['playlist_id'] ?? row['resource_id'] ?? ''}';
      final name = '${row['title'] ?? row['name'] ?? style['title'] ?? ''}';
      if (id.isNotEmpty &&
          name.isNotEmpty &&
          (row['type'] == 'playlist' ||
              row.containsKey('track_count') ||
              row.containsKey('count_tracks') ||
              row.containsKey('playlist_id'))) {
        lists[id] = QishuiPlaylist(
          id,
          name,
          sodaPicture(
            row['url_cover'] ?? row['cover_url'] ?? style['cover_url_list'],
          ),
          count: sodaInt(
            row['count_tracks'] ?? row['track_count'] ?? row['media_count'],
          ),
          kind: sodaInt(row['type']),
        );
      }
      for (final key in [
        'data',
        'playlists',
        'playlist',
        'blocks',
        'inner_block',
        'resources',
        'items',
        'mix',
        'list',
        'collections',
        'mixed_collections',
        'entity',
      ]) {
        visit(row[key], depth + 1);
      }
    }

    visit(value, 0);
    return List.unmodifiable(lists.values);
  }
}

class QishuiMedia {
  const QishuiMedia(
    this.url,
    this.duration,
    this.bitrate,
    this.encrypted, {
    this.qualityCode,
  });
  final String url;
  final Duration duration;
  final int bitrate;
  final bool encrypted;
  final int? qualityCode;

  static List<QishuiMedia> parse(Object? value) {
    final result = <QishuiMedia>[];
    void visit(
      Object? value,
      int depth,
      Duration inherited, [
      bool encrypted = false,
      int? inheritedQuality,
    ]) {
      if (depth > 14) return;
      if (value is String) {
        try {
          visit(
            jsonDecode(value),
            depth + 1,
            inherited,
            encrypted,
            inheritedQuality,
          );
        } on FormatException {
          /* Not JSON. */
        }
        return;
      }
      if (value is List) {
        for (final row in value) {
          visit(row, depth + 1, inherited, encrypted, inheritedQuality);
        }
        return;
      }
      if (value is! Map) return;
      final row = sodaMap(value);
      final protected =
          encrypted ||
          sodaInt(row['encrypted'] ?? row['encrypt']) != 0 ||
          ['sp', 'play_auth', 'encrypt_key'].any(
            (key) =>
                row[key] != null && !{'', '0', 'false'}.contains('${row[key]}'),
          );
      final qualityCode =
          int.tryParse('${row['quality'] ?? ''}') ?? inheritedQuality;
      // The surrounding track DTO also has a `duration`, in milliseconds.
      // Only a recognized player model/URL may supply seconds through this
      // generic key; never let a catalog duration make a preview appear full.
      final playerDuration =
          row.containsKey('video_list') ||
          row.containsKey('audio_list') ||
          row.containsKey('PlayInfoList') ||
          row.containsKey('main_url') ||
          row.containsKey('MainPlayUrl') ||
          row.containsKey('mainPlayUrl') ||
          row.containsKey('play_url');
      final rawDuration =
          num.tryParse(
            '${row['video_duration'] ?? (playerDuration ? row['duration'] : null) ?? 0}',
          ) ??
          0;
      final duration = rawDuration > 0
          ? Duration(microseconds: (rawDuration * 1000000).round())
          : inherited;
      final rawUrl =
          row['main_url'] ??
          row['MainPlayUrl'] ??
          row['mainPlayUrl'] ??
          row['play_url'];
      if (rawUrl is String && rawUrl.isNotEmpty) {
        var url = rawUrl;
        if (!url.startsWith('http')) {
          try {
            url = utf8.decode(base64.decode(base64.normalize(url)));
          } on Object {
            url = '';
          }
        }
        final uri = Uri.tryParse(url);
        if (uri?.scheme == 'https' &&
            uri!.host.isNotEmpty &&
            uri.userInfo.isEmpty) {
          var bitrate = sodaInt(
            row['bitrate'] ?? row['bit_rate'] ?? row['Bitrate'],
          );
          if (bitrate > 0 && bitrate < 1000) bitrate *= 1000;
          result.add(
            QishuiMedia(
              url,
              duration,
              bitrate,
              protected,
              qualityCode: qualityCode,
            ),
          );
        }
      }
      for (final key in [
        'data',
        'video_model',
        'VideoModel',
        'video_list',
        'audio_list',
        'video_info',
        'PlayInfoList',
        'PlayInfo',
        'url_list',
        'player_info',
        'media',
        'entity',
        'track_wrapper',
        'track',
        'player_models',
        'Result',
        'Data',
        'videoModel',
        'PlayInfoList',
      ]) {
        final child = row[key];
        if (child is Map && ['video_list', 'audio_list'].contains(key)) {
          for (final item in child.values) {
            visit(item, depth + 1, duration, protected, qualityCode);
          }
        } else {
          visit(child, depth + 1, duration, protected, qualityCode);
        }
      }
    }

    visit(value, 0, Duration.zero);
    return result;
  }
}
