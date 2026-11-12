import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/track.dart';
import '../music_platform/music_platform_providers.dart';
import '../themes/beta_appearance.dart';
import 'audio_downloads.dart';
import '../themes/music_typography.dart';

/// Account-scoped completed documents, independent of favorites and playback.
/// Failed/paused/network-100% tasks never receive a downloaded mark.
class DownloadedTrackSubtitle extends ConsumerWidget {
  const DownloadedTrackSubtitle({required this.track, this.style, super.key});
  final Track track;
  final TextStyle? style;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(platformAccountProvider).value?.ownerId;
    Widget artist() => Text(
      track.artist,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (owner == null) return artist();
    final manager = ref.watch(audioDownloadManagerProvider);
    return ListenableBuilder(
      listenable: manager.collectionChanges,
      builder: (context, _) {
        final downloaded = manager.completedTrackIds(owner).contains(track.id);
        return !downloaded
            ? artist()
            : Row(
                children: [
                  Icon(
                    CupertinoIcons.arrow_down_circle_fill,
                    size: 13,
                    color: BetaAppearance.success(Theme.of(context).brightness),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '已下载',
                    style:
                        (style ??
                                const TextStyle(
                                  fontSize: MusicTypography.captionSize,
                                ))
                            .copyWith(
                              color: BetaAppearance.success(
                                Theme.of(context).brightness,
                              ),
                            ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: artist()),
                ],
              );
      },
    );
  }
}
