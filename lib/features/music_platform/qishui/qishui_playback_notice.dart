import 'package:flutter/material.dart';

import '../../themes/music_typography.dart';

/// Reports the selected official stream, never a guessed VIP state. The label
/// wraps at large text sizes and remains visible in cover and lyric views.
class QishuiPlaybackNotice extends StatelessWidget {
  const QishuiPlaybackNotice({required this.preview, super.key});
  final bool preview;

  @override
  Widget build(BuildContext context) {
    if (!preview) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: '官方当前返回试听音频',
      child: Container(
        key: const ValueKey('qishui-official-preview-notice'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '官方试听',
          style: MusicTypography.footnote.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
