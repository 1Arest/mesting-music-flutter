import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/distribution_channel.dart';
import '../../shared/widgets/music_notice.dart';
import '../player/presentation/ip_progress_decoration.dart';
import '../player/presentation/shinchan_progress_walker.dart';
import 'music_theme_preset.dart';
import 'music_typography.dart';
import 'progress_decoration_picker.dart';
import 'theme_controller.dart';

/// One role catalogue is the normal entry point. Customization replaces that
/// catalogue with rail previews, keeping the current character unchanged.
class ProgressOutfitPicker extends ConsumerStatefulWidget {
  const ProgressOutfitPicker({super.key});

  @override
  ConsumerState<ProgressOutfitPicker> createState() =>
      _ProgressOutfitPickerState();
}

class _ProgressOutfitPickerState extends ConsumerState<ProgressOutfitPicker> {
  bool _customizing = false;
  bool _saving = false;

  Future<void> _select(ProgressDecoration value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final controller = ref.read(themeVisualSettingsProvider.notifier);
      if (_customizing) {
        await controller.setProgressStyle(value);
      } else {
        await controller.setProgressOutfit(value);
      }
    } on Object {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '装扮未保存',
          message: '请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(themeVisualSettingsProvider);
    final preset = ref.watch(effectiveMusicThemeProvider);
    final character = settings.progressCharacter;
    final style = settings.progressStyle;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('progress-outfit-preview'),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              _OutfitPreview(settings: settings, preset: preset),
              Text(
                '${progressDecorationLabel(character)} · ${progressDecorationLabel(style)}轨道',
                key: const ValueKey('progress-outfit-summary'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: MusicTypography.footnoteSize,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('progress-outfit-customize'),
            onPressed: _saving
                ? null
                : () => setState(() => _customizing = !_customizing),
            icon: Icon(_customizing ? Icons.check_rounded : Icons.tune_rounded),
            label: Text(_customizing ? '完成搭配' : '自定义搭配'),
          ),
        ),
        Text(
          _customizing ? '自定义轨道' : '选择角色',
          style: const TextStyle(fontWeight: MusicTypography.titleWeight),
        ),
        const SizedBox(height: 5),
        Text(
          _customizing ? '只更换轨道，保留当前角色。' : '选择角色时，会同时搭配同系列轨道。',
          style: TextStyle(
            fontSize: MusicTypography.footnoteSize,
            color: scheme.onSurfaceVariant,
          ),
        ),
        IgnorePointer(
          ignoring: _saving,
          child: ProgressDecorationPicker(
            selected: _customizing ? style : character,
            character: !_customizing,
            preset: preset,
            onSelected: _select,
          ),
        ),
        if (!_customizing &&
            DistributionChannel.isBeta &&
            character == ProgressDecoration.shinchan) ...[
          const SizedBox(height: 18),
          ShinchanWeatherPicker(
            selected:
                settings.shinchanWeather ?? shinchanWeatherForPreset(preset.id),
          ),
        ],
      ],
    );
  }
}

/// The same track shape, character size and optical alignment as the player.
/// A single paused preview lets users compare saved mixes without starting
/// animation loops in the catalogue or writing defaults during a rebuild.
class _OutfitPreview extends StatelessWidget {
  const _OutfitPreview({required this.settings, required this.preset});
  final ThemeVisualSettings settings;
  final MusicThemePreset preset;

  @override
  Widget build(BuildContext context) {
    final ip = decorationIp(settings.progressCharacter, preset);
    final size = progressCompanionSize(ip);
    return ExcludeSemantics(
      child: SizedBox(
        height: 72,
        child: LayoutBuilder(
          builder: (context, bounds) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 16,
                right: 16,
                top: 36,
                child: ProgressTrackPreview(
                  ip: decorationIp(settings.progressStyle, preset),
                ),
              ),
              if (ip == MusicThemeIp.classic)
                Positioned(
                  left: 16 + (bounds.maxWidth - 32) * .68 - 4.5,
                  top: 43.5,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: progressTrackColorForIp(
                        decorationIp(settings.progressStyle, preset),
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              else
                Positioned(
                  left:
                      16 +
                      progressCompanionLeft(
                        progress: .68,
                        availableWidth: bounds.maxWidth - 32,
                        companionWidth: size.width,
                      ),
                  top: progressCompanionTop(ip, trackCenterY: 48),
                  child: ip == MusicThemeIp.shinchan
                      ? ShinchanProgressWalker(
                          width: size.width,
                          presetId: preset.id,
                          weather: settings.shinchanWeather,
                          playing: false,
                        )
                      : IpProgressCompanion(ip: ip, playing: false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
