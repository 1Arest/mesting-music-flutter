import '../../themes/music_typography.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/share_bridge.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/beta_secondary_music_layout.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../downloads/audio_downloads_page.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_feedback.dart';
import 'qishui_models.dart';
import 'qishui_page_scope.dart';
import 'qishui_playlist_batch_page.dart';
import 'qishui_playlist_tools.dart';
import 'qishui_providers.dart';
import 'qishui_repository.dart';
import 'qishui_playlist_cover_page.dart';
import 'qishui_song_actions.dart';

/// The official collection layout sits on Mesting's existing material and
/// player. Its draft selection, read requests and mutations have separate
/// owners; opening a list never creates an additional player or local library.
class QishuiPlaylistPage extends ConsumerStatefulWidget {
  const QishuiPlaylistPage({
    required this.playlist,
    this.owned = false,
    this.navigationIndex,
    super.key,
  });

  final QishuiPlaylist playlist;
  final bool owned;

  /// Stable shell branch (0 Discover, 1 Music, 3 Mine). Personal collections
  /// belong to Mine even when this page is mounted outside the retained shell.
  final int? navigationIndex;

  @override
  ConsumerState<QishuiPlaylistPage> createState() => _QishuiPlaylistPageState();
}

enum _PlaylistSort { original, title, artist, reverse }

class _QishuiPlaylistPageState extends ConsumerState<QishuiPlaylistPage>
    with QishuiOwnedPage<QishuiPlaylistPage> {
  late final QishuiRepository _music = ref.read(qishuiRepositoryProvider);
  late Future<List<Track>> _tracks = _load();
  final _query = TextEditingController();
  _PlaylistSort _sort = _PlaylistSort.original;
  bool _searching = false;
  bool _busy = false;
  int _playIntent = 0;
  bool? _isPrivate;
  QishuiPlaylist? _updatedPlaylist;
  QishuiPlaylist get _playlist => _updatedPlaylist ?? widget.playlist;

  @override
  void initState() {
    super.initState();
    _isPrivate = widget.playlist.isPrivate;
  }

  Future<List<Track>> _load() =>
      _music.playlist(widget.playlist.id, abortTrigger: pageAbort);

  Future<void> _reload() async {
    if (!ownerCurrent) return;
    final next = _load();
    setState(() {
      _tracks = next;
    });
    await next;
  }

  @override
  void dispose() {
    ++_playIntent;
    _query.dispose();
    super.dispose();
  }

  /// A single-flight action prevents double taps from duplicating writes.
  /// Unknown outcomes are reported by the repository; this page never retries
  /// a mutation automatically and never announces success before readback.
  Future<void> _act(Future<void> Function() action) async {
    if (_busy || !ownerCurrent) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted && ownerCurrent) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Track> _visible(List<Track> values) {
    final query = _query.text.trim().toLowerCase();
    final result = values
        .where(
          (track) =>
              query.isEmpty ||
              '${track.title} ${track.artist} ${track.album}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    switch (_sort) {
      case _PlaylistSort.title:
        result.sort((a, b) => a.title.compareTo(b.title));
      case _PlaylistSort.artist:
        result.sort((a, b) => a.artist.compareTo(b.artist));
      case _PlaylistSort.reverse:
        return result.reversed.toList();
      case _PlaylistSort.original:
        break;
    }
    return result;
  }

  Future<void> _play(
    List<Track> tracks, {
    int index = 0,
    bool random = false,
    bool playAll = false,
  }) => _act(() async {
    if (tracks.isEmpty) return;
    final intent = ++_playIntent;
    final queue = List<Track>.of(tracks);
    if (random) queue.shuffle(Random());
    // The handler and resolver retain the original Qishui track identity;
    // this action has no fallback source or anonymous substitute URL.
    bool current() => ownerCurrent && _music.current && intent == _playIntent;
    final handler = ref.read(audioHandlerProvider);
    if (playAll) {
      await handler.replaceQueue(
        queue,
        initialIndex: index,
        togetherGuard: current,
      );
    } else {
      final selected = queue[random ? 0 : index];
      await handler.playSingleTrack(
        selected,
        playbackContext: [selected],
        discardRecommendations: true,
        isCurrent: current,
      );
    }
  });

  Future<void> _manage(List<Track> tracks) async {
    if (_busy || !ownerCurrent) return;
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      betaContentRoute<bool>(
        QishuiPlaylistBatchPage(
          playlist: _playlist,
          tracks: tracks,
          owned: widget.owned,
        ),
      ),
    );
    if (changed == true && ownerCurrent) await _act(_reload);
  }

  Future<void> _add() async {
    if (!widget.owned || _busy || !ownerCurrent) return;
    final selected = await Navigator.of(context, rootNavigator: true)
        .push<List<Track>>(
          betaContentRoute<List<Track>>(const QishuiPlaylistAddSongsPage()),
        );
    if (selected == null || selected.isEmpty || !ownerCurrent) return;
    await _act(() async {
      await _music.addPlaylistTracks(widget.playlist.id, selected);
      if (!ownerCurrent) return;
      await _reload();
      if (mounted && ownerCurrent) {
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: '已添加到歌单',
          message: '汽水歌单状态已核对',
        );
      }
    });
  }

  Future<void> _remove(List<Track> tracks) async {
    if (!widget.owned || _busy || !ownerCurrent) return;
    if (!await confirmQishuiPlaylistRemoval(context, tracks.length) ||
        !ownerCurrent) {
      return;
    }
    await _act(() async {
      await _music.removePlaylistTracks(widget.playlist.id, tracks);
      if (ownerCurrent) await _reload();
    });
  }

  Future<void> _privacy() async {
    if (!widget.owned || _busy || !ownerCurrent) return;
    final next = await showQishuiPlaylistPrivacy(context, _isPrivate);
    if (next == null || !ownerCurrent) return;
    await _act(() async {
      await _music.setPlaylistPrivate(widget.playlist.id, next);
      if (!mounted || !ownerCurrent) return;
      setState(() => _isPrivate = next);
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: next ? '已设为隐私歌单' : '已设为公开歌单',
        message: '汽水歌单状态已核对',
      );
    });
  }

  Future<void> _menu(List<Track> tracks) async {
    if (_busy || !ownerCurrent) return;
    final action = await showLiquidGlassBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Consumer(
        builder: (context, watch, _) {
          watch.watch(platformAccountProvider);
          if (!ownerCurrent) {
            return const Padding(
              padding: EdgeInsets.all(28),
              child: Text('账号已变化，请关闭后重新操作'),
            );
          }
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheet).height * .8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QishuiPlaylistSheetHeading(
                    playlist: _playlist,
                    currentCount: tracks.length,
                  ),
                  const SizedBox(height: 24),
                  if (widget.owned)
                    ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('更换歌单封面'),
                      onTap: _playlist.kind == 1
                          ? null
                          : () => Navigator.pop(sheet, 'cover'),
                    ),
                  if (widget.owned)
                    ListTile(
                      leading: const Icon(Icons.playlist_add),
                      title: const Text('添加歌曲'),
                      onTap: () => Navigator.pop(sheet, 'add'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.checklist_rounded),
                    title: const Text('批量管理歌曲'),
                    onTap: () => Navigator.pop(sheet, 'manage'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_rounded),
                    title: const Text('下载歌单内歌曲'),
                    onTap: tracks.isEmpty
                        ? null
                        : () => Navigator.pop(sheet, 'download'),
                  ),
                  if (widget.owned)
                    ListTile(
                      leading: Icon(
                        _isPrivate == true
                            ? Icons.lock_outline_rounded
                            : Icons.lock_open_rounded,
                      ),
                      title: const Text('设置歌单隐私'),
                      subtitle: _isPrivate == null
                          ? null
                          : Text(_isPrivate! ? '当前仅自己可见' : '当前公开'),
                      onTap: () => Navigator.pop(sheet, 'privacy'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: const Text('分享歌单'),
                    onTap: () => Navigator.pop(sheet, 'share'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (action == null || !mounted || !ownerCurrent) return;
    switch (action) {
      case 'cover':
        final updated = await Navigator.of(context, rootNavigator: true)
            .push<QishuiPlaylist>(
              betaContentRoute<QishuiPlaylist>(
                QishuiPlaylistCoverPage(playlist: _playlist),
              ),
            );
        if (updated != null && mounted && ownerCurrent) {
          setState(() => _updatedPlaylist = updated);
          showMusicNotice(
            context,
            icon: Icons.check_rounded,
            title: '歌单封面已保存',
            message: '汽水云端封面已核对',
          );
        }
      case 'add':
        await _add();
      case 'manage':
        await _manage(tracks);
      case 'download':
        await _act(() => enqueueAudioDownloads(context, ref, tracks));
      case 'privacy':
        await _privacy();
      case 'share':
        await _share();
    }
  }

  Future<void> _share() =>
      _act(() => ShareBridge.shareText('${widget.playlist.name}（汽水音乐歌单）'));

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    final scheme = Theme.of(context).colorScheme;
    return BetaSecondaryMusicLayout.wrap(
      context,
      Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<List<Track>>(
            future: _tracks,
            builder: (context, snapshot) {
              final tracks = snapshot.data ?? const <Track>[];
              final visible = _visible(tracks);
              return RefreshIndicator(
                onRefresh: () => _act(_reload),
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      automaticallyImplyLeading: false,
                      backgroundColor: scheme.surface.withValues(alpha: .96),
                      leadingWidth: 68,
                      leading: const Center(child: BetaGlassBackButton()),
                      actions: [
                        IconButton(
                          tooltip: '批量管理',
                          onPressed: _busy || tracks.isEmpty
                              ? null
                              : () => _manage(tracks),
                          icon: const Icon(Icons.checklist_rounded),
                        ),
                        IconButton(
                          tooltip: '歌单菜单',
                          onPressed: _busy ? null : () => _menu(tracks),
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    SliverToBoxAdapter(
                      child: _PlaylistHeader(
                        playlist: _playlist,
                        count: snapshot.hasData ? tracks.length : null,
                        isPrivate: _isPrivate,
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          children: [
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (widget.playlist.likeCount != null)
                                  _ReturnedCount(
                                    icon: widget.playlist.collected == true
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border,
                                    count: widget.playlist.likeCount!,
                                    label: '收藏',
                                  ),
                                if (widget.playlist.commentCount != null)
                                  _ReturnedCount(
                                    icon: Icons.mode_comment_outlined,
                                    count: widget.playlist.commentCount!,
                                    label: '评论',
                                  ),
                                TextButton.icon(
                                  onPressed: _share,
                                  icon: const Icon(Icons.share_outlined),
                                  label: Text(
                                    widget.playlist.shareCount == null
                                        ? '分享'
                                        : '${widget.playlist.shareCount}',
                                  ),
                                ),
                                IconButton(
                                  tooltip: '搜索歌单歌曲',
                                  onPressed: () => setState(() {
                                    _searching = !_searching;
                                    if (!_searching) _query.clear();
                                  }),
                                  icon: Icon(
                                    _searching
                                        ? Icons.search_off
                                        : Icons.search,
                                  ),
                                ),
                                PopupMenuButton<_PlaylistSort>(
                                  tooltip: '排序',
                                  initialValue: _sort,
                                  onSelected: (sort) =>
                                      setState(() => _sort = sort),
                                  icon: const Icon(Icons.sort_rounded),
                                  itemBuilder: (_) => [
                                    for (final item in const [
                                      (_PlaylistSort.original, '歌单原始顺序'),
                                      (_PlaylistSort.title, '按歌曲名'),
                                      (_PlaylistSort.artist, '按歌手'),
                                      (_PlaylistSort.reverse, '倒序显示'),
                                    ])
                                      CheckedPopupMenuItem(
                                        value: item.$1,
                                        checked: _sort == item.$1,
                                        child: Text(item.$2),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            if (_searching) ...[
                              BetaGlassField(
                                child: TextField(
                                  controller: _query,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: '搜索本歌单',
                                    prefixIcon: Icon(Icons.search),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final large =
                                    MediaQuery.textScalerOf(context).scale(16) >
                                    24;
                                final width = large
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 12) / 2;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: width,
                                      child: BetaGlassButton(
                                        height: 60,
                                        loading: _busy,
                                        onPressed: visible.isEmpty || _busy
                                            ? null
                                            : () =>
                                                  _play(visible, playAll: true),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.play_arrow),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                '播放全部 ${visible.length}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: width,
                                      child: BetaGlassButton(
                                        height: 60,
                                        accent: true,
                                        onPressed: visible.isEmpty || _busy
                                            ? null
                                            : () =>
                                                  _play(visible, random: true),
                                        child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.shuffle),
                                            SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                '随机选一首',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    if (snapshot.hasError)
                      SliverToBoxAdapter(
                        child: MusicFeatureMessage(
                          message: '${snapshot.error}',
                          onRetry: () => _act(_reload),
                        ),
                      )
                    else if (!snapshot.hasData)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: MusicActivityIndicator()),
                        ),
                      )
                    else if (visible.isEmpty)
                      SliverToBoxAdapter(
                        child: MusicFeatureMessage(
                          message: _query.text.trim().isEmpty
                              ? '歌单里还没有歌曲'
                              : '本歌单没有匹配的歌曲',
                        ),
                      )
                    else
                      SliverList.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) => ListTile(
                          key: ValueKey('qishui-playlist-${visible[index].id}'),
                          contentPadding: const EdgeInsets.fromLTRB(
                            20,
                            10,
                            12,
                            10,
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: TrackArtwork(
                              track: visible[index],
                              width: 48,
                              height: 48,
                            ),
                          ),
                          title: Text(
                            visible[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: MusicTypography.titleWeight,
                            ),
                          ),
                          subtitle: Text(
                            [
                              visible[index].artist,
                              visible[index].album,
                            ].where((value) => value.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: '${visible[index].title}更多操作',
                            onPressed: _busy
                                ? null
                                : () => showQishuiSongActions(
                                    context,
                                    ref,
                                    visible[index],
                                    extras: [
                                      if (widget.owned)
                                        (
                                          '从歌单移除',
                                          Icons.playlist_remove,
                                          () => _remove([visible[index]]),
                                        ),
                                    ],
                                  ),
                            icon: const Icon(Icons.more_vert),
                          ),
                          onTap: _busy
                              ? null
                              : () => _play(visible, index: index),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: BetaContentInsets.musicBottomOf(context),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      selectedIndex: widget.navigationIndex ?? (widget.owned ? 3 : 1),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.count,
    required this.isPrivate,
  });
  final QishuiPlaylist playlist;
  final int? count;
  final bool? isPrivate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        if (playlist.cover.isNotEmpty)
          Positioned.fill(
            child: Opacity(
              opacity: .16,
              child: ArtworkImage(uri: playlist.cover, fit: BoxFit.cover),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.surface.withValues(alpha: .35), scheme.surface],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SizedBox(
                  width: 230,
                  height: 230,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: -.12,
                        child: Container(
                          width: 208,
                          height: 208,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: scheme.onSurface.withValues(alpha: .12),
                              width: 4,
                            ),
                          ),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: 196,
                          height: 196,
                          child: playlist.cover.isEmpty
                              ? ColoredBox(
                                  color: scheme.surfaceContainerHighest,
                                  child: Icon(
                                    playlist.kind == 1
                                        ? Icons.favorite_rounded
                                        : Icons.library_music_rounded,
                                    size: 76,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                )
                              : ArtworkImage(uri: playlist.cover),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                playlist.name,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                [
                  count == null ? '正在读取歌单' : '$count 首歌曲',
                  if (isPrivate != null) isPrivate! ? '隐私歌单' : '公开歌单',
                ].join(' · '),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              if (playlist.ownerName.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  playlist.ownerName,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
              if (playlist.description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  playlist.description,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Social totals are returned metadata, not local counters or evidence that a
/// write endpoint is connected. Only supported actions become tap targets.
class _ReturnedCount extends StatelessWidget {
  const _ReturnedCount({
    required this.icon,
    required this.count,
    required this.label,
  });
  final IconData icon;
  final int count;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Semantics(
      label: '$label $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 5),
          Text('$count'),
        ],
      ),
    ),
  );
}
