import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/geometry_matte_cache.dart';

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xff47aacc),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(4, 4);
  } finally {
    picture.dispose();
  }
}

void main() {
  test('matte keys preserve exact fractional geometry and input order', () {
    final values = [2.625, 33.0, 70.0];
    final key = GeometryMatteKey(values);
    values[1] = 34;
    expect(key, GeometryMatteKey([2.625, 33, 70]));
    expect(key, isNot(GeometryMatteKey([2.625, 33.0000001, 70])));
    expect(key, isNot(GeometryMatteKey([2.625, 70, 33])));
  });
  testWidgets('cache and visible consumers own independent image handles', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = GeometryMatteCache();
      final key = GeometryMatteKey([2.625, 70]);
      final image = await _image();
      cache.remember(key, image);
      image.dispose();
      final visible = cache.obtain(key)!;
      cache.clear();
      expect(cache.retainedPixels, 0);
      expect(visible.debugDisposed, isFalse);
      final pixels = await visible.toByteData();
      expect(pixels!.getUint8(0), 0x47);
      visible.dispose();
      cache.dispose();
    });
  });
  testWidgets('LRU obeys pixel/entry limits and memory-pressure eviction', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = GeometryMatteCache(maxPixels: 32, maxEntries: 2);
      final image = await _image();
      final keys = List.generate(3, (i) => GeometryMatteKey([i.toDouble()]));
      cache.remember(keys[0], image);
      cache.remember(keys[1], image);
      cache.obtain(keys[0])!.dispose(); // Refresh the first entry's recency.
      cache.remember(keys[2], image);
      expect(cache.obtain(keys[1]), isNull);
      expect(cache.length, 2);
      expect(cache.retainedPixels, 32);
      cache.didHaveMemoryPressure();
      expect(cache.length, 0);
      expect(cache.retainedPixels, 0);
      expect(image.debugDisposed, isFalse);
      image.dispose();
      cache.dispose();
    });
  });
  testWidgets('oversized and nonfinite entries are never retained', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await _image();
      final cache = GeometryMatteCache(maxEntryPixels: 8);
      cache.remember(GeometryMatteKey([0]), image);
      expect(cache.length, 0);
      final validSize = GeometryMatteCache();
      validSize.remember(GeometryMatteKey([double.nan]), image);
      expect(validSize.length, 0);
      image.dispose();
      cache.dispose();
      validSize.dispose();
    });
  });
}
