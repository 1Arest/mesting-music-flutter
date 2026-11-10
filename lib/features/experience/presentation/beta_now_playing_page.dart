import '../../player/sharing/song_share_sheet.dart';
import '../../music_platform/netease/fallback/netease_source_picker.dart';
import '../../music_platform/presentation/platform_quality_button.dart';
import '../../music_platform/presentation/platform_comments_page.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../auth/presentation/beta_login_navigation.dart';
import 'player_queue_panel.dart';
import 'dart:ui';
import 'dart:async';
import '../../../shared/models/track.dart';
import '../../music_platform/netease/together/netease_together_panel.dart';
import '../../music_platform/netease/together/netease_together_player_header.dart';
import '../../music_platform/netease/messages/netease_messages_repository.dart';
import '../../music_platform/netease/together/netease_together_controller.dart';
import '../../music_platform/netease/together/netease_together_exit.dart';
import '../../themes/music_theme_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/track_artwork.dart';
import '../../library/presentation/favorite_toggle_button.dart';
import '../../player/player_visual_style.dart';
import '../../player/presentation/player_visual_stages.dart';
import '../../playlists/presentation/add_to_playlist_sheet.dart';
import '../../themes/beta_appearance.dart';
import '../../music_platform/platform_recommendation_providers.dart';
import 'apple_player_controls.dart';
import 'immersive_lyrics.dart';
import 'player_pull_to_dismiss.dart';
import 'player_more_menu.dart';
import 'player_glass_button.dart';
import '../../settings/presentation/music_equalizer_page.dart';
import '../../settings/presentation/music_sleep_timer_sheet.dart';
import '../../music_platform/presentation/music_effects_page.dart';
import '../../music_platform/presentation/music_mv_page.dart';
import '../../auth/presentation/beta_welcome_page.dart';
import 'player_chrome_reveal.dart';
import 'player_content_transition.dart';
import 'player_artwork_transition.dart';
import '../../themes/music_typography.dart';

/// THESIS: Artwork and lyrics lead; shared Apple transport recedes below them.
/// PALETTE: Cover-derived blur, a dark readability veil, white transport, red
/// selection. CLASSIC retains its grey turntable; other stages retain motion.
/// GEOMETRY: One bounded column, generous artwork, compact song identity.
/// BEHAVIOR: One audio handler; short windows scroll without squeezing controls.
/// ACCESS: TextScaler, native button targets, reduced motion, semantic actions.
class BetaNowPlayingPage extends ConsumerStatefulWidget {
  const BetaNowPlayingPage({
    this.lyricsInitially = false,
    this.queueInitially = false,
    this.togetherInitially = false,
    this.togetherInvitee,
    this.togetherInvitation,
    super.key,
  });
  final bool lyricsInitially;

  /// Used by the read-only diagnostic runner to enter the same production
  /// queue surface without synthesizing a tap or changing the audio owner.
  final bool queueInitially;
  final bool togetherInitially;
  final NeteasePerson? togetherInvitee;
  final String? togetherInvitation;
  @override
  ConsumerState<BetaNowPlayingPage> createState() => _BetaNowPlayingPageState();
}

class _BetaNowPlayingPageState extends ConsumerState<BetaNowPlayingPage> {
  late bool _lyrics = widget.lyricsInitially;
  late bool _queue = widget.queueInitially;
  double _direction = 1;
  StreamSubscription<String>? _commands;
  bool _routeExitRequested = false;
  late final PlayerChromeReveal _chromeReveal;
  NeteaseTogetherController? _togetherController;
  bool _togetherActive = false;
  void _roomVisibilityChanged() {
    final active = _togetherController?.active == true;
    if (mounted && active != _togetherActive) {
      setState(() => _togetherActive = active);
    }
  }

  void _showLyrics(bool show) => setState(() {
    _direction = show ? 1 : -1;
    _lyrics = show;
    _queue = false;
  });
  void _dismissPlayer() {
    if (_routeExitRequested || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _routeExitRequested = true;
    // Together entries can arrive on a local chat/feature Navigator route.
    // Dismiss that actual route as well as GoRouter-owned player routes.
    final navigator = Navigator.of(context);
    navigator.canPop() ? navigator.pop() : context.go('/music/recommend');
  }

  @override
  void initState() {
    super.initState();
    _chromeReveal = ref.read(playerChromeRevealProvider)..claim(this);
    // Only room appearance/disappearance affects the player's height budget;
    // heartbeats and duration updates remain inside the small room island.
    ref.listenManual(neteaseTogetherControllerProvider, (_, next) {
      _togetherController?.removeListener(_roomVisibilityChanged);
      _togetherController = next;
      next?.addListener(_roomVisibilityChanged);
      _roomVisibilityChanged();
    }, fireImmediately: true);
    _commands = ref.read(audioHandlerProvider).userCommandStream.listen((
      command,
    ) {
      if (command == 'skipNext') _direction = 1;
      if (command == 'skipPrevious') _direction = -1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chromeReveal.publish(this, 0);
      if (mounted && widget.togetherInitially) _openInitialTogether();
    });
  }

  Future<void> _openInitialTogether() async {
    final controller = ref.read(neteaseTogetherControllerProvider);
    await controller?.restore();
    if (mounted &&
        (controller?.active != true ||
            widget.togetherInvitee != null ||
            widget.togetherInvitation != null)) {
      await showNeteaseTogetherPanel(
        context,
        invitee: widget.togetherInvitee,
        invitation: widget.togetherInvitation,
      );
    }
  }

  @override
  void dispose() {
    final previousPlayer = _chromeReveal.release(this);
    if (previousPlayer != null) {
      // Restore after the route's disposal phase; a newer entry can claim the
      // signal in the meantime, in which case publish safely ignores this.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chromeReveal.publish(previousPlayer, 0);
      });
    }
    _togetherController?.removeListener(_roomVisibilityChanged);
    _commands?.cancel();
    super.dispose();
  }

  void _toggleQueue() => setState(() => _queue = !_queue);
  void _close() {
    if (_queue) {
      _toggleQueue();
      return;
    }
    if (_lyrics) {
      _showLyrics(false);
      return;
    }
    _dismissPlayer();
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    final style = ref.watch(playerVisualStyleProvider);
    // Buffer/position publications do not change the full artwork page. Keep
    // the transport's detailed subscriptions local to its own controls.
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final detail = _lyrics || _queue;
    final classic = style == PlayerVisualStyle.classic && !detail;
    final theme = Theme.of(context);
    final darkTheme = theme.copyWith(
      brightness: Brightness.dark,
      extensions: [
        for (final extension in theme.extensions.values)
          if (extension is! MusicThemeTokens) extension,
        MusicThemeTokens.forBrightness(Brightness.dark),
      ],
      colorScheme: ColorScheme.fromSeed(
        seedColor: BetaAppearance.blue,
        brightness: Brightness.dark,
      ).copyWith(primary: BetaAppearance.accent(Brightness.dark)),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: classic
              ? const Color(0x66000000)
              : Colors.transparent,
          minimumSize: const Size(48, 48),
        ),
      ),
    );
    return BetaMusicChromeCover(
      player: true,
      child: Theme(
        data: darkTheme,
        child: Builder(
          builder: (context) => PlayerPullToDismiss(
            onDismiss: _dismissPlayer,
            onProgress: (value) => _chromeReveal.publish(this, value),
            child: PopScope(
              canPop: !detail,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) _routeExitRequested = true;
                if (!didPop) _close();
              },
              child: Scaffold(
                backgroundColor: const Color(0xFF17191F),
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: classic
                          ? const ColoredBox(color: Color(0xFFAAA9AA))
                          : RepaintBoundary(
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: 65,
                                  sigmaY: 65,
                                ),
                                child: Transform.scale(
                                  scale: 1.4,
                                  child: TrackArtwork(
                                    track: track,
                                    width: 1000,
                                    height: 1400,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    if (style != PlayerVisualStyle.cover && !classic && !detail)
                      Positioned.fill(
                        child: PlayerStyleAtmosphere(style: style),
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: classic
                                ? const [
                                    Color(0x08000000),
                                    Color(0x66000000),
                                    Color(0xE817191D),
                                  ]
                                : [
                                    Color(
                                      _togetherActive ? 0x9916191B : 0x6616191B,
                                    ),
                                    const Color(0x8816191B),
                                    const Color(0xF216191D),
                                  ],
                            stops: const [0, .58, 1],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: LayoutBuilder(
                        builder: (context, bounds) {
                          final scaled =
                              (MediaQuery.textScalerOf(context).scale(24) - 24)
                                  .clamp(0.0, 96.0);
                          final minimum =
                              700.0 +
                              scaled * 2 +
                              (_togetherActive && !detail ? 140 : 0);
                          final content = Center(
                            child: SizedBox(
                              width: 560,
                              child: Column(
                                children: [
                                  const SizedBox(height: 8),
                                  PlayerDismissHandle(onTap: _dismissPlayer),
                                  if (!detail)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Row(
                                        children: [
                                          PlayerGlassButton(
                                            key: const ValueKey(
                                              'player-dismiss-glass',
                                            ),
                                            label: _lyrics ? '返回封面' : '收起播放器',
                                            onPressed: _close,
                                            icon: CupertinoIcons.chevron_down,
                                          ),
                                          const Spacer(),
                                          _more(context),
                                        ],
                                      ),
                                    ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 320),
                                    reverseDuration: const Duration(
                                      milliseconds: 260,
                                    ),
                                    curve: Curves.easeInOutCubic,
                                    child: !detail
                                        ? const SizedBox.shrink()
                                        : Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              26,
                                              7,
                                              26,
                                              4,
                                            ),
                                            child: Row(
                                              children: [
                                                Semantics(
                                                  button: true,
                                                  label: '返回封面',
                                                  child: GestureDetector(
                                                    onTap: () =>
                                                        _showLyrics(false),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      child: TrackArtwork(
                                                        track: track,
                                                        width: 58,
                                                        height: 58,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: _Identity(
                                                    title: track.title,
                                                    artist: track.artist,
                                                    direction: _direction,
                                                    small: true,
                                                  ),
                                                ),
                                                FavoriteToggleButton(
                                                  track: track,
                                                  star: true,
                                                  compact: true,
                                                ),
                                                _more(context),
                                              ],
                                            ),
                                          ),
                                  ),
                                  if (!detail)
                                    NeteaseTogetherPlayerHeader(
                                      foreground: classic
                                          ? const Color(0xFF17191F)
                                          : Colors.white,
                                      onManage: () =>
                                          showNeteaseTogetherPanel(context),
                                    ),
                                  Expanded(
                                    child: SizedBox(
                                      child: PlayerContentTransition(
                                        direction: _direction,
                                        child: _queue
                                            ? const PlayerQueuePanel(
                                                key: ValueKey(
                                                  'player-queue-panel',
                                                ),
                                              )
                                            : _lyrics
                                            ? ImmersiveLyrics(
                                                referenceDesign: true,
                                                key: ValueKey(
                                                  'immersive-lyrics-${track.id}',
                                                ),
                                              )
                                            : Padding(
                                                key: ValueKey(
                                                  'immersive-cover-${style.id}',
                                                ),
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      26,
                                                      12,
                                                      26,
                                                      20,
                                                    ),
                                                child: Semantics(
                                                  button: true,
                                                  label: '查看歌词',
                                                  child: GestureDetector(
                                                    onTap: () =>
                                                        _showLyrics(true),
                                                    child:
                                                        PlayerArtworkTransition(
                                                          direction: _direction,
                                                          style: style,
                                                          track: track,
                                                          playing: playing,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 320),
                                    reverseDuration: const Duration(
                                      milliseconds: 260,
                                    ),
                                    curve: Curves.easeInOutCubic,
                                    child: detail
                                        ? const SizedBox.shrink()
                                        : Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              26,
                                              0,
                                              26,
                                              5,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: _Identity(
                                                    title: track.title,
                                                    artist: track.artist,
                                                    direction: _direction,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                FavoriteToggleButton(
                                                  track: track,
                                                  star: true,
                                                ),
                                              ],
                                            ),
                                          ),
                                  ),
                                  if (track.source == TrackSource.netease &&
                                      track.audioOrigin != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 26,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        '音源：${track.audioOrigin!.adapter}${track.isPreview ? ' · 试听' : ''}',
                                        key: const ValueKey(
                                          'netease-actual-audio-source',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: classic
                                              ? const Color(0xFF565B66)
                                              : Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ApplePlayerControls(
                                    lyricsActive: _lyrics && !_queue,
                                    queueActive: _queue,
                                    onToggleLyrics: () =>
                                        _showLyrics(_queue || !_lyrics),
                                    onToggleQueue: _toggleQueue,
                                  ),
                                ],
                              ),
                            ),
                          );
                          return bounds.maxHeight < minimum
                              ? SingleChildScrollView(
                                  child: SizedBox(
                                    height: minimum,
                                    child: content,
                                  ),
                                )
                              : content;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _more(BuildContext context) {
    final current = ref.watch(playerVisualStyleProvider);
    final recommendation = ref.read(platformRecommendationSessionProvider);
    final track = ref.read(currentTrackProvider);
    return PlayerMoreMenu(
      onSelected: (value) async {
        if (value == 'share') {
          await showSongShareSheet(context, track);
          return;
        }
        if (value == 'netease-together-exit') {
          final controller = ref.read(neteaseTogetherControllerProvider);
          if (controller != null) {
            await confirmNeteaseTogetherExit(context, controller);
          }
          return;
        }
        if (value == 'source-info') {
          showMusicNotice(
            context,
            icon: CupertinoIcons.info_circle,
            title: '当前播放来源',
            message: track.availabilityMessage.isNotEmpty
                ? track.availabilityMessage
                : track.provider,
          );
          return;
        }
        if (value == 'choose-source') {
          await showNeteaseTrackSources(context, ref, track);
          return;
        }
        if (value == 'download') {
          await enqueueAudioDownload(context, ref, track);
          return;
        }
        if (value == 'sleep-timer') {
          await showMusicSleepTimer(context, ref);
          return;
        }
        if (value == 'equalizer' || value == 'effects' || value == 'mv') {
          final page = value == 'equalizer'
              ? const MusicEqualizerPage()
              : value == 'effects'
              ? const MusicEffectsPage()
              : MusicMvPage(track: track);
          await Navigator.of(
            context,
            rootNavigator: true,
          ).push(betaEntryRoute<void>(page));
          return;
        }
        if (value == 'fm-dislike') {
          await recommendation.dislike(track);
          return;
        }
        if (value == 'playlist') {
          await showAddToPlaylistSheet(
            context,
            ref,
            ref.read(currentTrackProvider),
          );
          return;
        }
        if (value == 'mode') {
          _toggleQueue();
          return;
        }
        if (value == 'quality') {
          await showPlatformQualityPicker(context, ref);
          return;
        }
        if (value == 'comments') {
          if (ref.read(platformAccountProvider).value == null) {
            await openBetaLogin(context, redirect: '/player');
          }
          if (context.mounted &&
              ref.read(platformAccountProvider).value != null) {
            await openPlatformSongComments(context, ref, track);
          }
          return;
        }
        if (value == 'netease-together') {
          await showNeteaseTogetherPanel(context);
          return;
        }
        final style = PlayerVisualStyle.values.firstWhere(
          (style) => style.name == value,
        );
        _direction = style.index < current.index ? -1 : 1;
        await ref.read(playerVisualStyleProvider.notifier).select(style);
        if (context.mounted) {
          showMusicNotice(
            context,
            icon: CupertinoIcons.music_note,
            title: '已切换为${style.displayName}',
            message: '',
          );
        }
      },
      groups: [
        if (_togetherActive)
          [
            const PlayerMenuAction(
              'netease-together',
              '管理一起听',
              CupertinoIcons.person_2,
            ),
            const PlayerMenuAction(
              'netease-together-exit',
              '退出一起听',
              CupertinoIcons.square_arrow_right,
            ),
          ],
        [
          const PlayerMenuAction(
            'mode',
            '待播列表与播放模式',
            CupertinoIcons.list_bullet,
          ),
          const PlayerMenuAction('quality', '音质选择', CupertinoIcons.waveform),
          const PlayerMenuAction('comments', '歌曲评论', CupertinoIcons.text_quote),
          const PlayerMenuAction(
            'share',
            '分享歌曲',
            CupertinoIcons.square_arrow_up,
          ),
          if (track.source == TrackSource.netease && !track.hasLocalAudio)
            const PlayerMenuAction(
              'choose-source',
              '选择音乐来源',
              CupertinoIcons.antenna_radiowaves_left_right,
            ),
          if (track.source == TrackSource.netease && !_togetherActive)
            const PlayerMenuAction(
              'netease-together',
              '一起听',
              CupertinoIcons.person_2,
            ),
          if (track.isRemote)
            const PlayerMenuAction(
              'download',
              '下载音乐',
              CupertinoIcons.arrow_down_circle,
            ),
          if (track.isRemote)
            PlayerMenuAction(
              'source-info',
              track.availabilityMessage.contains('备用音源')
                  ? track.availabilityMessage
                  : '播放来源',
              CupertinoIcons.info_circle,
            ),
          const PlayerMenuAction(
            'playlist',
            '添加到歌单',
            CupertinoIcons.music_note_list,
          ),
          if (recommendation.ownsFmTrack(track.id))
            const PlayerMenuAction(
              'fm-dislike',
              '不喜欢这首',
              CupertinoIcons.hand_thumbsdown,
            ),
        ],
        [
          PlayerMenuAction(
            'equalizer',
            track.source == TrackSource.netease ? '本地均衡器' : '均衡器',
            CupertinoIcons.slider_horizontal_3,
          ),
          if (track.source != TrackSource.netease)
            PlayerMenuAction(
              'effects',
              track.source == TrackSource.netease ? '本地音效' : '音效',
              CupertinoIcons.waveform,
            ),
          const PlayerMenuAction('mv', '观看 MV', CupertinoIcons.play_rectangle),
          const PlayerMenuAction(
            'sleep-timer',
            '定时关闭',
            CupertinoIcons.moon_zzz,
          ),
        ],
      ],
      disclosure: PlayerMenuDisclosure(
        title: '封面样式',
        current: current.displayName,
        actions: [
          for (final style in PlayerVisualStyle.values)
            PlayerMenuAction(style.name, style.displayName, switch (style) {
              PlayerVisualStyle.cover => CupertinoIcons.photo,
              PlayerVisualStyle.classic => CupertinoIcons.circle,
              PlayerVisualStyle.aurora => CupertinoIcons.sparkles,
              PlayerVisualStyle.cassette => CupertinoIcons.circle_grid_hex,
              PlayerVisualStyle.lyricStage => CupertinoIcons.waveform,
            }, selected: current == style),
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.title,
    required this.artist,
    this.small = false,
    this.direction = 1,
  });
  final String title, artist;
  final bool small;
  final double direction;
  @override
  Widget build(BuildContext context) => PlayerContentTransition(
    direction: direction,
    child: SizedBox(
      key: ValueKey('$title/$artist/$small'),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: small ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: small
                  ? MusicTypography.bodySize
                  : MusicTypography.titleSize,
              height: 1.16,
              fontWeight: MusicTypography.titleWeight,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: small
                  ? MusicTypography.subheadlineSize
                  : MusicTypography.bodySize,
            ),
          ),
        ],
      ),
    ),
  );
}
