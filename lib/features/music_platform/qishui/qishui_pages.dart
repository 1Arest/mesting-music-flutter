import 'qishui_lyrics_page.dart';
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
import 'qishui_effects_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_login_options_page.dart';
import '../presentation/song_actions_sheet.dart';
import 'qishui_models.dart';
import 'qishui_providers.dart';
import 'qishui_repository.dart';
import 'qishui_welfare_page.dart';

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
    if (ref.watch(usesQishuiProvider)) return QishuiRootPage(root);
    if (ref.watch(betaAccountChoiceProvider) != BetaAccountChoice.qishui) {
      return child;
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
                    onPressed: () => Navigator.of(context).push(
                      betaContentRoute<void>(const MusicPlatformSwitchPage()),
                    ),
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
  QishuiMineTab _mineTab = QishuiMineTab.playlists;
  late Future<Map<String, dynamic>> _profile = _music.profile();
  List<QishuiPlaylist> _mineLists = const [];
  Future<Object> _load() => switch (widget.root) {
    QishuiRoot.discover => _music.discover(abortTrigger: _abort.future),
    QishuiRoot.music => ref.read(qishuiFeedScopeProvider).load(),
    QishuiRoot.mine => switch (_mineTab) {
      QishuiMineTab.history => _music.recent(abortTrigger: _abort.future),
      QishuiMineTab.downloads => Future.value(_mineLists),
      QishuiMineTab.playlists => _music.playlists(abortTrigger: _abort.future),
    },
  };
  @override
  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _content = next;
      if (widget.root == QishuiRoot.mine) _profile = _music.profile();
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

  Widget _mineHeader() => FutureBuilder<Map<String, dynamic>>(
    future: _profile,
    builder: (context, profile) {
      final account = ref.watch(platformAccountProvider).value;
      final user = sodaMap(profile.data?['my_info']);
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
              onSwitchPlatform: () => _open(const MusicPlatformSwitchPage()),
              onSettings: () => context.push('/music/settings'),
            ),
          ),
          if (profile.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextButton(
                onPressed: () {
                  final next = _music.profile();
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
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) ref.read(qishuiMusicLyricsProvider.notifier).showCover();
        },
        child: const QishuiLyricsPage(),
      );
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
                      child: Text(
                        '历史播放',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
              ],
              if (widget.root == QishuiRoot.mine &&
                  _mineTab == QishuiMineTab.downloads)
                const QishuiMineDownloads()
              else
                FutureBuilder<Object>(
                  future: _content,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) _lastContent = snapshot.data;
                    final value = snapshot.data ?? _lastContent;
                    if (value == null) {
                      if (snapshot.hasError) {
                        return SliverToBoxAdapter(
                          child: QishuiError(
                            error: snapshot.error!,
                            retry: () => setState(() {
                              _content = _load();
                            }),
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
                    if (snapshot.hasError) {
                      return SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: QishuiError(
                              error: snapshot.error!,
                              retry: () => setState(() {
                                _content = _load();
                              }),
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

class QishuiSearchPage extends ConsumerStatefulWidget {
  const QishuiSearchPage({super.key});
  @override
  ConsumerState<QishuiSearchPage> createState() => _QishuiSearchPageState();
}

class _QishuiSearchPageState extends ConsumerState<QishuiSearchPage>
    with QishuiOwnedPage<QishuiSearchPage> {
  final _query = TextEditingController();
  Future<List<Track>>? _results;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _results = ref
          .read(qishuiRepositoryProvider)
          .search(text, abortTrigger: pageAbort);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    return MusicFeaturePage(
      title: '搜索汽水音乐',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: BetaGlassField(
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  labelText: '歌曲、歌手',
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: () => _search(_query.text),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _results == null
                ? const Center(child: Text('输入关键词，搜索汽水歌曲'))
                : FutureBuilder<List<Track>>(
                    future: _results,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return QishuiError(
                          error: snapshot.error!,
                          retry: () => _search(_query.text),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: MusicActivityIndicator());
                      }
                      final tracks = snapshot.data!;
                      if (tracks.isEmpty) {
                        return const Center(child: Text('没有找到歌曲，试试其他关键词'));
                      }
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
          ),
        ],
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
