import 'package:flutter/material.dart';
import '../lyrics/presentation/lyric_focus_treatment.dart';
import 'personal_style.dart';
import 'style_option_grid.dart';

class LyricPresentationPicker extends StatelessWidget {
  const LyricPresentationPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final LyricPresentation selected;
  final ValueChanged<LyricPresentation> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('歌词展示'),
      const SizedBox(height: 10),
      StyleOptionGrid(
        values: LyricPresentation.values.map((v) => v.name).toList(),
        labels: const ['当前样式', '聚焦歌词', '清晰歌词'],
        selected: selected.name,
        keyPrefix: 'lyric-presentation',
        onSelected: (value) =>
            onSelected(LyricPresentation.values.byName(value)),
        preview: (value) => Padding(
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  LyricFocusTreatment(
                    distance: value == 'focus' ? (i - 1).abs().toDouble() : 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        ['上一句，轻轻流过', '此刻，让音乐靠近', '下一句，缓缓浮现'][i],
                        textAlign: value != 'current'
                            ? TextAlign.center
                            : TextAlign.left,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: i == 1
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(
                                alpha: i == 1
                                    ? 1
                                    : value == 'clear'
                                    ? .38
                                    : .65,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '示例预览 · 聚焦歌词柔和虚化上下句；清晰歌词保留清楚文字，以亮度区分当前句。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 18),
    ],
  );
}
