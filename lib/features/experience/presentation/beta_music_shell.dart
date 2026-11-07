import '../../music_platform/qishui/qishui_providers.dart';
import '../../music_platform/qishui/qishui_pages.dart';
import '../../music_platform/qishui/qishui_chrome_policy.dart';
import '../../music_platform/qishui/qishui_appearance.dart';
import '../../music_platform/qishui/qishui_player_navigation.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../../shared/widgets/beta_edge_back.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import '../../../shared/widgets/beta_glass_action.dart';
import '../../../shared/widgets/beta_bottom_search.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/beta_entrance_readiness.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_tab_navigation.dart';
import '../../../shared/widgets/beta_scroll_chrome.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/performance/frame_timing_probe.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/layout/adaptive_layout.dart';
import '../../player/presentation/music_navigation.dart';
import '../../search/presentation/music_search_page.dart';
import '../../search/search_providers.dart';
import '../../themes/music_theme_background.dart';
import 'beta_bottom_bar.dart';
import 'floating_playback_pill.dart';
import 'player_chrome_reveal.dart';
import 'beta_search_back_history.dart';
import '../../music_platform/platform_rewards_provider.dart';

/// The official Apple Music GlassScaffold/searchable-tab/accessory composition
/// is the shell, not an overlay of independently positioned imitation pills.
/// Product navigation/search/audio stay behind their existing contracts.
class BetaMusicShell extends ConsumerStatefulWidget {
  const BetaMusicShell({
    required this.child,
    required this.location,
    this.navigationOwner,
    this.chromeVisible = true,
    super.key,
  });
  final Widget child;
  final String location;
  final int? navigationOwner;
  final bool chromeVisible;
  @override
  ConsumerState<BetaMusicShell> createState() => _BetaMusicShellState();
}

class _BetaMusicShellState extends ConsumerState<BetaMusicShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _searchMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 240),
  );
  final _resultsKey = GlobalKey<MusicSearchResultsBodyState>();
  final _searchText = TextEditingController();
  final _focus = FocusNode();
  final _chrome = BetaMusicChromeController();
  final _positions = <String, ScrollPosition>{};
  final _compact = BetaScrollChrome();
  bool get _mini => _compact.value;
  set _mini(bool value) {
    _pendingCompact = null;
    _compact.show(value);
  }

  bool _compactScheduled = false;
  bool? _pendingCompact;
  bool _searching = false;
  bool _searchFocused = false;
  bool _hasOpenedSearch = false;
  final _backHistory = BetaSearchBackHistory();
  final _pageBackHistory = BetaPageBackHistory();
  bool _historyScheduled = false;
  bool _searchBeforeOverlay = false;
  late final _pageSearchHost = BetaBottomSearchHost(
    location: widget.location,
    openMusicSearch: () => _search(true),
  );
  bool _pageSearchScheduled = false;
  bool _closingSearchRoute = false;
  bool get _routedSearch => Uri.parse(widget.location).path == '/music/search';
  // A music overlay can outlive a covered Navigator route. Until that overlay
  // closes it retains its own input, even if a page registration becomes current.
  BetaPageSearchController? get _pageSearch =>
      _searching || _routedSearch ? null : _pageSearchHost.current;
  bool get _anySearch => _searching || (_pageSearch?.active ?? false);
  late int _selected = musicBottomNavigationIndexForLocation(widget.location);
  late final BetaTabNavigation _tabNavigation;

  @override
  void initState() {
    super.initState();
    // Retain the coordinator itself: WidgetRef is unsafe during unmount.
    _tabNavigation = ref.read(betaTabNavigationProvider);
    _searchMotion.addStatusListener(_searchStatus);
    _pageSearchHost.addListener(_pageSearchChanged);
    if (_routedSearch) {
      _searching = _hasOpenedSearch = true;
      _searchMotion.value = 1;
    }
    _scheduleBackHistory();
  }

  void _pageSearchChanged() {
    // Binding/unbinding is a child lifecycle event. Coalesce changes until
    // after build/layout so a page never dirties its building shell ancestor.
    if (!mounted || _pageSearchScheduled) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      _scheduleBackHistory();
      return;
    }
    _pageSearchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageSearchScheduled = false;
      if (!mounted) return;
      setState(() {});
      _scheduleBackHistory();
    });
  }

  // Only mount/hide source pages at transition boundaries. Per-frame motion
  // belongs to SlideTransition; it must not rebuild the whole search/page tree.
  void _searchStatus(AnimationStatus status) {
    if (mounted &&
        (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed)) {
      setState(() {});
    }
  }

  static int? _rootTab(String location) => switch (location) {
    '/music/recommend' => 0,
    '/music' => 1,
    '/music/library' => 2,
    '/profile' => 3,
    _ => null,
  };

  void _backSearch() {
    final page = _pageSearch;
    if (page?.active == true) {
      page!.hasResults ? page.clearResults() : page.setActive(false);
      return;
    }
    final search = ref.read(musicSearchControllerProvider);
    if (search.query.isNotEmpty) {
      void clear() {
        if (!mounted) return;
        _searchText.clear();
        _focus.unfocus();
        ref.read(musicSearchControllerProvider.notifier).setQuery('');
        _scheduleBackHistory();
      }

      final results = _resultsKey.currentState;
      results == null ? clear() : results.returnToLanding(clear);
    } else {
      _search(false);
    }
  }

  @override
  void dispose() {
    _tabNavigation.cancel();
    _backHistory.clear();
    _pageBackHistory.clear();
    _pageSearchHost.removeListener(_pageSearchChanged);
    _pageSearchHost.dispose();
    _compact.dispose();
    _searchMotion.dispose();
    _searchText.dispose();
    _focus.dispose();
    _chrome.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BetaMusicShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != oldWidget.location) {
      if (_rootTab(widget.location) == null) {
        _tabNavigation.cancel();
      } else {
        _tabNavigation.settled(_rootTab(widget.location)!);
      }
      _closingSearchRoute = false;
      _pageSearchHost.current?.focus.unfocus();
      _pageSearchHost.location = widget.location;
      FrameTimingProbe.markTransition('page_change');
      if (widget.location == '/player') {
        // Reset synchronously before the bar's next paint. A post-frame reset
        // left the previously revealed capsule visible over the entering page.
        ref.read(playerChromeRevealProvider).value = 0;
      }
      // Detail paths describe content, not the tab that opened it. Only an
      // explicit root destination changes ownership of the persistent bar.
      _selected = _rootTab(widget.location) ?? _selected;
      // Overlay routes retain the mounted glass bar and its current geometry.
      // Re-entering a tab must not replay a fresh accessory entrance.
      if (_rootTab(widget.location) != null &&
          _rootTab(oldWidget.location) != null) {
        _mini = false;
      }
      if ((oldWidget.chromeVisible && !widget.chromeVisible) ||
          (_rootTab(oldWidget.location) != null &&
              _rootTab(widget.location) == null)) {
        _searchBeforeOverlay = _searchBeforeOverlay || _searching;
        _searching = false;
      } else if ((!oldWidget.chromeVisible &&
              widget.chromeVisible &&
              _rootTab(widget.location) != null) ||
          (_rootTab(widget.location) != null && _searchBeforeOverlay)) {
        _searching = _searchBeforeOverlay;
        _searchBeforeOverlay = false;
      } else {
        _searching = false;
      }
      // Keep legacy/deep-link routes on the exact same search surface and
      // glass field as the bottom button; the old top field stays unmounted.
      if (_routedSearch) _searching = _hasOpenedSearch = true;
      _focus.unfocus();
      _searching ? _searchMotion.forward() : _searchMotion.reverse();
      _scheduleBackHistory();
    }
  }

  bool _openingQishuiSearch = false;
  void _search(bool active) {
    if (active && ref.read(qishuiNavigationProvider)) {
      if (_openingQishuiSearch) return;
      _openingQishuiSearch = true;
      Navigator.of(context)
          .push(betaContentRoute<void>(const QishuiSearchPage()))
          .whenComplete(() => _openingQishuiSearch = false);
      return;
    }
    final page = _pageSearch;
    if (page != null && !_routedSearch) {
      _mini = false;
      page.setActive(active);
      return;
    }
    if (!active && _routedSearch) {
      if (_closingSearchRoute) return;
      _closingSearchRoute = true;
      _searchBeforeOverlay = false;
      _focus.unfocus();
      // Local history can call onClose while Navigator is inside didPop.
      // Remove the synthetic entries, then leave the real route after that
      // transaction. canPop now describes actual navigation, not search's own
      // local history; rapid close gestures cannot pop a second destination.
      _backHistory.clear();
      _pageBackHistory.clear();
      final location = widget.location;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.location != location) return;
        final parent = betaMusicBackDestination(
          location,
          tabRoot: betaMusicRoutes[widget.navigationOwner ?? _selected],
        );
        context.canPop()
            ? context.pop()
            : context.go(parent ?? betaMusicRoutes[_selected]);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return;
    }
    setState(() {
      _searching = active;
      // A compact scrolling accessory must leave its inline slot before the
      // real input expands into that same horizontal space.
      _mini = false;
      if (active) _hasOpenedSearch = true;
    });
    _searching ? _searchMotion.forward() : _searchMotion.reverse();
    if (!active) _focus.unfocus();
    _scheduleBackHistory();
  }

  void _searchFocusChanged(bool focused) {
    if (!mounted || _searchFocused == focused) return;
    // Focus changes may be published while a persistent field is being
    // rebound to another page. Apply chrome visibility outside that build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchFocused != focused) {
        setState(() => _searchFocused = focused);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleBackHistory() {
    if (_historyScheduled) return;
    _historyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyScheduled = false;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      final destination = betaMusicBackDestination(
        widget.location,
        tabRoot: betaMusicRoutes[widget.navigationOwner ?? _selected],
      );
      _pageBackHistory.synchronize(
        route: route,
        enabled: destination != null && !_closingSearchRoute,
        onBack: () {
          if (mounted && destination != null) context.go(destination);
        },
      );
      _backHistory.synchronize(
        route: route,
        visible: _anySearch && !_routedSearch && !_closingSearchRoute,
        hasResults: _pageSearch?.active == true
            ? _pageSearch!.hasResults
            : ref.read(musicSearchControllerProvider).query.isNotEmpty,
        onClose: () => _search(false),
        onClear: _backSearch,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Destination navigation ends a search; overlays only suspend its view.
  /// Clearing the query cancels all five category generations but keeps history.
  void _endSearch() {
    _pageSearchHost.current?.setActive(false);
    _searchText.clear();
    ref.read(musicSearchControllerProvider.notifier).setQuery('');
    _searchBeforeOverlay = false;
    _pendingCompact = null;
    _search(false);
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    _searchText.text = text;
    ref.read(musicSearchControllerProvider.notifier).submit(text);
    _focus.unfocus();
  }

  bool _scroll(ScrollNotification notification, {bool activePage = false}) {
    if (!widget.chromeVisible ||
        _anySearch ||
        (!activePage && notification.depth != 0) ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final position = Scrollable.maybeOf(notification.context!)?.position;
    if (position != null) _positions[widget.location] = position;
    // Hysteresis avoids toggling two costly glass geometries at one pixel
    // boundary during overscroll, slow drags and inertial settling.
    final requested = _pendingCompact ?? _compact.requestedCompact;
    final mini = requested
        ? notification.metrics.pixels > 24
        : notification.metrics.pixels > 88;
    if (mini != requested) {
      _pendingCompact = mini;
      if (!_compactScheduled) {
        _compactScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _compactScheduled = false;
          if (!mounted) return;
          final value = _pendingCompact;
          _pendingCompact = null;
          if (value != null && !_searching && widget.chromeVisible) {
            FrameTimingProbe.markTransition(
              value ? 'capsule_compact' : 'capsule_expanded',
            );
            _compact.request(value);
          }
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final artworkCandidate = qishuiLyricsAppearanceActive(
      musicRootVisible: qishuiMusicRootHidesMiniPlayer(
        qishui: ref.watch(qishuiNavigationProvider),
        location: widget.location,
        hasSecondaryPage: _tabNavigation.hasSecondaryPages(1),
      ),
      lyricsVisible: ref.watch(qishuiMusicLyricsProvider),
      qishuiTrack: true,
      searching: _anySearch,
      chromeVisible: widget.chromeVisible,
    );
    // A closed/offscreen lyrics view must not initialize playback providers on
    // account forms, other platforms or pages with no active media session.
    final artwork =
        artworkCandidate &&
        ref.watch(currentTrackProvider).source == TrackSource.qishui;
    return QishuiArtworkAppearance(
      active: artwork,
      child: Consumer(builder: (context, ref, _) => _buildShell(context, ref)),
    );
  }

  Widget _buildShell(BuildContext context, WidgetRef ref) {
    ref.watch(platformRewardAutomationProvider);
    final playerRoute = Uri.parse(widget.location).path == '/player';
    ref.listen(
      musicSearchControllerProvider.select((state) => state.query.isNotEmpty),
      (_, value) => _scheduleBackHistory(),
    );
    final selected = widget.navigationOwner ?? _selected;
    final pageSearch = _pageSearch;
    final searching = _anySearch;
    final hasTrack = ref.watch(
      currentMediaItemProvider.select((s) => s.value != null),
    );
    final hideQishuiAccessory = qishuiMusicRootHidesMiniPlayer(
      qishui: ref.watch(qishuiNavigationProvider),
      location: widget.location,
      hasSecondaryPage: _tabNavigation.hasSecondaryPages(1),
    );
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final backDestination = betaMusicBackDestination(
      widget.location,
      tabRoot: betaMusicRoutes[selected],
    );
    final shell = PopScope(
      canPop: !searching && backDestination == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (searching) {
          _backSearch();
        } else if (backDestination != null) {
          // GoRouter tries the nested content stack first. This callback is
          // reached only when that stack has no page left to return to.
          context.go(backDestination);
        }
      },
      child: GlassScaffold(
        key: const ValueKey('beta6-official-glass-shell'),
        background: const MusicThemeBackground(child: SizedBox.expand()),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        settings: betaMusicPillGlass(context),
        edgeFade: false,
        resizeToAvoidBottomInset: false,
        body: Material(
          type: MaterialType.transparency,
          child: NotificationListener<BetaActivePageScrollNotification>(
            onNotification: (event) {
              _scroll(event.scroll, activePage: true);
              return true;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: _scroll,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _searching,
                      child: Offstage(
                        // Keep the source mounted for its scroll state, but
                        // stop painting once the opaque search page has landed.
                        offstage: _searching && _searchMotion.isCompleted,
                        child: ExcludeSemantics(
                          excluding: _searching,
                          child: TickerMode(
                            enabled: !_searching,
                            child: MestingAdaptiveContentFrame(
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_hasOpenedSearch)
                    Positioned.fill(
                      child: ExcludeFocus(
                        excluding: !_searching,
                        child: Offstage(
                          offstage: !_searching && _searchMotion.isDismissed,
                          child: TickerMode(
                            enabled: !_searchMotion.isDismissed,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (_) => !_searching,
                              child: SlideTransition(
                                position: _searchMotion.drive(
                                  Tween<Offset>(
                                    begin: const Offset(1, 0),
                                    end: Offset.zero,
                                  ).chain(
                                    CurveTween(curve: Curves.easeOutCubic),
                                  ),
                                ),
                                child: RepaintBoundary(
                                  child: ColoredBox(
                                    key: const ValueKey(
                                      'beta10-search-surface',
                                    ),
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        bottom: inset,
                                        top: MediaQuery.paddingOf(context).top,
                                      ),
                                      child: BetaEntranceReadiness(
                                        ready: _searchMotion.isCompleted,
                                        child: BetaEdgeBack(
                                          onBack: _backSearch,
                                          child: MusicSearchResultsBody(
                                            key: _resultsKey,
                                            onSearch: _submit,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
        // Both system safe area and the search field's keyboard float belong
        // to the official components. Applying viewInsets again doubles lift.
        // Wide screens use this same single navigation; only content is capped.
        bottomBar: ValueListenableBuilder<double>(
          valueListenable: ref.watch(playerChromeRevealProvider),
          child: RepaintBoundary(
            child: Material(
              // GlassScaffold is Cupertino-based. Supply Mesting's normal text
              // defaults here so labels never inherit WidgetsApp's error style.
              type: MaterialType.transparency,
              child: ValueListenableBuilder<bool>(
                valueListenable: _compact,
                builder: (context, compact, _) => BetaMusicBottomBar(
                  selectedIndex: selected,
                  soda: ref.watch(qishuiNavigationProvider),
                  isSearchActive: compact || searching,
                  inline: compact && !searching,
                  accessory: hasTrack && !hideQishuiAccessory
                      ? FloatingPlaybackPill(compact: compact && !searching)
                      : null,
                  accessoryEnabled: inset == 0 && !_searchFocused,
                  onTabSelected: (index) {
                    appHaptic(context, AppHapticEvent.selection);
                    if (index == selected &&
                        _mini &&
                        !_tabNavigation.hasSecondaryPages(index) &&
                        !searching &&
                        _rootTab(widget.location) != null) {
                      _mini = false;
                      return;
                    }
                    _endSearch();
                    _tabNavigation.request(
                      index: index,
                      currentIndex: _rootTab(widget.location) ?? -1,
                      navigate: (destination) {
                        if (!mounted) return;
                        setState(() => _selected = destination);
                        context.go(betaMusicRoutes[destination]);
                      },
                    );
                  },
                  searchConfig: GlassSearchBarConfig(
                    contextMenuBuilder: buildBetaEditingMenu,
                    selectionControls: betaTextSelectionControls,
                    cursorColor: betaEditingBlue(context),
                    controller: pageSearch?.text ?? _searchText,
                    focusNode: pageSearch?.focus ?? _focus,
                    textInputAction: TextInputAction.search,
                    autoFocusOnExpand: false,
                    onSearchFocusChanged: _searchFocusChanged,
                    showsCancelButton: true,
                    expandWhenActive: !compact || searching,
                    hintText: pageSearch?.hintText ?? '搜索歌曲、歌手',
                    onSearchToggle: (active) {
                      appHaptic(context, AppHapticEvent.selection);
                      _search(active);
                    },

                    onChanged:
                        pageSearch?.changed ??
                        (text) => ref
                            .read(musicSearchControllerProvider.notifier)
                            .setQuery(text),
                    onSubmitted: pageSearch?.submit ?? _submit,
                    trailingBuilder: (context) => BetaGlassAction(
                      label: '搜索',
                      compact: true,
                      icon: Icons.arrow_upward_rounded,
                      blue: true,
                      onPressed: () => pageSearch != null
                          ? pageSearch.submit(pageSearch.text.text)
                          : _submit(_searchText.text),
                    ),
                    cancelButtonSemanticLabel: '关闭搜索',
                    clearButtonSemanticLabel: '清空搜索',
                  ),
                ),
              ),
            ),
          ),
          builder: (context, reveal, child) => BetaMusicChromeGate(
            controller: _chrome,
            playerReveal: ref.read(playerChromeRevealProvider),
            revealHandledByRoute: playerRoute,
            child: IgnorePointer(
              ignoring: !widget.chromeVisible,
              child: AnimatedOpacity(
                // Only the player may reveal chrome while it is dismissing.
                // Its retained value must not expose inert bars on other routes.
                opacity: widget.chromeVisible
                    ? 1
                    : playerRoute
                    ? reveal
                    : 0,
                duration: widget.location == '/player'
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    widget.chromeVisible
                        ? 0
                        : (1 - (playerRoute ? reveal : 0)) * 12,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Embedded search is a shell state, not a child route. Register directly
    // with Router's dispatcher so Android edge/system Back reaches that state
    // before the nested navigator attempts to leave its root page.
    final scopedShell = BetaBottomSearchScope(
      host: _pageSearchHost,
      child: BetaMusicChromeScope(
        controller: _chrome,
        child: ValueListenableBuilder<bool>(
          valueListenable: _compact,
          child: shell,
          builder: (context, compact, child) => BetaContentInsets(
            bottom: !widget.chromeVisible
                ? 0
                : (compact && !_anySearch) || hideQishuiAccessory
                ? BetaContentInsets.compactMusicBottomOf(context)
                : BetaContentInsets.musicChromeBottomOf(context),
            child: child!,
          ),
        ),
      ),
    );
    if (Router.maybeOf(context) == null) return scopedShell;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!_anySearch) return false;
        _backSearch();
        return true;
      },
      child: scopedShell,
    );
  }
}
