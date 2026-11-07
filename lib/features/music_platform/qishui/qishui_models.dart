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
  if (row['track_info'] is Map) return sodaTrack(sodaMap(row['track_info']));
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
      'track_info',
      'seo_track',
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
    this.ownerId = '',
    this.ownerName = '',
    this.description = '',
    this.isPrivate,
    this.likeCount,
    this.commentCount,
    this.shareCount,
    this.collected,
  });
  final String id, name, cover;
  final int count;
  final int kind;
  final String ownerId, ownerName, description;
  final bool? isPrivate, collected;
  final int? likeCount, commentCount, shareCount;
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
        final owner = sodaMap(row['owner']);
        final stats = sodaMap(row['stats']);
        final state = sodaMap(row['state']);
        int? counter(Object? value) =>
            value == null ? null : int.tryParse('$value');
        bool? flag(Object? value) => value is bool ? value : null;
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
          ownerId: '${owner['id'] ?? ''}',
          ownerName: '${owner['nickname'] ?? owner['public_name'] ?? ''}',
          description: '${row['desc'] ?? ''}',
          isPrivate: flag(row['is_private']),
          likeCount: counter(stats['count_collected']),
          commentCount: counter(stats['count_commented']),
          shareCount: counter(stats['count_shared']),
          collected: flag(state['is_collected']),
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
    this.playAuth = '',
    this.format = '',
    this.fileSize = 0,
    this.encryptionMethod = '',
    this.qualityName = '',
  });
  final String url;
  final Duration duration;
  final int bitrate;
  final bool encrypted;
  final int? qualityCode;

  /// Ephemeral official response authorization. Never persist this in Track,
  /// diagnostics, a download manifest, filenames or an external signing call.
  final String playAuth;
  final String format;
  final int fileSize;
  final String encryptionMethod;
  final String qualityName;

  /// Unknown encryption is not equivalent to a clear stream. The native
  /// decoder only handles the CENC AES-CTR variant used by the pinned source.
  bool get canDecodeOfficial =>
      !encrypted ||
      (playAuth.isNotEmpty &&
          (encryptionMethod.isEmpty || encryptionMethod == 'cenc-aes-ctr'));
  bool get canDecodeAuthorized => canDecodeOfficial;

  static List<QishuiMedia> parse(Object? value) {
    final result = <String, QishuiMedia>{};
    var remainingNodes = 12000;
    String field(Map<String, dynamic> row, Iterable<String> keys) {
      for (final key in keys) {
        final value = row[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return '';
    }

    bool marked(Object? value) =>
        value != null && !{'', '0', 'false', 'null'}.contains('$value');

    String decodeUrl(String input) {
      var url = input;
      if (!url.startsWith('https://')) {
        try {
          url = utf8.decode(base64.decode(base64.normalize(input)));
        } on Object {
          return '';
        }
      }
      final uri = Uri.tryParse(url);
      return uri != null &&
              uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty &&
              uri.port == 443
          ? url
          : '';
    }

    void visit(
      Object? value,
      int depth,
      Duration inherited, [
      bool encrypted = false,
      int? inheritedQuality,
      String inheritedAuth = '',
      String inheritedMethod = '',
    ]) {
      if (depth > 18 || --remainingNodes < 0) return;
      if (value is String) {
        if (value.length > 4 * 1024 * 1024) return;
        try {
          visit(
            jsonDecode(value),
            depth + 1,
            inherited,
            encrypted,
            inheritedQuality,
            inheritedAuth,
            inheritedMethod,
          );
        } on FormatException {
          /* Not JSON. */
        }
        return;
      }
      if (value is List) {
        for (final row in value) {
          visit(
            row,
            depth + 1,
            inherited,
            encrypted,
            inheritedQuality,
            inheritedAuth,
            inheritedMethod,
          );
        }
        return;
      }
      if (value is! Map) return;
      final row = sodaMap(value);
      final meta = sodaMap(row['video_meta'] ?? row['VideoMeta']);
      final encryptInfo = sodaMap(
        row['encrypt_info'] ?? row['EncryptInfo'] ?? row['encryptInfo'],
      );
      final auth = field(row, ['play_auth', 'PlayAuth', 'spade_a', 'SpadeA']);
      final nestedAuth = field(encryptInfo, [
        'spade_a',
        'SpadeA',
        'spadeA',
        'play_auth',
        'PlayAuth',
      ]);
      final authorization = auth.isNotEmpty
          ? auth
          : nestedAuth.isNotEmpty
          ? nestedAuth
          : inheritedAuth;
      var ownMethod = field(row, [
        'EncryptionMethod',
        'encryption_method',
        'encryptionMethod',
      ]).toLowerCase();
      if (ownMethod.isEmpty) {
        ownMethod = field(encryptInfo, [
          'encryption_method',
          'EncryptionMethod',
        ]).toLowerCase();
      }
      final method = ownMethod.isEmpty ? inheritedMethod : ownMethod;
      final protected =
          encrypted ||
          marked(row['encrypted'] ?? row['encrypt']) ||
          marked(encryptInfo['encrypt']) ||
          marked(row['sp']) ||
          marked(row['encrypt_key']) ||
          authorization.isNotEmpty ||
          method.isNotEmpty;
      final qualityCode =
          int.tryParse(
            '${row['quality'] ?? row['Quality'] ?? meta['quality'] ?? ''}',
          ) ??
          inheritedQuality;
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
          row.containsKey('main_play_url') ||
          row.containsKey('play_url');
      final rawDuration =
          num.tryParse(
            '${row['video_duration'] ?? (playerDuration ? row['Duration'] ?? row['duration'] : null) ?? 0}',
          ) ??
          0;
      final duration = rawDuration.isFinite && rawDuration > 0
          ? Duration(microseconds: (rawDuration * 1000000).round())
          : inherited;
      // Only explicit media URL fields count. A cover/account URL elsewhere
      // in a DTO must never become an audio candidate.
      for (final rawUrl in [
        field(row, [
          'main_url',
          'MainPlayUrl',
          'mainPlayUrl',
          'main_play_url',
          'play_url',
        ]),
        field(row, [
          'BackupPlayUrl',
          'backup_play_url',
          'backup_url',
          'backup_url_1',
        ]),
      ]) {
        final url = decodeUrl(rawUrl);
        if (url.isNotEmpty) {
          var bitrate = sodaInt(
            row['bitrate'] ??
                row['bit_rate'] ??
                row['Bitrate'] ??
                meta['bitrate'] ??
                meta['real_bitrate'],
          );
          if (bitrate > 0 && bitrate < 1000) bitrate *= 1000;
          result.putIfAbsent(
            url,
            () => QishuiMedia(
              url,
              duration,
              bitrate,
              protected,
              qualityCode: qualityCode,
              playAuth: authorization,
              format:
                  (field(row, [
                            'Format',
                            'format',
                            'file_format',
                            'vtype',
                          ]).isEmpty
                          ? field(meta, ['format', 'vtype'])
                          : field(row, [
                              'Format',
                              'format',
                              'file_format',
                              'vtype',
                            ]))
                      .toLowerCase(),
              fileSize: sodaInt(
                row['Size'] ?? row['size'] ?? row['file_size'] ?? meta['size'],
              ),
              encryptionMethod: method,
              qualityName:
                  (field(row, ['Quality', 'quality', 'definition']).isEmpty
                          ? field(meta, ['quality', 'definition'])
                          : field(row, ['Quality', 'quality', 'definition']))
                      .toLowerCase(),
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
        'track_info',
        'track_player',
        'trackPlayer',
        'player_models',
        'Result',
        'Data',
        'videoModel',
      ]) {
        final child = row[key];
        if (child is Map && ['video_list', 'audio_list'].contains(key)) {
          for (final item in child.values) {
            visit(
              item,
              depth + 1,
              duration,
              protected,
              qualityCode,
              authorization,
              method,
            );
          }
        } else {
          visit(
            child,
            depth + 1,
            duration,
            protected,
            qualityCode,
            authorization,
            method,
          );
        }
      }
    }

    visit(value, 0, Duration.zero);
    return List.unmodifiable(result.values);
  }
}
