import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/media/artwork_network_image.dart';
import '../../../shared/models/track.dart';
import '../../../shared/utils/media_uri.dart';
import '../../themes/music_typography.dart';

/// Catalogue links are independent of resolved audio URLs and local downloads.
String? songShareUrl(Track track) {
  final uri = Uri.tryParse(track.externalUrl.trim());
  if (uri != null &&
      {'http', 'https'}.contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.toString().length <= 2048) {
    return uri.toString();
  }
  if (track.source == TrackSource.kugou &&
      RegExp(r'^kugou_[a-fA-F0-9]{32}$').hasMatch(track.id)) {
    return 'https://www.kugou.com/song/#hash=${track.id.substring(6)}';
  }
  if (track.source == TrackSource.netease &&
      RegExp(r'^netease_\d+$').hasMatch(track.id)) {
    return 'https://music.163.com/#/song?id=${track.id.substring(8)}';
  }
  return null;
}

/// Render once at export resolution. Preview and saved PNG use identical pixels.
Future<Uint8List> generateSongPoster(Track track) async {
  final cover = await _loadCover(track.coverAsset);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(3);
  const size = Size(360, 568);
  const ink = Color(0xFF252D35);
  const muted = Color(0xFF68716F);
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF4F1E8), Color(0xFFE2EAE5)],
      ).createShader(Offset.zero & size),
  );
  void text(
    String value,
    Offset offset,
    double width,
    double fontSize, {
    Color color = ink,
    int lines = 1,
    bool heading = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1.22,
          fontWeight: heading
              ? MusicTypography.titleWeight
              : MusicTypography.bodyWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
    painter.dispose();
  }

  text('MESTING  /  正在听', const Offset(28, 24), 304, 11, color: muted);
  const coverRect = Rect.fromLTWH(28, 57, 304, 304);
  final clip = RRect.fromRectAndRadius(coverRect, const Radius.circular(16));
  canvas.drawShadow(Path()..addRRect(clip), const Color(0x44252D35), 9, false);
  canvas.save();
  canvas.clipRRect(clip);
  canvas.drawRect(coverRect, Paint()..color = const Color(0xFFCAD8D1));
  if (cover != null) {
    paintImage(
      canvas: canvas,
      rect: coverRect,
      image: cover,
      fit: BoxFit.cover,
    );
  } else {
    canvas.drawCircle(
      coverRect.center,
      100,
      Paint()..color = ink.withValues(alpha: .85),
    );
    canvas.drawCircle(
      coverRect.center,
      35,
      Paint()..color = const Color(0xFFE2EAE5),
    );
    canvas.drawCircle(coverRect.center, 5, Paint()..color = muted);
  }
  canvas.restore();
  text(track.title, const Offset(28, 383), 304, 26, lines: 2, heading: true);
  text(track.artist, const Offset(28, 453), 304, 15, color: muted);
  canvas.drawLine(
    const Offset(28, 487),
    const Offset(332, 487),
    Paint()..color = ink.withValues(alpha: .13),
  );
  text('把这一刻，分享给你', const Offset(28, 504), 225, 13);
  text('Mesting Music', const Offset(28, 528), 225, 11, color: muted);
  final url = songShareUrl(track);
  if (url != null) {
    canvas.save();
    canvas.translate(276, 499);
    canvas.drawRect(
      const Rect.fromLTWH(-4, -4, 64, 64),
      Paint()..color = Colors.white,
    );
    QrPainter(
      data: url,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    ).paint(canvas, const Size.square(56));
    canvas.restore();
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(1080, 1704);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('海报生成失败，请重试');
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
    cover?.dispose();
  }
}

Future<ui.Image?> _loadCover(String source) async {
  if (source.trim().isEmpty) return null;
  final value = sizedArtworkUri(source);
  final uri = Uri.tryParse(value);
  final ImageProvider provider;
  if (uri != null && {'https', 'http'}.contains(uri.scheme)) {
    provider = networkArtworkProvider(value);
  } else if (uri?.scheme == 'file' || value.startsWith('/')) {
    provider = FileImage(
      uri?.scheme == 'file' ? File.fromUri(uri!) : File(value),
    );
  } else if (uri?.scheme.isNotEmpty == true) {
    return null;
  } else {
    provider = AssetImage(value);
  }
  final stream = ResizeImage(
    provider,
    width: 1024,
  ).resolve(ImageConfiguration.empty);
  final completer = Completer<ui.Image?>();
  final listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (Object error, StackTrace? stack) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );
  stream.addListener(listener);
  try {
    return await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
  } finally {
    stream.removeListener(listener);
  }
}
