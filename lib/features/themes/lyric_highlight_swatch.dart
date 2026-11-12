import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A fill color must remain identifiable against a matching page background.
/// Borders express the swatch edge; a separate check expresses selection.
class LyricHighlightSwatch extends StatelessWidget {
  const LyricHighlightSwatch({
    required this.color,
    required this.selected,
    required this.onPressed,
    super.key,
  });
  final Color color;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final check = color.computeLuminance() > .5 ? Colors.black87 : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: color == Colors.white ? '白色歌词' : '歌词颜色',
      child: CupertinoButton(
        padding: const EdgeInsets.all(10),
        onPressed: onPressed,
        child: Container(
          width: 26,
          height: 26,
          key: ValueKey('lyric-color-${color.toARGB32()}'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: .32),
              width: selected ? 2.5 : 1.2,
            ),
          ),
          child: selected
              ? Icon(CupertinoIcons.check_mark, size: 15, color: check)
              : null,
        ),
      ),
    );
  }
}
