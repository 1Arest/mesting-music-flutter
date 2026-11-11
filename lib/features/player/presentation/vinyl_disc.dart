import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../shared/widgets/artwork_image.dart';

const vinylDefaultArtworkFactor = .60;

class VinylDisc extends StatefulWidget {
  const VinylDisc({
    required this.coverAsset,
    required this.playing,
    this.labelSizeFactor = vinylDefaultArtworkFactor,
    this.rotationDuration = const Duration(seconds: 18),
    this.rotationCount,
    super.key,
  });

  final String coverAsset;
  final bool playing;
  final double labelSizeFactor;
  final Duration rotationDuration;
  final int? rotationCount;

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.rotationDuration,
    );
    if (widget.playing) _startRotation();
  }

  @override
  void didUpdateWidget(covariant VinylDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rotationDuration != oldWidget.rotationDuration) {
      _controller.duration = widget.rotationDuration;
    }
    if (widget.playing == oldWidget.playing &&
        widget.rotationCount == oldWidget.rotationCount &&
        widget.rotationDuration == oldWidget.rotationDuration) {
      return;
    }
    if (widget.playing) {
      _startRotation();
    } else {
      _controller.stop();
    }
  }

  void _startRotation() {
    _controller.repeat(count: widget.rotationCount);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VinylDiscSurface(
      coverAsset: widget.coverAsset,
      labelSizeFactor: widget.labelSizeFactor,
      turns: _controller,
    );
  }
}

class VinylDiscSurface extends StatelessWidget {
  const VinylDiscSurface({
    required this.coverAsset,
    this.labelSizeFactor = vinylDefaultArtworkFactor,
    this.turns = const AlwaysStoppedAnimation(0),
    super.key,
  });

  final String coverAsset;
  final double labelSizeFactor;
  final Animation<double> turns;

  @override
  Widget build(BuildContext context) {
    // Classic's tonearm reserves vertical space inside a square stage. Loosen
    // that rectangular constraint before enforcing 1:1, including the label;
    // BoxShape.circle alone only fixes the grooves, not a stretched ClipOval.
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    stops: [0, .84, .975, 1],
                    colors: [
                      Color(0xFF171719),
                      Color(0xFF0B0B0D),
                      Color(0xFF1A1B1D),
                      Color(0xFF101012),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 24,
                      spreadRadius: 0,
                      offset: Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Color(0x332D2D31),
                      blurRadius: 12,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: RotationTransition(
                turns: turns,
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        stops: [0, .31, .315, .58, .82, 1],
                        colors: [
                          Color(0xFF111113),
                          Color(0xFF09090B),
                          Color(0xFF1B1B1E),
                          Color(0xFF101012),
                          Color(0xFF08080A),
                          Color(0xFF151518),
                        ],
                      ),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: labelSizeFactor.clamp(.35, .66),
                      heightFactor: labelSizeFactor.clamp(.35, .66),
                      child: ClipOval(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.black.withValues(alpha: .72),
                              width: 2.5,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.expand(
                            child: ArtworkImage(
                              uri: coverAsset,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _VinylGroovePainter(labelSizeFactor.clamp(.35, .66)),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) => DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF343438).withValues(alpha: .76),
                        width: constraints.maxWidth * .007,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VinylGroovePainter extends CustomPainter {
  const _VinylGroovePainter(this.labelFactor);
  final double labelFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .55;
    // Highlights remain above the rotating surface, like light on real vinyl.
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: radius * .985))
      ..addOval(
        Rect.fromCircle(center: center, radius: radius * (labelFactor + .025)),
      );
    canvas.save();
    canvas.clipPath(ring);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          transform: const GradientRotation(-math.pi / 4),
          colors: const [
            Color(0x0217181B),
            Color(0x245D6269),
            Color(0x0017181B),
            Color(0x0017181B),
            Color(0x185D6269),
            Color(0x0017181B),
            Color(0x0217181B),
          ],
          stops: const [0, .14, .28, .48, .64, .78, 1],
        ).createShader(Offset.zero & size),
    );
    final start = labelFactor + .035;
    for (var index = 0; index < 66; index++) {
      groove.color = index % 5 == 0
          ? const Color(0x18FFFFFF)
          : const Color(0x09FFFFFF);
      canvas.drawCircle(
        center,
        radius * (start + index * (.97 - start) / 65),
        groove,
      );
    }
    canvas.restore();
    canvas.drawCircle(
      center,
      radius * (labelFactor + .009),
      Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .017,
    );
  }

  @override
  bool shouldRepaint(covariant _VinylGroovePainter oldDelegate) =>
      oldDelegate.labelFactor != labelFactor;
}
