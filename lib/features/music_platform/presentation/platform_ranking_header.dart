import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../../shared/widgets/beta_glass_action.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../library/library_providers.dart';
import '../../player/presentation/beta_playback_actions.dart';
import '../../themes/beta_appearance.dart';
import '../data/platform_explore.dart';
import '../data/music_platform_api.dart';
import '../data/platform_library_repository.dart';
import '../data/platform_ranking.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../platform_explore_providers.dart';
import 'platform_comments_page.dart';
import 'platform_feedback.dart';

/// The chart interaction boundary owns pending state; protocols and complete
/// pagination remain in repositories. Leaving this page cancels publication,
/// never implies cancellation/rollback of an already submitted cloud mutation.
class PlatformRankingHeader extends ConsumerStatefulWidget {
  const PlatformRankingHeader({
    required this.item,
    required this.tracks,
    this.total,
    super.key,
  });
  final PlatformExploreItem item;
  final List<Track> tracks;
  final int? total;
  @override
  ConsumerState<PlatformRankingHeader> createState() => _RankingHeaderState();
}

class _RankingHeaderState extends ConsumerState<PlatformRankingHeader> {
  PlatformRankingInfo? _info;
  late final PlatformSession? _owner;
  PlatformRankingRepository? _repository;
  bool _reading = false,
      _playing = false,
      _saving = false,
      _downloading = false;
  bool get _busy => _playing || _saving || _downloading;
  bool? _subscribed;
  bool _revoked = false;
  String? _error, _snapshotId;
  var _date = DateTime.now();
  bool get _current {
    final now = ref.read(platformAccountProvider).value;
    return mounted &&
        !_revoked &&
        _owner != null &&
        now?.ownerId == _owner.ownerId &&
        now?.token == _owner.token;
  }

  bool get _netease => _owner?.platform == MusicPlatform.netease;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(platformAccountProvider).value;
    if (_owner != null) {
      _repository = PlatformRankingRepository(
        api: ref.read(musicPlatformApiProvider),
        owner: _owner,
        isCurrent: () => _current,
        netease: _netease ? ref.read(neteaseMusicRepositoryProvider) : null,
      );
    }
    unawaited(Future<void>.microtask(_read));
  }

  Future<void> _read() async {
    if (!_current || _reading) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final info = await _repository!.info(widget.item);
      if (!_current) return;
      setState(() {
        _info = info;
        _subscribed = info.subscribed;
      });
      final library = ref.read(libraryRepositoryProvider);
      if (!_netease && library is PlatformLibraryRepository) {
        final saved = await library.findRankingSnapshot(
          info.snapshotName(_date),
        );
        if (_current) setState(() => _snapshotId = saved);
      }
    } catch (_) {
      if (_current) setState(() => _error = '榜单资料读取失败，点击重试');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  PlatformExploreItem get _edition {
    final item = widget.item;
    return PlatformExploreItem(
      id: item.id,
      title: item.title,
      cover: item.cover,
      kind: item.kind,
      rankCid: _info?.period.isNotEmpty == true ? _info!.period : item.rankCid,
    );
  }

  Future<List<Track>> _complete() async {
    if (!_netease && (_info?.period.isEmpty ?? true)) {
      await _read();
      if (_info?.period.isEmpty ?? true) {
        throw const MusicPlatformException('请先重试榜单资料，确认本期期数后再读取完整榜单');
      }
    }
    return _repository!.complete(
      ref.read(platformExploreRepositoryProvider),
      _edition,
    );
  }

  Future<void> _play() async {
    if (!_current || _busy) return;
    setState(() => _playing = true);
    try {
      final all = await _complete();
      if (mounted && _current && all.isNotEmpty) {
        await playBetaSelection(
          context,
          ref,
          all.first,
          playAll: all,
          stillCurrent: () => _current,
        );
      }
    } catch (error) {
      if (mounted && _current) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _save() async {
    if (!_current || _busy) return;
    if (_info == null || _subscribed == null) return _read();
    // Capture the collection date at the start of this operation. A chart page
    // left open overnight must not name today's snapshot with yesterday's date.
    final today = DateTime.now();
    if (!_netease &&
        (_date.year != today.year ||
            _date.month != today.month ||
            _date.day != today.day)) {
      _date = today;
      _snapshotId = null;
    }
    setState(() => _saving = true);
    try {
      if (_netease) {
        await _repository!.subscribe(widget.item, !_subscribed!);
        if (_current) setState(() => _subscribed = null);
        // Re-read authoritative state after success; a timeout never causes
        // an automatic second subscribe/unsubscribe mutation.
        await _read();
      } else {
        final all = await _complete();
        if (!_current) return;
        final library = ref.read(libraryRepositoryProvider);
        if (library is! PlatformLibraryRepository) return;
        final id = await library.saveRankingSnapshot(
          draftId: 'ranking:${widget.item.id}:${_info!.snapshotName(_date)}',
          name: _info!.snapshotName(_date),
          tracks: all,
        );
        if (!mounted || !_current) return;
        setState(() => _snapshotId = id);
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: '已收藏本期 ${all.length} 首歌曲',
          message: '已保存到酷狗云歌单，不随榜单自动更新',
        );
      }
    } catch (error) {
      // The outcome of a remote write can be ambiguous. Clear the NetEase
      // toggle so the next tap reconciles state before making another change.
      if (mounted && _current) {
        if (_netease) setState(() => _subscribed = null);
        showPlatformFailure(context, error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _comments() async {
    if (!_current) return;
    var id = widget.item.id;
    if (!_netease) {
      if (_snapshotId == null) {
        showMusicNotice(
          context,
          icon: Icons.info_outline,
          title: '请先收藏本期榜单',
          message: '评论属于收藏后生成的酷狗云歌单',
        );
        return;
      }
      final library = ref.read(libraryRepositoryProvider);
      if (library is! PlatformLibraryRepository) return;
      try {
        id = await library.commentId(_snapshotId!);
      } catch (error) {
        if (mounted && _current) showPlatformFailure(context, error);
        return;
      }
    }
    if (mounted && _current) {
      openPlatformPlaylistComments(
        context,
        ref,
        id: id,
        name: _netease ? widget.item.title : _info!.snapshotName(_date),
      );
    }
  }

  Future<void> _share() async {
    if (!_current) return;
    final info =
        _info ??
        PlatformRankingInfo(item: widget.item, platform: _owner!.platform);
    try {
      await ShareBridge.shareText(
        '${widget.item.title}\n${info.shareUri}',
        title: widget.item.title,
      );
    } catch (error) {
      if (mounted && _current) showPlatformFailure(context, error);
    }
  }

  Future<void> _download() async {
    if (!_current || _busy) return;
    setState(() => _downloading = true);
    try {
      final all = await _complete();
      if (mounted && _current) await enqueueAudioDownloads(context, ref, all);
    } catch (error) {
      if (mounted && _current) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _details() {
    if (_info == null) {
      unawaited(_read());
      return;
    }
    showLiquidGlassBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.item.title,
              style: Theme.of(sheet).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              _info!.description.isEmpty ? '平台暂未提供榜单介绍' : _info!.description,
            ),
            if (!_netease)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('收藏保留本期歌曲，之后可在酷狗云歌单中管理。'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    ref.listen(platformAccountProvider, (before, after) {
      if (before?.value?.ownerId != after.value?.ownerId ||
          before?.value?.token != after.value?.token) {
        _revoked = true;
      }
    });
    if (!_current) return const SizedBox.shrink();
    final total = _info?.total ?? widget.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlatformCollectionMasthead(
          title: widget.item.title,
          platform: _owner!.platform,
          cover: _info?.cover ?? widget.item.cover,
          updatedAt: _info?.updatedAt,
          period: _info?.period ?? '',
          onSearch: () => GoRouter.maybeOf(context)?.push('/music/search'),
          onDetails: _details,
          actions: [
            PlatformCollectionAction(
              id: 'save',
              label: _saving
                  ? '收藏中'
                  : _netease
                  ? (_subscribed == true ? '已收藏' : '收藏')
                  : '收藏本期',
              icon: _subscribed == true && _netease || _snapshotId != null
                  ? Icons.library_add_check_outlined
                  : Icons.library_add_outlined,
              count: _info?.collections,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
            PlatformCollectionAction(
              id: 'comments',
              label: _netease ? '评论' : '歌单评论',
              icon: Icons.chat_bubble_outline,
              count: _info?.comments,
              onPressed: _busy ? null : () => unawaited(_comments()),
            ),
            PlatformCollectionAction(
              id: 'share',
              label: '分享',
              icon: Icons.share_outlined,
              count: _info?.shares,
              onPressed: _busy ? null : () => unawaited(_share()),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: TextButton(
              onPressed: _reading ? null : _read,
              child: Text(_error!),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const ValueKey('ranking-play-all'),
                  onPressed: widget.tracks.isEmpty || _busy ? null : _play,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: BetaAppearance.playbackAction(
                            Theme.of(context).brightness,
                          ),
                        ),
                        child: _playing
                            ? const BetaActivityIndicator(
                                color: Colors.white,
                                radius: 8,
                              )
                            : const Icon(
                                Icons.play_arrow_rounded,
                                size: 21,
                                color: Colors.white,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: _playing ? '读取完整榜单' : '播放全部'),
                              if (total != null)
                                TextSpan(
                                  text: '（$total）',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_downloading)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: BetaActivityIndicator(),
                )
              else
                BetaGlassAction(
                  label: '下载完整榜单',
                  icon: Icons.download_outlined,
                  blue: false,
                  onPressed: _busy || widget.tracks.isEmpty
                      ? null
                      : () => unawaited(_download()),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Presentation-only masthead: official update dates and counts are supplied by
/// the repository, never synthesized from the local clock or loaded row count.
class PlatformCollectionMasthead extends StatelessWidget {
  const PlatformCollectionMasthead({
    super.key,
    required this.title,
    required this.platform,
    required this.cover,
    required this.period,
    required this.actions,
    required this.onSearch,
    required this.onDetails,
    this.updatedAt,
    this.secondary,
  });
  final String? secondary;
  final String title, cover, period;
  final MusicPlatform platform;
  final DateTime? updatedAt;
  final List<PlatformCollectionAction> actions;
  final VoidCallback onSearch, onDetails;
  @override
  Widget build(BuildContext context) {
    final netease = platform == MusicPlatform.netease;
    final updated = updatedAt;
    final date =
        secondary ??
        (updated != null
            ? '${updated.month}月${updated.day}日更新'
            : period.isNotEmpty
            ? '第$period期'
            : '官方榜单');
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white70,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: netease
                              ? const [Color(0xFF8E292F), Color(0xFFAC4C53)]
                              : const [Color(0xFF144F70), Color(0xFF367C95)],
                        ),
                      ),
                    ),
                  ),
                  if (cover.isNotEmpty)
                    Positioned.fill(
                      child: Opacity(
                        opacity: .16,
                        child: ArtworkImage(uri: cover, fit: BoxFit.cover),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, top + 10, 20, 50),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const BetaGlassBackButton(),
                            const Spacer(),
                            BetaGlassAction(
                              label: '搜索歌曲',
                              icon: Icons.search_rounded,
                              blue: false,
                              onPressed: onSearch,
                            ),
                            const SizedBox(width: 8),
                            BetaGlassAction(
                              label: '榜单介绍',
                              icon: Icons.more_vert,
                              blue: false,
                              onPressed: onDetails,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.music_note_rounded,
                              size: 17,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              netease ? '网易云音乐' : '酷狗音乐',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          key: const ValueKey('ranking-masthead-title'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 42,
                            height: 1.12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 0,
            child: _RankingActionCapsule(actions: actions),
          ),
        ],
      ),
    );
  }
}

/// Keep a compact title/back control available once the large masthead scrolls
/// away. Horizontal drags within the action capsule never collapse this bar.
class PlatformRankingScrollShell extends StatefulWidget {
  const PlatformRankingScrollShell({
    required this.title,
    required this.child,
    super.key,
  });
  final String title;
  final Widget child;
  @override
  State<PlatformRankingScrollShell> createState() => _RankingScrollShellState();
}

class _RankingScrollShellState extends State<PlatformRankingScrollShell> {
  bool _collapsed = false;
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (scroll) {
          if (scroll.depth == 0 && scroll.metrics.axis == Axis.vertical) {
            final next = scroll.metrics.pixels > 170;
            if (next != _collapsed) setState(() => _collapsed = next);
          }
          return false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_collapsed)
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          const BetaGlassBackButton(
                            key: ValueKey('ranking-collapsed-back'),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class PlatformCollectionAction {
  const PlatformCollectionAction({
    required this.id,
    required this.label,
    required this.icon,
    this.count,
    this.onPressed,
  });
  final String id, label;
  final IconData icon;
  final int? count;
  final VoidCallback? onPressed;
  String get caption => count == null
      ? label
      : count! >= 100000000
      ? '${(count! / 100000000).toStringAsFixed(1)}亿'
      : count! >= 10000
      ? '${(count! / 10000).toStringAsFixed(1)}万'
      : '$count';
}

/// One shared glass lens matches the reference's compact, divided capsule.
/// At large text sizes it scrolls horizontally so captions keep their text
/// scale and every action remains reachable instead of shrinking or clipping.
class _RankingActionCapsule extends StatelessWidget {
  const _RankingActionCapsule({required this.actions});
  final List<PlatformCollectionAction> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final widths = <double>[];
      for (final action in actions) {
        final painter = TextPainter(
          text: TextSpan(
            text: action.caption,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          textScaler: scaler,
          textDirection: Directionality.of(context),
        )..layout();
        widths.add(
          (painter.width + 48).clamp(
            (constraints.maxWidth - 2) / 3,
            double.infinity,
          ),
        );
        painter.dispose();
      }
      final height = (scaler.scale(12) + 30)
          .clamp(52, double.infinity)
          .toDouble();
      return RepaintBoundary(
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          shape: const LiquidRoundedRectangle(borderRadius: 40),
          settings: betaNeutralActionGlass(
            context,
          ).copyWith(glassColor: const Color(0xF239393F)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0)
                      Container(width: 1, height: 22, color: Colors.white24),
                    BetaGlassButton(
                      key: ValueKey('ranking-action-${actions[i].id}'),
                      label:
                          '${actions[i].label}${actions[i].count == null ? '' : '，${actions[i].count}'}',
                      width: widths[i],
                      height: height,
                      horizontalPadding: 8,
                      embeddedInPill: true,
                      onPressed: actions[i].onPressed,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(actions[i].icon, size: 20, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            actions[i].caption,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
