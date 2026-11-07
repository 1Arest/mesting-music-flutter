import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../core/diagnostics/diagnostic_run.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/beta_glass_controls.dart'
    show BetaActivityIndicator;
import '../../../shared/widgets/music_feature_page.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../auth/beta_account_choice.dart';
import '../../audiobooks/audiobooks_page.dart';
import '../../kugou_together/together_page.dart';
import '../../experience/presentation/beta_bottom_bar.dart';
import '../../experience/presentation/beta_now_playing_page.dart';
import '../../experience/presentation/music_home_catalogues.dart';
import '../../experience/presentation/editorial_widgets.dart';
import '../../history/presentation/listening_history_page.dart';
import '../../music_platform/data/platform_explore.dart';
import '../../music_platform/data/platform_recommendations.dart';
import '../../music_platform/data/platform_category_search.dart';
import '../../music_platform/data/platform_comments_repository.dart';
import '../../music_platform/domain/platform_session.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/platform_backend_providers.dart';
import '../../music_platform/netease/netease_comments_repository.dart';
import '../../music_platform/netease/full/netease_full_page.dart';
import '../../music_platform/netease/netease_features_page.dart';
import '../../music_platform/netease/netease_features_repository.dart';
import '../../music_platform/netease/netease_membership_page.dart';
import '../../music_platform/netease/netease_playback_settings_page.dart';
import '../../music_platform/netease/messages/netease_messages_page.dart';
import '../../music_platform/netease/messages/netease_messages_repository.dart';
import '../../music_platform/presentation/music_effects_page.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../music_platform/presentation/platform_library_page.dart';
import '../../music_platform/presentation/platform_recommendations_page.dart';
import '../../music_platform/presentation/platform_catalog_detail_page.dart';
import '../../music_platform/presentation/platform_comments_page.dart';
import '../../music_platform/presentation/platform_search_landing.dart';
import '../../music_platform/presentation/unified_reward_page.dart';
import '../../music_platform/qishui/qishui_mine_widgets.dart';
import '../../music_platform/qishui/qishui_pages.dart';
import '../../music_platform/qishui/qishui_player_navigation.dart';
import '../../music_platform/qishui/qishui_playlist_page.dart';
import 'music_equalizer_page.dart';
import 'haptic_settings_page.dart';

/// Fixed, reviewable allowlist: navigation and scroll only. No semantic button
/// scanning, screen coordinates, account writes, playback commands or fixtures.
/// Each entry opens the production Widget/route, including its real glass chrome.
List<DiagnosticScenario> productionDiagnosticScenarios() => [
  for (final id in ['player', 'lyrics', 'queue'])
    DiagnosticScenario('common/$id', _labels[id]!, null),
  for (final platform in ['netease', 'kugou']) ...[
    for (final id in [
      'recommend',
      'functions',
      'library',
      'profile',
      'daily',
      'fm',
      'favorites',
      'history',
      'effects',
      'checkin',
      'tabs',
      'player',
      'lyrics',
      'queue',
      'comments',
    ])
      DiagnosticScenario(
        '$platform/$id',
        '${platform == 'netease' ? '网易云' : '酷狗'} · ${_labels[id]}',
        platform,
      ),
    for (final kind in PlatformExploreKind.values)
      DiagnosticScenario(
        '$platform/catalog-${kind.name}',
        '${platform == 'netease' ? '网易云' : '酷狗'} · ${kind.label}',
        platform,
      ),
    for (final kind in PlatformExploreKind.values)
      DiagnosticScenario(
        '$platform/collection-${kind.name}',
        '${platform == 'netease' ? '网易云' : '酷狗'} · ${kind.label}真实详情',
        platform,
      ),
    if (platform == 'kugou')
      for (final page in [1, 2])
        DiagnosticScenario(
          '$platform/effects@$page',
          '酷狗 · 音效${page == 1 ? '耳机' : '明星'}',
          platform,
        ),
    if (platform == 'kugou') ...[
      const DiagnosticScenario('kugou/audiobooks', '酷狗 · 有声书', 'kugou'),
      const DiagnosticScenario('kugou/together', '酷狗 · 一起听大厅（只读）', 'kugou'),
    ],
    DiagnosticScenario('$platform/checkin@1', '双平台签到 · 第二标签（只读）', platform),
    if (platform == 'netease') ...[
      for (final feed in _standaloneFeeds)
        DiagnosticScenario(
          '$platform/feed-${feed.name}',
          '网易云 · ${NeteaseFeaturesRepository.titles[feed] ?? feed.name}',
          platform,
        ),
      for (final id in ['messages', 'chat', 'notices'])
        DiagnosticScenario('$platform/$id', '网易云 · ${_labels[id]}', platform),
      for (final id in [
        'artist',
        'album',
        'playlist',
        'podcast',
        'podcastCategory',
        'category',
        'historyDate',
      ])
        DiagnosticScenario(
          '$platform/entity-$id',
          '网易云 · 真实${_entityLabels[id]}详情',
          platform,
        ),
      for (final page in [1, 2, 3])
        DiagnosticScenario(
          '$platform/notices@$page',
          '网易云 · 通知标签${page + 1}',
          platform,
        ),
      const DiagnosticScenario(
        'netease/workflows',
        '网易云 · 功能目录（只读浏览）',
        'netease',
      ),
      const DiagnosticScenario('netease/membership', '网易云 · 会员与音源', 'netease'),
      const DiagnosticScenario(
        'netease/playback-options',
        '网易云 · 音源设置',
        'netease',
      ),
    ],
  ],
  for (final id in [
    'downloads',
    'local',
    'history',
    'search',
    'themes',
    'settings',
    'replay',
    'queue-list',
    'playlists',
    'equalizer',
    'haptics',
    'legal',
    'agreement',
    'privacy',
  ])
    DiagnosticScenario('common/$id', _labels[id]!, null),
  const DiagnosticScenario('common/downloads@1', '下载任务', null),
  const DiagnosticScenario('common/local@1', '本地文件夹', null),
  const DiagnosticScenario('common/history@1', '最近播放', null),
  const DiagnosticScenario('common/comments', '当前歌曲评论（只读）', null),
  for (final id in _excludedScreens.keys)
    DiagnosticScenario('excluded/$id', _excludedScreens[id]!, null),
  // Preserve all previous scenarios' order and active platform for paired
  // measurements. Soda appends its real roots and read-only secondary pages.
  for (final entry in const {
    'recommend': '发现',
    'music': '音乐',
    'profile': '我的',
    'history': '历史播放',
    'playlist': '歌单',
    'search': '搜索',
    'lyrics': '歌词',
    'tabs': '主 Tab 快速切换',
  }.entries)
    DiagnosticScenario('qishui/${entry.key}', '汽水 · ${entry.value}', 'qishui'),
];

const _entityLabels = {
  'artist': '歌手',
  'album': '专辑',
  'playlist': '歌单',
  'podcast': '播客节目',
  'podcastCategory': '播客分类',
  'category': '歌单分类',
  'historyDate': '历史日推',
};
const _excludedScreens = {
  'authentication': '登录 / 验证码 / 绑定 / 注销：需用户主动身份操作',
  'editing': '头像 / 背景 / 歌单编辑与导入：需用户主动修改',
  'system-permissions': '识曲录音 / 一起听定位：需用户主动系统授权',
  'commerce': '会员购买 / 付费 / 奖励验证：不自动触发交易或领取',
  'social-writing': '发消息 / 评论 / 邀请 / 上传：不自动产生社交内容',
  'media-autoplay': 'MV / 视频详情：生产页面会自动播放，需用户主动进入',
  'mesting-social': 'Mesting 社交页：此次巡检使用网易云和酷狗身份，不切换第三方账号',
  'sleep-timer': '睡眠定时器：只读浏览不更改定时，需用户主动设置',
  'onboarding': '欢迎与首次引导：不重置已完成的引导状态',
};

const _labels = {
  'player': '歌曲播放器',
  'lyrics': '歌词',
  'queue': '播放队列',
  'recommend': '发现',
  'functions': '功能',
  'library': '音乐库',
  'profile': '我的',
  'daily': '每日推荐',
  'fm': '私人 FM',
  'favorites': '喜欢的音乐',
  'history': '听歌历史',
  'effects': '音效',
  'checkin': '双平台签到（只读）',
  'tabs': '超快速主 Tab',
  'messages': '消息',
  'comments': '歌曲评论',
  'chat': '已有私信会话',
  'notices': '评论 / @ / 通知',
  'downloads': '下载 / 已下载',
  'local': '本地音乐',
  'search': '搜索',
  'themes': '主题',
  'settings': '设置',
  'replay': '听歌回顾',
  'queue-list': '待播列表',
  'playlists': '本机歌单',
  'equalizer': '均衡器',
  'haptics': '震动与触感',
  'legal': '隐私与协议',
  'agreement': '用户协议',
  'privacy': '隐私政策',
};

// These feeds have no entity-ID prerequisite. Detail feeds are handled using
// real returned entities below; a missing item is a skip, never a fake song.
const _standaloneFeeds = [
  NeteaseFeed.recommended,
  NeteaseFeed.premium,
  NeteaseFeed.categories,
  NeteaseFeed.artists,
  NeteaseFeed.albums,
  NeteaseFeed.mvs,
  NeteaseFeed.likedAlbums,
  NeteaseFeed.likedArtists,
  NeteaseFeed.likedMvs,
  NeteaseFeed.cloud,
  NeteaseFeed.week,
  NeteaseFeed.allTime,
  NeteaseFeed.recentSongs,
  NeteaseFeed.recentPlaylists,
  NeteaseFeed.recentAlbums,
  NeteaseFeed.podcasts,
  NeteaseFeed.podcastCategories,
  NeteaseFeed.subscribedPodcasts,
  NeteaseFeed.podcastToday,
  NeteaseFeed.podcastPersonal,
  NeteaseFeed.podcastTop,
  NeteaseFeed.recentPodcasts,
  NeteaseFeed.recommendedPrograms,
  NeteaseFeed.historyDates,
  NeteaseFeed.follows,
  NeteaseFeed.followers,
  NeteaseFeed.userPlaylists,
  NeteaseFeed.recommendedMvs,
  NeteaseFeed.privateContent,
  NeteaseFeed.newestAlbums,
  NeteaseFeed.topAlbums,
  NeteaseFeed.recommendedSongs,
];

class ProductionDiagnosticDriver implements DiagnosticDriver {
  ProductionDiagnosticDriver({
    required this.container,
    required this.router,
    required this.navigator,
    required this.originalPlatform,
    this.originalAccountChoice,
  });
  final ProviderContainer container;
  final GoRouter router;
  final NavigatorState navigator;
  final MusicPlatform? originalPlatform;
  final BetaAccountChoice? originalAccountChoice;
  String? _expectedPlatform;
  Route<void>? _route;
  GlobalKey? _pageKey;
  bool _closed = false;
  bool _qishuiLyricsOpened = false;

  @override
  List<DiagnosticScenario> get scenarios => productionDiagnosticScenarios();

  @override
  Future<void> open(
    DiagnosticScenario scenario,
    DiagnosticTicket ticket,
  ) async {
    ticket.check();
    if (scenario.id.startsWith('excluded/')) {
      throw const DiagnosticSkip('excluded_interactive_operation');
    }
    _closed = false;
    _expectedPlatform = scenario.platform;
    if (scenario.platform != null) {
      final platform = MusicPlatform.values.byName(scenario.platform!);
      final accounts = container.read(platformAccountProvider.notifier);
      final saved = await accounts.retainedIdentity(platform);
      ticket.check();
      if (saved == null) throw const DiagnosticSkip('platform_not_logged_in');
      await accounts.switchPlatform(platform);
      ticket.check();
      if (container.read(platformAccountProvider).value?.platform != platform) {
        throw StateError('platform_not_ready');
      }
    }
    final variant = scenario.id.split('/').last.split('@');
    final id = variant.first;
    if (scenario.platform == 'qishui') {
      await _openQishui(id, ticket);
      await _ready(ticket);
      return;
    }
    const rootPaths = {
      'recommend': '/music/recommend',
      'functions': '/music',
      'library': '/music/library',
      'profile': '/profile',
      'local': '/music/local',
      'search': '/music/search',
      'themes': '/music/themes',
      'settings': '/music/settings',
      'history': '/profile/listening',
      'replay': '/music/replay',
      'queue-list': '/music/queue',
      'playlists': '/music/playlists',
      'legal': '/legal',
      'agreement': '/legal/user-agreement',
      'privacy': '/legal/privacy-policy',
      'tabs': '/music/recommend',
    };
    final path = rootPaths[id];
    if (path != null) {
      router.go(path);
      await _settle(ticket);
      if (router.routeInformationProvider.value.uri.path != path) {
        throw StateError('route_redirected');
      }
    } else {
      final page = await _page(id, ticket);
      ticket.check();
      final key = _pageKey = GlobalKey();
      _route = betaContentRoute<void>(KeyedSubtree(key: key, child: page));
      unawaited(navigator.push(_route!));
      await _settle(ticket);
      if (key.currentContext == null || _route?.isCurrent != true) {
        throw StateError('page_not_visible');
      }
    }
    // Settle route motion first, then wait for real visible loading indicators.
    // A ready error/empty state remains an honest failure/skip in the report.
    await _ready(ticket);
    if (variant.length > 1) {
      await _selectPage(int.parse(variant.last), ticket);
      await _ready(ticket);
    }
  }

  /// Navigate through Soda's actual roots and existing page callbacks. No
  /// playback, signer tests, cloud writes or synthetic song seeds are used.
  Future<void> _openQishui(String id, DiagnosticTicket ticket) async {
    final path = switch (id) {
      'recommend' || 'search' || 'tabs' => '/music/recommend',
      'music' || 'lyrics' => '/music',
      _ => '/profile',
    };
    router.go(path);
    await _settle(ticket);
    if (id == 'profile' || id == 'playlist') {
      // The preceding history scenario keeps this retained branch alive.
      // Select its real playlist tab before collecting a playlist seed; an
      // active history tab is not evidence that the account has no playlists.
      final tabs = _visible().map((e) => e.widget).whereType<QishuiMineTabs>();
      if (tabs.isEmpty) throw StateError('production_soda_mine_tabs_missing');
      tabs.last.onSelected(QishuiMineTab.playlists);
      await _settle(ticket);
    }
    await _ready(ticket);
    if (id == 'lyrics') {
      if (container.read(currentMediaItemProvider).value == null ||
          container.read(currentTrackProvider).source.name != 'qishui') {
        throw const DiagnosticSkip('no_current_platform_song');
      }
      container.read(qishuiMusicLyricsProvider.notifier).showLyrics();
      _qishuiLyricsOpened = true;
      await _settle(ticket);
    } else if (id == 'history') {
      final tabs = _visible().map((e) => e.widget).whereType<QishuiMineTabs>();
      if (tabs.isEmpty) throw StateError('production_soda_tabs_missing');
      tabs.last.onSelected(QishuiMineTab.history);
      await _settle(ticket);
    } else if (id == 'search' || id == 'playlist') {
      Widget page = const QishuiSearchPage();
      if (id == 'playlist') {
        final lists = _visible()
            .map((e) => e.widget)
            .whereType<QishuiMinePlaylistList>();
        if (lists.isEmpty || lists.last.playlists.isEmpty) {
          throw const DiagnosticSkip('no_real_detail_seed');
        }
        page = QishuiPlaylistPage(
          playlist: lists.last.playlists.first,
          navigationIndex: 3,
        );
      }
      final key = _pageKey = GlobalKey();
      _route = betaContentRoute<void>(KeyedSubtree(key: key, child: page));
      unawaited(navigator.push(_route!));
      await _settle(ticket);
      if (key.currentContext == null || _route?.isCurrent != true) {
        throw StateError('page_not_visible');
      }
    }
  }

  Future<Widget> _page(String id, DiagnosticTicket ticket) async {
    if (id == 'player' || id == 'lyrics' || id == 'queue') {
      if (container.read(currentMediaItemProvider).value == null) {
        throw const DiagnosticSkip('no_current_song');
      }
      if (_expectedPlatform != null &&
          container.read(currentTrackProvider).source.name !=
              _expectedPlatform) {
        throw const DiagnosticSkip('no_current_platform_song');
      }
      if (id == 'queue' &&
          (container.read(queueProvider).value?.isEmpty ?? true)) {
        throw const DiagnosticSkip('queue_empty');
      }
      return BetaNowPlayingPage(
        lyricsInitially: id == 'lyrics',
        queueInitially: id == 'queue',
      );
    }
    if (id.startsWith('catalog-')) {
      return MusicHomeCataloguePage(
        kind: PlatformExploreKind.values.byName(id.substring(8)),
      );
    }
    if (id.startsWith('feed-')) {
      return NeteaseFeaturesPage(
        feed: NeteaseFeed.values.byName(id.substring(5)),
      );
    }
    if (id.startsWith('collection-')) {
      final kind = PlatformExploreKind.values.byName(id.substring(11));
      final items = await container
          .read(platformExploreRepositoryProvider)
          .list(kind);
      ticket.check();
      if (items.isEmpty) throw const DiagnosticSkip('no_real_detail_seed');
      return PlatformExploreSongsPage(item: items.first);
    }
    if (id.startsWith('entity-')) return _entityPage(id.substring(7), ticket);
    switch (id) {
      case 'daily':
        return const PlatformRecommendationDetail(title: '每日推荐');
      case 'fm':
        return const PlatformRecommendationDetail(
          kind: PlatformRecommendationKind.fm,
          title: '私人 FM',
        );
      case 'favorites':
        return const PlatformLibraryPage(favorites: true);
      case 'history':
        return const ListeningHistoryPage();
      case 'effects':
        return const MusicEffectsPage();
      case 'checkin':
        return const UnifiedRewardPage();
      case 'downloads':
        // Fix the diagnostic baseline at page zero; the @1 scenario then
        // genuinely exercises the separate task page and its own scroll state.
        return const AudioDownloadsPage(downloadedOnly: true);
      case 'equalizer':
        return const MusicEqualizerPage();
      case 'haptics':
        return const HapticSettingsPage();
      case 'membership':
        return const NeteaseMembershipPage();
      case 'playback-options':
        return const NeteasePlaybackSettingsPage();
      case 'audiobooks':
        return const AudiobooksPage();
      case 'together':
        return const TogetherPage();
      case 'messages':
        return const NeteaseMessagesPage();
      case 'notices':
        return NeteaseNoticesPage(initial: NeteaseNoticeKind.values.first);
      case 'workflows':
        return const NeteaseFullHubPage();
      case 'comments':
        if (container.read(platformAccountProvider).value?.platform ==
            MusicPlatform.qishui) {
          throw const DiagnosticSkip('qishui_comments_unavailable');
        }
        final session = container.read(platformAccountProvider).value;
        final track = container.read(currentTrackProvider);
        if (session == null || track.platformSongId.isEmpty) {
          throw const DiagnosticSkip('no_current_song');
        }
        if (track.source.name != session.platform.name) {
          throw const DiagnosticSkip('no_current_platform_song');
        }
        final repository = session.platform == MusicPlatform.netease
            ? NeteaseCommentsRepository(
                container.read(musicPlatformApiProvider),
                session,
                container.read(neteaseMusicRepositoryProvider),
              )
            : PlatformCommentsRepository(
                container.read(musicPlatformApiProvider),
                session,
              );
        return PlatformSongCommentsPage(track: track, repository: repository);
      case 'chat':
        final rows = await container
            .read(neteaseMessagesRepositoryProvider)
            .conversations();
        ticket.check();
        if (rows.isEmpty) {
          throw const DiagnosticSkip('no_existing_conversation');
        }
        return NeteaseChatPage(peer: rows.first.peer);
    }
    throw const DiagnosticSkip('unsupported_page');
  }

  Future<Widget> _entityPage(String kind, DiagnosticTicket ticket) async {
    final seedFeed = switch (kind) {
      'artist' => NeteaseFeed.artists,
      'album' => NeteaseFeed.albums,
      'playlist' => NeteaseFeed.recommended,
      'podcast' => NeteaseFeed.podcasts,
      'podcastCategory' => NeteaseFeed.podcastCategories,
      'category' => NeteaseFeed.categories,
      _ => NeteaseFeed.historyDates,
    };
    final batch = await container.read(neteaseFeaturesProvider).load(seedFeed);
    ticket.check();
    if (batch.items.isEmpty) throw const DiagnosticSkip('no_real_detail_seed');
    final item = batch.items.first;
    if (kind == 'album' || kind == 'playlist') {
      return PlatformCatalogDetailPage(
        hit: PlatformSearchHit(
          kind: kind == 'album'
              ? PlatformSearchKind.albums
              : PlatformSearchKind.playlists,
          id: item.id,
          title: item.name,
          cover: item.cover,
        ),
      );
    }
    return NeteaseFeaturesPage(
      feed: switch (kind) {
        'artist' => NeteaseFeed.artistSongs,
        'podcast' => NeteaseFeed.podcastPrograms,
        'podcastCategory' => NeteaseFeed.podcastCategory,
        'category' => NeteaseFeed.category,
        _ => NeteaseFeed.historySongs,
      },
      id: item.id,
      title: item.name,
    );
  }

  Future<void> _selectPage(int index, DiagnosticTicket ticket) async {
    final pagers = _visible()
        .whereType<StatefulElement>()
        .map((e) => e.state)
        .whereType<ScrollableState>()
        .where(
          (s) =>
              s.context.findAncestorWidgetOfExactType<PageView>() != null &&
              // Root tabs are selected by their production callback. Driving
              // the root PageController directly can show another branch
              // while leaving route/back/search ownership on the old tab.
              // Their dedicated /tabs scenario exercises the real callback.
              s.context.findAncestorWidgetOfExactType<PageView>()!.key !=
                  const ValueKey('beta-root-tab-viewport') &&
              s.position.axis == Axis.horizontal,
        );
    if (pagers.isEmpty) throw const DiagnosticSkip('no_paged_navigation');
    final position = pagers.first.position;
    final destination = index * position.viewportDimension;
    if (destination > position.maxScrollExtent + 1) {
      throw const DiagnosticSkip('page_not_available');
    }
    await position.animateTo(
      destination,
      duration: const Duration(milliseconds: 160),
      curve: Curves.linear,
    );
    ticket.check();
    if ((position.pixels - destination).abs() > 2) {
      throw StateError('page_destination_mismatch');
    }
  }

  Future<void> _settle(DiagnosticTicket ticket) async {
    await Future<void>.delayed(const Duration(milliseconds: 520));
    ticket.check();
    await WidgetsBinding.instance.endOfFrame;
    ticket.check();
  }

  /// Enumerate only active, painted production descendants. Offstage routes,
  /// PageView cache neighbours and covered Navigator pages cannot own actions.
  List<Element> _visible() {
    final root = (_pageKey?.currentContext ?? navigator.context) as Element;
    final result = <Element>[];
    void walk(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is TickerMode && !widget.enabled) return;
      final route = ModalRoute.of(element);
      if (route != null && !route.isCurrent) return;
      final object = element.findRenderObject();
      if (object is RenderBox && object.attached && object.hasSize) {
        final bounds = object.localToGlobal(Offset.zero) & object.size;
        final view = View.of(element);
        final screen =
            Offset.zero & (view.physicalSize / view.devicePixelRatio);
        if (!bounds.overlaps(screen)) return;
      }
      result.add(element);
      element.visitChildren(walk);
    }

    root.visitChildren(walk);
    return result;
  }

  Future<void> _ready(DiagnosticTicket ticket) async {
    var stable = 0;
    while (stable < 2) {
      ticket.check();
      final visible = _visible();
      final feedback = visible
          .map((e) => e.widget)
          .whereType<PlatformFeedbackState>();
      final emptyStates = visible
          .map((e) => e.widget)
          .whereType<EditorialEmpty>();
      if (emptyStates.any((e) => e.onRetry != null)) {
        throw StateError('page_load_failed');
      }
      if (feedback.any((e) => !e.loading && e.retry != null)) {
        throw StateError('page_load_failed');
      }
      if (visible.any(
        (e) =>
            e.widget is MusicFeatureMessage &&
            (e.widget as MusicFeatureMessage).onRetry != null,
      )) {
        throw StateError('page_load_failed');
      }
      if (visible.any((e) => e.widget is ErrorWidget)) {
        throw StateError('page_build_failed');
      }
      // A settled Soda refusal is a failed load, not a smooth catalog sample.
      // Do not count its retry/empty surface as a successful music page.
      if (visible.any((e) => e.widget is QishuiError)) {
        throw StateError('page_load_failed');
      }
      final busy =
          feedback.any((e) => e.loading) ||
          visible.any(
            (e) =>
                e.widget is MestingLoadingIndicator ||
                e.widget is BetaActivityIndicator ||
                e.widget is MusicActivityIndicator ||
                e.widget is CircularProgressIndicator,
          );
      stable = busy ? 0 : stable + 1;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  Future<Map<String, Object>> exercise(
    DiagnosticScenario scenario,
    DiagnosticPhase phase,
    DiagnosticTicket ticket,
  ) async {
    ticket.check();
    if (scenario.id.endsWith('/tabs')) {
      if (phase != DiagnosticPhase.pages) {
        throw const DiagnosticSkip('dedicated_tab_stage');
      }
      // Soda exposes three destinations over the existing retained branches;
      // never send its hidden library branch as a visual fourth destination.
      final destinations = scenario.platform == 'qishui'
          ? [0, 1, 3, 1, 0, 3, 1, 0, 3, 0, 1, 3]
          : [0, 1, 2, 3, 2, 1, 0, 3, 0, 2, 1, 3];
      for (final index in destinations) {
        ticket.check();
        final bars = _visible()
            .map((e) => e.widget)
            .whereType<BetaMusicBottomBar>();
        if (bars.isEmpty) throw StateError('production_bar_missing');
        // This is the production onTabSelected callback, including existing
        // BetaTabNavigation coalescing; never bypass it with repeated go().
        bars.last.onTabSelected(index);
        await Future<void>.delayed(const Duration(milliseconds: 65));
      }
      await _settle(ticket);
      await _settle(ticket);
      if (router.routeInformationProvider.value.uri.path != '/profile') {
        throw StateError('final_tab_mismatch');
      }
      return {
        'requests': 12,
        'finalTab': 'profile',
        'productionNavigation': true,
      };
    }
    if (phase == DiagnosticPhase.transition) {
      // Record actual pop then entry motion in its own window. Opening is
      // verified by open(), not inferred from the visibility of an old button.
      if (_route == null) {
        // Root routes are declarative and close() has no imperative page to
        // pop. Visit a real neighbouring route so re-entry measures motion.
        final current = router.routeInformationProvider.value.uri.path;
        router.go(
          current == '/music/settings' ? '/music/recommend' : '/music/settings',
        );
        await _settle(ticket);
      } else {
        await close();
      }
      ticket.check();
      await open(scenario, ticket);
      return {'verifiedReentry': true};
    }
    if (phase == DiagnosticPhase.pages) return _pages(ticket);
    final states = _visible()
        .whereType<StatefulElement>()
        .map((e) => e.state)
        .whereType<ScrollableState>()
        .where(
          (s) =>
              s.position.axis == Axis.vertical &&
              s.position.hasContentDimensions &&
              s.position.maxScrollExtent > s.position.minScrollExtent,
        )
        .toList();
    if (states.isEmpty) throw const DiagnosticSkip('no_scrollable_content');
    var motions = 0;
    // Exercise a bounded set of visible lists. Geometry comes from each real
    // viewport and extent; content is never pulled past the refresh boundary.
    for (final state in states.take(3)) {
      for (var i = 0; i < (phase == DiagnosticPhase.normal ? 6 : 8); i++) {
        ticket.check();
        if (!state.mounted) break;
        final p = state.position;
        final forward = phase == DiagnosticPhase.normal ? i < 3 : i % 4 < 2;
        final distance =
            p.viewportDimension * (phase == DiagnosticPhase.normal ? .8 : 3.0);
        final sweep = phase == DiagnosticPhase.fastReverse && i.isOdd;
        final target =
            (sweep
                    ? (forward ? p.maxScrollExtent : p.minScrollExtent)
                    : p.pixels + (forward ? distance : -distance))
                .clamp(p.minScrollExtent, p.maxScrollExtent)
                .toDouble();
        if ((target - p.pixels).abs() < .5) continue;
        await p.animateTo(
          target,
          duration: Duration(
            milliseconds: phase == DiagnosticPhase.normal ? 420 : 65,
          ),
          curve: Curves.linear,
        );
        ticket.check();
        motions++;
      }
    }
    if (motions == 0) throw const DiagnosticSkip('no_scrollable_content');
    return {'scrollMotions': motions, 'directionReversed': true};
  }

  Future<Map<String, Object>> _pages(DiagnosticTicket ticket) async {
    final states = _visible()
        .whereType<StatefulElement>()
        .map((e) => e.state)
        .whereType<ScrollableState>()
        .where(
          (s) =>
              s.context.findAncestorWidgetOfExactType<PageView>() != null &&
              s.position.axis == Axis.horizontal,
        )
        .toList();
    if (states.isEmpty) throw const DiagnosticSkip('no_paged_navigation');
    var motions = 0;
    for (final state in states.take(2)) {
      final position = state.position;
      final dimension = position.viewportDimension;
      if (dimension <= 0) continue;
      final pages = (position.maxScrollExtent / dimension).round() + 1;
      // Covers every page, then fast reversals. Report the actual destinations.
      for (final index in [
        ...List.generate(pages, (i) => i),
        ...List.generate(pages, (i) => pages - 1 - i),
      ]) {
        ticket.check();
        await position.animateTo(
          (index * dimension)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble(),
          duration: const Duration(milliseconds: 80),
          curve: Curves.linear,
        );
        ticket.check();
        if ((position.pixels - index * dimension).abs() > 2) {
          throw StateError('page_destination_mismatch');
        }
        await _ready(ticket);
        motions++;
      }
    }
    return {'pageMotions': motions, 'verifiedDestinations': true};
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_qishuiLyricsOpened) {
      _qishuiLyricsOpened = false;
      container.read(qishuiMusicLyricsProvider.notifier).showCover();
    }
    final route = _route;
    _route = null;
    _pageKey = null;
    if (route != null && route.isActive) {
      // Search fields can install local back history. A single pop may close
      // that field instead of the page; verify that the actual route leaves.
      for (var attempt = 0; attempt < 4 && route.isCurrent; attempt++) {
        navigator.pop();
        await Future<void>.delayed(const Duration(milliseconds: 380));
      }
      if (route.isCurrent) throw StateError('route_did_not_pop');
      if (route.isActive) {
        navigator.removeRoute(route);
      }
      if (route is TransitionRoute<void>) await route.completed;
    }
  }

  @override
  Future<void> restore(DiagnosticTicket ticket) async {
    await close();
    ticket.check();
    if (originalPlatform != null &&
        container.read(platformAccountProvider).value?.platform !=
            originalPlatform) {
      await container
          .read(platformAccountProvider.notifier)
          .switchPlatform(originalPlatform!);
      ticket.check();
    }
    if (originalPlatform == null && originalAccountChoice != null) {
      // Restore a guest/Mesting choice without logging out either retained
      // platform account; signOut would destroy the very credentials we tested.
      await container
          .read(betaAccountChoiceProvider.notifier)
          .select(originalAccountChoice!);
      ticket.check();
    }
    router.go('/music/settings');
    await Future<void>.delayed(const Duration(milliseconds: 520));
    // The caller opens the diagnostics page after this driver has restored the
    // platform. No audio resume is issued as a side effect of navigation.
  }
}
