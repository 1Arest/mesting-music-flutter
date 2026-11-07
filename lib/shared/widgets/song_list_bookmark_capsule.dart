import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'artwork_image.dart';
import 'beta_glass_controls.dart';
import '../../features/themes/music_typography.dart';

/// One optical capsule with two independent hit targets. Closing never bubbles
/// into locate, and a pending locate leaves the close target usable.
class SongListBookmarkCapsule extends StatelessWidget {
  const SongListBookmarkCapsule({
    required this.title,
    required this.cover,
    required this.locating,
    required this.onLocate,
    required this.onDismiss,
    super.key,
  });
  final String title, cover;
  final bool locating;
  final VoidCallback onLocate, onDismiss;

  @override
  Widget build(BuildContext context) {
    final height =
        52.0 + (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 16);
    return BetaGlassButton(
      key: const ValueKey('song-list-last-played'),
      onPressed: locating ? () {} : onLocate,
      height: height,
      horizontalPadding: 8,
      label: '定位上次播放的歌曲：$title',
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: locating
                ? const SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: BetaActivityIndicator(independent: true),
                    ),
                  )
                : ArtworkImage(
                    key: const ValueKey('song-list-bookmark-cover'),
                    uri: cover,
                    width: 34,
                    height: 34,
                    frameOwner: cover,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '上次播放到这首',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: MusicTypography.smallCaptionSize),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: MusicTypography.footnoteSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('song-list-dismiss'),
            tooltip: '关闭上次播放提示',
            onPressed: onDismiss,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: EdgeInsets.zero,
            icon: const Icon(CupertinoIcons.xmark, size: 15),
          ),
        ],
      ),
    );
  }
}
