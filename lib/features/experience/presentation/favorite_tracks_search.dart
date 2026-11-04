import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/music_list_footer.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import '../../../shared/widgets/keyboard_overlay_layout.dart';
import '../../library/library_providers.dart';
import '../../library/data/favorite_track_window.dart';
import '../../../shared/widgets/automatic_song_paging.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../music_platform/presentation/platform_comment_composer.dart';
import 'editorial_widgets.dart';

/// Filtering receives the full account-owned collection. It has no dependency
/// on a global search client, and never limits matches to painted/lazy rows.
List<Track> filterFavoriteTracks(List<Track> tracks, String query) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
  return query.trim().isEmpty
      ? tracks
      : tracks.where((track) {
          final value = '${track.title} ${track.artist} ${track.album}'
              .toLowerCase();
          return words.every(value.contains);
        }).toList();
}

class FavoriteTracksSearch extends ConsumerStatefulWidget {
  const FavoriteTracksSearch({
    required this.tracks,
    required this.header,
    required this.onRefresh,
    required this.onCreatePlaylist,
    super.key,
  });
  final VoidCallback onCreatePlaylist;
  final List<Track> tracks;
  final Widget header;
  final Future<void> Function() onRefresh;
  @override
  ConsumerState<FavoriteTracksSearch> createState() =>
      _FavoriteTracksSearchState();
}

class _FavoriteTracksSearchState extends ConsumerState<FavoriteTracksSearch> {
  final _text = TextEditingController();
  Object? _owner;
  String _query = '';
  bool _editing = false;
  Timer? _debounce;
  int _searchGeneration = 0, _searchOffset = 0;
  bool _searching = false, _searchMore = false;
  Object? _searchError;
  List<Track> _results = const [];

  void _setQuery(String value) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _query = value;
      _searchOffset = 0;
      _searchMore = false;
      _searchError = null;
      _searching =
          value.trim().isNotEmpty && ref.exists(favoriteTrackWindowProvider);
    });
    if (_searching) {
      _debounce = Timer(
        const Duration(milliseconds: 220),
        () => _search(generation),
      );
    }
  }

  Future<void> _search(int generation, {bool append = false}) async {
    if (!mounted || generation != _searchGeneration) return;
    final window = ref.read(favoriteTrackWindowProvider);
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final page = await window.search(
        _query,
        offset: append ? _searchOffset : 0,
      );
      if (!mounted ||
          generation != _searchGeneration ||
          !identical(window, ref.read(favoriteTrackWindowProvider))) {
        return;
      }
      setState(() {
        final seen = append ? _results.map((t) => t.id).toSet() : <String>{};
        _results = [
          if (append) ..._results,
          ...page.items.where((t) => seen.add(t.id)),
        ];
        _searchOffset = page.nextOffset;
        _searchMore = page.hasMore;
        _searching = false;
      });
    } catch (failure) {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _searching = false;
          _searchError = failure;
        });
      }
    }
  }

  void _close() {
    _debounce?.cancel();
    ++_searchGeneration;
    _text.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _editing = false;
      _query = '';
      _searching = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    ++_searchGeneration;
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(libraryRepositoryProvider);
    if (!identical(owner, _owner)) {
      _owner = owner;
      _query = '';
      _text.clear();
      _editing = false;
      _debounce?.cancel();
      ++_searchGeneration;
      _results = const [];
      _searching = false;
    }
    final window = ref.exists(favoriteTrackWindowProvider)
        ? ref.watch(favoriteTrackWindowProvider)
        : null;
    return window == null
        ? _body(context, null)
        : ListenableBuilder(
            listenable: window,
            builder: (context, _) => _body(context, window),
          );
  }

  Widget _body(BuildContext context, FavoriteTrackWindow? window) {
    final searching = _query.trim().isNotEmpty && window != null;
    final tracks = searching
        ? _results
        : filterFavoriteTracks(widget.tracks, _query);
    final loading = searching ? _searching : window?.loading ?? false;
    final more = searching ? _searchMore : window?.hasMore ?? false;
    final error = searching ? _searchError : window?.error;
    Future<void> loadMore() => searching
        ? _search(_searchGeneration, append: true)
        : window?.loadMore() ?? Future.value();
    return BetaMusicChromeCover(
      enabled: _editing,
      child: PopScope(
        canPop: !_editing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _editing) _close();
        },
        child: KeyboardOverlayLayout(
          builder: (context, lift, keyboard) => Stack(
            children: [
              MusicRefreshIndicator(
                onRefresh: widget.onRefresh,
                child: AutomaticSongPaging(
                  enabled: more && !loading && error == null,
                  onLoadMore: loadMore,
                  child: ListView.builder(
                    key: const ValueKey('favorite-search-results'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + 14,
                      bottom: _editing
                          ? lift + 88 + MediaQuery.viewPaddingOf(context).bottom
                          : BetaContentInsets.musicBottomOf(context, 12),
                    ),
                    itemCount: tracks.length + 3,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return EditorialHeader(
                          '我的喜欢',
                          back: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '新建歌单',
                                onPressed: widget.onCreatePlaylist,
                                icon: const Icon(
                                  Icons.add_circle_outline_rounded,
                                ),
                              ),
                              IconButton(
                                tooltip: _editing ? '关闭收藏搜索' : '搜索我的喜欢',
                                icon: Icon(
                                  _editing
                                      ? CupertinoIcons.xmark
                                      : CupertinoIcons.search,
                                ),
                                onPressed: () => _editing
                                    ? _close()
                                    : setState(() => _editing = true),
                              ),
                            ],
                          ),
                        );
                      }
                      if (index == 1) return widget.header;
                      if (index == tracks.length + 2) {
                        if (loading) {
                          return const PlatformFeedbackState(loading: true);
                        }
                        if (error != null) {
                          return TextButton(
                            onPressed: loadMore,
                            child: const Text('加载未完成，点击重试'),
                          );
                        }
                        if (more) return const SizedBox(height: 12);
                        return tracks.isEmpty
                            ? EditorialEmpty(
                                _query.isEmpty ? '还没有收藏的歌曲' : '收藏中没有找到匹配歌曲',
                              )
                            : const MusicListEnd();
                      }
                      return EditorialTrackRow(
                        track: tracks[index - 2],
                        contextTracks: tracks,
                      );
                    },
                  ),
                ),
              ),
              if (_editing)
                Positioned(
                  key: const ValueKey('favorite-keyboard-composer'),
                  left: 0,
                  right: 0,
                  bottom: lift,
                  child: SafeArea(
                    top: false,
                    bottom: !keyboard,
                    child: Material(
                      type: MaterialType.transparency,
                      child: PlatformCommentComposer(
                        controller: _text,
                        sending: false,
                        keyboardVisible: keyboard,
                        hintText: '搜索收藏的歌名、歌手、专辑',
                        singleLine: true,
                        autofocus: true,
                        expandOnPress: false,
                        actionIcon: CupertinoIcons.search,
                        sendLabel: '搜索我的喜欢',
                        onChanged: _setQuery,
                        onSubmitted: _setQuery,
                        onSend: () {
                          _setQuery(_text.text);
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
