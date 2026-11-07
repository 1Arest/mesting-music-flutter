import '../../../shared/models/track.dart';
import '../domain/platform_audio_quality.dart';
import '../netease/fallback/netease_audio_probe.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';

/// Typed feature adapter. Account ownership is captured at construction; a
/// delayed old repository can never send through a newly configured identity.
class QishuiRepository {
  QishuiRepository(this.api)
    : credential = api.credential,
      _ownerAbort = api.identityAbort;
  final QishuiApi api;
  final Future<void> _ownerAbort;
  Future<void> _abort(Future<void>? caller) =>
      caller == null ? _ownerAbort : Future.any([_ownerAbort, caller]);
  final String? credential;
  bool get current => credential != null && api.credential == credential;
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    bool get = false,
    bool write = false,
    Future<void>? abortTrigger,
  }) {
    if (!current) throw const QishuiException('账号已变化，请重新打开');
    return api.request(
      path,
      body: body,
      query: query,
      get: get,
      write: write,
      expectedCredential: credential,
      abortTrigger: abortTrigger,
    );
  }

  Future<List<QishuiPlaylist>> discover({Future<void>? abortTrigger}) async =>
      QishuiPlaylist.parse(
        await call(
          '/luna/discover/mix',
          body: {'count': 24},
          abortTrigger: abortTrigger,
        ),
      );
  Future<List<Track>> search(
    String query, {
    String cursor = '',
    Future<void>? abortTrigger,
  }) async => sodaTracks(
    await call(
      '/luna/search/track',
      body: {
        'q': query.trim(),
        'cursor': cursor,
        'search_type': 'track',
        'search_method': 'normal',
        'search_id': '',
      },
      abortTrigger: abortTrigger,
    ),
  );
  Future<List<Track>> playlist(
    String id, {
    String cursor = '',
    Future<void>? abortTrigger,
  }) async {
    final result = <String, Track>{};
    final cursors = <String>{};
    for (var page = 0; page < 1000; page++) {
      final data = await call(
        '/luna/playlist/detail',
        body: {'playlist_id': id, 'cursor': cursor, 'count': 100},
        abortTrigger: abortTrigger,
      );
      final returnedId = '${sodaMap(data['playlist'])['id'] ?? ''}';
      if (returnedId.isNotEmpty && returnedId != id) {
        throw const QishuiException('汽水返回的歌单不匹配');
      }
      for (final track in sodaTracks(data)) {
        result[track.id] = track;
      }
      if (data['has_more'] != true) return List.unmodifiable(result.values);
      final next = '${data['next_cursor'] ?? ''}';
      if (next.isEmpty || next == cursor || !cursors.add(next)) {
        throw const QishuiException('歌单续载位置异常，请重新读取');
      }
      cursor = next;
    }
    throw const QishuiException('歌单读取超出本次上限，未将不完整列表当作全部歌曲');
  }

  Future<List<Track>> feed({
    QishuiFeedMode? mode,
    Future<void>? abortTrigger,
  }) async => sodaTracks(
    await call(
      '/luna/feed/song-tab',
      body: {'count': 20, if (mode != null) 'feed_preference': mode.preference},
      abortTrigger: abortTrigger,
    ),
  );
  Future<List<QishuiFeedMode>> modes() async =>
      QishuiFeedMode.parse(await call('/luna/feed/mode'));
  Future<Map<String, dynamic>> profile() => call('/luna/me', get: true);
  Future<List<QishuiPlaylist>> playlists({Future<void>? abortTrigger}) async {
    final result = <String, QishuiPlaylist>{};
    final seen = <String>{};
    var cursor = '';
    for (var page = 0; page < 1000; page++) {
      final data = await call(
        '/luna/me/playlist/v2',
        body: {'cursor': cursor, 'count': 50},
        abortTrigger: abortTrigger,
      );
      for (final list in QishuiPlaylist.parse(data)) {
        result[list.id] = list;
      }
      if (data['has_more'] != true) return List.unmodifiable(result.values);
      final next = '${data['next_cursor'] ?? ''}';
      if (next.isEmpty || next == cursor || !seen.add(next)) {
        throw const QishuiException('歌单目录续载异常，请重试');
      }
      cursor = next;
    }
    throw const QishuiException('歌单目录读取尚未完成');
  }

  Future<List<Track>> favorites({Future<void>? abortTrigger}) async {
    final matches = (await playlists(
      abortTrigger: abortTrigger,
    )).where((p) => p.kind == 1).toList();
    if (matches.length != 1) throw const QishuiException('汽水未返回唯一的我喜欢歌单，请刷新核对');
    return playlist(matches.single.id, abortTrigger: abortTrigger);
  }

  Future<void> setFavorite(Track track, bool favorite) async {
    if (track.source != TrackSource.qishui) {
      throw const QishuiException('汽水收藏仅支持汽水歌曲');
    }
    await call(
      favorite
          ? '/luna/me/collection/media'
          : '/luna/me/collection/media/delete',
      body: {
        'media': [
          {'id': track.platformSongId, 'type': 'track'},
        ],
      },
      write: true,
    );
    final confirmed = (await favorites()).any((t) => t.id == track.id);
    if (confirmed != favorite) {
      throw const QishuiException('已提交收藏，服务端状态尚未确认，请刷新核对');
    }
  }

  Future<List<Track>> recent({Future<void>? abortTrigger}) async => sodaTracks(
    await call(
      '/luna/me/recently-played-media',
      get: true,
      query: {'cursor': '', 'count': '50'},
      abortTrigger: abortTrigger,
    ),
  );
  Future<Map<String, dynamic>> commerce({Future<void>? abortTrigger}) => call(
    '/luna/commerce/v2/commerce_info',
    abortTrigger: abortTrigger,
    body: {
      'includes': [
        'treasure',
        'play_entitlements',
        'activity_free_vip',
        'membership',
        'benefit_base',
      ],
    },
  );

  Future<Map<String, dynamic>> media(String id, {Future<void>? abortTrigger}) =>
      call(
        '/luna/media_v2',
        body: {
          'media': [
            {'id': id, 'type': 'track'},
          ],
        },
        abortTrigger: abortTrigger,
      );

  /// Some mobile media responses defer the video model to a signed public
  /// player-info URL. Fetch it anonymously with a bounded body; credentials
  /// belong only to the fixed Luna host, never to a CDN or signing service.
  Future<Map<String, dynamic>> _playbackData(
    String id,
    Future<void>? abortTrigger,
  ) async {
    abortTrigger = _abort(abortTrigger);
    final data = await media(id, abortTrigger: abortTrigger);
    final urls = <String>{};
    void visit(Object? value, int depth) {
      if (depth > 12) return;
      if (value is List) {
        for (final v in value) {
          visit(v, depth + 1);
        }
      }
      if (value is Map) {
        for (final entry in value.entries) {
          if ({'url_player_info', 'urlPlayerInfo'}.contains(entry.key) &&
              entry.value is String) {
            urls.add(entry.value as String);
          } else if (entry.value is Map || entry.value is List) {
            visit(entry.value, depth + 1);
          }
        }
      }
    }

    visit(data, 0);
    final models = <Object>[];
    for (final url in urls.take(3)) {
      final uri = Uri.tryParse(url);
      if (uri?.scheme != 'https' ||
          uri!.userInfo.isNotEmpty ||
          !(uri.host == 'open.bytedanceapi.com' ||
              uri.host.endsWith('.volcvod.com') ||
              uri.host.endsWith('.douyinvod.com') ||
              uri.host.endsWith('.bytecdn.cn'))) {
        continue;
      }
      final response = await sendMusicRequest(
        client: api.client,
        platform: 'qishui',
        operation: MusicNetworkOperation.playbackUrl,
        abortTrigger: abortTrigger,
        maximumResponseBytes: 2 * 1024 * 1024,
        build: (abort) =>
            http.AbortableRequest('GET', uri, abortTrigger: abort)
              ..followRedirects = false,
      );
      if (!current) throw const QishuiException('账号已变化，请重新播放');
      if (response.statusCode == 200) {
        try {
          models.add(jsonDecode(utf8.decode(response.bodyBytes)) as Object);
        } on FormatException {
          throw const QishuiException('汽水播放资料无法读取');
        }
      }
    }
    return {'media': data, 'player_models': models};
  }

  Future<Set<PlatformAudioQuality>> qualities(String id) async {
    final values = QishuiMedia.parse(
      await _playbackData(id.replaceFirst('qishui_', ''), null),
    );
    return {
      for (final value in values.where((v) => !v.encrypted && v.bitrate > 0))
        value.bitrate > 220000
            ? PlatformAudioQuality.high
            : PlatformAudioQuality.standard,
    };
  }

  Future<Track> resolve(
    Track track, {
    bool download = false,
    PlatformAudioQuality? quality,
    bool requireQuality = true,
    Future<void>? abortTrigger,
  }) async {
    if (track.source != TrackSource.qishui || !current) {
      throw const QishuiException('请先切换到汽水账号');
    }
    if (track.duration <= Duration.zero) {
      throw const QishuiException('汽水未返回歌曲时长，暂不能确认完整版');
    }
    abortTrigger = _abort(abortTrigger);
    final data = await _playbackData(track.platformSongId, abortTrigger);
    final candidates =
        QishuiMedia.parse(data).where((v) => !v.encrypted).toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (candidates.isEmpty) {
      throw const QishuiException('汽水未提供可直接播放的音频，当前媒体授权或签名仍不可用');
    }
    final playable = candidates.where(
      (v) =>
          v.duration > Duration.zero &&
          (track.duration == Duration.zero ||
              v.duration.inSeconds + 5 >= track.duration.inSeconds),
    );
    if (playable.isEmpty) throw const QishuiException('汽水当前仅提供试听，未取得完整歌曲');
    final matching = playable
        .where(
          (v) =>
              quality == null ||
              quality == PlatformAudioQuality.high && v.bitrate > 220000 ||
              quality == PlatformAudioQuality.standard &&
                  v.bitrate > 0 &&
                  v.bitrate <= 220000,
        )
        .firstOrNull;
    final candidate =
        matching ?? (requireQuality ? null : playable.firstOrNull);
    if (candidate == null) throw const QishuiException('汽水未提供所选音质');
    if (download) {
      await _requireDownloadPermission(
        track.platformSongId,
        candidate,
        abortTrigger,
      );
    }
    final probe = await inspectNeteaseAudio(
      api.client,
      candidate.url,
      expectedDuration: track.duration,
      abortTrigger: abortTrigger,
      prefixBytes: 65536,
    );
    if (!current) throw const QishuiException('账号已变化，请重新播放');
    if (!probe.playable || !{'mp3', 'm4a', 'flac'}.contains(probe.format)) {
      throw const QishuiException('汽水音频完整性或格式核验未通过');
    }
    final bitrate = probe.bitrate;
    final actual = bitrate <= 0
        ? null
        : bitrate > 220000
        ? PlatformAudioQuality.high
        : PlatformAudioQuality.standard;
    if (requireQuality && quality != null && actual != quality) {
      throw const QishuiException('汽水未提供所选音质');
    }
    return track.copyWith(
      audioAsset: candidate.url,
      isPreview: false,
      playbackQuality: actual?.code ?? '',
      audioBitrate: bitrate,
      audioHeaders: const {},
      audioOrigin: AudioOrigin(AudioOrigin.qishui, track.platformSongId),
    );
  }

  Future<void> _requireDownloadPermission(
    String id,
    QishuiMedia media,
    Future<void>? abort,
  ) async {
    final quality = media.qualityCode;
    if (quality == null) throw const QishuiException('汽水未返回本音质的下载资格参数，暂不能保存');
    final result = await call(
      '/luna/commerce/v2/check_download',
      body: {
        'tracks': [
          {'track_id': id, 'quality': quality},
        ],
      },
      abortTrigger: abort,
    );
    final rows = sodaRows(result['track_download_info_list'])
        .where((row) => row['track_id'] == id && row['quality'] == quality)
        .toList();
    if (rows.length != 1 || rows.single['need_download_quota'] != false) {
      // Quota consumption is a distinct write contract. Never silently spend
      // quota, synthesize a grant or infer downloads from a playable URL.
      throw const QishuiException('汽水未确认无需额外扣额的下载资格，暂不能保存');
    }
  }

  Future<String> lyrics(String id) async {
    final data = await media(id);
    String? content;
    void visit(Object? value, int depth) {
      if (depth > 12 || content != null) return;
      if (value is List) {
        for (final item in value) {
          visit(item, depth + 1);
        }
      }
      if (value is Map) {
        final lyric = sodaMap(value['lyric']);
        if (lyric['content'] is String &&
            (lyric['content'] as String).trim().isNotEmpty) {
          content = lyric['content'] as String;
          return;
        }
        for (final key in [
          'media',
          'entity',
          'track_wrapper',
          'track',
          'data',
        ]) {
          visit(value[key], depth + 1);
        }
      }
    }

    visit(data, 0);
    if (content == null) throw const QishuiException('汽水暂未提供这首歌的歌词');
    return qishuiLrc(content!);
  }
}

/// Preserve real line timing while removing the proprietary word-tag syntax.
/// Existing LRC is passed through; no synthetic lyrics or timestamps are made.
String qishuiLrc(String source) {
  if (RegExp(r'^\[\d+:\d+', multiLine: true).hasMatch(source)) return source;
  final lines = <String>[];
  for (final line in source.split('\n')) {
    final match = RegExp(r'^\[(\d+),(\d+)\](.*)$').firstMatch(line.trim());
    if (match == null) continue;
    final ms = int.parse(match[1]!);
    final text = match[3]!.replaceAll(RegExp(r'<\d+,\d+(?:,\d+)?>'), '');
    lines.add(
      '[${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}]$text',
    );
  }
  return lines.isEmpty ? source : lines.join('\n');
}
