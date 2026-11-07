import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';

/// Premium glass asks for descendants' transforms before painting them. Probe
/// that order explicitly; an after-paint screenshot alone misses stale Flow
/// coordinates even though the first Android frame shows a top-left ghost.
class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required this.beforePaint, required super.child});
  final VoidCallback beforePaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProbe(beforePaint);
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this.beforePaint);
  final VoidCallback beforePaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    beforePaint();
    super.paint(context, offset);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  testWidgets(
    'menu transforms are current before paint, including first entry and rapid reversal',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final motion = AnimationController(
        vsync: tester,
        duration: betaMenuOpenDuration,
      );
      final key = GlobalKey();
      final samples = <({double t, Offset topLeft})>[];
      var builds = 0;
      await tester.pumpWidget(
        LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => _Probe(
                  beforePaint: () {
                    final box = key.currentContext?.findRenderObject();
                    if (box is RenderBox) {
                      samples.add((
                        t: motion.value,
                        topLeft: box.localToGlobal(Offset.zero),
                      ));
                    }
                  },
                  child: BetaLiquidMenu(
                    animation: motion,
                    layout: BetaMenuLayout(
                      anchor: const Rect.fromLTWH(330, 40, 48, 48),
                      media: MediaQuery.of(context),
                      width: 280,
                    ),
                    child: Builder(
                      builder: (_) {
                        builds++;
                        return SizedBox(key: key, width: 280, height: 240);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(samples.first.topLeft.dx, greaterThan(300));
      expect(samples.first.topLeft.dy, greaterThan(40));
      for (final value in [0.12, 0.48, 0.25, 0.8, 0.4, 1.0]) {
        motion.value = value;
        await tester.pump();
        final before = samples.last;
        final after = (key.currentContext!.findRenderObject() as RenderBox)
            .localToGlobal(Offset.zero);
        expect(before.t, value);
        expect(
          (before.topLeft - after).distance,
          lessThan(.01),
          reason: 'SDF and content must see the same frame',
        );
      }
      expect(builds, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      motion.dispose();
    },
  );
}
