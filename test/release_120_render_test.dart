import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_layer.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_settings.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';

// Exercise the real glass compositing predicate with a host-supported filter.
// A canvas clip around a subsequently pushed layer is insufficient: Flutter
// must emit a ClipRectLayer before the first GPU matte has been constructed.
class _FirstPaintGlass extends SingleChildRenderObjectWidget {
  const _FirstPaintGlass({super.key});
  @override
  _FirstPaintRender createRenderObject(BuildContext context) =>
      _FirstPaintRender();
}

class _FirstPaintRender extends RenderLiquidGlassLayer {
  _FirstPaintRender()
    : super(
        link: GeometryRenderLink(),
        renderShader: null,
        settings: const LiquidGlassSettings(blur: 2),
        devicePixelRatio: 1,
        shadows: [],
      );
  final _clip = LayerHandle<ClipRectLayer>();
  final _filter = LayerHandle<BackdropFilterLayer>(
    BackdropFilterLayer()..filter = ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
  );
  ClipRectLayer? get emittedClip => _clip.layer;
  BackdropFilterLayer get filter => _filter.layer!;
  @override
  // This probe deliberately substitutes a host-supported pass for the shader.
  // ignore: must_call_super
  void paint(PaintingContext context, Offset offset) {
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      const Rect.fromLTWH(0, 0, 100, 40),
      (context, offset) =>
          context.pushLayer(filter, (context, offset) {}, offset),
      oldLayer: emittedClip,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _filter.layer = null;
    super.dispose();
  }
}

void main() {
  testWidgets(
    'first-paint backdrop pass is bounded even before the matte exists',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              height: 40,
              child: _FirstPaintGlass(key: key),
            ),
          ),
        ),
      );
      final render =
          key.currentContext!.findRenderObject()! as _FirstPaintRender;
      expect(render.needsCompositing, isTrue);
      expect(
        render.emittedClip,
        isNotNull,
        reason: 'The live filter needs a compositor clip on its first paint.',
      );
      expect(render.emittedClip!.clipRect!.size, const Size(100, 40));
      expect(render.filter.parent, same(render.emittedClip));
      render.settings = const LiquidGlassSettings(blur: 4);
      await tester.pump();
      expect(render.filter.parent, same(render.emittedClip));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
