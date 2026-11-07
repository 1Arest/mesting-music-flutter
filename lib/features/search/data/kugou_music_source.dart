import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../shared/models/track.dart';
import '../domain/music_source.dart';
import 'abortable_json_client.dart';
import 'online_music_config.dart';

class KugouMusicSource implements MusicSource {
  KugouMusicSource(
    http.Client client, {
    String apiBaseUrl = OnlineMusicConfig.kugouApiBaseUrl,
    String publicSearchBaseUrl = 'https://songsearch.kugou.com/song_search_v2',
    String legacySongInfoBaseUrl = 'https://m.kugou.com/app/i/getSongInfo.php',
    String rankingBaseUrl = 'https://m.kugou.com/rank/info/',
  }) : _apiBaseUrl = OnlineMusicConfig.normalizeBaseUrl(apiBaseUrl),
       _publicSearchBaseUrl = publicSearchBaseUrl,
       _legacySongInfoBaseUrl = legacySongInfoBaseUrl,
       _rankingBaseUrl = rankingBaseUrl,
       _jsonClient = AbortableJsonClient(client);

  final String _apiBaseUrl;
  final String _publicSearchBaseUrl;
  final String _legacySongInfoBaseUrl;
  final String _rankingBaseUrl;
  final AbortableJsonClient _jsonClient;

  @override
  String get id => 'kugou';

  @override
  String get label => '酷狗概念版';

  // Public metadata search remains available without putting a provider
  // account cookie in the APK. The self-hosted service is only used for
  // signed playback/lyrics requests.
  @override
  bool get isConfigured => true;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    final uri = Uri.parse(_publicSearchBaseUrl).replace(
      queryParameters: {
        'keyword': query,
        'page': '1',
        'pagesize': '$limit',
        'platform': 'WebFilter',
        'tag': 'em',
      },
    );

    try {
      final payload = await _jsonClient.get(uri, abortTrigger: abortTrigger);
      final candidates = parseCandidates(payload).take(limit).toList();
      return _resolveCandidates(candidates, abortTrigger: abortTrigger);
    } on http.RequestAbortedException {
      rethrow;
    } on TimeoutException {
      throw const MusicSourceException(
        sourceLabel: '酷狗概念版',
        message: '连接超时，请稍后重试',
        isTimeout: true,
      );
    } on Object {
      throw const MusicSourceException(sourceLabel: '酷狗概念版', message: '暂时无法连接');
    }
  }

  /// Loads Kugou's current TOP chart and resolves only tracks that can really
  /// be played. The chart itself may contain member/region restricted items,
  /// so metadata-only entries are deliberately excluded here.
  Future<List<Track>> hotRanking({int limit = 9, Future<void>? abortTrigger}) {
    return ranking(
      rankId: '8888',
      sourceLabel: '酷狗实时榜',
      limit: limit,
      abortTrigger: abortTrigger,
    );
  }

  Future<List<Track>> ranking({
    required String rankId,
    required String sourceLabel,
    int limit = 9,
    Future<void>? abortTrigger,
  }) async {
    final uri = Uri.parse(
      _rankingBaseUrl,
    ).replace(queryParameters: {'rankid': rankId, 'page': '1', 'json': 'true'});
    try {
      final payload = await _jsonClient.get(uri, abortTrigger: abortTrigger);
      final candidates = parseRankingCandidates(
        payload,
      ).take((limit * 2).clamp(limit, 24)).toList(growable: false);
      final resolved = await _resolveCandidates(
        candidates,
        abortTrigger: abortTrigger,
      );
      return resolved
          .where((track) => track.isPlayable)
          .take(limit)
          .toList(growable: false);
    } on http.RequestAbortedException {
      rethrow;
    } on Object {
      throw MusicSourceException(
        sourceLabel: sourceLabel,
        message: '实时榜单暂时无法更新',
      );
    }
  }

  static List<KugouSearchCandidate> parseCandidates(Object? payload) {
    final root = _asMap(payload);
    final data = _asMap(root?['data']);
    final items = data?['info'] ?? data?['lists'];
    if (items is! List) return const [];

    return items
        .whereType<Map>()
        .map(_asMap)
        .whereType<Map<String, Object?>>()
        .map(KugouSearchCandidate.fromJson)
        .whereType<KugouSearchCandidate>()
        .toList(growable: false);
  }

  static List<KugouSearchCandidate> parseRankingCandidates(Object? payload) {
    final root = _asMap(payload);
    final songs = _asMap(root?['songs']);
    final items = songs?['list'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(_asMap)
        .whereType<Map<String, Object?>>()
        .map(KugouSearchCandidate.fromJson)
        .whereType<KugouSearchCandidate>()
        .toList(growable: false);
  }

  Future<List<Track>> _resolveCandidates(
    List<KugouSearchCandidate> candidates, {
    Future<void>? abortTrigger,
  }) async {
    if (candidates.isEmpty) return const [];
    final resolved = List<Track?>.filled(candidates.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < candidates.length) {
        final index = nextIndex++;
        resolved[index] = await _resolveCandidate(
          candidates[index],
          abortTrigger: abortTrigger,
        );
      }
    }

    final workerCount = candidates.length.clamp(1, 4);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return resolved.whereType<Track>().toList(growable: false);
  }

  Future<Track> _resolveCandidate(
    KugouSearchCandidate candidate, {
    Future<void>? abortTrigger,
  }) async {
    var audioUrl = '';
    var preview = false;

    if (_apiBaseUrl.isNotEmpty) {
      try {
        final payload = await _jsonClient.get(
          Uri.parse('$_apiBaseUrl/song/url').replace(
            queryParameters: {
              'hash': candidate.hash,
              'album_id': candidate.albumId,
              'album_audio_id': candidate.albumAudioId,
              'quality': '128',
            },
          ),
          abortTrigger: abortTrigger,
        );
        final audio = _extractAudio(payload);
        audioUrl = audio.url;
        preview = audio.isPreview;
      } on http.RequestAbortedException {
        rethrow;
      } on Object {
        // The official service can require device/account verification. Fall
        // back to its legacy play-info endpoint without bypassing restrictions.
      }
    }

    if (audioUrl.isEmpty) {
      try {
        final payload = await _jsonClient.get(
          Uri.parse(_legacySongInfoBaseUrl).replace(
            queryParameters: {
              'cmd': 'playInfo',
              'hash': candidate.hash,
              if (candidate.albumId.isNotEmpty) 'album_id': candidate.albumId,
            },
          ),
          abortTrigger: abortTrigger,
        );
        final audio = _extractAudio(payload);
        audioUrl = audio.url;
        preview = audio.isPreview;
      } on http.RequestAbortedException {
        rethrow;
      } on Object {
        // Keep the metadata visible and clearly mark it unavailable.
      }
    }

    // Lyrics can be resolved through the self-hosted service when configured,
    // or through Kugou's public lyrics endpoint as a client-side fallback.
    // Keep the locator even when no private API base URL was supplied.
    final lyricsLocator = Uri(
      scheme: 'mesting-lyrics',
      host: 'kugou',
      path: '/${candidate.hash}',
      queryParameters: {
        'albumAudioId': candidate.albumAudioId,
        'durationMs': '${candidate.duration.inMilliseconds}',
      },
    ).toString();

    return candidate.toTrack(
      audioUrl: _preferHttps(audioUrl),
      lyricsLocator: lyricsLocator,
      isPreview: preview,
    );
  }

  static _ResolvedAudio _extractAudio(Object? payload) {
    final root = _asMap(payload);
    if (root == null) return const _ResolvedAudio();
    final candidates = <Map<String, Object?>>[root];
    final data = root['data'];
    if (data is List && data.isNotEmpty) {
      final first = _asMap(data.first);
      if (first != null) candidates.add(first);
    } else {
      final map = _asMap(data);
      if (map != null) candidates.add(map);
    }
    for (final item in candidates) {
      for (final key in const ['url', 'play_url', 'backupUrl']) {
        final value = item[key]?.toString().trim() ?? '';
        if (value.isNotEmpty && value != 'null') {
          final freePart =
              item['freeTrialInfo'] != null ||
              item['is_free_part'] == 1 ||
              item['isFreePart'] == true;
          return _ResolvedAudio(url: value, isPreview: freePart);
        }
      }
    }
    return const _ResolvedAudio();
  }

  static String _preferHttps(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'http') return value;
    return uri.replace(scheme: 'https').toString();
  }

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}

class KugouSearchCandidate {
  const KugouSearchCandidate({
    required this.hash,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.coverUrl,
    required this.albumId,
    required this.albumAudioId,
  });

  final String hash;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String coverUrl;
  final String albumId;
  final String albumAudioId;

  static KugouSearchCandidate? fromJson(Map<String, Object?> item) {
    final hash =
        (item['hash'] ?? item['FileHash'])?.toString().trim().toLowerCase() ??
        '';
    final title = _plainText(
      (item['songname_original'] ??
              item['songname'] ??
              item['OriSongName'] ??
              item['SongName'])
          ?.toString(),
    );
    if (hash.isEmpty || title.isEmpty) return null;
    final transParam = KugouMusicSource._asMap(item['trans_param']);
    final authors = item['authors'];
    final firstAuthor = authors is List && authors.isNotEmpty
        ? KugouMusicSource._asMap(authors.first)
        : null;
    final rawCover =
        (transParam?['union_cover'] ??
                item['album_sizable_cover'] ??
                item['album_img'] ??
                item['Image'])
            ?.toString()
            .trim() ??
        '';
    return KugouSearchCandidate(
      hash: hash,
      title: title,
      artist: _plainText(
        (item['singername'] ??
                item['SingerName'] ??
                item['h5_author_name'] ??
                firstAuthor?['author_name'])
            ?.toString(),
        fallback: '未知音乐人',
      ),
      album:
          (item['album_name'] ?? item['AlbumName'])
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
          ? (item['album_name'] ?? item['AlbumName']).toString().trim()
          : '酷狗音乐',
      duration: Duration(seconds: _asInt(item['duration'] ?? item['Duration'])),
      coverUrl: KugouMusicSource._preferHttps(
        rawCover.replaceAll('{size}', '400'),
      ),
      albumId: (item['album_id'] ?? item['AlbumID'])?.toString() ?? '',
      albumAudioId:
          (item['album_audio_id'] ?? item['MixSongID'] ?? item['ID'])
              ?.toString() ??
          '',
    );
  }

  Track toTrack({
    required String audioUrl,
    required String lyricsLocator,
    required bool isPreview,
  }) {
    return Track(
      id: 'kugou_$hash',
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      audioAsset: audioUrl,
      coverAsset: coverUrl,
      lyricsAsset: lyricsLocator,
      source: TrackSource.kugou,
      provider: '酷狗概念版',
      isPreview: isPreview,
      externalUrl: 'https://www.kugou.com/song/#hash=$hash',
      availabilityMessage: audioUrl.isEmpty ? '该歌曲受会员、地区或版权限制，当前仅展示歌曲信息' : '',
    );
  }

  static int _asInt(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _plainText(String? value, {String fallback = ''}) {
    final text = (value ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .trim();
    return text.isEmpty ? fallback : text;
  }
}

class _ResolvedAudio {
  const _ResolvedAudio({this.url = '', this.isPreview = false});

  final String url;
  final bool isPreview;
}
