import 'package:flutter/foundation.dart';
import 'dart:async';

import '../data/music_platform_api.dart';
import 'netease_connection_models.dart';
import 'netease_user_repository.dart';

/// A tab owns its full page cursor, search/filter/order and loaded rows. The UI
/// keeps two instances alive, so switching Follow/Followers never drops a
/// search, starts a new pagination session or changes the tab's scroll offset.
class NeteaseConnectionsController extends ChangeNotifier {
  NeteaseConnectionsController({
    required this.repository,
    required this.userId,
    required this.followers,
    required this.isCurrent,
  });

  final NeteaseUserRepository repository;
  final String userId;
  final bool followers;
  final bool Function() isCurrent;
  final _items = <NeteaseConnection>[];
  int _userOffset = 0, _artistOffset = 0;
  bool _usersMore = true, _artistsMore = true;
  bool _disposed = false, _started = false;
  int _generation = 0;
  bool busy = false;
  String? error;
  String query = '';
  NeteaseConnectionFilter filter = NeteaseConnectionFilter.all;
  NeteaseConnectionSort sort = NeteaseConnectionSort.official;

  List<NeteaseConnection> get items => List.unmodifiable(_items);
  bool get complete => !_usersMore && (followers || !_artistsMore);
  bool get started => _started;
  bool get _active => !_disposed && isCurrent();

  List<NeteaseConnection> get _filtered => [
    for (final item in _items)
      if ((filter == NeteaseConnectionFilter.all ||
              filter == NeteaseConnectionFilter.artists &&
                  item.kind == NeteaseConnectionKind.artist ||
              filter == NeteaseConnectionFilter.users &&
                  item.kind == NeteaseConnectionKind.user) &&
          (query.trim().isEmpty ||
              item.name.toLowerCase().contains(query.trim().toLowerCase()) ||
              item.description.toLowerCase().contains(
                query.trim().toLowerCase(),
              )))
        item,
  ];

  /// Explicit time sorting is available only for a complete, comparable set.
  /// Server-default ordering remains usable when old rows have no timestamp.
  bool get canSortByTime =>
      complete &&
      _filtered.isNotEmpty &&
      _filtered.every((item) => item.followedAt != null);

  List<NeteaseConnection> get visible {
    final values = _filtered;
    if (sort == NeteaseConnectionSort.name) {
      values.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName == 0 ? a.key.compareTo(b.key) : byName;
      });
    } else if (sort == NeteaseConnectionSort.followTime && canSortByTime) {
      values.sort((a, b) {
        final byTime = b.followedAt!.compareTo(a.followedAt!);
        return byTime == 0 ? a.key.compareTo(b.key) : byTime;
      });
    }
    return values;
  }

  void setQuery(String value) {
    query = value;
    _ensureReliableSort();
    notifyListeners();
    if (_started && value.trim().isNotEmpty) unawaited(loadRemaining());
  }

  void setFilter(NeteaseConnectionFilter value) {
    filter = followers ? NeteaseConnectionFilter.users : value;
    _ensureReliableSort();
    notifyListeners();
  }

  bool setSort(NeteaseConnectionSort value) {
    if (value == NeteaseConnectionSort.followTime && !canSortByTime) {
      return false;
    }
    sort = value;
    if (value == NeteaseConnectionSort.name) unawaited(loadRemaining());
    notifyListeners();
    return true;
  }

  void _ensureReliableSort() {
    if (sort == NeteaseConnectionSort.followTime && !canSortByTime) {
      sort = NeteaseConnectionSort.official;
    }
  }

  Future<void> start() async {
    if (_started || !_active) return;
    _started = true;
    await loadMore();
  }

  Future<void> loadMore() => loadRemaining(singlePage: true);

  /// Complete every upstream page before claiming a complete local search or
  /// name sort. Existing rows remain visible while later pages arrive/retry.
  Future<void> loadRemaining({bool singlePage = false}) async {
    if (busy || complete || !_active) return;
    final generation = _generation;
    bool current() => _active && generation == _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      while (current() && !complete) {
        if (_usersMore) {
          final page = await repository.personalConnections(
            userId,
            followers: followers,
            offset: _userOffset,
          );
          if (!current()) return;
          _append(page);
          _userOffset += page.consumed;
          _usersMore = page.more;
          notifyListeners();
        }
        if (!followers && _artistsMore) {
          final page = await repository.subscribedArtists(_artistOffset);
          if (!current()) return;
          _append(page);
          _artistOffset += page.consumed;
          _artistsMore = page.more;
          notifyListeners();
        }
        if (singlePage &&
            query.trim().isEmpty &&
            sort == NeteaseConnectionSort.official) {
          break;
        }
      }
    } catch (_) {
      if (current()) error = '列表未加载完整，重试后继续';
    } finally {
      if (current()) {
        busy = false;
        _ensureReliableSort();
        notifyListeners();
      }
    }
  }

  void _append(NeteaseConnectionPage page) {
    final keys = _items.map((item) => item.key).toSet();
    final additions = page.items.where((item) => keys.add(item.key)).toList();
    // A broken server page must not spin forever, silently truncate the list,
    // or move the cursor past the page that the user needs to retry.
    if (page.more && (page.consumed <= 0 || additions.isEmpty)) {
      throw const MusicPlatformException('列表分页未前进，请重试');
    }
    _items.addAll(additions);
  }

  /// Refresh builds a replacement snapshot offscreen. A failing first request
  /// preserves old rows, filters and scroll; it never blanks a usable tab.
  Future<void> refresh() async {
    if (busy || !_active) return;
    final generation = ++_generation;
    final replacement = NeteaseConnectionsController(
      repository: repository,
      userId: userId,
      followers: followers,
      isCurrent: () => _active && generation == _generation,
    );
    busy = true;
    error = null;
    notifyListeners();
    await replacement.start();
    while (!replacement.complete &&
        replacement.error == null &&
        replacement._items.length < _items.length &&
        _active &&
        generation == _generation) {
      await replacement.loadMore();
    }
    if (!_active || generation != _generation) {
      replacement.dispose();
      return;
    }
    if (replacement.error == null) {
      _items
        ..clear()
        ..addAll(replacement._items);
      _userOffset = replacement._userOffset;
      _artistOffset = replacement._artistOffset;
      _usersMore = replacement._usersMore;
      _artistsMore = replacement._artistsMore;
      _ensureReliableSort();
    } else {
      error = '刷新未完成，已保留原列表，请重试';
    }
    busy = false;
    replacement.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
