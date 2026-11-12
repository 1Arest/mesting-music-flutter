import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/glass_render_diagnostics.dart';

import 'release_120_shadow_test.dart' as fixture;

void expectSameShadow(Uint8List expected, Uint8List actual) {
  final differences = [
    for (var i = 0; i < actual.length; i++) (expected[i] - actual[i]).abs(),
  ]..sort();
  expect(differences[(differences.length * .99).floor()], lessThanOrEqualTo(2));
  expect(differences.last, lessThanOrEqualTo(12));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dpr in [3.0, 2.625]) {
    test('settled rounded shadow retains full raster at DPR $dpr', () async {
      final cached = fixture.lens(dpr);
      final mask = await fixture.matte(245.14, 44, dpr);
      const bounds = Rect.fromLTWH(30, 30, 245.14, 44);
      GlassRenderDiagnostics.begin();
      try {
        for (var frame = 0; frame < 4; frame++) {
          // A new reference surface always takes the original live blur path.
          final original = fixture.lens(dpr);
          final expected = await fixture.render(original, mask, bounds);
          original.dispose();
          final actual = await fixture.render(
            cached,
            mask,
            bounds,
            retained: true,
          );
          expectSameShadow(expected, actual);
          if (frame > 0) expect(cached.debugBakedShadow, isNotNull);
        }
        final baked = cached.debugBakedShadow;
        await fixture.render(cached, mask, bounds, retained: true);
        expect(identical(cached.debugBakedShadow, baked), isTrue);
        final counters = GlassRenderDiagnostics.report();
        expect(
          counters.fold<int>(
            0,
            (n, row) => n + (row['shadowBakes'] as int? ?? 0),
          ),
          1,
        );
        // Bounds, DPR and colors participate in invalidation, even when the
        // geometry handle itself remains stable across an ancestor update.
        final expectedLayer = fixture.lens(dpr);
        const moved = Rect.fromLTWH(31.25, 30.5, 245.14, 44);
        final expected = await fixture.render(expectedLayer, mask, moved);
        expectedLayer.dispose();
        final actual = await fixture.render(
          cached,
          mask,
          moved,
          retained: true,
        );
        expectSameShadow(expected, actual);
        expect(identical(cached.debugBakedShadow, baked), isFalse);
      } finally {
        GlassRenderDiagnostics.stop();
        cached.dispose();
        mask.dispose();
      }
    });
  }
}
