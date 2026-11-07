import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/shinchan_progress_weather.dart';
export '../domain/shinchan_progress_weather.dart';

ShinchanProgressWeather shinchanWeatherForPreset(String presetId) =>
    switch (presetId) {
      'kasukabe-sky' || 'motion-walk' => ShinchanProgressWeather.sun,
      'family-picnic' || 'crayon-room' => ShinchanProgressWeather.breeze,
      'sunset-road' => ShinchanProgressWeather.sunset,
      'starry-radio' || 'midnight-cinema' => ShinchanProgressWeather.night,
      'rainy-day' => ShinchanProgressWeather.drizzle,
      'motion-rain' => ShinchanProgressWeather.storm,
      'motion-parade' => ShinchanProgressWeather.parade,
      _ => ShinchanProgressWeather.breeze,
    };

class ShinchanProgressWalker extends StatefulWidget {
  const ShinchanProgressWalker({
    required this.presetId,
    required this.playing,
    this.weather,
    this.width = 104,
    super.key,
  });

  final String presetId;
  final bool playing;

  /// Null preserves the formal channel's original theme-to-weather mapping.
  final ShinchanProgressWeather? weather;
  final double width;

  static Size sizeForWidth(double width) => Size(width, 84 * width / 104);

  @override
  State<ShinchanProgressWalker> createState() => _ShinchanProgressWalkerState();
}

class _ShinchanProgressWalkerState extends State<ShinchanProgressWalker>
    with TickerProviderStateMixin {
  static const _shinchanFrames = <String>[
    'assets/images/theme_gallery/progress-shinchan-walk-stride.png',
    'assets/images/theme_gallery/progress-shinchan-walk-mid.png',
    'assets/images/theme_gallery/progress-shinchan-walk-pass.png',
  ];
  static const _shiroFrames = <String>[
    'assets/images/theme_gallery/progress-shiro-walk-stride.png',
    'assets/images/theme_gallery/progress-shiro-walk-mid.png',
    'assets/images/theme_gallery/progress-shiro-walk-pass.png',
  ];
  // Original 502 x 283 PNG frames include transparent pixels below the feet.
  // Compensate in layout, so changing player size never makes either character
  // float above the rail. Frame-specific padding preserves the walking gait.
  static const _shinchanBottomPadding = [28.0, 28.0, 29.0];
  static const _shiroBottomPadding = [55.0, 50.0, 54.0];

  late final AnimationController _walkController;
  late final AnimationController _weatherController;
  late final AnimationController _cloudController;
  late final AnimationController _rainController;
  bool _assetsPrecached = false;
  bool _motionAllowed = false;
  ScrollableState? _scrollable;
  ScrollPosition? _scrollPosition;
  bool _viewportVisible = true;
  bool _visibilityCheckScheduled = false;

  ShinchanProgressWeather get _weather =>
      widget.weather ?? shinchanWeatherForPreset(widget.presetId);

  @override
  void initState() {
    super.initState();
    _walkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _weatherController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5400),
    );
    _cloudController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _rainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionAllowed =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    _scrollable = Scrollable.maybeOf(context);
    final position = _scrollable?.position;
    if (!identical(position, _scrollPosition)) {
      _scrollPosition?.removeListener(_scheduleVisibilityCheck);
      _scrollPosition = position;
      _scrollPosition?.addListener(_scheduleVisibilityCheck);
    }
    _scheduleVisibilityCheck();
    _syncMotion();
    if (_assetsPrecached) return;
    _assetsPrecached = true;
    for (final asset in [..._shinchanFrames, ..._shiroFrames]) {
      precacheImage(AssetImage(asset), context);
    }
  }

  @override
  void didUpdateWidget(covariant ShinchanProgressWalker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing ||
        oldWidget.presetId != widget.presetId ||
        oldWidget.weather != widget.weather) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    if (widget.playing && _motionAllowed && _viewportVisible) {
      _walkController.repeat();
      _weatherController.repeat();
      if (_weather == ShinchanProgressWeather.storm) {
        _cloudController.repeat();
        _rainController.repeat();
      } else {
        _cloudController
          ..stop()
          ..value = 0;
        _rainController
          ..stop()
          ..value = 0;
      }
    } else {
      _walkController
        ..stop()
        ..value = 0;
      _weatherController
        ..stop()
        ..value = 0;
      _cloudController
        ..stop()
        ..value = 0;
      _rainController
        ..stop()
        ..value = 0;
    }
  }

  /// Slivers may keep an offscreen preview alive inside their cache extent.
  /// TickerMode alone cannot see that. Coalesce scroll notifications and test
  /// the real painted bounds after layout; no settings-page rebuild is needed.
  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      final viewport = _scrollable?.context.findRenderObject();
      var visible = true;
      if (box is RenderBox &&
          box.hasSize &&
          viewport is RenderBox &&
          viewport.hasSize) {
        final bounds = box.localToGlobal(Offset.zero) & box.size;
        final viewportBounds =
            viewport.localToGlobal(Offset.zero) & viewport.size;
        visible = bounds.overlaps(viewportBounds);
      }
      if (visible != _viewportVisible) {
        _viewportVisible = visible;
        _syncMotion();
      }
    });
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_scheduleVisibilityCheck);
    _walkController.dispose();
    _weatherController.dispose();
    _cloudController.dispose();
    _rainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.width / 104;
    return SizedBox(
      width: widget.width,
      height: ShinchanProgressWalker.sizeForWidth(widget.width).height,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _walkController,
          _weatherController,
          _cloudController,
          _rainController,
        ]),
        builder: (context, _) {
          final frame = widget.playing
              ? (_walkController.value * 3).floor().clamp(0, 2)
              : 0;
          final cadence = widget.playing
              ? -1.3 * math.sin(_walkController.value * math.pi * 2).abs()
              : 0.0;
          final weather = _weather;
          final storm = weather == ShinchanProgressWeather.storm;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 38 * scale,
                top: (storm ? -8 : 0) * scale,
                width: (storm ? 36.5 : 43) * scale,
                height: (storm ? 41.6 : 43) * scale,
                child: CustomPaint(
                  painter: _WeatherPainter(
                    weather: weather,
                    progress: _weatherController.value,
                    cloudProgress: _cloudController.value,
                    rainProgress: _rainController.value,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: -_shinchanBottomPadding[frame] * widget.width / 502,
                width: widget.width,
                height: 59 * scale,
                child: Transform.translate(
                  offset: Offset(0, cadence * scale),
                  child: Image.asset(
                    _shinchanFrames[frame],
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned(
                right: 20 * scale,
                bottom: -_shiroBottomPadding[frame] * 54 * scale / 502,
                width: 54 * scale,
                height: 36 * scale,
                child: Transform.translate(
                  offset: Offset(0, cadence * scale),
                  child: Image.asset(
                    _shiroFrames[frame],
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  const _WeatherPainter({
    required this.weather,
    required this.progress,
    required this.cloudProgress,
    required this.rainProgress,
  });

  final ShinchanProgressWeather weather;
  final double progress;
  final double cloudProgress;
  final double rainProgress;

  @override
  void paint(Canvas canvas, Size size) {
    switch (weather) {
      case ShinchanProgressWeather.sun:
        _paintSun(canvas, size, sunset: false);
      case ShinchanProgressWeather.sunset:
        _paintSun(canvas, size, sunset: true);
      case ShinchanProgressWeather.breeze:
        _paintBreeze(canvas, size);
      case ShinchanProgressWeather.night:
        _paintNight(canvas, size);
      case ShinchanProgressWeather.drizzle:
        _paintRain(canvas, size, storm: false);
      case ShinchanProgressWeather.storm:
        _paintRain(canvas, size, storm: true);
      case ShinchanProgressWeather.parade:
        _paintParade(canvas, size);
    }
  }

  void _paintSun(Canvas canvas, Size size, {required bool sunset}) {
    final pulse = 1 + math.sin(progress * math.pi * 4) * .05;
    final center = Offset(size.width * .48, size.height * .46);
    final radius = size.shortestSide * .22 * pulse;
    final rayPaint = Paint()
      ..color = sunset ? const Color(0xB8D18B22) : const Color(0xB8F2AE30)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 12; index++) {
      final angle = index * math.pi / 6 + progress * math.pi * .25;
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 3),
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 7),
        rayPaint,
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.35),
          colors: sunset
              ? const [Color(0xFFFFF2BD), Color(0xFFF1A24B), Color(0xFFD18B22)]
              : const [Color(0xFFFFF8B9), Color(0xFFFFD760), Color(0xFFF1AD36)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    _paintLeaf(
      canvas,
      Offset(size.width * .78, size.height * .72),
      const Color(0xFF78AD58),
      progress * math.pi * 2,
    );
  }

  void _paintBreeze(Canvas canvas, Size size) {
    final note = TextPainter(
      text: const TextSpan(
        text: '♪',
        style: TextStyle(
          color: Color(0xFFD18B22),
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    note.paint(
      canvas,
      Offset(size.width * .34, 1 + math.sin(progress * math.pi * 4) * 2),
    );
    final drift = math.sin(progress * math.pi * 2) * 3;
    _paintLeaf(
      canvas,
      Offset(6 + drift, size.height * .58),
      const Color(0xFF72AC63),
      -.3,
    );
    _paintLeaf(
      canvas,
      Offset(size.width * .65 - drift, size.height * .72),
      const Color(0xFFE8B64C),
      .45,
    );
    _paintLeaf(
      canvas,
      Offset(size.width * .82 + drift, size.height * .30),
      const Color(0xFFD9A04E),
      -.55,
    );
  }

  void _paintNight(Canvas canvas, Size size) {
    final center = Offset(size.width * .48, size.height * .44);
    canvas.drawCircle(
      center,
      size.shortestSide * .24,
      Paint()..color = const Color(0xFFF4DFA0),
    );
    canvas.drawCircle(
      center + Offset(size.width * .12, -size.height * .08),
      size.shortestSide * .24,
      Paint()..color = const Color(0xFF31425C),
    );
    final glow = .45 + .55 * math.sin(progress * math.pi * 8).abs();
    final starPaint = Paint()
      ..color = const Color(0xFFFFF4B5).withValues(alpha: glow);
    for (final point in <Offset>[
      Offset(size.width * .07, size.height * .20),
      Offset(size.width * .76, size.height * .13),
      Offset(size.width * .81, size.height * .72),
    ]) {
      canvas.drawCircle(point, 1.7, starPaint);
    }
  }

  void _paintRain(Canvas canvas, Size size, {required bool storm}) {
    if (storm) {
      _paintOriginalStorm(canvas, size);
      return;
    }
    final rain = Paint()
      ..color = const Color(0xFF54A9D1)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    const top = 2.0;
    for (var index = 0; index < 4; index++) {
      final phase = (progress * 5 + index * .23) % 1;
      final x = size.width * (.18 + index * .21) - phase * 2;
      final y = top + phase * (size.height - top - 4);
      canvas.drawLine(Offset(x, y), Offset(x - 2, y + 7), rain);
    }
  }

  void _paintOriginalStorm(Canvas canvas, Size size) {
    canvas.save();
    final stageScale = size.width / 50;
    canvas.scale(stageScale, stageScale);
    // CSS 伪元素会伸出天气盒子上缘 11px；下移绘制区并同步上移组件，
    // 保持原位置的同时避免 Flutter 裁掉云朵顶部。
    canvas.translate(0, 11);

    // 与原项目一致：整组天气上下漂浮 2px，并在 -1°～1° 间摆动。
    final drift = (1 - math.cos(cloudProgress * math.pi * 2)) / 2;
    canvas.translate(25, 46);
    canvas.rotate((-1 + drift * 2) * math.pi / 180);
    canvas.translate(-25, -46 - drift * 2);

    final flashing = _lightningVisible(progress);
    final cloudBase = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 2, 42, 15),
          const Radius.circular(999),
        ),
      );
    final cloudWithLeft = Path.combine(
      PathOperation.union,
      cloudBase,
      Path()..addOval(const Rect.fromLTWH(11, -5, 19, 19)),
    );
    final cloud = Path.combine(
      PathOperation.union,
      cloudWithLeft,
      Path()..addOval(const Rect.fromLTWH(16, -11, 25, 25)),
    );

    if (flashing) {
      canvas.drawPath(
        cloud,
        Paint()
          ..color = const Color(0x80FFE075)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawPath(
      cloud.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0x57232D3D)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      cloud,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: flashing
              ? const [Color(0xFFA9B4C1), Color(0xFF66758A)]
              : const [Color(0xFF6F7D91), Color(0xFF435166)],
        ).createShader(const Rect.fromLTWH(4, -11, 42, 28)),
    );

    // 原项目的三颗雨滴：0.72 秒循环，彼此错开 0.24 秒。
    for (var index = 0; index < 3; index++) {
      final phase = (rainProgress + index / 3) % 1;
      final opacity = switch (phase) {
        < .18 => phase / .18 * .90,
        < .82 => .90 - (phase - .18) / .64 * .18,
        _ => .72 * (1 - (phase - .82) / .18),
      };
      final dropY = -2 + phase * 10;
      canvas.save();
      canvas.translate(10 + index * 8, 20 + dropY);
      canvas.rotate(12 * math.pi / 180);
      final dropRect = const Rect.fromLTWH(-1, 0, 2, 9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          dropRect.shift(const Offset(0, 1)),
          const Radius.circular(2),
        ),
        Paint()
          ..color = const Color(0x42269CD7).withValues(alpha: .26 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(dropRect, const Radius.circular(2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF54BEF0).withValues(alpha: .45 * opacity),
              const Color(0xFF269CD7).withValues(alpha: opacity),
            ],
          ).createShader(dropRect),
      );
      canvas.restore();
    }

    _paintLightningBolt(canvas, phase: progress, secondary: false);
    _paintLightningBolt(
      canvas,
      phase: (progress - 0.12 / 5.4) % 1,
      secondary: true,
    );
    canvas.restore();
  }

  bool _lightningVisible(double phase) =>
      (phase >= .64 && phase < .67) || (phase >= .685 && phase < .70);

  void _paintLightningBolt(
    Canvas canvas, {
    required double phase,
    required bool secondary,
  }) {
    if (!_lightningVisible(phase)) return;
    final width = secondary ? 6.0 : 8.0;
    final height = secondary ? 13.0 : 17.0;
    canvas.save();
    canvas.translate(secondary ? 33 : 22, secondary ? 21 : 19);
    canvas.rotate((secondary ? -8 : 7) * math.pi / 180);
    canvas.scale(secondary ? .82 : .88);
    final bolt = Path()
      ..moveTo(width * .47, 0)
      ..lineTo(width, 0)
      ..lineTo(width * .68, height * .42)
      ..lineTo(width, height * .42)
      ..lineTo(width * .25, height)
      ..lineTo(width * .42, height * .57)
      ..lineTo(width * .08, height * .57)
      ..close();
    canvas.drawPath(
      bolt,
      Paint()
        ..color = const Color(0xC7FFD349)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    canvas.drawPath(
      bolt,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF4A3), Color(0xFFFFD24D), Color(0xFFF2A31D)],
          stops: [0, .58, 1],
        ).createShader(Rect.fromLTWH(0, 0, width, height)),
    );
    canvas.restore();
  }

  void _paintParade(Canvas canvas, Size size) {
    const colors = <Color>[
      Color(0xFF2E9B82),
      Color(0xFFF2B943),
      Color(0xFF56A9CA),
      Color(0xFF71B879),
      Color(0xFF8068D8),
    ];
    for (var index = 0; index < colors.length; index++) {
      final phase = (progress * 3 + index * .19) % 1;
      final x = size.width * (.12 + index * .18);
      final y = -5 + phase * (size.height + 5);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(phase * math.pi * 2 + index);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2, -4, 4, 8),
          const Radius.circular(1.5),
        ),
        Paint()..color = colors[index],
      );
      canvas.restore();
    }
  }

  void _paintLeaf(Canvas canvas, Offset center, Color color, double rotation) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final path = Path()
      ..moveTo(-6, 0)
      ..quadraticBezierTo(0, -5, 7, 0)
      ..quadraticBezierTo(0, 5, -6, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter oldDelegate) =>
      oldDelegate.weather != weather ||
      oldDelegate.progress != progress ||
      oldDelegate.cloudProgress != cloudProgress ||
      oldDelegate.rainProgress != rainProgress;
}
