import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/domain/platform_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../core/audio/playback_mode.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_popover.dart';
import '../../music_platform/default_playback_quality.dart';
import '../../music_platform/presentation/platform_design.dart';

class PlaybackPreferencesPage extends ConsumerStatefulWidget {
  const PlaybackPreferencesPage({super.key});
  @override
  ConsumerState<PlaybackPreferencesPage> createState() =>
      _PlaybackPreferencesPageState();
}

class _PlaybackPreferencesPageState
    extends ConsumerState<PlaybackPreferencesPage> {
  TrackSource _source = TrackSource.netease;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _source = switch (ref.read(platformAccountProvider).value?.platform) {
      MusicPlatform.netease => TrackSource.netease,
      MusicPlatform.qishui => TrackSource.qishui,
      _ => TrackSource.kugou,
    };
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(defaultPlaybackQualityProvider);
    final order =
        ref.watch(playbackOrderProvider).value ?? const PlaybackOrder();
    final handler = ref.read(audioHandlerProvider);
    Future<void> apply(Future<void> Function() task) async {
      if (_saving) return;
      setState(() => _saving = true);
      try {
        await task();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('设置未保存，请重试')));
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }

    return PlatformPageFrame(
      title: '播放设置',
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          22,
          18,
          22,
          BetaContentInsets.bottomOf(context, 32),
        ),
        children: [
          Text('默认播放音质', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            '按歌曲实际音源分别保存。从下一次载入音源开始生效，不会中断当前歌曲。平台账号与版权权限决定可用档位，播放器显示实际返回音质。',
          ),
          const SizedBox(height: 24),
          _PlaybackChoice<TrackSource>(
            value: _source,
            label: '音乐平台',
            options: const [
              (value: TrackSource.netease, label: '网易云'),
              (value: TrackSource.kugou, label: '酷狗'),
              (value: TrackSource.qishui, label: '汽水'),
            ],
            onChanged: _saving ? null : (v) => setState(() => _source = v),
          ),
          const SizedBox(height: 18),
          _PlaybackChoice<String>(
            value: preferences[_source] ?? 'auto',
            label: '默认音质',
            options: [
              (value: 'auto', label: '最高可用音质（自动）'),
              for (final q in DefaultPlaybackQuality.options(_source))
                (value: q.code, label: q.label),
            ],
            onChanged: _saving
                ? null
                : (v) => apply(
                    () => ref
                        .read(defaultPlaybackQualityProvider.notifier)
                        .select(_source, v),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('所选档位不可用时，会回退到该音源可播放的档位。当前歌曲的音质按钮仍可手动切换。'),
          ),
          const SizedBox(height: 32),
          Text('播放顺序', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          DropdownButtonFormField<PlaybackRepeat>(
            key: ValueKey(order.repeat),
            initialValue: order.repeat,
            decoration: const InputDecoration(labelText: '循环方式'),
            items: [
              for (final repeat in PlaybackRepeat.values)
                DropdownMenuItem(value: repeat, child: Text(repeat.label)),
            ],
            onChanged: _saving
                ? null
                : (v) => apply(
                    () => handler.setRepeatMode(switch (v!) {
                      PlaybackRepeat.off => AudioServiceRepeatMode.none,
                      PlaybackRepeat.all => AudioServiceRepeatMode.all,
                      PlaybackRepeat.one => AudioServiceRepeatMode.one,
                    }),
                  ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('随机播放'),
            subtitle: const Text('与循环方式分别设置'),
            value: order.shuffle,
            onChanged: _saving
                ? null
                : (v) => apply(() => handler.setShuffleEnabled(v)),
          ),
        ],
      ),
    );
  }
}

/// Both preferences use the existing anchored glass route. The route bounds
/// the menu to the space above/below the trigger, so long quality lists scroll.
class _PlaybackChoice<T extends Object> extends StatelessWidget {
  const _PlaybackChoice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
    if (!DistributionChannel.isBeta) {
      return DropdownButtonFormField<T>(
        key: ValueKey((label, selected.value)),
        initialValue: selected.value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.value, child: Text(option.label)),
        ],
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null && next != value) onChanged!(next);
              },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 7),
        Builder(
          builder: (anchorContext) => BetaGlassButton(
            key: ValueKey('playback-choice-$label'),
            label: '$label，${selected.label}',
            onPressed: onChanged == null
                ? null
                : () async {
                    final box = anchorContext.findRenderObject() as RenderBox;
                    final width = box.size.width.clamp(1.0, 360.0).toDouble();
                    final next = await showBetaGlassPopover<T>(
                      context: anchorContext,
                      anchor: box.localToGlobal(Offset.zero) & box.size,
                      width: width,
                      label: '关闭$label选项',
                      builder: (menu) => SizedBox(
                        width: width,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final option in options)
                                ListTile(
                                  selected: option.value == selected.value,
                                  title: Text(option.label),
                                  trailing: option.value == selected.value
                                      ? const Icon(Icons.check_rounded)
                                      : null,
                                  onTap: () =>
                                      Navigator.pop(menu, option.value),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (anchorContext.mounted &&
                        next != null &&
                        next != value) {
                      onChanged!(next);
                    }
                  },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.keyboard_arrow_down_rounded),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
