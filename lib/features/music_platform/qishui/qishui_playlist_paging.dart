import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/cache/cached_browse_loader.dart';
import '../../../shared/models/track.dart';
import 'qishui_api.dart';
import 'qishui_search_catalog.dart';

typedef QishuiPlaylistPageRequest =
    Future<QishuiCatalogPage<Track>> Function(
      String cursor,
      Future<void> abort,
    );

/// A page owns presentation pagination, cache subscriptions and cancellation.
/// Explicit full-list actions continue to use the repository's live full read.
/// A fresh page may replace only its own batch; a changed continuation discards
/// its old tail instead of stitching cursors from different server snapshots.
class QishuiPlaylistPaging extends ChangeNotifier {
  QishuiPlaylistPaging({
    required this.request,
    required this.current,
    required this.pageAbort,
  });

  final QishuiPlaylistPageRequest request;
  final bool Function() current;
  final Future<void> pageAbort;
  final _cached = CachedBrowseLoader();
  final _pages = <String, QishuiCatalogPage<Track>>{};
  var _abort = Completer<void>();
  var _generation = 0;
  var _disposed = false;
  List<Track> _items = const [];
  bool loading = false, ready = false;
  String? error;

  List<Track> get items => _items;
  bool get hasMore => _pages.isNotEmpty && _pages.values.last.hasMore;
  bool get complete => ready && !hasMore;
  bool get canLoadMore => ready && hasMore && !loading && error == null;

  bool _active(int generation) =>
      !_disposed && current() && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> reload() async {
    if (_disposed || !current()) return;
    if (!_abort.isCompleted) _abort.complete();
    _abort = Completer<void>();
    _cached.reset();
    loading = false;
    await _load('', ++_generation);
  }

  Future<void> loadMore() async {
    if (!canLoadMore || _disposed || !current()) return;
    final cursor = _pages.values.last.nextCursor;
    if (cursor == null || _pages.containsKey(cursor) || _pages.length >= 1000) {
      error = '歌单续载位置重复、缺失或已超出本次读取范围，请刷新核对';
      _notify();
      return;
    }
    await _load(cursor, _generation);
  }

  Future<void> retry() => ready ? _retryMore() : reload();
  Future<void> _retryMore() async {
    error = null;
    await loadMore();
  }

  Future<void> _load(String cursor, int generation) async {
    if (!_active(generation) || loading) return;
    loading = true;
    error = null;
    _notify();
    final abort = Future.any<void>([pageAbort, _abort.future]);
    var newerPublished = false;
    try {
      final page = await _cached.load<QishuiCatalogPage<Track>>(
        key: cursor,
        request: () => request(cursor, abort),
        onUpdate: (_, incoming) {
          if (!_active(generation)) return;
          newerPublished = true;
          _install(cursor, incoming);
        },
      );
      if (_active(generation) && !newerPublished) _install(cursor, page);
    } on Object catch (failure) {
      if (_active(generation)) {
        error = failure is QishuiException ? failure.message : '歌单暂时无法读取，请重试';
      }
    } finally {
      if (_active(generation)) {
        loading = false;
        _notify();
      }
    }
  }

  void _install(String cursor, QishuiCatalogPage<Track> page) {
    if (page.cursor != cursor) {
      error = '汽水返回的歌单页位置不匹配，请刷新核对';
      _notify();
      return;
    }
    // A predecessor can refresh while this next-page request is in flight.
    // Its obsolete continuation is no longer allowed to publish on completion.
    if (cursor.isNotEmpty &&
        !_pages.values.any((entry) => entry.nextCursor == cursor)) {
      return;
    }
    _pages[cursor] = page;
    final reachable = <String>{};
    final rows = <String, Track>{};
    var next = '';
    String? problem;
    while (reachable.add(next)) {
      final batch = _pages[next];
      if (batch == null) break;
      for (final track in batch.items) {
        rows.putIfAbsent(track.id, () => track);
      }
      problem = batch.continuationProblem;
      if (!batch.hasMore || problem != null) break;
      final continuation = batch.nextCursor;
      if (continuation == null || reachable.contains(continuation)) {
        problem = '歌单续载位置重复或缺失，请刷新核对';
        break;
      }
      if (!_pages.containsKey(continuation)) break;
      next = continuation;
    }
    _pages.removeWhere((key, _) => !reachable.contains(key));
    _items = List.unmodifiable(rows.values);
    ready = true;
    error = problem;
    _notify();
  }

  /// Full search/sort/bulk actions explicitly obtained this complete live
  /// collection. Reuse it locally without continuing obsolete page requests.
  void useComplete(List<Track> tracks) {
    if (_disposed || !current()) return;
    _generation++;
    if (!_abort.isCompleted) _abort.complete();
    _abort = Completer<void>();
    _cached.reset();
    _pages.clear();
    loading = false;
    _install('', QishuiCatalogPage(items: tracks, cursor: ''));
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (!_abort.isCompleted) _abort.complete();
    _cached.dispose();
    super.dispose();
  }
}
