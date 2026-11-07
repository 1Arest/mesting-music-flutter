import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../music_platform/presentation/platform_quality_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../shared/layout/adaptive_layout.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../auth/auth_providers.dart';
import '../../auth/presentation/auth_gate.dart';
import '../../auth/account_capabilities.dart';
import '../../library/presentation/library_access.dart';
import '../../music_platform/presentation/platform_feedback.dart';
import '../../music_platform/presentation/platform_comments_page.dart';
import '../../library/library_providers.dart';
import '../../lyrics/presentation/lyrics_panel.dart';
import '../../social/domain/listen_together.dart';
import '../../social/domain/social_models.dart';
import '../../social/domain/track_share.dart';
import '../../social/listen_together_providers.dart';
import '../../social/presentation/listen_together_sheet.dart';
import '../../social/presentation/social_widgets.dart';
import '../../social/presentation/track_share_sheet.dart';
import '../../social/social_providers.dart';
import '../../themes/mesting_palette.dart';
import '../../themes/music_theme_preset.dart';
import '../../themes/theme_controller.dart';
import '../player_visual_style.dart';
import 'playback_controls.dart';
import 'player_visual_stages.dart';
import 'persistent_mini_player.dart';
import 'now_playing_transition.dart';
import 'vinyl_disc.dart';
import '../../experience/presentation/cover_player_page.dart';
import '../../experience/presentation/beta_now_playing_page.dart';

const nowPlayingTonearmAsset = 'assets/images/player/netease-style-tonearm.png';
const nowPlayingTonearmPlayingTurns = 0.0;
const nowPlayingTonearmPausedTurns = -22.5 / 360;
const nowPlayingTonearmPivotAlignment = Alignment(-.78, -.86);
const nowPlayingRecordControlsLift = 28.0;
const nowPlayingLyricsControlsLift = 28.0;
const nowPlayingLyricsMinimumTop = 78.0;
const nowPlayingLyricsHeadingClearance = 48.0;
const nowPlayingLyricsTopFadeClearExtent = 16.0;
const nowPlayingLyricsTopFadeExtent = 64.0;

double nowPlayingLyricsViewportTop(double safeTop) {
  final headingAwareTop = safeTop + nowPlayingLyricsHeadingClearance;
  return headingAwareTop > nowPlayingLyricsMinimumTop
      ? headingAwareTop
      : nowPlayingLyricsMinimumTop;
}

class NowPlayingTurntableLayout {
  const NowPlayingTurntableLayout({
    required this.recordRect,
    required this.tonearmRect,
    required this.infoTop,
  });

  factory NowPlayingTurntableLayout.fromSize(Size size) {
    final scale = (size.height / 873).clamp(.88, 1.12);
    final recordMaxSize = (size.width - 28).clamp(260.0, 352.0).toDouble();
    final recordSize = (328.0 * scale).clamp(260.0, recordMaxSize).toDouble();
    final recordTop = mestingIsTabletWindow(size)
        ? _tabletRecordTop(size.height, recordSize)
        : 218.0 * scale;
    final desiredInfoTop = recordTop + recordSize + 40;
    final infoTop = desiredInfoTop
        .clamp(recordTop + recordSize + 16, size.height - 272)
        .toDouble();
    final tonearmHeight = recordSize * .49;
    final tonearmWidth = recordSize * .33;
    final tonearmTop = recordTop - recordSize * .26;
    final tonearmLeft = size.width / 2 - tonearmWidth * .11;

    return NowPlayingTurntableLayout(
      recordRect: Rect.fromLTWH(
        (size.width - recordSize) / 2,
        recordTop,
        recordSize,
        recordSize,
      ),
      tonearmRect: Rect.fromLTWH(
        tonearmLeft,
        tonearmTop,
        tonearmWidth,
        tonearmHeight,
      ),
      infoTop: infoTop,
    );
  }

  final Rect recordRect;
  final Rect tonearmRect;
  final double infoTop;
}

double _tabletRecordTop(double height, double recordSize) {
  const heroTop = 72.0;
  const heroBottomClearance = 150.0;
  const infoGap = 40.0;
  const infoHeight = 114.0;
  final heroBottom = height - heroBottomClearance;
  final contentHeight = recordSize + infoGap + infoHeight;
  return heroTop +
      ((heroBottom - heroTop - contentHeight) / 2).clamp(0.0, double.infinity);
}

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({
    this.vinylOrigin,
    this.showLyricsInitially = false,
    super.key,
  });

  final Rect? vinylOrigin;
  final bool showLyricsInitially;

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  late bool _lyricsVisible;
  bool _allowRoutePop = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _lyricsVisible = widget.showLyricsInitially;
  }

  Rect _resolvedVinylOrigin(Size pageSize) {
    return widget.vinylOrigin ??
        Rect.fromLTWH(
          17,
          pageSize.height - MediaQuery.viewPaddingOf(context).bottom - 135,
          miniPlayerVinylDiameter,
          miniPlayerVinylDiameter,
        );
  }

  Future<void> _closePlayer() async {
    if (_exiting) return;
    _exiting = true;
    setState(() => _allowRoutePop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (DistributionChannel.isBeta) {
      return BetaNowPlayingPage(lyricsInitially: widget.showLyricsInitially);
    }
    if (ref.watch(playerVisualStyleProvider) == PlayerVisualStyle.cover) {
      return CoverPlayerPage(lyricsInitially: widget.showLyricsInitially);
    }
    final track = ref.watch(currentTrackProvider);
    final playbackState = ref.watch(playbackStateProvider).value;
    final playing = playbackState?.playing ?? false;
    final vinylRotating = shouldAnimateVinyl(playbackState);
    final favorite = ref.watch(favoriteTrackIdsProvider).contains(track.id);
    final pageSize = MediaQuery.sizeOf(context);
    final widePlayer =
        pageSize.width >= MestingAdaptiveBreakpoints.expanded &&
        pageSize.width / pageSize.height >= 1.15;
    final safeTop = MediaQuery.paddingOf(context).top;
    final preset = ref.watch(effectiveMusicThemeProvider);
    final playerStyle = ref.watch(playerVisualStyleProvider);
    final togetherSession = ref.watch(listenTogetherControllerProvider).value;
    final currentUser = ref.watch(currentUserProvider);
    final routeAnimation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final foregroundOpacity = CurvedAnimation(
      parent: routeAnimation,
      curve: const NowPlayingForegroundCurve(),
      reverseCurve: const NowPlayingForegroundCurve(),
    );

    Future<void> toggleFavorite() async {
      final allowed = await ensureLibraryAccess(
        context,
        ref,
        reason: '登录后才能收藏歌曲，喜欢的音乐会跟随账号在不同设备间同步。',
        redirect: '/player',
      );
      if (!allowed || !mounted) return;
      try {
        await ref.read(libraryRepositoryProvider).toggleFavorite(track);
      } catch (error) {
        if (context.mounted) showPlatformFailure(context, error);
      }
    }

    Future<void> shareTrack() async {
      final allowed = await ensureAuthenticated(
        context,
        ref,
        reason: '登录后才能把正在听的音乐分享给好友。',
        redirect: '/player',
      );
      if (!allowed || !context.mounted) return;
      final friend = await showTrackShareSheet(context: context, track: track);
      if (friend == null || !context.mounted) return;

      try {
        await ref
            .read(socialRepositoryProvider)
            .sendMessage(
              friend.uid,
              kind: SocialMessageKind.text,
              text: encodeTrackShareMessage(track),
              mediaUrl: trackShareRemoteUrl(track.audioAsset),
              thumbnailUrl: trackShareRemoteUrl(track.coverAsset),
            );
        ref.invalidate(socialConversationsProvider);
        ref.invalidate(socialMessagesProvider(friend.uid));
        if (!context.mounted) return;
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: '已分享给${friend.displayName}',
          message: '《${track.title}》已发送',
        );
      } on Object catch (error) {
        if (!context.mounted) return;
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '分享失败',
          message: userFacingErrorMessage(error, fallback: '暂时无法分享这首歌，请稍后重试'),
        );
      }
    }

    Future<void> inviteToListenTogether() async {
      final friend = await showListenTogetherInviteSheet(
        context: context,
        track: track,
      );
      if (friend == null || !context.mounted) return;
      try {
        await ref
            .read(listenTogetherControllerProvider.notifier)
            .invite(friend.uid);
        if (!context.mounted) return;
        showMusicNotice(
          context,
          icon: Icons.headphones_rounded,
          title: '邀请已发送',
          message: '正在等待${friend.displayName}加入一起听',
        );
      } on Object catch (error) {
        if (!context.mounted) return;
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '暂时无法发起一起听',
          message: userFacingErrorMessage(error, fallback: '请稍后再试'),
        );
      }
    }

    Future<void> openListenTogether() async {
      final allowed = await ensureAuthenticated(
        context,
        ref,
        reason: '登录后才能邀请互相关注的好友一起听音乐。',
        redirect: '/player',
      );
      if (!allowed || !context.mounted) return;
      final session = ref.read(listenTogetherControllerProvider).value;
      if (session == null) {
        await inviteToListenTogether();
        return;
      }
      final action = await showListenTogetherStatusSheet(
        context: context,
        session: session,
      );
      if (action == null || !context.mounted) return;
      if (action == ListenTogetherSheetAction.invite) {
        await inviteToListenTogether();
        return;
      }
      try {
        await ref.read(listenTogetherControllerProvider.notifier).leave();
        if (!context.mounted) return;
        showMusicNotice(
          context,
          icon: Icons.check_rounded,
          title: session.isPending ? '已取消邀请' : '一起听已结束',
          message: '本次时长和音乐记录已经保存',
        );
      } on Object catch (error) {
        if (!context.mounted) return;
        showMusicNotice(
          context,
          icon: Icons.error_outline_rounded,
          title: '操作失败',
          message: userFacingErrorMessage(error, fallback: '请稍后再试'),
        );
      }
    }

    return PopScope(
      canPop: _allowRoutePop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_lyricsVisible) {
          setState(() => _lyricsVisible = false);
        } else {
          _closePlayer();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _lyricsVisible
                    ? _LyricsThemeVeil(
                        key: const ValueKey('lyrics-readability-veil'),
                        coverAsset: track.coverAsset,
                      )
                    : FadeTransition(
                        key: const ValueKey('player-theme-veil'),
                        opacity: foregroundOpacity,
                        child: _PlayerThemeVeil(preset: preset),
                      ),
              ),
            ),
            Positioned.fill(
              child: AnimatedSwitcher(
                key: const ValueKey('now-playing-content-switcher'),
                duration: const Duration(milliseconds: 520),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, .025),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _lyricsVisible
                    ? Padding(
                        key: const ValueKey('lyrics'),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          nowPlayingLyricsViewportTop(safeTop),
                          16,
                          150 + nowPlayingLyricsControlsLift,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: widePlayer ? 760 : double.infinity,
                            ),
                            child: const _ImmersiveLyricsViewport(
                              child: LyricsPanel(immersive: true),
                            ),
                          ),
                        ),
                      )
                    : Align(
                        alignment: widePlayer
                            ? Alignment.centerLeft
                            : Alignment.center,
                        child: SizedBox(
                          key: ValueKey(
                            widePlayer
                                ? 'now-playing-wide-visual-pane'
                                : 'now-playing-single-visual-pane',
                          ),
                          width: widePlayer
                              ? pageSize.width * .54
                              : pageSize.width,
                          height: pageSize.height,
                          child: playerStyle == PlayerVisualStyle.classic
                              ? LayoutBuilder(
                                  key: const ValueKey('record'),
                                  builder: (context, constraints) {
                                    final turntable =
                                        NowPlayingTurntableLayout.fromSize(
                                          constraints.biggest,
                                        );
                                    final destination = turntable.recordRect;
                                    final infoTop = turntable.infoTop;
                                    final tonearmRect = turntable.tonearmRect;
                                    final tonearmHeight = tonearmRect.height;
                                    final tonearmWidth = tonearmRect.width;
                                    final tonearmTop = tonearmRect.top;
                                    final tonearmLeft = tonearmRect.left;
                                    final origin = _resolvedVinylOrigin(
                                      constraints.biggest,
                                    );
                                    return Stack(
                                      children: [
                                        AnimatedBuilder(
                                          animation: routeAnimation,
                                          builder: (context, child) {
                                            final flightProgress = Curves
                                                .easeOutCubic
                                                .transform(
                                                  (routeAnimation.value / .86)
                                                      .clamp(0.0, 1.0),
                                                );
                                            return Positioned.fromRect(
                                              rect: Rect.lerp(
                                                origin,
                                                destination,
                                                flightProgress,
                                              )!,
                                              child: GestureDetector(
                                                onTap: () => setState(
                                                  () => _lyricsVisible = true,
                                                ),
                                                child: VinylDisc(
                                                  coverAsset: track.coverAsset,
                                                  playing: vinylRotating,
                                                  labelSizeFactor:
                                                      0.59 +
                                                      (0.01 * flightProgress),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        Positioned(
                                          left: tonearmLeft,
                                          top: tonearmTop,
                                          width: tonearmWidth,
                                          height: tonearmHeight,
                                          child: FadeTransition(
                                            opacity: foregroundOpacity,
                                            child: PlayerTonearm(
                                              playing: playing,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 20,
                                          right: 20,
                                          top: infoTop,
                                          child: FadeTransition(
                                            opacity: foregroundOpacity,
                                            child: SizedBox(
                                              height: 114,
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                    left: 50,
                                                    right: 50,
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        Text(
                                                          track.title,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 26,
                                                                height: 1.15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                letterSpacing:
                                                                    -.8,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 7,
                                                        ),
                                                        Text(
                                                          track.artist,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style:
                                                              const TextStyle(
                                                                color: Color(
                                                                  0xBFFFFFFF,
                                                                ),
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Positioned(
                                                    right: 0,
                                                    top: 1,
                                                    child: _RoundGlassButton(
                                                      key: const ValueKey(
                                                        'classic-player-favorite',
                                                      ),
                                                      tooltip: favorite
                                                          ? '取消收藏'
                                                          : '收藏歌曲',
                                                      icon: favorite
                                                          ? Icons
                                                                .favorite_rounded
                                                          : Icons
                                                                .favorite_border_rounded,
                                                      iconColor: MestingPalette
                                                          .favorite,
                                                      surfaceColor:
                                                          MestingPalette
                                                              .favorite
                                                              .withValues(
                                                                alpha: favorite
                                                                    ? .20
                                                                    : .10,
                                                              ),
                                                      borderColor:
                                                          MestingPalette
                                                              .favorite
                                                              .withValues(
                                                                alpha: favorite
                                                                    ? .58
                                                                    : .34,
                                                              ),
                                                      onTap: toggleFavorite,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                )
                              : Stack(
                                  key: ValueKey(
                                    'player-stage-${playerStyle.id}',
                                  ),
                                  fit: StackFit.expand,
                                  children: [
                                    FadeTransition(
                                      opacity: foregroundOpacity,
                                      child: PlayerStyleAtmosphere(
                                        style: playerStyle,
                                      ),
                                    ),
                                    AlternativePlayerStage(
                                      style: playerStyle,
                                      track: track,
                                      vinylRotating: vinylRotating,
                                      routeAnimation: routeAnimation,
                                      favorite: favorite,
                                      onToggleFavorite: toggleFavorite,
                                      onShowLyrics: () =>
                                          setState(() => _lyricsVisible = true),
                                      topInset: alternativePlayerStageTopInset(
                                        safeTop,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
              ),
            ),
            if (widePlayer && !_lyricsVisible)
              Positioned(
                left: pageSize.width * .56,
                right: 32,
                top: safeTop + 72,
                bottom: 152,
                child: FadeTransition(
                  opacity: foregroundOpacity,
                  child: DecoratedBox(
                    key: const ValueKey('now-playing-tablet-lyrics-pane'),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .13),
                        width: .8,
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: _ImmersiveLyricsViewport(
                        child: LyricsPanel(immersive: true),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 24,
              top: safeTop + 8,
              child: FadeTransition(
                opacity: foregroundOpacity,
                child: _RoundGlassButton(
                  key: const ValueKey('now-playing-back-button'),
                  tooltip: _lyricsVisible ? '返回唱片页' : '返回音乐页',
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () {
                    if (_lyricsVisible) {
                      setState(() => _lyricsVisible = false);
                    } else if (context.canPop()) {
                      _closePlayer();
                    } else {
                      context.go('/music');
                    }
                  },
                  size: 42,
                  iconColor: Colors.white,
                  singleLayer: true,
                ),
              ),
            ),
            if (_lyricsVisible)
              Positioned(
                left: 72,
                right: 72,
                top: safeTop + 9,
                child: FadeTransition(
                  opacity: foregroundOpacity,
                  child: GestureDetector(
                    key: const ValueKey('lyrics-track-heading'),
                    onTap: () => setState(() => _lyricsVisible = false),
                    child: Column(
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: Color(0x8A000000),
                                blurRadius: 10,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xBFFFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: Color(0x80000000), blurRadius: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_lyricsVisible && ref.watch(showMestingFeaturesProvider))
              Positioned(
                left: 72,
                right: 72,
                top: safeTop + 8,
                child: FadeTransition(
                  opacity: foregroundOpacity,
                  child: Center(
                    child: _ListenTogetherPlayerChip(
                      session: togetherSession,
                      currentUser: currentUser == null
                          ? null
                          : SocialUser(
                              uid: currentUser.uid,
                              nickname: currentUser.nickname,
                              avatarUrl: currentUser.avatarUrl,
                            ),
                      onTap: openListenTogether,
                    ),
                  ),
                ),
              ),
            if (ref.watch(showPlatformFeaturesProvider) &&
                track.source == TrackSource.kugou)
              Positioned(
                right: 24,
                top: safeTop + 8,
                child: _RoundGlassButton(
                  tooltip: '酷狗歌曲评论',
                  icon: Icons.comment_outlined,
                  onTap: () => openPlatformSongComments(context, ref, track),
                  size: 42,
                  iconColor: Colors.white,
                ),
              ),
            if (track.isPreview)
              Positioned(
                left: 90,
                right: 90,
                top: safeTop + 12,
                child: const Center(
                  child: Text('平台试听', style: TextStyle(color: Colors.white)),
                ),
              ),
            if (DistributionChannel.isBeta && !_lyricsVisible)
              Positioned(
                left: 78,
                top: safeTop + 8,
                child: const PlatformQualityButton(),
              ),
            if (ref.watch(showMestingFeaturesProvider))
              Positioned(
                right: 24,
                top: safeTop + 8,
                child: FadeTransition(
                  opacity: foregroundOpacity,
                  child: _RoundGlassButton(
                    tooltip: '分享给好友',
                    icon: Icons.ios_share_rounded,
                    onTap: shareTrack,
                    size: 42,
                    iconColor: Colors.white,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FadeTransition(
                opacity: foregroundOpacity,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widePlayer ? 1080 : double.infinity,
                    ),
                    child: PlaybackControls(
                      immersive: true,
                      visualStyle: playerStyle,
                      showElapsed: true,
                      bottomLift: _lyricsVisible
                          ? nowPlayingLyricsControlsLift
                          : nowPlayingRecordControlsLift,
                    ),
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

class _ListenTogetherPlayerChip extends StatefulWidget {
  const _ListenTogetherPlayerChip({
    required this.session,
    required this.currentUser,
    required this.onTap,
  });

  final ListenTogetherSession? session;
  final SocialUser? currentUser;
  final VoidCallback onTap;

  @override
  State<_ListenTogetherPlayerChip> createState() =>
      _ListenTogetherPlayerChipState();
}

class _ListenTogetherPlayerChipState extends State<_ListenTogetherPlayerChip> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant _ListenTogetherPlayerChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.isActive != widget.session?.isActive) _syncClock();
  }

  void _syncClock() {
    _clock?.cancel();
    _clock = null;
    if (widget.session?.isActive != true) return;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final current = widget.currentUser;
    final label = switch (session?.status) {
      ListenTogetherStatus.pending => '等待好友加入',
      ListenTogetherStatus.active =>
        '一起听 ${formatListenTogetherDuration(session!.accumulatedDurationAt())}',
      ListenTogetherStatus.ended => '一起听记录',
      ListenTogetherStatus.declined ||
      ListenTogetherStatus.expired ||
      null => '好友一起听',
    };
    return Semantics(
      button: true,
      label: label,
      child: Material(
        key: const ValueKey('listen-together-player-entry'),
        color: const Color(0xFF17131E).withValues(alpha: .42),
        shape: StadiumBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: .2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (session != null && current != null) ...[
                  SizedBox(
                    width: 43,
                    height: 27,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          child: SocialAvatar(user: current, size: 27),
                        ),
                        Positioned(
                          right: 0,
                          child: SocialAvatar(user: session.peer, size: 27),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                ] else ...[
                  const Icon(
                    Icons.headphones_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
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

class PlayerTonearm extends StatelessWidget {
  const PlayerTonearm({required this.playing, super.key});

  final bool playing;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedRotation(
        turns: playing
            ? nowPlayingTonearmPlayingTurns
            : nowPlayingTonearmPausedTurns,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        alignment: nowPlayingTonearmPivotAlignment,
        child: Image.asset(
          nowPlayingTonearmAsset,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
          semanticLabel: '唱臂',
        ),
      ),
    );
  }
}

class _PlayerThemeVeil extends StatelessWidget {
  const _PlayerThemeVeil({required this.preset});

  final MusicThemePreset preset;

  @override
  Widget build(BuildContext context) {
    // The player route is non-opaque during its vinyl transition. Give the
    // player an opaque base so top-bar controls from the underlying music page
    // can never leak through and resemble an extra action button.
    final baseColor = preset.followsSystem
        ? Theme.of(context).colorScheme.surface
        : preset.colors.first;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: baseColor),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: preset.dark
                  ? [
                      Colors.black.withValues(alpha: .24),
                      Colors.black.withValues(alpha: .20),
                      Colors.black.withValues(alpha: .62),
                    ]
                  : [
                      Colors.black.withValues(alpha: .28),
                      Colors.black.withValues(alpha: .22),
                      Colors.black.withValues(alpha: .56),
                    ],
              stops: const [0, .55, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _ImmersiveLyricsViewport extends StatelessWidget {
  const _ImmersiveLyricsViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      key: const ValueKey('lyrics-top-safe-clip'),
      child: ShaderMask(
        key: const ValueKey('lyrics-top-fade-mask'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final height = bounds.height;
          final clearStop = height <= 0
              ? 0.0
              : (nowPlayingLyricsTopFadeClearExtent / height).clamp(0.0, 1.0);
          final fadeStop = height <= 0
              ? 1.0
              : (nowPlayingLyricsTopFadeExtent / height).clamp(clearStop, 1.0);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Colors.transparent,
              Colors.transparent,
              Colors.white,
              Colors.white,
            ],
            stops: [0, clearStop, fadeStop, 1],
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}

class _LyricsThemeVeil extends StatelessWidget {
  const _LyricsThemeVeil({required this.coverAsset, super.key});

  final String coverAsset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(
            key: ValueKey('lyrics-backdrop-base'),
            color: Color(0xFF36383B),
          ),
          if (coverAsset.trim().isNotEmpty)
            Positioned.fill(
              child: RepaintBoundary(
                child: Opacity(
                  opacity: .30,
                  child: ImageFiltered(
                    key: const ValueKey('lyrics-artwork-blur'),
                    imageFilter: ImageFilter.blur(sigmaX: 54, sigmaY: 54),
                    child: Transform.scale(
                      scale: 1.28,
                      child: ArtworkImage(
                        uri: coverAsset,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        retryOnNetworkError: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          DecoratedBox(
            key: const ValueKey('lyrics-backdrop-neutral-veil'),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB84A4C4F),
                  Color(0xC43B3D40),
                  Color(0xD9323437),
                  Color(0xED25272A),
                ],
                stops: [0, .36, .72, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(1.15, .42),
                radius: 1.05,
                colors: [Color(0x243A506F), Color(0x00191A1C)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.size = 48,
    this.iconColor = Colors.white,
    this.surfaceColor,
    this.borderColor,
    this.singleLayer = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color iconColor;
  final Color? surfaceColor;
  final Color? borderColor;
  final bool singleLayer;

  @override
  Widget build(BuildContext context) {
    final surface = Material(
      color:
          surfaceColor ??
          const Color(0xFF1A1422).withValues(alpha: singleLayer ? .52 : .28),
      shape: CircleBorder(
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: iconColor, size: size * .44),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: singleLayer
          ? surface
          : ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: surface,
              ),
            ),
    );
  }
}
