import 'dart:convert';

import '../../../core/cache/browse_response_cache.dart';
import 'music_platform_api.dart';

typedef KugouPageRead =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, String> query,
    );

/// Raw-record pagination shared by private and public Kugou collections. DTO
/// conversion happens only after the requested slice has been selected.
class KugouPlaylistPaging {
  KugouPlaylistPaging({
    required this.read,
    required this.rows,
    this.pageSize = 30,
  });
  final KugouPageRead read;
  final List<Map<String, dynamic>> Function(Object?) rows;
  final _pages = <String, Future<_RawPage>>{};
  final _versions = <String, String>{};
  final _counts = <String, int>{};
  final _pageSignatures = <String, Map<int, String>>{};
  final int pageSize;

  void clear() {
    _pages.clear();
    _versions.clear();
    _counts.clear();
    _pageSignatures.clear();
  }

  Future<_RawPage> _load(String path, Map<String, String> query, int page) {
    final collection = '$path:${jsonEncode(query)}';
    Future<_RawPage> fetch() async {
      final payload = await read(path, {
        ...query,
        'page': '$page',
        'pagesize': '$pageSize',
      });
      final data = MusicPlatformApi.objectMap(payload['data']);
      int? number(List<String> keys) {
        for (final key in keys) {
          final value = int.tryParse('${data[key] ?? payload[key]}');
          if (value != null && value >= 0) return value;
        }
        return null;
      }

      // A known remote snapshot may not be mixed with another version. The
      // normal refresh/mutation boundary clears pages and starts a new one.
      final version = data['list_ver'] ?? payload['list_ver'];
      if (version != null) {
        final previous = _versions[collection];
        if (previous != null && previous != '$version') {
          throw const MusicPlatformException('歌单已更新，请刷新后继续加载');
        }
        _versions[collection] = '$version';
      }
      final total = number(['total', 'count', 'total_count']);
      if (total != null) {
        final previous = _counts[collection];
        if (previous != null && previous != total) {
          throw const MusicPlatformException('歌单数量已变化，请刷新后继续加载');
        }
        _counts[collection] = total;
      }
      final values = rows(payload);
      if (values.isNotEmpty &&
          values.every((row) => row['hash'] != null || row['fileid'] != null)) {
        final signature = values
            .map((row) => '${row['fileid']}:${row['hash']}')
            .join('|');
        final seen = _pageSignatures.putIfAbsent(collection, () => {});
        if (seen.entries.any(
          (entry) => entry.key != page && entry.value == signature,
        )) {
          throw const MusicPlatformException('平台歌曲分页未前进，请刷新后重试');
        }
        seen[page] = signature;
      }
      return _RawPage(values, total);
    }

    // Cache observers need to subscribe to the transport reads, including its
    // stale-response refresh notifications, rather than to an opaque Future.
    if (BrowseResponseCache.observing) return fetch();
    final key = '$collection:$page';
    return _pages[key] ??= fetch().catchError((Object error) {
      _pages.remove(key);
      throw error;
    });
  }

  Future<KugouRowsPage> page(
    String path,
    Map<String, String> query, {
    int offset = 0,
    int limit = 30,
  }) async {
    final start = offset.clamp(0, 1 << 31);
    final size = limit.clamp(1, 500);
    final selected = <Map<String, dynamic>>[];
    var cursor = start;
    var more = false;
    int? total;
    while (selected.length < size) {
      final page = cursor ~/ pageSize + 1;
      final current = await _load(path, query, page);
      total = current.total ?? total;
      final withinPage = cursor % pageSize;
      if (withinPage >= current.items.length) {
        more = false;
        break;
      }
      final available = current.items
          .skip(withinPage)
          .take(size - selected.length);
      final values = available.toList(growable: false);
      selected.addAll(values);
      cursor += values.length;
      more = total != null
          ? cursor < total
          : withinPage + values.length < current.items.length ||
                current.items.length >= pageSize;
      if (!more) break;
    }
    return KugouRowsPage(
      selected,
      offset: start,
      nextOffset: cursor,
      total: total,
      hasMore: more,
    );
  }
}

class KugouRowsPage {
  const KugouRowsPage(
    this.items, {
    required this.offset,
    required this.nextOffset,
    required this.total,
    required this.hasMore,
  });
  final List<Map<String, dynamic>> items;
  final int offset, nextOffset;
  final int? total;
  final bool hasMore;
}

class _RawPage {
  const _RawPage(this.items, this.total);
  final List<Map<String, dynamic>> items;
  final int? total;
}
