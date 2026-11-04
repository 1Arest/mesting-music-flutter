// Copyright (c) 2023. Compose Cupertino project and open source contributors.
// Licensed under the Apache License, Version 2.0; see
// third_party/audio_glyphs/LICENSE-COMPOSE-CUPERTINO.txt and NOTICE.md.
// Generated from the pinned airpodspro.svg without changing its path geometry.
// Original symbol copyright remains with its respective owner.
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The exact AirPods Pro silhouette; preserves the source's wide aspect ratio.
/// Native output metadata still supplies the real device name independently.
void paintAirPodsProGlyph(Canvas canvas, Size size, Color color) {
  const width = 32.168, height = 20.7313;
  final scale = math.min(size.width / width, size.height / height);
  canvas.save();
  canvas.translate(
    (size.width - width * scale) / 2,
    (size.height - height * scale) / 2,
  );
  canvas.scale(scale);
  final pen = Paint()
    ..isAntiAlias = true
    ..color = color;
  for (final path in _paths) {
    canvas.drawPath(path, pen);
  }
  canvas.restore();
}

// Generated once rather than parsing SVG or allocating paths per frame.
final _paths = <Path>[
  Path()
    ..moveTo(10.582, 0.000408646)
    ..cubicTo(8.57812, -0.0230289, 6.33984, 0.961346, 4.85156, 3.04728)
    ..cubicTo(4.62891, 3.32853, 4.42969, 3.64494, 4.21875, 4.11369)
    ..cubicTo(6.76172, 4.57072, 8.82422, 6.82072, 8.82422, 9.32853)
    ..cubicTo(8.82422, 10.0434, 8.68359, 10.6996, 8.4375, 11.2856)
    ..cubicTo(9.98438, 11.0629, 10.9453, 10.7113, 11.8242, 10.2192)
    ..cubicTo(13.7578, 9.10588, 15.2812, 7.30119, 15.2812, 4.71135)
    ..cubicTo(15.2812, 1.72306, 13.1719, 0.0238461, 10.582, 0.000408646)
    ..close()
    ..moveTo(11.0391, 5.02775)
    ..cubicTo(10.8047, 5.22697, 10.4414, 5.20353, 10.2422, 4.95744)
    ..cubicTo(10.043, 4.71135, 10.0781, 4.35978, 10.3242, 4.16056)
    ..lineTo(12.0469, 2.70744)
    ..cubicTo(12.2812, 2.50822, 12.6328, 2.54338, 12.8203, 2.78947)
    ..cubicTo(13.0312, 3.02385, 13.0195, 3.37541, 12.7734, 3.57463)
    ..close()
    ..moveTo(8.89453, 20.7309)
    ..lineTo(9.82031, 20.7309)
    ..cubicTo(10.5352, 20.7309, 11.0156, 20.3559, 11.0156, 19.6293)
    ..lineTo(11.0156, 11.9067)
    ..cubicTo(10.0195, 12.2699, 8.90625, 12.4926, 7.6875, 12.5746)
    ..lineTo(7.6875, 19.6293)
    ..cubicTo(7.6875, 20.3559, 8.16797, 20.7309, 8.89453, 20.7309)
    ..close()
    ..moveTo(21.5742, 0.000408646)
    ..cubicTo(18.9961, 0.0238461, 16.8867, 1.72306, 16.8867, 4.71135)
    ..cubicTo(16.8867, 7.30119, 18.4102, 9.10588, 20.332, 10.2192)
    ..cubicTo(21.2227, 10.7113, 22.1836, 11.0629, 23.7305, 11.2856)
    ..cubicTo(23.4727, 10.6996, 23.3438, 10.0434, 23.3438, 9.32853)
    ..cubicTo(23.3438, 6.82072, 25.3945, 4.57072, 27.9375, 4.11369)
    ..cubicTo(27.7383, 3.64494, 27.5273, 3.32853, 27.3164, 3.04728)
    ..cubicTo(25.8164, 0.961346, 23.5898, -0.0230289, 21.5742, 0.000408646)
    ..close()
    ..moveTo(21.1289, 5.02775)
    ..lineTo(19.3945, 3.57463)
    ..cubicTo(19.1484, 3.37541, 19.1367, 3.02385, 19.3359, 2.78947)
    ..cubicTo(19.5234, 2.54338, 19.8867, 2.50822, 20.1211, 2.70744)
    ..lineTo(21.8438, 4.16056)
    ..cubicTo(22.0898, 4.35978, 22.1133, 4.71135, 21.9141, 4.95744)
    ..cubicTo(21.7148, 5.20353, 21.3633, 5.22697, 21.1289, 5.02775)
    ..close()
    ..moveTo(23.2617, 20.7309)
    ..cubicTo(24, 20.7309, 24.4688, 20.3559, 24.4688, 19.6293)
    ..lineTo(24.4688, 12.5746)
    ..cubicTo(23.25, 12.4926, 22.1484, 12.2699, 21.1523, 11.9067)
    ..lineTo(21.1523, 19.6293)
    ..cubicTo(21.1523, 20.3559, 21.6211, 20.7309, 22.3477, 20.7309)
    ..close(),
  Path()
    ..moveTo(4.26562, 12.727)
    ..cubicTo(6.08203, 12.727, 7.69922, 11.602, 7.69922, 9.32853)
    ..cubicTo(7.69922, 7.30119, 5.78906, 5.15666, 3.30469, 5.15666)
    ..cubicTo(1.20703, 5.15666, 0, 6.82072, 0, 8.51994)
    ..cubicTo(0, 11.0629, 2.16797, 12.727, 4.26562, 12.727)
    ..close()
    ..moveTo(3.67969, 10.9457)
    ..cubicTo(3.35156, 11.2387, 2.78906, 10.9457, 2.09766, 10.1137)
    ..cubicTo(1.41797, 9.28166, 1.24219, 8.70744, 1.57031, 8.42619)
    ..cubicTo(1.91016, 8.1215, 2.46094, 8.40275, 3.16406, 9.2465)
    ..cubicTo(3.83203, 10.102, 4.00781, 10.6645, 3.67969, 10.9457)
    ..close()
    ..moveTo(27.9023, 12.727)
    ..cubicTo(30, 12.727, 32.168, 11.0629, 32.168, 8.51994)
    ..cubicTo(32.168, 6.82072, 30.9609, 5.15666, 28.8633, 5.15666)
    ..cubicTo(26.3789, 5.15666, 24.4688, 7.30119, 24.4688, 9.32853)
    ..cubicTo(24.4688, 11.602, 26.0859, 12.727, 27.9023, 12.727)
    ..close()
    ..moveTo(28.4883, 10.9457)
    ..cubicTo(28.1602, 10.6645, 28.3359, 10.102, 29.0039, 9.2465)
    ..cubicTo(29.707, 8.40275, 30.2578, 8.1215, 30.5977, 8.42619)
    ..cubicTo(30.9258, 8.70744, 30.75, 9.28166, 30.0703, 10.1137)
    ..cubicTo(29.3789, 10.9457, 28.8164, 11.2387, 28.4883, 10.9457)
    ..close(),
];
