import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Local, theme-aware symbols replace remote catalog thumbnails. Category is
/// visual metadata only: it never changes the repository's actual EQ mapping.
class MusicEffectGlyph extends StatelessWidget {
  const MusicEffectGlyph({
    required this.name,
    required this.category,
    required this.preset,
    super.key,
  });
  final String name, category, preset;

  IconData get symbol {
    final value = '$name $category $preset'.toLowerCase();
    if (value.contains('耳机') || value.contains('buds')) {
      return CupertinoIcons.headphones;
    }
    if (value.contains('汽车') || value.contains('车载')) {
      return CupertinoIcons.car_detailed;
    }
    if (value.contains('环绕') || value.contains('空间') || value.contains('3d')) {
      return CupertinoIcons.hifispeaker;
    }
    if (value.contains('低音')) {
      return CupertinoIcons.speaker_2;
    }
    if (value.contains('人声')) {
      return CupertinoIcons.mic;
    }
    if (value.contains('电子') || value.contains('电音')) {
      return CupertinoIcons.waveform;
    }
    if (value.contains('古典') || value.contains('钢琴')) {
      return CupertinoIcons.music_note;
    }
    return CupertinoIcons.slider_horizontal_3;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A restrained porcelain/glass tile keeps a common weight and silhouette;
    // no remote artwork, per-row shader, animation or image decode is needed.
    return ExcludeSemantics(
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                scheme.primary.withValues(alpha: dark ? .18 : .07),
                scheme.surface,
              ),
              scheme.surfaceContainerLow,
            ],
          ),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .35),
            width: .6,
          ),
        ),
        child: Icon(symbol, size: 27, color: scheme.primary),
      ),
    );
  }
}
