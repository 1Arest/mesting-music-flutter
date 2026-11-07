import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../domain/social_models.dart';
import '../social_providers.dart';
import 'social_widgets.dart';

Future<SocialUser?> showTrackShareSheet({
  required BuildContext context,
  required Track track,
}) {
  return showLiquidGlassBottomSheet<SocialUser>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _TrackShareSheet(track: track),
  );
}

class _TrackShareSheet extends ConsumerWidget {
  const _TrackShareSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(
      socialConnectionsProvider(SocialConnectionKind.following),
    );
    final height = (MediaQuery.sizeOf(context).height * .72)
        .clamp(380.0, 620.0)
        .toDouble();

    return SizedBox(
      key: const ValueKey('track-share-sheet'),
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 14),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '分享给好友',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text('选择一位互相关注的好友', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SharedTrackPreview(track: track),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '好友',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: connections.when(
              loading: () => const SocialLoadingState(message: '正在读取可以分享的好友'),
              error: (error, stackTrace) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  SocialErrorCard(
                    error: error,
                    onRetry: () => ref.invalidate(
                      socialConnectionsProvider(SocialConnectionKind.following),
                    ),
                  ),
                ],
              ),
              data: (connections) {
                final friends = connections
                    .where((connection) => connection.isFriend)
                    .toList(growable: false);
                if (friends.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: const [
                      SocialEmptyState(
                        icon: Icons.people_outline_rounded,
                        title: '还没有可以分享的好友',
                        message: '与对方互相关注后，就能把正在听的音乐分享过去。',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                  itemCount: friends.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return _FriendShareRow(friend: friend);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedTrackPreview extends StatelessWidget {
  const _SharedTrackPreview({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ArtworkImage(
              uri: track.coverAsset,
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              retryOnNetworkError: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.music_note_rounded, color: accent),
        ],
      ),
    );
  }
}

class _FriendShareRow extends StatelessWidget {
  const _FriendShareRow({required this.friend});

  final SocialUser friend;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '分享给${friend.displayName}',
      child: InkWell(
        key: ValueKey('track-share-friend-${friend.uid}'),
        onTap: () => Navigator.pop(context, friend),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SocialAvatar(user: friend, size: 46),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (friend.status.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        friend.status.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.send_rounded,
                size: 21,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
