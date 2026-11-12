import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'companion_motion.dart';

/// The paired poses preserve the startup artwork's left-record/right-earbud
/// shoulder contact. One decoded atlas keeps pose changes independent of video,
/// authentication and playback; speech and finger accents remain vector layers.
class BetaCompanionStage extends StatefulWidget {
  const BetaCompanionStage({required this.height, super.key});
  final double height;
  @override
  State<BetaCompanionStage> createState() => _BetaCompanionStageState();
}

class _BetaCompanionStageState extends State<BetaCompanionStage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = CompanionMotion(this);
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _image;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream == null) {
      _stream = const AssetImage(
        'assets/branding/welcome/companions-atlas.webp',
      ).resolve(createLocalImageConfiguration(context));
      _listener = ImageStreamListener((info, _) {
        if (!mounted) {
          info.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = info;
        });
      });
      _stream!.addListener(_listener!);
    }
    _updateMotion();
  }

  void _updateMotion() {
    final active =
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    _motion.setActive(active);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) _updateMotion();
  }

  void _greet() {
    if (!MediaQuery.disableAnimationsOf(context) && _foreground) {
      _motion.greet();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_listener != null) _stream?.removeListener(_listener!);
    _image?.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '黑胶唱片与耳机伙伴搭肩说 hi，轻点打招呼',
    button: true,
    onTap: _greet,
    child: GestureDetector(
      onTap: _greet,
      behavior: HitTestBehavior.opaque,
      child: RepaintBoundary(
        child: SizedBox(
          key: const ValueKey('beta21-companions-stage'),
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _CompanionAtlasPainter(
              _image?.image,
              _motion,
              Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        ),
      ),
    ),
  );
}

class _CompanionAtlasPainter extends CustomPainter {
  _CompanionAtlasPainter(this.atlas, this.motion, this.dark)
    : super(repaint: motion);
  final ui.Image? atlas;
  final CompanionMotion motion;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    // These coordinates belong to one composition, so responsive scaling never
    // moves the friends apart or detaches the earbud's hand from the record.
    final scale = math.min(size.width / 360, size.height / 320);
    canvas.save();
    canvas.translate(
      (size.width - 360 * scale) / 2,
      (size.height - 320 * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawOval(
      const Rect.fromLTWH(42, 300, 286, 12),
      Paint()
        ..color = (dark ? Colors.white : const Color(0xFF81584A)).withValues(
          alpha: .09,
        ),
    );
    final seconds = motion.seconds;
    final greeting = motion.greeting;
    final hello = motion.hello;
    final phase = seconds % 6;
    final wave = greeting || (phase > .3 && phase < 1.9);
    final blink = phase > 3.8 && phase < 3.94;
    final gestureTime = greeting ? hello * 1.8 : phase - .3;
    final bounce = math.sin(gestureTime * math.pi * 3.2);
    final lift = wave ? math.max(0.0, bounce) * 5 : 0.0;
    canvas.save();
    canvas.translate(180, 306 - lift);
    canvas.rotate(wave ? bounce * .012 : 0);
    canvas.translate(-180, -306);
    void pose(int frame, double opacity) {
      final image = atlas;
      if (image == null || opacity <= 0) return;
      final cell = Size(image.width / 2, image.height / 2);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          (frame % 2) * cell.width,
          (frame ~/ 2) * cell.height,
          cell.width,
          cell.height,
        ),
        const Rect.fromLTWH(15, -6, 330, 330),
        Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..filterQuality = FilterQuality.medium,
      );
    }

    if (wave) {
      // The earbud nod changes its silhouette, so each beat paints one clean
      // pose. The shared canvas bounce supplies continuous motion while the
      // hand/face animation keeps the reference's shoulder contact intact.
      pose(2 + ((gestureTime * 4).floor() % 2), 1);
    } else {
      pose(blink ? 1 : 0, 1);
    }
    _greetingBubble(canvas, wave ? bounce : 0);
    _fingerAccents(canvas, wave ? bounce : 0);
    canvas.restore();
    canvas.restore();
  }

  /// Default-visible lowercase lettering follows the supplied playful bubble.
  /// Rounded strokes avoid platform font substitution changing this brand cue.
  void _greetingBubble(Canvas canvas, double beat) {
    canvas.save();
    canvas.translate(143, 96 - beat * 3);
    canvas.rotate(-.22 + beat * .04);
    canvas.scale(1 + math.max(0.0, beat) * .07);
    final tail = Path()
      ..moveTo(-7, 19)
      ..quadraticBezierTo(-7, 27, -15, 32)
      ..quadraticBezierTo(0, 31, 8, 19)
      ..close();
    final bubblePaint = Paint()..color = const Color(0xFF30282B);
    canvas.drawPath(tail, bubblePaint);
    canvas.drawOval(const Rect.fromLTWH(-30, -25, 60, 50), bubblePaint);
    final ink = Paint()
      ..color = const Color(0xFFFFF3DF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7.5;
    canvas.drawPath(
      Path()
        ..moveTo(-14, -12)
        ..lineTo(-14, 11)
        ..moveTo(-14, 0)
        ..cubicTo(-13, -10, 0, -8, 0, 2)
        ..lineTo(0, 11)
        ..moveTo(13, 0)
        ..lineTo(13, 11),
      ink,
    );
    canvas.drawCircle(
      const Offset(13, -12),
      4.3,
      ink..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  /// Cream three-line greeting accent, with a restrained edge for visibility
  /// on both the original light welcome ground and the dark appearance.
  void _fingerAccents(Canvas canvas, double beat) {
    canvas.save();
    canvas.translate(67, 149 - beat * 2);
    canvas.scale(1 + math.max(0.0, beat) * .12);
    final lines = Path()
      ..moveTo(-10, -1)
      ..lineTo(-17, -11)
      ..moveTo(0, -5)
      ..lineTo(1, -18)
      ..moveTo(10, -2)
      ..lineTo(19, -12);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.8
      ..color = const Color(0xFF674F43).withValues(alpha: dark ? .2 : .5);
    canvas.drawPath(lines, stroke);
    canvas.drawPath(
      lines,
      stroke
        ..strokeWidth = 2.8
        ..color = const Color(0xFFFFF3DF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompanionAtlasPainter old) =>
      old.atlas != atlas || old.motion != motion || old.dark != dark;
}
