import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/distribution_channel.dart';
import '../../shared/widgets/music_notice.dart';
import '../player/presentation/ip_progress_decoration.dart';
import '../player/presentation/shinchan_progress_walker.dart';
import '../player/presentation/uploaded_progress_portrait.dart';
import 'beta_appearance.dart';
import 'music_theme_preset.dart';
import 'music_theme_tokens.dart';
import 'music_typography.dart';
import 'theme_controller.dart';
import 'theme_follow_icons.dart';

class ProgressDecorationPicker extends StatelessWidget {
  const ProgressDecorationPicker({
    required this.selected,
    required this.character,
    required this.onSelected,
    this.preset,
    super.key,
  });

  final ProgressDecoration selected;
  final bool character;
  final MusicThemePreset? preset;
  final ValueChanged<ProgressDecoration> onSelected;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ProgressDecoration>>{};
    for (final value in ProgressDecoration.values) {
      if (DistributionChannel.isBeta &&
          value == ProgressDecoration.followTheme) {
        continue;
      }
      final series = progressDecorationSeries(value);
      groups.putIfAbsent(series, () => []).add(value);
    }
    final fontSize = MediaQuery.textScalerOf(
      context,
    ).scale(MusicTypography.captionSize);
    final minimumCardWidth = 66 + fontSize * 6;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                group.key,
                style: TextStyle(
                  fontSize: MusicTypography.footnoteSize,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: group.value.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth < minimumCardWidth * 2 + 9
                    ? 1
                    : 2,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
                mainAxisExtent:
                    (character ? 32 : 48) +
                    MediaQuery.textScalerOf(context).scale(13) * 1.4,
              ),
              itemBuilder: (context, index) {
                final value = group.value[index];
                return _DecorationChoice(
                  key: ValueKey(
                    '${character ? 'progress-character' : 'progress-track'}-${value.name}',
                  ),
                  value: value,
                  preset: preset ?? musicThemePresets.first,
                  active: selected == value,
                  character: character,
                  onTap: () => onSelected(value),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Only the selected weather animates. Choices are static, so opening settings
/// does not start seven independent character/weather tickers.
class ShinchanWeatherPicker extends ConsumerWidget {
  const ShinchanWeatherPicker({required this.selected, super.key});
  final ShinchanProgressWeather selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '小新天气',
        style: TextStyle(
          fontSize: MusicTypography.calloutSize,
          fontWeight: MusicTypography.bodyWeight,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        '手动选择，重启后保留。',
        style: TextStyle(
          fontSize: MusicTypography.footnoteSize,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final weather in ShinchanProgressWeather.values)
            ChoiceChip(
              key: ValueKey('shinchan-weather-${weather.name}'),
              label: Text(weather.label),
              selected: weather == selected,
              onSelected: (_) async {
                try {
                  await ref
                      .read(themeVisualSettingsProvider.notifier)
                      .setShinchanWeather(weather);
                } on Object {
                  if (context.mounted) {
                    showMusicNotice(
                      context,
                      icon: Icons.error_outline_rounded,
                      title: '天气未保存',
                      message: '请稍后重试',
                    );
                  }
                }
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
      Center(
        child: RepaintBoundary(
          child: ShinchanProgressWalker(
            key: const ValueKey('shinchan-weather-preview'),
            presetId: 'classic',
            weather: selected,
            playing: true,
            width: 104,
          ),
        ),
      ),
    ],
  );
}

class _DecorationChoice extends StatelessWidget {
  const _DecorationChoice({
    required this.value,
    required this.preset,
    required this.active,
    required this.character,
    required this.onTap,
    super.key,
  });

  final ProgressDecoration value;
  final MusicThemePreset preset;
  final bool active;
  final bool character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final selectionAccent = DistributionChannel.isBeta
        ? BetaAppearance.accent(Theme.of(context).brightness)
        : const Color(0xFF6C80EA);
    final label = character
        ? switch (value) {
            ProgressDecoration.followTheme => '跟随皮肤',
            ProgressDecoration.classic => '经典圆点',
            ProgressDecoration.shinchan => '蜡笔小新',
            ProgressDecoration.helloKitty => 'Hello Kitty',
            ProgressDecoration.kuromi => '库洛米',
            _ => progressDecorationLabel(value),
          }
        : progressDecorationLabel(value);
    return Material(
      color: active
          ? Color.alphaBlend(
              selectionAccent.withValues(alpha: .12),
              tokens.glassSubtle,
            )
          : tokens.glassSubtle,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? selectionAccent.withValues(alpha: .62)
                  : tokens.border,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: selectionAccent.withValues(alpha: .12),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: character
              ? Row(
                  children: [
                    _DecorationChoiceIcon(value: value, character: true),
                    const SizedBox(width: 9),
                    Expanded(child: _label(label, tokens.textPrimary)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _label('$label轨道', tokens.textPrimary),
                    ProgressTrackPreview(ip: decorationIp(value, preset)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _label(String label, Color color) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: color,
      fontSize: MusicTypography.captionSize,
      fontWeight: MusicTypography.bodyWeight,
    ),
  );
}

class _DecorationChoiceIcon extends StatelessWidget {
  const _DecorationChoiceIcon({required this.value, required this.character});

  final ProgressDecoration value;
  final bool character;

  @override
  Widget build(BuildContext context) {
    final ip = decorationIp(value, musicThemePresets.first);
    if (ip == MusicThemeIp.nailong) {
      return SizedBox(
        width: 26,
        height: 26,
        child: Image.asset(
          companionAssetForIp(ip)!,
          fit: BoxFit.contain,
          cacheHeight: 96,
        ),
      );
    }
    if (isUploadedProgressIp(ip)) {
      return SizedBox(
        width: 26,
        height: 26,
        child: UploadedProgressPortrait(ip: ip),
      );
    }
    final asset = switch (value) {
      ProgressDecoration.shinchan =>
        'assets/images/theme_gallery/shinchan-avatar-v2.png',
      ProgressDecoration.helloKitty =>
        'assets/images/theme_gallery/hello-kitty-progress-head.png',
      ProgressDecoration.kuromi =>
        'assets/images/theme_gallery/kuromi-progress-head.png',
      _ => null,
    };
    if (asset != null) {
      final background = switch (value) {
        ProgressDecoration.shinchan => const Color(0xFFFFE2BD),
        ProgressDecoration.helloKitty => const Color(0xFFF0F4FF),
        ProgressDecoration.kuromi => const Color(0xFFF1D9ED),
        _ => Colors.white,
      };
      return Container(
        width: 26,
        height: 26,
        padding: const EdgeInsets.all(1),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          cacheWidth: 80,
          excludeFromSemantics: true,
        ),
      );
    }
    final follow = value == ProgressDecoration.followTheme;
    if (follow) {
      return ThemeFollowIcon(
        kind: character
            ? ThemeFollowIconKind.progressCharacter
            : ThemeFollowIconKind.progressStyle,
      );
    }
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFF314055), Color(0xFF111923)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29222A3A),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
    );
  }
}

/// Reuses the player track painter so previews include the actual IP motifs.
/// Static previews do not start Nailong or weather animation tickers.
class ProgressTrackPreview extends StatelessWidget {
  const ProgressTrackPreview({required this.ip, super.key});
  final MusicThemeIp ip;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox(
        height: 24,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: ip == MusicThemeIp.classic ? 2 : ipProgressTrackHeight,
            trackShape: ip == MusicThemeIp.classic
                ? const RoundedRectSliderTrackShape()
                : IpProgressTrackShape(ip: ip),
            activeTrackColor: progressTrackColorForIp(ip),
            inactiveTrackColor: Theme.of(context).colorScheme.outlineVariant,
            thumbShape: SliderComponentShape.noThumb,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: .68,
            padding: EdgeInsets.zero,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}
