import 'dart:convert';
import '../../../shared/models/track.dart';
import 'platform_category_search.dart';
import '../netease/netease_music_repository.dart';

class SongMenuPerson {
  const SongMenuPerson(
    this.name, {
    this.id = '',
    this.role = '',
    this.officialCreatorSongId = '',
  });
  final String name, id, role, officialCreatorSongId;
}

enum SongDetailsSection {
  catalogue('歌手、专辑'),
  creators('创作者署名');

  const SongDetailsSection(this.label);
  final String label;
}

class SongMenuDetails {
  const SongMenuDetails({
    this.artists = const [],
    this.creators = const [],
    this.album = '',
    this.albumId = '',
    this.cover = '',
    this.failed = const {},
  });
  final List<SongMenuPerson> artists, creators;
  final String album, albumId, cover;

  /// 缺少署名与请求失败分别表示：空数据不伪装成网络错误，也不伪造资料。
  final Set<SongDetailsSection> failed;

  SongMenuDetails copyWith({
    List<SongMenuPerson>? creators,
    Set<SongDetailsSection>? failed,
  }) => SongMenuDetails(
    artists: artists,
    creators: creators ?? this.creators,
    album: album,
    albumId: albumId,
    cover: cover,
    failed: failed ?? this.failed,
  );
  factory SongMenuDetails.local(Track track) => SongMenuDetails(
    artists: track.artist.trim().isEmpty
        ? const []
        : [SongMenuPerson(track.artist)],
    album: track.album,
    cover: track.coverAsset,
  );
}

typedef SongDetailsCall =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, Object?> query,
    );

/// Catalogue metadata is read only when a menu opens. It never resolves an
/// audio URL, starts playback or submits a listening event. The caller supplies
/// a credential-bound client; UI epoch checks reject obsolete account results.
class SongMenuDetailsRepository {
  const SongMenuDetailsRepository({required this.netease, required this.kugou});
  final SongDetailsCall netease, kugou;
  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};
  static String _text(Object? value) => value is String || value is num
      ? PlatformCategorySearchRepository.clean(value)
      : '';
  static String _id(Object? value) {
    final text = _text(value);
    return (int.tryParse(text) ?? 0) > 0 ? text : '';
  }

  static List<SongMenuPerson> _people(Object? rows) => rows is List
      ? [
          for (final raw in rows)
            if (_text(
              _map(raw)['name'] ??
                  _map(raw)['author_name'] ??
                  _map(raw)['singername'],
            ).isNotEmpty)
              SongMenuPerson(
                _text(
                  _map(raw)['name'] ??
                      _map(raw)['author_name'] ??
                      _map(raw)['singername'],
                ),
                id: _id(
                  _map(raw)['id'] ??
                      _map(raw)['author_id'] ??
                      _map(raw)['singerid'] ??
                      _map(raw)['singer_id'] ??
                      _map(raw)['SingerId'],
                ),
              ),
        ]
      : const [];

  /// Credits are explicit author lines supplied by the platform's lyric file,
  /// not singers guessed from the title. Ignore timed singing and unrelated
  /// names; no fabricated creator IDs or inferred writer/singer equivalence.
  static List<SongMenuPerson> lyricCredits(String lyric) {
    final result = <SongMenuPerson>[];
    final seen = <String>{};
    final credit = RegExp(
      r'^\s*(作词|作曲|编曲|制作人|词|曲|ly|au)\s*[:：]\s*(.+?)\s*\]?$',
      caseSensitive: false,
    );
    for (final line in lyric.split('\n').take(160)) {
      final clean = line
          .replaceAll(RegExp(r'\[\d{1,3}:\d{1,2}(?:[.:]\d+)?\]'), '')
          .replaceFirst(RegExp(r'^\[(?=(?:ly|au):)', caseSensitive: false), '');
      final match = credit.firstMatch(clean);
      if (match == null) continue;
      final role = switch (match[1]!.toLowerCase()) {
        'ly' || '词' => '作词',
        'au' || '曲' => '作曲',
        final value => value,
      };
      final name = match[2]!.trim();
      if (name.isNotEmpty && seen.add('$role:$name')) {
        result.add(SongMenuPerson(name, role: role));
      }
    }
    return result;
  }

  Future<SongMenuDetails> load(
    Track track, {
    SongMenuDetails? previous,
    SongDetailsSection? only,
  }) async {
    if (only == SongDetailsSection.creators && previous != null) {
      final failed = {...previous.failed}..remove(SongDetailsSection.creators);
      try {
        return previous.copyWith(
          creators: await _credits(track),
          failed: failed,
        );
      } catch (_) {
        return previous.copyWith(
          failed: failed..add(SongDetailsSection.creators),
        );
      }
    }
    Future<SongMenuDetails> catalogueFailure() async {
      var retained = (previous ?? SongMenuDetails.local(track)).copyWith(
        failed: {...?previous?.failed, SongDetailsSection.catalogue},
      );
      // 两个独立资料源：目录暂不可用时仍读取署名，不把未读取当作空数据。
      if (only == null || previous == null) {
        try {
          retained = retained.copyWith(
            creators: await _credits(track),
            failed: {...retained.failed}..remove(SongDetailsSection.creators),
          );
        } catch (_) {
          retained = retained.copyWith(
            failed: {...retained.failed, SongDetailsSection.creators},
          );
        }
      }
      return retained;
    }

    if (track.source == TrackSource.netease) {
      final id = _id(
        track.platformSongId.isNotEmpty
            ? track.platformSongId
            : track.id.replaceFirst('netease_', ''),
      );
      if (id.isEmpty) return SongMenuDetails.local(track);
      Map<String, dynamic> payload;
      try {
        // The shared NetEase transport serializes a list into the official
        // `c` request. A scalar fails its cast before any HTTP request starts.
        payload = await netease('/song/detail', {
          'ids': [id],
        });
      } catch (_) {
        return catalogueFailure();
      }
      final songs = NeteaseMusicRepository.rows(payload['songs']);
      final song = songs.where((s) => _text(s['id']) == id).firstOrNull;
      if (song == null) return catalogueFailure();
      final album = _map(song['al'] ?? song['album']);
      List<SongMenuPerson> creators = previous?.creators ?? const [];
      final failed = {...?previous?.failed}
        ..remove(SongDetailsSection.catalogue);
      // Credits are optional. A lyric failure must not discard verified album
      // and artist IDs; the empty creator state remains truthful and retryable.
      if (only == null || previous == null) {
        try {
          creators = await _credits(track);
          failed.remove(SongDetailsSection.creators);
        } catch (_) {
          failed.add(SongDetailsSection.creators);
        }
      }
      final artists = _people(song['ar'] ?? song['artists']);
      return SongMenuDetails(
        artists: artists.isEmpty
            ? SongMenuDetails.local(track).artists
            : artists,
        creators: creators,
        album: _text(album['name']),
        albumId: _id(album['id']),
        cover: _text(album['picUrl']),
        failed: failed,
      );
    }
    if (track.source == TrackSource.kugou && track.id.startsWith('kugou_')) {
      final hash = track.id.substring(6);
      Map<String, dynamic> payload;
      try {
        payload = await kugou('/audio', {'hash': hash});
      } catch (_) {
        return catalogueFailure();
      }
      final data = payload['data'];
      final rows = data is List ? data : [data];
      // /audio was requested for one exact hash. If the response names a
      // different recording, never attach that recording's people or album.
      final row = rows.map(_map).where((r) {
        final actual = _text(r['hash'] ?? _map(r['base'])['hash']);
        return actual.isEmpty || actual.toLowerCase() == hash.toLowerCase();
      }).firstOrNull;
      if (row == null || row.isEmpty) return catalogueFailure();
      final base = _map(row['base']);
      final album = _map(row['album_info']);
      final artists = _people(
        row['singerinfo'] ??
            row['authors'] ??
            row['singers'] ??
            base['authors'],
      );
      List<SongMenuPerson> creators = previous?.creators ?? const [];
      final failed = {...?previous?.failed}
        ..remove(SongDetailsSection.catalogue);
      // Only explicit roles qualify as credits; a generic author/singer list
      // must never be relabeled as lyricists or composers.
      final credits = row['credits'];
      if (credits is List && (only == null || previous == null)) {
        creators = [
          for (final raw in credits)
            if (_text(_map(raw)['role']).isNotEmpty &&
                _text(_map(raw)['name']).isNotEmpty)
              SongMenuPerson(
                _text(_map(raw)['name']),
                role: _text(_map(raw)['role']),
              ),
        ];
      }
      if (creators.isEmpty && (only == null || previous == null)) {
        // Same read-only hash-scoped lyric contract as LyricsRepository. Only
        // explicit credit lines are retained; never infer credits from names.
        try {
          creators = await _credits(track);
          failed.remove(SongDetailsSection.creators);
        } catch (_) {
          failed.add(SongDetailsSection.creators);
        }
      }
      return SongMenuDetails(
        artists: artists.isEmpty
            ? SongMenuDetails.local(track).artists
            : artists,
        creators: creators,
        album: _text(album['album_name'] ?? row['album_name'] ?? track.album),
        albumId: _id(
          album['album_id'] ??
              album['id'] ??
              row['album_id'] ??
              base['album_id'],
        ),
        cover: _text(
          album['sizable_cover'] ?? album['cover'],
        ).replaceAll('{size}', '400'),
        failed: failed,
      );
    }
    return SongMenuDetails.local(track);
  }

  /// 独立读取失败的署名部分，重试不会重新请求已经成功的歌手/专辑。
  Future<List<SongMenuPerson>> _credits(Track track) async {
    if (track.source == TrackSource.netease) {
      final id = _id(
        track.platformSongId.isNotEmpty
            ? track.platformSongId
            : track.id.replaceFirst('netease_', ''),
      );
      if (id.isEmpty) return const [];
      final response = await netease('/song/other/message', {'songId': id});
      final rows = response['data'];
      if (rows == null) return const [];
      if (rows is! List) throw const FormatException('网易云歌曲资料格式无效');
      for (final raw in rows) {
        final row = _map(raw);
        // The official menu uses type 100 for credits. Other entries can
        // describe unrelated features such as sheet music.
        if ('${row['type']}' != '100') continue;
        final title = _text(
          row['title'],
        ).replaceFirst(RegExp(r'^创作者\s*[:：]\s*'), '').trim();
        if (title.isEmpty || title == '无') continue;
        final url = Uri.tryParse(_text(row['jumpUrl']));
        final opensCreatorList =
            url != null &&
            url.scheme == 'orpheus' &&
            url.host == 'rnpage' &&
            url.queryParameters['component'] == 'rn-creatorlist' &&
            url.queryParameters['songId'] == id;
        return [
          SongMenuPerson(
            title,
            officialCreatorSongId: opensCreatorList ? id : '',
          ),
        ];
      }
      return const [];
    }
    if (track.source != TrackSource.kugou || !track.id.startsWith('kugou_')) {
      return const [];
    }
    final hash = track.id.substring(6);
    final search = await kugou('/search/lyric', {
      'hash': hash,
      'album_audio_id': track.platformSongId.isEmpty
          ? '0'
          : track.platformSongId,
      'duration': '${track.duration.inMilliseconds}',
      'man': 'no',
    });
    final values = search['candidates'];
    final candidate = values is List
        ? values
              .map(_map)
              .where(
                (c) =>
                    _text(c['hash']).isEmpty ||
                    _text(c['hash']).toLowerCase() == hash.toLowerCase(),
              )
              .firstOrNull
        : null;
    if (candidate == null) return const [];
    final id = _text(candidate['id']), key = _text(candidate['accesskey']);
    if (id.isEmpty || key.isEmpty) return const [];
    final lyric = await kugou('/lyric', {
      'id': id,
      'accesskey': key,
      'fmt': 'lrc',
      'decode': 'true',
    });
    final decoded = _text(lyric['decodeContent']);
    final content = decoded.isNotEmpty
        ? decoded
        : utf8.decode(base64Decode(_text(lyric['content'])));
    return lyricCredits(content);
  }
}
