import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../data/song_favorite_count.dart';

/// Decorates existing song controls without replacing their tap or animation.
class SongFavoriteCountBadge extends ConsumerWidget {
  const SongFavoriteCountBadge({
    required this.track,
    required this.child,
    this.color,
    this.inline = false,
    super.key,
  });

  final Track track;
  final Widget child;
  final Color? color;
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = songCountIdentity(track);
    final count = song == null
        ? null
        : ref.watch(songFavoriteCountProvider(song)).value;
    if (count == null) return child;
    final label = IgnorePointer(
      child: Semantics(
        label: '平台收藏总数 $count',
        child: Text(
          formatSongFavoriteCount(count),
          key: ValueKey('song-favorite-count-${track.id}'),
          style: TextStyle(
            fontSize: inline ? 11 : 9,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 36),
            child: FittedBox(fit: BoxFit.scaleDown, child: label),
          ),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: SizedBox(
            width: 34,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: label,
            ),
          ),
        ),
      ],
    );
  }
}
