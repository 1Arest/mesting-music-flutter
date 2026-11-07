import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../shared/models/track.dart';
import '../domain/music_source.dart';
import 'abortable_json_client.dart';
import 'online_music_config.dart';

class NeteaseMusicSource implements MusicSource {
  NeteaseMusicSource(
    http.Client client, {
    String apiBaseUrl = OnlineMusicConfig.neteaseApiBaseUrl,
    bool enabled = OnlineMusicConfig.enableNeteaseSource,
  }) : _apiBaseUrl = OnlineMusicConfig.normalizeBaseUrl(apiBaseUrl),
       _enabled = enabled,
       _jsonClient = AbortableJsonClient(client);

  final String _apiBaseUrl;
  final bool _enabled;
  final AbortableJsonClient _jsonClient;

  @override
  String get id => 'netease';

  @override
  String get label => '网易云 Enhanced';

  @override
  bool get isConfigured => _enabled && _apiBaseUrl.isNotEmpty;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    if (!isConfigured) return const [];
    try {
      final payload = await _jsonClient.get(
        Uri.parse('$_apiBaseUrl/cloudsearch').replace(
          queryParameters: {'keywords': query, 'limit': '$limit', 'type': '1'},
        ),
        abortTrigger: abortTrigger,
      );
      final candidates = parseCandidates(payload).take(limit).toList();
      return _resolveCandidates(candidates, abortTrigger: abortTrigger);
    } on http.RequestAbortedException {
      rethrow;
    } on TimeoutException {
      throw const MusicSourceException(
        sourceLabel: '网易云 Enhanced',
        message: '连接超时，请稍后重试',
        isTimeout: true,
      );
    } on Object {
      throw const MusicSourceException(
        sourceLabel: '网易云 Enhanced',
        message: '暂时无法连接',
      );
    }
  }

  static List<NeteaseSearchCandidate> parseCandidates(Object? payload) {
    final root = _asMap(payload);
    final result = _asMap(root?['result']);
    final songs = result?['songs'];
    if (songs is! List) return const [];
    return songs
        .whereType<Map>()
        .map(_asMap)
        .whereType<Map<String, Object?>>()
        .map(NeteaseSearchCandidate.fromJson)
        .whereType<NeteaseSearchCandidate>()
        .toList(growable: false);
  }

  Future<List<Track>> _resolveCandidates(
    List<NeteaseSearchCandidate> candidates, {
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
    NeteaseSearchCandidate candidate, {
    Future<void>? abortTrigger,
  }) async {
    if (!candidate.mayPlayWithoutUnlock) {
      return candidate.toTrack();
    }

    try {
      final payload = await _jsonClient.get(
        Uri.parse('$_apiBaseUrl/song/url/v1').replace(
          queryParameters: {
            'id': candidate.songId,
            'level': 'standard',
            // This must remain false. The client never calls match/unblock APIs.
            'unblock': 'false',
          },
        ),
        abortTrigger: abortTrigger,
      );
      final root = _asMap(payload);
      final data = root?['data'];
      final item = data is List && data.isNotEmpty ? _asMap(data.first) : null;
      if (item == null) return candidate.toTrack();

      final url = item['url']?.toString().trim() ?? '';
      final fee = _asInt(item['fee']);
      final payed = _asInt(item['payed']);
      final trialInfo = item['freeTrialInfo'];
      final isPreview = trialInfo != null;

      // A backend with ENABLE_GENERAL_UNBLOCK=true can replace restricted URLs.
      // Refuse those replacements even if a URL is returned.
      final looksLikeUnlockedReplacement =
          (fee == 1 || fee == 4) && payed <= 0 && !isPreview;
      if (url.isEmpty || looksLikeUnlockedReplacement) {
        return candidate.toTrack();
      }
      return candidate.toTrack(
        // Use the official 302 endpoint as a stable playback locator. It
        // refreshes the short-lived CDN URL whenever a saved queue or playlist
        // is played again and does not run the general-unblock middleware.
        audioUrl: Uri.parse('$_apiBaseUrl/song/url/v1/302')
            .replace(
              queryParameters: {'id': candidate.songId, 'level': 'standard'},
            )
            .toString(),
        isPreview: isPreview,
      );
    } on http.RequestAbortedException {
      rethrow;
    } on Object {
      return candidate.toTrack();
    }
  }

  static String _preferHttps(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'http') return value;
    return uri.replace(scheme: 'https').toString();
  }

  static int _asInt(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}

class NeteaseSearchCandidate {
  const NeteaseSearchCandidate({
    required this.songId,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.coverUrl,
    required this.mayPlayWithoutUnlock,
  });

  final String songId;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String coverUrl;
  final bool mayPlayWithoutUnlock;

  static NeteaseSearchCandidate? fromJson(Map<String, Object?> item) {
    final songId = item['id']?.toString().trim() ?? '';
    final title = item['name']?.toString().trim() ?? '';
    if (songId.isEmpty || title.isEmpty) return null;

    final albumData = NeteaseMusicSource._asMap(item['al']);
    final artists = item['ar'];
    final artistNames = artists is List
        ? artists
              .whereType<Map>()
              .map(NeteaseMusicSource._asMap)
              .whereType<Map<String, Object?>>()
              .map((artist) => artist['name']?.toString().trim() ?? '')
              .where((name) => name.isNotEmpty)
              .join(' / ')
        : '';
    final privilege = NeteaseMusicSource._asMap(item['privilege']);
    final playBitrate = NeteaseMusicSource._asInt(privilege?['pl']);

    return NeteaseSearchCandidate(
      songId: songId,
      title: title,
      artist: artistNames.isEmpty ? '未知音乐人' : artistNames,
      album: albumData?['name']?.toString().trim().isNotEmpty == true
          ? albumData!['name'].toString().trim()
          : '网易云音乐',
      duration: Duration(milliseconds: NeteaseMusicSource._asInt(item['dt'])),
      coverUrl: NeteaseMusicSource._preferHttps(
        albumData?['picUrl']?.toString().trim() ?? '',
      ),
      mayPlayWithoutUnlock: privilege == null || playBitrate > 0,
    );
  }

  Track toTrack({String audioUrl = '', bool isPreview = false}) {
    return Track(
      id: 'netease_$songId',
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      audioAsset: audioUrl,
      coverAsset: coverUrl,
      lyricsAsset: Uri(
        scheme: 'mesting-lyrics',
        host: 'netease',
        path: '/$songId',
      ).toString(),
      source: TrackSource.netease,
      provider: '网易云 Enhanced',
      isPreview: isPreview,
      externalUrl: 'https://music.163.com/#/song?id=$songId',
      availabilityMessage: audioUrl.isEmpty ? '该歌曲受会员、地区或版权限制，未使用解灰音源' : '',
    );
  }
}
