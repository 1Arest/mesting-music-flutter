import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_output_controller.dart';
import '../../../core/audio/media_volume_controller.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_glass_popover.dart';
import '../../../shared/widgets/beta_icon_button.dart';
import 'apple_audio_glyphs.dart';
import 'apple_output_volume_slider.dart';
import 'player_output_routes.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../themes/music_typography.dart';

/// The app owns this presentation; Android owns the real device transfer.
/// Do not list paired devices as available routes or pretend a transfer worked.
Future<void> showPlayerOutputDialog(BuildContext context, WidgetRef ref) async {
  await ref.read(audioOutputProvider.notifier).refresh();
  if (!context.mounted) return;
  final switchDevice = await showBetaGlassDialog<bool>(
    context: context,
    builder: (_) => const PlayerOutputDialog(),
  );
  if (switchDevice != true || !context.mounted) return;
  try {
    await ref.read(audioOutputProvider.notifier).choose();
  } catch (error) {
    if (context.mounted) showPlatformFailure(context, error);
  }
}

class PlayerOutputDialog extends ConsumerStatefulWidget {
  const PlayerOutputDialog({super.key});
  @override
  ConsumerState<PlayerOutputDialog> createState() => _PlayerOutputDialogState();
}

class _PlayerOutputDialogState extends ConsumerState<PlayerOutputDialog> {
  double? _drag;
  // Beta opens the real device list immediately; Formal keeps its existing
  // summary followed by the platform picker. This never initiates a transfer.
  final bool _devices = DistributionChannel.isBeta;
  @override
  Widget build(BuildContext context) {
    final output = ref.watch(audioOutputProvider);
    final volume = ref.watch(mediaVolumeProvider);
    final track = ref.watch(currentTrackProvider);
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onSurface;
    final blue = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF78B4FF)
        : const Color(0xFF0069D5);
    return Dialog(
      key: const ValueKey('apple-output-picker'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: BetaGlassMenuSurface(
          radius: 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _devices ? '播放设备' : '音频输出',
                              style: TextStyle(
                                fontSize: MusicTypography.sectionTitleSize,
                                fontWeight: MusicTypography.titleWeight,
                                color: ink,
                              ),
                            ),
                          ),
                          BetaIconButton(
                            key: const ValueKey('output-close'),
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(false),
                            icon: Icon(
                              CupertinoIcons.xmark_circle_fill,
                              color: ink.withValues(alpha: .6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ArtworkImage(
                              uri: track.coverAsset,
                              width: 58,
                              height: 58,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: MusicTypography.bodySize,
                                    fontWeight: MusicTypography.titleWeight,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: ink.withValues(alpha: .7),
                                    fontSize: MusicTypography.subheadlineSize,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      if (_devices)
                        const PlayerOutputRoutes()
                      else
                        Row(
                          children: [
                            AppleAudioGlyph(
                              output.local
                                  ? AppleAudioGlyphKind.phone
                                  : output.headphones
                                  ? AppleAudioGlyphKind.earphones
                                  : AppleAudioGlyphKind.speakerLoud,
                              size: 40,
                              color: blue,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    output.name,
                                    key: const ValueKey(
                                      'output-current-device',
                                    ),
                                    style: TextStyle(
                                      color: ink,
                                      fontSize: MusicTypography.headingSize,
                                      fontWeight: MusicTypography.titleWeight,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    output.available ? '当前播放设备' : '设备状态暂不可用',
                                    style: TextStyle(
                                      color: ink.withValues(alpha: .7),
                                      fontSize: MusicTypography.footnoteSize,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (output.available)
                              AppleAudioGlyph(
                                AppleAudioGlyphKind.check,
                                color: blue,
                                size: 28,
                              ),
                          ],
                        ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            '音量',
                            style: TextStyle(
                              color: ink.withValues(alpha: .7),
                              fontSize: MusicTypography.footnoteSize,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            volume.available
                                ? '${((_drag ?? volume.value) * 100).round()}%'
                                : '暂不可调',
                            style: TextStyle(
                              color: ink.withValues(alpha: .7),
                              fontSize: MusicTypography.footnoteSize,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          AppleAudioGlyph(
                            AppleAudioGlyphKind.speakerQuiet,
                            color: ink.withValues(alpha: .65),
                            size: 20,
                          ),
                          Expanded(
                            child: Semantics(
                              label: '系统媒体音量',
                              child: AppleOutputVolumeSlider(
                                key: const ValueKey('output-volume-slider'),
                                value: _drag ?? volume.value,
                                ink: ink,
                                onChanged: !volume.available
                                    ? null
                                    : (value) {
                                        setState(() => _drag = value);
                                        ref
                                            .read(mediaVolumeProvider.notifier)
                                            .setVolume(value);
                                      },
                                onChangeEnd: !volume.available
                                    ? null
                                    : (value) async {
                                        await ref
                                            .read(mediaVolumeProvider.notifier)
                                            .setVolume(value);
                                        if (mounted) {
                                          setState(() => _drag = null);
                                        }
                                      },
                              ),
                            ),
                          ),
                          AppleAudioGlyph(
                            AppleAudioGlyphKind.speakerLoud,
                            color: ink.withValues(alpha: .65),
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Keep the primary action visible even in a short landscape card.
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CupertinoButton(
                      key: const ValueKey('output-open-system-picker'),
                      color: const Color(0xFF0069D5),
                      borderRadius: BorderRadius.circular(25),
                      onPressed: _devices || output.available
                          ? () {
                              if (_devices) {
                                Navigator.of(context).pop(false);
                              } else {
                                Navigator.of(context).pop(true);
                              }
                            }
                          : null,
                      child: Text(
                        _devices ? '完成' : '切换设备',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
