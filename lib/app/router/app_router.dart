import '../../shared/widgets/beta_page_motion.dart';
import '../../shared/widgets/beta_tab_navigation.dart';
import '../../features/experience/presentation/player_dismiss_motion.dart';
import '../../features/experience/presentation/playback_pill_menu.dart';
import '../../features/music_platform/data/platform_category_search.dart';
import '../../features/music_platform/presentation/platform_catalog_detail_page.dart';
import 'dart:ui';
import '../../shared/widgets/beta_edge_back.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/sensitive_screen.dart';
import '../../core/platform/distribution_channel.dart';
import '../../features/auth/presentation/auth_page.dart';
import '../../features/auth/presentation/account_deletion_page.dart';
import '../../features/auth/presentation/auth_protected_page.dart';
import '../../features/auth/presentation/account_bindings_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
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
import '../../features/social/presentation/chat_page.dart';
import '../../features/social/presentation/public_profile_page.dart';
import '../../features/social/presentation/social_connections_page.dart';
import '../../features/social/presentation/social_messages_page.dart';
import '../../features/social/presentation/saved_messages_page.dart';
import '../../features/themes/theme_gallery_page.dart';
import '../../features/profile/presentation/profile_edit_page.dart';
import '../../features/profile/presentation/avatar_preview_page.dart';
import '../../features/profile/presentation/profile_background_page.dart';
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
final appRouter = GoRouter(
  initialLocation: '/music/recommend',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          MusicShell(location: state.uri.toString(), child: child),
      routes: [
        GoRoute(
          path: '/music/recommend',
          pageBuilder: (context, state) =>
              _musicSlidePage(state: state, child: const RecommendationPage()),
        ),
        GoRoute(
          path: '/music',
          pageBuilder: (context, state) =>
              _musicSlidePage(state: state, child: const MusicHomePage()),
        ),
        GoRoute(
          path: '/music/library',
          pageBuilder: (context, state) => _musicSlidePage(
            state: state,
            child: MusicLibraryPage(view: state.uri.queryParameters['view']),
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
            child: AuthProtectedPage(
              reason: '登录后才能查看和编辑个人歌单。',
              allowBetaLocalLibrary: true,
              redirect: state.uri.toString(),
              child: PlaylistDetailPage(
                playlistId: state.pathParameters['playlistId']!,
              ),
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
          pageBuilder: (context, state) =>
              _musicSlidePage(state: state, child: const ProfilePage()),
        ),
        GoRoute(
          path: '/profile/edit',
          pageBuilder: (context, state) => _profileEditTransitionPage(
            state: state,
            child: SensitiveScreen(
              child: DistributionChannel.isBeta
                  ? const PlatformProfileEditPage()
                  : const AuthProtectedPage(
                      reason: '登录后才能编辑头像和个人资料。',
                      redirect: '/profile/edit',
                      child: ProfileEditPage(),
                    ),
            ),
          ),
        ),
        GoRoute(
          path: '/profile/avatar',
          pageBuilder: (context, state) => _AvatarPreviewTransitionPage(
            key: ValueKey(state.uri.toString()),
            avatarFocused: true,
            child: AuthProtectedPage(
              reason: '登录后才能预览和管理头像。',
              redirect: state.uri.toString(),
              child: const AvatarPreviewPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/profile/background',
          pageBuilder: (context, state) => _AvatarPreviewTransitionPage(
            key: ValueKey(state.uri.toString()),
            child: AuthProtectedPage(
              reason: '登录后才能预览和管理个人主页背景。',
              redirect: state.uri.toString(),
              child: const ProfileBackgroundPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/profile/listening',
          pageBuilder: (context, state) => _musicSlidePage(
            state: state,
            child: AuthProtectedPage(
              reason: '登录后才能查看听歌排行和最近播放。',
              redirect: state.uri.toString(),
              child: const ListeningHistoryPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/profile/account',
          pageBuilder: (context, state) => _musicSlidePage(
            state: state,
            child: const SensitiveScreen(
              child: AuthProtectedPage(
                reason: '登录后才能管理账号绑定。',
                redirect: '/profile/account',
                child: AccountBindingsPage(),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/profile/delete-account',
          pageBuilder: (context, state) => _musicSlidePage(
            state: state,
            child: const SensitiveScreen(
              child: AuthProtectedPage(
                reason: '登录后才能注销账号。',
                redirect: '/profile/delete-account',
                child: AccountDeletionPage(),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/social',
          pageBuilder: (context, state) => _musicSlidePage(
            state: state,
            child: AuthProtectedPage(
              reason: '登录后才能查看关注、粉丝和好友。',
              redirect: state.uri.toString(),
              child: SocialConnectionsPage(
                initialTab:
                    int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/social/messages',
          pageBuilder: (context, state) => _messagesTransitionPage(
            state: state,
            child: AuthProtectedPage(
              reason: '登录后才能查看好友消息。',
              redirect: state.uri.toString(),
              child: const SocialMessagesPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/social/saved-messages',
          pageBuilder: (context, state) => _messagesTransitionPage(
            state: state,
            child: AuthProtectedPage(
              reason: '登录后才能查看收藏消息。',
              redirect: state.uri.toString(),
              child: const SavedMessagesPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/social/saved-messages/:messageId',
          pageBuilder: (context, state) => _messagesTransitionPage(
            state: state,
            child: AuthProtectedPage(
              reason: '登录后才能查看收藏消息。',
              redirect: state.uri.toString(),
              child: SavedMessageDetailPage(
                messageId: state.pathParameters['messageId']!,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/social/users/:uid',
          pageBuilder: (context, state) => _musicSlidePage(
            state: state,
            child: AuthProtectedPage(
              reason: '登录后才能查看用户主页。',
              redirect: state.uri.toString(),
              child: PublicProfilePage(uid: state.pathParameters['uid']!),
            ),
          ),
        ),
        GoRoute(
          path: '/social/chat/:uid',
          pageBuilder: (context, state) => _musicSlidePage(
            state: state,
            child: SensitiveScreen(
              child: AuthProtectedPage(
                reason: '登录后才能与好友聊天。',
                redirect: state.uri.toString(),
                child: ChatPage(uid: state.pathParameters['uid']!),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/player',
          pageBuilder: (context, state) => _NowPlayingTransitionPage(
            key: state.pageKey,
            child: NowPlayingPage(
              showLyricsInitially: state.extra is PlaybackPillLyricsIntent,
              vinylOrigin: state.extra is NowPlayingTransitionIntent
                  ? (state.extra! as NowPlayingTransitionIntent).vinylOrigin
                  : null,
            ),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => SensitiveScreen(
        child: AuthPage(
          initialMode: state.uri.queryParameters['mode'] ?? 'register',
          redirect: state.uri.queryParameters['redirect'] ?? '/music/recommend',
        ),
      ),
    ),
    GoRoute(
      path: '/auth/recover',
      // Retired Beta account recovery links return to the available platform
      // login flow. The formal channel keeps its original recovery route.
      redirect: (context, state) => DistributionChannel.isBeta
          ? Uri(
              path: '/auth',
              queryParameters: {
                'mode': 'login',
                'redirect': state.uri.queryParameters['redirect'] ?? '/profile',
              },
            ).toString()
          : null,
      builder: (context, state) => SensitiveScreen(
        child: ForgotPasswordPage(
          redirect: state.uri.queryParameters['redirect'] ?? '/music/recommend',
        ),
      ),
    ),
  ],
);

class _NowPlayingTransitionPage extends Page<void> {
  const _NowPlayingTransitionPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) {
    late final _NowPlayingRoute route;
    route = _NowPlayingRoute(
      settings: this,
      // The vinyl flight is rendered inside the live player page so it can use
      // the mini player's exact global bounds without route snapshot artifacts.
      // Snapshot static page bodies while the route itself slides/fades. The
      // shell player and navigation stay outside this route and remain live.
      allowSnapshotting: !DistributionChannel.isBeta,
      opaque: false,
      transitionDuration: nowPlayingTransitionDuration,
      reverseTransitionDuration: nowPlayingReverseTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          DistributionChannel.isBeta ? BetaEdgeBack(child: child) : child,
      // The player animates its vinyl and chrome from the route animation.
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          DistributionChannel.isBeta
          ? AnimatedBuilder(
              animation: Listenable.merge([
                animation,
                route.playerDismissMotion,
              ]),
              builder: (context, child) {
                final motion = route.playerDismissMotion;
                final progress = motion.dragDriven
                    ? animation.value
                    : (animation.status == AnimationStatus.reverse
                              ? Curves.easeInCubic
                              : Curves.easeOutCubic)
                          .transform(animation.value);
                return FractionalTranslation(
                  translation: Offset(0, 1 - progress),
                  child: child,
                );
              },
              child: RepaintBoundary(child: child),
            )
          : child,
    );
    return route;
  }
}

class _NowPlayingRoute extends PageRouteBuilder<void>
    implements PlayerDismissRoute {
  _NowPlayingRoute({
    required super.pageBuilder,
    required super.transitionsBuilder,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
    required super.opaque,
    required super.allowSnapshotting,
    super.settings,
  });

  @override
  late final PlayerDismissMotion playerDismissMotion;

  @override
  void install() {
    super.install();
    playerDismissMotion = PlayerDismissMotion(controller!);
  }

  @override
  bool didPop(void result) {
    playerDismissMotion.markPopped();
    return super.didPop(result);
  }

  @override
  void dispose() {
    playerDismissMotion.dispose();
    super.dispose();
  }

  @override
  DelegatedTransitionBuilder get delegatedTransition =>
      (context, animation, secondaryAnimation, allowSnapshotting, child) {
        if (child == null) return null;
        // The Beta player is a real sliding surface. Its underlay must stay
        // painted throughout both route pop and handle dismissal. The formal
        // vinyl flight uses its original two-phase choreography below.
        if (DistributionChannel.isBeta) return child;
        return AnimatedBuilder(
          animation: secondaryAnimation,
          child: child,
          builder: (context, child) {
            final progress = secondaryAnimation.value;
            return Opacity(
              opacity: nowPlayingUnderlayOpacity(progress),
              child: Transform.translate(
                offset: Offset(0, nowPlayingUnderlayOffset(progress)),
                child: Transform.scale(
                  scale: nowPlayingUnderlayScale(progress),
                  alignment: Alignment.bottomCenter,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: nowPlayingUnderlayBlurSigma(progress),
                      sigmaY: nowPlayingUnderlayBlurSigma(progress),
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      };
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
    return CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      child: tabIndex != null
          ? BetaTabRouteReady(
              index: tabIndex,
              child: BetaEdgeBack(child: child),
            )
          : child is MusicSearchPage
          ? child
          : BetaEdgeBack(child: child),
      transitionsBuilder: (context, animation, secondary, child) =>
          tabIndex != null
          ? BetaRootTabMotion(
              index: tabIndex,
              animation: animation,
              secondary: secondary,
              child: child,
            )
          : BetaPageMotion(animation: animation, child: child),
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
  if (DistributionChannel.isBeta) child = BetaEdgeBack(child: child);
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

Page<void> _messagesTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  if (DistributionChannel.isBeta) child = BetaEdgeBack(child: child);
  final intent = state.extra is MusicPageTransitionIntent
      ? state.extra! as MusicPageTransitionIntent
      : const MusicPageTransitionIntent.forward();
  if (intent.usesMusicHubPanelTransition) {
    return _MusicHubPanelTransitionPage(
      key: ValueKey(state.uri.toString()),
      handoffProgress: messagesPageHandoffProgress,
      child: child,
    );
  }
  final horizontal = intent.direction == MusicPageTransitionDirection.forward
      ? messagesPageHorizontalOffset
      : -messagesPageHorizontalOffset;
  return _SequencedMusicTransitionPage(
    key: ValueKey(state.uri.toString()),
    transitionDuration: messagesPageTransitionDuration,
    reverseTransitionDuration: messagesPageReverseTransitionDuration,
    enterOffset: Offset(horizontal, 0),
    enterScale: messagesPageStartScale,
    scaleAlignment: Alignment.centerRight,
    handoffProgress: messagesPageHandoffProgress,
    child: child,
  );
}

/// Full-page continuation after [MusicHubPanelTransition] has dismissed.
///
/// The drawer is dismissed before this route is pushed. A short, already-
/// visible destination glide preserves that spatial relationship without
/// repeating the drawer's full-width sweep or compositing both surfaces.
class _MusicHubPanelTransitionPage extends Page<void> {
  const _MusicHubPanelTransitionPage({
    required this.child,
    this.handoffProgress = musicPageHandoffProgress,
    super.key,
  });

  final Widget child;
  final double handoffProgress;

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
class _AvatarPreviewTransitionPage extends Page<void> {
  const _AvatarPreviewTransitionPage({
    required this.child,
    this.avatarFocused = false,
    super.key,
  });

  final Widget child;
  final bool avatarFocused;

  @override
  Route<void> createRoute(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return PageRouteBuilder<void>(
      settings: this,
      opaque: false,
      allowSnapshotting: false,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 420),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => child,
      transitionsBuilder: (_, animation, _, child) {
        if (reduceMotion) return child;
        final opacity = CurvedAnimation(
          parent: animation,
          curve: const Interval(.03, .82, curve: Curves.easeOutCubic),
          reverseCurve: const Interval(0, .78, curve: Curves.easeInCubic),
        );
        Widget transition = FadeTransition(opacity: opacity, child: child);
        if (avatarFocused) {
          transition = ScaleTransition(
            alignment: Alignment.center,
            scale: Tween<double>(begin: .975, end: 1).animate(opacity),
            child: transition,
          );
        }
        return transition;
      },
    );
  }
}

Page<void> _collectionRevealPage({
  required GoRouterState state,
  required Widget child,
}) {
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

/// A single-layer handoff used by glass-heavy music pages.
///
/// It coordinates the outgoing and incoming routes so they do not paint over
/// each other, which otherwise produces duplicated content or a dark backdrop
/// flash on some Android compositors.
class _SequencedMusicTransitionPage extends Page<void> {
  const _SequencedMusicTransitionPage({
    required this.child,
    required this.enterOffset,
    this.enterScale = 1,
    this.scaleAlignment = Alignment.center,
    this.handoffProgress = musicPageHandoffProgress,
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
          reverseCurve: Interval(
            1 - handoffProgress,
            1,
            curve: reverseMotionCurve,
          ),
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
