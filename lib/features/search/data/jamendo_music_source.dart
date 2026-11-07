import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../shared/models/track.dart';
import '../domain/music_source.dart';
import 'abortable_json_client.dart';

class JamendoMusicSource implements MusicSource {
  JamendoMusicSource(
    http.Client client, {
    String clientId = const String.fromEnvironment('JAMENDO_CLIENT_ID'),
  }) : _clientId = clientId.trim(),
       _jsonClient = AbortableJsonClient(client);

  static const _baseUrl = 'https://api.jamendo.com/v3.0';

  final String _clientId;
  final AbortableJsonClient _jsonClient;

  @override
  String get id => 'jamendo';

  @override
  String get label => 'Jamendo';

  @override
  bool get isConfigured => _clientId.isNotEmpty;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    if (!isConfigured) {
      return const [];
    }

    final uri = Uri.parse('$_baseUrl/tracks/').replace(
      queryParameters: {
        'client_id': _clientId,
        'format': 'json',
        'limit': '$limit',
        'include': 'musicinfo licenses lyrics',
        'audioformat': 'mp32',
        'search': query,
      },
    );

    try {
      final payload = await _jsonClient.get(uri, abortTrigger: abortTrigger);
      return parseTracks(payload);
    } on http.RequestAbortedException {
      rethrow;
    } on TimeoutException {
      throw const MusicSourceException(
        sourceLabel: 'Jamendo',
        message: '连接超时，请稍后重试',
        isTimeout: true,
      );
    } on Object {
      throw const MusicSourceException(
        sourceLabel: 'Jamendo',
        message: '暂时无法连接',
      );
    }
  }

  static List<Track> parseTracks(Object? payload) {
    final root = _asMap(payload);
    final items = root?['results'];
    if (items is! List) {
      return const [];
    }

    return items
        .whereType<Map>()
        .map((item) => _asMap(item))
        .whereType<Map<String, Object?>>()
        .map(_trackFromJson)
        .whereType<Track>()
        .toList(growable: false);
  }

  static Track? _trackFromJson(Map<String, Object?> item) {
    final rawId = item['id']?.toString().trim() ?? '';
    final title = item['name']?.toString().trim() ?? '';
    final audio = item['audio']?.toString().trim() ?? '';
    if (rawId.isEmpty || title.isEmpty || audio.isEmpty) {
      return null;
    }

    return Track(
      id: 'jamendo_$rawId',
      title: title,
      artist: item['artist_name']?.toString().trim().isNotEmpty == true
          ? item['artist_name'].toString().trim()
          : '未知音乐人',
      album: item['album_name']?.toString().trim().isNotEmpty == true
          ? item['album_name'].toString().trim()
          : 'Jamendo',
      duration: Duration(seconds: _asInt(item['duration'])),
      audioAsset: audio,
      coverAsset: item['image']?.toString().trim() ?? '',
      lyricsAsset: '',
      source: TrackSource.jamendo,
      provider: 'Jamendo',
      externalUrl: item['shareurl']?.toString().trim() ?? '',
      licenseUrl: item['license_ccurl']?.toString().trim() ?? '',
    );
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
