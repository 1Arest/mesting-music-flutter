import '../../music_platform/netease/fallback/netease_source_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_popover.dart';
import '../../../shared/widgets/beta_glass_menu_item.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../library/library_providers.dart';
import '../../library/presentation/library_access.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../auth/presentation/beta_login_navigation.dart';
import '../../music_platform/platform_recommendation_providers.dart';
import '../../music_platform/presentation/platform_comments_page.dart';
import '../../music_platform/presentation/platform_quality_button.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../playlists/presentation/add_to_playlist_sheet.dart';
import '../../queue/presentation/queue_page.dart';
import '../../downloads/audio_downloads_page.dart';

/// Presentation returns an intent only. Existing repositories/audio owner still
/// perform every action after the menu has finished closing.
Future<void> showPlaybackPillMenu(
  BuildContext context,
  WidgetRef ref,
  Rect anchor,
) async {
  final track = ref.read(currentTrackProvider);
  final favorite = ref.read(favoriteTrackIdsProvider).contains(track.id);
  final mode = ref.read(playbackModeProvider).value;
  final fm = ref
      .read(platformRecommendationSessionProvider)
      .ownsFmTrack(track.id);
  final platform =
      track.source == TrackSource.kugou || track.source == TrackSource.netease;
  final selected = await showBetaGlassPopover<String>(
    context: context,
    anchor: anchor,
    label: '关闭播放器菜单',
    builder: (dialog) {
      Widget action(
        String id,
        String title,
        IconData icon, {
        bool quick = false,
      }) => Semantics(
        button: true,
        child: BetaGlassMenuItem(
          onTap: () => Navigator.of(dialog).pop(id),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: quick ? 2 : 12,
              vertical: 13,
            ),
            child: quick
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 23),
                      const SizedBox(height: 7),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(icon, size: 21),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: action(
                    'favorite',
                    favorite ? '取消喜欢' : '喜欢',
                    favorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                    quick: true,
                  ),
                ),
                Expanded(
                  child: action(
                    'playlist',
                    '添加到歌单',
                    CupertinoIcons.add_circled,
                    quick: true,
                  ),
                ),
                Expanded(
                  child: action(
                    'queue',
                    '当前队列',
                    CupertinoIcons.list_bullet,
                    quick: true,
                  ),
                ),
              ],
            ),
            const Divider(height: 12, indent: 16, endIndent: 16),
            action('lyrics', '查看歌词', CupertinoIcons.text_alignleft),
            if (platform)
              action('comments', '歌曲评论', CupertinoIcons.text_bubble),
            if (platform) action('quality', '音质', CupertinoIcons.waveform),
            if (track.source == TrackSource.netease && !track.hasLocalAudio)
              action(
                'choose-source',
                '选择音乐来源',
                CupertinoIcons.antenna_radiowaves_left_right,
              ),
            if (track.isRemote)
              action('download', '下载音乐', CupertinoIcons.arrow_down_circle),
            if (mode != null)
              action('mode', '播放模式 · ${mode.label}', CupertinoIcons.repeat),
            if (fm) ...[
              const Divider(height: 12, indent: 16, endIndent: 16),
              action('dislike', '不喜欢这首', CupertinoIcons.hand_thumbsdown),
            ],
          ],
        ),
      );
    },
  );
  if (selected == null || !context.mounted) return;
  if (ref.read(currentTrackProvider).id != track.id) {
    showMusicNotice(
      context,
      icon: CupertinoIcons.music_note,
      title: '歌曲已切换，请重新打开菜单',
      message: '',
    );
    return;
  }
  try {
    switch (selected) {
      case 'choose-source':
        await showNeteaseTrackSources(context, ref, track);
      case 'download':
        await enqueueAudioDownload(context, ref, track);
      case 'favorite':
        if (!await ensureLibraryAccess(
              context,
              ref,
              reason: '登录后同步喜欢的音乐',
              redirect: '/music',
            ) ||
            !context.mounted) {
          return;
        }
        final wasFavorite = ref
            .read(favoriteTrackIdsProvider)
            .contains(track.id);
        await ref.read(libraryRepositoryProvider).toggleFavorite(track);
        if (context.mounted) {
          showMusicNotice(
            context,
            icon: wasFavorite
                ? Icons.heart_broken_outlined
                : Icons.favorite_rounded,
            title: wasFavorite ? '已取消喜欢' : '已添加到喜欢',
            message: '',
          );
        }
      case 'playlist':
        await showAddToPlaylistSheet(context, ref, track);
      case 'queue':
        await showPlaybackQueueSheet(context);
      case 'lyrics':
        await context.push('/player', extra: const PlaybackPillLyricsIntent());
      case 'comments':
        if (ref.read(platformAccountProvider).value == null) {
          await openBetaLogin(context, redirect: '/music');
        }
        if (context.mounted) {
          await openPlatformSongComments(context, ref, track);
        }
      case 'quality':
        await showPlatformQualityPicker(context, ref);
      case 'mode':
        final current = ref.read(playbackModeProvider).value;
        if (current == null) return;
        await ref.read(audioHandlerProvider).setPlaybackMode(current.next);
        if (context.mounted) {
          showMusicNotice(
            context,
            icon: CupertinoIcons.repeat,
            title: current.next.label,
            message: '',
          );
        }
      case 'dislike':
        final recommendation = ref.read(platformRecommendationSessionProvider);
        if (recommendation.ownsFmTrack(track.id)) {
          await recommendation.dislike(track);
        }
    }
  } catch (error) {
    if (context.mounted) showPlatformFailure(context, error);
  }
}

/// Typed route intent avoids query strings leaking into shell route identity.
class PlaybackPillLyricsIntent {
  const PlaybackPillLyricsIntent();
}
