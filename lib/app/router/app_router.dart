import '../../features/music_platform/presentation/platform_auth_page.dart';
import '../../features/music_platform/qishui/qishui_pages.dart';
import '../../shared/widgets/beta_page_motion.dart';
import '../../shared/widgets/beta_page_route_observer.dart';
import 'beta_tab_shell.dart';
import '../../features/notifications/notification_pages.dart';
import '../../features/player/presentation/now_playing_route.dart';
import '../../features/experience/presentation/playback_pill_menu.dart';
import '../../features/music_platform/data/platform_category_search.dart';
import '../../features/music_platform/presentation/platform_catalog_detail_page.dart';
import '../../shared/widgets/beta_edge_back.dart';

import 'package:flutter/material.dart';
import '../../shared/widgets/song_list_tools.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/sensitive_screen.dart';
import '../../core/platform/distribution_channel.dart';
import '../../features/legal/domain/legal_documents.dart';
import '../../features/legal/presentation/legal_documents_page.dart';
import '../../features/library/presentation/music_home_page.dart';
import '../../features/history/presentation/listening_history_page.dart';
import '../../features/discover/presentation/curated_playlist_page.dart';
import '../../features/discover/presentation/discover_page.dart';
import '../../features/player/presentation/music_shell.dart';
import '../../features/player/presentation/music_page_transition.dart';
import '../../features/player/presentation/now_playing_page.dart';
import '../../features/player/presentation/now_playing_transition.dart';
import '../../features/playlists/presentation/playlist_detail_page.dart';
import '../../features/queue/presentation/queue_page.dart';
import '../../features/search/presentation/music_search_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/music_platform/presentation/platform_profile_edit_page.dart';
import '../../features/themes/theme_gallery_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/recommendation/presentation/recommendation_page.dart';
import '../../features/experience/presentation/music_library_page.dart';
import '../../features/experience/presentation/listening_replay_page.dart';
import '../../features/local_music/presentation/local_music_page.dart';
import '../../features/kugou_together/together_page.dart';
import '../../features/recognition/song_recognition_page.dart';
import '../../features/audiobooks/audiobooks_page.dart';
import '../../features/music_platform/platform_capabilities.dart';

/// App navigation graph.
///
/// Music routes live inside [MusicShell] so bottom navigation and the mini
/// player survive child-page transitions. Authentication stays outside the
/// shell because it is a sensitive, full-screen flow with its own back stack.
final appRootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  observers: [if (DistributionChannel.isBeta) BetaPageRouteObserver()],
  navigatorKey: appRootNavigatorKey,
  initialLocation: '/music/recommend',
  routes: [
    ..._musicShellRoutes(),
    GoRoute(
      path: '/auth',
      pageBuilder: (context, state) => _ordinaryPage(
        state,
        SensitiveScreen(
          child: PlatformAuthPage(
            redirect:
                state.uri.queryParameters['redirect'] ?? '/music/recommend',
          ),
        ),
      ),
    ),
    GoRoute(path: '/auth/recover', redirect: (_, _) => '/auth'),
  ],
);

// Root tabs have independent retained Navigators; ordinary detail/player
// routes keep their established shell and back behavior. A tab switch changes
// the selected branch immediately; its viewport alone owns interruptible motion.
List<RouteBase> _musicShellRoutes() {
  final routes = <GoRoute>[
    GoRoute(
      path: '/music/recommend',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: const QishuiRootSwitch(
          root: QishuiRoot.discover,
          child: RecommendationPage(),
        ),
      ),
    ),
    GoRoute(
      path: '/music',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: const QishuiRootSwitch(
          root: QishuiRoot.music,
          child: MusicHomePage(),
        ),
      ),
    ),
    GoRoute(
      path: '/music/library',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: QishuiRootSwitch(
          root: QishuiRoot.mine,
          child: MusicLibraryPage(view: state.uri.queryParameters['view']),
        ),
      ),
    ),
    GoRoute(
      path: '/music/local',
      pageBuilder: (context, state) =>
          _musicSlidePage(state: state, child: const LocalMusicPage()),
    ),
    GoRoute(
      path: '/music/audiobooks',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: const PlatformFeatureGate(
          feature: PlatformFeature.audiobooks,
          child: AudiobooksPage(),
        ),
      ),
    ),
    GoRoute(
      path: '/music/together',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: const PlatformFeatureGate(
          feature: PlatformFeature.together,
          child: TogetherPage(),
        ),
      ),
    ),
    GoRoute(
      path: '/music/recognize',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: const PlatformFeatureGate(
          feature: PlatformFeature.recognition,
          child: SongRecognitionPage(),
        ),
      ),
    ),
    GoRoute(
      path: '/music/replay',
      pageBuilder: (context, state) =>
          _musicSlidePage(state: state, child: const ListeningReplayPage()),
    ),
    GoRoute(
      path: '/music/queue',
      pageBuilder: (context, state) =>
          _musicSlidePage(state: state, child: const QueuePage()),
    ),
    GoRoute(
      path: '/music/notifications',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: MusicNotificationInboxPage(platform: state.uri.queryParameters['platform'],
          noticeId: state.uri.queryParameters['notice']),
      ),
    ),
    GoRoute(
      path: '/music/search',
      pageBuilder: (context, state) =>
          _musicSlidePage(state: state, child: const MusicSearchPage()),
    ),
    GoRoute(
      path: '/music/catalog/:kind/:id',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: PlatformCatalogDetailPage(
          hit: state.extra is PlatformSearchHit
              ? state.extra! as PlatformSearchHit
              : PlatformSearchHit(
                  kind: PlatformSearchKind.values.firstWhere(
                    (k) => k.name == state.pathParameters['kind'],
                    orElse: () => PlatformSearchKind.albums,
                  ),
                  id: state.pathParameters['id']!,
                  title: '音乐详情',
                ),
        ),
      ),
    ),
    GoRoute(
      path: '/music/discover',
      redirect: (context, state) =>
          DistributionChannel.isBeta ? '/music' : null,
      pageBuilder: (context, state) =>
          _collectionRevealPage(state: state, child: const DiscoverPage()),
    ),
    GoRoute(
      path: '/music/discover/:playlistId',
      redirect: (context, state) =>
          DistributionChannel.isBeta ? '/music' : null,
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: CuratedPlaylistPage(
          playlistId: state.pathParameters['playlistId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/music/playlists',
      redirect: (context, state) => '/music?view=playlists',
    ),
    GoRoute(
      path: '/music/playlists/:playlistId',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: PlaylistDetailPage(
          playlistId: state.pathParameters['playlistId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/music/themes',
      pageBuilder: (context, state) =>
          _musicSlidePage(state: state, child: const ThemeGalleryPage()),
    ),
    GoRoute(
      path: '/music/settings',
      pageBuilder: (context, state) =>
          _musicSlidePage(state: state, child: const SettingsPage()),
    ),
    GoRoute(
      path: '/legal',
      pageBuilder: (context, state) =>
          _musicSlidePage(state: state, child: const LegalDocumentsPage()),
    ),
    GoRoute(
      path: '/legal/user-agreement',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: const LegalDocumentPage(
          documentType: LegalDocumentType.userAgreement,
        ),
      ),
    ),
    GoRoute(
      path: '/legal/privacy-policy',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: const LegalDocumentPage(
          documentType: LegalDocumentType.privacyPolicy,
        ),
      ),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) => _musicSlidePage(
        state: state,
        child: const QishuiRootSwitch(
          root: QishuiRoot.mine,
          child: ProfilePage(),
        ),
      ),
    ),
    GoRoute(
      path: '/profile/edit',
      pageBuilder: (context, state) => _profileEditTransitionPage(
        state: state,
        child: SensitiveScreen(child: const PlatformProfileEditPage()),
      ),
    ),
    GoRoute(
      path: '/profile/listening',
      pageBuilder: (context, state) =>
          _musicSlidePage(state: state, child: const ListeningHistoryPage()),
    ),
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) => NowPlayingTransitionPage(
        key: state.pageKey,
        child: NowPlayingPage(
          showLyricsInitially: state.extra is PlaybackPillLyricsIntent,
          vinylOrigin: state.extra is NowPlayingTransitionIntent
              ? (state.extra! as NowPlayingTransitionIntent).vinylOrigin
              : null,
        ),
      ),
    ),
  ];
  ShellRoute regular(List<RouteBase> children) => ShellRoute(
    observers: [if (DistributionChannel.isBeta) BetaPageRouteObserver()],
    pageBuilder: (context, state, child) {
      final shell = MusicShell(location: state.uri.toString(), child: child);
      return DistributionChannel.isBeta
          ? BetaRootTransitionPage<void>(key: state.pageKey, child: shell)
          : MaterialPage<void>(key: state.pageKey, child: shell);
    },
    routes: children,
  );
  if (!DistributionChannel.isBeta) return [regular(routes)];
  const roots = ['/music/recommend', '/music', '/music/library', '/profile'];
  return [
    regular([
      ...betaTabShellRoutes([
        for (final path in roots) routes.singleWhere((r) => r.path == path),
      ]),
      ...routes.where((r) => !roots.contains(r.path)),
    ]),
  ];
}

/// Applies the shared directional transition to ordinary music subpages.
///
/// Callers can pass [MusicPageTransitionIntent] in route extras; defaulting to
/// forward motion keeps deep links and system navigation deterministic.
Page<void> _musicSlidePage({
  required GoRouterState state,
  required Widget child,
}) {
  if (DistributionChannel.isBeta) {
    final tabIndex = switch (state.uri.toString()) {
      '/music/recommend' => 0,
      '/music' => 1,
      '/music/library' => 2,
      '/profile' => 3,
      _ => null,
    };
    // The shell owns routed search's visible slide. Its content Navigator is
    // paused while that overlay is open; a second route animation would retain
    // an exiting stateful tab shell and duplicate its key when search closes.
    if (tabIndex != null) {
      // The PageView owns root-to-root motion. A branch root still needs the
      // secondary animation when ANY ordinary Navigator page is above it.
      return BetaRootTransitionPage<void>(
        key: state.pageKey,
        child: SongListTools(
          listId: state.uri.toString(),
          child: BetaEdgeBack(child: child),
        ),
      );
    }
    if (child is MusicSearchPage) {
      return NoTransitionPage<void>(key: state.pageKey, child: child);
    }
    return BetaContentTransitionPage<void>(
      key: state.pageKey,
      name: state.uri.toString(),
      child: SongListTools(
        listId: state.uri.toString(),
        child: child is MusicSearchPage ? child : BetaEdgeBack(child: child),
      ),
    );
  }
  final intent = state.extra is MusicPageTransitionIntent
      ? state.extra! as MusicPageTransitionIntent
      : const MusicPageTransitionIntent.forward();
  if (intent.usesMusicHubPanelTransition) {
    return _MusicHubPanelTransitionPage(
      key: ValueKey(state.uri.toString()),
      child: child,
    );
  }
  final horizontal = intent.horizontalOffset;
  return _SequencedMusicTransitionPage(
    key: ValueKey(state.uri.toString()),
    enterOffset: Offset(horizontal, 0),
    handoffProgress: intent.handoffProgress ?? musicPageHandoffProgress,
    child: child,
  );
}

Page<void> _profileEditTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  if (DistributionChannel.isBeta) return _ordinaryPage(state, child);
  final intent = state.extra is MusicPageTransitionIntent
      ? state.extra! as MusicPageTransitionIntent
      : const MusicPageTransitionIntent.forward();
  final horizontal = intent.direction == MusicPageTransitionDirection.forward
      ? profileEditPageHorizontalOffset
      : -profileEditPageHorizontalOffset;
  return _SequencedMusicTransitionPage(
    key: ValueKey(state.uri.toString()),
    transitionDuration: profileEditPageTransitionDuration,
    reverseTransitionDuration: profileEditPageReverseTransitionDuration,
    enterOffset: Offset(horizontal, 0),
    enterScale: profileEditPageStartScale,
    scaleAlignment: Alignment.centerRight,
    // This stays aligned with the profile page's transition. The two routes
    // trade one opaque layer directly, so backing out never pauses on shell
    // artwork between the editor and the profile.
    handoffProgress: profileEditPageHandoffProgress,
    reverseMotionCurve: profileEditPageReverseMotionCurve,
    child: child,
  );
}

/// Full-page continuation after [MusicHubPanelTransition] has dismissed.
///
/// The drawer is dismissed before this route is pushed. A short, already-
/// visible destination glide preserves that spatial relationship without
/// repeating the drawer's full-width sweep or compositing both surfaces.
class _MusicHubPanelTransitionPage extends Page<void> {
  const _MusicHubPanelTransitionPage({required this.child, super.key});

  final Widget child;
  static const handoffProgress = musicPageHandoffProgress;

  @override
  Route<void> createRoute(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return PageRouteBuilder<void>(
      settings: this,
      allowSnapshotting: musicPageUsesRouteSnapshotting,
      opaque: true,
      transitionDuration: reduceMotion
          ? Duration.zero
          : musicHubDestinationTransitionDuration,
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : musicHubDestinationReverseTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (reduceMotion) return child;
        return MusicHubDestinationLayerHandoff(
          primaryAnimation: animation,
          secondaryAnimation: secondaryAnimation,
          handoffProgress: handoffProgress,
          child: child,
        );
      },
    );
  }
}

/// Fade/scale transition for sensitive avatar and background previews.
///
/// The route deliberately honors Android's reduced-motion setting instead of
/// forcing a zoom animation on users who have disabled system animations.

Page<void> _collectionRevealPage({
  required GoRouterState state,
  required Widget child,
}) {
  if (DistributionChannel.isBeta) return _ordinaryPage(state, child);
  return _SequencedMusicTransitionPage(
    key: ValueKey(state.uri.toString()),
    transitionDuration: collectionRevealDuration,
    reverseTransitionDuration: collectionRevealReverseDuration,
    enterOffset: const Offset(0, collectionRevealVerticalOffset),
    enterScale: collectionRevealStartScale,
    scaleAlignment: Alignment.topRight,
    child: child,
  );
}

/// Full-page flows outside the music list also use the ordinary route
/// contract. Player/search/avatar preview keep their separate entry motions.
Page<void> _ordinaryPage(GoRouterState state, Widget child) =>
    DistributionChannel.isBeta
    ? BetaContentTransitionPage<void>(
        key: state.pageKey,
        name: state.uri.toString(),
        child: BetaEdgeBack(child: child),
      )
    : MaterialPage<void>(key: state.pageKey, child: child);

/// A single-layer handoff used by glass-heavy music pages.
///
/// It coordinates the outgoing and incoming routes so they do not paint over
/// each other, which otherwise produces duplicated content or a dark backdrop
/// flash on some Android compositors.
class _SequencedMusicTransitionPage extends Page<void> {
  const _SequencedMusicTransitionPage({
    required this.child,
    this.handoffProgress = musicPageHandoffProgress,
    required this.enterOffset,
    this.enterScale = 1,
    this.scaleAlignment = Alignment.center,
    this.transitionDuration = musicPageTransitionDuration,
    this.reverseTransitionDuration = musicPageReverseTransitionDuration,
    this.reverseMotionCurve = musicPageMotionCurve,
    super.key,
  });

  final Widget child;
  final Offset enterOffset;
  final double enterScale;
  final Alignment scaleAlignment;
  final double handoffProgress;
  final Duration transitionDuration;
  final Duration reverseTransitionDuration;
  final Curve reverseMotionCurve;

  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder<void>(
      settings: this,
      // Keep backdrop-filtered music pages live during the short transition.
      // Route snapshots isolate the filter from the shell artwork on some
      // Android compositors and can flash a dark blurred frame.
      allowSnapshotting: musicPageUsesRouteSnapshotting,
      opaque: true,
      transitionDuration: transitionDuration,
      reverseTransitionDuration: reverseTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final movement = CurvedAnimation(
          parent: animation,
          curve: Interval(handoffProgress, 1, curve: musicPageMotionCurve),
          reverseCurve: Interval(handoffProgress, 1, curve: reverseMotionCurve),
        );
        final position = Tween<Offset>(
          begin: enterOffset,
          end: Offset.zero,
        ).animate(movement);
        final scale = enterScale == 1
            ? null
            : Tween<double>(begin: enterScale, end: 1).animate(movement);
        // The shell owns the theme artwork, so page routes remain transparent.
        // Stop the outgoing route from painting once the replacement begins;
        // this preserves the shared background and guarantees a single visible
        // content layer throughout tab changes.
        return MusicPageSingleLayerHandoff(
          primaryAnimation: animation,
          secondaryAnimation: secondaryAnimation,
          handoffProgress: handoffProgress,
          child: RepaintBoundary(
            child: MusicPageTransitionSurface(
              position: position,
              scale: scale,
              scaleAlignment: scaleAlignment,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
