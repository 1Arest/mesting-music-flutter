import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'vinyl_disc.dart';

/// Normalized stage geometry keeps the stylus on the grooves, outside the label.
class ClassicRecordGeometry {
  const ClassicRecordGeometry(this.side);
  final double side;
  Rect get record =>
      Rect.fromLTWH(side * .05, side * .21, side * .90, side * .90);
  double get height => side * 1.14;
  Offset get pivot => Offset(side * .52, side * .014);
  Offset get stylus => Offset(side * .83, side * .43);
}

/// A taller stage reserves air above the record for the articulated
/// metal arm. The arm is stationary while the existing record surface rotates.
class ClassicRecordStage extends StatelessWidget {
  const ClassicRecordStage({
    required this.coverAsset,
    required this.playing,
    super.key,
  });
  final String coverAsset;
  final bool playing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final side = math.min(bounds.maxWidth, bounds.maxHeight / 1.14);
      final geometry = ClassicRecordGeometry(side);
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return Center(
        child: SizedBox(
          width: side,
          height: geometry.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: geometry.record.inflate(side * .018),
                child: DecoratedBox(
                  key: const ValueKey('classic-record-halo'),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .025),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .065),
                      width: 1,
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: geometry.record,
                child: VinylDisc(
                  key: const ValueKey('classic-record-disc'),
                  coverAsset: coverAsset,
                  playing: playing && !reduceMotion,
                  labelSizeFactor: .62,
                  rotationDuration: const Duration(seconds: 24),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: playing ? 0 : -.34),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 480),
                    curve: Curves.easeInOutCubic,
                    builder: (_, angle, _) => RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('classic-record-tonearm'),
                        painter: ClassicTonearmPainter(angle),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ClassicTonearmPainter extends CustomPainter {
  const ClassicTonearmPainter(this.angle);
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide;
    final geometry = ClassicRecordGeometry(w);
    final pivot = geometry.pivot;
    canvas.drawCircle(
      pivot + Offset(0, w * .004),
      w * .042,
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawCircle(
      pivot,
      w * .035,
      Paint()..color = const Color(0x33FFFFFF),
    );
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    canvas.translate(-pivot.dx, -pivot.dy);

    final arm = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..lineTo(w * .573, w * .223)
      ..quadraticBezierTo(w * .582, w * .258, w * .611, w * .279)
      ..lineTo(w * .799, w * .409);
    canvas.drawPath(
      arm.shift(Offset(w * .005, w * .009)),
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .024
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      arm,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F5F5), Color(0xFFB8BFC4), Color(0xFFE8EAEC)],
        ).createShader(Rect.fromLTWH(w * .5, 0, w * .35, w * .45))
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .017
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      arm.shift(Offset(-w * .002, 0)),
      Paint()
        ..color = const Color(0xAAFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .004
        ..strokeCap = StrokeCap.round,
    );

    canvas.save();
    canvas.translate(w * .799, w * .409);
    canvas.rotate(.605);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-w * .018, -w * .014, w * .036, w * .028),
        Radius.circular(w * .004),
      ),
      Paint()..color = const Color(0xFFBCC2C6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .005, -w * .024, w * .064, w * .048),
        Radius.circular(w * .007),
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFF1F2F3), Color(0xFFD0D4D7)],
        ).createShader(Rect.fromLTWH(0, -w * .024, w * .07, w * .048)),
    );
    for (final y in [-.009, .009]) {
      canvas.drawLine(
        Offset(w * .019, w * y),
        Offset(w * .051, w * y),
        Paint()
          ..color = const Color(0xFFADB5BC)
          ..strokeWidth = w * .003,
      );
    }
    canvas.restore();
    canvas.restore();

    // The pivot cap stays fixed as the arm lifts away from the record.
    canvas.drawCircle(
      pivot,
      w * .024,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0xFFBBC2C7)],
        ).createShader(Rect.fromCircle(center: pivot, radius: w * .024)),
    );
    canvas.drawCircle(
      pivot,
      w * .009,
      Paint()..color = const Color(0xFF909AA3),
    );
  }

  @override
  bool shouldRepaint(ClassicTonearmPainter oldDelegate) =>
      oldDelegate.angle != angle;
}
