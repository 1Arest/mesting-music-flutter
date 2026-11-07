import 'player_toolbar_glyphs.dart';
import 'player_output_dialog.dart';
import '../../music_platform/presentation/platform_quality_button.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/player_comment_glyph.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/media_volume_controller.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../shared/utils/duration_format.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../auth/presentation/beta_login_navigation.dart';
import '../../music_platform/presentation/platform_comments_page.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../../core/audio/audio_output_controller.dart';
import '../../player/presentation/ip_progress_decoration.dart';
import '../../player/presentation/shinchan_progress_walker.dart';
import '../../queue/presentation/queue_page.dart';
import '../../themes/theme_controller.dart';
import '../../themes/music_theme_preset.dart';

/// CONTRACT: Apple Music transport from the user's pinned reference. All five
/// Beta styles share this exact component: progress, naked white glyphs, system
/// media volume, then lyrics / audio output / current queue. IP rail and character
/// preferences are independent decoration, never an alternate control layout.
class ApplePlayerControls extends ConsumerStatefulWidget {
  const ApplePlayerControls({
    this.lyricsActive = false,
    this.queueActive = false,
    this.onToggleLyrics,
    this.onToggleQueue,
    super.key,
  });
  final bool lyricsActive, queueActive;
  final VoidCallback? onToggleLyrics, onToggleQueue;
  @override
  ConsumerState<ApplePlayerControls> createState() =>
      _ApplePlayerControlsState();
}

class _ApplePlayerControlsState extends ConsumerState<ApplePlayerControls> {
  double? _scrub, _volumeDrag;
  String? _trackId;
  Future<void> _act(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (mounted) showPlatformFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    if (_trackId != track.id) {
      _trackId = track.id;
      _scrub = null;
    }
    final handler = ref.watch(audioHandlerProvider);
    final playback = ref.watch(playbackStateProvider).value;
    final playing = playback?.playing ?? false;
    final busy = playback?.processingState == AudioProcessingState.loading;
    final sourceReady =
        playback?.processingState == AudioProcessingState.ready ||
        playback?.processingState == AudioProcessingState.buffering ||
        playback?.processingState == AudioProcessingState.completed;
    final measuredPosition = ref.watch(positionProvider).value;
    final measuredDuration = ref.watch(durationProvider).value;
    final position = sourceReady
        ? measuredPosition ?? Duration.zero
        : Duration.zero;
    final duration = sourceReady
        ? measuredDuration ?? track.duration
        : track.duration;
    final maximum = duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final value = (_scrub ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      maximum,
    );
    final visual = ref.watch(themeVisualSettingsProvider);
    final preset = ref.watch(effectiveMusicThemeProvider);
    final railIp = decorationIp(visual.progressStyle, preset);
    final characterIp = decorationIp(visual.progressCharacter, preset);
    final classic = railIp == MusicThemeIp.classic;
    final volume = ref.watch(mediaVolumeProvider);
    final output = widget.onToggleLyrics != null
        ? ref.watch(audioOutputProvider)
        : const AudioOutput();
    final order =
        ref.watch(playbackOrderProvider).value ?? handler.playbackOrder;
    return Padding(
      key: const ValueKey('apple-player-controls'),
      // Reserve real layout space above the thumb. Shrinking artwork alone
      // cannot stop a negative-positioned companion from covering artist text.
      padding: EdgeInsets.fromLTRB(
        26,
        characterIp == MusicThemeIp.classic ? 6 : 30,
        26,
        8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 42,
            child: LayoutBuilder(
              builder: (context, box) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: classic ? 5 : ipProgressTrackHeight,
                          trackShape: classic
                              ? const RoundedRectSliderTrackShape()
                              : IpProgressTrackShape(ip: railIp),
                          activeTrackColor: classic
                              ? const Color(0xD9FFFFFF)
                              : progressTrackColorForIp(railIp),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          // Beta's rail stays draggable and accessible without
                          // a painted thumb; IP companions retain their layout.
                          thumbShape:
                              widget.onToggleLyrics == null &&
                                  characterIp == MusicThemeIp.classic
                              ? RoundSliderThumbShape(
                                  enabledThumbRadius: _scrub == null ? 2.5 : 5,
                                )
                              : SliderComponentShape.noThumb,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: MergeSemantics(
                          key: const ValueKey('playback-seek-semantics'),
                          child: Semantics(
                            label: '播放进度',
                            child: Slider(
                              semanticFormatterCallback: (milliseconds) =>
                                  '${_spokenTime(Duration(milliseconds: milliseconds.round()))}，共${_spokenTime(duration)}',
                              key: const ValueKey('playback-seek-slider'),
                              padding: EdgeInsets.zero,
                              value: value,
                              max: maximum,
                              onChangeStart: duration > Duration.zero
                                  ? (v) => setState(() => _scrub = v)
                                  : null,
                              onChanged: duration > Duration.zero
                                  ? (v) => setState(() => _scrub = v)
                                  : null,
                              onChangeEnd: duration > Duration.zero
                                  ? (v) async {
                                      appHaptic(context, AppHapticEvent.impact);
                                      await _act(
                                        () => handler.seek(
                                          Duration(milliseconds: v.round()),
                                        ),
                                      );
                                      if (mounted && _trackId == track.id) {
                                        setState(() => _scrub = null);
                                      }
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (characterIp == MusicThemeIp.shinchan)
                      Positioned(
                        left: progressCompanionLeft(
                          progress: value / maximum,
                          availableWidth: box.maxWidth,
                          companionWidth: 56,
                        ),
                        top: progressCompanionTop(
                          characterIp,
                          trackCenterY: box.maxHeight / 2,
                          trackHeight: classic ? 5 : ipProgressTrackHeight,
                        ),
                        child: IgnorePointer(
                          child: ShinchanProgressWalker(
                            presetId: preset.id,
                            weather: visual.shinchanWeather,
                            width: 56,
                            playing: playing,
                          ),
                        ),
                      ),
                    if (characterIp == MusicThemeIp.helloKitty ||
                        characterIp == MusicThemeIp.kuromi)
                      Positioned(
                        left: progressCompanionLeft(
                          progress: value / maximum,
                          availableWidth: box.maxWidth,
                          companionWidth: progressCompanionSize(
                            characterIp,
                          ).width,
                        ),
                        top: progressCompanionTop(
                          characterIp,
                          trackCenterY: box.maxHeight / 2,
                        ),
                        child: IgnorePointer(
                          child: IpProgressCompanion(
                            ip: characterIp,
                            playing: playing,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(Duration(milliseconds: value.round())),
                key: const ValueKey('playback-elapsed-time'),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              Text(
                '-${formatDuration(Duration(milliseconds: (maximum - value).round()))}',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Transport(
                label: '上一首',
                icon: CupertinoIcons.backward_fill,
                size: 35,
                onPressed: () => _act(handler.skipToPrevious),
              ),
              SizedBox(
                width: 84,
                height: 74,
                child: busy
                    ? const Center(
                        child: CupertinoActivityIndicator(color: Colors.white),
                      )
                    : _Transport(
                        label: playing ? '暂停' : '播放',
                        icon: playing
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        size: 49,
                        onPressed: () => _act(handler.togglePlayPause),
                      ),
              ),
              _Transport(
                label: '下一首',
                icon: CupertinoIcons.forward_fill,
                size: 35,
                onPressed: () => _act(handler.skipToNext),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                CupertinoIcons.volume_down,
                color: Colors.white54,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: Colors.white60,
                      inactiveTrackColor: Colors.white24,
                      disabledActiveTrackColor: Colors.white24,
                      disabledInactiveTrackColor: Colors.white12,
                      thumbShape: SliderComponentShape.noThumb,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: MergeSemantics(
                      key: const ValueKey('media-volume-semantics'),
                      child: Semantics(
                        label: '系统媒体音量',
                        child: Slider(
                          semanticFormatterCallback: (value) =>
                              '${(value * 100).round()}%',
                          key: const ValueKey('system-media-volume'),
                          padding: EdgeInsets.zero,
                          value: _volumeDrag ?? volume.value,
                          onChangeStart: volume.available
                              ? (v) => setState(() => _volumeDrag = v)
                              : null,
                          onChanged: volume.available
                              ? (v) {
                                  setState(() => _volumeDrag = v);
                                  ref
                                      .read(mediaVolumeProvider.notifier)
                                      .setVolume(v);
                                }
                              : null,
                          onChangeEnd: volume.available
                              ? (v) async {
                                  await ref
                                      .read(mediaVolumeProvider.notifier)
                                      .setVolume(v);
                                  if (mounted) {
                                    setState(() => _volumeDrag = null);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                CupertinoIcons.volume_up,
                color: Colors.white54,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Transport(
                label: widget.onToggleLyrics != null ? '显示或隐藏歌词' : '歌曲评论',
                glyph: widget.onToggleLyrics != null
                    ? PlayerToolbarGlyph(
                        tool: PlayerToolbarTool.lyrics,
                        active: widget.lyricsActive,
                      )
                    : const PlayerCommentGlyph(),
                icon: CupertinoIcons.text_quote,
                size: 26,
                onPressed:
                    widget.onToggleLyrics ??
                    () async {
                      if (ref.read(platformAccountProvider).value == null) {
                        await openBetaLogin(context, redirect: '/player');
                        if (!context.mounted) return;
                      }
                      if (context.mounted) {
                        await openPlatformSongComments(context, ref, track);
                      }
                    },
              ),
              if (widget.onToggleLyrics == null)
                const PlatformQualityButton(inline: true)
              else
                _Transport(
                  label: '音频输出，${output.name}',
                  glyph: PlayerToolbarGlyph(
                    key: const ValueKey('player-output-glyph'),
                    tool: PlayerToolbarTool.output,
                    headphones: output.headphones,
                    local: output.local,
                  ),
                  icon: output.headphones
                      ? Icons.headphones_rounded
                      : Icons.airplay_rounded,
                  size: 25,
                  onPressed: () => showPlayerOutputDialog(context, ref),
                ),
              _Transport(
                label: '播放队列',
                value: order.label,
                glyph: widget.onToggleQueue != null
                    ? PlayerToolbarGlyph(
                        tool: PlayerToolbarTool.queue,
                        active: widget.queueActive,
                        order: order,
                      )
                    : null,
                icon: CupertinoIcons.list_bullet,
                size: 27,
                onPressed:
                    widget.onToggleQueue ??
                    () => showPlaybackQueueSheet(context),
              ),
            ],
          ),
          if (widget.onToggleLyrics != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: Center(
                child: Text(
                  output.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.label,
    required this.icon,
    required this.size,
    required this.onPressed,
    this.glyph,
    this.value,
  });
  final String label;
  final IconData icon;
  final double size;
  final VoidCallback onPressed;
  final Widget? glyph;
  final String? value;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    value: value,
    child: Tooltip(
      message: label,
      child: CupertinoButton(
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(48, 48),
        onPressed: () {
          appHaptic(context, AppHapticEvent.selection);
          onPressed();
        },
        child: glyph ?? Icon(icon, size: size, color: Colors.white),
      ),
    ),
  );
}

String _spokenTime(Duration value) =>
    '${value.inMinutes}分${value.inSeconds.remainder(60)}秒';
