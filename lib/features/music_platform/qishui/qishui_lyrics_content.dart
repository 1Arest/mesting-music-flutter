import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../experience/presentation/immersive_lyrics.dart'
    show activeLyricIndexProvider;
import '../../lyrics/domain/lyrics_document.dart';
import '../../lyrics/lyrics_providers.dart';
import '../../lyrics/lyric_timing.dart';
import '../../themes/music_typography.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_feedback.dart';
import 'qishui_player_navigation.dart';

String qishuiLyricTime(Duration time) {
  final safe = time.isNegative ? Duration.zero : time;
  return '${safe.inMinutes.toString().padLeft(2, '0')}:${(safe.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Loading/retry belongs to the lyrics repository. Selection and scrolling
/// below are presentation state and never resolve a second audio stream.
class QishuiLyricsContent extends ConsumerWidget {
  const QishuiLyricsContent({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    return ref
        .watch(currentTimedLyricsProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: MusicActivityIndicator()),
          error: (_, _) => Center(
            child: BetaGlassButton(
              onPressed: () =>
                  ref.invalidate(lyricsProvider(track.resolvedLyricsAsset)),
              child: const Text('歌词暂未读取，点击重试'),
            ),
          ),
          data: (document) => document.lines.isEmpty
              ? const Center(child: Text('汽水暂未提供这首歌的歌词'))
              : QishuiLyricLines(
                  key: ValueKey(track.id),
                  document: document,
                  onReturnToCover: () =>
                      ref.read(qishuiMusicLyricsProvider.notifier).showCover(),
                ),
        );
  }
}

/// Official-reference layout: large left-aligned lines, a strong current line,
/// edge fades and a selected-line time/play cue during manual scrolling.
/// A normal tap returns to the cover; only a browsed selection can seek.
class QishuiLyricLines extends ConsumerStatefulWidget {
  const QishuiLyricLines({
    required this.document,
    this.onReturnToCover,
    super.key,
  });
  final LyricsDocument document;
  final VoidCallback? onReturnToCover;
  @override
  ConsumerState<QishuiLyricLines> createState() => _LyricLinesState();
}

class _LyricLinesState extends ConsumerState<QishuiLyricLines> {
  final _scroll = ScrollController();
  Timer? _resume;
  int? _selected;
  bool _following = true, _jumping = false;
  int _lastActive = -2;
  final _heights = <double>[];
  double _width = 0;
  TextScaler? _scaler;
  LyricsDocument? _measured;

  @override
  void dispose() {
    _resume?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _resumeFollowing() {
    _resume?.cancel();
    if (!mounted) return;
    setState(() {
      _selected = null;
      _following = true;
      _lastActive = -2;
    });
  }

  void _pauseFollowing() {
    _resume?.cancel();
    if (_following) setState(() => _following = false);
  }

  void _selectAt(ScrollMetrics metrics) {
    if (!widget.document.isSynced || _heights.isEmpty) return;
    final offset = metrics.pixels + metrics.viewportDimension / 2 - 28;
    var before = 0.0;
    var index = _heights.length - 1;
    for (var i = 0; i < _heights.length; i++) {
      before += _heights[i];
      if (offset < before) {
        index = i;
        break;
      }
    }
    if (_selected != index) setState(() => _selected = index);
  }

  void _scheduleResume() {
    _resume?.cancel();
    _resume = Timer(const Duration(seconds: 8), _resumeFollowing);
  }

  void _follow(int active, double viewport) {
    if (!_following || active < 0 || active == _lastActive) return;
    _lastActive = active;
    final before = _heights
        .take(active)
        .fold(0.0, (sum, height) => sum + height);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scroll.hasClients ||
          !_following ||
          _lastActive != active) {
        return;
      }
      final target = (before + 28 - viewport * .27).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _jump(int index) async {
    if (_jumping || !widget.document.isSynced) return;
    final track = ref.read(currentTrackProvider);
    final owner = ref.read(platformAccountProvider).value;
    final selectedTime = widget.document.lines[index].time;
    final time = selectedTime.isNegative ? Duration.zero : selectedTime;
    bool current() =>
        mounted &&
        ref.read(currentTrackProvider).id == track.id &&
        ref.read(platformAccountProvider).value?.ownerId == owner?.ownerId &&
        ref.read(platformAccountProvider).value?.token == owner?.token;
    setState(() => _jumping = true);
    try {
      final handler = ref.read(audioHandlerProvider);
      await handler.seek(time, togetherGuard: current);
      if (current()) await handler.play(togetherGuard: current);
      if (current()) _resumeFollowing();
    } on Object catch (error) {
      if (mounted && current()) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _jumping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    // The provider filters position ticks to changes of sung line, avoiding a
    // full large-text list rebuild at the audio position stream's frequency.
    final active = ref.watch(activeLyricIndexProvider(document));
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: MusicTypography.sectionTitleSize,
      fontWeight: MusicTypography.titleWeight,
      height: 1.5,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final textWidth = (constraints.maxWidth - 48 - 58).clamp(
          1.0,
          double.infinity,
        );
        if (_width != textWidth ||
            _scaler != scaler ||
            !identical(_measured, document)) {
          _width = textWidth;
          _scaler = scaler;
          _measured = document;
          _heights.clear();
          _lastActive = -2;
          for (final line in document.lines) {
            final painter = TextPainter(
              text: TextSpan(
                text: line.text.isEmpty ? ' ' : line.text,
                style: style,
              ),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
            )..layout(maxWidth: textWidth);
            _heights.add((painter.height + 30).clamp(72.0, double.infinity));
            painter.dispose();
          }
        }
        _follow(active, constraints.maxHeight);
        return Stack(
          children: [
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .08, .86, 1],
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
              ).createShader(rect),
              child: NotificationListener<ScrollNotification>(
                onNotification: (event) {
                  if (event.depth != 0) return false;
                  if (event is UserScrollNotification &&
                      event.direction != ScrollDirection.idle) {
                    _pauseFollowing();
                    _selectAt(event.metrics);
                  }
                  if (event is ScrollUpdateNotification && !_following) {
                    _selectAt(event.metrics);
                  }
                  if (event is ScrollEndNotification && !_following) {
                    _scheduleResume();
                  }
                  return false;
                },
                child: ListView.builder(
                  key: const ValueKey('qishui-official-lyric-lines'),
                  controller: _scroll,
                  physics: const ArtworkFrontierPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.only(
                    top: 28,
                    bottom: constraints.maxHeight * .65,
                  ),
                  itemCount: document.lines.length,
                  itemBuilder: (context, index) {
                    final selected = _selected == index;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('qishui-lyric-line-$index'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: _selected == null
                              ? widget.onReturnToCover
                              : selected && !_jumping
                              ? () => _jump(index)
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white.withValues(alpha: .09)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            constraints: BoxConstraints(
                              minHeight: _heights[index],
                            ),
                            padding: const EdgeInsets.fromLTRB(10, 15, 6, 15),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    document.lines[index].text,
                                    style: style.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: index == active || selected
                                            ? 1
                                            : .48,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 58,
                                  child: !selected
                                      ? null
                                      : Semantics(
                                          label:
                                              '从 ${qishuiLyricTime(document.lines[index].time)} 播放',
                                          button: true,
                                          child: InkWell(
                                            key: ValueKey(
                                              'qishui-lyric-play-$index',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            onTap: _jumping
                                                ? null
                                                : () => _jump(index),
                                            child: SizedBox(
                                              height: 52,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.play_arrow_rounded,
                                                    color: Colors.white,
                                                    size: 24,
                                                  ),
                                                  Text(
                                                    qishuiLyricTime(
                                                      document
                                                          .lines[index]
                                                          .time,
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall!
                                                        .copyWith(
                                                          color: Colors.white70,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (!_following)
              Positioned(
                right: 20,
                bottom: 12,
                child: BetaGlassButton(
                  onPressed: _resumeFollowing,
                  child: const Text('回到当前句'),
                ),
              ),
          ],
        );
      },
    );
  }
}
