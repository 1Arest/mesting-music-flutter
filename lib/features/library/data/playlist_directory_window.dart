import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/database/app_database.dart';
import 'library_repository.dart';

class PlaylistDirectoryPage {
  const PlaylistDirectoryPage(
    this.items, {
    required this.nextOffset,
    required this.hasMore,
    this.total,
  });
  final List<UserPlaylist> items;
  final int nextOffset;
  final bool hasMore;
  final int? total;
}

/// Page only the browsing directory; playlist pickers explicitly retain their
/// complete repository read. Snapshot refresh retains the already-browsed span.
class PlaylistDirectoryWindow extends ChangeNotifier {
  PlaylistDirectoryWindow(this.repository) {
    _subscription = repository.watchPlaylistDirectory().listen((page) async {
      final generation = ++_generation;
      loading = true;
      final wanted = items.length;
      final staged = [...page.items];
      try {
        var current = page;
        while (current.hasMore && staged.length < wanted) {
          final next = await repository.playlistDirectoryPage(
            offset: current.nextOffset,
          );
          if (_disposed || generation != _generation) return;
          if (next.nextOffset <= current.nextOffset) {
            throw StateError('歌单分页未前进');
          }
          staged.addAll(next.items);
          current = next;
        }
        if (!_disposed && generation == _generation) _publish(staged, current);
      } catch (failure, stack) {
        if (!_disposed && generation == _generation) _fail(failure, stack);
      }
    }, onError: _fail);
  }
  final LibraryRepository repository;
  late final StreamSubscription<PlaylistDirectoryPage> _subscription;
  final _updates = StreamController<List<UserPlaylist>>.broadcast(sync: true);
  List<UserPlaylist> items = const [];
  int _offset = 0, _generation = 0;
  int? total;
  bool hasMore = true, loading = true, _disposed = false, _ready = false;
  Object? error;
  Stream<List<UserPlaylist>> get stream => Stream.multi((sink) {
    final sub = _updates.stream.listen(sink.add, onError: sink.addError);
    if (_ready) sink.add(items);
    if (!_ready && error != null) sink.addError(error!);
    sink.onCancel = sub.cancel;
  });
  void _fail(Object failure, StackTrace stack) {
    if (_disposed) return;
    error = failure;
    loading = false;
    if (!_ready) _updates.addError(failure, stack);
    notifyListeners();
  }

  void _publish(List<UserPlaylist> rows, PlaylistDirectoryPage page) {
    final seen = <String>{};
    items = List.unmodifiable(rows.where((row) => seen.add(row.id)));
    _offset = page.nextOffset;
    hasMore = page.hasMore;
    total = page.total;
    loading = false;
    error = null;
    _ready = true;
    _updates.add(items);
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasMore) return;
    final generation = _generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await repository.playlistDirectoryPage(offset: _offset);
      if (_disposed || generation != _generation) return;
      if (page.hasMore && page.nextOffset <= _offset) {
        throw StateError('歌单分页未前进');
      }
      _publish([...items, ...page.items], page);
    } catch (failure, stack) {
      if (!_disposed && generation == _generation) _fail(failure, stack);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_subscription.cancel());
    unawaited(_updates.close());
    super.dispose();
  }
}
