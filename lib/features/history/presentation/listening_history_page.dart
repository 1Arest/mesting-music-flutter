import '../../music_platform/presentation/song_actions_sheet.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../../shared/widgets/music_list_footer.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../core/platform/distribution_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../themes/music_theme_tokens.dart';
import '../listening_history_providers.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../../themes/music_typography.dart';

const double listeningHistoryPrimaryShadowBlurRadius = 10;
const double listeningHistoryAccentShadowBlurRadius = 14;
const double listeningHistoryLightShadowAlpha = .12;
const double listeningHistoryDarkShadowAlpha = .3;

class ListeningHistoryPage extends ConsumerStatefulWidget {
  const ListeningHistoryPage({super.key});

  @override
  ConsumerState<ListeningHistoryPage> createState() =>
      _ListeningHistoryPageState();
}

class _ListeningHistoryPageState extends ConsumerState<ListeningHistoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top + 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _HistoryHeader(onBack: () => context.pop()),
          ),
          const SizedBox(height: 14),
          TabBar(
            controller: _tabController,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: '听歌排行'),
              Tab(text: '最近播放'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                BetaTabScrollRelay(
                  controller: _tabController,
                  index: 0,
                  child: const _RankingList(),
                ),
                BetaTabScrollRelay(
                  controller: _tabController,
                  index: 1,
                  child: const _RecentList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        if (DistributionChannel.isBeta)
          BetaGlassBackButton(
            key: const ValueKey('listening-history-back'),
            onPressed: onBack,
          )
        else
          InkWell(
            key: const ValueKey('listening-history-back'),
            onTap: onBack,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xE71C1722)
                    : Colors.white.withValues(alpha: .76),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: .14)
                      : const Color(0x26596784),
                ),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            ),
          ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '听歌足迹',
                style: TextStyle(
                  fontSize: MusicTypography.sectionTitleSize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '完整听完才会计入次数',
                style: TextStyle(
                  fontSize: MusicTypography.smallCaptionSize,
                  color: Color(0xFF8D858F),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF8EA0F2), Color(0xFFD4DEFF)],
            ),
          ),
          child: const Icon(Icons.equalizer_rounded, color: Colors.white),
        ),
      ],
    );
  }
}

class _RankingList extends ConsumerWidget {
  const _RankingList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(listeningRankingProvider);
    return history.when(
      loading: () => const Center(
        child: MestingLoadingIndicator(
          key: ValueKey('listening-ranking-loading-animation'),
          semanticLabel: '正在加载听歌排行',
        ),
      ),
      error: (_, _) => const _HistoryMessage(
        icon: Icons.cloud_off_rounded,
        title: '听歌记录暂时不可用',
        message: '稍后再来看看你的音乐足迹',
      ),
      data: (items) => items.isEmpty
          ? const _HistoryMessage(
              icon: Icons.graphic_eq_rounded,
              title: '还没有听歌排行',
              message: '完整播放一首歌后，这里就会留下记录',
            )
          : _HistoryList(items: items, ranking: true),
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(recentPlaybackProvider);
    return history.when(
      loading: () => const Center(
        child: MestingLoadingIndicator(
          key: ValueKey('recent-playback-loading-animation'),
          semanticLabel: '正在加载最近播放',
        ),
      ),
      error: (_, _) => const _HistoryMessage(
        icon: Icons.cloud_off_rounded,
        title: '最近播放暂时不可用',
        message: '稍后再来看看你的播放足迹',
      ),
      data: (items) => items.isEmpty
          ? const _HistoryMessage(
              icon: Icons.history_rounded,
              title: '还没有最近播放',
              message: '歌曲实际开始播放后，会按最近时间记录在这里',
            )
          : _HistoryList(items: items, ranking: false),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.items, required this.ranking});

  final List<ListeningHistoryItem> items;
  final bool ranking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = items.map((item) => item.track).toList(growable: false);
    final window = ref.exists(historyTrackWindowProvider(ranking))
        ? ref.watch(historyTrackWindowProvider(ranking))
        : null;
    return ListenableBuilder(
      listenable: window ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) => AutomaticSongPaging(
        songListId: 'listening-history:$ranking',
        enabled:
            window != null &&
            window.hasMore &&
            !window.loading &&
            window.error == null,
        onLoadMore: () => window?.loadMore() ?? Future.value(),
        child: ListView.separated(
          key: ValueKey(
            ranking ? 'listening-ranking-list' : 'recent-playback-list',
          ),
          physics: const ArtworkFrontierPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: BetaContentInsets.musicPaddingOf(
            context,
            EdgeInsets.fromLTRB(16, 6, 16, 170),
          ),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            if (index == items.length) {
              if (window?.loading == true) {
                return const Center(child: MusicActivityIndicator());
              }
              if (window?.error != null) {
                return TextButton(
                  onPressed: window!.loadMore,
                  child: const Text('加载未完成，点击重试'),
                );
              }
              return window?.hasMore == true
                  ? const SizedBox(height: 12)
                  : const MusicListEnd();
            }
            final item = items[index];
            return SongListEntry(
              track: item.track,
              tracks: tracks,
              child: _HistoryTrackRow(
                item: item,
                rank: ranking ? index + 1 : null,
                onTap: () {
                  SongListTools.remember(context, item.track);
                  DistributionChannel.isBeta
                      ? playBetaSelection(context, ref, item.track)
                      : ref
                            .read(audioHandlerProvider)
                            .playSingleTrack(
                              item.track,
                              playbackContext: items.map((item) => item.track),
                            );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HistoryTrackRow extends StatelessWidget {
  const _HistoryTrackRow({
    required this.item,
    required this.rank,
    required this.onTap,
  });

  final ListeningHistoryItem item;
  final int? rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = rank != null && rank! <= 3
        ? const Color(0xFF745CC7)
        : const Color(0xFF8D858F);
    return _HistoryGlassCard(
      key: ValueKey('history-track-${item.track.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 30,
                child: Text(
                  rank!.toString().padLeft(2, '0'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent,
                    fontSize: MusicTypography.captionSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ArtworkImage(
                uri: item.track.coverAsset,
                width: 54,
                height: 54,
                retryOnNetworkError: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: MusicTypography.subheadlineSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8D858F),
                      fontSize: MusicTypography.smallCaptionSize,
                    ),
                  ),
                ],
              ),
            ),
            if (DistributionChannel.isBeta)
              SongActionsButton(track: item.track),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (rank != null)
                  Semantics(
                    label: '完整听完 ${item.completedPlayCount} 次',
                    child: Row(
                      key: ValueKey('completed-play-count-${item.track.id}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_outlined,
                          color: accent,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${item.completedPlayCount}次',
                          style: TextStyle(
                            color: accent,
                            fontSize: MusicTypography.smallCaptionSize,
                            fontWeight: MusicTypography.bodyWeight,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    _recentLabel(item.lastPlayedAt),
                    style: const TextStyle(
                      color: Color(0xFF8D858F),
                      fontSize: MusicTypography.smallCaptionSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                const SizedBox(height: 7),
                const Icon(Icons.play_circle_fill_rounded, size: 22),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryGlassCard extends StatelessWidget {
  const _HistoryGlassCard({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(20);
    final content = onTap == null
        ? child
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: child),
          );
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: tokens.shadow.withValues(
                alpha: dark
                    ? listeningHistoryDarkShadowAlpha
                    : listeningHistoryLightShadowAlpha,
              ),
              blurRadius: listeningHistoryPrimaryShadowBlurRadius,
              spreadRadius: -7,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: accent.withValues(alpha: dark ? .04 : .018),
              blurRadius: listeningHistoryAccentShadowBlurRadius,
              spreadRadius: -12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? .14 : .58),
                width: .8,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: dark ? .07 : .38),
                    tokens.glassStrong.withValues(alpha: dark ? .58 : .66),
                  ),
                  tokens.glass.withValues(alpha: dark ? .54 : .57),
                  Color.alphaBlend(
                    accent.withValues(alpha: dark ? .055 : .025),
                    tokens.glassSubtle.withValues(alpha: dark ? .58 : .54),
                  ),
                ],
                stops: const [0, .52, 1],
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: BetaContentInsets.musicPaddingOf(
        context,
        EdgeInsets.fromLTRB(22, 52, 22, 170),
      ),
      children: [
        _HistoryGlassCard(
          key: const ValueKey('history-empty-glass-card'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
            child: Column(
              children: [
                Icon(icon, size: 38, color: const Color(0xFF745CC7)),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: MusicTypography.bodySize,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8D858F),
                    fontSize: MusicTypography.captionSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _recentLabel(DateTime value) {
  final now = DateTime.now();
  final local = value.toLocal();
  final difference = now.difference(local);
  if (difference.isNegative || difference < const Duration(minutes: 1)) {
    return '刚刚播放';
  }
  if (difference < const Duration(hours: 1)) {
    return '${difference.inMinutes} 分钟前';
  }
  if (difference < const Duration(days: 1)) {
    return '${difference.inHours} 小时前';
  }
  if (difference < const Duration(days: 7)) {
    return '${difference.inDays} 天前';
  }
  return '${local.month}月${local.day}日';
}
