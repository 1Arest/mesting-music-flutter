import 'dart:convert';
import 'dart:math';

import '../../../shared/models/track.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';

/// The catalog owns DTOs and pagination only. Its caller owns the authenticated
/// transport, Cookie scope, cancellation and protocol-specific route mapping.
typedef QishuiCatalogRequest =
    Future<Map<String, dynamic>> Function(
      String path, {
      Map<String, Object?> body,
      Map<String, String> query,
      bool get,
      Future<void>? abortTrigger,
    });

enum QishuiSearchKind {
  tracks('track', 'tracks', '歌曲'),
  artists('artist', 'artists', '歌手');

  const QishuiSearchKind(this.pathName, this.groupName, this.label);
  final String pathName, groupName, label;
}

/// Artist identity comes from an artist DTO, never from a matching song name.
/// Unknown totals stay null so the page cannot present a partial list as all
/// of an artist's work. Images retain the existing catalog image rules.
class QishuiArtist {
  const QishuiArtist({
    required this.id,
    required this.name,
    this.artwork = '',
    this.description = '',
    this.trackCount,
    this.albumCount,
  });

  final String id, name, artwork, description;
  final int? trackCount, albumCount;

  static QishuiArtist? parse(Object? value) {
    final row = sodaMap(value);
    final id = _text(row['id'] ?? row['artist_id']);
    final name = _text(row['name']);
    if (id.isEmpty || name.isEmpty) return null;
    return QishuiArtist(
      id: id,
      name: name,
      artwork: sodaPicture([
        row['url_avatar'],
        row['avatar_url'],
        row['url_cover'],
      ]),
      description: _text(row['description'] ?? row['desc'] ?? row['bio']),
      trackCount: _total(row['count_tracks']),
      albumCount: _total(row['count_albums']),
    );
  }

  QishuiArtist merge(QishuiArtist detail) {
    if (detail.id != id) {
      throw const QishuiException('汽水返回的歌手资料不匹配');
    }
    return QishuiArtist(
      id: id,
      name: detail.name.isEmpty ? name : detail.name,
      artwork: detail.artwork.isEmpty ? artwork : detail.artwork,
      description: detail.description.isEmpty
          ? description
          : detail.description,
      trackCount: detail.trackCount ?? trackCount,
      albumCount: detail.albumCount ?? albumCount,
    );
  }
}

class QishuiCatalogPage<T> {
  QishuiCatalogPage({
    required List<T> items,
    required this.cursor,
    this.nextCursor,
    this.hasMore = false,
    this.searchId = '',
    this.continuationProblem,
  }) : items = List.unmodifiable(items);

  final List<T> items;
  final String cursor, searchId;
  final String? nextCursor, continuationProblem;
  final bool hasMore;
}

/// Keeps usable rows when a later page fails, deduplicates by stable entity ID,
/// and blocks repeated/missing cursors. An empty page with a fresh continuation
/// is still pageable; an empty middle page is not proof that the list ended.
class QishuiCatalogAccumulator<T> {
  QishuiCatalogAccumulator({required this.keyOf, this.searchId = ''});
  final String Function(T item) keyOf;
  final _rows = <String, T>{};
  final _visited = <String>{};
  String nextCursor = '0';
  String searchId;
  bool hasMore = true;
  String? continuationProblem;
  int pageCount = 0;
  List<T> get items => List.unmodifiable(_rows.values);

  void accept(QishuiCatalogPage<T> page) {
    if (page.cursor != nextCursor || !hasMore) {
      throw const QishuiException('搜索列表已变化，请重新搜索');
    }
    _visited.add(page.cursor);
    for (final item in page.items) {
      final key = keyOf(item);
      if (key.isNotEmpty) _rows[key] = item;
    }
    ++pageCount;
    if (page.searchId.isNotEmpty) searchId = page.searchId;
    continuationProblem = page.continuationProblem;
    final next = page.nextCursor;
    hasMore = page.hasMore && continuationProblem == null;
    if (hasMore && (next == null || next.isEmpty || _visited.contains(next))) {
      hasMore = false;
      continuationProblem = '汽水返回的续载位置异常，请重新搜索或刷新。';
    }
    if (hasMore && pageCount >= 1000) {
      hasMore = false;
      continuationProblem = '本次列表已达到读取上限，请缩小关键词后重试。';
    }
    if (hasMore) nextCursor = next!;
  }
}

/// PC search and artist reads have explicit translations in QishuiWebRoute.
/// The PC references are retained account_search.rs (TuneWeave) and
/// qishuiPcGet/getArtistWorks (baka-plugins); Android 19.0 DEX independently
/// establishes search groups and artist identity. Static evidence does not
/// establish that a particular account/server will accept a request.
class QishuiSearchCatalog {
  const QishuiSearchCatalog({required QishuiCatalogRequest request})
    : _request = request;
  final QishuiCatalogRequest _request;

  static String newSearchId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<Map<String, dynamic>> _search(
    String keyword,
    QishuiSearchKind kind,
    String cursor,
    String searchId,
    Future<void>? abortTrigger,
  ) {
    final query = keyword.trim();
    if (query.isEmpty ||
        utf8.encode(query).length > 500 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(query) ||
        !_validCursor(cursor) ||
        searchId.isEmpty ||
        searchId.length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(searchId)) {
      throw const QishuiException('请输入有效的歌曲或歌手关键词');
    }
    return _request(
      '/luna/search/${kind.pathName}',
      get: true,
      query: {
        'q': query,
        'cursor': cursor,
        'search_id': searchId,
        'search_method': 'input',
        'debug_params': '',
        'from_search_id': '',
        'search_scene': '',
      },
      abortTrigger: abortTrigger,
    );
  }

  Future<QishuiCatalogPage<Track>> searchTracks(
    String keyword, {
    String cursor = '0',
    required String searchId,
    Future<void>? abortTrigger,
  }) async => parseTrackSearch(
    await _search(
      keyword,
      QishuiSearchKind.tracks,
      cursor,
      searchId,
      abortTrigger,
    ),
    cursor: cursor,
    searchId: searchId,
  );

  Future<QishuiCatalogPage<QishuiArtist>> searchArtists(
    String keyword, {
    String cursor = '0',
    required String searchId,
    Future<void>? abortTrigger,
  }) async => parseArtistSearch(
    await _search(
      keyword,
      QishuiSearchKind.artists,
      cursor,
      searchId,
      abortTrigger,
    ),
    cursor: cursor,
    searchId: searchId,
  );

  Future<QishuiArtist> artistDetail(
    String id, {
    Future<void>? abortTrigger,
  }) async {
    final root = await _request(
      '/luna/artists/${_artistId(id)}',
      get: true,
      abortTrigger: abortTrigger,
    );
    final data = _payload(root);
    final artist = QishuiArtist.parse(
      data['artist_info'] ?? data['artist'] ?? data,
    );
    if (artist == null || artist.id != id) {
      throw const QishuiException('汽水暂未返回可核对的歌手资料');
    }
    return artist;
  }

  Future<QishuiCatalogPage<Track>> artistTracks(
    String id, {
    String cursor = '0',
    Future<void>? abortTrigger,
  }) async {
    if (!_validCursor(cursor)) throw const QishuiException('歌手作品续载位置无效');
    final data = _payload(
      await _request(
        '/luna/artists/${_artistId(id)}/tracks',
        get: true,
        query: {'cursor': cursor, 'count': '50'},
        abortTrigger: abortTrigger,
      ),
    );
    final more = _hasMore(data['has_more']);
    // The retained PC artist contract uses fixed 50-row offset pages and may
    // omit next_cursor. Increment the request offset, not the deduplicated size.
    final offset = int.tryParse(cursor);
    final next =
        _cursor(data['next_cursor']) ??
        (more && offset != null ? '${offset + 50}' : null);
    return QishuiCatalogPage(
      items: sodaTracks(data),
      cursor: cursor,
      hasMore: more,
      nextCursor: next,
      continuationProblem: _continuationProblem(more, next, cursor),
    );
  }

  static QishuiCatalogPage<Track> parseTrackSearch(
    Map<String, dynamic> root, {
    required String cursor,
    String searchId = '',
  }) {
    final result = _searchGroup(root, QishuiSearchKind.tracks);
    return _page(
      root,
      result,
      sodaTracks(result['data'] ?? result),
      cursor,
      searchId,
    );
  }

  static QishuiCatalogPage<QishuiArtist> parseArtistSearch(
    Map<String, dynamic> root, {
    required String cursor,
    String searchId = '',
  }) {
    final result = _searchGroup(root, QishuiSearchKind.artists);
    final artists = <String, QishuiArtist>{};
    final rows = sodaRows(result['data'] ?? result['artists']);
    for (final row in rows) {
      final entity = sodaMap(row['entity']);
      final artist = QishuiArtist.parse(
        entity['artist'] ?? row['artist'] ?? row,
      );
      if (artist != null) artists[artist.id] = artist;
    }
    return _page(root, result, artists.values.toList(), cursor, searchId);
  }
}

String _text(Object? value) =>
    value is String || value is num ? '$value'.trim() : '';
int? _total(Object? value) {
  final number = int.tryParse(_text(value));
  return number != null && number >= 0 ? number : null;
}

bool _hasMore(Object? value) => value == true || value == 1 || value == '1';
bool _validCursor(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    !RegExp(r'[\x00-\x20\x7f]').hasMatch(value);
String? _cursor(Object? value) {
  final text = _text(value);
  return _validCursor(text) ? text : null;
}

String _artistId(String id) {
  // IDs are interpolated into one path segment. Never allow a search result
  // to inject another route, query string or traversal into authenticated reads.
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
    throw const QishuiException('汽水歌手标识无效，请重新搜索');
  }
  return id;
}

Map<String, dynamic> _payload(Map<String, dynamic> root) {
  final data = root['data'];
  return data is Map ? sodaMap(data) : root;
}

Map<String, dynamic> _searchGroup(
  Map<String, dynamic> root,
  QishuiSearchKind kind,
) {
  final data = _payload(root);
  final groups = sodaRows(data['result_groups'] ?? data['resultGroups']);
  if (groups.length > 32) throw const QishuiException('汽水搜索分组超出本次读取范围');
  final matches = groups.where((row) => row['id'] == kind.groupName).toList();
  if (matches.length > 1) throw const QishuiException('汽水搜索分组重复，请重新搜索');
  if (matches.isNotEmpty) return matches.single;
  if (groups.isNotEmpty) {
    // The Android DTO permits a missing group ID. Only an unnamed group that
    // actually contains the requested entity is a valid compatibility case.
    final unnamed = groups.where((row) => _text(row['id']).isEmpty).where((
      row,
    ) {
      return sodaRows(row['data']).any((item) {
        final entity = sodaMap(item['entity']);
        return kind == QishuiSearchKind.tracks
            ? entity['track'] is Map || entity['track_wrapper'] is Map
            : entity['artist'] is Map;
      });
    }).toList();
    if (unnamed.length == 1) return unnamed.single;
    return const {};
  }
  // Old flat first-party DTOs remain readable. Artist rows are parsed only as
  // artists, and a different named group never leaks into this fallback.
  return data;
}

QishuiCatalogPage<T> _page<T>(
  Map<String, dynamic> root,
  Map<String, dynamic> group,
  List<T> items,
  String cursor,
  String requestSearchId,
) {
  final payload = _payload(root);
  final extra = sodaMap(payload['extra']);
  final more = _hasMore(group['has_more'] ?? group['hasMore']);
  final next = _cursor(group['next_cursor'] ?? group['nextCursor']);
  final returnedId = _text(
    extra['search_id'] ?? extra['searchId'] ?? payload['search_id'],
  );
  return QishuiCatalogPage(
    items: items,
    cursor: cursor,
    nextCursor: next,
    hasMore: more,
    searchId:
        returnedId.isNotEmpty &&
            returnedId.length <= 128 &&
            !RegExp(r'[\x00-\x1f\x7f]').hasMatch(returnedId)
        ? returnedId
        : requestSearchId,
    continuationProblem: _continuationProblem(more, next, cursor),
  );
}

String? _continuationProblem(bool more, String? next, String cursor) =>
    more && (next == null || next == cursor) ? '汽水返回的续载位置异常，请重新搜索或刷新。' : null;
