import '../../../shared/widgets/beta_content_insets.dart';
import 'beta_category_search_results.dart';
import '../../../shared/widgets/beta_edge_back.dart';
import '../../../shared/widgets/beta_bottom_search.dart';
import '../../../shared/widgets/beta_page_search_layout.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/artwork_reveal_boundary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../shared/models/track.dart';
import '../../../shared/utils/duration_format.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../library/library_providers.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../player/presentation/music_page_transition.dart';
import '../../recommendation/recommendation_providers.dart';
import '../../social/domain/social_models.dart';
import '../../social/social_providers.dart';
import '../../social/presentation/social_widgets.dart';
import '../../themes/mesting_palette.dart';
import '../../themes/music_theme_tokens.dart';
import '../domain/music_rankings.dart';
import '../search_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../auth/account_capabilities.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../music_platform/presentation/platform_search_landing.dart';
import '../../music_platform/presentation/platform_comments_page.dart';

List<Track> selectedSearchPlaybackQueue(Track selectedTrack) =>
    List<Track>.unmodifiable([selectedTrack]);

class MusicSearchPage extends ConsumerStatefulWidget {
  const MusicSearchPage({super.key});

  @override
  ConsumerState<MusicSearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends ConsumerState<MusicSearchPage> {
  final _resultsKey = GlobalKey<MusicSearchResultsBodyState>();
  late final _bottomSearch = BetaPageSearchController(
    hintText: '搜索歌曲、歌手或专辑',
    onSubmitted: _submit,
    onCleared: () => _handleQueryChanged(''),
    onChanged: _handleQueryChanged,
  );
  TextEditingController get _textController => _bottomSearch.text;
  FocusNode get _focusNode => _bottomSearch.focus;
  bool _inputIsEmpty = true;
  bool _hasSubmitted = false;

  @override
  void initState() {
    super.initState();
    // Composition can end without changing text. A value listener observes
    // that commit too; TextField.onChanged alone misses it on some keyboards.
    _textController.addListener(_editingChanged);
  }

  void _editingChanged() {
    final value = _textController.value;
    ref
        .read(musicSearchControllerProvider.notifier)
        .setQuery(
          value.text,
          composing: value.composing.isValid && !value.composing.isCollapsed,
        );
  }

  @override
  void dispose() {
    _textController.removeListener(_editingChanged);
    _bottomSearch.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    setState(() {
      _inputIsEmpty = false;
      _hasSubmitted = true;
    });
    _textController.text = query;
    _textController.selection = TextSelection.collapsed(offset: query.length);
    ref.read(musicSearchControllerProvider.notifier).submit(query);
    _focusNode.unfocus();
  }

  void _handleQueryChanged(String value) {
    final isEmpty = value.trim().isEmpty;
    if (isEmpty != _inputIsEmpty || (!isEmpty && _hasSubmitted)) {
      setState(() {
        _inputIsEmpty = isEmpty;
        if (!isEmpty) _hasSubmitted = false;
      });
    }
    _editingChanged();
  }

  void _closeSearch() {
    if (DistributionChannel.isBeta && !_inputIsEmpty) {
      void clear() {
        if (!mounted) return;
        _textController.clear();
        _focusNode.unfocus();
        ref.read(musicSearchControllerProvider.notifier).setQuery('');
        setState(() {
          _inputIsEmpty = true;
          _hasSubmitted = false;
        });
      }

      final results = _resultsKey.currentState;
      results == null ? clear() : results.returnToLanding(clear);
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        '/music/recommend',
        extra: const MusicPageTransitionIntent.backward(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Beta's shell owns both input and results, including direct route entry.
    // Keep this route as a compatibility address without building a second UI.
    if (DistributionChannel.isBeta &&
        BetaBottomSearchScope.maybeOf(context) != null) {
      return const SizedBox.expand();
    }
    final search = ref.watch(musicSearchControllerProvider);
    final top = MediaQuery.paddingOf(context).top;
    final tokens = context.musicThemeTokens;
    return BetaPageSearchLayout(
      controller: _bottomSearch,
      child: BetaEdgeBack(
        enabled: DistributionChannel.isBeta,
        onBack: _closeSearch,
        child: PopScope(
          canPop: !DistributionChannel.isBeta || _inputIsEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _closeSearch();
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tokens.glassStrong.withValues(alpha: .93),
                  tokens.glass.withValues(alpha: .89),
                ],
              ),
            ),
            child: Column(
              children: [
                SizedBox(height: top + 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _CircleBack(onTap: _closeSearch),
                ),
                Expanded(
                  child: DistributionChannel.isBeta
                      ? MusicSearchResultsBody(
                          key: _resultsKey,
                          onSearch: _submit,
                        )
                      : _inputIsEmpty
                      ? _SearchLanding(onSearch: _submit)
                      : (_hasSubmitted
                            ? AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: search.isLoading
                                    ? _SearchLoading(
                                        key: ValueKey(
                                          'search-loading-${search.query}',
                                        ),
                                        query: search.query,
                                      )
                                    : _SearchResults(
                                        key: ValueKey(
                                          'search-results-${search.query}',
                                        ),
                                        state: search,
                                        onSearch: _submit,
                                      ),
                              )
                            : AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: _SearchInputPreview(
                                  key: ValueKey(
                                    'search-input-preview-${search.query}',
                                  ),
                                  state: search,
                                  onSearch: _submit,
                                ),
                              )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Search results reused by the official bottom search field. It consumes the
/// same paged controller, so there is no second search implementation/state.
class MusicSearchResultsBody extends ConsumerStatefulWidget {
  const MusicSearchResultsBody({required this.onSearch, super.key});
  final ValueChanged<String> onSearch;
  @override
  ConsumerState<MusicSearchResultsBody> createState() =>
      MusicSearchResultsBodyState();
}

/// Keep the real result pane and its providers alive until the return motion
/// ends. Clearing query first would reset five categories in the outgoing frame.
class MusicSearchResultsBodyState extends ConsumerState<MusicSearchResultsBody>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 280),
    value: 1,
  );
  bool _returning = false;
  bool _entering = false;
  int _presentation = 0;
  @override
  void initState() {
    super.initState();
    // A landing-only visit has no AnimatedBuilder; initialize before disposal.
    _motion;
  }

  Future<void> _enterResults() async {
    final generation = ++_presentation;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final start = reduced ? 1.0 : (_returning ? _motion.value : 0.0);
    setState(() {
      _returning = false;
      _entering = !reduced;
    });
    try {
      await _motion.forward(from: start).orCancel;
      // The final moving frame is painted before mounting providers, lazy
      // result rows and image decoders. Network requests can run in parallel.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && generation == _presentation) {
        setState(() => _entering = false);
      }
    } on TickerCanceled {
      // A return gesture or newer query owns this presentation now.
    }
  }

  Future<void> returnToLanding(VoidCallback clear) async {
    if (_returning) return;
    final query = ref.read(musicSearchControllerProvider).query;
    if (query.isEmpty) {
      clear();
      return;
    }
    final generation = ++_presentation;
    setState(() => _returning = true);
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = 0;
      } else {
        await _motion.reverse().orCancel;
      }
      if (mounted && ref.read(musicSearchControllerProvider).query == query) {
        clear();
      }
    } on TickerCanceled {
      // A newer query/navigation owns the presentation now.
    } finally {
      if (mounted && generation == _presentation) {
        setState(() {
          _returning = false;
          _entering = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(
      musicSearchControllerProvider.select((s) => s.query),
    );
    ref.listen(musicSearchControllerProvider.select((s) => s.query), (
      before,
      after,
    ) {
      if (after.isNotEmpty &&
          (before == null || before.isEmpty || _returning && before != after)) {
        _enterResults();
      }
    });
    if (!DistributionChannel.isBeta) {
      final state = ref.watch(musicSearchControllerProvider);
      return state.query.isEmpty
          ? _SearchLanding(onSearch: widget.onSearch)
          : state.isLoading
          ? _SearchLoading(query: state.query)
          : _SearchResults(state: state, onSearch: widget.onSearch);
    }
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Retain the landing's element, scroll position and ready frames.
          // Offstage prevents hit testing, and TickerMode stops hidden work.
          Offstage(
            offstage: query.isNotEmpty && !_returning && !_entering,
            child: TickerMode(
              enabled: query.isEmpty || _returning,
              child: RepaintBoundary(
                child: ArtworkRevealBoundary(
                  child: PlatformSearchLanding(onSearch: widget.onSearch),
                ),
              ),
            ),
          ),
          if (query.isNotEmpty)
            AnimatedBuilder(
              animation: _motion,
              child: RepaintBoundary(
                child: TickerMode(
                  enabled: !_returning,
                  child: _entering
                      ? const Center(
                          child: BetaActivityIndicator(label: '正在加载内容'),
                        )
                      : const BetaCategorySearchResults(),
                ),
              ),
              builder: (context, child) => IgnorePointer(
                ignoring: _returning,
                child: FractionalTranslation(
                  translation: Offset(
                    1 - Curves.easeInOutCubic.transform(_motion.value),
                    0,
                  ),
                  child: ColoredBox(
                    key: const ValueKey('beta13-search-results-surface'),
                    color: Theme.of(context).colorScheme.surface,
                    child: child,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleBack extends StatelessWidget {
  const _CircleBack({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    if (DistributionChannel.isBeta) {
      return BetaGlassBackButton(onPressed: onTap);
    }
    return Material(
      color: tokens.glass,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: tokens.shadow,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox.square(
          dimension: 42,
          child: Icon(Icons.arrow_back_ios_new_rounded, size: 17),
        ),
      ),
    );
  }
}

class _SearchLanding extends ConsumerStatefulWidget {
  const _SearchLanding({required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  ConsumerState<_SearchLanding> createState() => _SearchLandingState();
}

enum _RankingType { search, popular, rising, personal }

extension on _RankingType {
  String get label => switch (this) {
    _RankingType.search => '热搜榜',
    _RankingType.popular => '热歌榜',
    _RankingType.rising => '飙升榜',
    _RankingType.personal => '我的热榜',
  };
}

class _SearchLandingState extends ConsumerState<_SearchLanding> {
  _RankingType _rankingType = _RankingType.search;

  @override
  Widget build(BuildContext context) {
    if (DistributionChannel.isBeta) {
      return PlatformSearchLanding(onSearch: widget.onSearch);
    }
    final tokens = context.musicThemeTokens;
    final hotRanking = ref.watch(hotMusicControllerProvider);
    final hotSnapshot = hotRanking.value;
    final hotTracks = hotSnapshot?.tracks ?? const <Track>[];
    final popularTracks = hotSnapshot?.popularTracks ?? const <Track>[];
    final risingTracks = hotSnapshot?.risingTracks ?? const <Track>[];
    final listeningSignals =
        ref.watch(listeningSignalsProvider).value ?? const [];
    final favoriteTracks = ref.watch(favoriteTracksProvider).value ?? const [];
    final artistSuggestions = artistSuggestionsForUser(
      listeningSignals: listeningSignals,
      favoriteTracks: favoriteTracks,
      hotTracks: hotTracks,
      popularTracks: popularTracks,
      risingTracks: risingTracks,
    );
    final personalTracks = personalHotRanking(
      listeningSignals: listeningSignals,
      favoriteTracks: favoriteTracks,
      freshTracks: [...hotTracks, ...popularTracks, ...risingTracks],
    );
    final selectedTracks = switch (_rankingType) {
      _RankingType.search => hotTracks,
      _RankingType.popular => popularTracks,
      _RankingType.rising => risingTracks,
      _RankingType.personal => personalTracks,
    };
    final remoteRanking = _rankingType != _RankingType.personal;
    final badge = remoteRanking
        ? hotSnapshot == null
              ? ''
              : hotSnapshot.statusLabel
        : personalTracks.isEmpty
        ? '等待你的播放'
        : '专属排序';
    final leaderBadge = switch (_rankingType) {
      _RankingType.search => '爆',
      _RankingType.popular => '热',
      _RankingType.rising => '升',
      _RankingType.personal => '荐',
    };
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: BetaContentInsets.musicPaddingOf(
        context,
        EdgeInsets.fromLTRB(18, 22, 0, 96),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Row(
            children: [
              Text(
                '猜你喜欢',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  artistSuggestions.label,
                  key: ValueKey(artistSuggestions.source),
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (
                var index = 0;
                index < artistSuggestions.artists.length;
                index += 1
              )
                ActionChip(
                  key: ValueKey('artist-suggestion-$index'),
                  label: Text(artistSuggestions.artists[index]),
                  onPressed: () =>
                      widget.onSearch(artistSuggestions.artists[index]),
                  backgroundColor: tokens.glassSubtle,
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12,
                  ),
                  visualDensity: const VisualDensity(vertical: -3),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Column(
            children: [
              _RankingTabs(
                selected: _rankingType,
                onSelected: (value) => setState(() => _rankingType = value),
              ),
              const SizedBox(height: 9),
              SizedBox(
                height: 562,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  layoutBuilder: (currentChild, _) =>
                      currentChild ?? const SizedBox.shrink(),
                  child: _RankingCard(
                    key: ValueKey('ranking-card-${_rankingType.name}'),
                    title: _rankingType.label,
                    badge: badge,
                    songs: selectedTracks
                        .map((track) => track.title)
                        .toList(growable: false),
                    leaderBadge: leaderBadge,
                    emptyMessage: _rankingType == _RankingType.personal
                        ? '播放或收藏歌曲后，这里会生成你的专属排行'
                        : '暂时没有可播放歌曲，刷新后再试',
                    isLoading: remoteRanking && hotSnapshot == null,
                    onRefresh: remoteRanking ? _refreshRankings : null,
                    onSong: (index) {
                      if (index >= selectedTracks.length) return;
                      ref
                          .read(audioHandlerProvider)
                          .playSingleTrack(
                            selectedTracks[index],
                            playbackContext: selectedTracks,
                          );
                    },
                    onPlay: selectedTracks.isEmpty
                        ? null
                        : () => ref
                              .read(audioHandlerProvider)
                              .replaceQueue(selectedTracks),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _refreshRankings() async {
    await ref.read(hotMusicControllerProvider.notifier).refresh();
    if (!mounted) return;
    showMusicNotice(
      context,
      icon: Icons.check_rounded,
      title: '榜单已更新',
      message: '热搜、热歌与飙升榜已同步',
    );
  }
}

class _RankingTabs extends StatelessWidget {
  const _RankingTabs({required this.selected, required this.onSelected});

  final _RankingType selected;
  final ValueChanged<_RankingType> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    const accent = MestingPalette.heart;
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.glassSubtle,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          for (final type in _RankingType.values)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('ranking-tab-${type.name}'),
                  onTap: () => onSelected(type),
                  borderRadius: BorderRadius.circular(11),
                  child: AnimatedContainer(
                    key: ValueKey('ranking-tab-surface-${type.name}'),
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected == type
                          ? accent.withValues(alpha: .14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: selected == type
                          ? Border.all(color: accent.withValues(alpha: .28))
                          : null,
                    ),
                    child: Text(
                      type.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: selected == type ? accent : tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: selected == type
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    super.key,
    required this.title,
    required this.badge,
    required this.songs,
    required this.onSong,
    required this.emptyMessage,
    this.onPlay,
    this.onRefresh,
    this.isLoading = false,
    this.leaderBadge,
  });

  final String title;
  final String badge;
  final List<String> songs;
  final ValueChanged<int> onSong;
  final String emptyMessage;
  final VoidCallback? onPlay;
  final VoidCallback? onRefresh;
  final bool isLoading;
  final String? leaderBadge;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: dark ? const Color(0x6B000000) : const Color(0x38232A3D),
              blurRadius: dark ? 28 : 32,
              spreadRadius: -7,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: accent.withValues(alpha: dark ? .10 : .07),
              blurRadius: 22,
              spreadRadius: -9,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: BoxDecoration(
              color: tokens.glass,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: dark ? tokens.border : const Color(0x2E596579),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 7),
                    if (badge.isNotEmpty)
                      Text(
                        badge,
                        style: TextStyle(color: tokens.textMuted, fontSize: 10),
                      ),
                    const Spacer(),
                    if (onRefresh != null) ...[
                      _RankingRefreshButton(
                        onTap: onRefresh!,
                        isLoading: isLoading,
                      ),
                      const SizedBox(width: 7),
                    ],
                    TextButton.icon(
                      key: const ValueKey('ranking-play-button'),
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 15),
                      label: const Text('播放'),
                      style: TextButton.styleFrom(
                        backgroundColor: MestingPalette.heart,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: MestingPalette.heartSoft,
                        disabledForegroundColor: MestingPalette.heart
                            .withValues(alpha: .46),
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),
                Expanded(
                  child: isLoading && songs.isEmpty
                      ? const _RankingLoadingRows()
                      : songs.isEmpty
                      ? _RankingEmptyState(message: emptyMessage)
                      : ListView.separated(
                          primary: false,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: songs.length.clamp(0, 9),
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) =>
                              _RankingSongPressFeedback(
                                onTap: () => onSong(index),
                                child: SizedBox(
                                  height: 52,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: index < 3
                                                ? const Color(0xFF4F65D1)
                                                : tokens.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          songs[index],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (leaderBadge != null && index == 0)
                                        Container(
                                          key: const ValueKey(
                                            'ranking-leader-badge',
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: MestingPalette.heart,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            leaderBadge!,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankingRefreshButton extends StatefulWidget {
  const _RankingRefreshButton({required this.onTap, required this.isLoading});

  final VoidCallback onTap;
  final bool isLoading;

  @override
  State<_RankingRefreshButton> createState() => _RankingRefreshButtonState();
}

class _RankingRefreshButtonState extends State<_RankingRefreshButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: '刷新实时榜单',
      child: Semantics(
        button: true,
        label: '刷新实时榜单',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.isLoading ? null : widget.onTap,
          onTapDown: widget.isLoading ? null : (_) => _setPressed(true),
          onTapCancel: widget.isLoading ? null : () => _setPressed(false),
          onTapUp: widget.isLoading ? null : (_) => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed ? .84 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: AnimatedRotation(
              turns: widget.isLoading ? 1 : 0,
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: _pressed ? .24 : .10),
                  border: Border.all(
                    color: accent.withValues(alpha: _pressed ? .42 : .16),
                  ),
                ),
                child: Icon(Icons.refresh_rounded, size: 17, color: accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RankingSongPressFeedback extends StatefulWidget {
  const _RankingSongPressFeedback({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_RankingSongPressFeedback> createState() =>
      _RankingSongPressFeedbackState();
}

class _RankingSongPressFeedbackState extends State<_RankingSongPressFeedback> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? .965 : 1,
          duration: const Duration(milliseconds: 115),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: _pressed ? .11 : 0),
              borderRadius: BorderRadius.circular(13),
            ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 95),
              opacity: _pressed ? .82 : 1,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _RankingLoadingRows extends StatelessWidget {
  const _RankingLoadingRows();

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Column(
      children: List.generate(9, (index) {
        return SizedBox(
          height: 52,
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: .58 + (index % 3) * .10,
                  child: Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: tokens.textMuted.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _RankingEmptyState extends StatelessWidget {
  const _RankingEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .10),
                border: Border.all(color: accent.withValues(alpha: .18)),
              ),
              child: Icon(Icons.leaderboard_rounded, color: accent, size: 23),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchLoading extends StatelessWidget {
  const _SearchLoading({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MestingLoadingIndicator(
        key: const ValueKey('search-loading-animation'),
        semanticLabel: query.isEmpty ? '正在加载搜索结果' : '正在加载“$query”的搜索结果',
      ),
    );
  }
}

class _SearchInputPreview extends ConsumerWidget {
  const _SearchInputPreview({required this.state, this.onSearch, super.key});

  final MusicSearchState state;
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoading && !state.hasResults) {
      return _SearchLoading(query: state.query);
    }
    final users = ref.watch(showMestingFeaturesProvider)
        ? ref.watch(socialUserSearchProvider(state.query))
        : const AsyncData<List<SocialUser>>([]);

    return SingleChildScrollView(
      key: const ValueKey('search-input-preview-scroll'),
      physics: const BouncingScrollPhysics(),
      padding: BetaContentInsets.musicPaddingOf(
        context,
        EdgeInsets.fromLTRB(18, 10, 18, 96),
      ),
      child: _NeteaseSearchOverview(
        query: state.query,
        users: users.value ?? const <SocialUser>[],
        tracks: [...state.localTracks, ...state.onlineTracks],
        onSearch: onSearch,
      ),
    );
  }
}

enum _SearchResultCategory { tracks, users }

extension on _SearchResultCategory {
  String get label => switch (this) {
    _SearchResultCategory.tracks => '单曲',
    _SearchResultCategory.users => '用户',
  };
}

class _SearchResults extends ConsumerStatefulWidget {
  const _SearchResults({required this.state, this.onSearch, super.key});

  final MusicSearchState state;
  final ValueChanged<String>? onSearch;

  @override
  ConsumerState<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends ConsumerState<_SearchResults> {
  _SearchResultCategory _category = _SearchResultCategory.tracks;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.extentAfter < 320 &&
          widget.state.moreError == null &&
          _category == _SearchResultCategory.tracks) {
        ref.read(musicSearchControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final showUsers =
        _category == _SearchResultCategory.users &&
        ref.watch(showMestingFeaturesProvider);
    final showTracks = !showUsers;
    final userResults = showUsers
        ? ref.watch(socialUserSearchProvider(state.query))
        : const AsyncData<List<SocialUser>>(<SocialUser>[]);
    final hasUserResults = userResults.value?.isNotEmpty == true;
    final allUsers = userResults.value ?? const <SocialUser>[];
    if (DistributionChannel.isBeta) return const BetaCategorySearchResults();
    return Column(
      children: [
        if (ref.watch(showMestingFeaturesProvider))
          _SearchResultTabs(
            selected: _category,
            onSelected: (category) => setState(() => _category = category),
          ),
        Expanded(
          child: ListView(
            key: const ValueKey('search-results-scroll'),
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            padding: BetaContentInsets.musicPaddingOf(
              context,
              EdgeInsets.fromLTRB(18, 14, 18, 96),
            ),
            children: [
              if (showTracks && state.errorMessage != null)
                _MessageCard(
                  icon: Icons.cloud_off_rounded,
                  message: state.errorMessage!,
                  actionLabel: '重试',
                  onAction: ref
                      .read(musicSearchControllerProvider.notifier)
                      .retry,
                ),
              if (showTracks)
                for (final warning in state.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MessageCard(
                      icon: Icons.info_outline_rounded,
                      message: warning,
                    ),
                  ),
              if (showUsers && hasUserResults) ...[
                _SectionTitle(title: '用户', count: allUsers.length, unit: '位'),
                const SizedBox(height: 8),
                _UserResults(users: allUsers, query: state.query),
              ] else if (showUsers && userResults.isLoading) ...[
                const _SearchingUsersCard(),
              ],
              if (showTracks && state.localTracks.isNotEmpty) ...[
                _SectionTitle(title: '本地音乐', count: state.localTracks.length),
                const SizedBox(height: 8),
                _TrackResults(tracks: state.localTracks),
                const SizedBox(height: 22),
              ],
              if (showTracks && state.onlineTracks.isNotEmpty) ...[
                _SectionTitle(
                  title: '在线音乐',
                  count: state.onlineTracks.length,
                  suffix: state.fromCache
                      ? '已从缓存加载'
                      : DistributionChannel.isBeta
                      ? (state.total == null ? '酷狗概念版' : '共 ${state.total} 首')
                      : '酷狗优先 · 网易云补充',
                ),
                const SizedBox(height: 8),
                _TrackResults(tracks: state.onlineTracks),
                if (DistributionChannel.isBeta)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: state.isLoadingMore
                        ? const MestingLoadingIndicator(
                            semanticLabel: '正在加载更多歌曲',
                          )
                        : state.moreError != null
                        ? _MessageCard(
                            icon: Icons.refresh_rounded,
                            message: state.moreError!,
                            actionLabel: '重试加载',
                            onAction: ref
                                .read(musicSearchControllerProvider.notifier)
                                .loadMore,
                          )
                        : state.hasMore
                        ? TextButton.icon(
                            key: const ValueKey('platform-search-more'),
                            onPressed: ref
                                .read(musicSearchControllerProvider.notifier)
                                .loadMore,
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('继续加载歌曲'),
                          )
                        : const Center(child: Text('已显示全部搜索结果')),
                  ),
              ],
              if (_category == _SearchResultCategory.tracks &&
                  !state.hasResults &&
                  state.errorMessage == null)
                _MessageCard(
                  icon: Icons.music_off_outlined,
                  message: '没有找到“${state.query}”相关单曲',
                ),
              if (_category == _SearchResultCategory.users &&
                  !hasUserResults &&
                  !userResults.isLoading)
                _MessageCard(
                  icon: Icons.person_search_outlined,
                  message: '没有找到“${state.query}”相关用户',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A compact, grouped search preview inspired by the familiar NetEase search
/// layout.  It keeps the existing tabbed result lists below it, but makes the
/// first viewport useful immediately: artist/song highlights are followed by
/// query suggestions with the matching text in the heart-red accent.
class _NeteaseSearchOverview extends ConsumerWidget {
  const _NeteaseSearchOverview({
    required this.query,
    required this.users,
    required this.tracks,
    this.onSearch,
  });

  final String query;
  final List<SocialUser> users;
  final List<Track> tracks;
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? MestingPalette.heartBright : MestingPalette.heart;
    final favorites = ref.watch(favoriteTrackIdsProvider);
    final uniqueTracks = <String, Track>{};
    for (final track in tracks) {
      uniqueTracks.putIfAbsent(track.id, () => track);
    }
    final previewTracks = uniqueTracks.values.take(3).toList(growable: false);
    final suggestions = _searchSuggestionValues(
      query: query,
      users: users,
      tracks: uniqueTracks.values,
    );

    return Column(
      key: const ValueKey('netease-search-overview'),
      children: [
        if (users.isNotEmpty)
          _NeteaseArtistResult(user: users.first, query: query),
        for (final track in previewTracks)
          _NeteaseTrackResult(
            track: track,
            query: query,
            favorite: favorites.contains(track.id),
            accent: accent,
          ),
        for (final suggestion in suggestions)
          _NeteaseSuggestionRow(
            key: ValueKey('netease-search-suggestion-$suggestion'),
            query: query,
            value: suggestion,
            accent: accent,
            favorite: uniqueTracks.values.any(
              (track) =>
                  favorites.contains(track.id) &&
                  suggestion.contains(track.title),
            ),
            onTap: onSearch == null ? null : () => onSearch!(suggestion),
          ),
      ],
    );
  }
}

class _NeteaseArtistResult extends StatelessWidget {
  const _NeteaseArtistResult({required this.user, required this.query});

  final SocialUser user;
  final String query;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? MestingPalette.heartBright : MestingPalette.heart;
    return Semantics(
      button: true,
      label: '歌手 ${user.displayName}',
      child: InkWell(
        key: const ValueKey('netease-search-artist-result'),
        onTap: () =>
            context.push('/social/users/${Uri.encodeComponent(user.uid)}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
          child: Row(
            children: [
              SocialAvatar(user: user, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedSearchText(
                      value: user.displayName,
                      query: query,
                      baseStyle: TextStyle(
                        color: accent,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                      highlightStyle: TextStyle(
                        color: accent,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '艺人 · ${_compactCount(user.followerCount)}粉丝',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.verified_rounded, color: accent, size: 23),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeteaseTrackResult extends ConsumerWidget {
  const _NeteaseTrackResult({
    required this.track,
    required this.query,
    required this.favorite,
    required this.accent,
  });

  final Track track;
  final String query;
  final bool favorite;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = favorite ? accent : tokens.textPrimary;
    return InkWell(
      key: ValueKey('netease-search-track-${track.id}'),
      onTap: track.isPlayable
          ? () async {
              try {
                await ref
                    .read(audioHandlerProvider)
                    .playSingleTrack(track, playbackContext: [track]);
              } catch (error) {
                if (context.mounted) showPlatformFailure(context, error);
              }
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 8, 8, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: TrackArtwork(track: track, width: 52, height: 52),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightedSearchText(
                    value: track.title,
                    query: query,
                    baseStyle: TextStyle(
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                    highlightStyle: TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (favorite) ...[
                        Icon(Icons.favorite_rounded, color: accent, size: 14),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          '${track.artist} · ${track.provider} · ${formatDuration(track.duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: favorite ? accent : tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (ref.watch(showPlatformFeaturesProvider) &&
                track.source == TrackSource.kugou)
              IconButton(
                tooltip: '酷狗歌曲评论',
                icon: const Icon(Icons.comment_outlined),
                onPressed: () => openPlatformSongComments(context, ref, track),
              ),
            if (!track.isPlayable)
              Icon(Icons.lock_outline_rounded, color: tokens.textMuted)
            else
              IconButton(
                key: ValueKey('netease-search-queue-${track.id}'),
                tooltip: '添加至播放列表',
                onPressed: () async {
                  final added = await ref
                      .read(audioHandlerProvider)
                      .appendToUpcomingQueue(track);
                  if (!context.mounted) return;
                  showMusicNotice(
                    context,
                    icon: added
                        ? Icons.check_rounded
                        : Icons.queue_music_rounded,
                    title: added ? '已添加至播放列表' : '已在播放列表',
                    message: '',
                  );
                },
                color: dark ? tokens.textSecondary : tokens.textPrimary,
                icon: const Icon(Icons.playlist_add_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _NeteaseSuggestionRow extends StatelessWidget {
  const _NeteaseSuggestionRow({
    required this.query,
    required this.value,
    required this.accent,
    this.favorite = false,
    this.onTap,
    super.key,
  });

  final String query;
  final String value;
  final Color accent;
  final bool favorite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Column(
      children: [
        Divider(height: 1, indent: 13, endIndent: 13, color: tokens.border),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: tokens.textMuted, size: 20),
                const SizedBox(width: 11),
                Expanded(
                  child: _HighlightedSearchText(
                    value: value,
                    query: query,
                    baseStyle: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    highlightStyle: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (favorite) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.favorite_rounded, color: accent, size: 14),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HighlightedSearchText extends StatelessWidget {
  const _HighlightedSearchText({
    required this.value,
    required this.query,
    required this.baseStyle,
    required this.highlightStyle,
  });

  final String value;
  final String query;
  final TextStyle baseStyle;
  final TextStyle highlightStyle;

  @override
  Widget build(BuildContext context) {
    final spans = _highlightSearchSpans(
      value: value,
      query: query,
      baseStyle: baseStyle,
      highlightStyle: highlightStyle,
    );
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}

List<TextSpan> _highlightSearchSpans({
  required String value,
  required String query,
  required TextStyle baseStyle,
  required TextStyle highlightStyle,
}) {
  final normalizedQuery = query.trim();
  if (normalizedQuery.isEmpty) {
    return [TextSpan(text: value, style: baseStyle)];
  }
  final lowerValue = value.toLowerCase();
  final lowerQuery = normalizedQuery.toLowerCase();
  final spans = <TextSpan>[];
  var cursor = 0;
  while (cursor < value.length) {
    final hit = lowerValue.indexOf(lowerQuery, cursor);
    if (hit < 0) {
      spans.add(TextSpan(text: value.substring(cursor), style: baseStyle));
      break;
    }
    if (hit > cursor) {
      spans.add(TextSpan(text: value.substring(cursor, hit), style: baseStyle));
    }
    final end = hit + normalizedQuery.length;
    spans.add(TextSpan(text: value.substring(hit, end), style: highlightStyle));
    cursor = end;
  }
  return spans.isEmpty ? [TextSpan(text: value, style: baseStyle)] : spans;
}

List<String> _searchSuggestionValues({
  required String query,
  required Iterable<SocialUser> users,
  required Iterable<Track> tracks,
}) {
  final normalized = query.trim();
  if (normalized.isEmpty) return const [];
  final values = <String>[];

  void add(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty ||
        values.contains(candidate) ||
        values.length >= 10) {
      return;
    }
    values.add(candidate);
  }

  // The exact query stays first, just like the native search suggestions.
  add(normalized);
  for (final user in users) {
    add(user.displayName);
    add('$normalized ${user.displayName}');
  }
  for (final track in tracks) {
    add(track.artist);
    add(track.title);
    add('$normalized ${track.title}');
    add('$normalized ${track.artist}');
  }
  return List<String>.unmodifiable(values);
}

String _compactCount(int value) {
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(value % 100000000 == 0 ? 0 : 1)}亿';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(value % 10000 == 0 ? 0 : 1)}万';
  }
  return '$value';
}

class _SearchResultTabs extends StatelessWidget {
  const _SearchResultTabs({required this.selected, required this.onSelected});

  final _SearchResultCategory selected;
  final ValueChanged<_SearchResultCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.brightness == Brightness.dark
        ? MestingPalette.heartBright
        : MestingPalette.heart;
    final tokens = context.musicThemeTokens;
    return Container(
      key: const ValueKey('search-result-tabs'),
      height: 50,
      margin: const EdgeInsets.only(top: 7),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: .18)),
        ),
      ),
      child: Row(
        children: [
          for (final category in _SearchResultCategory.values)
            Expanded(
              child: Semantics(
                selected: selected == category,
                button: true,
                label: '${category.label}搜索结果',
                child: InkWell(
                  key: ValueKey('search-result-tab-${category.name}'),
                  onTap: () => onSelected(category),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        category.label,
                        style: TextStyle(
                          color: selected == category
                              ? accent
                              : tokens.textSecondary,
                          fontSize: 14,
                          fontWeight: selected == category
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                      if (selected == category)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            key: ValueKey(
                              'search-result-tab-indicator-${category.name}',
                            ),
                            width: 24,
                            height: 3,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchingUsersCard extends StatelessWidget {
  const _SearchingUsersCard();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: MestingLoadingIndicator(
        key: ValueKey('search-users-loading-animation'),
        size: 48,
        semanticLabel: '正在搜索用户',
      ),
    ),
  );
}

class _UserResults extends StatelessWidget {
  const _UserResults({required this.users, required this.query});

  final List<SocialUser> users;
  final String query;

  @override
  Widget build(BuildContext context) {
    return _SearchGlass(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: users.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, indent: 76),
        itemBuilder: (context, index) =>
            _SearchUserRow(user: users[index], query: query),
      ),
    );
  }
}

class _SearchUserRow extends ConsumerStatefulWidget {
  const _SearchUserRow({required this.user, required this.query});

  final SocialUser user;
  final String query;

  @override
  ConsumerState<_SearchUserRow> createState() => _SearchUserRowState();
}

class _SearchUserRowState extends ConsumerState<_SearchUserRow> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return ListTile(
      onTap: () =>
          context.push('/social/users/${Uri.encodeComponent(user.uid)}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      leading: SocialAvatar(user: user, size: 52),
      title: Text(
        user.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        user.bio.trim().isEmpty ? '${user.followerCount} 粉丝' : user.bio,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        height: 36,
        child: user.isFollowing
            ? OutlinedButton(
                onPressed: _working ? null : () => _toggle(user),
                child: Text(user.isFriend ? '互相关注' : '已关注'),
              )
            : FilledButton.tonalIcon(
                onPressed: _working ? null : () => _toggle(user),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('关注'),
              ),
      ),
    );
  }

  Future<void> _toggle(SocialUser user) async {
    setState(() => _working = true);
    try {
      await ref
          .read(socialRepositoryProvider)
          .setFollowing(user.uid, following: !user.isFollowing);
      ref.invalidate(socialUserSearchProvider(widget.query));
      ref.invalidate(socialUserProvider(user.uid));
      ref.invalidate(socialConnectionsProvider);
      ref.invalidate(socialSummaryProvider);
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: user.isFollowing ? '已取消关注' : '已关注',
          message: !user.isFollowing && user.followsMe ? '你们现在可以聊天了' : '',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '关注失败',
          message: userFacingErrorMessage(error, fallback: '关注操作失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _TrackResults extends ConsumerWidget {
  const _TrackResults({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(currentMediaItemProvider).value?.id;
    final favoriteAccent = Theme.of(context).brightness == Brightness.dark
        ? MestingPalette.heartBright
        : MestingPalette.heart;
    return _SearchGlass(
      child: ListView.separated(
        key: const ValueKey('search-track-list'),
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tracks.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, indent: 70),
        itemBuilder: (context, index) {
          final track = tracks[index];
          final active = currentId == track.id;
          return ListTile(
            onTap: () async {
              if (!track.isPlayable) {
                showMusicNotice(
                  context,
                  icon: Icons.error_outline_rounded,
                  title: track.availabilityMessage.isEmpty
                      ? '这首歌当前不可播放'
                      : track.availabilityMessage,
                  message: '',
                );
                return;
              }
              // Search results remain outside the explicit upcoming queue,
              // but provide an invisible ordered context for previous/next.
              try {
                await ref
                    .read(audioHandlerProvider)
                    .playSingleTrack(track, playbackContext: tracks);
              } catch (error) {
                if (context.mounted) showPlatformFailure(context, error);
              }
            },
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: TrackArtwork(track: track, width: 52, height: 52),
            ),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: active ? favoriteAccent : null,
              ),
            ),
            subtitle: Text(
              track.isPlayable
                  ? '${track.artist} · ${track.provider}${track.isPreview ? '试听' : ''} · ${formatDuration(track.duration)}'
                  : '${track.artist} · ${track.provider} · 版权/会员限制',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: track.isPlayable ? null : TextStyle(color: favoriteAccent),
            ),
            trailing: track.isPlayable
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FavoriteToggleButton(track: track, compact: true),
                      if (ref.watch(showPlatformFeaturesProvider) &&
                          track.source == TrackSource.kugou)
                        IconButton(
                          tooltip: '酷狗歌曲评论',
                          icon: const Icon(Icons.comment_outlined, size: 19),
                          onPressed: () =>
                              openPlatformSongComments(context, ref, track),
                        ),
                      _SearchQueueButton(
                        onTap: () async {
                          try {
                            final added = await ref
                                .read(audioHandlerProvider)
                                .appendToUpcomingQueue(track);
                            if (!context.mounted) return;
                            showMusicNotice(
                              context,
                              icon: added
                                  ? Icons.check_rounded
                                  : Icons.queue_music_rounded,
                              title: added ? '已添加' : '已在播放列表',
                              message: '',
                            );
                          } on Object {
                            if (!context.mounted) return;
                            showMusicNotice(
                              context,
                              icon: Icons.error_outline_rounded,
                              title: '添加失败',
                              message: '暂时无法加入《${track.title}》，请稍后重试',
                            );
                          }
                        },
                      ),
                    ],
                  )
                : const Tooltip(
                    message: '当前不可播放',
                    child: Icon(Icons.lock_outline_rounded),
                  ),
          );
        },
      ),
    );
  }
}

class _SearchQueueButton extends StatelessWidget {
  const _SearchQueueButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: '加入播放列表',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text(
              '+',
              style: TextStyle(
                color: accent,
                fontSize: 27,
                height: 1,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.count,
    this.suffix,
    this.unit = '首',
  });

  final String title;
  final int count;
  final String? suffix;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          suffix == null ? '$count $unit' : '$count $unit · $suffix',
          style: TextStyle(color: tokens.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return _SearchGlass(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
        child: Column(
          children: [
            Icon(icon, size: 38, color: tokens.textMuted),
            const SizedBox(height: 9),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchGlass extends StatelessWidget {
  const _SearchGlass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.glass,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tokens.border),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: dark ? .04 : .18),
                Colors.transparent,
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
