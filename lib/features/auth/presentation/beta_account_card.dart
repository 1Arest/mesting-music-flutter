import '../../music_platform/qishui/qishui_providers.dart';
import '../../music_platform/presentation/platform_login_options_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/platform_profile_provider.dart';
import '../../music_platform/presentation/platform_account_page.dart';
import '../../music_platform/presentation/platform_avatar.dart';
import '../../music_platform/presentation/platform_profile_edit_page.dart';
import '../auth_providers.dart';
import 'beta_login_navigation.dart';
import 'beta_welcome_page.dart';
import '../../music_platform/netease/netease_membership_page.dart';
import '../../themes/music_typography.dart';

/// Shared account presentation; never creates a second credential store or
/// advertises unavailable Mesting registration/social capabilities.
class BetaAccountCard extends ConsumerWidget {
  const BetaAccountCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(platformAccountProvider).value;
    final user = ref.watch(currentUserProvider);
    final profile = platform == null
        ? null
        : ref.watch(platformProfileProvider).value;
    final signedIn = platform != null || user != null;
    final name =
        profile?.nickname ?? platform?.nickname ?? user?.nickname ?? '';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('beta11-unified-account'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                button: platform != null,
                label: ref.watch(usesQishuiProvider) ? '查看账号资料' : '编辑个人资料',
                child: GestureDetector(
                  key: const ValueKey('platform-profile-edit-entry'),
                  onTap: platform == null
                      ? null
                      : () => Navigator.of(context, rootNavigator: true).push(
                          betaEntryRoute<void>(const PlatformProfileEditPage()),
                        ),
                  child: PlatformAvatar(
                    url:
                        profile?.avatarUrl ??
                        platform?.avatarUrl ??
                        user?.avatarUrl ??
                        '',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signedIn
                          ? (name.isEmpty ? '当前账号' : name)
                          : '登录 Mesting Music',
                      style: TextStyle(
                        fontSize: MusicTypography.sectionTitleSize,
                        fontWeight: MusicTypography.titleWeight,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const NeteaseLocalSvipBadge(),
                    Text(
                      signedIn
                          ? (platform != null
                                ? '${platform.platformLabel}账号 · 已登录'
                                : 'Mesting 账号 · 已登录')
                          : '登录后同步喜欢的音乐与歌单',
                      style: TextStyle(
                        fontSize: MusicTypography.footnoteSize,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (platform != null) ...[
            BetaGlassButton(
              onPressed: () => Navigator.of(
                context,
                rootNavigator: true,
              ).push(betaEntryRoute<void>(const MusicPlatformSwitchPage())),
              child: const Text('切换音乐平台'),
            ),
            const SizedBox(height: 10),
            BetaGlassButton(
              accent: true,
              onPressed: () => Navigator.of(
                context,
                rootNavigator: true,
              ).push(betaEntryRoute<void>(const PlatformProfileEditPage())),
              child: Text(ref.watch(usesQishuiProvider) ? '查看账号资料' : '编辑个人资料'),
            ),
            const SizedBox(height: 10),
          ],
          BetaGlassButton(
            onPressed: () {
              if (platform != null) {
                Navigator.of(
                  context,
                ).push(betaEntryRoute<void>(const PlatformAccountPage()));
              } else if (user != null) {
                // Existing Mesting sessions remain intact; their logout stays in settings.
                final router = Navigator.of(context);
                router.push(betaEntryRoute<void>(const PlatformAccountPage()));
              } else {
                openBetaLogin(context);
              }
            },
            accent: !signedIn,
            child: Text(signedIn ? '管理当前账号' : '立即登录'),
          ),
        ],
      ),
    );
  }
}
