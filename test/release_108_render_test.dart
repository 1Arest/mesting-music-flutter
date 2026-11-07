import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/glass_render_diagnostics.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_layer.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_settings.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_widgets/src/renderer/glass_backdrop_group.dart';
import 'package:liquid_glass_widgets/src/renderer/glass_backdrop_peer.dart';
import 'package:mesting_music/core/performance/frame_timing_probe.dart';

// Exercise real membership/key invalidation without pretending the host Skia
// backend can measure the Android Impeller shader. Fixed lens bounds stand in
// for its matte; the actual engine's transform/pass/group policy is unchanged.
class _Lens extends SingleChildRenderObjectWidget {
  const _Lens({super.key});
  @override
  _LensRender createRenderObject(BuildContext context) => _LensRender()
    ..backdropKey = GlassBackdropGroup.keyOf(context)
    ..sharedBackdrop = true;
}

class _LensRender extends RenderLiquidGlassLayer {
  _LensRender()
    : super(
        renderShader: null,
        devicePixelRatio: 1,
        settings: const LiquidGlassSettings(blur: 2),
        shadows: [],
        link: GeometryRenderLink(),
      );
  @override
  ui.Rect get paintBounds => Offset.zero & size;
}

void main() {
  testWidgets(
    'stable peers share; gate, press and fade clear retained membership immediately',
    (tester) async {
      final state = ValueNotifier((true, true, 1.0));
      addTearDown(state.dispose);
      final a = GlobalKey();
      final b = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GlassBackdropGroup(
            requireDisjointBounds: true,
            child: ValueListenableBuilder(
              valueListenable: state,
              builder: (_, s, _) => Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 100,
                    height: 40,
                    child: _Lens(key: a),
                  ),
                  Positioned(
                    left: 0,
                    top: 80,
                    width: 100,
                    height: 40,
                    child: GlassBackdropSharingGate(
                      enabled: s.$1 && s.$2,
                      child: GlassPeerFade(
                        visible: s.$1,
                        child: Transform.scale(
                          scale: s.$3,
                          child: _Lens(key: b),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      _LensRender lens(GlobalKey key) =>
          key.currentContext!.findRenderObject()! as _LensRender;
      bool resolve() {
        lens(a).debugResolveSharing();
        lens(b).debugResolveSharing();
        return lens(a).debugResolveSharing();
      }

      expect(resolve(), isTrue);
      final original = b.currentContext;
      state.value = (true, false, 1);
      await tester.pump(); // before a geometry tween has advanced
      expect(lens(b).debugSharesBackdrop, isFalse);
      expect(resolve(), isFalse);
      state.value = (true, true, 1);
      await tester.pump();
      expect(resolve(), isTrue);
      state.value = (true, true, 1.12);
      await tester.pump();
      expect(resolve(), isFalse, reason: 'retained press scale must not join');
      state.value = (false, true, 1);
      await tester.pump();
      expect(lens(b).debugSharesBackdrop, isFalse);
      await tester.pump(const Duration(milliseconds: 8));
      expect(resolve(), isFalse);
      expect(b.currentContext, same(original));
      state.value = (true, true, 1);
      await tester.pumpAndSettle();
      expect(resolve(), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('overlap and ordinary opaque Opacity remain isolated', (
    tester,
  ) async {
    for (final mode in [0, 1]) {
      final a = GlobalKey();
      final b = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GlassBackdropGroup(
            requireDisjointBounds: true,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 100,
                  height: 40,
                  child: _Lens(key: a),
                ),
                Positioned(
                  left: 0,
                  top: mode == 0 ? 20 : 80,
                  width: 100,
                  height: 40,
                  child: mode == 0
                      ? _Lens(key: b)
                      : Opacity(opacity: 1, child: _Lens(key: b)),
                ),
              ],
            ),
          ),
        ),
      );
      final first = a.currentContext!.findRenderObject()! as _LensRender;
      final second = b.currentContext!.findRenderObject()! as _LensRender;
      first.debugResolveSharing();
      second.debugResolveSharing();
      expect(first.debugResolveSharing(), isFalse);
      expect(second.debugResolveSharing(), isFalse);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'diagnostics align raw vsync, drain final batch and exclude outside frames',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      FrameTimingProbe.beginSession(120, environment: {'appVersion': '1.0.8'});
      final start = FrameTimingProbe.sessionReport()['startVsyncUs']! as int;
      tester.binding.handleBeginFrame(Duration(microseconds: start + 10000));
      tester.binding.handleDrawFrame();
      FrameTimingProbe.markTransition('page_change');
      GlassRenderDiagnostics.count(GlassRenderMetric.matteRebuilds);
      tester.binding.handleBeginFrame(Duration(microseconds: start + 20000));
      tester.binding.handleDrawFrame();
      final stopped = FrameTimingProbe.stopSession();
      expect(FrameTimingProbe.draining.value, isTrue);
      final end = FrameTimingProbe.sessionReport()['stopVsyncUs']! as int;
      final elapsedAtStop = FrameTimingProbe.sessionReport()['elapsedMs'];
      FrameTimingProbe.collectForTest([
        _timing(start),
        _timing(end),
        _timing(end + 1),
      ]);
      expect((FrameTimingProbe.sessionReport()['samples']! as List).length, 1);
      await tester.pump(const Duration(milliseconds: 1200));
      await stopped;
      final report = FrameTimingProbe.sessionReport();
      expect(report['schema'], 2);
      expect(report['timingsDrained'], isTrue);
      final event = (report['events']! as List).single as Map;
      expect(event['nextVsyncUs'], greaterThan(event['lastVsyncUs']! as int));
      expect(report['paintCounters'], isNotEmpty);
      GlassRenderDiagnostics.count(GlassRenderMetric.captures);
      expect(report['paintCounters'], GlassRenderDiagnostics.report());
      expect(report['elapsedMs'], elapsedAtStop);
    },
  );

  test(
    'disabled renderer diagnostics allocate no rows and exported copies are independent',
    () {
      GlassRenderDiagnostics.begin();
      GlassRenderDiagnostics.count(GlassRenderMetric.blurPasses, amount: 2);
      GlassRenderDiagnostics.stop();
      final report = GlassRenderDiagnostics.report();
      GlassRenderDiagnostics.count(GlassRenderMetric.blurPasses);
      expect(GlassRenderDiagnostics.report(), report);
      report.first['blurPasses'] = 100;
      expect(GlassRenderDiagnostics.report().first['blurPasses'], 2);
    },
  );
}

ui.FrameTiming _timing(int at) => ui.FrameTiming(
  vsyncStart: at,
  buildStart: at + 10,
  buildFinish: at + 100,
  rasterStart: at + 100,
  rasterFinish: at + 200,
  rasterFinishWallTime: at + 200,
  frameNumber: at,
);
