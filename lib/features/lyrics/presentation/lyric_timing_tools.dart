import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../lyric_timing.dart';

/// Uses the existing player menu; lyrics never allocate a second more button.
Future<void> showLyricTimingSheet(BuildContext context) =>
    showLiquidGlassBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const LyricTimingPanel(),
    );

class LyricTimingPanel extends ConsumerStatefulWidget {
  const LyricTimingPanel({super.key});
  @override
  ConsumerState<LyricTimingPanel> createState() => _LyricTimingPanelState();
}

class _LyricTimingPanelState extends ConsumerState<LyricTimingPanel> {
  bool _saving = false;

  Future<void> _adjust(String song, int? delta) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(lyricTimingProvider(song).notifier);
      if (delta == null) {
        await controller.reset();
      } else {
        await controller.adjust(delta);
      }
    } on Object catch (error) {
      if (mounted) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = lyricTimingKey(ref.watch(currentTrackProvider));
    final offset = ref.watch(lyricTimingProvider(song));
    final synced =
        ref.watch(currentTimedLyricsProvider).value?.isSynced == true;
    final milliseconds = offset.value ?? 0;
    final label =
        '${milliseconds > 0 ? '+' : ''}${(milliseconds / 1000).toStringAsFixed(1)} 秒';
    final ready = !_saving && offset.hasValue;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('歌词时间调整', style: TextStyle(fontSize: 20)),
                ),
                IconButton(
                  tooltip: '关闭歌词时间调整',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            const Text('负值提前，正值延后；仅保存在本机当前歌曲'),
            const SizedBox(height: 16),
            if (!synced) const Text('当前歌曲没有可调整时间的同步歌词'),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: ready && synced ? () => _adjust(song, -500) : null,
                  child: const Text('−0.5 秒'),
                ),
                TextButton(
                  onPressed: ready && synced && milliseconds != 0
                      ? () => _adjust(song, null)
                      : null,
                  child: const Text('还原'),
                ),
                TextButton(
                  onPressed: ready && synced ? () => _adjust(song, 500) : null,
                  child: const Text('＋0.5 秒'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
