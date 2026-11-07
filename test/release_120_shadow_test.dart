import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/glass_render_diagnostics.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_layer.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_settings.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/rounded_shadow_cache.dart';

const shadows = [
  BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x18000000), blurRadius: 3),
];
RenderLiquidGlassLayer lens([double dpr = 3]) => RenderLiquidGlassLayer(
  renderShader: null,
  devicePixelRatio: dpr,
  settings: const LiquidGlassSettings(blur: 2),
  shadows: shadows,
  link: GeometryRenderLink(),
);

Future<ui.Image> matte(double width, double height, [double dpr = 3]) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(dpr);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      Radius.circular(height / 2),
    ),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * dpr).ceil(),
    (height * dpr).ceil(),
  );
  picture.dispose();
  return image;
}

Future<Uint8List> render(
  RenderLiquidGlassLayer layer,
  ui.Image mask,
  Rect bounds, {
  bool retained = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(layer.devicePixelRatio);
  layer.debugPaintShadows(
    canvas,
    Offset.zero,
    mask,
    bounds,
    profile: retained
        ? RoundedShadowProfile(
            bounds: bounds,
            radius: bounds.height / 2,
            nativeEdge: false,
          )
        : null,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(1200, 360);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'width-only capsule shadow retains original Gaussian corners and reuses blur rasters',
    () async {
      final original = lens(), cached = lens();
      addTearDown(original.dispose);
      addTearDown(cached.dispose);
      GlassRenderDiagnostics.begin();
      addTearDown(GlassRenderDiagnostics.stop);
      var comparisons = 0;
      for (final width in [245.0, 245.0, 351.0, 160.0, 280.0]) {
        final mask = await matte(width, 44);
        final bounds = Rect.fromLTWH(30, 30, width, 44);
        final expected = await render(original, mask, bounds);
        final actual = await render(cached, mask, bounds, retained: true);
        final differences = [
          for (var i = 3; i < actual.length; i += 4)
            (expected[i] - actual[i]).abs(),
        ]..sort();
        expect(
          differences[(differences.length * .99).floor()],
          lessThanOrEqualTo(2),
          reason:
              'A stretched middle must preserve the Gaussian corner pixels.',
        );
        expect(differences.last, lessThanOrEqualTo(12));
        comparisons++;
        mask.dispose();
      }
      final counters = GlassRenderDiagnostics.report();
      int total(String metric) =>
          counters.fold(0, (sum, row) => sum + (row[metric] as int? ?? 0));
      expect(comparisons, 5);
      expect(total('shadowBakes'), 2);
      expect(total('shadowCacheHits'), 4);
    },
  );
  test(
    'fractional DPR 2.625 and width changes retain the Gaussian shadow',
    () async {
      final original = lens(2.625), cached = lens(2.625);
      addTearDown(original.dispose);
      addTearDown(cached.dispose);
      GlassRenderDiagnostics.begin();
      addTearDown(GlassRenderDiagnostics.stop);
      var comparisons = 0;
      for (final width in [245.14, 245.14, 351.35, 160.3, 280.01]) {
        final mask = await matte(width, 44, 2.625);
        final bounds = Rect.fromLTWH(30, 30, width, 44);
        final expected = await render(original, mask, bounds);
        final actual = await render(cached, mask, bounds, retained: true);
        final differences = [
          for (var i = 3; i < actual.length; i += 4)
            (expected[i] - actual[i]).abs(),
        ]..sort();
        expect(
          differences[(differences.length * .99).floor()],
          lessThanOrEqualTo(2),
          reason:
              'A stretched middle must preserve the Gaussian corner pixels.',
        );
        expect(differences.last, lessThanOrEqualTo(12));
        comparisons++;
        mask.dispose();
      }
      final counters = GlassRenderDiagnostics.report();
      int total(String metric) =>
          counters.fold(0, (sum, row) => sum + (row[metric] as int? ?? 0));
      expect(comparisons, 5);
      expect(total('shadowBakes'), 2);
      expect(total('shadowCacheHits'), 4);
    },
  );
  test(
    'narrow capsules and changed silhouettes keep the live shadow path',
    () async {
      final cached = lens();
      addTearDown(cached.dispose);
      GlassRenderDiagnostics.begin();
      addTearDown(GlassRenderDiagnostics.stop);
      for (final size in [
        const Size(245, 44),
        const Size(245, 50),
        const Size(48, 50),
        const Size(48, 50),
      ]) {
        final mask = await matte(size.width, size.height);
        await render(cached, mask, Offset.zero & size, retained: true);
        mask.dispose();
      }
      final counters = GlassRenderDiagnostics.report();
      int total(String metric) =>
          counters.fold(0, (sum, row) => sum + (row[metric] as int? ?? 0));
      expect(total('shadowBakes'), 0);
      expect(total('shadowLivePasses'), 8);
    },
  );
}
