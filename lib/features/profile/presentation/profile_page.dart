import '../../../shared/widgets/artwork_scroll_frontier.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../shared/widgets/route_settled_content.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../music_platform/presentation/platform_account_page.dart';
import '../../music_platform/presentation/platform_profile.dart';
import '../../../shared/layout/adaptive_layout.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../auth/auth_providers.dart';
import '../../history/listening_history_providers.dart';
import '../../library/library_providers.dart';
import '../../player/presentation/music_hub_top_bar.dart';
import '../../player/presentation/music_page_transition.dart';
import '../../playlists/presentation/playlist_editor_dialog.dart';
import '../../experience/presentation/music_library_page.dart';
import '../../social/social_providers.dart';
import '../../social/social_attention.dart';
import '../../social/domain/social_models.dart';
import '../../social/presentation/social_widgets.dart';
import '../../themes/theme_gallery_page.dart';
import '../../themes/mesting_palette.dart';
import '../../themes/beta_appearance.dart';
import '../../themes/music_theme_tokens.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/music_notice.dart';
import '../profile_background_controller.dart';
import 'profile_background_visual.dart';
import 'social_status_sheet.dart';

void openMyPlaylistsFromProfile(BuildContext context) {
  context.push(
    '/music?view=playlists',
    extra: const MusicPageTransitionIntent.forward(),
  );
}

void openMusicSearchFromProfile(BuildContext context) {
  context.push(
    '/music/search',
    extra: const MusicPageTransitionIntent.forward(),
  );
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Beta owns one account presentation for guests and either restored identity.
    if (DistributionChannel.isBeta) {
      return RouteSettledContent(
        // Keep the first cold profile's glass/metadata work out of the tab's
        // moving frames. Once mounted, the complete page is retained normally.
        builder: (_) => const PlatformProfile(),
        placeholder: const Center(child: MusicActivityIndicator()),
      );
    }
    final auth = ref.watch(authControllerProvider);
    final user = auth.value?.user;
    final topInset = MediaQuery.paddingOf(context).top;
    final playlists = ref.watch(playlistsProvider).value?.length ?? 0;
    final listeningHistory = user == null
        ? const <ListeningHistoryItem>[]
        : ref.watch(listeningRankingProvider).value ??
              const <ListeningHistoryItem>[];
    final completedPlayCount = listeningHistory.fold<int>(
      0,
      (total, item) => total + item.completedPlayCount,
    );
    final socialSummary = user == null
        ? null
        : ref.watch(socialSummaryProvider).value;
    final socialAttention = user == null
        ? const SocialAttention()
        : ref.watch(socialAttentionControllerProvider);
    final socialStatus = user == null
        ? const SocialStatus.empty()
        : ref.watch(socialStatusProvider).value ??
              cachedSocialStatusSnapshot(
                ref.watch(sharedPreferencesProvider),
                user.uid,
              ) ??
              const SocialStatus.empty();
    final profileBackground = ref.watch(profileBackgroundProvider);
    final pageWidth = MediaQuery.sizeOf(context).width;
    final expanded = mestingUsesNavigationRailForWidth(pageWidth);
    final bottomClearance = mestingMusicPageBottomClearanceForWidth(pageWidth);

    final header = _PageEyebrow(
      immersive: user != null,
      onMenu: () => showMusicHubPanel(context),
      status: user == null ? null : socialStatus,
      onStatusTap: user == null
          ? null
          : () => _changeStatus(context, ref, socialStatus),
      onSearch: () => openMusicSearchFromProfile(context),
      onCreate: () =>
          _openProfileCreateMenu(context, ref, signedIn: user != null),
    );
    final dashboardItems = <_ProfileDashboardItem>[
      _ProfileDashboardItem(
        id: 'playlists',
        eyebrow: 'COLLECTION',
        icon: Icons.library_music_rounded,
        color: DistributionChannel.isBeta
            ? BetaAppearance.accent(Theme.of(context).brightness)
            : const Color(0xFF9A7AF1),
        title: '我的歌单',
        subtitle: '$playlists 个歌单 · 收藏你的声音',
        onTap: () => openMyPlaylistsFromProfile(context),
      ),
      _ProfileDashboardItem(
        id: 'history',
        eyebrow: 'FOOTPRINT',
        icon: Icons.equalizer_rounded,
        color: DistributionChannel.isBeta
            ? BetaAppearance.accent(Theme.of(context).brightness)
            : MestingPalette.amber,
        title: '听歌排行',
        subtitle: listeningHistory.isEmpty
            ? '从第一首完整播放开始记录'
            : '${listeningHistory.length} 首足迹 · 完整播放 $completedPlayCount 次',
        onTap: () => context.push(
          '/profile/listening',
          extra: const MusicPageTransitionIntent.forward(),
        ),
      ),
      _ProfileDashboardItem(
        id: 'friends',
        eyebrow: 'CONNECTION',
        icon: Icons.people_alt_rounded,
        color: DistributionChannel.isBeta
            ? BetaAppearance.accent(Theme.of(context).brightness)
            : const Color(0xFF67A9F5),
        title: '关注与粉丝',
        subtitle: socialSummary == null
            ? '找到与你同频的人'
            : '${socialSummary.followingCount} 关注 · ${socialSummary.followerCount} 粉丝',
        unreadCount: socialAttention.unreadCount,
        onUnreadTap: socialAttention.messageUnreadCount > 0
            ? () => context.push(
                '/social/messages',
                extra: const MusicPageTransitionIntent.forward(),
              )
            : null,
        onTap: () {
          unawaited(
            ref
                .read(socialAttentionControllerProvider.notifier)
                .markFollowersSeen(user?.uid ?? ''),
          );
          final tab = socialAttention.followerUnreadCount > 0 ? 1 : 0;
          context.push('/social?tab=$tab');
        },
      ),
      _ProfileDashboardItem(
        id: 'dress-up',
        eyebrow: 'IDENTITY',
        color: DistributionChannel.isBeta
            ? BetaAppearance.accent(Theme.of(context).brightness)
            : MestingPalette.teal,
        iconWidget: _DressUpGlyph(
          key: ValueKey('profile-dress-up-glyph'),
          color: MestingPalette.teal,
        ),
        title: '装扮',
        subtitle: DistributionChannel.isBeta
            ? '启动页、播放器、背景与进度条'
            : '皮肤、IP 主题、图标与启动页',
        onTap: () => showDressUpCenterSheet(context),
      ),
    ];

    return CustomScrollView(
      key: const PageStorageKey('profile-page'),
      physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          child: user == null
              ? Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    topInset + 14,
                    14,
                    bottomClearance,
                  ),
                  child: Column(
                    children: [
                      const DressUpAssetWarmup(),
                      header,
                      if (DistributionChannel.isBeta)
                        _musicPlatformEntry(context),
                      const SizedBox(height: 16),
                      if (auth.isLoading)
                        const _LoadingProfile()
                      else
                        const _GuestProfile(),
                      if (DistributionChannel.isBeta) ...[
                        ListTile(
                          leading: const Icon(Icons.favorite_border),
                          title: const Text('本机收藏'),
                          subtitle: const Text('保存在此 Beta 应用中'),
                          onTap: () => context.push('/music?view=favorites'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.queue_music),
                          title: const Text('本机歌单'),
                          onTap: () => context.push('/music?view=playlists'),
                        ),
                      ],
                    ],
                  ),
                )
              : Column(
                  children: [
                    const DressUpAssetWarmup(),
                    _SignedInHero(
                      topInset: topInset,
                      header: header,
                      nickname: user.nickname,
                      bio: user.bio,
                      avatarUrl: user.avatarUrl,
                      background: profileBackground,
                      onEditTap: () => context.push('/profile/edit'),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(14, 20, 14, bottomClearance),
                      child: _ProfileDashboard(
                        key: const ValueKey('profile-dashboard'),
                        expanded: expanded,
                        items: dashboardItems,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

Widget _musicPlatformEntry(BuildContext context) => ListTile(
  leading: const Icon(Icons.music_note_outlined),
  title: const Text('音乐平台账号'),
  subtitle: const Text('酷狗音乐 · 独立登录与退出'),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PlatformAccountPage())),
);

Future<void> _changeStatus(
  BuildContext context,
  WidgetRef ref,
  SocialStatus initialStatus,
) async {
  final selected = await showSocialStatusPicker(
    context,
    initialStatus: initialStatus,
  );
  if (selected == null || selected == initialStatus || !context.mounted) return;
  final repository = ref.read(socialRepositoryProvider);
  final preferences = ref.read(sharedPreferencesProvider);
  final uid = ref.read(currentUserProvider)?.uid;
  try {
    final saved = await repository.setStatus(selected);
    if (uid != null) {
      await rememberSocialStatusSnapshot(preferences, uid, saved);
    }
    if (!context.mounted) return;
    ref.invalidate(socialStatusProvider);
    if (uid != null) ref.invalidate(socialUserProvider(uid));
    showMusicNotice(
      context,
      icon: Icons.check_rounded,
      title: selected.isEmpty ? '状态已清除' : '状态已更新',
      message: selected.isEmpty ? '' : selected.label,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    showMusicNotice(
      context,
      icon: Icons.error_outline_rounded,
      title: '状态更新失败',
      message: userFacingErrorMessage(error, fallback: '状态更新失败，请稍后重试'),
    );
  }
}

enum _ProfileQuickAction { createPlaylist }

Future<void> _openProfileCreateMenu(
  BuildContext context,
  WidgetRef ref, {
  required bool signedIn,
}) async {
  final action = await showLiquidGlassBottomSheet<_ProfileQuickAction>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: .58),
    builder: (sheetContext) => const _ProfileCreateSheet(),
  );
  if (!context.mounted || action != _ProfileQuickAction.createPlaylist) return;
  if (DistributionChannel.isBeta) {
    await createEditorialPlaylist(context, ref);
    return;
  }
  if (!signedIn) {
    context.push(
      '/auth?mode=register&redirect=${Uri.encodeComponent('/profile')}',
    );
    return;
  }

  final draft = await showPlaylistEditorDialog(context);
  if (draft == null || !context.mounted) return;
  try {
    await ref
        .read(libraryRepositoryProvider)
        .createPlaylist(
          id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
          name: draft.name,
          description: draft.description,
          coverAsset: draft.coverAsset,
        );
    if (!context.mounted) return;
    showMusicNotice(
      context,
      icon: Icons.check_rounded,
      title: '歌单已创建',
      message: draft.name,
    );
  } on Object {
    if (!context.mounted) return;
    showMusicNotice(
      context,
      icon: Icons.error_outline_rounded,
      title: '创建失败',
      message: '暂时没能保存歌单，请稍后重试',
    );
  }
}

class _PageEyebrow extends StatelessWidget {
  const _PageEyebrow({
    required this.onMenu,
    required this.onSearch,
    required this.onCreate,
    this.immersive = false,
    this.status,
    this.onStatusTap,
  });

  final VoidCallback onMenu;
  final VoidCallback onSearch;
  final VoidCallback onCreate;
  final bool immersive;
  final SocialStatus? status;
  final VoidCallback? onStatusTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerSideInset = math.min(
          _profileHeaderCenterSideInset,
          math.max(0.0, (constraints.maxWidth - 48) / 2),
        );
        return SizedBox(
          height: _profileHeaderActionSize,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (status != null)
                Positioned(
                  left: centerSideInset,
                  right: centerSideInset,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    key: const ValueKey('profile-header-center-lane'),
                    alignment: Alignment.center,
                    child: SocialStatusBadge(
                      key: const ValueKey('profile-header-status'),
                      status: status!,
                      onTap: onStatusTap,
                      plain: true,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: _ProfileHeaderAction(
                  key: const ValueKey('profile-menu-button'),
                  tooltip: '个人中心与设置',
                  icon: Icons.menu_rounded,
                  onTap: onMenu,
                  immersive: immersive,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ProfileHeaderAction(
                      key: const ValueKey('profile-create-menu-button'),
                      tooltip: '新建歌单',
                      icon: Icons.add_rounded,
                      onTap: onCreate,
                      immersive: immersive,
                    ),
                    const SizedBox(width: _profileHeaderActionGap),
                    _ProfileHeaderAction(
                      key: const ValueKey('profile-search-button'),
                      tooltip: '搜索音乐和用户',
                      icon: Icons.search_rounded,
                      onTap: onSearch,
                      immersive: immersive,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

const double _profileHeaderActionSize = 48;
const double _profileHeaderActionGap = 9;
const double _profileHeaderCenterSideInset =
    _profileHeaderActionSize * 2 + _profileHeaderActionGap + 12;

class _ProfileHeaderAction extends StatelessWidget {
  const _ProfileHeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.immersive = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool immersive;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: immersive
            ? Colors.black.withValues(alpha: .28)
            : dark
            ? Colors.white.withValues(alpha: .07)
            : Colors.black.withValues(alpha: .035),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: immersive
                ? Colors.white.withValues(alpha: .22)
                : dark
                ? Colors.white.withValues(alpha: .16)
                : Colors.black.withValues(alpha: .10),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: _profileHeaderActionSize,
            height: _profileHeaderActionSize,
            child: Icon(
              icon,
              color: immersive ? Colors.white : tokens.textPrimary,
              size: 23,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCreateSheet extends StatelessWidget {
  const _ProfileCreateSheet();

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    final panelColor = Color.alphaBlend(
      tokens.glassStrong,
      Theme.of(context).colorScheme.surface,
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: Material(
        color: panelColor,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.textMuted.withValues(alpha: .40),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '快速创建',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '把喜欢的声音整理成自己的音乐空间',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('profile-create-menu-close'),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Material(
                  color: tokens.glassSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: BorderSide(color: tokens.borderStrong),
                  ),
                  child: InkWell(
                    key: const ValueKey('profile-create-playlist-action'),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_ProfileQuickAction.createPlaylist),
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                color: accent.withValues(alpha: .20),
                              ),
                            ),
                            child: Icon(
                              Icons.library_music_rounded,
                              color: accent,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '创建音乐歌单',
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '自定义名称、描述和封面',
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: tokens.textMuted,
                            size: 16,
                          ),
                        ],
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

class _LoadingProfile extends StatelessWidget {
  const _LoadingProfile();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 240,
      child: Center(
        child: MestingLoadingIndicator(
          key: ValueKey('profile-loading-animation'),
          semanticLabel: '正在恢复个人资料',
        ),
      ),
    );
  }
}

class _GuestProfile extends StatelessWidget {
  const _GuestProfile();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final loginPath =
        '/auth?mode=register&redirect=${Uri.encodeComponent('/profile')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileSurface(
          key: const ValueKey('guest-profile-hero'),
          emphasizeInLight: true,
          child: Stack(
            children: [
              Positioned(
                top: -78,
                right: -56,
                child: _GuestGlow(
                  size: 190,
                  color: scheme.primary.withValues(alpha: dark ? .18 : .12),
                ),
              ),
              Positioned(
                bottom: -82,
                left: -74,
                child: _GuestGlow(
                  size: 176,
                  color: scheme.secondary.withValues(alpha: dark ? .16 : .10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 21),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            size: 17,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'MESTING ACCOUNT',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.45,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.glassStrong.withValues(alpha: .72),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Text(
                            '访客模式',
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 23),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          key: const ValueKey('guest-profile-avatar'),
                          width: 94,
                          height: 94,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                scheme.primary.withValues(alpha: .92),
                                scheme.secondary.withValues(alpha: .82),
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: dark ? .22 : .72,
                              ),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: .24),
                                blurRadius: 34,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.person_outline_rounded,
                            size: 47,
                            color: scheme.onPrimary,
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: 1,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: tokens.glassStrong,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: tokens.borderStrong,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.shadow,
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '让喜欢的音乐，一直在身边',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '登录后同步收藏、歌单与个人资料\n在新设备上也能接着听',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        height: 1.55,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        key: const ValueKey('guest-login-button'),
                        onPressed: () => context.push(loginPath),
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                        label: const Text(
                          '登录或创建账号',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '登录令牌由 Android Keystore 加密保存',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text(
            '登录后解锁',
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        _ProfileSurface(
          key: const ValueKey('guest-profile-benefits'),
          emphasizeInLight: true,
          child: Column(
            children: const [
              _GuestBenefitTile(
                icon: Icons.favorite_border_rounded,
                color: MestingPalette.favorite,
                title: '收藏与歌单同步',
                subtitle: '喜欢的歌曲和创建的歌单跟随账号保存',
              ),
              Divider(height: 1, indent: 66),
              _GuestBenefitTile(
                icon: Icons.person_outline_rounded,
                color: Color(0xFF8E6DE7),
                title: '建立个人音乐主页',
                subtitle: '展示头像、状态、资料与音乐品味',
              ),
              Divider(height: 1, indent: 66),
              _GuestBenefitTile(
                icon: Icons.devices_rounded,
                color: Color(0xFF5B9DE8),
                title: '换设备继续使用',
                subtitle: '登录同一账号即可恢复云端资料',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            '暂不登录也可以继续发现和播放音乐',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _GuestGlow extends StatelessWidget {
  const _GuestGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _GuestBenefitTile extends StatelessWidget {
  const _GuestBenefitTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return ListTile(
      minTileHeight: 67,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: SizedBox(
        width: 40,
        height: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: 10,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SignedInHero extends StatelessWidget {
  const _SignedInHero({
    required this.topInset,
    required this.header,
    required this.nickname,
    required this.bio,
    required this.avatarUrl,
    required this.background,
    required this.onEditTap,
  });

  final double topInset;
  final Widget header;
  final String nickname;
  final String bio;
  final String? avatarUrl;
  final ProfileBackgroundState background;
  final VoidCallback onEditTap;

  @override
  Widget build(BuildContext context) {
    const foreground = Colors.white;
    const secondary = Color(0xD9FFFFFF);
    return SizedBox(
      key: const ValueKey('profile-immersive-hero'),
      height: topInset + 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: ProfileBackgroundVisual(
              key: const ValueKey('profile-hero-background'),
              background: background,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x12000000),
                  Color(0x4D000000),
                  Color(0xD9000000),
                ],
                stops: [0, .34, .66, 1],
              ),
            ),
          ),
          Positioned(left: 14, right: 14, top: topInset + 14, child: header),
          Positioned(
            left: 18,
            right: 18,
            bottom: 22,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                key: const ValueKey('profile-hero-content'),
                constraints: const BoxConstraints(maxWidth: 780),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      button: true,
                      label: '编辑个人资料',
                      child: GestureDetector(
                        key: const ValueKey('profile-edit-entry'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onEditTap,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              key: const ValueKey('profile-avatar-halo'),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: .14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .72),
                                  width: 1.2,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x73000000),
                                    blurRadius: 28,
                                    offset: Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: _ProfileAvatar(url: avatarUrl, size: 86),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'PERSONAL SOUNDSPACE',
                                      style: TextStyle(
                                        color: Color(0xC7FFFFFF),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.65,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      nickname,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: foreground,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -.55,
                                        shadows: [
                                          Shadow(
                                            color: Color(0x80000000),
                                            blurRadius: 12,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      bio.trim().isEmpty ? '还没有写个人简介' : bio,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: secondary,
                                        fontSize: 11.5,
                                        height: 1.38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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

class _ProfileDashboardItem {
  const _ProfileDashboardItem({
    required this.id,
    required this.eyebrow,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.unreadCount = 0,
    this.onUnreadTap,
    this.icon,
    this.iconWidget,
  }) : assert(icon != null || iconWidget != null);

  final String id;
  final String eyebrow;
  final IconData? icon;
  final Widget? iconWidget;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int unreadCount;
  final VoidCallback? onUnreadTap;
}

class _ProfileDashboard extends StatelessWidget {
  const _ProfileDashboard({
    required this.expanded,
    required this.items,
    super.key,
  });

  final bool expanded;
  final List<_ProfileDashboardItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR MUSIC SPACE',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '我的音乐空间',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.35,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '把收藏、足迹与关系放在一起',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 330
                ? 1
                : expanded
                ? 4
                : 2;
            const spacing = 10.0;
            final cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              key: expanded
                  ? const ValueKey('profile-expanded-sections')
                  : const ValueKey('profile-compact-sections'),
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in items)
                  SizedBox(
                    width: cardWidth,
                    height: 142,
                    child: _ProfileDashboardCard(item: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ProfileDashboardCard extends StatelessWidget {
  const _ProfileDashboardCard({required this.item});

  final _ProfileDashboardItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    final surface = Color.alphaBlend(
      item.color.withValues(alpha: dark ? .055 : .04),
      tokens.glassStrong.withValues(alpha: dark ? .82 : .86),
    );
    return Semantics(
      button: true,
      label: item.unreadCount > 0
          ? '${item.title}，${item.unreadCount} 条新提醒，${item.subtitle}'
          : '${item.title}，${item.subtitle}',
      child: RepaintBoundary(
        child: DecoratedBox(
          key: ValueKey('profile-dashboard-card-${item.id}'),
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: tokens.shadow.withValues(alpha: dark ? .22 : .12),
                blurRadius: 20,
                spreadRadius: -7,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: surface,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: Color.alphaBlend(
                  item.color.withValues(alpha: dark ? .12 : .08),
                  tokens.border,
                ),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: item.onTap,
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: -28,
                    right: -26,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            item.color.withValues(alpha: dark ? .20 : .13),
                            item.color.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 15,
                    left: 15,
                    child: Container(
                      key: ValueKey('profile-tile-leading-${item.title}'),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: dark ? .17 : .12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: item.color.withValues(alpha: .18),
                        ),
                      ),
                      child: Center(
                        child:
                            item.iconWidget ??
                            Icon(item.icon, color: item.color, size: 22),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 17,
                    right: 16,
                    child: item.unreadCount > 0
                        ? _ProfileUnreadBadge(
                            count: item.unreadCount,
                            onTap: item.onUnreadTap,
                          )
                        : Icon(
                            Icons.arrow_outward_rounded,
                            color: item.color.withValues(alpha: .86),
                            size: 18,
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 67, 15, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.eyebrow,
                          style: TextStyle(
                            color: item.color,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Expanded(
                          child: Text(
                            item.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 9.5,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
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
        ),
      ),
    );
  }
}

class _ProfileUnreadBadge extends StatelessWidget {
  const _ProfileUnreadBadge({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      key: const ValueKey('profile-social-unread-badge'),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: MestingPalette.heart,
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [
          BoxShadow(
            color: Color(0x36CC3F56),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        socialAttentionUnreadLabel(count),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
    if (onTap == null) return badge;
    return Semantics(
      button: true,
      label: '查看未读消息，共 $count 条',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: badge,
      ),
    );
  }
}

class _DressUpGlyph extends StatelessWidget {
  const _DressUpGlyph({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size.square(24),
        painter: _DressUpGlyphPainter(color),
      ),
    );
  }
}

class _DressUpGlyphPainter extends CustomPainter {
  const _DressUpGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final backCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(7, 2.5, 14, 16),
      const Radius.circular(4.5),
    );
    canvas.drawRRect(
      backCard,
      Paint()
        ..color = color.withValues(alpha: .42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final frontCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 5.5, 14, 16),
      const Radius.circular(4.5),
    );
    canvas
      ..drawRRect(frontCard, Paint()..color = color.withValues(alpha: .16))
      ..drawRRect(
        frontCard,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );

    final sparkle = Path()
      ..moveTo(10, 8)
      ..cubicTo(10.4, 10.4, 11.6, 11.6, 14, 12)
      ..cubicTo(11.6, 12.4, 10.4, 13.6, 10, 16)
      ..cubicTo(9.6, 13.6, 8.4, 12.4, 6, 12)
      ..cubicTo(8.4, 11.6, 9.6, 10.4, 10, 8)
      ..close();
    canvas
      ..drawPath(sparkle, Paint()..color = color)
      ..drawCircle(const Offset(17.5, 7), 1.3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DressUpGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ProfileSurface extends StatelessWidget {
  const _ProfileSurface({
    required this.child,
    this.emphasizeInLight = false,
    super.key,
  });

  final Widget child;
  final bool emphasizeInLight;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: !dark && emphasizeInLight
            ? const [
                BoxShadow(
                  color: Color(0x182E3D61),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Material(
        color: dark
            ? const Color(0xD112151C)
            : Colors.white.withValues(alpha: .78),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: dark
                ? Colors.white.withValues(alpha: .12)
                : emphasizeInLight
                ? const Color(0x26596784)
                : Colors.white.withValues(alpha: .70),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('profile-avatar'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MestingPalette.primaryBright, MestingPalette.cyan],
        ),
        shape: BoxShape.circle,
      ),
      child: url == null || url!.isEmpty
          ? Icon(Icons.person_rounded, color: Colors.white, size: size * .52)
          : ArtworkImage(
              uri: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              retryOnNetworkError: true,
            ),
    );
  }
}
