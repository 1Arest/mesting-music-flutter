import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/distribution_channel.dart';
import '../../shared/widgets/beta_glass_controls.dart';
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

class ProgressDecorationPicker extends ConsumerStatefulWidget {
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
  ConsumerState<ProgressDecorationPicker> createState() =>
      _ProgressDecorationPickerState();
}

/// Category filtering never edits the selected outfit. Scene expansion belongs
/// to the Shin-chan row; its saved weather still belongs to the theme owner.
class _ProgressDecorationPickerState
    extends ConsumerState<ProgressDecorationPicker> {
  String _series = '全部';
  bool _scenesOpen = true;

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
    final selected = widget.selected;
    final character = widget.character;
    final preset = widget.preset;
    final onSelected = widget.onSelected;
    final fontSize = MediaQuery.textScalerOf(
      context,
    ).scale(MusicTypography.captionSize);
    final minimumCardWidth = 62 + fontSize * 4.8;
    if (character) {
      final choices = _series == '全部'
          ? groups.values.expand((values) => values).toList()
          : groups[_series] ?? const <ProgressDecoration>[];
      final settings = ref.watch(themeVisualSettingsProvider);
      final weather =
          settings.shinchanWeather ??
          shinchanWeatherForPreset((preset ?? musicThemePresets.first).id);
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < minimumCardWidth * 2 + 9
              ? 1
              : 2;
          final height = 36 + fontSize * 2.6;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                key: const ValueKey('progress-series-filter'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    for (final series in ['全部', ...groups.keys])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Semantics(
                          selected: _series == series,
                          child: BetaGlassButton(
                            key: ValueKey('progress-series-$series'),
                            height: 44,
                            blue: _series == series,
                            horizontalPadding: 14,
                            onPressed: () => setState(() => _series = series),
                            child: Text(series),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (var start = 0; start < choices.length; start += columns) ...[
                SizedBox(
                  height: height,
                  child: Row(
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const SizedBox(width: 9),
                        Expanded(
                          child: start + column >= choices.length
                              ? const SizedBox.shrink()
                              : _DecorationChoice(
                                  key: ValueKey(
                                    'progress-character-${choices[start + column].name}',
                                  ),
                                  value: choices[start + column],
                                  preset: preset ?? musicThemePresets.first,
                                  active: selected == choices[start + column],
                                  character: true,
                                  subtitle:
                                      DistributionChannel.isBeta &&
                                          choices[start + column] ==
                                              ProgressDecoration.shinchan &&
                                          selected ==
                                              ProgressDecoration.shinchan
                                      ? '${weather.label} · 7 种场景'
                                      : progressDecorationSeries(
                                          choices[start + column],
                                        ),
                                  expanded:
                                      DistributionChannel.isBeta &&
                                          choices[start + column] ==
                                              ProgressDecoration.shinchan &&
                                          selected ==
                                              ProgressDecoration.shinchan
                                      ? _scenesOpen
                                      : null,
                                  onTap: () {
                                    final value = choices[start + column];
                                    if (DistributionChannel.isBeta &&
                                        value == ProgressDecoration.shinchan) {
                                      setState(
                                        () => _scenesOpen =
                                            selected != value || !_scenesOpen,
                                      );
                                      if (selected == value) return;
                                    }
                                    onSelected(value);
                                  },
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                if (DistributionChannel.isBeta &&
                    _scenesOpen &&
                    selected == ProgressDecoration.shinchan &&
                    choices.skip(start).take(columns).contains(selected))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DecoratedBox(
                      key: const ValueKey('progress-shinchan-scenes'),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: ShinchanWeatherPicker(
                          selected: weather,
                          onCollapse: () => setState(() => _scenesOpen = false),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      );
    }
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
  const ShinchanWeatherPicker({
    required this.selected,
    this.onCollapse,
    super.key,
  });
  final ShinchanProgressWeather selected;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '小新场景',
              style: TextStyle(
                fontSize: MusicTypography.calloutSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
          ),
          if (onCollapse != null)
            TextButton.icon(
              onPressed: onCollapse,
              icon: const Icon(Icons.expand_less_rounded),
              label: const Text('收起'),
            ),
        ],
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
            Semantics(
              selected: weather == selected,
              child: BetaGlassButton(
                key: ValueKey('shinchan-weather-${weather.name}'),
                blue: weather == selected,
                height: 44,
                horizontalPadding: 14,
                onPressed: () async {
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
                child: Text(weather.label),
              ),
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
    this.subtitle,
    this.expanded,
    super.key,
  });

  final ProgressDecoration value;
  final MusicThemePreset preset;
  final bool active;
  final bool character;
  final VoidCallback onTap;
  final String? subtitle;
  final bool? expanded;

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
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(label, tokens.textPrimary),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: MusicTypography.captionSize - 1,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 3),
                      Icon(
                        expanded == null
                            ? Icons.check_circle_rounded
                            : expanded!
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 17,
                        color: selectionAccent,
                      ),
                    ],
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
        'assets/images/theme_gallery/shinchan-avatar-v2.webp',
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
