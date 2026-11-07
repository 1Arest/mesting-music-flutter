import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/player_visual_style.dart';

/// Five bounded live drawings use one local repaint clock. They preview the
/// real stage vocabulary without five audio owners or full-screen shaders.
class BetaPlayerStylePreviews extends ConsumerStatefulWidget {
  const BetaPlayerStylePreviews({super.key});
  @override
  ConsumerState<BetaPlayerStylePreviews> createState() =>
      _BetaPlayerStylePreviewsState();
}

class _BetaPlayerStylePreviewsState
    extends ConsumerState<BetaPlayerStylePreviews>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(playerVisualStyleProvider);
    final ink = Theme.of(context).colorScheme.onSurface;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = (bounds.maxWidth - 20) / 3;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final style in PlayerVisualStyle.values)
              Semantics(
                button: true,
                selected: selected == style,
                label: style.displayName,
                child: InkWell(
                  key: ValueKey('guide-style-${style.id}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => ref
                      .read(playerVisualStyleProvider.notifier)
                      .select(style),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: width,
                    padding: const EdgeInsets.fromLTRB(7, 8, 7, 10),
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: .035),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        width: selected == style ? 1.8 : 1,
                        color: selected == style
                            ? Theme.of(context).colorScheme.primary
                            : ink.withValues(alpha: .16),
                      ),
                    ),
                    child: Column(
                      children: [
                        RepaintBoundary(
                          child: CustomPaint(
                            size: Size(width - 14, 82),
                            painter: _StylePainter(style, _phase, reduced),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          style.displayName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.25,
                            color: ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Icon(
                          selected == style
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 15,
                          color: selected == style
                              ? Theme.of(context).colorScheme.primary
                              : ink.withValues(alpha: .25),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StylePainter extends CustomPainter {
  _StylePainter(this.style, this.phase, this.reduced)
    : super(repaint: reduced ? null : phase);
  final PlayerVisualStyle style;
  final Animation<double> phase;
  final bool reduced;
  @override
  void paint(Canvas c, Size s) {
    final p = reduced ? .2 : phase.value;
    c.save();
    c.translate(s.width / 2, s.height / 2);
    final r = math.min(s.width, s.height) * .42;
    final pen = Paint()..isAntiAlias = true;
    switch (style) {
      case PlayerVisualStyle.cover:
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: r * 1.9,
          height: r * 1.9,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(10)),
          pen
            ..shader = const LinearGradient(
              colors: [Color(0xFFD75E63), Color(0xFF784344)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(rect),
        );
        pen.shader = null;
        c.drawCircle(
          Offset(math.sin(p * math.pi * 2) * r * .18, -r * .1),
          r * .45,
          pen..color = const Color(0xFFF2D5BA),
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-r * .65, r * .58, r * 1.3, 3),
            const Radius.circular(3),
          ),
          pen..color = Colors.white70,
        );
      case PlayerVisualStyle.classic:
      case PlayerVisualStyle.aurora:
        c.drawCircle(Offset.zero, r, pen..color = const Color(0xFF29292D));
        for (final v in [.6, .75, .9]) {
          c.drawCircle(
            Offset.zero,
            r * v,
            pen
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = Colors.white12,
          );
        }
        pen.style = PaintingStyle.fill;
        c.drawCircle(
          Offset.zero,
          r * .36,
          pen..color = const Color(0xFFDE5757),
        );
        c.save();
        c.rotate(p * math.pi * 8);
        c.drawCircle(Offset(r * .2, 0), 2, pen..color = Colors.white);
        c.restore();
        if (style == PlayerVisualStyle.classic) {
          c.drawPath(
            Path()
              ..moveTo(r * .8, -r * .9)
              ..lineTo(r * .8, -r * .1)
              ..lineTo(r * .28, r * .33),
            pen
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 3
              ..color = const Color(0xFFF2F2F7),
          );
        } else {
          c.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: r * 1.13),
            p * math.pi * 2,
            math.pi * 1.2,
            false,
            pen
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = const Color(0xFF6BDCF5),
          );
        }
      case PlayerVisualStyle.cassette:
        for (var ring = 0; ring < 3; ring++) {
          for (var i = 0; i < 12; i++) {
            final a = i * math.pi / 6 + p * math.pi * (ring.isEven ? 2 : -2);
            final d = r * (.4 + ring * .3);
            c.drawCircle(
              Offset(math.cos(a) * d, math.sin(a) * d),
              2 + math.sin(a + p * 8),
              pen
                ..style = PaintingStyle.fill
                ..color = const Color(
                  0xFFA78BFA,
                ).withValues(alpha: .4 + ring * .25),
            );
          }
        }
        c.drawCircle(
          Offset.zero,
          r * .23,
          pen..color = const Color(0xFF6BDCF5),
        );
      case PlayerVisualStyle.lyricStage:
        for (var i = 0; i < 12; i++) {
          final h =
              r * (.25 + .75 * (math.sin(i * .8 + p * math.pi * 8) + 1) / 2);
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(-r + i * r / 6, -h / 2, r / 10, h),
              const Radius.circular(3),
            ),
            pen
              ..style = PaintingStyle.fill
              ..color = Color.lerp(
                const Color(0xFF5EEAD4),
                const Color(0xFF6BDCF5),
                i / 12,
              )!,
          );
        }
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_StylePainter old) =>
      old.style != style || old.reduced != reduced;
}
