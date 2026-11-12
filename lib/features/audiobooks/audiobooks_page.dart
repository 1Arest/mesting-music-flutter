import '../../shared/widgets/beta_content_insets.dart';
import '../../shared/widgets/beta_page_motion.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_providers.dart';
import '../../shared/widgets/beta_bottom_search.dart';
import '../../shared/widgets/beta_page_search_layout.dart';
import '../../shared/widgets/artwork_image.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/presentation/platform_design.dart';
import '../music_platform/presentation/platform_feedback.dart';
import '../player/presentation/beta_playback_actions.dart';
import 'audiobook_models.dart';
import 'audiobook_playback.dart';
import 'audiobook_repository.dart';
import 'audiobook_resume.dart';
import '../themes/music_typography.dart';

class AudiobooksPage extends ConsumerStatefulWidget {
  const AudiobooksPage({super.key});
  @override
  ConsumerState<AudiobooksPage> createState() => _AudiobooksPageState();
}

class _AudiobooksPageState extends ConsumerState<AudiobooksPage> {
  late final _bottomSearch = BetaPageSearchController(
    hintText: '搜索书名、作者',
    onSubmitted: (_) => _submit(),
    onCleared: _clearSearch,
  );
  TextEditingController get _search => _bottomSearch.text;
  final _scroll = ScrollController();
  AudiobookRepository? _repository;
  Completer<void>? _abort;
  int _generation = 0, _page = 0;
  bool _loading = true,
      _loadingMore = false,
      _hasMore = false,
      _resuming = false;
  String _category = '906', _query = '';
  String? _error, _categoryError;
  List<BookAlbum> _albums = const [];
  List<BookCategory> _categories = const [];
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400 &&
          _hasMore &&
          !_loading &&
          !_loadingMore &&
          _error == null) {
        unawaited(_load(reset: false));
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    if (_abort?.isCompleted == false) {
      _abort!.complete();
    }
    _bottomSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_abort?.isCompleted == false) _abort!.complete();
    _abort = Completer<void>();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_load(), _loadCategories()]);
  }

  Future<void> _loadCategories() async {
    final repo = _repository, generation = _generation;
    if (repo == null) return;
    try {
      final result = await repo.categories();
      if (mounted && repo == _repository && generation == _generation) {
        setState(() {
          _categories = result;
          _categoryError = null;
        });
      }
    } catch (_) {
      if (mounted && repo == _repository && generation == _generation) {
        setState(() => _categoryError = '分类暂未加载');
      }
    }
  }

  Future<void> _load({bool reset = true}) async {
    final repo = _repository;
    if (repo == null || !reset && (_loading || _loadingMore || !_hasMore)) {
      return;
    }
    if (reset) {
      _generation++;
      _cancel();
    }
    final generation = _generation, requestedPage = reset ? 1 : _page + 1;
    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      final result = _query.isEmpty
          ? await repo.albums(
              category: _category,
              page: requestedPage,
              abortTrigger: _abort?.future,
            )
          : await repo.search(
              _query,
              page: requestedPage,
              abortTrigger: _abort?.future,
            );
      if (!mounted || generation != _generation) return;
      final ids = <String>{};
      setState(() {
        _albums = [
          if (!reset) ..._albums,
          ...result.items,
        ].where((a) => ids.add(a.id)).toList();
        _page = requestedPage;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _bookError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(audiobookRepositoryProvider);
    // The root binding persists chapter progress outside this page as well.
    ref.watch(audiobookProgressBindingProvider);
    final store = ref.watch(audiobookResumeStoreProvider);
    if (_repository != repository) {
      _generation++;
      _cancel();
      _repository = repository;
      _albums = const [];
      _categories = const [];
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _repository == repository) unawaited(_refreshAll());
      });
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 700
        ? 4
        : width < 350 || MediaQuery.textScalerOf(context).scale(14) > 21
        ? 2
        : 3;
    return BetaPageSearchLayout(
      controller: _bottomSearch,
      child: PlatformPageFrame(
        title: '听书',
        subtitle: '把故事听进日常',
        actions: [
          BetaGlassButton(
            label: '刷新听书',
            width: 48,
            height: 48,
            onPressed: _loading ? null : _refreshAll,
            child: const Icon(CupertinoIcons.arrow_clockwise, size: 21),
          ),
        ],
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListenableBuilder(
                      listenable: store,
                      builder: (context, _) {
                        final entries = store.entries.take(3).toList();
                        if (entries.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),
                            const PlatformSectionTitle('接着听'),
                            for (final entry in entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: PlatformPanel(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      _BookCover(album: entry.album, size: 58),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.album.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight:
                                                    MusicTypography.titleWeight,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              entry.track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                            Text(
                                              '已听 ${_bookTime(entry.position)}',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      BetaGlassButton(
                                        label: '继续收听${entry.album.name}',
                                        width: 46,
                                        height: 46,
                                        loading: _resuming,
                                        onPressed: _resuming
                                            ? null
                                            : () => _resume(entry),
                                        child: const Icon(
                                          CupertinoIcons.play_fill,
                                          size: 19,
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
                    const SizedBox(height: 24),
                    PlatformSectionTitle(
                      _query.isEmpty ? '挑一本，慢慢听' : '“$_query”的搜索结果',
                      subtitle: _query.isEmpty ? '酷狗免费书库' : null,
                    ),
                    if (_categories.isNotEmpty)
                      SizedBox(
                        height: 46,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            return ChoiceChip(
                              label: Text(category.name),
                              selected:
                                  _query.isEmpty && _category == category.id,
                              onSelected: (_) {
                                FocusScope.of(context).unfocus();
                                _search.clear();
                                _query = '';
                                _bottomSearch.hasResults = false;
                                _category = category.id;
                                unawaited(_load());
                              },
                            );
                          },
                        ),
                      ),
                    if (_categoryError != null)
                      TextButton(
                        onPressed: _loadCategories,
                        child: const Text('重新加载分类'),
                      ),
                    if (_query.isNotEmpty)
                      TextButton(
                        onPressed: _bottomSearch.clearResults,
                        child: const Text('返回书库'),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(35),
                        child: Center(child: BetaActivityIndicator()),
                      ),
                    if (!_loading && _albums.isEmpty && _error == null)
                      const _BookMessage('暂未找到相关听书内容，换一个关键词或分类试试。'),
                  ],
                ),
              ),
            ),
            if (!_loading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 22,
                    mainAxisExtent:
                        (width - 44 - 14 * (columns - 1)) / columns +
                        82 *
                            (MediaQuery.textScalerOf(context).scale(14) / 14)
                                .clamp(1.0, 1.8),
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final album = _albums[index];
                    return Semantics(
                      button: true,
                      label: '打开${album.name}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openAlbum(album),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: _BookCover(album: album),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              album.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: MusicTypography.titleWeight,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              album.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: _albums.length),
                ),
              ),
            SliverPadding(
              padding: BetaContentInsets.musicPaddingOf(
                context,
                EdgeInsets.fromLTRB(22, 22, 22, 160),
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (_error != null)
                      _BookMessage(
                        _error!,
                        retry: () => _load(reset: _albums.isEmpty),
                      ),
                    if (_loadingMore) const BetaActivityIndicator(),
                    if (!_loading &&
                        !_loadingMore &&
                        _hasMore &&
                        _error == null)
                      TextButton(
                        onPressed: () => _load(reset: false),
                        child: const Text('加载更多'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    _query = _search.text.trim();
    _bottomSearch.hasResults = _query.isNotEmpty;
    unawaited(_load());
  }

  void _clearSearch() {
    _query = '';
    unawaited(_load());
  }

  void _openAlbum(BookAlbum album) => Navigator.of(
    context,
  ).push(mestingCupertinoRoute<void>(AudiobookAlbumPage(album: album)));
  Future<void> _resume(BookResume entry) async {
    setState(() => _resuming = true);
    try {
      await resumeAudiobook(context, ref, entry);
    } catch (error) {
      if (mounted) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }
}

class AudiobookAlbumPage extends ConsumerStatefulWidget {
  const AudiobookAlbumPage({required this.album, super.key});
  final BookAlbum album;
  @override
  ConsumerState<AudiobookAlbumPage> createState() => _AudiobookAlbumPageState();
}

class _AudiobookAlbumPageState extends ConsumerState<AudiobookAlbumPage> {
  final _scroll = ScrollController();
  Completer<void> _abort = Completer<void>();
  AudiobookRepository? _repository;
  late BookAlbum _album = widget.album;
  List<BookChapter> _chapters = const [];
  final Map<String, int> _chapterPages = {};
  bool _loading = true,
      _loadingMore = false,
      _hasMore = false,
      _playing = false,
      _expanded = false;
  int _page = 0, _generation = 0;
  String? _error, _detailError;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 350 &&
          _hasMore &&
          !_loading &&
          !_loadingMore &&
          _error == null) {
        unawaited(_load(reset: false));
      }
    });
  }

  @override
  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
    _generation++;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = true}) async {
    final repo = _repository;
    if (repo == null || !reset && (_loading || _loadingMore || !_hasMore)) {
      return;
    }
    if (reset) {
      _generation++;
      if (!_abort.isCompleted) _abort.complete();
      _abort = Completer<void>();
    }
    final generation = _generation, page = reset ? 1 : _page + 1;
    setState(() {
      _error = null;
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    if (reset) {
      unawaited(() async {
        try {
          final detail = await repo.detail(
            widget.album,
            abortTrigger: _abort.future,
          );
          if (mounted && generation == _generation) {
            setState(() {
              _album = detail;
              _detailError = null;
            });
          }
        } catch (_) {
          if (mounted && generation == _generation) {
            setState(() => _detailError = '简介暂未加载');
          }
        }
      }());
    }
    try {
      final result = await repo.chapters(
        _album,
        page: page,
        abortTrigger: _abort.future,
      );
      if (!mounted || generation != _generation) return;
      final ids = <String>{};
      setState(() {
        if (reset) _chapterPages.clear();
        for (final chapter in result.items) {
          _chapterPages[chapter.track.id] = page;
        }
        _chapters = [
          if (!reset) ..._chapters,
          ...result.items,
        ].where((c) => ids.add(c.track.id)).toList();
        _hasMore = result.hasMore;
        _page = page;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _bookError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(audiobookRepositoryProvider);
    ref.watch(audiobookProgressBindingProvider);
    final store = ref.watch(audiobookResumeStoreProvider);
    if (_repository != repository) {
      _generation++;
      if (!_abort.isCompleted) {
        _abort.complete();
      }
      _abort = Completer<void>();
      _chapters = const [];
      _chapterPages.clear();
      _loading = true;
      _repository = repository;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && repository == _repository) unawaited(_load());
      });
    }
    final playingId = ref.watch(
      currentMediaItemProvider.select((s) => s.value?.id),
    );
    return PlatformPageFrame(
      title: '听书专辑',
      actions: [
        BetaGlassButton(
          label: '刷新章节',
          width: 48,
          height: 48,
          onPressed: _loading ? null : _load,
          child: const Icon(CupertinoIcons.arrow_clockwise, size: 21),
        ),
      ],
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BookCover(
                        album: _album,
                        size: MediaQuery.sizeOf(context).width < 350 ? 90 : 112,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _album.name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: MusicTypography.titleWeight,
                                    height: 1.3,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(_album.author),
                            if (_album.chapterCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${_album.chapterCount} 个章节',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_album.intro.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text(
                      _album.intro,
                      maxLines: _expanded ? null : 4,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.7),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? '收起简介' : '展开简介'),
                    ),
                  ],
                  if (_detailError != null)
                    TextButton(onPressed: _load, child: const Text('重新加载简介')),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      BetaGlassButton(
                        blue: true,
                        loading: _playing,
                        onPressed:
                            _playing || _chapters.every((c) => !c.canPlay)
                            ? null
                            : () => _play(0),
                        child: const Text('从头播放'),
                      ),
                      ListenableBuilder(
                        listenable: store,
                        builder: (context, _) {
                          final resume = store.forAlbum(_album.id);
                          if (resume == null) return const SizedBox.shrink();
                          return BetaGlassButton(
                            onPressed: _playing ? null : () => _resume(resume),
                            child: const Text('继续收听'),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const PlatformSectionTitle('章节'),
                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: BetaActivityIndicator(),
                      ),
                    ),
                  if (!_loading && _chapters.isEmpty && _error == null)
                    const _BookMessage('平台暂未返回章节，请稍后重试。'),
                ],
              ),
            ),
          ),
          if (!_loading)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index],
                      selected = chapter.track.id == playingId;
                  return ListTile(
                    key: ValueKey(chapter.track.id),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 7,
                    ),
                    leading: SizedBox(
                      width: 32,
                      child: Center(
                        child: selected
                            ? Icon(
                                CupertinoIcons.speaker_2_fill,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : Text(
                                '${index + 1}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                      ),
                    ),
                    title: Text(
                      chapter.track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: MusicTypography.titleWeight,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      chapter.canPlay
                          ? _bookTime(chapter.duration)
                          : '需要相应购买或会员权限',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: chapter.canPlay
                        ? const Icon(CupertinoIcons.play_circle, size: 26)
                        : const Icon(CupertinoIcons.lock, size: 19),
                    onTap: !chapter.canPlay || _playing
                        ? null
                        : () => _play(index),
                  );
                },
              ),
            ),
          SliverPadding(
            padding: BetaContentInsets.musicPaddingOf(
              context,
              EdgeInsets.fromLTRB(22, 20, 22, 160),
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (_error != null)
                    _BookMessage(
                      _error!,
                      retry: () => _load(reset: _chapters.isEmpty),
                    ),
                  if (_loadingMore) const BetaActivityIndicator(),
                  if (!_loading && !_loadingMore && _hasMore && _error == null)
                    TextButton(
                      onPressed: () => _load(reset: false),
                      child: const Text('加载后续章节'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _play(int index) async {
    final chosen = _chapters.skip(index).where((c) => c.canPlay).toList();
    if (chosen.isEmpty) return;
    setState(() => _playing = true);
    try {
      final played = await playBetaSelection(
        context,
        ref,
        chosen.first.track,
        playAll: chosen.map((c) => c.track).toList(),
      );
      if (played && mounted) {
        ref
            .read(audiobookProgressBindingProvider)
            .begin(
              _album,
              _chapters,
              firstPage: 1,
              nextPage: _page + 1,
              hasMore: _hasMore,
              chapterPages: _chapterPages,
            );
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _resume(BookResume entry) async {
    setState(() => _playing = true);
    try {
      await resumeAudiobook(context, ref, entry);
    } catch (error) {
      if (mounted) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }
}

Future<void> resumeAudiobook(
  BuildContext context,
  WidgetRef ref,
  BookResume resume,
) async {
  final repository = ref.read(audiobookRepositoryProvider);
  var page = await repository.chapters(resume.album, page: resume.chapterPage);
  if (!context.mounted) return;
  var index = page.items.indexWhere((c) => c.track.id == resume.track.id);
  if (index < 0) throw const MusicPlatformException('原章节已变更，请从专辑重新选择章节');
  var position = resume.position;
  if (resume.track.duration > Duration.zero &&
      position >= resume.track.duration - const Duration(seconds: 2)) {
    index++;
    position = Duration.zero;
    if (index >= page.items.length && page.hasMore) {
      page = await repository.chapters(resume.album, page: page.page + 1);
      index = 0;
    }
  }
  final chosen = page.items.skip(index).where((c) => c.canPlay).toList();
  if (chosen.isEmpty) throw const MusicPlatformException('这本书已听完，或后续章节暂不可播放');
  if (!context.mounted) return;
  final played = await playBetaSelection(
    context,
    ref,
    chosen.first.track,
    playAll: chosen.map((c) => c.track).toList(),
  );
  if (!played || !context.mounted) return;
  if (position > Duration.zero) {
    await ref.read(audioHandlerProvider).seek(position);
  }
  ref
      .read(audiobookProgressBindingProvider)
      .begin(
        resume.album,
        page.items,
        firstPage: page.page,
        nextPage: page.page + 1,
        hasMore: page.hasMore,
      );
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.album, this.size});
  final BookAlbum album;
  final double? size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: album.cover.isEmpty
        ? Container(
            width: size,
            height: size,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            alignment: Alignment.center,
            child: Icon(
              CupertinoIcons.book_fill,
              color: Theme.of(context).colorScheme.primary,
              size: size == null ? 38 : size! * .38,
            ),
          )
        : ArtworkImage(
            uri: album.cover,
            width: size,
            height: size,
            decodeWidth: 360,
            persistentNetworkCacheKey: 'kugou-book-${album.id}',
            retryOnNetworkError: true,
          ),
  );
}

class _BookMessage extends StatelessWidget {
  const _BookMessage(this.message, {this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => PlatformPanel(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        if (retry != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: retry, child: const Text('重试')),
        ],
      ],
    ),
  );
}

String _bookError(Object error) =>
    error is MusicPlatformException ? error.message : '听书内容暂未加载，请重试';
String _bookTime(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 864000);
  return seconds >= 3600
      ? '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
      : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
