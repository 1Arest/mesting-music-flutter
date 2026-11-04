import 'platform_backend_providers.dart';
import 'netease/netease_catalog_adapters.dart';
import 'dart:async';
import '../../core/cache/cached_browse_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../search/search_providers.dart';
import 'music_platform_providers.dart';
import 'data/platform_category_search.dart';
import 'data/music_platform_api.dart';

final platformCategorySearchRepositoryProvider = Provider((ref) {
  final api = ref.watch(musicPlatformApiProvider);
  return ref.watch(usesNeteaseProvider)
      ? NeteaseCategoryAdapter(api, ref.watch(neteaseMusicRepositoryProvider))
      : PlatformCategorySearchRepository(api);
});

class CategorySearchSlice {
  const CategorySearchSlice({
    this.items = const [],
    this.page = 0,
    this.total,
    this.more = true,
    this.loading = false,
    this.error,
    this.stale = false,
  });
  final List<PlatformSearchHit> items;
  final int page;
  final int? total;
  final bool more, loading, stale;
  final String? error;
}

class CategorySearchState {
  const CategorySearchState(
    this.query, {
    this.selected = PlatformSearchKind.songs,
    this.pages = const {},
  });
  final String query;
  final PlatformSearchKind selected;
  final Map<PlatformSearchKind, CategorySearchSlice> pages;
  CategorySearchSlice get current =>
      pages[selected] ?? const CategorySearchSlice();
}

final categorySearchProvider =
    NotifierProvider<CategorySearchController, CategorySearchState>(
      CategorySearchController.new,
    );

/// Each category owns its request/page/cache. Selection does not cancel another
/// category's valid public response; changing query/account invalidates them all.
class CategorySearchController extends Notifier<CategorySearchState> {
  final _browse = CachedBrowseLoader();
  var _generation = 0;
  final _abort = <PlatformSearchKind, Completer<void>>{};
  void _cancel() {
    for (final value in _abort.values) {
      if (!value.isCompleted) value.complete();
    }
    _abort.clear();
  }

  @override
  CategorySearchState build() {
    ref.onDispose(_cancel);
    ref.onDispose(_browse.reset);
    ref.listen(
      musicSearchControllerProvider.select((s) => s.query),
      (_, query) => reset(query),
    );
    ref.listen(
      platformAccountProvider.select((s) => (s.value?.ownerId, s.value?.token)),
      (before, after) {
        if (before != after) reset(state.query, retainResults: false);
      },
    );
    return CategorySearchState(ref.read(musicSearchControllerProvider).query);
  }

  void reset(String query, {bool retainResults = true}) {
    ++_generation;
    _browse.reset();
    _cancel();
    final previous = state;
    state = CategorySearchState(
      query,
      selected: query.isEmpty ? PlatformSearchKind.songs : previous.selected,
      pages: {
        if (retainResults && query.isNotEmpty)
          for (final entry in previous.pages.entries)
            entry.key: CategorySearchSlice(
              items: entry.value.items,
              stale: true,
            ),
      },
    );
    if (query.isNotEmpty && state.selected != PlatformSearchKind.songs) {
      unawaited(Future<void>.microtask(loadMore));
    }
  }

  Future<void> select(PlatformSearchKind kind) async {
    state = CategorySearchState(
      state.query,
      selected: kind,
      pages: state.pages,
    );
    if (kind != PlatformSearchKind.songs &&
        (!state.pages.containsKey(kind) || state.current.stale)) {
      await loadMore();
    }
  }

  Future<void> loadMore() async {
    final kind = state.selected;
    if (kind == PlatformSearchKind.songs || state.query.isEmpty) return;
    final old = state.current;
    final retained = old.stale ? const <PlatformSearchHit>[] : old.items;
    if (old.loading || !old.more) return;
    final generation = _generation;
    final query = state.query;
    final abort = Completer<void>();
    _abort[kind] = abort;
    void put(CategorySearchSlice value) {
      if (ref.mounted && generation == _generation) {
        state = CategorySearchState(
          state.query,
          selected: state.selected,
          pages: {...state.pages, kind: value},
        );
      }
    }

    put(
      CategorySearchSlice(
        items: old.items,
        page: old.page,
        total: old.total,
        more: old.more,
        loading: true,
        stale: old.stale,
      ),
    );
    try {
      final repository = ref.read(platformCategorySearchRepositoryProvider);
      final page = old.page + 1;
      final result = await _browse.load(
        key: (kind, page),
        request: () => repository.search(
          query,
          kind,
          page: page,
          abortTrigger: abort.future,
        ),
        onUpdate: (previous, current) {
          if (!ref.mounted ||
              generation != _generation ||
              state.query != query) {
            return;
          }
          final slice = state.pages[kind];
          if (slice == null || slice.stale) return;
          final items = slice.items.toList();
          replaceBrowsePage(
            items,
            previous.items,
            current.items,
            (item) => item.id,
            fallbackIndex: (page - 1) * 30,
          );
          put(
            CategorySearchSlice(
              items: items,
              page: slice.page,
              total: current.total,
              more: page == slice.page ? current.hasMore : slice.more,
              loading: slice.loading,
            ),
          );
        },
      );
      final seen = retained.map((e) => e.id).toSet();
      final added = result.items.where((e) => seen.add(e.id)).toList();
      put(
        CategorySearchSlice(
          items: [...retained, ...added],
          page: old.page + 1,
          total: result.total,
          more: result.hasMore && added.isNotEmpty,
        ),
      );
    } catch (error) {
      put(
        CategorySearchSlice(
          items: old.items,
          page: old.page,
          total: old.total,
          more: old.more,
          error: error is MusicPlatformException ? error.message : '加载未完成，请重试',
          stale: old.stale,
        ),
      );
    } finally {
      if (identical(_abort[kind], abort)) _abort.remove(kind);
    }
  }
}
