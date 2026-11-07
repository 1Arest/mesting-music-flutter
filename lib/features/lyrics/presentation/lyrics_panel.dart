import '../../../shared/widgets/artwork_scroll_frontier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../lyrics_providers.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/music_typography.dart';

class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({this.immersive = false, super.key});

  final bool immersive;

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  String? _lastTrackId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _followActiveLine(int index) {
    if (index < 0 || index == _lastActiveIndex) return;
    _lastActiveIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final itemExtent = widget.immersive ? 48.0 : 58.0;
      final target = ((index - 2).clamp(0, index) * itemExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    if (_lastTrackId != track.id) {
      _lastTrackId = track.id;
      _lastActiveIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
      });
    }
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final lyrics = ref.watch(lyricsProvider(track.resolvedLyricsAsset));
    final tokens = context.musicThemeTokens;
    const immersiveHalo = Color(0xE6000000);

    return lyrics.when(
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
        final activeIndex = document.activeIndexAt(position);
        _followActiveLine(activeIndex);
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

        if (widget.immersive) {
          return ListView.builder(
            controller: _scrollController,
            physics: const ArtworkFrontierPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(vertical: 225, horizontal: 12),
            itemExtent: 48,
            itemCount: document.lines.length,
            itemBuilder: (context, index) {
              final line = document.lines[index];
              final active = index == activeIndex;
              final completed = index < activeIndex;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: document.isSynced
                    ? () => ref.read(audioHandlerProvider).seek(line.time)
                    : null,
                child: AnimatedDefaultTextStyle(
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
                ),
              );
            },
          );
        }

        return Column(
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
                  vertical: 90,
                  horizontal: 18,
                ),
                itemExtent: 58,
                itemCount: document.lines.length,
                itemBuilder: (context, index) {
                  final line = document.lines[index];
                  final active = index == activeIndex;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: document.isSynced
                        ? () => ref.read(audioHandlerProvider).seek(line.time)
                        : null,
                    child: AnimatedDefaultTextStyle(
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
                    ),
                  );
                },
              ),
            ),
          ],
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
