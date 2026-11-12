import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/music_rhythm.dart';
import '../../../shared/widgets/music_spectrum_ring.dart';
import '../../themes/profile_effect_style.dart';
import 'platform_avatar.dart';

/// Discovery/Functions use the same saved audio-ring choice as My. The outer
/// canvas owns the decoration only; the original account button owns taps.
class RhythmPlatformAvatar extends ConsumerWidget {
  const RhythmPlatformAvatar({
    required this.url,
    this.size = 42,
    this.personal = false,
    super.key,
  });
  final String url;
  final double size;
  final bool personal;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = PlatformAvatar(url: url, size: size, personal: personal);
    if (ref.watch(profileEffectProvider) != ProfileEffectStyle.rhythm) {
      return avatar;
    }
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size + 16,
        child: MusicRhythmSurface(
          builder: (context, frame) => CustomPaint(
            painter: _AvatarRing(frame),
            child: Padding(padding: const EdgeInsets.all(8), child: avatar),
          ),
        ),
      ),
    );
  }
}

class _AvatarRing extends CustomPainter {
  _AvatarRing(this.frame);
  final MusicRhythmFrame frame;
  @override
  void paint(Canvas canvas, Size size) => paintMusicSpectrumRing(
    canvas,
    center: size.center(Offset.zero),
    radius: size.shortestSide / 2 - 6,
    reach: 4.4,
    stroke: 1.05,
    frame: frame,
  );

  @override
  bool shouldRepaint(_AvatarRing oldDelegate) => frame != oldDelegate.frame;
}
