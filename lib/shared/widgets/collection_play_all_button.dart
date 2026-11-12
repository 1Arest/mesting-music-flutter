import 'package:flutter/material.dart';
import '../../features/themes/beta_appearance.dart';
import '../../features/themes/music_typography.dart';
import 'beta_glass_controls.dart';

/// Collection pages share a 26dp disc and a 48dp minimum touch target. Keeping
/// the disc explicit avoids TextButton.icon's inherited 18dp icon shrinking it.
/// The page still owns fetching, queue construction and account validation.
class CollectionPlayAllButton extends StatelessWidget {
  const CollectionPlayAllButton({
    required this.onPressed,
    this.total,
    this.label = '播放全部',
    this.loading = false,
    this.loadingLabel = '正在准备…',
    super.key,
  });
  final VoidCallback? onPressed;
  final int? total;
  final String label, loadingLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: loading ? null : onPressed,
    style: TextButton.styleFrom(
      alignment: Alignment.centerLeft,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CollectionPlayGlyph(loading: loading),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            '${loading ? loadingLabel : label}${total == null ? '' : '（$total）'}',
            style: const TextStyle(
              fontSize: MusicTypography.bodySize,
              fontWeight: MusicTypography.titleWeight,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The same optical size also serves pages with a custom count/loading label.
class CollectionPlayGlyph extends StatelessWidget {
  const CollectionPlayGlyph({this.loading = false, super.key});
  final bool loading;
  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: BetaAppearance.playbackAction(Theme.of(context).brightness),
    ),
    child: loading
        ? const BetaActivityIndicator(color: Colors.white, radius: 8)
        : const Icon(Icons.play_arrow_rounded, size: 21, color: Colors.white),
  );
}
