import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import 'library_repository.dart';

/// Visible collection details and the complete collection are distinct. A
/// window requests one source page at a time; only an explicit complete action
/// (search/export/play all) asks the repository for the remaining collection.
class FavoriteTrackWindow extends ChangeNotifier {
  FavoriteTrackWindow(
    this.repository, {
    this.playlistId,
    this.readPage,
    Stream<TrackPage>? preview,
  }) {
    _subscription =
        (preview ??
                (playlistId == null
                    ? repository.watchFavoritePreview()
                    : repository.watchPlaylistPreview(playlistId!)))
            .listen(
              (page) => unawaited(_replacePreview(page)),
              onError: (Object failure, StackTrace stack) {
                error = failure;
                loading = false;
                if (!_hasValue) _updates.addError(failure, stack);
                _notify();
              },
            );
  }

  final LibraryRepository repository;
  final String? playlistId;
  final Future<TrackPage> Function(int offset, int limit)? readPage;
  Future<TrackPage> _page({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) => readPage != null
      ? readPage!(offset, limit)
      : playlistId == null
      ? repository.favoritePage(offset: offset, limit: limit, query: query)
      : repository.playlistPage(playlistId!, offset: offset, limit: limit);
  final _updates = StreamController<List<Track>>.broadcast(sync: true);
  late final StreamSubscription<TrackPage> _subscription;
  List<Track> items = const [];
  int? total;
  int _offset = 0, _generation = 0;
  bool hasMore = true, loading = true, _hasValue = false, _disposed = false;
  Object? error;

  Stream<List<Track>> get stream => Stream.multi((sink) {
    final subscription = _updates.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    if (_hasValue) sink.add(items);
    if (error != null && !_hasValue) sink.addError(error!);
    sink.onCancel = subscription.cancel;
  });

  /// Appending a visible page does not invalidate complete membership. Only a
  /// replacement snapshot advances this revision and refreshes the ID index.
  Stream<int> get revisions => stream.map((_) => _generation).distinct();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _publish(List<Track> tracks, TrackPage last) {
    items = List.unmodifiable(tracks);
    total = last.total ?? (last.hasMore ? total : last.nextOffset);
    _offset = last.nextOffset;
    hasMore = last.hasMore;
    loading = false;
    error = null;
    _hasValue = true;
    _updates.add(items);
    _notify();
  }

  Future<void> _replacePreview(TrackPage first) async {
    final generation = ++_generation;
    loading = true;
    final wanted = math.max(first.items.length, items.length);
    final staged = <Track>[...first.items];
    final seen = staged.map((t) => t.id).toSet();
    var page = first;
    try {
      // Refresh only the already-browsed window, preserving its scroll extent
      // and the previous usable snapshot until the replacement is complete.
      while (page.hasMore && staged.length < wanted) {
        final next = await _page(offset: page.nextOffset);
        if (_disposed || generation != _generation) return;
        if (next.nextOffset <= page.nextOffset) {
          throw StateError('收藏分页未前进，请重试');
        }
        staged.addAll(next.items.where((track) => seen.add(track.id)));
        page = next;
      }
      if (!_disposed && generation == _generation) _publish(staged, page);
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure;
      loading = false;
      if (!_hasValue) _updates.addError(failure);
      _notify();
    }
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasMore) return;
    final generation = _generation;
    loading = true;
    error = null;
    _notify();
    try {
      final page = await _page(offset: _offset);
      if (_disposed || generation != _generation) return;
      if (page.hasMore && page.nextOffset <= _offset) {
        throw StateError('收藏分页未前进，请重试');
      }
      final seen = items.map((track) => track.id).toSet();
      _publish([
        ...items,
        ...page.items.where((track) => seen.add(track.id)),
      ], page);
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure;
      loading = false;
      _notify();
    }
  }

  Future<TrackPage> search(String query, {int offset = 0}) async {
    if (_disposed) throw StateError('账号已变化');
    final page = await _page(offset: offset, query: query);
    if (_disposed) throw StateError('账号已变化');
    return page;
  }

  Future<List<Track>> complete() async {
    if (_disposed) throw StateError('账号已变化');
    final generation = _generation;
    final tracks = <Track>[];
    final seen = <String>{};
    var offset = 0;
    while (true) {
      final page = await _page(offset: offset, limit: 200);
      if (_disposed || generation != _generation) {
        throw StateError('收藏已变化，请重试');
      }
      tracks.addAll(page.items.where((track) => seen.add(track.id)));
      if (!page.hasMore) return tracks;
      if (page.nextOffset <= offset) throw StateError('收藏分页未前进，请重试');
      offset = page.nextOffset;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription.cancel());
    unawaited(_updates.close());
    super.dispose();
  }
}
