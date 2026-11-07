import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/models/track.dart';
import '../domain/platform_session.dart';
import 'music_platform_api.dart';
import 'platform_catalog.dart';

/// Contracts ported from md3Music a69503b: KugouProvider.getPersonalFm,
/// getHomeDiscover/fetchMoreHomeDiscover and HotSearchBoard.parseList. Results
/// retain server order; there is no local preference scoring or artist search.
enum PlatformRecommendationKind { fm, discover }

enum PlatformFmStation {
  heart('红心', 'normal', 0),
  explore('探索', 'normal', 2),
  niche('小众', 'small', 1),
  radio('电台', 'radio', 0);

  const PlatformFmStation(this.label, this.mode, this.pool);
  final String label, mode;
  final int pool;
}

class PlatformHotSearchBoard {
  const PlatformHotSearchBoard(this.name, this.keywords);
  final String name;
  final List<String> keywords;
  static List<PlatformHotSearchBoard> parse(Map<String, dynamic> payload) {
    final data = MusicPlatformApi.objectMap(payload['data']);
    final boards = <PlatformHotSearchBoard>[];
    for (final row
        in (data['list'] is List ? data['list'] as List : const [])) {
      if (row is! Map || row['keywords'] is! List) continue;
      final name = '${row['name'] ?? ''}'.trim();
      final words = <String>[
        for (final item in row['keywords'] as List)
          if ('${item is Map ? item['keyword'] ?? '' : item}'.trim().isNotEmpty)
            '${item is Map ? item['keyword'] ?? '' : item}'.trim(),
      ];
      if (name.isNotEmpty && words.isNotEmpty) {
        boards.add(PlatformHotSearchBoard(name, words));
      }
    }
    return boards;
  }
}

class PlatformRecommendations {
  PlatformRecommendations(this.api, this.preferences, this.identity) {
    final raw = preferences.getString(_progressKey);
    try {
      final value = jsonDecode(raw ?? '{}');
      _cursor = (value['cursor'] as num?)?.toInt() ?? 0;
      _seen.addAll((value['seen'] as List? ?? const []).map((e) => '$e'));
    } catch (_) {
      /* Corrupt disposable progress restarts safely. */
    }
  }
  final MusicPlatformApi api;
  final SharedPreferences preferences;
  final PlatformSession? identity;
  int _cursor = 0;
  final _seen = <String>{};
  final _discoverySongs = <Track>[];
  List<Track> get discoverySongs => List.unmodifiable(_discoverySongs);
  final _fmFeedback = <String, Map<String, String>>{};
  Future<List<Track>>? _discoverPending;
  bool _disposed = false;
  String get _progressKey =>
      'beta7_discover_progress_${identity?.userId ?? "guest"}';
  int get cursor => _cursor;
  void dispose() {
    _disposed = true;
  }

  bool get _current =>
      !_disposed &&
      api.session?.userId == identity?.userId &&
      api.session?.token == identity?.token;
  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    if (!_current) throw const MusicPlatformException('账号已变化，请重新加载推荐');
    final result = await api.get(path, query: query, expectedSession: identity);
    if (!_current) throw const MusicPlatformException('账号已变化，请重新加载推荐');
    return result;
  }

  Future<List<PlatformHotSearchBoard>> hotSearch() async =>
      PlatformHotSearchBoard.parse(await _get('/search/hot', const {}));

  /// A garbage response can carry a replacement batch. Register its own tokens
  /// as well: never reuse the previous recording's cur_mark for the new song.
  List<Track> _ingestFm(
    Map<String, dynamic> payload,
    String mode,
    String pool,
  ) {
    final tracks = PlatformCatalog.tracks(payload);
    for (final row in PlatformCatalog.rows(payload)) {
      final nested = MusicPlatformApi.objectMap(row['rec_song_info']);
      final data = {...nested, ...row};
      final parsed = PlatformCatalog.tracks([row]);
      if (parsed.isEmpty) continue;
      _fmFeedback[parsed.first.id] = {
        'mode': mode,
        'song_pool_id': pool,
        'hash': parsed.first.id.substring('kugou_'.length),
        if (parsed.first.platformSongId.isNotEmpty)
          'songid': parsed.first.platformSongId,
        if ('${data['cur_mark'] ?? ''}'.isNotEmpty)
          'cur_mark': '${data['cur_mark']}',
      };
    }
    return tracks;
  }

  Future<List<Track>> personalFm(
    PlatformFmStation station, {
    bool first = true,
    Track? anchor,
    String? action,
  }) async {
    Future<List<Track>> request(Map<String, String> params) async {
      final payload = await _get('/personal/fm', params);
      return _ingestFm(payload, station.mode, '${station.pool}');
    }

    final params = <String, String>{
      // Match upstream: the default first pull supplies action=login; saved
      // non-default stations explicitly supply their mode and pool.
      if (!first || station != PlatformFmStation.heart) 'mode': station.mode,
      if (!first || station != PlatformFmStation.heart)
        'song_pool_id': '${station.pool}',
      if (first && station == PlatformFmStation.heart) 'action': 'login',
      if (!first) 'action': action ?? 'play',
      if (anchor != null) 'hash': anchor.id.replaceFirst('kugou_', ''),
      if (anchor?.platformSongId.isNotEmpty == true)
        'songid': anchor!.platformSongId,
    };
    try {
      final tracks = await request(params);
      if (tracks.isNotEmpty) return tracks;
    } on MusicPlatformException {
      if (!_current) rethrow;
    }
    // Upstream's login/anchor fallback requests the default cursor once. It
    // never invents songs or replaces an explicit station with a local model.
    return request({
      if (station != PlatformFmStation.heart || !first) 'mode': station.mode,
      if (station != PlatformFmStation.heart || !first)
        'song_pool_id': '${station.pool}',
    });
  }

  Future<List<Track>> feedback(
    Track track,
    String action, {
    int? seconds,
    bool complete = false,
  }) async {
    final context = _fmFeedback[track.id];
    if (identity == null || context == null) return const [];
    final payload = await _get('/personal/fm', {
      ...context,
      'action': action,
      if (seconds != null) 'playtime': '$seconds',
      if (seconds != null) 'is_overplay': complete ? '1' : '0',
    });
    return _ingestFm(payload, context['mode']!, context['song_pool_id']!);
  }

  Future<void> _saveProgress() async {
    final tail = _seen.toList().skip(
      (_seen.length - 500).clamp(0, _seen.length),
    );
    try {
      await preferences.setString(
        _progressKey,
        jsonEncode({'cursor': _cursor, 'seen': tail.toList()}),
      );
    } catch (_) {
      /* A failed cache write cannot stop the playback queue. */
    }
  }

  Future<List<Track>> discover({bool more = false}) {
    final pending = _discoverPending;
    if (pending != null) return pending;
    final request = _discover(more: more);
    _discoverPending = request;
    return request.whenComplete(() {
      if (identical(_discoverPending, request)) _discoverPending = null;
    });
  }

  Future<List<Track>> _discover({required bool more}) async {
    final result = <Track>[];
    final size = more ? 30 : 4;
    for (var attempt = 0; attempt < (more ? 3 : 1); attempt++) {
      if (attempt > 0) {
        _cursor += 30;
        await _saveProgress();
      }
      final payload = await _get('/home/discover', {
        'pagesize': '$size',
        'today_play_num': '$_cursor',
        'recall_type': 'song',
      });
      final incoming = PlatformCatalog.tracks(payload);
      final fresh = incoming.where((track) => _seen.add(track.id)).toList();
      _cursor += fresh.length;
      result.addAll(fresh);
      _discoverySongs.addAll(fresh);
      await _saveProgress();
      if (result.length >= size) break;
    }
    return result;
  }
}
