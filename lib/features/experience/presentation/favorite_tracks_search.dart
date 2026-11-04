import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/music_list_footer.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import '../../library/library_providers.dart';
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
  void _close() {
    _text.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _editing = false;
      _query = '';
    });
  }

  @override
  void dispose() {
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
    }
    final tracks = filterFavoriteTracks(widget.tracks, _query);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return BetaMusicChromeCover(
      enabled: _editing,
      child: PopScope(
        canPop: !_editing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _editing) _close();
        },
        child: Stack(
          children: [
            MusicRefreshIndicator(
              onRefresh: widget.onRefresh,
              child: ListView.builder(
                key: const ValueKey('favorite-search-results'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + 14,
                  bottom: _editing
                      ? 88 + MediaQuery.viewPaddingOf(context).bottom
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
                            icon: const Icon(Icons.add_circle_outline_rounded),
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
            if (_editing)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
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
                      onChanged: (value) => setState(() => _query = value),
                      onSubmitted: (value) => setState(() => _query = value),
                      onSend: () {
                        setState(() => _query = _text.text);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
