import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_mode.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../themes/theme_controller.dart';
import '../../themes/music_theme_preset.dart';
import '../../queue/presentation/queue_page.dart';
import '../player_visual_style.dart';
import 'ip_progress_decoration.dart';
import 'shinchan_progress_walker.dart';

bool usesClassicProgressThumb(MusicThemeIp ip) => ip == MusicThemeIp.classic;

class PlaybackControls extends ConsumerStatefulWidget {
  const PlaybackControls({
    this.immersive = false,
    this.visualStyle = PlayerVisualStyle.classic,
    this.showElapsed = false,
    this.bottomLift = 0,
    super.key,
  });

  final bool immersive;
  final PlayerVisualStyle visualStyle;
  final bool showElapsed;
  final double bottomLift;

  @override
  ConsumerState<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends ConsumerState<PlaybackControls> {
  double? _scrubMilliseconds;

  IconData _modeIcon(PlaybackMode mode) => switch (mode) {
    PlaybackMode.list => Icons.repeat_rounded,
    PlaybackMode.single => Icons.repeat_one_rounded,
    PlaybackMode.random => Icons.shuffle_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final state = ref.watch(playbackStateProvider).value;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = ref.watch(durationProvider).value ?? Duration.zero;
    final mode = ref.watch(playbackModeProvider).value ?? PlaybackMode.list;
    final playing = state?.playing ?? false;
    final musicTheme = ref.watch(effectiveMusicThemeProvider);
    final visualSettings = ref.watch(themeVisualSettingsProvider);
    final busy =
        state?.processingState == AudioProcessingState.loading ||
        state?.processingState == AudioProcessingState.buffering;
    final unavailable = state?.processingState == AudioProcessingState.error;
    final maxMilliseconds = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final canSeek = duration.inMilliseconds > 0;
    final streamValue = canSeek
        ? position.inMilliseconds.toDouble().clamp(0.0, maxMilliseconds)
        : 0.0;
    final value = (_scrubMilliseconds ?? streamValue).clamp(
      0.0,
      maxMilliseconds,
    );
    if (!widget.immersive) {
      return const SizedBox.shrink();
    }

    final styleAccent = switch (widget.visualStyle) {
      PlayerVisualStyle.cover ||
      PlayerVisualStyle.classic => const Color(0xFF5F75DE),
      PlayerVisualStyle.aurora => const Color(0xFF73E0FF),
      PlayerVisualStyle.cassette => const Color(0xFFA78BFA),
      PlayerVisualStyle.lyricStage => const Color(0xFF5EEAD4),
    };
    final dockColor = switch (widget.visualStyle) {
      PlayerVisualStyle.cover ||
      PlayerVisualStyle.classic => Colors.transparent,
      PlayerVisualStyle.aurora => const Color(0x221D397A),
      PlayerVisualStyle.cassette => const Color(0x4D17123C),
      PlayerVisualStyle.lyricStage => const Color(0x4D102F3B),
    };
    final dockRadius = widget.visualStyle == PlayerVisualStyle.classic
        ? BorderRadius.zero
        : const BorderRadius.vertical(top: Radius.circular(30));

    final bottomLift = widget.bottomLift.clamp(0.0, 48.0);
    return Container(
      key: const ValueKey('playback-controls-dock'),
      height: 150 + bottomLift,
      padding: EdgeInsets.fromLTRB(10, 12, 10, 18 + bottomLift),
      decoration: BoxDecoration(
        color: dockColor,
        borderRadius: dockRadius,
        border: widget.visualStyle == PlayerVisualStyle.classic
            ? null
            : Border(
                top: BorderSide(color: styleAccent.withValues(alpha: .22)),
              ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: .33),
            Colors.black.withValues(alpha: .62),
          ],
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            key: const ValueKey('playback-seek-touch-target'),
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final progress = value / maxMilliseconds;
                final characterIp = decorationIp(
                  visualSettings.progressCharacter,
                  musicTheme,
                );
                final progressIp = decorationIp(
                  visualSettings.progressStyle,
                  musicTheme,
                );
                final progressColor = progressTrackColorForIp(progressIp);
                final effectiveProgressColor =
                    visualSettings.progressStyle ==
                            ProgressDecoration.followTheme &&
                        progressIp == MusicThemeIp.classic &&
                        widget.visualStyle != PlayerVisualStyle.classic
                    ? styleAccent
                    : progressColor;
                final showClassicThumb = usesClassicProgressThumb(characterIp);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (busy)
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 14,
                        height: 20,
                        child: _BufferingPulseTrack(
                          color: effectiveProgressColor,
                        ),
                      )
                    else
                      Positioned.fill(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: progressIp == MusicThemeIp.classic
                                ? 2
                                : ipProgressTrackHeight,
                            trackShape: progressIp == MusicThemeIp.classic
                                ? const RoundedRectSliderTrackShape()
                                : IpProgressTrackShape(ip: progressIp),
                            activeTrackColor: effectiveProgressColor,
                            inactiveTrackColor: Colors.white.withValues(
                              alpha: .22,
                            ),
                            thumbColor: Colors.white,
                            thumbShape: showClassicThumb
                                ? RoundSliderThumbShape(
                                    enabledThumbRadius:
                                        _scrubMilliseconds == null ? 4.5 : 6.5,
                                  )
                                : SliderComponentShape.noThumb,
                            overlayShape: SliderComponentShape.noOverlay,
                          ),
                          child: Slider(
                            key: const ValueKey('playback-seek-slider'),
                            value: value,
                            max: maxMilliseconds,
                            onChangeStart: canSeek
                                ? (next) => setState(
                                    () => _scrubMilliseconds = next.clamp(
                                      0.0,
                                      maxMilliseconds,
                                    ),
                                  )
                                : null,
                            onChanged: canSeek
                                ? (next) => setState(
                                    () => _scrubMilliseconds = next.clamp(
                                      0.0,
                                      maxMilliseconds,
                                    ),
                                  )
                                : null,
                            onChangeEnd: canSeek
                                ? (next) async {
                                    final target = next.clamp(
                                      0.0,
                                      maxMilliseconds,
                                    );
                                    setState(() => _scrubMilliseconds = target);
                                    await handler.seek(
                                      Duration(milliseconds: target.round()),
                                    );
                                    if (mounted) {
                                      setState(() => _scrubMilliseconds = null);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ),
                    if (!busy &&
                        (characterIp == MusicThemeIp.helloKitty ||
                            characterIp == MusicThemeIp.kuromi))
                      Positioned(
                        left: progressCompanionLeft(
                          progress: progress,
                          availableWidth: constraints.maxWidth,
                          companionWidth: progressCompanionSize(
                            characterIp,
                          ).width,
                        ),
                        top: progressCompanionTop(characterIp),
                        child: IgnorePointer(
                          child: IpProgressCompanion(
                            ip: characterIp,
                            playing: playing,
                          ),
                        ),
                      ),
                    if (!busy && characterIp == MusicThemeIp.shinchan)
                      Positioned(
                        left: progressCompanionLeft(
                          progress: progress,
                          availableWidth: constraints.maxWidth,
                          companionWidth: 104,
                        ),
                        top: progressCompanionTop(
                          characterIp,
                          trackCenterY: constraints.maxHeight / 2,
                          trackHeight: progressIp == MusicThemeIp.classic
                              ? 2
                              : ipProgressTrackHeight,
                          companionSize: ShinchanProgressWalker.sizeForWidth(
                            104,
                          ),
                        ),
                        child: IgnorePointer(
                          child: ShinchanProgressWalker(
                            presetId: musicTheme.id,
                            playing: playing,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: Stack(
              children: [
                if (busy)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '正在缓冲',
                      key: const ValueKey('playback-buffering-label'),
                      style: _metaStyle.copyWith(
                        color: styleAccent.withValues(alpha: .9),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else if (unavailable)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '音源不可用',
                      key: const ValueKey('playback-source-unavailable-label'),
                      style: _metaStyle.copyWith(
                        color: styleAccent.withValues(alpha: .9),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else if (widget.showElapsed)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatDuration(Duration(milliseconds: value.round())),
                      key: const ValueKey('playback-elapsed-time'),
                      style: _metaStyle,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    (busy || unavailable) && duration == Duration.zero
                        ? '--:--'
                        : formatDuration(duration),
                    style: _metaStyle,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _DockButton(
                tooltip: mode.label,
                icon: _modeIcon(mode),
                onTap: () async {
                  final nextMode = mode.next;
                  await handler.cyclePlaybackMode();
                  if (!context.mounted) return;
                  showMusicNotice(
                    context,
                    icon: _modeIcon(nextMode),
                    title: nextMode.label,
                    message: '播放模式已切换',
                  );
                },
                visualStyle: widget.visualStyle,
                accent: styleAccent,
              ),
              _DockButton(
                tooltip: '上一首',
                icon: Icons.skip_previous_rounded,
                iconSize: 31,
                onTap: handler.skipToPrevious,
                visualStyle: widget.visualStyle,
                accent: styleAccent,
              ),
              Material(
                color: widget.visualStyle == PlayerVisualStyle.classic
                    ? Colors.white
                    : styleAccent.withValues(alpha: .16),
                shape: CircleBorder(
                  side: BorderSide(color: styleAccent.withValues(alpha: .7)),
                ),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: .28),
                child: InkWell(
                  key: const ValueKey('playback-primary-control'),
                  customBorder: const CircleBorder(),
                  onTap: busy ? null : handler.togglePlayPause,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: const ValueKey('playback-primary-icon'),
                      color:
                          (widget.visualStyle == PlayerVisualStyle.classic
                                  ? const Color(0xFF211D27)
                                  : Colors.white)
                              .withValues(alpha: busy ? .58 : 1),
                      size: 31,
                    ),
                  ),
                ),
              ),
              _DockButton(
                tooltip: '下一首',
                icon: Icons.skip_next_rounded,
                iconSize: 31,
                onTap: handler.skipToNext,
                visualStyle: widget.visualStyle,
                accent: styleAccent,
              ),
              _DockButton(
                tooltip: '播放列表',
                icon: Icons.queue_music_rounded,
                onTap: () => showPlaybackQueueSheet(context),
                visualStyle: widget.visualStyle,
                accent: styleAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _metaStyle = TextStyle(
  color: Color(0xAFFFFFFF),
  fontSize: 10.8,
  fontWeight: FontWeight.w600,
);

/// 声波脉冲列表示“音频数据正在抵达”，不把没有确定百分比的缓冲误导成
/// 下载进度。绘制被限制在进度条区域，避免影响唱片与控制按钮的帧率。
class _BufferingPulseTrack extends StatefulWidget {
  const _BufferingPulseTrack({required this.color});

  final Color color;

  @override
  State<_BufferingPulseTrack> createState() => _BufferingPulseTrackState();
}

class _BufferingPulseTrackState extends State<_BufferingPulseTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == nextReduceMotion && _controller.isAnimating) return;
    _reduceMotion = nextReduceMotion;
    if (_reduceMotion) {
      _controller.stop();
      _controller.value = .5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('playback-buffering-progress'),
      label: '正在缓冲音乐',
      value: '加载中',
      liveRegion: true,
      child: RepaintBoundary(
        key: const ValueKey('playback-buffering-pulse'),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _BufferingPulsePainter(
              color: widget.color,
              phase: _controller.value,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _BufferingPulsePainter extends CustomPainter {
  const _BufferingPulsePainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 1.25, size.width, 2.5),
      const Radius.circular(99),
    );
    canvas.drawRRect(
      rail,
      Paint()..color = Colors.white.withValues(alpha: .14),
    );

    const pulseCount = 5;
    const pulseWidth = 3.2;
    const pulseGap = 4.6;
    final groupWidth = pulseCount * pulseWidth + (pulseCount - 1) * pulseGap;
    final groupLeft = (size.width + groupWidth) * phase - groupWidth;
    for (var index = 0; index < pulseCount; index++) {
      final x = groupLeft + index * (pulseWidth + pulseGap);
      if (x + pulseWidth < 0 || x > size.width) continue;
      final wave = (math.sin(phase * math.pi * 4 + index * .95) + 1) / 2;
      final height = 6 + wave * 11;
      final opacity = .36 + wave * .58;
      final pulse = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - height) / 2, pulseWidth, height),
        const Radius.circular(99),
      );
      canvas.drawRRect(
        pulse,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BufferingPulsePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.phase != phase;
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconSize = 24,
    required this.visualStyle,
    required this.accent,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final PlayerVisualStyle visualStyle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: visualStyle == PlayerVisualStyle.classic
            ? Colors.transparent
            : accent.withValues(alpha: .025),
        foregroundColor: Color.lerp(Colors.white, accent, .1),
      ),
      icon: Icon(icon, size: iconSize),
    );
  }
}
