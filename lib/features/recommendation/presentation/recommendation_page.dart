import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../experience/presentation/music_landing_page.dart';
import '../../../shared/layout/adaptive_layout.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../discover/data/curated_playlists.dart';
import '../../discover/domain/curated_playlist.dart';
import '../../library/library_providers.dart';
import '../../player/presentation/music_hub_top_bar.dart';
import '../../search/search_providers.dart';
import '../../themes/mesting_palette.dart';
import '../../themes/music_theme_preset.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/theme_controller.dart';
import '../domain/personalized_recommendation.dart';
import '../recommendation_providers.dart';
import '../../themes/music_typography.dart';

export '../data/daily_recommendations.dart' show recommendationTracksForDate;

class RecommendationPage extends ConsumerStatefulWidget {
  const RecommendationPage({super.key});

  @override
  ConsumerState<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends ConsumerState<RecommendationPage>
    with WidgetsBindingObserver {
  int _recommendationBatch = 0;
  int _refreshAnimationTurns = 0;
  bool _changingRecommendations = false;
  DateTime _now = DateTime.now();
  Timer? _greetingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleGreetingUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _calibrateGreetingClock();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _greetingTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _greetingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DistributionChannel.isBeta) return const MusicLandingPage();
    final now = _now;
    final theme = ref.watch(effectiveMusicThemeProvider);
    final hotSnapshot = ref.watch(hotMusicControllerProvider).value;
    final onlineTracks = hotSnapshot?.recommendationTracks.isNotEmpty == true
        ? hotSnapshot!.recommendationTracks
        : <Track>[
            ...?hotSnapshot?.tracks,
            ...?hotSnapshot?.popularTracks,
            ...?hotSnapshot?.risingTracks,
          ];
    final legacyListeningSignals =
        ref.watch(listeningSignalsProvider).value ?? const <ListeningSignal>[];
    final preferenceDate = recommendationPreferenceDate(now);
    final dailyListeningSignals =
        ref.watch(listeningSignalsForDayProvider(preferenceDate)).value ??
        const <ListeningSignal>[];
    final preferenceSignals = recommendationPreferenceSignalsForDate(
      now,
      dailySignals: dailyListeningSignals,
      legacySignals: legacyListeningSignals,
    );
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayPreferenceDate = recommendationPreferenceDate(yesterday);
    final yesterdayDailyListeningSignals =
        ref
            .watch(listeningSignalsForDayProvider(yesterdayPreferenceDate))
            .value ??
        const <ListeningSignal>[];
    final yesterdayPreferenceSignals = recommendationPreferenceSignalsForDate(
      yesterday,
      dailySignals: yesterdayDailyListeningSignals,
      legacySignals: legacyListeningSignals,
    );
    final favoriteTracks =
        ref.watch(favoriteTracksProvider).value ?? const <Track>[];
    final consecutiveRecommendations = consecutiveDailyRecommendations(
      today: now,
      onlineTracks: onlineTracks,
      todayPreferenceSignals: preferenceSignals,
      yesterdayPreferenceSignals: yesterdayPreferenceSignals,
      favoriteTracks: favoriteTracks,
    );
    final dailyTracks = consecutiveRecommendations.today;
    final recommendedPlaylists = _playlistBatch(_recommendationBatch);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomClearance = mestingMusicPageBottomClearanceForWidth(
      MediaQuery.sizeOf(context).width,
    );

    return CustomScrollView(
      key: const PageStorageKey('recommendation-page'),
      physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            topInset + 12,
            16,
            BetaContentInsets.bottomOf(context, bottomClearance),
          ),
          sliver: SliverList.list(
            children: [
              _RecommendationHeader(now: now),
              const SizedBox(height: 18),
              _DailyMixHero(
                tracks: dailyTracks,
                accent: theme.accent,
                onPlay: () => _playQueue(dailyTracks),
              ),
              const SizedBox(height: 14),
              _DailyRecommendationEntry(
                now: now,
                trackCount: dailyTracks.length,
                onTap: () => context.push('/music?view=daily'),
              ),
              const SizedBox(height: 28),
              const _SectionHeading(
                eyebrow: 'MATCH YOUR MOMENT',
                title: '现在适合听什么',
                subtitle: '不用搜索，选一个此刻的状态',
              ),
              const SizedBox(height: 12),
              const RepaintBoundary(
                key: ValueKey('mood-grid-visual-boundary'),
                child: _MoodGrid(),
              ),
              const SizedBox(height: 28),
              _SectionHeading(
                eyebrow: 'QUICK START',
                title: '随手点一首',
                subtitle: '从熟悉的旋律开始今天',
                actionLabel: '播放全部',
                onAction: () => _playQueue(dailyTracks),
              ),
              const SizedBox(height: 12),
              _TrackRail(
                tracks: dailyTracks.take(5).toList(growable: false),
                onPlay: (index) => _playTrack(dailyTracks[index], dailyTracks),
              ),
              const SizedBox(height: 28),
              _SectionHeading(
                eyebrow: 'MADE FOR YOU',
                title: '猜你喜欢',
                subtitle: '从不同场景里挑一些新鲜感',
                actionLabel: '换一批',
                actionIconTurns: _refreshAnimationTurns.toDouble(),
                onAction: _changeRecommendationBatch,
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                key: const ValueKey('recommendation-grid-switcher'),
                duration: const Duration(milliseconds: 520),
                reverseDuration: const Duration(milliseconds: 520),
                switchInCurve: Curves.linear,
                switchOutCurve: Curves.linear,
                transitionBuilder: (child, animation) {
                  final gridKey = (child.key as ValueKey<String>).value;
                  // Old and new glass cards must not remain readable at the
                  // same time: their borders and shadows otherwise look like
                  // a duplicated card layer. Keep only a tiny hand-off window.
                  final opacity = CurvedAnimation(
                    parent: animation,
                    curve: const Interval(.46, 1, curve: Curves.easeOutCubic),
                    reverseCurve: const Interval(
                      .50,
                      1,
                      curve: Curves.easeOutCubic,
                    ),
                  );
                  final movement = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );
                  final offset = Tween<Offset>(
                    begin: const Offset(0, .032),
                    end: Offset.zero,
                  ).animate(movement);
                  final scale = Tween<double>(
                    begin: .972,
                    end: 1,
                  ).animate(movement);
                  return FadeTransition(
                    key: ValueKey('recommendation-grid-fade-$gridKey'),
                    opacity: opacity,
                    child: SlideTransition(
                      position: offset,
                      child: ScaleTransition(
                        scale: scale,
                        child: RepaintBoundary(child: child),
                      ),
                    ),
                  );
                },
                child: _RecommendationGrid(
                  key: ValueKey('recommendation-grid-$_recommendationBatch'),
                  playlists: recommendedPlaylists,
                  theme: theme,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<CuratedPlaylist> _playlistBatch(int batch) {
    final source = <CuratedPlaylist>[
      ...curatedPlaylistsFor(CuratedPlaylistCategory.featured),
      ...curatedPlaylistsFor(CuratedPlaylistCategory.editor),
      ...curatedPlaylistsFor(CuratedPlaylistCategory.treasure),
    ];
    final offset = batch * 4;
    return List<CuratedPlaylist>.generate(
      4,
      (index) => source[(offset + index) % source.length],
      growable: false,
    );
  }

  Future<void> _changeRecommendationBatch() async {
    if (_changingRecommendations) return;
    final nextBatch = (_recommendationBatch + 1) % 4;
    setState(() {
      _changingRecommendations = true;
      _refreshAnimationTurns += 1;
      _recommendationBatch = nextBatch;
    });
    await Future<void>.delayed(const Duration(milliseconds: 520));
    if (mounted) setState(() => _changingRecommendations = false);
  }

  Future<void> _playQueue(List<Track> tracks, {int index = 0}) {
    if (tracks.isEmpty) return Future<void>.value();
    return ref
        .read(audioHandlerProvider)
        .replaceQueue(tracks, initialIndex: index);
  }

  Future<void> _playTrack(Track track, List<Track> playbackContext) {
    return ref
        .read(audioHandlerProvider)
        .playSingleTrack(track, playbackContext: playbackContext);
  }

  void _calibrateGreetingClock() {
    final now = DateTime.now();
    if (mounted) setState(() => _now = now);
    _scheduleGreetingUpdate(now);
  }

  void _scheduleGreetingUpdate([DateTime? calibratedNow]) {
    _greetingTimer?.cancel();
    final now = calibratedNow ?? DateTime.now();
    final delay = recommendationGreetingNextUpdate(now).difference(now);
    _greetingTimer = Timer(
      delay <= Duration.zero ? const Duration(minutes: 3) : delay,
      _calibrateGreetingClock,
    );
  }
}

const _lateNightGreetings = <String>[
  '月亮还在线，你也续个播？',
  '夜猫子签到，音量温柔点',
  '睡意迷路了？先听一首',
  '凌晨电台，只差你的耳朵',
  '被窝已就位，旋律请入场',
  '今晚不赶路，跟拍子散步',
];

const _morningGreetings = <String>[
  '早八没醒？让鼓点代班',
  '咖啡还没到，音乐先提神',
  '起床进度 1%，音量拉满？',
  '今天的好运，从前奏开始',
  '通勤别内耗，耳机来接管',
  '太阳打卡了，你的歌呢？',
];

const _noonGreetings = <String>[
  '午饭管饱，副歌负责快乐',
  '中场休息，给耳朵加个菜',
  '饭后别困，让节拍扶一下',
  '午间频道：禁止严肃三分钟',
  '先放下待办，听完这段前奏',
  '能量见底？旋律正在充电',
];

const _afternoonGreetings = <String>[
  '下午有点长，歌曲来抄近路',
  '摸鱼要低调，耳机要戴好',
  '困意来袭，鼓点请求出战',
  '进度条很慢，副歌可以很快',
  '脑袋转不动？先转一首歌',
  '给忙碌按暂停，给旋律按播放',
];

const _eveningGreetings = <String>[
  '今天辛苦了，耳朵下班吧',
  '晚风已到站，歌单请上车',
  '把白天静音，让旋律说话',
  '夜生活开场，先来一段前奏',
  '烦恼先寄存，音乐不收押金',
  '沙发很软，这首歌更会哄人',
];

const _bedtimeGreetings = <String>[
  '睡前最后一首——经典谎言',
  '枕头已催更，歌单还没完',
  '夜已深，音量和心事都小点',
  '再听三分钟，就三分钟',
  '把今天收尾，留一段旋律',
  '晚安还早，先让前奏落地',
];

List<String> recommendationGreetingsForTime(DateTime time) {
  final hour = time.hour;
  if (hour < 5) return _lateNightGreetings;
  if (hour < 11) return _morningGreetings;
  if (hour < 14) return _noonGreetings;
  if (hour < 18) return _afternoonGreetings;
  if (hour < 23) return _eveningGreetings;
  return _bedtimeGreetings;
}

String recommendationGreetingForTime(DateTime time) {
  final pool = recommendationGreetingsForTime(time);
  final dayKey = (time.year * 372) + (time.month * 31) + time.day;
  final threeMinuteSlot = (time.hour * 60 + time.minute) ~/ 3;
  return pool[(dayKey * 480 + threeMinuteSlot) % pool.length];
}

DateTime recommendationGreetingNextUpdate(DateTime time) {
  final slotStartMinute = time.minute - (time.minute % 3);
  return DateTime(
    time.year,
    time.month,
    time.day,
    time.hour,
    slotStartMinute,
  ).add(const Duration(minutes: 3));
}

class _RecommendationHeader extends StatelessWidget {
  const _RecommendationHeader({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return MusicHubTopBar(
      title: recommendationGreetingForTime(now),
      titleKey: ValueKey(
        'recommendation-greeting-${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute ~/ 3}',
      ),
      animateTitle: true,
      subtitle: 'FOR YOU  ·  ${now.month}月${now.day}日  ·  先从一首喜欢的歌开始',
    );
  }
}

class _DailyMixHero extends StatelessWidget {
  const _DailyMixHero({
    required this.tracks,
    required this.accent,
    required this.onPlay,
  });

  final List<Track> tracks;
  final Color accent;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = dailyMixHeroPaletteFor(accent);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 12 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 226,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                key: const ValueKey('daily-mix-hero-background'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.backgroundStart, palette.backgroundEnd],
                  ),
                ),
              ),
              if (tracks.isNotEmpty)
                Positioned(
                  right: -25,
                  top: -16,
                  child: _TiltedArtwork(track: tracks[0], size: 158, angle: .1),
                ),
              if (tracks.length > 1)
                Positioned(
                  right: 71,
                  bottom: -35,
                  child: _TiltedArtwork(
                    track: tracks[1],
                    size: 112,
                    angle: -.13,
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xD916101F),
                        const Color(0x8A16101F),
                        Colors.transparent,
                      ],
                      stops: const [0, .53, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _HeroTag(),
                    const Spacer(),
                    const Text(
                      '今日私人混合',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MusicTypography.titleSize,
                        height: 1,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tracks.isEmpty
                          ? '连接在线曲库后，为你生成今日歌单'
                          : '${tracks.length} 首偏爱与新鲜风格 · 随机开启今天',
                      style: const TextStyle(
                        color: Color(0xD9FFFFFF),
                        fontSize: MusicTypography.captionSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('daily-mix-play'),
                      onPressed: tracks.isEmpty ? null : onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 21),
                      label: const Text('开始播放'),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.playButton,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: palette.playButton.withValues(
                          alpha: .38,
                        ),
                        disabledForegroundColor: Colors.white54,
                        elevation: 0,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .16),
                        ),
                        minimumSize: const Size(124, 44),
                        textStyle: const TextStyle(
                          fontSize: MusicTypography.captionSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class DailyMixHeroPalette {
  const DailyMixHeroPalette({
    required this.backgroundStart,
    required this.backgroundEnd,
    required this.playButton,
  });

  final Color backgroundStart;
  final Color backgroundEnd;
  final Color playButton;
}

DailyMixHeroPalette dailyMixHeroPaletteFor(Color accent) {
  return DailyMixHeroPalette(
    backgroundStart: Color.lerp(accent, const Color(0xFF522D4A), .74)!,
    backgroundEnd: Color.lerp(accent, const Color(0xFF1D1725), .88)!,
    playButton: MestingPalette.heart,
  );
}

class _TiltedArtwork extends StatelessWidget {
  const _TiltedArtwork({
    required this.track,
    required this.size,
    required this.angle,
  });

  final Track track;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .2),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withValues(alpha: .34)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ArtworkImage(
            uri: track.coverAsset,
            width: size - 10,
            height: size - 10,
          ),
        ),
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .25)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'JUST FOR YOU',
          style: TextStyle(
            color: Colors.white,
            fontSize: MusicTypography.smallCaptionSize,
            fontWeight: MusicTypography.bodyWeight,
            letterSpacing: 1.3,
          ),
        ),
      ),
    );
  }
}

@immutable
class DailyDateBadgePalette {
  const DailyDateBadgePalette({
    required this.background,
    required this.border,
    required this.day,
    required this.month,
    required this.shadow,
  });

  final Color background;
  final Color border;
  final Color day;
  final Color month;
  final Color shadow;
}

const _lightDailyDateBadgeBackgrounds = <Color>[
  Color(0xFF4C6F7A),
  Color(0xFF5D638A),
  Color(0xFF52698A),
  Color(0xFF67577D),
  Color(0xFF4B705C),
  Color(0xFF796834),
  Color(0xFF505879),
];

const _darkDailyDateBadgeBackgrounds = <Color>[
  Color(0xFF294650),
  Color(0xFF333B61),
  Color(0xFF34445E),
  Color(0xFF44384F),
  Color(0xFF31483A),
  Color(0xFF4D4529),
  Color(0xFF343A52),
];

DailyDateBadgePalette dailyDateBadgePaletteFor(
  Brightness brightness, {
  DateTime? date,
}) {
  final localDate = (date ?? DateTime.now()).toLocal();
  final naturalDay = DateTime.utc(
    localDate.year,
    localDate.month,
    localDate.day,
  );
  final dayIndex =
      naturalDay.difference(DateTime.utc(2024)).inDays %
      _lightDailyDateBadgeBackgrounds.length;
  final dark = brightness == Brightness.dark;
  final backgrounds = dark
      ? _darkDailyDateBadgeBackgrounds
      : _lightDailyDateBadgeBackgrounds;
  return DailyDateBadgePalette(
    background: backgrounds[dayIndex],
    border: dark ? const Color(0x737F9AA2) : const Color(0xA8D9E8E9),
    day: const Color(0xFFFFFAF0),
    month: dark ? const Color(0xFFE8BE70) : const Color(0xFFF2CB7C),
    shadow: dark ? const Color(0x8F000000) : const Color(0x45243E46),
  );
}

class _DailyRecommendationEntry extends StatelessWidget {
  const _DailyRecommendationEntry({
    required this.now,
    required this.trackCount,
    required this.onTap,
  });

  final DateTime now;
  final int trackCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    final badgePalette = dailyDateBadgePaletteFor(
      Theme.of(context).brightness,
      date: now,
    );
    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 22,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                key: const ValueKey('daily-recommendation-date-badge'),
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgePalette.background,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: badgePalette.border),
                  boxShadow: [
                    BoxShadow(
                      color: badgePalette.shadow,
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${now.day}',
                      style: TextStyle(
                        color: badgePalette.day,
                        height: 1,
                        fontSize: MusicTypography.headingSize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    Text(
                      '${now.month}月',
                      style: TextStyle(
                        color: badgePalette.month,
                        fontSize: MusicTypography.smallCaptionSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '每日推荐',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: MusicTypography.subheadlineSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '每天更新的专属歌单 · $trackCount 首',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: MusicTypography.smallCaptionSize,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '查看',
                style: TextStyle(
                  color: accent,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIconTurns = 0,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double actionIconTurns;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                  letterSpacing: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.headingSize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.smallCaptionSize,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton.icon(
            onPressed: onAction,
            icon: AnimatedRotation(
              turns: actionIconTurns,
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              child: const Icon(Icons.refresh_rounded, size: 16),
            ),
            label: Text(actionLabel!),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: MusicTypography.smallCaptionSize,
                fontWeight: MusicTypography.bodyWeight,
              ),
            ),
          ),
      ],
    );
  }
}

class _MoodGrid extends StatelessWidget {
  const _MoodGrid();

  static const moods = <_Mood>[
    _Mood('通勤醒脑', '给今天一点速度', _MoodVisual.commute, [
      MestingPalette.primaryBright,
      MestingPalette.primary,
    ], 'editor-1'),
    _Mood('放松一下', '卸下此刻的疲惫', _MoodVisual.unwind, [
      Color(0xFF8FC8BB),
      MestingPalette.teal,
    ], 'featured-4'),
    _Mood('保持专注', '安静进入心流', _MoodVisual.focus, [
      Color(0xFF8295B7),
      MestingPalette.heart,
    ], 'featured-3'),
    _Mood('准备入睡', '让节奏慢下来', _MoodVisual.sleep, [
      Color(0xFFB0A4DD),
      MestingPalette.violet,
    ], 'editor-2'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = mestingGridColumnCount(width: constraints.maxWidth);
        const spacing = 10.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final mood in moods)
              SizedBox(
                width: itemWidth,
                child: _MoodCard(mood: mood),
              ),
          ],
        );
      },
    );
  }
}

enum _MoodVisual { commute, unwind, focus, sleep }

class _Mood {
  const _Mood(
    this.title,
    this.subtitle,
    this.visual,
    this.colors,
    this.playlistId,
  );

  final String title;
  final String subtitle;
  final _MoodVisual visual;
  final List<Color> colors;
  final String playlistId;
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.mood});

  final _Mood mood;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      key: ValueKey('mood-card-${mood.visual.name}'),
      padding: EdgeInsets.zero,
      borderRadius: 20,
      color: isDark ? null : const Color(0xFFF5F6FA),
      borderColor: isDark ? null : const Color(0x3D596784),
      shadows: isDark
          ? null
          : const [
              BoxShadow(
                color: Color(0x1F2E3D61),
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
      child: Semantics(
        button: true,
        label: '${mood.title}：${mood.subtitle}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('/music/discover/${mood.playlistId}'),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                _MoodGlyph(visual: mood.visual, colors: mood.colors),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mood.title,
                        maxLines: 1,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: MusicTypography.footnoteSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mood.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: MusicTypography.smallCaptionSize,
                        ),
                      ),
                    ],
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

class _MoodGlyph extends StatelessWidget {
  const _MoodGlyph({required this.visual, required this.colors});

  final _MoodVisual visual;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 图标轮廓以页面的深色墨水为基准，只轻微染入状态色。这样靶心的
    // 红色箭头仍是点睛，而不会把整枚图标的描边染成警示色。
    final foreground = Color.lerp(
      isDark ? Colors.white : MestingPalette.darkInk,
      colors.last,
      isDark ? .18 : .12,
    )!;
    return Container(
      key: ValueKey('mood-glyph-${visual.name}'),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.first.withValues(alpha: isDark ? .26 : .19),
            colors.last.withValues(alpha: isDark ? .13 : .08),
          ],
        ),
        border: Border.all(
          color: foreground.withValues(alpha: isDark ? .5 : .34),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: isDark ? .14 : .1),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: RepaintBoundary(
          key: ValueKey('mood-glyph-design-v2-${visual.name}'),
          child: CustomPaint(
            key: ValueKey('mood-glyph-art-${visual.name}'),
            painter: _MoodGlyphPainter(
              visual: visual,
              foreground: foreground,
              secondary: foreground.withValues(alpha: .38),
              primary: colors.first,
              accent: colors.last,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _MoodGlyphPainter extends CustomPainter {
  const _MoodGlyphPainter({
    required this.visual,
    required this.foreground,
    required this.secondary,
    required this.primary,
    required this.accent,
  });

  final _MoodVisual visual;
  final Color foreground;
  final Color secondary;
  final Color primary;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 42, size.height / 42);
    final line = Paint()
      ..color = foreground
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final soft = Paint()
      ..color = secondary
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final primaryFill = Paint()
      ..color = primary.withValues(alpha: .2)
      ..style = PaintingStyle.fill;
    final accentFill = Paint()
      ..color = accent.withValues(alpha: .48)
      ..style = PaintingStyle.fill;
    switch (visual) {
      case _MoodVisual.commute:
        _paintCommuteBus(canvas, line, soft, primaryFill, accentFill);
        break;
      case _MoodVisual.unwind:
        _paintRelaxHeadphones(canvas, line, soft, primaryFill, accentFill);
        break;
      case _MoodVisual.focus:
        _paintFocusTarget(canvas, line, soft, primaryFill, accentFill);
        break;
      case _MoodVisual.sleep:
        _paintSleepMoon(canvas, line, soft, primaryFill, accentFill);
        break;
    }
  }

  void _paintCommuteBus(
    Canvas canvas,
    Paint line,
    Paint soft,
    Paint primaryFill,
    Paint accentFill,
  ) {
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(8, 7.5, 26, 25),
      const Radius.circular(5),
    );
    final window = RRect.fromRectAndRadius(
      const Rect.fromLTWH(11.4, 11, 19.2, 8.2),
      const Radius.circular(2.7),
    );
    canvas.drawRRect(body, primaryFill);
    canvas.drawRRect(body, line);
    canvas.drawRRect(window, accentFill);
    canvas.drawRRect(window, soft);
    canvas.drawLine(const Offset(9.7, 24.2), const Offset(32.3, 24.2), soft);
    for (final x in [13.1, 28.9]) {
      canvas.drawCircle(Offset(x, 27.7), 2.1, accentFill);
      canvas.drawCircle(Offset(x, 27.7), 2.1, line);
    }
    canvas.drawLine(const Offset(11.2, 33.2), const Offset(17.3, 33.2), line);
    canvas.drawLine(const Offset(24.7, 33.2), const Offset(30.8, 33.2), line);
    canvas.drawLine(const Offset(5.5, 17.2), const Offset(8, 17.2), soft);
    canvas.drawLine(const Offset(34, 17.2), const Offset(36.5, 17.2), soft);
  }

  void _paintRelaxHeadphones(
    Canvas canvas,
    Paint line,
    Paint soft,
    Paint primaryFill,
    Paint accentFill,
  ) {
    const arch = Rect.fromLTWH(8.4, 5.3, 25.2, 27.5);
    canvas.drawArc(arch, math.pi, math.pi, false, line);
    canvas.drawArc(
      const Rect.fromLTWH(11.2, 8.1, 19.6, 22),
      math.pi,
      math.pi,
      false,
      soft,
    );
    final leftCup = RRect.fromRectAndRadius(
      const Rect.fromLTWH(6.4, 21.8, 8.9, 12.1),
      const Radius.circular(4.1),
    );
    final rightCup = RRect.fromRectAndRadius(
      const Rect.fromLTWH(28.7, 21.8, 8.9, 12.1),
      const Radius.circular(4.1),
    );
    canvas.drawRRect(leftCup, primaryFill);
    canvas.drawRRect(rightCup, primaryFill);
    canvas.drawRRect(leftCup, line);
    canvas.drawRRect(rightCup, line);
    canvas.drawLine(const Offset(11, 24.4), const Offset(11, 31.3), soft);
    canvas.drawLine(const Offset(33, 24.4), const Offset(33, 31.3), soft);
    final paddedBand = Paint()
      ..color = accentFill.color
      ..strokeWidth = 4.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      const Rect.fromLTWH(14.7, 5.2, 12.6, 7),
      math.pi,
      math.pi,
      false,
      paddedBand,
    );
  }

  void _paintFocusTarget(
    Canvas canvas,
    Paint line,
    Paint soft,
    Paint primaryFill,
    Paint accentFill,
  ) {
    const center = Offset(19.5, 23);
    canvas.drawCircle(center, 13.2, soft);
    canvas.drawCircle(center, 8.8, line);
    canvas.drawCircle(center, 4.2, primaryFill);
    canvas.drawCircle(center, 4.2, line);
    canvas.drawLine(const Offset(8.2, 34.3), const Offset(28.6, 13.9), line);
    final arrow = Path()
      ..moveTo(26.6, 11.4)
      ..lineTo(36.5, 7.2)
      ..lineTo(32.3, 17.1)
      ..lineTo(30.1, 13.6)
      ..close();
    canvas.drawPath(arrow, accentFill);
    canvas.drawPath(arrow, line);
    canvas.drawCircle(const Offset(19.5, 23), 1.5, accentFill);
    canvas.drawLine(const Offset(5.8, 35.8), const Offset(10.5, 35.8), soft);
  }

  void _paintSleepMoon(
    Canvas canvas,
    Paint line,
    Paint soft,
    Paint primaryFill,
    Paint accentFill,
  ) {
    final moon = Path()
      ..moveTo(26.8, 6.8)
      ..cubicTo(15.1, 7.8, 9.1, 17.4, 12.7, 26.2)
      ..cubicTo(16.2, 34.5, 27.1, 36.7, 34.1, 29.6)
      ..cubicTo(26.5, 30.4, 20.3, 26.5, 19.6, 20.4)
      ..cubicTo(18.8, 13.8, 22.4, 9.3, 26.8, 6.8)
      ..close();
    canvas.drawPath(moon, primaryFill);
    canvas.drawPath(moon, line);
    canvas.drawPath(
      Path()
        ..moveTo(27, 11.2)
        ..lineTo(31.6, 11.2)
        ..lineTo(27.7, 15.3)
        ..lineTo(32.2, 15.3),
      soft,
    );
    canvas.drawPath(
      Path()
        ..moveTo(31.4, 18.8)
        ..lineTo(35.1, 18.8)
        ..lineTo(32, 22.2)
        ..lineTo(35.7, 22.2),
      line,
    );
    canvas.drawCircle(const Offset(23, 31.3), 1.5, accentFill);
    canvas.drawCircle(const Offset(27.2, 33.6), 1, accentFill);
  }

  @override
  bool shouldRepaint(covariant _MoodGlyphPainter oldDelegate) =>
      visual != oldDelegate.visual ||
      foreground != oldDelegate.foreground ||
      secondary != oldDelegate.secondary ||
      primary != oldDelegate.primary ||
      accent != oldDelegate.accent;
}

class _TrackRail extends StatelessWidget {
  const _TrackRail({required this.tracks, required this.onPlay});

  final List<Track> tracks;
  final ValueChanged<int> onPlay;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    if (tracks.isEmpty) {
      return Container(
        height: 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.glassSubtle,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: tokens.border),
        ),
        child: Text(
          '在线曲库暂时不可用，请稍后刷新',
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: MusicTypography.captionSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
      );
    }
    return SizedBox(
      height: 151,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 11),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return SizedBox(
            width: 112,
            child: InkWell(
              onTap: () => onPlay(index),
              borderRadius: BorderRadius.circular(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: ArtworkImage(
                          uri: track.coverAsset,
                          width: 112,
                          height: 112,
                        ),
                      ),
                      Positioned(
                        right: 7,
                        bottom: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .92),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const SizedBox(
                            width: 29,
                            height: 29,
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xFF28212D),
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: MusicTypography.captionSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: MusicTypography.smallCaptionSize,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RecommendationGrid extends StatelessWidget {
  const _RecommendationGrid({
    required this.playlists,
    required this.theme,
    super.key,
  });

  final List<CuratedPlaylist> playlists;
  final MusicThemePreset theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = mestingGridColumnCount(width: constraints.maxWidth);
        const spacing = 11.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final playlist in playlists)
              SizedBox(
                width: itemWidth,
                child: _RecommendationCard(
                  playlist: playlist,
                  theme: theme,
                  imageWidth: itemWidth,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.playlist,
    required this.theme,
    required this.imageWidth,
  });

  final CuratedPlaylist playlist;
  final MusicThemePreset theme;
  final double imageWidth;

  @override
  Widget build(BuildContext context) {
    final index = curatedPlaylists.indexOf(playlist);
    final cover = themedPlaylistCover(
      preset: theme,
      index: index,
      fallback: playlist.coverAsset,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/music/discover/${playlist.id}'),
        borderRadius: BorderRadius.circular(21),
        child: AspectRatio(
          key: ValueKey('recommendation-card-ratio-${playlist.id}'),
          aspectRatio: 1,
          child: Container(
            key: ValueKey('recommendation-card-layer-${playlist.id}'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: context.musicThemeTokens.borderStrong),
              boxShadow: [
                BoxShadow(
                  color: context.musicThemeTokens.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ArtworkImage(
                    uri: cover,
                    decodeWidth: imageWidth,
                    decodeHeight: imageWidth,
                    fit: BoxFit.cover,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xD916111B)],
                        stops: [.35, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 10,
                    bottom: 11,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: MusicTypography.subheadlineSize,
                            fontWeight: MusicTypography.bodyWeight,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 7),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '为此刻挑选 · 在线歌单',
                          style: TextStyle(
                            color: Color(0xD9FFFFFF),
                            fontSize: MusicTypography.smallCaptionSize,
                            fontWeight: MusicTypography.bodyWeight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
