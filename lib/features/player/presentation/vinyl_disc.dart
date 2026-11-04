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
                    stops: [0, .88, .945, 1],
                    colors: [
                      Color(0xFF171719),
                      Color(0xFF0B0B0D),
                      Color(0xFF252529),
                      Color(0xFF101012),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 34,
                      spreadRadius: 2,
                      offset: Offset(0, 18),
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
                child: CustomPaint(painter: _VinylGroovePainter()),
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
                        width: constraints.maxWidth * .025,
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
  const _VinylGroovePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .55;
    for (var index = 0; index < 48; index++) {
      groove.color = index % 4 == 0
          ? Colors.white.withValues(alpha: .075)
          : Colors.white.withValues(alpha: .032);
      canvas.drawCircle(center, radius * (.31 + index * .0131), groove);
    }
  }

  @override
  bool shouldRepaint(covariant _VinylGroovePainter oldDelegate) => false;
}
