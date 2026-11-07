import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../queue/presentation/queue_page.dart';
import '../../themes/music_typography.dart';
import '../presentation/platform_feedback.dart';
import '../presentation/song_actions_sheet.dart';
import 'qishui_lyrics_content.dart';
import 'qishui_player_navigation.dart';
import 'qishui_playback_notice.dart';

/// Structure follows the user's official Qishui screenshot; all artwork and
/// metadata come from the existing player. This is an inline Music-tab view,
/// never a new playback route, fabricated popularity count or karaoke service.
class QishuiLyricsPage extends ConsumerWidget {
  const QishuiLyricsPage({super.key});

  Future<void> _action(
    BuildContext context,
    Future<void> Function() run,
  ) async {
    try {
      await run();
    } on Object catch (error) {
      if (context.mounted) showPlatformFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final playing = ref.watch(
      playbackStateProvider.select((s) => s.value?.playing ?? false),
    );
    final base = Theme.of(context);
    final theme = base.copyWith(
      brightness: Brightness.dark,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white70,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          key: const ValueKey('qishui-music-lyrics-view'),
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                          child: TrackArtwork(track: track, fit: BoxFit.cover),
                        ),
                        ColoredBox(
                          color: const Color(0xFF242428).withValues(alpha: .88),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: BetaContentInsets.musicBottomOf(context),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                        child: Row(
                          children: [
                            BetaGlassButton(
                              onPressed: () => ref
                                  .read(qishuiMusicLyricsProvider.notifier)
                                  .showCover(),
                              label: '返回封面',
                              horizontalPadding: 14,
                              child: const Icon(Icons.arrow_back_rounded),
                            ),
                            const Spacer(),
                            SongActionsButton(track: track),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                        child: Row(
                          children: [
                            Semantics(
                              button: true,
                              label: '返回歌曲封面',
                              child: InkWell(
                                key: const ValueKey(
                                  'qishui-lyric-header-cover',
                                ),
                                onTap: () => ref
                                    .read(qishuiMusicLyricsProvider.notifier)
                                    .showCover(),
                                borderRadius: BorderRadius.circular(10),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: TrackArtwork(
                                    track: track,
                                    width: 64,
                                    height: 64,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontSize: MusicTypography.headingSize,
                                      fontWeight: MusicTypography.titleWeight,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: MusicTypography.subheadlineSize,
                                      color: Colors.white60,
                                    ),
                                  ),
                                  QishuiPlaybackNotice(
                                    preview: track.isPreview,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            BetaGlassButton(
                              onPressed: () => _action(
                                context,
                                ref.read(audioHandlerProvider).togglePlayPause,
                              ),
                              label: playing ? '暂停' : '播放',
                              horizontalPadding: 12,
                              child: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Expanded(
                        child: QishuiLyricsContent(
                          key: ValueKey('qishui-inline-lyrics'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                        child: Row(
                          children: [
                            BetaGlassButton(
                              onPressed: () => _action(
                                context,
                                () => ShareBridge.shareText(
                                  '${track.title} — ${track.artist}（汽水音乐）',
                                ),
                              ),
                              label: '分享歌曲',
                              child: const Icon(Icons.ios_share_rounded),
                            ),
                            const Spacer(),
                            FavoriteToggleButton(track: track),
                            const SizedBox(width: 24),
                            BetaGlassButton(
                              onPressed: () => showPlaybackQueueSheet(context),
                              label: '待播列表',
                              child: const Icon(Icons.queue_music_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
