import '../../../shared/widgets/music_feature_page.dart';
import 'dart:async';
import 'qishui_page_scope.dart';
import 'qishui_playlist_grid.dart';
import '../../auth/beta_account_choice.dart';
import 'qishui_login_page.dart';
import 'qishui_now_playing.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
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
import '../../downloads/audio_downloads_page.dart';
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
  Future<Object> _load() => switch (widget.root) {
    QishuiRoot.discover => _music.discover(abortTrigger: _abort.future),
    QishuiRoot.music => ref.read(qishuiFeedScopeProvider).load(),
    QishuiRoot.mine => _music.playlists(abortTrigger: _abort.future),
  };
  @override
  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _content = next);
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
    if (lists.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无歌单，下拉可重新读取。'),
        ),
      );
    }
    return QishuiPlaylistGrid(
      lists: lists,
      open: (list) => _open(
        QishuiTrackPage(
          title: list.name,
          load: (abort) => _music.playlist(list.id, abortTrigger: abort),
        ),
      ),
    );
  }

  Future<void> _chooseMode() async {
    final modes = _music.modes();
    final selected = await showLiquidGlassBottomSheet<QishuiFeedMode>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => FutureBuilder<List<QishuiFeedMode>>(
        future: modes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: MusicActivityIndicator(),
            );
          }
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheet).height * .7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                Text('听歌模式', style: Theme.of(sheet).textTheme.titleLarge),
                for (final mode in snapshot.data!)
                  ListTile(
                    title: Text(mode.name),
                    onTap: () => Navigator.of(sheet).pop(mode),
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (selected == null || !mounted || !_music.current) return;
    ref.read(qishuiModeProvider.notifier).select(selected);
    setState(() => _content = _load());
  }

  void _open(Widget page) =>
      Navigator.of(context).push(betaContentRoute<void>(page));
  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    final title = switch (widget.root) {
      QishuiRoot.discover => '发现',
      QishuiRoot.music => '音乐',
      QishuiRoot.mine => '我的',
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            key: PageStorageKey('qishui-${widget.root.name}'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  sliver: SliverToBoxAdapter(
                    child: BetaGlassButton(
                      onPressed: _chooseMode,
                      child: Text(
                        ref.watch(qishuiModeProvider)?.name ?? '选择听歌模式',
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: QishuiNowPlaying()),
              ],
              if (widget.root == QishuiRoot.mine)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          account?.nickname.isNotEmpty == true
                              ? account!.nickname
                              : '汽水账号',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text('汽水音乐'),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            BetaGlassButton(
                              onPressed: () => _open(const QishuiEffectsPage()),
                              child: const Text('官版音效'),
                            ),
                            BetaGlassButton(
                              onPressed: () => _open(
                                QishuiTrackPage(
                                  title: '我喜欢的音乐',
                                  load: (abort) =>
                                      _music.favorites(abortTrigger: abort),
                                ),
                              ),
                              child: const Text('我喜欢的音乐'),
                            ),
                            BetaGlassButton(
                              onPressed: () => _open(const QishuiWelfarePage()),
                              child: const Text('免费听与权益'),
                            ),
                            BetaGlassButton(
                              onPressed: () =>
                                  _open(const AudioDownloadsPage()),
                              child: const Text('已下载'),
                            ),
                            BetaGlassButton(
                              onPressed: () => _open(
                                QishuiTrackPage(
                                  title: '播放历史',
                                  load: (abort) =>
                                      _music.recent(abortTrigger: abort),
                                ),
                              ),
                              child: const Text('播放历史'),
                            ),
                            BetaGlassButton(
                              onPressed: () =>
                                  _open(const MusicPlatformSwitchPage()),
                              child: const Text('切换平台'),
                            ),
                            BetaGlassButton(
                              onPressed: () => context.push('/music/settings'),
                              child: const Text('设置'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '我的歌单',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ),
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
                          retry: () => setState(() => _content = _load()),
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
                            retry: () => setState(() => _content = _load()),
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
              playbackContext: queue.isEmpty ? [track] : queue,
              replaceUpcoming: true,
              isCurrent: () =>
                  context.mounted &&
                  music.current &&
                  identical(ref.read(platformAccountProvider).value, owner),
            );
      } on Object catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
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
              retry: () => setState(() => _tracks = widget.load(pageAbort)),
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
    setState(
      () => _results = ref
          .read(qishuiRepositoryProvider)
          .search(text, abortTrigger: pageAbort),
    );
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
