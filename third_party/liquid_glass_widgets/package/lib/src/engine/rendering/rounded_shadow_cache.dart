import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Width-independent silhouette of one axis-aligned rounded rectangle.
/// The radius/height and shadow parameters must match exactly. A
/// changing corner, scale, frost edge or blended shape takes the live path.
class RoundedShadowProfile {
  const RoundedShadowProfile({
    required this.bounds,
    required this.radius,
    required this.nativeEdge,
  });
  final Rect bounds;
  final double radius;
  double get height => bounds.height;
  final bool nativeEdge;
  @override
  bool operator ==(Object other) =>
      other is RoundedShadowProfile &&
      height == other.height &&
      radius == other.radius &&
      nativeEdge == other.nativeEdge;
  @override
  int get hashCode => Object.hash(height, radius, nativeEdge);
}

/// Retains Gaussian blur rasters for width-only capsule morphs.
///
/// The cap bands contain the full corner/blur footprint. Only their uniform
/// straight middle stretches. Each original shadow keeps its own saveLayer
/// and is punched out with the CURRENT geometry mask, so fractional-pixel
/// inner-edge coverage remains identical to live drawing. Narrow controls,
/// changing heights/corners and blended shapes retain the live path.
class RoundedShadowCache {
  RoundedShadowProfile? _previous, _builtProfile;
  List<BoxShadow>? _previousShadows, _builtShadows;
  double _previousDpr = 0, _builtDpr = 0;
  final List<_ShadowRaster> _rasters = [];

  bool paint({
    required Canvas canvas,
    required Offset offset,
    required Rect bounds,
    required double dpr,
    required RoundedShadowProfile? profile,
    required List<BoxShadow> shadows,
    required void Function(Canvas, BoxShadow) rasterizeBlur,
    required void Function(Canvas, Offset) cutout,
    required VoidCallback onBake,
    required VoidCallback onHit,
  }) {
    final stable = profile != null &&
        profile == _previous &&
        listEquals(shadows, _previousShadows) &&
        dpr == _previousDpr;
    _previous = profile;
    _previousDpr = dpr;
    if (!listEquals(shadows, _previousShadows)) {
      _previousShadows = List.of(shadows);
    }
    if (!stable || !dpr.isFinite || dpr <= 0) return false;
    final plans = <(BoxShadow, Rect, double, int, int)>[];
    var totalPixels = 0;
    for (final shadow in shadows) {
      if (shadow.color.a == 0) continue;
      final area = bounds
          .shift(shadow.offset)
          .inflate(shadow.spreadRadius + shadow.blurRadius * 3 + 2);
      if (!area.isFinite || area.isEmpty) return false;
      final reach = profile.radius +
          shadow.spreadRadius.abs() +
          shadow.blurRadius * 3 +
          shadow.offset.dx.abs() +
          2;
      final cap =
          ((reach + (area.width - bounds.width) / 2) * dpr).ceilToDouble() + 2;
      final width = (area.width * dpr).ceil(),
          height = (area.height * dpr).ceil();
      totalPixels += width * height;
      if (width <= cap * 2 + 1 || height <= 0 || totalPixels > 1024 * 1024) {
        return false;
      }
      plans.add((shadow, area, cap, width, height));
    }
    if (plans.isEmpty) return false;
    if (_rasters.isEmpty ||
        profile != _builtProfile ||
        !listEquals(shadows, _builtShadows) ||
        dpr != _builtDpr) {
      final replacement = <_ShadowRaster>[];
      try {
        for (final (shadow, area, cap, width, height) in plans) {
          final rect =
              Rect.fromLTWH(area.left, area.top, width / dpr, height / dpr);
          final recorder = ui.PictureRecorder();
          final target = Canvas(recorder)
            ..scale(dpr)
            ..translate(-rect.left, -rect.top);
          rasterizeBlur(target, shadow);
          final picture = recorder.endRecording();
          try {
            replacement.add(_ShadowRaster(
                picture.toImageSync(width, height), rect, bounds.width, cap));
          } finally {
            picture.dispose();
          }
          onBake();
        }
      } catch (_) {
        for (final raster in replacement) {
          raster.image.dispose();
        }
        rethrow;
      }
      _clearRasters();
      _rasters.addAll(replacement);
      _builtProfile = profile;
      _builtShadows = List.of(shadows);
      _builtDpr = dpr;
    }
    for (var i = 0; i < _rasters.length; i++) {
      final raster = _rasters[i];
      final area = plans[i].$2;
      canvas.saveLayer(area.shift(offset), Paint());
      // drawImageNine keeps corners in canvas units. Draw in physical pixels
      // so DPR does not scale the cached corner bands a second time.
      canvas
        ..save()
        ..translate(offset.dx, offset.dy)
        ..scale(1 / dpr);
      canvas.drawImageNine(
          raster.image,
          Rect.fromLTRB(raster.cap, 0, raster.image.width - raster.cap,
              raster.image.height.toDouble()),
          Rect.fromLTWH(
              area.left * dpr,
              area.top * dpr,
              (raster.rect.width + bounds.width - raster.width) * dpr,
              raster.rect.height * dpr),
          Paint()..filterQuality = FilterQuality.low);
      canvas.restore();
      // This uses today's mask rather than stretching yesterday's sharp
      // cutout; its anti-aliased inner edge follows the exact current shape.
      cutout(canvas, offset);
      canvas.restore();
    }
    onHit();
    return true;
  }

  void _clearRasters() {
    for (final raster in _rasters) {
      raster.image.dispose();
    }
    _rasters.clear();
  }

  void dispose() {
    _clearRasters();
    _previous = _builtProfile = null;
    _previousShadows = _builtShadows = null;
  }
}

class _ShadowRaster {
  const _ShadowRaster(this.image, this.rect, this.width, this.cap);
  final ui.Image image;
  final Rect rect;
  final double width, cap;
}
