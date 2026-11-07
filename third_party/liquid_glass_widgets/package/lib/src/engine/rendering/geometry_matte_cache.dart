import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Exact shader inputs. No rounded sizes or approximated material parameters.
@immutable
class GeometryMatteKey {
  GeometryMatteKey(Iterable<double> values)
      : values = List<double>.unmodifiable(values);
  final List<double> values;
  late final int _hash = Object.hashAll(values);
  @override
  int get hashCode => _hash;
  @override
  bool operator ==(Object other) =>
      other is GeometryMatteKey && listEquals(values, other.values);
}

/// Bounded LRU for identical control geometry, never captured page contents.
/// Callers admit only full-resolution resting/initial sizes, so a one-frame
/// animated size does not evict recurring buttons. A cache and each consumer
/// own separate image handles; eviction cannot dispose a visible image.
class GeometryMatteCache with WidgetsBindingObserver {
  GeometryMatteCache({
    this.maxPixels = 2 * 1024 * 1024,
    this.maxEntries = 48,
    this.maxEntryPixels = 256 * 1024,
    bool observeMemoryPressure = false,
  }) : _observing = observeMemoryPressure {
    if (_observing) WidgetsBinding.instance.addObserver(this);
  }
  static final shared = GeometryMatteCache(observeMemoryPressure: true);
  final int maxPixels, maxEntries, maxEntryPixels;
  final bool _observing;
  final Map<GeometryMatteKey, ui.Image> _images = {};
  int _pixels = 0;
  @visibleForTesting
  int get retainedPixels => _pixels;
  @visibleForTesting
  int get length => _images.length;

  ui.Image? obtain(GeometryMatteKey key) {
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image;
    return image.clone();
  }

  void remember(GeometryMatteKey key, ui.Image image) {
    final pixels = image.width * image.height;
    if (pixels > maxEntryPixels ||
        pixels > maxPixels ||
        maxEntries <= 0 ||
        key.values.any((v) => !v.isFinite)) {
      return;
    }
    final previous = _images.remove(key);
    if (previous != null) {
      _pixels -= previous.width * previous.height;
      previous.dispose();
    }
    while (_images.isNotEmpty &&
        (_pixels + pixels > maxPixels || _images.length >= maxEntries)) {
      final image = _images.remove(_images.keys.first)!;
      _pixels -= image.width * image.height;
      image.dispose();
    }
    _images[key] = image.clone();
    _pixels += pixels;
  }

  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _pixels = 0;
  }

  @override
  void didHaveMemoryPressure() => clear();
  void dispose() {
    clear();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
  }
}
