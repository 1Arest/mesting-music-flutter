import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'package:flutter/cupertino.dart';
import 'netease_library_sections.dart';
import 'package:flutter/material.dart';
import '../../../core/cache/cached_browse_loader.dart';
import '../../../core/cache/cached_browse_provider.dart';
import '../platform_browse_cache.dart';
import '../platform_catalog_providers.dart';
import '../platform_recommendation_providers.dart';
import '../presentation/retained_platform_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../../shared/widgets/route_settled_content.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../experience/presentation/editorial_widgets.dart';
import '../data/platform_category_search.dart';
import '../data/platform_explore.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../presentation/music_mv_page.dart';
import '../presentation/platform_catalog_detail_page.dart';
import '../presentation/platform_design.dart';
import '../presentation/platform_feedback.dart';
import '../presentation/platform_search_landing.dart';
import '../presentation/platform_recommendations_page.dart';
import '../../experience/presentation/music_home_catalogues.dart';
import 'netease_cloud_upload.dart';
import 'netease_features_repository.dart';
import 'netease_membership_page.dart';
import '../data/platform_comments_repository.dart';
import '../presentation/platform_comments_page.dart';
import 'netease_comments_repository.dart';
import '../../downloads/audio_downloads_page.dart';
import 'netease_playlist_import_page.dart';
import 'full/netease_full_page.dart';

final neteaseFeaturesProvider = Provider<NeteaseFeaturesRepository>(
  (ref) => NeteaseFeaturesRepository(ref.watch(neteaseMusicRepositoryProvider)),
);

final neteaseFeedPreviewProvider = FutureProvider.autoDispose
    .family<NeteaseBatch, NeteaseFeed>((ref, feed) async {
      await ref.watch(platformAccountProvider.future);
      return cachedBrowse(
        ref,
        () => ref.watch(neteaseFeaturesProvider).load(feed),
      );
    });

/// A NetEase composition replaces the Kugou feed modes while retaining the
/// incumbent row, shelf, header, artwork and navigation primitives.
class NeteaseDiscoveryPage extends ConsumerWidget {
  const NeteaseDiscoveryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PlatformStyle(
    child: EditorialScroll(
      onRefresh: () => refreshBrowse(ref, [
        () => ref.refresh(platformDailyProvider.future),
        if (ref.exists(platformFmProvider))
          () => ref.refresh(platformFmProvider.future),
        if (ref.exists(platformNewSongsProvider))
          () => ref.refresh(platformNewSongsProvider.future),
        if (ref.exists(platformExploreProvider(PlatformExploreKind.rank)))
          () => ref.refresh(
            platformExploreProvider(PlatformExploreKind.rank).future,
          ),
        for (final feed in [
          NeteaseFeed.recommended,
          NeteaseFeed.premium,
          NeteaseFeed.albums,
          NeteaseFeed.artists,
          NeteaseFeed.mvs,
        ])
          if (ref.exists(neteaseFeedPreviewProvider(feed)))
            () => ref.refresh(neteaseFeedPreviewProvider(feed).future),
      ]),
      children: const [
        EditorialHeader('发现'),
        PlatformRecommendedSection(title: '每日推荐'),
        PlatformFmSection(),
        NeteaseHomeShelf(feed: NeteaseFeed.recommended),
        NeteaseHomeShelf(feed: NeteaseFeed.premium),
        MusicHomeCatalogueShelf(PlatformExploreKind.rank),
        PlatformRecommendedSection(title: '新歌速递', newSongs: true),
        NeteaseHomeShelf(feed: NeteaseFeed.albums),
        NeteaseHomeShelf(feed: NeteaseFeed.artists),
        NeteaseHomeShelf(feed: NeteaseFeed.mvs),
        NeteaseFullNavigation(tab: '发现'),
      ],
    ),
  );
}

class NeteaseHomeShelf extends ConsumerWidget {
  const NeteaseHomeShelf({required this.feed, super.key});
  final NeteaseFeed feed;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = NeteaseFeaturesRepository.titles[feed]!;
    // A restored provider already has pixels/data. Route deferral is for live
    // work only; blanking a restored shelf until an animation settles causes a
    // second cold-start flash despite successfully restored disk snapshots.
    final restored = ref.watch(neteaseFeedPreviewProvider(feed)).hasValue;
    Widget contents(BuildContext context) => Consumer(
      builder: (context, ref, _) => RetainedPlatformSnapshot(
        value: ref.watch(neteaseFeedPreviewProvider(feed)),
        artwork: (batch) => batch.items.map((item) => item.cover),
        loading: () => const PlatformFeedbackState(loading: true),
        error: (_, _) => EditorialEmpty(
          '$title暂时无法加载',
          onRetry: () => ref.invalidate(neteaseFeedPreviewProvider(feed)),
        ),
        data: (batch) => batch.items.isEmpty
            ? EditorialEmpty('暂无$title')
            : EditorialShelf(
                height: 248,
                children: [
                  for (final item in batch.items.take(12))
                    EditorialCover(
                      cover: item.cover,
                      title: item.name,
                      subtitle: item.subtitle,
                      width: 170,
                      onTap: () => openNeteaseItem(context, item),
                    ),
                ],
              ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorialSection(title, onTap: () => openNeteaseFeed(context, feed)),
        if (restored)
          contents(context)
        else
          RouteSettledContent(
            placeholder: const SizedBox(height: 248),
            builder: contents,
          ),
      ],
    );
  }
}

void openNeteaseFeed(
  BuildContext context,
  NeteaseFeed feed, {
  String id = '',
  String? title,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NeteaseFeaturesPage(feed: feed, id: id, title: title),
    ),
  );
}

void openNeteaseItem(BuildContext context, NeteaseItem item) {
  final Widget page;
  switch (item.kind) {
    case NeteaseEntity.podcast:
      openNeteaseFeed(
        context,
        NeteaseFeed.podcastPrograms,
        id: item.id,
        title: item.name,
      );
      return;
    case NeteaseEntity.podcastCategory:
      openNeteaseFeed(
        context,
        NeteaseFeed.podcastCategory,
        id: item.id,
        title: item.name,
      );
      return;
    case NeteaseEntity.date:
      openNeteaseFeed(
        context,
        NeteaseFeed.historySongs,
        id: item.id,
        title: item.name,
      );
      return;
    case NeteaseEntity.user:
      openNeteaseFeed(
        context,
        NeteaseFeed.userPlaylists,
        id: item.id,
        title: '${item.name}的歌单',
      );
      return;
    case NeteaseEntity.program:
      return;
    case NeteaseEntity.category:
      openNeteaseFeed(
        context,
        NeteaseFeed.category,
        id: item.name,
        title: item.name,
      );
      return;
    case NeteaseEntity.album:
    case NeteaseEntity.artist:
      page = PlatformCatalogDetailPage(
        hit: PlatformSearchHit(
          kind: item.kind == NeteaseEntity.artist
              ? PlatformSearchKind.artists
              : PlatformSearchKind.albums,
          id: item.id,
          globalId: item.id,
          title: item.name,
          subtitle: item.subtitle,
          cover: item.cover,
        ),
      );
    case NeteaseEntity.playlist:
      page = PlatformExploreSongsPage(
        item: PlatformExploreItem(
          id: item.id,
          title: item.name,
          cover: item.cover,
          kind: PlatformExploreKind.playlist,
          subtitle: item.subtitle,
        ),
      );
    case NeteaseEntity.mv:
      page = MusicMvPage(
        mvId: item.id,
        track: Track(
          id: 'netease_mv_${item.id}',
          title: item.name,
          artist: item.subtitle,
          album: '',
          duration: Duration.zero,
          audioAsset: '',
          coverAsset: item.cover,
          lyricsAsset: '',
          source: TrackSource.netease,
          provider: '网易云音乐',
        ),
      );
    case NeteaseEntity.song:
      return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

/// Each page owns its pagination and the account epoch from which it opened.
/// A platform switch blocks all old controls instead of letting a stale page
/// create new requests under a different account.
class NeteaseFeaturesPage extends ConsumerStatefulWidget {
  const NeteaseFeaturesPage({
    required this.feed,
    this.id = '',
    this.title,
    super.key,
  });
  final NeteaseFeed feed;
  final String id;
  final String? title;
  @override
  ConsumerState<NeteaseFeaturesPage> createState() =>
      _NeteaseFeaturesPageState();
}

class _NeteaseFeaturesPageState extends ConsumerState<NeteaseFeaturesPage> {
  final _browse = CachedBrowseLoader();
  final _items = <NeteaseItem>[];
  int _page = 0, _cursor = 0, _generation = 0;
  bool _busy = false, _more = true, _writing = false;
  String? _error, _owner, _token;
  String _area = 'ALL';
  int _artistArea = 1;
  bool get _current {
    final account = ref.read(platformAccountProvider).value;
    return ref.read(usesNeteaseProvider) &&
        account?.ownerId == _owner &&
        account?.token == _token;
  }

  @override
  void initState() {
    super.initState();
    final account = ref.read(platformAccountProvider).value;
    _owner = account?.ownerId;
    _token = account?.token;
    Future.microtask(() => _load(reset: true));
  }

  @override
  void dispose() {
    _browse.dispose();
    _generation++;
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!_current || (_busy && !reset) || (!_more && !reset)) return;
    final generation = reset ? ++_generation : _generation;
    if (reset) _browse.reset();
    if (reset) revalidateBrowse(ref);
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _page = 0;
        _cursor = 0;
        _more = true;
        _items.clear();
      }
    });
    try {
      final page = _page + 1, before = _cursor;
      final repository = ref.read(neteaseFeaturesProvider);
      final batch = await _browse.load(
        key: page,
        request: () => repository.load(
          widget.feed,
          page: page,
          before: before,
          id: widget.id,
          category: widget.feed == NeteaseFeed.category ? widget.id : '全部',
          area: _area,
          artistArea: _artistArea,
        ),
        onUpdate: (previous, current) {
          if (!mounted || generation != _generation || !_current) return;
          setState(() {
            replaceBrowsePage(
              _items,
              previous.items,
              current.items,
              (item) => '${item.kind}:${item.id}',
            );
            if (page == _page) {
              _cursor = current.cursor;
              _more = current.more;
            }
          });
        },
      );
      if (!mounted || generation != _generation || !_current) return;
      setState(() {
        final ids = _items.map((i) => '${i.kind}:${i.id}').toSet();
        final added = batch.items
            .where((i) => i.id.isNotEmpty && ids.add('${i.kind}:${i.id}'))
            .toList();
        _items.addAll(added);
        _page++;
        _cursor = batch.cursor;
        _more = batch.more && added.isNotEmpty;
      });
    } catch (error) {
      if (mounted && generation == _generation && _current) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCloud(NeteaseItem item) async {
    if (_writing || !_current) return;
    final yes = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: const Text('从网易云云盘删除？'),
        content: Text('“${item.name}”将从当前账号云盘移除，本地原文件保留。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !_current) return;
    setState(() => _writing = true);
    try {
      await ref.read(neteaseMusicRepositoryProvider).call('/user/cloud/del', {
        'ids': [item.id],
      });
      if (mounted && _current) await _load(reset: true);
    } catch (e) {
      if (mounted) showPlatformFailure(context, e);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _upload() async {
    if (_writing || !_current) return;
    setState(() => _writing = true);
    try {
      await chooseAndUploadNeteaseCloud(
        context,
        ref,
        isCurrent: () => mounted && _current,
      );
      if (mounted && _current) await _load(reset: true);
    } catch (e) {
      if (mounted) showPlatformFailure(context, e);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    return PlatformPageFrame(
      title: widget.title ?? NeteaseFeaturesRepository.titles[widget.feed]!,
      child: !_current
          ? const EditorialEmpty('账号已变化，请返回后重新打开')
          : MusicRefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: AutomaticSongPaging(
                enabled: _more && !_busy && _error == null,
                onLoadMore: _load,
                child: ListView.builder(
                  padding: BetaContentInsets.musicPaddingOf(
                    context,
                    EdgeInsets.only(
                      bottom: BetaContentInsets.musicBottomOf(
                        context,
                        editorialBottomClearance,
                      ),
                    ),
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _items.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.feed == NeteaseFeed.podcasts)
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final feed in [
                                    NeteaseFeed.podcastCategories,
                                    NeteaseFeed.podcastToday,
                                    NeteaseFeed.podcastPersonal,
                                    NeteaseFeed.podcastTop,
                                    NeteaseFeed.recommendedPrograms,
                                    NeteaseFeed.subscribedPodcasts,
                                    NeteaseFeed.recentPodcasts,
                                  ])
                                    TextButton(
                                      onPressed: () =>
                                          openNeteaseFeed(context, feed),
                                      child: Text(
                                        NeteaseFeaturesRepository.titles[feed]!,
                                      ),
                                    ),
                                ],
                              ),
                            if (widget.feed == NeteaseFeed.podcastPrograms)
                              NeteaseResourceActions(
                                item: NeteaseItem(
                                  id: widget.id,
                                  name: widget.title ?? '播客',
                                  kind: NeteaseEntity.podcast,
                                ),
                              ),
                            if (_items.any((i) => i.track != null))
                              TextButton.icon(
                                icon: const Icon(
                                  CupertinoIcons.arrow_down_circle,
                                ),
                                label: const Text('下载已加载歌曲'),
                                onPressed: () {
                                  if (!_current) return;
                                  enqueueAudioDownloads(
                                    context,
                                    ref,
                                    _items
                                        .map((i) => i.track)
                                        .whereType<Track>()
                                        .toList(),
                                  );
                                },
                              ),
                            if (widget.feed == NeteaseFeed.cloud)
                              BetaGlassButton(
                                onPressed: _writing ? null : _upload,
                                child: Text(_writing ? '正在处理…' : '上传音乐到网易云云盘'),
                              ),
                            if ({
                              NeteaseFeed.albums,
                              NeteaseFeed.artists,
                              NeteaseFeed.mvs,
                            }.contains(widget.feed))
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final area
                                      in widget.feed == NeteaseFeed.artists
                                          ? ['华语', '欧美', '韩国', '日本']
                                          : widget.feed == NeteaseFeed.mvs
                                          ? ['全部', '内地', '港台', '欧美', '日本', '韩国']
                                          : ['全部', '华语', '欧美', '日本', '韩国'])
                                    ChoiceChip(
                                      label: Text(area),
                                      selected:
                                          widget.feed == NeteaseFeed.artists
                                          ? _artistArea ==
                                                [
                                                      '华语',
                                                      '欧美',
                                                      '韩国',
                                                      '日本',
                                                    ].indexOf(area) +
                                                    1
                                          : _area ==
                                                (widget.feed ==
                                                        NeteaseFeed.albums
                                                    ? {
                                                        '全部': 'ALL',
                                                        '华语': 'ZH',
                                                        '欧美': 'EA',
                                                        '日本': 'JP',
                                                        '韩国': 'KR',
                                                      }[area]
                                                    : area),
                                      onSelected: _busy
                                          ? null
                                          : (_) {
                                              if (widget.feed ==
                                                  NeteaseFeed.artists) {
                                                _artistArea =
                                                    [
                                                      '华语',
                                                      '欧美',
                                                      '韩国',
                                                      '日本',
                                                    ].indexOf(area) +
                                                    1;
                                              } else {
                                                _area =
                                                    widget.feed ==
                                                        NeteaseFeed.albums
                                                    ? {
                                                        '全部': 'ALL',
                                                        '华语': 'ZH',
                                                        '欧美': 'EA',
                                                        '日本': 'JP',
                                                        '韩国': 'KR',
                                                      }[area]!
                                                    : area;
                                              }
                                              _load(reset: true);
                                            },
                                    ),
                                ],
                              ),
                            if (_writing)
                              const Center(
                                child: MusicActivityIndicator(
                                  independent: true,
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    if (index == _items.length + 1) {
                      if (_busy) {
                        return const PlatformFeedbackState(loading: true);
                      }
                      if (_error != null) {
                        return EditorialEmpty(
                          _error!,
                          onRetry: () => _load(reset: _items.isEmpty),
                        );
                      }
                      return _items.isEmpty
                          ? EditorialEmpty(
                              '暂无${widget.title ?? NeteaseFeaturesRepository.titles[widget.feed] ?? '内容'}',
                            )
                          : const SizedBox(height: 24);
                    }
                    final item = _items[index - 1];
                    if (item.track != null) {
                      return Column(
                        children: [
                          EditorialTrackRow(
                            track: item.track!,
                            contextTracks: _items
                                .map((i) => i.track)
                                .whereType<Track>()
                                .toList(),
                          ),
                          if (widget.feed == NeteaseFeed.cloud)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _writing
                                    ? null
                                    : () => _deleteCloud(item),
                                child: const Text('从云盘删除'),
                              ),
                            ),
                          if (item.kind == NeteaseEntity.program)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  final account = ref
                                      .read(platformAccountProvider)
                                      .value;
                                  if (account == null || !_current) return;
                                  Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PlatformCommentsPage(
                                        resource: PlatformCommentResource(
                                          kind: PlatformCommentKind.podcast,
                                          id: item.id,
                                          name: item.name,
                                        ),
                                        repository: NeteaseCommentsRepository(
                                          ref.read(musicPlatformApiProvider),
                                          account,
                                          ref.read(
                                            neteaseMusicRepositoryProvider,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('节目评论'),
                              ),
                            ),
                        ],
                      );
                    }
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 8,
                      ),
                      leading: item.cover.isEmpty
                          ? const Icon(CupertinoIcons.music_note_list)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(
                                item.kind == NeteaseEntity.artist ? 32 : 12,
                              ),
                              child: ArtworkImage(
                                uri: item.cover,
                                width: 60,
                                height: 60,
                              ),
                            ),
                      title: Text(item.name),
                      subtitle: item.subtitle.isEmpty
                          ? null
                          : Text(
                              item.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: const Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                      ),
                      onTap: () => openNeteaseItem(context, item),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

/// Real collection state is read before enabling mutations. No optimistic
/// bookmark can claim success if the upstream rejected or timed out the write.
class NeteaseResourceActions extends ConsumerStatefulWidget {
  const NeteaseResourceActions({required this.item, super.key});
  final NeteaseItem item;
  @override
  ConsumerState<NeteaseResourceActions> createState() =>
      _NeteaseResourceActionsState();
}

class NeteaseLibraryLinks extends StatelessWidget {
  const NeteaseLibraryLinks({this.section, super.key});
  final NeteaseLibrarySection? section;
  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        for (final feed
            in section == null
                ? [
                    NeteaseFeed.likedAlbums,
                    NeteaseFeed.likedArtists,
                    NeteaseFeed.likedMvs,
                    NeteaseFeed.cloud,
                    NeteaseFeed.recentSongs,
                    NeteaseFeed.recentPlaylists,
                    NeteaseFeed.recentAlbums,
                    NeteaseFeed.week,
                    NeteaseFeed.allTime,
                    NeteaseFeed.subscribedPodcasts,
                  ]
                : neteaseLibrarySectionFeeds[section]!)
          ListTile(
            contentPadding: section == null
                ? null
                : const EdgeInsets.symmetric(horizontal: 24),
            minLeadingWidth: section == null ? null : 26,
            horizontalTitleGap: section == null ? null : 18,
            title: Text(
              NeteaseFeaturesRepository.titles[feed]!,
              style: section == null
                  ? null
                  : const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            leading: Icon(
              feed == NeteaseFeed.cloud
                  ? CupertinoIcons.cloud
                  : feed == NeteaseFeed.likedMvs
                  ? CupertinoIcons.play_rectangle
                  : CupertinoIcons.music_note_list,
              color: section == null
                  ? null
                  : Theme.of(context).colorScheme.primary,
            ),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () => openNeteaseFeed(context, feed),
          ),
        if (section == null || section == NeteaseLibrarySection.playlists)
          ListTile(
            contentPadding: section == null
                ? null
                : const EdgeInsets.symmetric(horizontal: 24),
            minLeadingWidth: section == null ? null : 26,
            horizontalTitleGap: section == null ? null : 18,
            title: Text(
              '导入歌单',
              style: section == null
                  ? null
                  : const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            leading: Icon(
              CupertinoIcons.doc_text,
              color: section == null
                  ? null
                  : Theme.of(context).colorScheme.primary,
            ),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NeteasePlaylistImportPage(),
              ),
            ),
          ),
        NeteaseFullNavigation(
          tab: '音乐库',
          categories: section == null || section == NeteaseLibrarySection.other
              ? null
              : {
                  for (final entry in neteaseLibraryCategorySections.entries)
                    if (entry.value == section) entry.key,
                },
          excludedCategories: section == NeteaseLibrarySection.other
              ? neteaseLibraryCategorySections.keys.toSet()
              : const {},
          showHeading:
              section == null || section == NeteaseLibrarySection.other,
          heading: section == NeteaseLibrarySection.other ? '更多音乐库功能' : '网易云专区',
          grouped: section == null,
          categoryLabels: section == null
              ? const {}
              : const {
                  '历史与听歌报告': '记录与报告管理',
                  '歌单与收藏': '歌单与收藏管理',
                  '资料与收藏概览': '收藏概览',
                },
        ),
      ],
    );
    return section != null
        ? content
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: PlatformPanel(padding: EdgeInsets.zero, child: content),
          );
  }
}

class NeteaseAccountPanel extends ConsumerStatefulWidget {
  const NeteaseAccountPanel({super.key});
  @override
  ConsumerState<NeteaseAccountPanel> createState() =>
      _NeteaseAccountPanelState();
}

class _NeteaseAccountPanelState extends ConsumerState<NeteaseAccountPanel> {
  bool _busy = false;
  String? _result;
  @override
  Widget build(BuildContext context) => PlatformPanel(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BetaGlassButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const NeteaseMembershipPage(),
            ),
          ),
          child: const Text('我的会员 · 本地 SVIP'),
        ),
        const SizedBox(height: 12),
        BetaGlassButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final message = await ref
                        .read(neteaseFeaturesProvider)
                        .signIn();
                    if (mounted) setState(() => _result = message);
                  } catch (e) {
                    if (context.mounted) showPlatformFailure(context, e);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(_busy ? '正在签到…' : '网易云每日签到'),
        ),
        if (_result != null)
          Padding(padding: const EdgeInsets.all(10), child: Text(_result!)),
        TextButton(
          onPressed: () => openNeteaseFeed(context, NeteaseFeed.week),
          child: const Text('网易云听歌排行'),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final feed in [NeteaseFeed.follows, NeteaseFeed.followers])
              TextButton(
                onPressed: () => openNeteaseFeed(context, feed),
                child: Text(NeteaseFeaturesRepository.titles[feed]!),
              ),
          ],
        ),
        const NeteaseFullNavigation(tab: '我的'),
      ],
    ),
  );
}

class _NeteaseResourceActionsState
    extends ConsumerState<NeteaseResourceActions> {
  bool? _subscribed;
  bool _busy = false;
  String? _error;
  late final String? _owner, _token;
  bool get _current =>
      ref.read(usesNeteaseProvider) &&
      ref.read(platformAccountProvider).value?.ownerId == _owner &&
      ref.read(platformAccountProvider).value?.token == _token;
  @override
  void initState() {
    super.initState();
    final a = ref.read(platformAccountProvider).value;
    _owner = a?.ownerId;
    _token = a?.token;
    Future.microtask(_read);
  }

  Future<void> _read() async {
    if (!_current) return;
    try {
      final value = await ref
          .read(neteaseFeaturesProvider)
          .subscribed(widget.item);
      if (mounted && _current) {
        setState(() {
          _subscribed = value;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && _current) setState(() => _error = '收藏状态读取失败，点击重试');
    }
  }

  Future<void> _toggle() async {
    if (_busy || !_current) return;
    if (_subscribed == null) {
      await _read();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(neteaseFeaturesProvider)
          .subscribe(widget.item, !_subscribed!);
      if (mounted && _current) setState(() => _subscribed = !_subscribed!);
    } catch (e) {
      if (mounted) showPlatformFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    if (!_current) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BetaGlassButton(
            onPressed: _busy ? null : _toggle,
            child: Text(
              _busy
                  ? '正在保存…'
                  : _error ??
                        (_subscribed == null
                            ? '正在读取收藏状态…'
                            : _subscribed!
                            ? (widget.item.kind == NeteaseEntity.artist
                                  ? '取消关注'
                                  : '取消收藏')
                            : widget.item.kind == NeteaseEntity.artist
                            ? '关注歌手'
                            : '收藏'),
            ),
          ),
          const SizedBox(height: 12),
          BetaGlassButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NeteaseFullHubPage(
                  entityKind: widget.item.kind.name,
                  seed: {
                    'id': widget.item.id,
                    'pid': widget.item.id,
                    'ids': widget.item.id,
                  },
                ),
              ),
            ),
            child: const Text('更多相关功能'),
          ),
          if (widget.item.kind == NeteaseEntity.artist)
            for (final feed in [
              NeteaseFeed.artistSongs,
              NeteaseFeed.artistAlbums,
              NeteaseFeed.artistMvs,
              NeteaseFeed.similarArtists,
            ])
              TextButton(
                onPressed: () =>
                    openNeteaseFeed(context, feed, id: widget.item.id),
                child: Text(NeteaseFeaturesRepository.titles[feed]!),
              ),
          if (widget.item.kind == NeteaseEntity.mv)
            TextButton(
              onPressed: () => openNeteaseFeed(
                context,
                NeteaseFeed.similarMvs,
                id: widget.item.id,
              ),
              child: const Text('相似 MV'),
            ),
          if (widget.item.kind == NeteaseEntity.mv ||
              widget.item.kind == NeteaseEntity.album ||
              widget.item.kind == NeteaseEntity.playlist)
            TextButton(
              onPressed: () {
                final account = ref.read(platformAccountProvider).value;
                if (account == null || !_current) return;
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlatformCommentsPage(
                      resource: PlatformCommentResource(
                        kind: widget.item.kind == NeteaseEntity.mv
                            ? PlatformCommentKind.mv
                            : widget.item.kind == NeteaseEntity.album
                            ? PlatformCommentKind.album
                            : PlatformCommentKind.playlist,
                        id: widget.item.id,
                        name: widget.item.name,
                      ),
                      repository: NeteaseCommentsRepository(
                        ref.read(musicPlatformApiProvider),
                        account,
                        ref.read(neteaseMusicRepositoryProvider),
                      ),
                    ),
                  ),
                );
              },
              child: Text(
                widget.item.kind == NeteaseEntity.mv
                    ? 'MV 评论'
                    : widget.item.kind == NeteaseEntity.album
                    ? '专辑评论'
                    : '歌单评论',
              ),
            ),
        ],
      ),
    );
  }
}
