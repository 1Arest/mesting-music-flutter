import '../../../shared/widgets/artwork_scroll_frontier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../domain/lyrics_document.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/music_typography.dart';
import 'lyric_scroll_preview.dart';
import '../lyric_timing.dart';
import 'lyric_timing_tools.dart';

class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({this.immersive = false, super.key});

  final bool immersive;

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  final ScrollController _scrollController = ScrollController();
  late final LyricScrollPreview _preview = LyricScrollPreview(() {
    setState(() {
      if (_preview.index == null) _lastActiveIndex = -2;
    });
  });
  int _lastActiveIndex = -2;
  String? _lastTrackId;
  LyricsDocument? _document;

  double get _itemExtent => widget.immersive ? 48 : 58;

  @override
  void dispose() {
    _preview.clear(notify: false);
    _scrollController.dispose();
    super.dispose();
  }

  void _followActiveLine(int index) {
    if (_preview.index != null || index == _lastActiveIndex) return;
    _lastActiveIndex = index;
    final trackId = _lastTrackId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          _preview.index != null ||
          _lastTrackId != trackId ||
          _lastActiveIndex != index) {
        return;
      }
      final target = ((index >= 2 ? index - 2 : 0) * _itemExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Widget _previewScroll(
    LyricsDocument document,
    double topPadding,
    Widget list,
  ) {
    return NotificationListener<ScrollNotification>(
      onNotification: (event) =>
          document.isSynced &&
          _preview.handleScroll(
            event,
            lineCount: document.lines.length,
            topPadding: topPadding,
            lineAtOffset: (offset) => (offset / _itemExtent).floor(),
          ),
      child: list,
    );
  }

  VoidCallback? _lineTap(LyricsDocument document, int index) {
    if (!document.isSynced) return null;
    final time = document.lines[index].time;
    if (_preview.index == null) {
      return () => ref
          .read(audioHandlerProvider)
          .seek(time.isNegative ? Duration.zero : time);
    }
    return _preview.index == index && !_preview.seeking
        ? () => _preview.playFrom(context, ref, time)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    if (_lastTrackId != track.id) {
      _lastTrackId = track.id;
      _lastActiveIndex = -2;
      _preview.clear(notify: false);
    }
    final lyrics = ref.watch(currentTimedLyricsProvider);
    final tokens = context.musicThemeTokens;
    const immersiveHalo = Color(0xE6000000);

    return lyrics.when(
      skipLoadingOnReload: true,
      loading: () => _LyricsLoadingState(immersive: widget.immersive),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            userFacingErrorMessage(error, fallback: '歌词暂时无法读取，请稍后重试'),
            textAlign: TextAlign.center,
            style: widget.immersive
                ? const TextStyle(color: Color(0xCFFFFFFF))
                : null,
          ),
        ),
      ),
      data: (document) {
        if (!identical(_document, document)) {
          _document = document;
          _lastActiveIndex = -2;
          _preview.clear(notify: false);
        }
        if (document.lines.isEmpty) {
          return Center(
            child: Text(
              '这首歌暂时没有歌词',
              style: TextStyle(
                color: widget.immersive
                    ? const Color(0xAFFFFFFF)
                    : tokens.textSecondary,
              ),
            ),
          );
        }
        final activeIndex = ref.watch(
          positionProvider.select(
            (value) => document.activeIndexAt(value.value ?? Duration.zero),
          ),
        );
        _followActiveLine(activeIndex);
        final highlightedIndex = _preview.index ?? activeIndex;

        if (widget.immersive) {
          const topPadding = 225.0;
          final lyrics = ListView.builder(
            controller: _scrollController,
            physics: const ArtworkFrontierPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: topPadding,
              horizontal: 12,
            ),
            itemExtent: _itemExtent,
            itemCount: document.lines.length,
            itemBuilder: (context, index) {
              final line = document.lines[index];
              final active = index == highlightedIndex;
              final completed = index < activeIndex;
              final onTap = _lineTap(document, index);
              final text = AnimatedDefaultTextStyle(
                key: ValueKey('lyrics-line-$index-style'),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: active
                      ? Colors.white
                      : completed
                      ? const Color(0x8FFFFFFF)
                      : const Color(0xA8FFFFFF),
                  fontSize: active
                      ? MusicTypography.headingSize
                      : MusicTypography.subheadlineSize,
                  fontWeight: active
                      ? MusicTypography.titleWeight
                      : MusicTypography.bodyWeight,
                  height: 1.3,
                  shadows: [
                    Shadow(color: immersiveHalo, blurRadius: active ? 12 : 8),
                    Shadow(
                      color: immersiveHalo.withValues(alpha: .74),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    line.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: _preview.index == index
                    ? LyricSeekRow(
                        time: line.time,
                        foreground: Colors.white,
                        onPlay: onTap,
                        child: text,
                      )
                    : text,
              );
            },
          );
          return LyricTimingTools(
            child: _previewScroll(document, topPadding, lyrics),
          );
        }

        const topPadding = 90.0;
        final lyrics = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.lyrics_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '同步歌词',
                    style: TextStyle(fontWeight: MusicTypography.titleWeight),
                  ),
                  const Spacer(),
                  Text(
                    document.isSynced ? '逐句同步' : '普通文本',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: MusicTypography.captionSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  vertical: topPadding,
                  horizontal: 18,
                ),
                itemExtent: _itemExtent,
                itemCount: document.lines.length,
                itemBuilder: (context, index) {
                  final line = document.lines[index];
                  final active = index == highlightedIndex;
                  final onTap = _lineTap(document, index);
                  final text = AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    // Preserve the shared typography's font/fallback family
                    // when changing active-line emphasis.
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: active
                          ? const Color(0xFF4B63D0)
                          : tokens.textMuted,
                      fontSize: active
                          ? MusicTypography.headingSize
                          : MusicTypography.subheadlineSize,
                      fontWeight: active
                          ? MusicTypography.titleWeight
                          : MusicTypography.bodyWeight,
                      height: 1.3,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        line.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onTap,
                    child: _preview.index == index
                        ? LyricSeekRow(
                            time: line.time,
                            foreground: const Color(0xFF4B63D0),
                            alignment: Alignment.centerLeft,
                            onPlay: onTap,
                            child: text,
                          )
                        : text,
                  );
                },
              ),
            ),
          ],
        );
        return LyricTimingTools(
          child: _previewScroll(document, topPadding, lyrics),
        );
      },
    );
  }
}

class _LyricsLoadingState extends StatelessWidget {
  const _LyricsLoadingState({required this.immersive});

  final bool immersive;

  @override
  Widget build(BuildContext context) {
    final accent = immersive
        ? const Color(0xFFDDE5FF)
        : Theme.of(context).colorScheme.primary;

    return Center(
      child: MestingLoadingIndicator(
        key: const ValueKey('lyrics-curve-loader'),
        size: 104,
        color: accent,
        secondaryColor: immersive ? Colors.white : null,
        duration: const Duration(milliseconds: 3000),
        semanticLabel: '正在加载歌词',
      ),
    );
  }
}
