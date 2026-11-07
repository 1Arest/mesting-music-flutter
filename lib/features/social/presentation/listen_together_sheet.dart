import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../auth/auth_providers.dart';
import '../domain/listen_together.dart';
import '../domain/social_models.dart';
import '../listen_together_providers.dart';
import '../social_providers.dart';
import 'social_widgets.dart';

enum ListenTogetherSheetAction { leave, invite }

Future<SocialUser?> showListenTogetherInviteSheet({
  required BuildContext context,
  required Track track,
}) {
  return showLiquidGlassBottomSheet<SocialUser>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _ListenTogetherInviteSheet(track: track),
  );
}

Future<ListenTogetherSheetAction?> showListenTogetherStatusSheet({
  required BuildContext context,
  required ListenTogetherSession session,
}) {
  return showLiquidGlassBottomSheet<ListenTogetherSheetAction>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _ListenTogetherStatusSheet(session: session),
  );
}

String formatListenTogetherDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

class _ListenTogetherInviteSheet extends ConsumerWidget {
  const _ListenTogetherInviteSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(
      socialConnectionsProvider(SocialConnectionKind.following),
    );
    final height = (MediaQuery.sizeOf(context).height * .72)
        .clamp(400.0, 640.0)
        .toDouble();
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      key: const ValueKey('listen-together-invite-sheet'),
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
                        '好友一起听',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text('邀请一位互相关注的好友进入同一播放空间'),
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
            child: Container(
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
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.headphones_rounded, color: accent),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '可邀请好友',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: connections.when(
              loading: () => const SocialLoadingState(message: '正在读取好友列表'),
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
                        title: '还没有可以一起听的好友',
                        message: '与对方互相关注后，就能邀请对方进入一起听。',
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
                    return InkWell(
                      key: ValueKey('listen-together-friend-${friend.uid}'),
                      onTap: () => Navigator.pop(context, friend),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            SocialAvatar(user: friend, size: 46),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                friend.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Icon(Icons.person_add_alt_1_rounded, color: accent),
                          ],
                        ),
                      ),
                    );
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

class _ListenTogetherStatusSheet extends ConsumerStatefulWidget {
  const _ListenTogetherStatusSheet({required this.session});

  final ListenTogetherSession session;

  @override
  ConsumerState<_ListenTogetherStatusSheet> createState() =>
      _ListenTogetherStatusSheetState();
}

class _ListenTogetherStatusSheetState
    extends ConsumerState<_ListenTogetherStatusSheet> {
  Timer? _clock;
  Future<List<ListenTogetherTrackRecord>>? _records;
  String? _recordsUid;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveSession =
        ref.watch(listenTogetherControllerProvider).value ?? widget.session;
    final current = ref.watch(currentUserProvider);
    final currentSocial = SocialUser(
      uid: current?.uid ?? '',
      nickname: current?.nickname ?? '我',
      avatarUrl: current?.avatarUrl,
    );
    if (_records == null || _recordsUid != liveSession.peer.uid) {
      _recordsUid = liveSession.peer.uid;
      _records = ref
          .read(listenTogetherControllerProvider.notifier)
          .records(liveSession.peer.uid);
    }
    final height = (MediaQuery.sizeOf(context).height * .72)
        .clamp(430.0, 660.0)
        .toDouble();
    return SizedBox(
      key: const ValueKey('listen-together-status-sheet'),
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '一起听空间',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
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
          _TogetherPairSummary(session: liveSession, current: currentSocial),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '一起听音乐记录',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ListenTogetherTrackRecord>>(
              future: _records,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SocialLoadingState(message: '正在读取一起听记录');
                }
                if (snapshot.hasError) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    children: [
                      SocialErrorCard(
                        error: snapshot.error!,
                        onRetry: () {
                          setState(() => _records = null);
                        },
                      ),
                    ],
                  );
                }
                final values = snapshot.data ?? const [];
                if (values.isEmpty) {
                  return const Center(child: Text('一起听过的音乐会记录在这里'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: values.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final record = values[index];
                    return ListTile(
                      key: ValueKey(
                        'listen-together-record-${record.track.id}',
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ArtworkImage(
                          uri: record.track.coverAsset,
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                          retryOnNetworkError: true,
                        ),
                      ),
                      title: Text(
                        record.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        record.track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '听了 ${record.playCount} 次',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Row(
              children: [
                if (liveSession.isActive || liveSession.isPending)
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('listen-together-leave'),
                      onPressed: () => Navigator.pop(
                        context,
                        ListenTogetherSheetAction.leave,
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(liveSession.isPending ? '取消邀请' : '结束一起听'),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('listen-together-invite-again'),
                      onPressed: () => Navigator.pop(
                        context,
                        ListenTogetherSheetAction.invite,
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('再次邀请好友'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TogetherPairSummary extends StatelessWidget {
  const _TogetherPairSummary({required this.session, required this.current});

  final ListenTogetherSession session;
  final SocialUser current;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final duration = formatListenTogetherDuration(
      session.accumulatedDurationAt(),
    );
    final status = switch (session.status) {
      ListenTogetherStatus.pending => '等待${session.peer.displayName}加入',
      ListenTogetherStatus.active =>
        session.bothPresent ? '正在一起听 · $duration' : '等待好友重新连接 · $duration',
      ListenTogetherStatus.ended => '累计一起听 $duration',
      ListenTogetherStatus.declined => '上次邀请未加入',
      ListenTogetherStatus.expired => '上次邀请已失效',
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 48,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: SocialAvatar(user: current, size: 46),
                ),
                Positioned(
                  right: 0,
                  child: SocialAvatar(user: session.peer, size: 46),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我和 ${session.peer.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(status, style: TextStyle(color: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
