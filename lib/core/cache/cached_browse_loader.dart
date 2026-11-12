import 'dart:async';
import 'browse_response_cache.dart';

/// A stateful page owns one loader and disposes it with its scroll/controller.
/// Each loaded page keeps its own query and updates just that batch, retaining
/// later pages, scroll state and input while network revalidation completes.
class CachedBrowseLoader {
  final _queries = <Object, _BrowseQuery<dynamic>>{};
  bool _disposed = false;

  Future<T> load<T>({
    required Object key,
    required Future<T> Function() request,
    required void Function(T previous, T current) onUpdate,
  }) {
    _queries.remove(key)?.dispose();
    final query = _BrowseQuery<T>(request, onUpdate);
    if (_disposed) return request();
    _queries[key] = query;
    return query.initial();
  }

  void reset() {
    for (final query in _queries.values) {
      query.dispose();
    }
    _queries.clear();
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}

class _BrowseQuery<T> {
  _BrowseQuery(this.request, this.onUpdate);
  final Future<T> Function() request;
  final void Function(T previous, T current) onUpdate;
  late final watch = BrowseCacheWatch(() => unawaited(_refresh()));
  late T _value;
  bool _ready = false, _disposed = false, _refreshing = false, _again = false;

  Future<T> initial() async {
    final value = await watch.run(request);
    _value = value;
    _ready = true;
    if (_again) {
      _again = false;
      unawaited(_refresh());
    }
    return value;
  }

  Future<void> _refresh() async {
    if (_disposed) return;
    if (!_ready || _refreshing) {
      _again = true;
      return;
    }
    _refreshing = true;
    try {
      final value = await watch.run(request);
      if (!_disposed) {
        final previous = _value;
        _value = value;
        onUpdate(previous, value);
      }
    } on Object {
      /* A refresh error retains the last displayed page. */
    } finally {
      _refreshing = false;
      if (_again && !_disposed) {
        _again = false;
        unawaited(_refresh());
      }
    }
  }

  void dispose() {
    _disposed = true;
    watch.dispose();
  }
}

/// Replaces one page by logical identity while retaining other loaded pages.
void replaceBrowsePage<T>(
  List<T> items,
  Iterable<T> previous,
  Iterable<T> current,
  String Function(T) identity, {
  int fallbackIndex = 0,
}) {
  final oldIds = previous.map(identity).toSet();
  final fresh = <T>[];
  final seen = <String>{};
  for (final item in current) {
    if (seen.add(identity(item))) fresh.add(item);
  }
  var position = items.indexWhere((item) => oldIds.contains(identity(item)));
  if (position < 0) position = fallbackIndex;
  items.removeWhere(
    (item) => oldIds.contains(identity(item)) || seen.contains(identity(item)),
  );
  items.insertAll(position.clamp(0, items.length), fresh);
}
