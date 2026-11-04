import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_mode.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/models/track.dart';
import 'queue_track_duration.dart';
import 'beta_playback_queue.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../themes/music_theme_tokens.dart';

const double playbackQueueSheetHeightFactor = .74;
const double minimumPopulatedQueueSheetHeightFactor = .30;
// Keep the empty state as compact as a one-song queue; additional rows expand
// the sheet through playbackQueueSheetHeightFactorForCount.
const double emptyPlaybackQueueSheetHeightFactor =
    minimumPopulatedQueueSheetHeightFactor;
const double playbackQueueRowHeight = 64;
const double playbackQueueSheetChromeHeight = 118;
const liquidGlassQueuePageSurfaceKey = ValueKey<String>(
  'liquid-glass-queue-page-surface',
);

double playbackQueueSheetHeightFactorForCount({
  required int count,
  required double viewportHeight,
  double bottomInset = 0,
}) {
  if (count <= 0) return emptyPlaybackQueueSheetHeightFactor;
  if (!viewportHeight.isFinite || viewportHeight <= 0) {
    return playbackQueueSheetHeightFactor;
  }

  final safeBottomInset = bottomInset > 0 ? bottomInset : 0;
  final desiredHeight =
      playbackQueueSheetChromeHeight +
      safeBottomInset +
      count * playbackQueueRowHeight;
  return (desiredHeight / viewportHeight)
      .clamp(
        minimumPopulatedQueueSheetHeightFactor,
        playbackQueueSheetHeightFactor,
      )
      .toDouble();
}

IconData playbackModeIcon(PlaybackMode mode) => switch (mode) {
  PlaybackMode.list => Icons.repeat_rounded,
  PlaybackMode.single => Icons.repeat_one_rounded,
  PlaybackMode.random => Icons.shuffle_rounded,
};

Future<void> showPlaybackQueueSheet(BuildContext context) {
  return showLiquidGlassBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: .46),
    showDragHandle: false,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 280),
      reverseDuration: Duration(milliseconds: 220),
    ),
    builder: (context) => const _PlaybackQueueSheetFrame(),
  );
}

class _PlaybackQueueSheetFrame extends ConsumerWidget {
  const _PlaybackQueueSheetFrame();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(upcomingQueueProvider).value ?? const [];
    final mediaQuery = MediaQuery.of(context);
    return AnimatedFractionallySizedBox(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      heightFactor: DistributionChannel.isBeta
          ? ((160 + queue.length * 76 + mediaQuery.padding.bottom) /
                    mediaQuery.size.height)
                .clamp(.32, .86)
                .toDouble()
          : playbackQueueSheetHeightFactorForCount(
              count: queue.length,
              viewportHeight: mediaQuery.size.height,
              bottomInset: mediaQuery.padding.bottom,
            ),
      alignment: Alignment.bottomCenter,
      child: const QueuePage(sheet: true),
    );
  }
}

class QueuePage extends ConsumerWidget {
  const QueuePage({this.sheet = false, super.key});

  final bool sheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (DistributionChannel.isBeta) {
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          top: !sheet,
          child: Column(
            children: [
              if (sheet) const _QueueGrabHandle(),
              Expanded(
                child: BetaPlaybackQueue(
                  bottomClearance: sheet
                      ? 18
                      : BetaContentInsets.musicBottomOf(context, 18),
                  onClose: sheet
                      ? () => Navigator.of(context).pop()
                      : () => context.go('/music'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final tokens = context.musicThemeTokens;
    final queue = ref.watch(upcomingQueueProvider).value ?? const [];
    final mode = ref.watch(playbackModeProvider).value ?? PlaybackMode.list;
    final handler = ref.watch(audioHandlerProvider);
    final manual = queue
        .where((item) => !handler.isAutomaticallyQueued(item.id))
        .toList();
    final automatic = queue
        .where((item) => handler.isAutomaticallyQueued(item.id))
        .toList();
    final grouped = DistributionChannel.isBeta && automatic.isNotEmpty;
    final rows = grouped ? [...manual, ...automatic] : queue;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final content = SafeArea(
      top: !sheet,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          sheet ? 0 : 12,
          14,
          sheet ? bottomInset + 8 : 112,
        ),
        child: Column(
          children: [
            if (sheet) const _QueueGrabHandle(),
            _QueueHeader(
              sheet: sheet,
              count: queue.length,
              mode: mode,
              onClose: sheet
                  ? Navigator.of(context).pop
                  : () => context.go('/music'),
              onCycleMode: handler.cyclePlaybackMode,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
              child: Divider(height: 1, color: tokens.border),
            ),
            Expanded(
              child: queue.isEmpty
                  ? const PlaybackQueueEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                      physics: const BouncingScrollPhysics(),
                      cacheExtent: playbackQueueRowHeight * 4,
                      itemCount: rows.length + (grouped ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (grouped && index == manual.length) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                            child: Text(
                              '自动推荐',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: tokens.textSecondary,
                              ),
                            ),
                          );
                        }
                        final rowIndex = grouped && index > manual.length
                            ? index - 1
                            : index;
                        final item = rows[rowIndex];
                        final track = handler.trackForId(item.id);
                        return _QueueSongRow(
                          index: rowIndex,
                          coverUri:
                              track?.coverAsset ??
                              item.artUri?.toString() ??
                              '',
                          title: item.title,
                          artist: item.artist ?? '未知歌手',
                          duration: item.duration,
                          track: track,
                          isNext: rowIndex == 0,
                          onPlay: () => handler.playTrack(item.id),
                          onRemove: () =>
                              handler.removeFromUpcomingQueue(item.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );

    if (sheet) {
      // showPlaybackQueueSheet already supplies the shared liquid-glass
      // surface. Keeping another nearly opaque panel here hid that surface.
      return Material(color: Colors.transparent, child: content);
    }
    return LiquidGlassSurface(
      key: liquidGlassQueuePageSurfaceKey,
      borderRadius: BorderRadius.zero,
      child: Material(color: Colors.transparent, child: content),
    );
  }
}

class _QueueGrabHandle extends StatelessWidget {
  const _QueueGrabHandle();

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return SizedBox(
      height: 27,
      child: Center(
        child: Container(
          width: 46,
          height: 5,
          decoration: BoxDecoration(
            color: tokens.textPrimary.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.sheet,
    required this.count,
    required this.mode,
    required this.onClose,
    required this.onCycleMode,
  });

  final bool sheet;
  final int count;
  final PlaybackMode mode;
  final VoidCallback onClose;
  final VoidCallback onCycleMode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 2, 7),
      child: Row(
        children: [
          if (!sheet) ...[
            _QueueCircleButton(
              tooltip: '返回音乐页面',
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: onClose,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '播放列表',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 23,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$count 首待播放歌曲',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _PlaybackModeControl(mode: mode, onTap: onCycleMode),
          const SizedBox(width: 8),
          _QueueCircleButton(
            tooltip: sheet ? '关闭播放列表' : '返回音乐页面',
            icon: sheet
                ? Icons.close_rounded
                : Icons.keyboard_arrow_down_rounded,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _PlaybackModeControl extends StatelessWidget {
  const _PlaybackModeControl({required this.mode, required this.onTap});

  final PlaybackMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: '当前${mode.label}，点击切换播放模式',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                accent.withValues(alpha: .1),
                tokens.glassSubtle,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: .22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(playbackModeIcon(mode), size: 17, color: accent),
                const SizedBox(width: 6),
                Text(
                  mode.label,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueCircleButton extends StatelessWidget {
  const _QueueCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.glassSubtle,
              border: Border.all(color: tokens.border),
            ),
            child: Icon(icon, size: 19, color: tokens.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _QueueSongRow extends StatelessWidget {
  const _QueueSongRow({
    required this.index,
    required this.coverUri,
    required this.title,
    required this.artist,
    required this.duration,
    required this.track,
    required this.isNext,
    required this.onPlay,
    required this.onRemove,
  });

  final int index;
  final String coverUri;
  final String title;
  final String artist;
  final Duration? duration;
  final Track? track;
  final bool isNext;
  final VoidCallback onPlay;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Semantics(
      label: isNext ? '下一首，$title，$artist' : '待播放，$title，$artist',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            height: playbackQueueRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: ArtworkImage(uri: coverUri, width: 44, height: 44),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                QueueTrackDuration(
                  track: track,
                  mediaDuration: duration,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                _QueueRemoveButton(onTap: onRemove),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PlaybackQueueEmptyState extends StatelessWidget {
  const PlaybackQueueEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 68,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (var index = 0; index < 3; index++)
                  Positioned(
                    top: 8.0 + index * 13,
                    left: 7.0 + index * 4,
                    child: Container(
                      width: 50 - index * 8,
                      height: 5,
                      decoration: BoxDecoration(
                        color: index == 0
                            ? accent.withValues(alpha: .58)
                            : tokens.textMuted.withValues(alpha: .24),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 29,
                    height: 29,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: .12),
                      border: Border.all(color: accent.withValues(alpha: .28)),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: accent,
                      size: 19,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '播放列表还是空的',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRemoveButton extends StatelessWidget {
  const _QueueRemoveButton({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Tooltip(
      message: '从播放列表移除',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(Icons.close_rounded, size: 17, color: tokens.textMuted),
        ),
      ),
    );
  }
}
