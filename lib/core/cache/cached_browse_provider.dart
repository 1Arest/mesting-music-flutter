import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'browse_response_cache.dart';

/// Retains the existing FutureProvider contract. Only responses consumed by
/// this provider can invalidate it; unrelated pages keep their state and scroll.
Future<T> cachedBrowse<T>(Ref ref, Future<T> Function() load) {
  final watch = BrowseCacheWatch(() {
    if (ref.mounted) ref.invalidateSelf();
  });
  ref.onDispose(watch.dispose);
  return watch.run(load);
}
