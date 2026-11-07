import '../../music_platform/presentation/platform_collection_play.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/music_list_footer.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../music_platform/data/platform_explore.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/platform_explore_providers.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../music_platform/presentation/retained_platform_snapshot.dart';
import '../../music_platform/presentation/platform_search_landing.dart'
    show PlatformExploreSongsPage;
import '../../themes/music_theme_tokens.dart';
import 'editorial_widgets.dart';

/// Home deliberately consumes music catalogues, not the mixed advertising,
/// livestream or long-audio feed. Selection and tracks always come from Kugou.
bool isMusicHomeCatalogueItem(PlatformExploreItem item) => !RegExp(
  r'^(听书|有声书|小说|直播|直播间|短剧|相声评书|播客)(专区|频道|推荐)?$',
).hasMatch(item.title.trim());

const musicHomeCatalogueOrder = [
  PlatformExploreKind.rank,
  PlatformExploreKind.album,
  PlatformExploreKind.theme,
  PlatformExploreKind.scene,
];

String musicHomeCatalogueTitle(PlatformExploreKind kind) => switch (kind) {
  PlatformExploreKind.rank => '热门榜单',
  PlatformExploreKind.album => '新碟上架',
  PlatformExploreKind.theme => '主题歌单',
  PlatformExploreKind.scene => '场景音乐',
  PlatformExploreKind.playlist => '精选歌单',
};

void openMusicHomeCatalogue(BuildContext context, PlatformExploreKind kind) =>
    Navigator.of(context).push(
      MestingPageRoute<void>(
        builder: (_) => MusicHomeCataloguePage(kind: kind),
      ),
    );

void _openCollection(BuildContext context, PlatformExploreItem item) =>
    Navigator.of(context).push(
      MestingPageRoute<void>(
        builder: (_) => PlatformExploreSongsPage(item: item),
      ),
    );

/// Each lazy shelf owns its subscription/error state. A failed album request
/// cannot replace working recommendations or eagerly load the whole catalogue.
class MusicHomeCatalogueShelf extends ConsumerWidget {
  const MusicHomeCatalogueShelf(this.kind, {super.key});
  final PlatformExploreKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(platformExploreProvider(kind));
    final title = musicHomeCatalogueTitle(kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorialSection(
          title,
          onTap: () => openMusicHomeCatalogue(context, kind),
        ),
        RetainedPlatformSnapshot(
          value: value,
          artwork: (items) => items.map((item) => item.cover),
          loading: () => const PlatformFeedbackState(loading: true),
          error: (_, _) => EditorialEmpty(
            '$title暂时无法加载',
            onRetry: () => ref.invalidate(platformExploreProvider(kind)),
          ),
          data: (all) {
            final items = all.where(isMusicHomeCatalogueItem).take(12).toList();
            if (items.isEmpty) {
              return EditorialEmpty(
                '暂无$title',
                onRetry: () => ref.invalidate(platformExploreProvider(kind)),
              );
            }
            if (kind == PlatformExploreKind.scene) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in items)
                      CupertinoButton(
                        key: ValueKey('home-scene-${item.id}'),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        onPressed: () => _openCollection(context, item),
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.musicThemeTokens.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }
            return EditorialShelf(
              height: 248,
              children: [
                for (final item in items)
                  EditorialCover(
                    key: ValueKey('home-${kind.name}-${item.id}'),
                    cover: item.cover,
                    title: item.title,
                    subtitle: item.subtitle,
                    width: 170,
                    coverAction:
                        {
                          PlatformExploreKind.rank,
                          PlatformExploreKind.playlist,
                        }.contains(item.kind)
                        ? PlatformCollectionPlayButton(item: item)
                        : null,
                    onTap: () => _openCollection(context, item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Full catalogue retains account identity across pagination, and opens the
/// same real detail route as the preview. No placeholder "more" action.
class MusicHomeCataloguePage extends ConsumerStatefulWidget {
  const MusicHomeCataloguePage({required this.kind, super.key});
  final PlatformExploreKind kind;
  @override
  ConsumerState<MusicHomeCataloguePage> createState() =>
      _MusicHomeCataloguePageState();
}

class _MusicHomeCataloguePageState
    extends ConsumerState<MusicHomeCataloguePage> {
  final _items = <PlatformExploreItem>[];
  int _page = 0;
  bool _busy = false, _more = true;
  String? _error;
  String? _owner, _token;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (_busy || !_more) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await ref.read(platformAccountProvider.future);
      final owner = account?.ownerId, token = account?.token;
      if (!mounted) return;
      final batch = _page == 0
          ? await ref.read(platformExploreProvider(widget.kind).future)
          : await ref
                .read(platformExploreRepositoryProvider)
                .list(widget.kind, page: _page + 1);
      if (!mounted) return;
      final current = ref.read(platformAccountProvider).value;
      if (owner != current?.ownerId || token != current?.token) {
        setState(() => _error = '账号已变化，请返回后重新打开');
        return;
      }
      setState(() {
        final ids = _items.map((item) => item.id).toSet();
        final fresh = batch
            .where(isMusicHomeCatalogueItem)
            .where((item) => ids.add(item.id))
            .toList();
        _items.addAll(fresh);
        _page++;
        _more =
            (widget.kind == PlatformExploreKind.playlist ||
                widget.kind == PlatformExploreKind.album) &&
            fresh.isNotEmpty &&
            batch.length >= 20;
        _owner = owner;
        _token = token;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '内容暂时无法加载，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    return PlatformPageFrame(
      title: musicHomeCatalogueTitle(widget.kind),
      child: _loaded && (_owner != account?.ownerId || _token != account?.token)
          ? const EditorialEmpty('账号已变化，请返回后重新打开')
          : AutomaticSongPaging(
              enabled: _more && !_busy && _error == null,
              onLoadMore: _load,
              child: ListView.builder(
                cacheExtent: MediaQuery.sizeOf(context).height,
                padding: BetaContentInsets.musicPaddingOf(
                  context,
                  EdgeInsets.only(
                    bottom: BetaContentInsets.musicBottomOf(
                      context,
                      editorialBottomClearance,
                    ),
                  ),
                ),
                itemCount: _items.length + 1,
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    if (_busy) {
                      return const PlatformFeedbackState(loading: true);
                    }
                    if (_error != null) {
                      return EditorialEmpty(_error!, onRetry: _load);
                    }
                    return _items.isEmpty
                        ? const EditorialEmpty('平台暂未返回音乐内容')
                        : _more
                        ? const SizedBox(height: 12)
                        : const MusicListEnd();
                  }
                  final item = _items[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 10,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ArtworkImage(
                        uri: item.cover,
                        width: 64,
                        height: 64,
                      ),
                    ),
                    title: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: item.subtitle.isEmpty
                        ? null
                        : Text(
                            item.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                    ),
                    onTap: () => _openCollection(context, item),
                  );
                },
              ),
            ),
    );
  }
}
