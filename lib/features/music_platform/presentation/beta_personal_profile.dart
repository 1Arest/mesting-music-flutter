import '../../../shared/widgets/beta_content_insets.dart';
import '../netease/netease_account_overview.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../domain/platform_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../auth/presentation/beta_account_card.dart';
import '../../downloads/audio_downloads_page.dart';
import '../../experience/presentation/editorial_widgets.dart';
import '../../themes/beta_appearance.dart';
import '../../library/library_providers.dart';
import '../data/cloud_library_repository.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../platform_profile_provider.dart';
import '../netease/netease_library_repository.dart';
import '../netease/netease_membership_page.dart';
import '../netease/full/netease_full_page.dart';
import 'platform_account_page.dart';
import 'platform_avatar.dart';
import 'platform_design.dart';
import 'platform_library_page.dart';
import 'platform_login_options_page.dart';
import 'platform_profile_edit_page.dart';
import 'unified_reward_page.dart';

/// Personal library composition is independent of the account card used by
/// Settings. Only real library/profile data is shown; reference statistics are
/// never copied from the supplied screenshot.
class BetaPersonalProfile extends ConsumerStatefulWidget {
  const BetaPersonalProfile({super.key});
  @override
  ConsumerState<BetaPersonalProfile> createState() =>
      _BetaPersonalProfileState();
}

class _BetaPersonalProfileState extends ConsumerState<BetaPersonalProfile> {
  void _open(Widget page) =>
      Navigator.of(context).push(betaContentRoute<void>(page));
  Future<void> _sign() async => _open(const UnifiedRewardPage());

  Future<void> _account() async {
    final action = await showLiquidGlassBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              ('edit', '编辑个人资料', CupertinoIcons.person_crop_circle),
              ('switch', '切换音乐平台', CupertinoIcons.arrow_2_circlepath),
              (
                'account',
                '管理当前账号',
                CupertinoIcons.person_crop_circle_badge_checkmark,
              ),
            ])
              ListTile(
                leading: Icon(entry.$3),
                title: Text(entry.$2),
                onTap: () => Navigator.pop(sheet, entry.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') _open(const PlatformProfileEditPage());
    if (action == 'switch') _open(const MusicPlatformSwitchPage());
    if (action == 'account') {
      final session = ref.read(platformAccountProvider).value;
      if (session != null) {
        _open(PlatformAccountPage(platform: session.platform));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only identity changes rebuild the page structure. Profile metadata,
    // favorites, counts and playlists subscribe inside their own sections.
    final session = ref.watch(platformAccountProvider).value;
    final netease = ref.watch(usesNeteaseProvider);
    return PlatformStyle(
      child: CustomScrollView(
        key: PageStorageKey('personal-profile:${session?.ownerId ?? 'guest'}'),
        slivers: [
          _ProfilePart(
            key: const ValueKey('profile-heading-sliver'),
            child: _PersonalHeading(
              signedIn: session != null,
              onAccount: _account,
            ),
          ),
          _ProfilePart(
            key: const ValueKey('profile-identity-sliver'),
            child: session == null
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: BetaAccountCard(),
                  )
                : _PersonalIdentity(session),
          ),
          _ProfilePart(
            key: const ValueKey('profile-quick-sliver'),
            child: _PersonalQuickActions(
              signedIn: session != null,
              netease: netease,
              signing: false,
              onSign: _sign,
            ),
          ),
          const _ProfilePart(child: _PersonalStorageEntry()),
          _ProfilePart(child: _PersonalMusicHeading(signedIn: session != null)),
          const _ProfilePart(child: _PersonalLikedPlaylist()),
          const _PersonalPlaylists(),
          if (netease)
            const _ProfilePart(child: NeteaseFullNavigation(tab: '我的')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: BetaContentInsets.musicBottomOf(
                context,
                editorialBottomClearance,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A separate sliver is important here: a single large Column keeps all six
/// glass layers in its paint traversal while any part of the header is visible.
/// The viewport can omit a fully offscreen part, without disposing its state or
/// replacing its live material with a screenshot. Text/image repaints stay local.
class _ProfilePart extends StatelessWidget {
  const _ProfilePart({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      SliverToBoxAdapter(child: RepaintBoundary(child: child));
}

class _PersonalHeading extends StatelessWidget {
  const _PersonalHeading({required this.signedIn, required this.onAccount});
  final bool signedIn;
  final VoidCallback onAccount;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 14),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 18, 12),
      child: GlassBackdropGroup(
        // Sharing is opt-in and conservative: scales, shadows or read margins
        // that overlap return to independent passes, including during a press.
        requireDisjointBounds: true,
        child: Row(
          children: [
            Text(
              '我的',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (signedIn)
              BetaGlassButton(
                label: '账号选项',
                width: 48,
                height: 48,
                onPressed: onAccount,
                child: const Icon(CupertinoIcons.ellipsis),
              ),
            const SizedBox(width: 12),
            BetaGlassButton(
              label: '设置',
              width: 48,
              height: 48,
              onPressed: () => context.push('/music/settings'),
              child: const Icon(CupertinoIcons.gear_alt),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PersonalIdentity extends ConsumerWidget {
  const _PersonalIdentity(this.session);
  final PlatformSession session;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(platformProfileProvider).value;
    return Column(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(
            context,
          ).push(betaContentRoute<void>(const PlatformProfileEditPage())),
          child: Semantics(
            button: true,
            label: '编辑个人资料',
            child: PlatformAvatar(
              url: profile?.avatarUrl ?? session.avatarUrl,
              size: 104,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            profile?.nickname ?? session.nickname,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
        ),
        const NeteaseLocalSvipBadge(),
        if (session.platform == MusicPlatform.netease) const _PersonalLevel(),
        const SizedBox(height: 9),
        Text(
          '${session.platformLabel}账号',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (profile?.signature?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
            child: Text(
              profile!.signature!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: 18),
        const _PersonalCounts(),
      ],
    );
  }
}

class _PersonalLevel extends ConsumerWidget {
  const _PersonalLevel();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(
      neteaseAccountOverviewProvider.select(
        (value) => value.value?.level?.level,
      ),
    );
    return TextButton(
      onPressed: () => Navigator.of(
        context,
      ).push(betaContentRoute<void>(const NeteaseAccountOverviewPage())),
      child: Text(level == null ? '查看网易云等级' : 'Lv.$level'),
    );
  }
}

/// The page displays only a count and the first cover, not every track field.
/// A metadata/availability update for another one of 674 favorites must not
/// rebuild the avatar, glass controls or playlist slivers.
final _personalFavoriteSummary = Provider((ref) {
  return ref.watch(
    favoriteTracksProvider.select((value) {
      final tracks = value.value;
      return (
        count: tracks?.length ?? 0,
        cover: tracks?.firstOrNull?.coverAsset ?? '',
      );
    }),
  );
});

class _PersonalCounts extends ConsumerWidget {
  const _PersonalCounts();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(
      _personalFavoriteSummary.select((s) => s.count),
    );
    final playlists = ref.watch(
      playlistsProvider.select((s) => s.value?.length ?? 0),
    );
    return Text(
      '$favorites 首喜欢  ·  $playlists 个歌单',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _PersonalQuickActions extends StatelessWidget {
  const _PersonalQuickActions({
    required this.signedIn,
    required this.netease,
    required this.signing,
    required this.onSign,
  });
  final bool signedIn, netease, signing;
  final VoidCallback onSign;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
    child: GlassBackdropGroup(
      requireDisjointBounds: true,
      child: Row(
        children: [
          _PersonalQuickLink(
            '最近',
            CupertinoIcons.clock,
            () => context.push('/music/library?view=recent'),
            tone: BetaFeatureTone.insights,
          ),
          _PersonalQuickLink(
            '已下载',
            CupertinoIcons.arrow_down_circle,
            () => openAudioDownloads(context, downloadedOnly: true),
            tone: BetaFeatureTone.downloads,
          ),
          _PersonalQuickLink(
            '签到',
            CupertinoIcons.calendar,
            signedIn && !signing ? onSign : null,
            loading: signing,
          ),
          _PersonalQuickLink(
            '会员',
            CupertinoIcons.star_circle,
            signedIn
                ? () => Navigator.of(context).push(
                    betaContentRoute<void>(
                      netease
                          ? const NeteaseMembershipPage()
                          : const UnifiedRewardPage(),
                    ),
                  )
                : null,
          ),
        ],
      ),
    ),
  );
}

class _PersonalQuickLink extends StatelessWidget {
  const _PersonalQuickLink(
    this.title,
    this.icon,
    this.action, {
    this.loading = false,
    this.tone = BetaFeatureTone.action,
  });
  final String title;
  final IconData icon;
  final VoidCallback? action;
  final bool loading;
  final BetaFeatureTone tone;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: BetaGlassButton(
        onPressed: action,
        loading: loading,
        height: 62,
        horizontalPadding: 5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: action == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : BetaAppearance.feature(context, tone),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PersonalStorageEntry extends StatelessWidget {
  const _PersonalStorageEntry();
  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('profile-download-storage'),
    contentPadding: const EdgeInsets.symmetric(horizontal: 26),
    leading: Icon(
      CupertinoIcons.folder,
      color: BetaAppearance.feature(context, BetaFeatureTone.downloads),
    ),
    title: const Text('下载与存储', style: TextStyle(fontWeight: FontWeight.w500)),
    subtitle: const Text('下载任务、保存目录与文件管理'),
    trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
    onTap: () => openAudioDownloads(context),
  );
}

class _PersonalMusicHeading extends ConsumerWidget {
  const _PersonalMusicHeading({required this.signedIn});
  final bool signedIn;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      const SizedBox(height: 10),
      EditorialSection(
        '我的音乐',
        fontWeight: FontWeight.w700,
        actionLabel: '新建歌单',
        onTap: signedIn ? () => createPlatformPlaylist(context, ref) : null,
      ),
    ],
  );
}

class _PersonalLikedPlaylist extends ConsumerWidget {
  const _PersonalLikedPlaylist();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(_personalFavoriteSummary);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: 64,
          child: favorites.cover.isNotEmpty
              ? ArtworkImage(
                  uri: favorites.cover,
                  width: 64,
                  height: 64,
                  decodeWidth: 64,
                  decodeHeight: 64,
                  retryOnNetworkError: true,
                )
              : ColoredBox(
                  color: scheme.surfaceContainerLow,
                  child: Icon(
                    CupertinoIcons.heart_fill,
                    color: BetaAppearance.favorite(scheme.brightness),
                  ),
                ),
        ),
      ),
      title: const Text(
        '我喜欢的音乐',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${favorites.count} 首歌曲'),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
      onTap: () => context.push('/music?view=favorites'),
    );
  }
}

class _PersonalPlaylists extends ConsumerWidget {
  const _PersonalPlaylists();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final repository = ref.watch(libraryRepositoryProvider);
    final owner = ref.watch(
      platformAccountProvider.select((a) => a.value?.ownerId),
    );
    final lists = playlists.value ?? const <UserPlaylist>[];
    final liked = repository is NeteaseLibraryRepository
        ? repository.likedPlaylistId
        : null;
    final owned = <UserPlaylist>[], saved = <UserPlaylist>[];
    for (final playlist in lists) {
      if (playlist.id == liked) continue;
      if (repository is! CloudLibraryRepository ||
          repository.canManage(playlist.id)) {
        owned.add(playlist);
      } else {
        saved.add(playlist);
      }
    }
    Widget group(String title, List<UserPlaylist> items) => SliverMainAxisGroup(
      slivers: [
        _ProfilePart(
          child: EditorialSection(
            '$title · ${items.length}',
            fontWeight: FontWeight.w700,
          ),
        ),
        if (items.isEmpty)
          _ProfilePart(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Text(
                '还没有$title',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              key: ValueKey('profile-playlist:$owner:${item.id}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 7,
              ),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ArtworkImage(
                  uri: item.coverAsset ?? '',
                  width: 64,
                  height: 64,
                  retryOnNetworkError: true,
                  persistentNetworkCacheKey: 'playlist-cover:$owner:${item.id}',
                ),
              ),
              title: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(title == '创建的歌单' ? '我的歌单' : '收藏的歌单'),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
              onTap: () => context.push(
                '/music/playlists/${Uri.encodeComponent(item.id)}',
              ),
            );
          },
        ),
      ],
    );
    return SliverMainAxisGroup(
      slivers: [
        if (playlists.isLoading)
          const _ProfilePart(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: BetaActivityIndicator(),
            ),
          ),
        if (playlists.hasError)
          _ProfilePart(
            child: EditorialEmpty(
              '歌单暂时无法加载',
              onRetry: () => ref.invalidate(playlistsProvider),
            ),
          ),
        group('创建的歌单', owned),
        group('收藏的歌单', saved),
      ],
    );
  }
}
