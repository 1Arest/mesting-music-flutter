import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../shared/models/track.dart';
import '../domain/music_source.dart';
import 'abortable_json_client.dart';

class AudiusMusicSource implements MusicSource {
  AudiusMusicSource(http.Client client)
    : _jsonClient = AbortableJsonClient(client);

  static const _baseUrl = 'https://api.audius.co/v1';
  static const _appName = 'mesting-music';

  final AbortableJsonClient _jsonClient;

  @override
  String get id => 'audius';

  @override
  String get label => 'Audius';

  @override
  bool get isConfigured => true;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    final uri = Uri.parse('$_baseUrl/tracks/search').replace(
      queryParameters: {
        'query': query,
        'limit': '$limit',
        'app_name': _appName,
      },
    );

    try {
      final payload = await _jsonClient.get(uri, abortTrigger: abortTrigger);
      return parseTracks(payload);
    } on http.RequestAbortedException {
      rethrow;
    } on TimeoutException {
      throw const MusicSourceException(
        sourceLabel: 'Audius',
        message: '连接超时，请稍后重试',
        isTimeout: true,
      );
    } on Object {
      throw const MusicSourceException(
        sourceLabel: 'Audius',
        message: '暂时无法连接',
      );
    }
  }

  static List<Track> parseTracks(Object? payload) {
    final root = _asMap(payload);
    final items = root?['data'];
    if (items is! List) {
      return const [];
    }

    return items
        .whereType<Map>()
        .map((item) => _asMap(item))
        .whereType<Map<String, Object?>>()
        .where((item) {
          return item['is_streamable'] != false && item['is_unlisted'] != true;
        })
        .map(_trackFromJson)
        .whereType<Track>()
        .toList(growable: false);
  }

  static Track? _trackFromJson(Map<String, Object?> item) {
    final rawId = item['id']?.toString().trim() ?? '';
    final title = item['title']?.toString().trim() ?? '';
    if (rawId.isEmpty || title.isEmpty) {
      return null;
    }

    final user = _asMap(item['user']);
    final artwork = _asMap(item['artwork']);
    final artist = (user?['name'] ?? user?['handle'] ?? '未知音乐人')
        .toString()
        .trim();
    final album = (item['album_name'] ?? item['genre'] ?? 'Audius')
        .toString()
        .trim();
    final durationSeconds = _asInt(item['duration']);
    final permalink = item['permalink']?.toString().trim() ?? '';

    return Track(
      id: 'audius_$rawId',
      title: title,
      artist: artist.isEmpty ? '未知音乐人' : artist,
      album: album.isEmpty ? 'Audius' : album,
      duration: Duration(seconds: durationSeconds),
      audioAsset: '$_baseUrl/tracks/$rawId/stream?app_name=$_appName',
      coverAsset: _artworkUrl(artwork),
      lyricsAsset: '',
      source: TrackSource.audius,
      provider: 'Audius',
      externalUrl: permalink,
    );
  }

  static String _artworkUrl(Map<String, Object?>? artwork) {
    if (artwork == null) {
      return '';
    }
    for (final key in const ['1000x1000', '480x480', '150x150']) {
      final value = artwork[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}
