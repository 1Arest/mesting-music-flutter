import 'dart:ui';
import 'package:flutter/material.dart';
import '../../music_platform/presentation/platform_quality_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/playback_mode.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../../shared/widgets/mesting_glass.dart';
import '../../../shared/utils/duration_format.dart';
import '../../auth/account_capabilities.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../music_platform/presentation/platform_comments_page.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../player/player_visual_style.dart';
import '../../playlists/presentation/add_to_playlist_sheet.dart';
import '../../queue/presentation/queue_page.dart';
import 'immersive_lyrics.dart';

/// A presentation-only player. The existing audio service owns playback,
/// scrubbing, media notifications, the queue, and current account favorites.
class CoverPlayerPage extends ConsumerStatefulWidget {
  const CoverPlayerPage({this.lyricsInitially = false, super.key});
  final bool lyricsInitially;
  @override
  ConsumerState<CoverPlayerPage> createState() => _CoverPlayerPageState();
}

class _CoverPlayerPageState extends ConsumerState<CoverPlayerPage> {
  late bool _lyrics = widget.lyricsInitially;
  double? _scrub;
  String? _trackId;
  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    if (_trackId != track.id) {
      _trackId = track.id;
      _scrub = null;
    }
    final handler = ref.watch(audioHandlerProvider);
    final state = ref.watch(playbackStateProvider).value;
    final playing = state?.playing ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = ref.watch(durationProvider).value ?? track.duration;
    final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final value = (_scrub ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      max,
    );
    final mode = ref.watch(playbackModeProvider).value ?? PlaybackMode.list;
    Future<void> act(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (context.mounted) showPlatformFailure(context, error);
      }
    }

    void close() {
      if (_lyrics) {
        setState(() => _lyrics = false);
        return;
      }
      context.canPop() ? context.pop() : context.go('/music/recommend');
    }

    return PopScope(
      canPop: !_lyrics,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _lyrics) setState(() => _lyrics = false);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1B20),
        // Immersive controls must not inherit pale form-button fills from the
        // selected dress theme. Fixed dark chrome keeps white icons legible.
        body: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF34383F),
              foregroundColor: Colors.white,
              minimumSize: const Size.square(44),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                    child: Transform.scale(
                      scale: 1.35,
                      child: TrackArtwork(
                        track: track,
                        width: 800,
                        height: 1200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: ColoredBox(color: const Color(0x99131820)),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide =
                        constraints.maxWidth > 760 &&
                        constraints.maxWidth / constraints.maxHeight > 1.1;
                    final content = Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: '收起播放器',
                                onPressed: close,
                                color: Colors.white,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 33,
                                ),
                              ),
                              const Spacer(),
                              if (DistributionChannel.isBeta)
                                const PlatformQualityButton(),
                              PopupMenuButton<PlayerVisualStyle>(
                                tooltip: '播放器样式',
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  color: Colors.white,
                                ),
                                onSelected: (style) => ref
                                    .read(playerVisualStyleProvider.notifier)
                                    .select(style),
                                itemBuilder: (_) => [
                                  for (final style in PlayerVisualStyle.values)
                                    PopupMenuItem(
                                      value: style,
                                      child: Text(style.displayName),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 320),
                            child: _lyrics
                                ? Column(
                                    key: const ValueKey('immersive-lyrics'),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          26,
                                          10,
                                          26,
                                          6,
                                        ),
                                        child: Row(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                              child: TrackArtwork(
                                                track: track,
                                                width: 52,
                                                height: 52,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    track.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 19,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  Text(
                                                    track.artist,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Expanded(child: ImmersiveLyrics()),
                                    ],
                                  )
                                : Center(
                                    key: const ValueKey('immersive-cover'),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        28,
                                        12,
                                        28,
                                        20,
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x66000000),
                                                blurRadius: 32,
                                                offset: Offset(0, 16),
                                              ),
                                            ],
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: TrackArtwork(
                                            track: track,
                                            width: 640,
                                            height: 640,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        if (!_lyrics)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -.5,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Theme(
                                  data: Theme.of(context).copyWith(
                                    iconTheme: const IconThemeData(
                                      color: Colors.white,
                                    ),
                                  ),
                                  child: FavoriteToggleButton(track: track),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                          child: Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.white,
                                  overlayShape: SliderComponentShape.noOverlay,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 4,
                                  ),
                                ),
                                child: Slider(
                                  value: value,
                                  max: max,
                                  onChangeStart: duration > Duration.zero
                                      ? (v) => setState(() => _scrub = v)
                                      : null,
                                  onChanged: duration > Duration.zero
                                      ? (v) => setState(() => _scrub = v)
                                      : null,
                                  onChangeEnd: (v) async {
                                    await act(
                                      () => handler.seek(
                                        Duration(milliseconds: v.round()),
                                      ),
                                    );
                                    if (mounted) setState(() => _scrub = null);
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      formatDuration(
                                        Duration(milliseconds: value.round()),
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      '-${formatDuration(Duration(milliseconds: (max - value).round()))}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 13,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                tooltip: mode.label,
                                color: Colors.white70,
                                onPressed: () => act(
                                  () => handler.setPlaybackMode(mode.next),
                                ),
                                icon: Icon(
                                  mode == PlaybackMode.random
                                      ? Icons.shuffle_rounded
                                      : mode == PlaybackMode.single
                                      ? Icons.repeat_one_rounded
                                      : Icons.repeat_rounded,
                                  size: 23,
                                ),
                              ),
                              IconButton(
                                tooltip: '上一首',
                                onPressed: () => act(handler.skipToPrevious),
                                icon: const Icon(
                                  Icons.fast_rewind_rounded,
                                  color: Colors.white,
                                  size: 43,
                                ),
                              ),
                              SizedBox.square(
                                dimension: 74,
                                child: IconButton(
                                  tooltip: playing ? '暂停' : '播放',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF20232B),
                                  ),
                                  onPressed: () => act(
                                    playing ? handler.pause : handler.play,
                                  ),
                                  icon: Icon(
                                    playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: const Color(0xFF20232B),
                                    size: 60,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '下一首',
                                onPressed: () => act(handler.skipToNext),
                                icon: const Icon(
                                  Icons.fast_forward_rounded,
                                  color: Colors.white,
                                  size: 43,
                                ),
                              ),
                              IconButton(
                                tooltip: '加入歌单',
                                onPressed: () =>
                                    showAddToPlaylistSheet(context, ref, track),
                                icon: const Icon(
                                  Icons.playlist_add_rounded,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              MestingGlass(
                                child: IconButton(
                                  tooltip: _lyrics ? '显示封面' : '显示歌词',
                                  onPressed: () =>
                                      setState(() => _lyrics = !_lyrics),
                                  icon: Icon(
                                    _lyrics
                                        ? Icons.album_outlined
                                        : Icons.lyrics_outlined,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (ref.watch(showPlatformFeaturesProvider))
                                IconButton(
                                  tooltip: '歌曲评论',
                                  onPressed: () => openPlatformSongComments(
                                    context,
                                    ref,
                                    track,
                                  ),
                                  icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: Colors.white70,
                                  ),
                                ),
                              IconButton(
                                tooltip: '播放队列',
                                onPressed: () =>
                                    showPlaybackQueueSheet(context),
                                icon: const Icon(
                                  Icons.queue_music_rounded,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final minimumHeight =
                        620 +
                        (MediaQuery.textScalerOf(context).scale(60) - 60).clamp(
                          0.0,
                          180.0,
                        );
                    // Short windows (including landscape) keep every transport
                    // action reachable by scrolling instead of squeezing covers.
                    if (constraints.maxHeight < minimumHeight) {
                      return SingleChildScrollView(
                        child: SizedBox(
                          height: minimumHeight,
                          child: Center(
                            child: SizedBox(
                              width: wide ? 600 : double.infinity,
                              child: content,
                            ),
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: SizedBox(
                        width: wide ? 600 : double.infinity,
                        child: content,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
