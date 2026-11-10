import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/diagnostics/glass_lab_run.dart';

/// Explicit optics avoid depending on newer upstream theme/style defaults.
/// These are the current app pill values; no quality adaptation is enabled.
const glassLabOptics = LiquidGlassSettings(
  glassColor: Color(0x80F2F2F7),
  thickness: 30,
  blur: 2,
  lightIntensity: .28,
  chromaticAberration: .01,
  saturation: 1.2,
  fresnelStrength: .2,
  ambientStrength: 0,
  refractiveIndex: 1.2,
  frost: 0,
);

/// No repository, network image, account, playback or live business providers.
/// Repaint boundaries keep static row content separate from animated optics.
class GlassLabScene extends StatelessWidget {
  const GlassLabScene({
    required this.scenario,
    required this.scroll,
    required this.motion,
    super.key,
  });
  final GlassLabScenario scenario;
  final ScrollController scroll;
  final Animation<double> motion;

  Widget _panel(
    String label, {
    double width = 140,
    double height = 52,
    double blur = 2,
  }) => GlassContainer(
    key: ValueKey(label),
    useOwnLayer: true,
    quality: GlassQuality.premium,
    settings: blur == 2 ? glassLabOptics : glassLabOptics.copyWith(blur: blur),
    shape: const LiquidRoundedSuperellipse(borderRadius: 24),
    width: width,
    height: height,
    alignment: Alignment.center,
    child: ClipRect(
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(color: Color(0xff20242b)),
      ),
    ),
  );

  Widget _background(int page) => ColoredBox(
    color: page == 0 ? const Color(0xfff8f9fb) : const Color(0xfffff3ea),
    child: ListView.builder(
      key: ValueKey('background-$page'),
      controller: page == 0 ? scroll : null,
      itemExtent: 76,
      itemCount: 1500,
      itemBuilder: (context, i) => RepaintBoundary(
        child: ListTile(
          // Fixtures deliberately keep light backgrounds across themes. Match
          // their ink explicitly instead of inheriting dark-theme white text.
          leading: SizedBox.square(
            dimension: 48,
            child: CustomPaint(painter: _Cover(i + page * 17)),
          ),
          title: Text(
            'Synthetic track ${i.toString().padLeft(4, '0')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: const Color(0xff20242b)),
          ),
          subtitle: Text(
            'Fixed local content',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xff52606d)),
          ),
          trailing: const Icon(Icons.favorite, color: Colors.pink),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (_, box) {
          final background = RepaintBoundary(child: _background(0));
          if (scenario == GlassLabScenario.pageSlide) {
            final next = RepaintBoundary(child: _background(1));
            return AnimatedBuilder(
              animation: motion,
              builder: (context, child) => Stack(
                children: [
                  Transform.translate(
                    offset: Offset(-motion.value * box.maxWidth, 0),
                    child: background,
                  ),
                  Transform.translate(
                    offset: Offset((1 - motion.value) * box.maxWidth, 0),
                    child: next,
                  ),
                  Positioned(
                    bottom: 24,
                    left: 24,
                    child: _panel('Persistent chrome'),
                  ),
                ],
              ),
            );
          }
          final panels = switch (scenario) {
            GlassLabScenario.peersShared ||
            GlassLabScenario.peersSeparate ||
            GlassLabScenario.peersSharedMixedFilters => Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: GlassBackdropGroup(
                enabled: scenario != GlassLabScenario.peersSeparate,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _panel('Peer A'),
                    _panel(
                      'Peer B',
                      blur: scenario == GlassLabScenario.peersSharedMixedFilters
                          ? 3
                          : 2,
                    ),
                  ],
                ),
              ),
            ),
            // Overlapping peers intentionally do not share the background key.
            GlassLabScenario.overlap => Positioned(
              left: 32,
              bottom: 24,
              child: SizedBox(
                width: 290,
                height: 90,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: _panel('Back surface', width: 210),
                    ),
                    Positioned(
                      left: 70,
                      top: 32,
                      child: _panel('Front surface', width: 210),
                    ),
                  ],
                ),
              ),
            ),
            GlassLabScenario.menuMorph => Positioned(
              right: 24,
              bottom: 24,
              child: AnimatedBuilder(
                animation: motion,
                builder: (context, child) => _panel(
                  'Menu geometry',
                  width: 64 + 196 * motion.value,
                  height: 52 + 180 * motion.value,
                ),
              ),
            ),
            _ => Positioned(
              left: 24,
              bottom: 24,
              child: _panel('Single surface'),
            ),
          };
          return Stack(children: [background, panels]);
        },
      ),
    );
  }
}

/// Deterministic vector fixture. Bitmap upload is deliberately a separate
/// future experiment; these painted covers must not stand in for decode cost.
class _Cover extends CustomPainter {
  const _Cover(this.seed);
  final int seed;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.primaries[seed % Colors.primaries.length],
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
        Offset(size.width * (i + 1) / 6, size.height * ((seed + i) % 7) / 7),
        4 + i.toDouble(),
        Paint()..color = const Color(0x99ffffff),
      );
    }
  }

  @override
  bool shouldRepaint(_Cover old) => old.seed != seed;
}
