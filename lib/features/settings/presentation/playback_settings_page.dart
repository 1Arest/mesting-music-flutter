import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_preferences.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
import '../../../shared/widgets/music_notice.dart';

/// Same grouped Apple controls and scroll material as the existing haptics page.
class PlaybackSettingsPage extends ConsumerWidget {
  const PlaybackSettingsPage({this.embedded = false, super.key});
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackPreferencesProvider);
    Future<void> change(Map<String, Object> patch) async {
      try {
        await ref.read(playbackPreferencesProvider.notifier).change(patch);
      } catch (_) {
        if (context.mounted) {
          showMusicNotice(
            context,
            title: '播放设置未保存',
            message: '请重试',
            icon: CupertinoIcons.exclamationmark_circle,
          );
        }
      }
    }

    Widget group(String title, String caption, String key, bool value) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    CupertinoSwitch(
                      key: ValueKey(key),
                      value: value,
                      onChanged: (v) => change({key: v}),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(caption, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
    final content = <Widget>[
      group(
        '下一首提前准备',
        '在所有网络下提前解析并缓冲下一首，会使用少量流量；关闭后按需加载。',
        'prepareNext',
        settings.prepareNext,
      ),
      group(
        '歌曲音量平衡',
        '拉近歌曲的整体响度，保留曲内强弱。完整播放后在本机分析并记住结果；首次或数据不足时保留原音量。',
        'balance',
        settings.balance,
      ),
      group(
        '歌曲交叉淡化',
        '仅自然结束时衔接下一首，开启后仍需在临近结束时准备下一首。手动切歌立即响应；一起听、单曲循环和定时停止时不叠播。',
        'crossfade',
        settings.crossfade,
      ),
      if (settings.crossfade) ...[
        Text('交叉淡化时长 · ${settings.seconds} 秒'),
        CupertinoSlider(
          key: const ValueKey('crossfade-seconds'),
          value: settings.seconds.toDouble(),
          min: 1,
          max: 6,
          divisions: 5,
          onChanged: (v) => change({'seconds': v.round()}),
        ),
      ],
    ];
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: content,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('播放设置')),
      body: SafeArea(
        top: false,
        child: BetaGlassScrollBody(
          padding: const EdgeInsets.all(20),
          children: content,
        ),
      ),
    );
  }
}
