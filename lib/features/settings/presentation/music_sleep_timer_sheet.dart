import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/music_sleep_timer.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_action.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';

Future<void> showMusicSleepTimer(BuildContext context, WidgetRef ref) {
  final handler = ref.read(audioHandlerProvider);
  // The artwork player deliberately installs a dark local Theme. The timer
  // is an application sheet, so both its material and its content must resolve
  // from the root app theme instead of mixing the two brightness contexts.
  final appContext = Navigator.of(context, rootNavigator: true).context;
  return showLiquidGlassBottomSheet<void>(
    context: appContext,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _SleepTimerSheet(
      timer: handler.sleepTimer,
      hasTrack: handler.mediaItem.value != null,
    ),
  );
}

class _SleepTimerSheet extends StatefulWidget {
  const _SleepTimerSheet({required this.timer, required this.hasTrack});
  final MusicSleepTimer timer;
  final bool hasTrack;
  @override
  State<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<_SleepTimerSheet> {
  int _minutes = 30;
  Future<void> _customDuration() async {
    var value = Duration(minutes: _minutes);
    final selected = await showLiquidGlassBottomSheet<Duration>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const Expanded(
                  child: Text(
                    '自定义时长',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.pop(context, value),
                  child: const Text('完成'),
                ),
              ],
            ),
            SizedBox(
              height: 230,
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.hm,
                initialTimerDuration: value,
                onTimerDurationChanged: (duration) => value = duration,
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _minutes = selected.inMinutes.clamp(1, 1439));
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListenableBuilder(
      listenable: widget.timer,
      builder: (context, _) {
        final timer = widget.timer, scheme = Theme.of(context).colorScheme;
        final seconds = timer.remaining.inSeconds;
        final countdown =
            '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '定时关闭',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    BetaGlassAction(
                      label: '关闭定时设置',
                      icon: CupertinoIcons.xmark,
                      blue: false,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  timer.mode == MusicSleepMode.endOfTrack
                      ? '播完当前歌曲后停止'
                      : timer.mode == MusicSleepMode.countdown
                      ? countdown
                      : '让音乐陪你到入睡',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: timer.mode == MusicSleepMode.countdown ? 42 : 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final minutes in [15, 30, 45, 60, 90])
                      ChoiceChip(
                        label: Text('$minutes 分钟'),
                        selected: _minutes == minutes,
                        onSelected: (_) => setState(() => _minutes = minutes),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '自定义时长',
                        style: TextStyle(
                          fontSize: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      key: const ValueKey('music-sleep-custom'),
                      onPressed: _customDuration,
                      child: Text(
                        '$_minutes 分钟  ›',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                BetaGlassButton(
                  key: const ValueKey('music-sleep-start'),
                  blue: true,
                  onPressed: () {
                    timer.start(Duration(minutes: _minutes));
                  },
                  child: Text(timer.active ? '重新开始计时' : '开始计时'),
                ),
                const SizedBox(height: 10),
                BetaGlassButton(
                  key: const ValueKey('music-sleep-end-track'),
                  onPressed: widget.hasTrack ? timer.afterCurrentTrack : null,
                  child: const Text('播完当前歌曲后停止'),
                ),
                if (timer.active) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    key: const ValueKey('music-sleep-cancel'),
                    onPressed: timer.cancel,
                    child: const Text('取消定时'),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  '到时只停止音乐播放，保留应用和账号。定时不会在重启应用后自动恢复。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
