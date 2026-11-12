import '../../../shared/widgets/beta_selection_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/beta_choice_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../presentation/platform_design.dart';
import '../presentation/platform_feedback.dart';
import 'netease_fallback.dart';
import 'netease_membership_page.dart';
import 'netease_playback_options.dart';
import 'netease_account_source_info.dart';
import '../../themes/music_typography.dart';

/// Reuses the existing playback settings page; loading/disabled state is shared
/// across all mutations so rapid edits cannot overwrite another saved option.
class NeteaseSourceSettingsPanel extends ConsumerStatefulWidget {
  const NeteaseSourceSettingsPanel({super.key});
  @override
  ConsumerState<NeteaseSourceSettingsPanel> createState() =>
      _NeteaseSourceSettingsPanelState();
}

class _NeteaseSourceSettingsPanelState
    extends ConsumerState<NeteaseSourceSettingsPanel> {
  bool _busy = false;
  Future<void> _save(NeteasePlaybackOptions value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(neteasePlaybackOptionsProvider.notifier).save(value);
    } catch (e) {
      if (mounted) showPlatformFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(neteasePlaybackOptionsProvider);
    final diagnostics = ref.watch(neteaseFallbackDiagnosticsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ref.watch(neteaseLocalSvipProvider) ? '至尊SVIP 已启用' : '本地会员',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              BetaGlassButton(
                onPressed: () => Navigator.of(context).push(
                  MestingPageRoute<void>(
                    builder: (_) => const NeteaseMembershipPage(),
                  ),
                ),
                child: const Text('管理本地会员'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '备用音源与音质',
          style: TextStyle(
            fontSize: MusicTypography.bodySize,
            fontWeight: MusicTypography.titleWeight,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '$neteaseAutomaticSourceOrder。自动模式优先官方完整音频；手动选源失败后自动补源，并显示实际来源。',
        ),
        const SizedBox(height: 6),
        const Text('下载独立于播放选源：优先官方完整版，官方不可用时由你选择其他可下载音源。'),
        const SizedBox(height: 12),
        const NeteaseAccountSourceInfo(),
        const SizedBox(height: 12),
        BetaChoiceField<NeteaseSourceStrategy>(
          initialValue: options.strategy,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '新音源选择策略'),
          items: const [
            DropdownMenuItem(
              value: NeteaseSourceStrategy.ordered,
              child: Text('按顺序优先'),
            ),
            DropdownMenuItem(
              value: NeteaseSourceStrategy.highestQuality,
              child: Text('优先最高音质'),
            ),
          ],
          onChanged: _busy
              ? null
              : (v) {
                  if (v != null) _save(options.copyWith(strategy: v));
                },
        ),
        BetaSwitchTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('允许无损音源'),
          subtitle: const Text('选择无损音质时尝试真实 FLAC；返回有损文件时不标为无损'),
          value: options.lossless,
          onChanged: _busy ? null : (v) => _save(options.copyWith(lossless: v)),
        ),
        BetaChoiceField<int>(
          initialValue: options.minimumBitrate,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '备用音源最低码率'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('不限，允许未知码率')),
            DropdownMenuItem(value: 128000, child: Text('128 kbps')),
            DropdownMenuItem(value: 192000, child: Text('192 kbps')),
            DropdownMenuItem(value: 320000, child: Text('320 kbps')),
          ],
          onChanged: _busy
              ? null
              : (v) {
                  if (v != null) _save(options.copyWith(minimumBitrate: v));
                },
        ),
        const SizedBox(height: 12),
        for (final source in NeteasePublicSource.values)
          BetaSwitchTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              source == NeteasePublicSource.kugou ? '酷狗（公开音源）' : source.label,
            ),
            subtitle: Text(source.note),
            value: source.available && options.enabledSources.contains(source),
            onChanged: _busy || !source.available
                ? null
                : (enabled) {
                    final sources = {...options.enabledSources};
                    if (enabled) {
                      sources.add(source);
                    } else {
                      sources.remove(source);
                    }
                    _save(options.copyWith(enabledSources: sources));
                  },
          ),
        const SizedBox(height: 12),
        BetaSwitchTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('缓存音源解析'),
          subtitle: const Text('短时缓存并在复用前检测地址；切换账号后重建'),
          value: options.cache,
          onChanged: _busy ? null : (v) => _save(options.copyWith(cache: v)),
        ),
        BetaGlassButton(
          onPressed: () =>
              ref.read(neteaseFallbackResolverProvider).clearCache(),
          child: const Text('清除解析缓存'),
        ),
        BetaSwitchTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('音源诊断日志'),
          subtitle: const Text(
            '本机记录音源与系统退出原因；原生崩溃保留可用的脱敏线程和函数栈，最多 80 条，不包含账号或歌曲内容',
          ),
          value: options.diagnostics,
          onChanged: _busy
              ? null
              : (v) => _save(options.copyWith(diagnostics: v)),
        ),
        if (options.diagnostics)
          ListenableBuilder(
            listenable: diagnostics,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('当前 ${diagnostics.rows.length} 条记录'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    BetaGlassButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: diagnostics.json),
                        );
                      },
                      child: const Text('复制 JSON 日志'),
                    ),
                    BetaGlassButton(
                      onPressed: diagnostics.clear,
                      child: const Text('清空日志'),
                    ),
                  ],
                ),
                if (diagnostics.rows.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      diagnostics.json,
                      style: const TextStyle(
                        fontSize: MusicTypography.captionSize,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
