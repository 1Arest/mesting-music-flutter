import 'package:flutter/material.dart';

import '../../../core/audio/music_rhythm.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/music_spectrum_ring.dart';
import '../../../shared/widgets/track_artwork.dart';

/// A single, isolated spectrum around the actual player artwork.
class MusicRhythmArtwork extends StatelessWidget {
  const MusicRhythmArtwork({
    required this.track,
    this.preview = false,
    super.key,
  });

  final Track track;
  final bool preview;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.biggest.shortestSide;
        final side = available.isFinite ? available : 320.0;
        if (side <= 0) return const SizedBox.shrink();
        final inset = (side * .18).clamp(16.0, 56.0);
        final artwork = Padding(
          padding: EdgeInsets.all(inset),
          child: ClipOval(
            child: TrackArtwork(track: track, width: 640, height: 640),
          ),
        );
        // A Polaroid frame leaves more padding at the bottom. Keep the cover
        // and its spectrum on one square inside the available rectangle.
        Widget draw(MusicRhythmFrame frame) => Center(
          child: SizedBox.square(
            dimension: side,
            child: CustomPaint(
              painter: _RhythmRingPainter(frame, inset),
              child: artwork,
            ),
          ),
        );
        // Gallery cards show a static illustration. The player only consumes
        // a frame from its running decoder, even when that means a quiet ring.
        if (preview) {
          return draw(
            const MusicRhythmFrame(
              available: true,
              level: .55,
              peak: .78,
              pulse: .26,
              bands: [
                .81,
                .62,
                .24,
                .46,
                .28,
                .14,
                .54,
                .38,
                .66,
                .25,
                .12,
                .37,
              ],
            ),
          );
        }
        return MusicRhythmSurface(
          respectChrome: false,
          builder: (_, frame) => draw(frame),
        );
      },
    ),
  );
}

class _RhythmRingPainter extends CustomPainter {
  _RhythmRingPainter(this.frame, this.inset);

  final MusicRhythmFrame frame;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) => paintMusicSpectrumRing(
    canvas,
    center: size.center(Offset.zero),
    radius: size.shortestSide / 2 - inset + 5,
    reach: (inset - 7).clamp(1.0, 50.0),
    stroke: 1.65,
    frame: frame,
  );

  @override
  bool shouldRepaint(_RhythmRingPainter oldDelegate) =>
      frame != oldDelegate.frame || inset != oldDelegate.inset;
}
