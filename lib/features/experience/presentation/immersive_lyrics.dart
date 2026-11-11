import '../../../shared/widgets/artwork_scroll_frontier.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_providers.dart';
import '../../lyrics/lyrics_providers.dart';
import '../../lyrics/domain/lyrics_document.dart';
import '../../themes/music_typography.dart';
import '../../themes/personal_style.dart';

/// Position ticks resolve to an index here, so a long lyric list rebuilds only
/// when the sung LINE changes, rather than at the audio position frequency.
final activeLyricIndexProvider = Provider.family<int, LyricsDocument>(
  (ref, document) => document.activeIndexAt(
    ref.watch(positionProvider).value ?? Duration.zero,
  ),
);

/// Variable-height lines keep long lyrics and accessibility text sizes intact.
/// The measured offsets use the same text style as the rendered paragraphs.
class ImmersiveLyrics extends ConsumerStatefulWidget {
  const ImmersiveLyrics({this.referenceDesign = false, super.key});
  final bool referenceDesign;
  @override
  ConsumerState<ImmersiveLyrics> createState() => _ImmersiveLyricsState();
}

class _ImmersiveLyricsState extends ConsumerState<ImmersiveLyrics> {
  final _scroll = ScrollController();
  int _active = -2;
  String _track = '';
  LyricsDocument? _measured;
  double _measuredWidth = 0;
  TextStyle? _measuredStyle;
  TextScaler? _measuredScaler;
  final _heights = <double>[];
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    final personal = ref.watch(personalStyleProvider);
    if (_track != track.id) {
      _track = track.id;
      _active = -2;
    }
    return ref
        .watch(lyricsProvider(track.resolvedLyricsAsset))
        .when(
          loading: () => const Center(
            child: Text('正在寻找歌词…', style: TextStyle(color: Colors.white70)),
          ),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () =>
                  ref.invalidate(lyricsProvider(track.resolvedLyricsAsset)),
              child: const Text(
                '歌词暂时无法读取，点此重试',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          data: (document) {
            if (document.lines.isEmpty) {
              return const Center(
                child: Text(
                  '这首歌暂时没有歌词',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }
            final active = ref.watch(activeLyricIndexProvider(document));
            return LayoutBuilder(
              builder: (context, constraints) {
                final style = Theme.of(context).textTheme.headlineLarge!
                    .copyWith(
                      fontFamily: personal.serif ? 'serif' : null,
                      fontSize: personal.lyricSize > 0
                          ? personal.lyricSize
                          : widget.referenceDesign
                          ? MusicTypography.largeTitleSize
                          : MusicTypography.sectionTitleSize,
                      fontWeight: personal.lyricWeight == 1
                          ? FontWeight.w400
                          : MusicTypography.titleWeight,
                      height: personal.lineHeight > 0
                          ? personal.lineHeight
                          : widget.referenceDesign
                          ? 1.3
                          : 1.4,
                      letterSpacing: -.5,
                    );
                final textWidth = (constraints.maxWidth - 48).clamp(
                  1.0,
                  double.infinity,
                );
                final scaler = MediaQuery.textScalerOf(context);
                // Position ticks only update the active line; measuring every
                // paragraph at audio frequency wastes frames on long songs.
                if (!identical(_measured, document) ||
                    _measuredWidth != textWidth ||
                    _measuredStyle != style ||
                    _measuredScaler != scaler) {
                  _measured = document;
                  _measuredWidth = textWidth;
                  _measuredStyle = style;
                  _measuredScaler = scaler;
                  _heights.clear();
                  _active = -2;
                  for (final line in document.lines) {
                    final painter = TextPainter(
                      text: TextSpan(
                        text: line.text.isEmpty ? ' ' : line.text,
                        style: style,
                      ),
                      textDirection: TextDirection.ltr,
                      textScaler: scaler,
                    )..layout(maxWidth: textWidth);
                    _heights.add(painter.height + 28);
                    painter.dispose();
                  }
                }
                if (_active != active) {
                  _active = active;
                  final target = _heights
                      .take(active.clamp(0, _heights.length))
                      .fold(0.0, (a, b) => a + b);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted ||
                        !_scroll.hasClients ||
                        !identical(_measured, document) ||
                        _active != active) {
                      return;
                    }
                    _scroll.animateTo(
                      target.clamp(0.0, _scroll.position.maxScrollExtent),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 460),
                      curve: Curves.easeOutCubic,
                    );
                  });
                }
                return ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0, .10, .83, 1],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: ListView.builder(
                    key: ValueKey(track.id),
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      constraints.maxHeight * .2,
                      24,
                      constraints.maxHeight * .7,
                    ),
                    physics: const ArtworkFrontierPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    itemCount: document.lines.length,
                    itemBuilder: (context, index) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: document.isSynced
                          ? () => ref
                                .read(audioHandlerProvider)
                                .seek(document.lines[index].time)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            end: !document.isSynced || index == active ? 0 : 1,
                          ),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 460),
                          curve: Curves.easeOutCubic,
                          child: Text(
                            document.lines[index].text,
                            style: style.copyWith(
                              color:
                                  (index == active || !document.isSynced) &&
                                      personal.lyricColor != null
                                  ? Color(personal.lyricColor!)
                                  : Colors.white,
                            ),
                          ),
                          builder: (_, distance, child) => ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: distance * 3.4,
                              sigmaY: distance * 3.4,
                            ),
                            enabled: widget.referenceDesign && distance > .01,
                            child: Opacity(
                              opacity:
                                  1 -
                                  distance *
                                      (widget.referenceDesign ? .55 : .35),
                              child: Transform.scale(
                                scale: widget.referenceDesign
                                    ? 1 - distance * .035
                                    : 1,
                                alignment: Alignment.centerLeft,
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
  }
}
