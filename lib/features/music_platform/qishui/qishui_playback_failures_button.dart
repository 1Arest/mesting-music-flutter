import 'package:flutter/material.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import 'qishui_playback_failures.dart';

/// Keep recovery detail off the lyric controls. The last skipped title remains
/// accessible after the next song begins, so users can identify a failed song.
class QishuiRecentPlaybackFailuresButton extends StatelessWidget {
  const QishuiRecentPlaybackFailuresButton({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: QishuiPlaybackFailures.shared,
    builder: (context, _) {
      final rows = QishuiPlaybackFailures.shared.rows;
      if (rows.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextButton.icon(
          key: const ValueKey('qishui-recent-skips'),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          label: Text(
            '最近跳过：${rows.first.title}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () => showLiquidGlassBottomSheet<void>(
            context: context,
            useSafeArea: true,
            useRootNavigator: true,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    '最近跳过的歌曲',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('仅保留本次账号的最近20条。格式或资料问题不代表没有版权。'),
                  for (final row in rows)
                    ListTile(
                      title: Text(row.title),
                      subtitle: Text(
                        '${row.artist}\n${row.reason} · ${row.phase}',
                      ),
                      isThreeLine: true,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
