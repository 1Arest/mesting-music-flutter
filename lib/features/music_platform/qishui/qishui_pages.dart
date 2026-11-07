import 'qishui_lyrics_page.dart';
import 'qishui_lyrics_back_scope.dart';
import '../../themes/music_typography.dart';
import '../../../shared/widgets/music_feature_page.dart';
import 'dart:async';
import 'qishui_page_scope.dart';
import 'qishui_playlist_grid.dart';
import '../../auth/beta_account_choice.dart';
import 'qishui_login_page.dart';
import 'qishui_now_playing.dart';
import 'qishui_player_navigation.dart';
import 'qishui_feed_mode_menu.dart';
import 'qishui_mine_widgets.dart';
import 'qishui_mine_downloads.dart';
import 'qishui_account_page.dart';
import 'qishui_playlist_page.dart';
import 'qishui_playlist_dialogs.dart';
import '../presentation/platform_feedback.dart';
import '../presentation/platform_display_snapshots.dart';
import '../presentation/platform_home_visit.dart';
import 'qishui_effects_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/cache/browse_response_cache.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/beta_entrance_readiness.dart';
import '../../../shared/widgets/beta_root_tab_viewport.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_login_options_page.dart';
import '../presentation/song_actions_sheet.dart';
import 'qishui_models.dart';
import 'qishui_providers.dart';
import 'qishui_repository.dart';
import 'qishui_history_providers.dart';
import 'qishui_browse_providers.dart';
import 'qishui_welfare_page.dart';
import 'qishui_search_page.dart';

// Keep historical imports source-compatible after separating catalog pages.
export 'qishui_search_page.dart';

enum QishuiRoot { discover, music, mine }

/// Keep the existing four retained Navigator branches (and their historical
/// indices) stable. Soda maps only three visible destinations onto 0/1/3;
/// an old library-root link remains a safe alias of its own Mine page.
class QishuiRootSwitch extends ConsumerWidget {
  const QishuiRootSwitch({required this.root, required this.child, super.key});
  final QishuiRoot root;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(platformAccountProvider);
    final visit = ref.watch(platformHomeVisitProvider);
    Widget surface(Widget child) => PlatformRootSurface(
      key: ValueKey((platformDisplayOwner(account.value), visit, root)),
      home: root == QishuiRoot.discover,
      child: child,
    );
    if (ref.watch(usesQishuiProvider)) return surface(QishuiRootPage(root));
    if (ref.watch(betaAccountChoiceProvider) != BetaAccountChoice.qishui) {
      return surface(child);
    }
    // A pending/broken Soda restore must not mount legacy providers, flash
    // another platform's catalog or silently create a guest Kugou transport.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (account.isLoading) ...[
                  const MusicActivityIndicator(),
                  const SizedBox(height: 20),
                  const Text('正在恢复汽水账号'),
                ] else ...[
                  Text(account.hasError ? '汽水登录资料未能恢复，原有资料已保留。' : '请登录汽水账号'),
                  const SizedBox(height: 20),
                  if (account.hasError)
                    BetaGlassButton(
                      onPressed: () => ref.invalidate(platformAccountProvider),
                      child: const Text('重试恢复'),
                    ),
                  const SizedBox(height: 12),
                  BetaGlassButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(betaContentRoute<bool>(const QishuiLoginPage())),
                    child: const Text('汽水音乐扫码登录'),
                  ),
                  const SizedBox(height: 12),
                  BetaGlassButton(
                    onPressed: () => openMusicPlatformSwitch(context),
                    child: const Text('切换音乐平台'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Each owner/credential gets a fresh page state. Pages never mount the old
/// two-platform providers or retain a previous user's recommendations.
class QishuiRootPage extends ConsumerWidget {
  const QishuiRootPage(this.root, {super.key});
  final QishuiRoot root;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(platformAccountProvider).value;
    return _QishuiContent(
      root: root,
      key: ValueKey(
        'qishui:${account?.ownerId}:${account?.token}:${root.name}',
      ),
    );
  }
}

class _QishuiContent extends ConsumerStatefulWidget {
  const _QishuiContent({required this.root, super.key});
  final QishuiRoot root;
  @override
  ConsumerState<_QishuiContent> createState() => _QishuiContentState();
}

class _QishuiContentState extends ConsumerState<_QishuiContent> {
  final _abort = Completer<void>();
  late final QishuiRepository _music = ref.read(qishuiRepositoryProvider);
  late Future<Object> _content = _load();
  Object? _lastContent;
  late final _displayOwner = platformDisplayOwner(
    ref.read(platformAccountProvider).value,
  );
  late final _snapshots = ref.read(platformDisplaySnapshotsProvider);
  Object? _homeCandidate;
  int _homeGeneration = 0;

  Iterable<String> _homeCovers(Object value) => value is List<QishuiPlaylist>
      ? value.map((v) => v.cover)
      : value is List<Track>
      ? value.map((v) => v.coverAsset)
      : const <String>[];

  void _rememberHome(Object value) => _snapshots.remember(
    _displayOwner,
    'qishui-home',
    value,
    _homeCovers(value),
  );

  Object? _homeValue(Object? incoming) {
    if (incoming == null) return _lastContent;
    if (_lastContent == null) {
      _lastContent = incoming;
      _rememberHome(incoming);
    } else if (!identical(_lastContent, incoming) &&
        !identical(_homeCandidate, incoming) &&
        TickerMode.valuesOf(context).enabled &&
        BetaEntranceReadiness.of(context) &&
        BetaTabVisibility.settledOf(context)) {
      _homeCandidate = incoming;
      unawaited(_prepareHome(incoming, ++_homeGeneration));
    }
    return _lastContent;
  }

  Future<void> _prepareHome(Object incoming, int generation) async {
    bool ready;
    try {
      ready = await _snapshots.prepareReplacement(
        _homeCovers(_lastContent!),
        _homeCovers(incoming),
      );
    } on Object {
      ready = false;
    }
    if (!mounted ||
        !_music.current ||
        generation != _homeGeneration ||
        !ready) {
      return;
    }
    _rememberHome(incoming);
    setState(() => _lastContent = incoming);
  }

  @override
  void initState() {
    super.initState();
    if (widget.root == QishuiRoot.discover) {
      _lastContent = _snapshots.read<Object>(_displayOwner, 'qishui-home');
      _snapshots.seedArtwork(_displayOwner, 'qishui-home');
    }
  }

  QishuiMineTab _mineTab = QishuiMineTab.playlists;
  late Future<Object> _profile = ref.read(
    qishuiBrowseProvider('profile').future,
  );
  List<QishuiPlaylist> _mineLists = const [];
  String get _browsePage => switch (widget.root) {
    QishuiRoot.discover => 'discover',
    QishuiRoot.music => 'music',
    QishuiRoot.mine =>
      _mineTab == QishuiMineTab.history ? 'history' : 'playlists',
  };
  Future<Object> _load() =>
      _mineTab == QishuiMineTab.downloads && widget.root == QishuiRoot.mine
      ? Future.value(_mineLists)
      : ref.read(qishuiBrowseProvider(_browsePage).future);
  @override
  void dispose() {
    _homeGeneration++;
    if (!_abort.isCompleted) _abort.complete();
    super.dispose();
  }

  Future<void> _refresh() async {
    final scope = _music.api.browseScope;
    if (scope != null) _music.api.browseCache.revalidateScope(scope);
    ref.invalidate(qishuiBrowseProvider(_browsePage));
    if (widget.root == QishuiRoot.mine) {
      ref.invalidate(qishuiBrowseProvider('profile'));
    }
    final next = _load();
    setState(() {
      _content = next;
      if (widget.root == QishuiRoot.mine) {
        _profile = ref.read(qishuiBrowseProvider('profile').future);
      }
    });
    try {
      await next;
    } on Object {
      /* FutureBuilder owns the visible error. */
    }
  }

  Widget _dataSliver(Object value) {
    if (value is List<Track>) {
      if (value.isEmpty) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('汽水暂未返回歌曲，下拉重试。'),
          ),
        );
      }
      return SliverList.builder(
        itemCount: value.length,
        itemBuilder: (context, i) =>
            QishuiTrackTile(track: value[i], queue: value),
      );
    }
    final lists = value as List<QishuiPlaylist>;
    if (widget.root == QishuiRoot.mine) {
      _mineLists = lists;
      return QishuiMinePlaylistList(playlists: lists, open: _openPlaylist);
    }
    if (lists.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无歌单，下拉可重新读取。'),
        ),
      );
    }
    return QishuiPlaylistGrid(lists: lists, open: _openPlaylist);
  }

  Future<void> _openPlaylist(QishuiPlaylist list) async {
    await Navigator.of(context).push(
      betaContentRoute<void>(
        QishuiPlaylistPage(
          playlist: list,
          owned: list.kind == 1 || list.ownerId == _music.api.session?.userId,
          navigationIndex: widget.root == QishuiRoot.mine ? 3 : 0,
        ),
      ),
    );
    if (mounted && _music.current && widget.root == QishuiRoot.mine) {
      await _refresh();
    }
  }

  void _selectMode(QishuiFeedMode selected) {
    if (!_music.current) return;
    ref.read(qishuiModeProvider.notifier).select(selected);
    final next = _load();
    setState(() {
      _content = next;
    });
  }

  void _selectMineTab(QishuiMineTab tab) {
    if (_mineTab == tab) return;
    setState(() {
      _mineTab = tab;
      _lastContent = null;
      _content = _load();
    });
  }

  void _open(Widget page) =>
      Navigator.of(context).push(betaContentRoute<void>(page));

  Widget _mineHeader() => FutureBuilder<Object>(
    future: _profile,
    builder: (context, profile) {
      final account = ref.watch(platformAccountProvider).value;
      final profileState = ref.watch(qishuiBrowseProvider('profile'));
      // Dependency reloads can retain an older owner's AsyncData internally.
      // This page has a fresh owner key; do not unwrap that previous payload.
      final cachedProfile = profileState.isReloading
          ? null
          : profileState.value;
      final profileError = profileState.isReloading ? null : profileState.error;
      final user = sodaMap(sodaMap(cachedProfile ?? profile.data)['my_info']);
      final name = '${user['nickname'] ?? account?.nickname ?? ''}';
      final picture = sodaPicture(
        user['larger_avatar_url'] ?? user['medium_avatar_url'],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<Object>(
            future: _content,
            builder: (context, content) => QishuiMineHeader(
              nickname: name,
              avatar: picture.isEmpty ? account?.avatarUrl ?? '' : picture,
              playlists: content.data is List<QishuiPlaylist>
                  ? content.data! as List<QishuiPlaylist>
                  : _mineLists,
              onAccount: () => _open(const QishuiAccountPage()),
              onMembership: () => _open(const QishuiWelfarePage()),
              onEffects: () => _open(const QishuiEffectsPage()),
              onSwitchPlatform: () => openMusicPlatformSwitch(context),
              onSettings: () => context.push('/music/settings'),
            ),
          ),
          if (profileError != null &&
              profileError is! BrowseSnapshotUnavailable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextButton(
                onPressed: () {
                  ref.invalidate(qishuiBrowseProvider('profile'));
                  final next = ref.read(qishuiBrowseProvider('profile').future);
                  setState(() {
                    _profile = next;
                  });
                },
                child: const Text('资料暂未更新，点击重试'),
              ),
            ),
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) {
    final title = switch (widget.root) {
      QishuiRoot.discover => '发现',
      QishuiRoot.music => '音乐',
      QishuiRoot.mine => '我的',
    };
    if (widget.root == QishuiRoot.music &&
        ref.watch(qishuiMusicLyricsProvider)) {
      return const QishuiLyricsBackScope(child: QishuiLyricsPage());
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            key: PageStorageKey('qishui-${widget.root.name}'),
            slivers: [
              if (widget.root != QishuiRoot.mine)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(
                                      fontWeight: MusicTypography.titleWeight,
                                    ),
                              ),
                              if (widget.root == QishuiRoot.music) ...[
                                const SizedBox(width: 14),
                                Flexible(
                                  child: QishuiFeedModeMenu(
                                    load: _music.modes,
                                    selected: ref.watch(qishuiModeProvider),
                                    isCurrent: () => mounted && _music.current,
                                    onSelected: _selectMode,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '搜索汽水音乐',
                          onPressed: () => _open(const QishuiSearchPage()),
                          icon: const Icon(Icons.search),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.root == QishuiRoot.music) ...[
                const SliverToBoxAdapter(child: QishuiNowPlaying()),
              ],
              if (widget.root == QishuiRoot.mine) ...[
                SliverToBoxAdapter(child: _mineHeader()),
                SliverToBoxAdapter(
                  child: QishuiMineTabs(
                    selected: _mineTab,
                    onSelected: _selectMineTab,
                  ),
                ),
                if (_mineTab == QishuiMineTab.playlists)
                  SliverToBoxAdapter(
                    child: QishuiMinePlaylistToolbar(
                      onCreate: () async {
                        await showQishuiCreatePlaylist(context, ref);
                        if (mounted && _music.current) await _refresh();
                      },
                      onImport: () async {
                        await showQishuiImportPlaylist(context, ref);
                        if (mounted && _music.current) await _refresh();
                      },
                    ),
                  ),
                if (_mineTab == QishuiMineTab.history)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '历史播放',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Consumer(
                            builder: (context, ref, _) => Text(
                              ref.watch(qishuiHistoryStatusProvider).message,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (widget.root == QishuiRoot.mine &&
                  _mineTab == QishuiMineTab.downloads)
                const QishuiMineDownloads()
              else
                FutureBuilder<Object>(
                  key: ValueKey('qishui-browse-$_browsePage'),
                  future: _content,
                  builder: (context, snapshot) {
                    // Read the same hydrated provider used during startup.
                    // Riverpod keeps its previous value while revalidating;
                    // the completed FutureBuilder must not paint older data
                    // over a newly published cache snapshot.
                    final cached = ref.watch(qishuiBrowseProvider(_browsePage));
                    // Reloading a dependency (notifying a different identity)
                    // retains AsyncData in Riverpod. The new keyed page may
                    // only use its own Future/local snapshot until it finishes.
                    // Same-owner cache invalidations are refreshes and continue
                    // showing their existing content while work is pending.
                    final currentValue = cached.isReloading
                        ? null
                        : cached.value;
                    final incoming = currentValue ?? snapshot.data;
                    final value = widget.root == QishuiRoot.discover
                        ? _homeValue(incoming)
                        : incoming ?? _lastContent;
                    // The startup Future may have completed with a disk miss
                    // before the same provider starts its normal live read.
                    // Only the provider's current error is authoritative;
                    // a restore-only miss is internal control flow, not a
                    // server refusal or a persistent banner over fresh data.
                    final error =
                        cached.isReloading ||
                            cached.error is BrowseSnapshotUnavailable
                        ? null
                        : cached.error;
                    if (value != null && widget.root != QishuiRoot.discover) {
                      _lastContent = value;
                    }
                    if (value == null) {
                      if (error != null) {
                        return SliverToBoxAdapter(
                          child: QishuiError(
                            error: error,
                            retry: () => unawaited(_refresh()),
                          ),
                        );
                      }
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(child: MusicActivityIndicator()),
                        ),
                      );
                    }
                    final body = _dataSliver(value);
                    if (error != null) {
                      return SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: QishuiError(
                              error: error,
                              retry: () => unawaited(_refresh()),
                            ),
                          ),
                          body,
                        ],
                      );
                    }
                    return body;
                  },
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: BetaContentInsets.musicBottomOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QishuiTrackTile extends ConsumerWidget {
  const QishuiTrackTile({
    required this.track,
    this.queue = const [],
    super.key,
  });
  final Track track;
  final List<Track> queue;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: TrackArtwork(track: track, width: 52, height: 52),
    ),
    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: SongActionsButton(track: track),
    onTap: () async {
      final owner = ref.read(platformAccountProvider).value;
      final music = ref.read(qishuiRepositoryProvider);
      try {
        await ref
            .read(audioHandlerProvider)
            .playSingleTrack(
              track,
              // A row selects one recording; its surrounding list is not an
              // implicit replacement queue. Only the explicit Play All does so.
              playbackContext: [track],
              discardRecommendations: true,
              isCurrent: () =>
                  context.mounted &&
                  music.current &&
                  identical(ref.read(platformAccountProvider).value, owner),
            );
      } on Object catch (e) {
        if (context.mounted) {
          showPlatformFailure(context, e);
        }
      }
    },
  );
}

class QishuiTrackPage extends ConsumerStatefulWidget {
  const QishuiTrackPage({required this.title, required this.load, super.key});
  final String title;
  final Future<List<Track>> Function(Future<void> abort) load;
  @override
  ConsumerState<QishuiTrackPage> createState() => _QishuiTrackPageState();
}

class _QishuiTrackPageState extends ConsumerState<QishuiTrackPage>
    with QishuiOwnedPage<QishuiTrackPage> {
  late Future<List<Track>> _tracks = widget.load(pageAbort);
  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    return MusicFeaturePage(
      title: widget.title,
      child: FutureBuilder<List<Track>>(
        future: _tracks,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return QishuiError(
              error: snapshot.error!,
              retry: () => setState(() {
                _tracks = widget.load(pageAbort);
              }),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: MusicActivityIndicator());
          }
          final tracks = snapshot.data!;
          if (tracks.isEmpty) return const Center(child: Text('暂无歌曲'));
          return ListView.builder(
            padding: EdgeInsets.only(
              bottom: BetaContentInsets.musicBottomOf(context),
            ),
            itemCount: tracks.length,
            itemBuilder: (context, i) =>
                QishuiTrackTile(track: tracks[i], queue: tracks),
          );
        },
      ),
    );
  }
}

class QishuiError extends StatelessWidget {
  const QishuiError({required this.error, required this.retry, super.key});
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(liveRegion: true, child: Text('$error')),
        const SizedBox(height: 20),
        BetaGlassButton(onPressed: retry, child: const Text('重试')),
      ],
    ),
  );
}
