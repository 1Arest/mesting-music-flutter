import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../core/audio/playback_providers.dart';
import '../../core/platform/distribution_channel.dart';
import '../../features/search/search_providers.dart';
import '../../features/experience/presentation/beta_bottom_bar.dart';
import '../../features/experience/presentation/floating_playback_pill.dart';
import 'beta_bottom_search.dart';
import 'beta_swipe_pages.dart';
import 'beta_text_editing.dart';
import 'beta_glass_action.dart';
import 'beta_content_insets.dart';
import 'beta_tab_navigation.dart';
import 'keyboard_visibility_builder.dart';

/// Root-Navigator music pages have no persistent shell ancestor. Compose the
/// very same glass navigation and playback accessory over their painted content,
/// instead of the former search-only bar with an opaque reserved bottom box.
/// Audio ownership remains in the existing application providers.
class BetaSecondaryMusicLayout extends ConsumerStatefulWidget {
  const BetaSecondaryMusicLayout({required this.child, this.search, super.key});
  final Widget child;
  final BetaPageSearchController? search;

  static Widget wrap(
    BuildContext context,
    Widget child, {
    bool enabled = true,
  }) =>
      enabled &&
          DistributionChannel.isBeta &&
          BetaBottomSearchScope.maybeOf(context) == null
      ? BetaSecondaryMusicLayout(child: child)
      : child;

  @override
  ConsumerState<BetaSecondaryMusicLayout> createState() =>
      _SecondaryLayoutState();
}

class _SecondaryLayoutState extends ConsumerState<BetaSecondaryMusicLayout> {
  late final _host = BetaBottomSearchHost(
    location: '/secondary',
    openMusicSearch: () {},
  );
  late final _emptySearch = BetaPageSearchController(
    hintText: '搜索歌曲、歌手',
    onSubmitted: (text) {
      // A page without a local filter delegates discovery to the app router.
      ref.read(musicSearchControllerProvider.notifier).submit(text);
      _navigate('/music/search');
    },
    onCleared: () {},
  );
  bool _compact = false, _scheduled = false;
  @override
  void initState() {
    super.initState();
    _host.addListener(_changed);
  }

  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _navigate(String destination) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final navigation = ref.read(betaTabNavigationProvider);
    // Dismiss imperative pages above the declarative root before choosing a tab.
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
    final index = betaMusicRoutes.indexOf(destination);
    if (index >= 0) navigation.returnToRoot(index);
    router.go(destination);
  }

  bool _scroll(ScrollNotification scroll, {bool activePage = false}) {
    if (scroll.metrics.axis != Axis.vertical ||
        (!activePage && scroll.depth != 0)) {
      return false;
    }
    final next = scroll.metrics.pixels > (_compact ? 24 : 88);
    if (next != _compact) {
      _compact = next;
      _changed();
    }
    return false;
  }

  @override
  void dispose() {
    _host.removeListener(_changed);
    _host.dispose();
    _emptySearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = widget.search ?? _host.current ?? _emptySearch;
    return BetaBottomSearchScope(
      host: _host,
      child: ListenableBuilder(
        listenable: search,
        builder: (context, _) => KeyboardVisibilityBuilder(
          builder: (context, keyboard) {
            final hasTrack =
                ref.watch(currentMediaItemProvider).asData?.value != null;
            return LayoutBuilder(
              builder: (context, constraints) {
                final inset =
                    View.of(context).viewInsets.bottom /
                    View.of(context).devicePixelRatio;
                final consumed =
                    (MediaQuery.sizeOf(context).height - constraints.maxHeight)
                        .clamp(0.0, inset);
                final lift = (inset - consumed).clamp(0.0, inset);
                return Stack(
                  children: [
                    Positioned.fill(
                      child:
                          NotificationListener<
                            BetaActivePageScrollNotification
                          >(
                            onNotification: (event) {
                              _scroll(event.scroll, activePage: true);
                              return true;
                            },
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _scroll,
                              child: BetaContentInsets(
                                bottom: BetaContentInsets.musicChromeBottomOf(
                                  context,
                                ),
                                child: widget.child,
                              ),
                            ),
                          ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: lift,
                      child: Material(
                        type: MaterialType.transparency,
                        child: BetaMusicBottomBar(
                          selectedIndex: 1,
                          isSearchActive: search.active || _compact,
                          inline: _compact && !search.active,
                          accessory: hasTrack
                              ? FloatingPlaybackPill(
                                  compact: _compact && !search.active,
                                )
                              : null,
                          accessoryEnabled: !keyboard,
                          onTabSelected: (index) =>
                              _navigate(betaMusicRoutes[index]),
                          searchConfig: GlassSearchBarConfig(
                            controller: search.text,
                            focusNode: search.focus,
                            hintText: search.hintText,
                            autoFocusOnExpand: false,
                            showsCancelButton: true,
                            expandWhenActive: !_compact || search.active,
                            contextMenuBuilder: buildBetaEditingMenu,
                            selectionControls: betaTextSelectionControls,
                            cursorColor: betaEditingBlue(context),
                            onSearchToggle: (active) {
                              search.setActive(active);
                              if (!active) search.clearResults();
                            },
                            onChanged: search.changed,
                            onSubmitted: search.submit,
                            trailingBuilder: (_) => BetaGlassAction(
                              key: const ValueKey('search-submit-action'),
                              label: '搜索',
                              compact: true,
                              icon: Icons.arrow_upward_rounded,
                              blue: true,
                              onPressed: () => search.submit(search.text.text),
                            ),
                            cancelButtonSemanticLabel: '关闭搜索',
                            clearButtonSemanticLabel: '清空搜索',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
