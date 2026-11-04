import '../music_platform/platform_backend_providers.dart';
import '../music_platform/netease/netease_catalog_adapters.dart';
import 'dart:async';
import '../../core/cache/cached_browse_loader.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/persistence/app_preferences.dart';
import '../../core/platform/distribution_channel.dart';
import '../music_platform/data/embedded_kugou_music_source.dart';
import '../music_platform/data/platform_search_repository.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/music_platform_providers.dart';
import '../../shared/models/track.dart';
import 'data/audius_music_source.dart';
import 'data/hot_music_repository.dart';
import 'data/jamendo_music_source.dart';
import 'data/kugou_music_source.dart';
import 'data/music_search_repository.dart';
import 'data/netease_music_source.dart';
import 'domain/music_source.dart';

final musicSearchHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final kugouMusicSourceProvider = Provider<KugouMusicSource>((ref) {
  if (DistributionChannel.isBeta) {
    // Restore only the platform credential; never wait for CloudBase here.
    ref.watch(platformAccountProvider);
    return EmbeddedKugouMusicSource(
      ref.watch(musicSearchHttpClientProvider),
      ref.watch(musicPlatformApiProvider),
    );
  }
  return KugouMusicSource(ref.watch(musicSearchHttpClientProvider));
});

final onlineMusicSourcesProvider = Provider<List<MusicSource>>((ref) {
  // Beta has one platform transport for every account/guest mode. Other
  // distributions retain their existing independent sources.
  if (DistributionChannel.isBeta) return [ref.watch(kugouMusicSourceProvider)];
  final client = ref.watch(musicSearchHttpClientProvider);
  return List<MusicSource>.unmodifiable([
    ref.watch(kugouMusicSourceProvider),
    NeteaseMusicSource(client),
    AudiusMusicSource(client),
    JamendoMusicSource(client),
  ]);
});

final musicSearchRepositoryProvider = Provider<MusicSearchRepository>((ref) {
  final repository = MusicSearchRepository(
    localTracks: const <Track>[],
    sources: ref.watch(onlineMusicSourcesProvider),
  );
  ref.onDispose(repository.cancelActiveSearch);
  return repository;
});

final hotMusicRepositoryProvider = Provider<HotMusicRepository>((ref) {
  final source = ref.watch(kugouMusicSourceProvider);
  final identity = ref.watch(platformAccountProvider).value;
  if (DistributionChannel.isBeta && ref.watch(usesNeteaseProvider)) {
    final music = ref.watch(neteaseMusicRepositoryProvider);
    return HotMusicRepository(
      rankingLoader: ({int limit = 9}) async =>
          (await music.newSongs()).take(limit).toList(),
      preferences: ref.watch(sharedPreferencesProvider),
      localTracks: const [],
      cacheNamespace: ':${identity?.ownerId}',
      sourceLabel: '网易云新歌榜',
    );
  }
  return HotMusicRepository(
    rankingLoader: ({int limit = 9}) => source.hotRanking(limit: limit),
    popularRankingLoader: ({int limit = 9}) =>
        source.ranking(rankId: '82831', sourceLabel: '酷狗网络热歌榜', limit: limit),
    risingRankingLoader: ({int limit = 9}) =>
        source.ranking(rankId: '6666', sourceLabel: '酷狗飙升榜', limit: limit),
    preferences: ref.watch(sharedPreferencesProvider),
    localTracks: const <Track>[],
  );
});

final hotMusicControllerProvider =
    AsyncNotifierProvider<HotMusicController, HotMusicSnapshot>(
      HotMusicController.new,
    );

class HotMusicController extends AsyncNotifier<HotMusicSnapshot> {
  @override
  Future<HotMusicSnapshot> build() {
    return ref.watch(hotMusicRepositoryProvider).load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<HotMusicSnapshot>();
    state = await AsyncValue.guard(
      () => ref.read(hotMusicRepositoryProvider).load(forceRefresh: true),
    );
  }
}

final musicSearchControllerProvider =
    NotifierProvider<MusicSearchController, MusicSearchState>(
      MusicSearchController.new,
    );

final platformSearchRepositoryProvider = Provider<PlatformSearchRepository>((
  ref,
) {
  final api = ref.watch(musicPlatformApiProvider);
  return ref.watch(usesNeteaseProvider)
      ? NeteaseSearchAdapter(api, ref.watch(neteaseMusicRepositoryProvider))
      : PlatformSearchRepository(api);
});

class MusicSearchController extends Notifier<MusicSearchState> {
  final _browse = CachedBrowseLoader();
  static const _legacyRecentKey = 'music_recent_searches';
  String _recentSearchesKey = _legacyRecentKey;
  static const _debounceDuration = Duration(milliseconds: 450);
  static const _maxRecentSearches = 8;

  Timer? _debounce;
  var _generation = 0;
  int _page = 0;
  Completer<void>? _platformAbort;

  void _cancelPlatform() {
    final abort = _platformAbort;
    _platformAbort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  @override
  MusicSearchState build() {
    // Rebuilding for a platform/account change invalidates in-flight pages as
    // well as their rendered rows; public search responses are owner-bound too.
    ++_generation;
    _browse.reset();
    _scheduledQuery = null;
    _debounce?.cancel();
    _cancelPlatform();
    ref.watch(
      platformAccountProvider.select((s) => (s.value?.ownerId, s.value?.token)),
    );
    final repository = ref.read(musicSearchRepositoryProvider);
    ref.onDispose(() {
      _debounce?.cancel();
      repository.cancelActiveSearch();
      _cancelPlatform();
      _browse.reset();
    });
    final preferences = ref.watch(sharedPreferencesProvider);
    if (DistributionChannel.isBeta) {
      final owner = ref.read(platformAccountProvider).value?.ownerId ?? 'guest';
      _recentSearchesKey = '$_legacyRecentKey:${Uri.encodeComponent(owner)}';
      // Claim the old single-platform history once, for the restored Kugou
      // owner only. A later account must never inherit another user's queries.
      if (owner.startsWith('kugou:') &&
          preferences.getString('music_recent_searches_migrated_owner') ==
              null) {
        final legacy = preferences.getStringList(_legacyRecentKey);
        if (legacy != null && !preferences.containsKey(_recentSearchesKey)) {
          unawaited(preferences.setStringList(_recentSearchesKey, legacy));
        }
        unawaited(
          preferences.setString('music_recent_searches_migrated_owner', owner),
        );
      }
    }
    return MusicSearchState(
      recentSearches: preferences.getStringList(_recentSearchesKey) ?? const [],
    );
  }

  String? _scheduledQuery;

  /// A composing IME value is not a committed query. Invalidate the previous
  /// request immediately, but keep its visible results until the debounce ends.
  void setQuery(String rawQuery, {bool composing = false}) {
    final query = rawQuery.trim();
    if (!composing && _scheduledQuery == query) return;
    _debounce?.cancel();
    _scheduledQuery = composing ? null : query;
    final generation = ++_generation;
    _browse.reset();
    _cancelPlatform();
    ref.read(musicSearchRepositoryProvider).cancelActiveSearch();
    if (composing) return;
    if (query.isEmpty) {
      state = MusicSearchState(recentSearches: state.recentSearches);
      return;
    }
    // Stable keeps its existing immediate preview/loading contract. Beta
    // publishes a committed query only after the typing interval has elapsed.
    if (!DistributionChannel.isBeta) _beginQuery(query);
    _debounce = Timer(_debounceDuration, () {
      if (!ref.mounted || generation != _generation) return;
      if (DistributionChannel.isBeta) _beginQuery(query);
      unawaited(_search(query, generation));
    });
  }

  void _beginQuery(String query) {
    state = state.copyWith(
      query: query,
      localTracks: DistributionChannel.isBeta ? null : const [],
      onlineTracks: DistributionChannel.isBeta ? null : const [],
      isLoading: true,
      fromCache: false,
      clearError: true,
      warnings: const [],
      hasMore: false,
      isLoadingMore: false,
      clearTotal: true,
      clearMoreError: true,
    );
  }

  Future<void> submit(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return;
    }
    _debounce?.cancel();
    _generation += 1;
    _cancelPlatform();
    ref.read(musicSearchRepositoryProvider).cancelActiveSearch();
    _scheduledQuery = query;
    _beginQuery(query);
    await _search(query, _generation);
  }

  Future<void> retry() => submit(state.query);

  void removeRecentSearch(String query) {
    final recent = [...state.recentSearches]..remove(query);
    _saveRecentSearches(recent);
  }

  void clearRecentSearches() => _saveRecentSearches(const []);

  Future<void> _search(String query, int generation) async {
    if (DistributionChannel.isBeta) {
      await _searchPlatform(query, generation, reset: true);
      return;
    }
    try {
      final result = await ref
          .read(musicSearchRepositoryProvider)
          .search(query);
      if (generation != _generation) {
        return;
      }
      _rememberQuery(query);
      state = state.copyWith(
        query: result.query,
        localTracks: result.localTracks,
        onlineTracks: result.onlineTracks,
        warnings: result.warnings,
        isLoading: false,
        fromCache: result.fromCache,
        clearError: true,
      );
    } on http.RequestAbortedException {
      // A newer query superseded this request. Its state is already visible.
    } on MusicSearchException catch (error) {
      if (generation != _generation) {
        return;
      }
      state = state.copyWith(
        localTracks: _localMatches(query),
        onlineTracks: const [],
        warnings: const [],
        isLoading: false,
        fromCache: false,
        errorMessage: error.message,
      );
    } on Object {
      if (generation != _generation) {
        return;
      }
      state = state.copyWith(
        localTracks: _localMatches(query),
        onlineTracks: const [],
        warnings: const [],
        isLoading: false,
        fromCache: false,
        errorMessage: '搜索暂时不可用，请稍后重试',
      );
    }
  }

  /// Paging has its own busy/error state so an append never replaces the
  /// visible list with a full-page spinner. Late responses cannot cross queries.
  Future<void> loadMore() async {
    if (!DistributionChannel.isBeta ||
        state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore ||
        state.query.isEmpty) {
      return;
    }
    await _searchPlatform(state.query, _generation, reset: false);
  }

  Future<void> _searchPlatform(
    String query,
    int generation, {
    required bool reset,
  }) async {
    final abort = Completer<void>();
    _platformAbort = abort;
    final page = reset ? 1 : _page + 1;
    if (!reset) {
      state = state.copyWith(isLoadingMore: true, clearMoreError: true);
    }
    try {
      final repository = ref.read(platformSearchRepositoryProvider);
      final result = await _browse.load(
        key: page,
        request: () =>
            repository.search(query, page: page, abortTrigger: abort.future),
        onUpdate: (previous, current) {
          if (!ref.mounted ||
              generation != _generation ||
              state.query != query) {
            return;
          }
          final items = state.onlineTracks.toList();
          replaceBrowsePage(
            items,
            previous.tracks,
            current.tracks,
            (track) => track.id,
            fallbackIndex: (page - 1) * 30,
          );
          state = state.copyWith(
            onlineTracks: items,
            total: current.total,
            hasMore: page == _page ? current.hasMore : state.hasMore,
            fromCache: false,
          );
        },
      );
      if (generation != _generation) return;
      // Remove repeated file IDs only; never collapse distinct recordings by
      // title/artist or re-rank upstream results with the legacy fuzzy matcher.
      final merged = <String, Track>{
        if (!reset)
          for (final track in state.onlineTracks) track.id: track,
      };
      final previousLength = merged.length;
      for (final track in result.tracks) {
        merged.putIfAbsent(track.id, () => track);
      }
      final progressed = reset || merged.length > previousLength;
      _page = page;
      _rememberQuery(query);
      state = state.copyWith(
        onlineTracks: merged.values.toList(growable: false),
        localTracks: const [],
        isLoading: false,
        isLoadingMore: false,
        total: result.total,
        hasMore: result.hasMore && progressed,
        clearError: true,
        clearMoreError: true,
        fromCache: false,
      );
    } on http.RequestAbortedException {
      // A newer query owns state now.
    } catch (error) {
      if (generation != _generation) return;
      final message = error is MusicPlatformException
          ? error.message
          : '搜索暂时不可用，请重试';
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        errorMessage: reset ? message : null,
        moreError: reset ? null : message,
      );
    } finally {
      if (identical(_platformAbort, abort)) _platformAbort = null;
    }
  }

  List<Track> _localMatches(String query) {
    return const <Track>[];
  }

  void _rememberQuery(String query) {
    final recent = [...state.recentSearches]
      ..remove(query)
      ..insert(0, query);
    if (recent.length > _maxRecentSearches) {
      recent.removeRange(_maxRecentSearches, recent.length);
    }
    _saveRecentSearches(recent);
  }

  void _saveRecentSearches(List<String> recent) {
    final immutable = List<String>.unmodifiable(recent);
    state = state.copyWith(recentSearches: immutable);
    ref
        .read(sharedPreferencesProvider)
        .setStringList(_recentSearchesKey, immutable);
  }
}

class MusicSearchState {
  const MusicSearchState({
    this.query = '',
    this.localTracks = const [],
    this.onlineTracks = const [],
    this.recentSearches = const [],
    this.warnings = const [],
    this.isLoading = false,
    this.fromCache = false,
    this.errorMessage,
    this.total,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.moreError,
  });

  final String query;
  final List<Track> localTracks;
  final List<Track> onlineTracks;
  final List<String> recentSearches;
  final List<String> warnings;
  final bool isLoading;
  final bool fromCache;
  final String? errorMessage;
  final int? total;
  final bool hasMore;
  final bool isLoadingMore;
  final String? moreError;

  bool get hasResults => localTracks.isNotEmpty || onlineTracks.isNotEmpty;

  MusicSearchState copyWith({
    String? query,
    List<Track>? localTracks,
    List<Track>? onlineTracks,
    List<String>? recentSearches,
    List<String>? warnings,
    bool? isLoading,
    bool? fromCache,
    String? errorMessage,
    bool clearError = false,
    int? total,
    bool clearTotal = false,
    bool? hasMore,
    bool? isLoadingMore,
    String? moreError,
    bool clearMoreError = false,
  }) {
    return MusicSearchState(
      query: query ?? this.query,
      localTracks: localTracks ?? this.localTracks,
      onlineTracks: onlineTracks ?? this.onlineTracks,
      recentSearches: recentSearches ?? this.recentSearches,
      warnings: warnings ?? this.warnings,
      isLoading: isLoading ?? this.isLoading,
      fromCache: fromCache ?? this.fromCache,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      total: clearTotal ? null : total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      moreError: clearMoreError ? null : moreError ?? this.moreError,
    );
  }
}
