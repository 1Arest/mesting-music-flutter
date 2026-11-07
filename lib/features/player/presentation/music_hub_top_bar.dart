import '../../../shared/widgets/artwork_scroll_frontier.dart';
import 'package:flutter/material.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../music_platform/platform_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../legal/presentation/disclaimer_dialog.dart';
import '../../themes/music_theme_tokens.dart';
import 'music_page_transition.dart';
import '../../themes/music_typography.dart';

class MusicHubTopBar extends StatelessWidget {
  const MusicHubTopBar({
    required this.title,
    required this.subtitle,
    this.showBack = false,
    this.onBack,
    this.animateTitle = false,
    this.titleKey,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final bool animateTitle;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Row(
      children: [
        if (DistributionChannel.isBeta && showBack)
          BetaGlassBackButton(onPressed: onBack)
        else
          _TopAction(
            tooltip: showBack ? '返回' : '个人中心与设置',
            icon: showBack
                ? Icons.arrow_back_ios_new_rounded
                : Icons.menu_rounded,
            onTap: showBack
                ? onBack ?? Navigator.of(context).maybePop
                : () => showMusicHubPanel(context),
          ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBarTitle(
                title: title,
                titleKey: titleKey,
                animate: animateTitle,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 13),
        _TopAction(
          tooltip: '搜索音乐',
          icon: Icons.search_rounded,
          onTap: () => context.push(
            '/music/search',
            extra: const MusicPageTransitionIntent.forward(),
          ),
        ),
      ],
    );
  }
}

class _TopBarTitle extends StatelessWidget {
  const _TopBarTitle({
    required this.title,
    required this.titleKey,
    required this.animate,
  });

  final String title;
  final Key? titleKey;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      key: titleKey,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.musicThemeTokens.textPrimary,
        fontSize: MusicTypography.headingSize,
        height: 1.12,
        fontWeight: MusicTypography.titleWeight,
      ),
    );
    if (!animate) return text;
    return ClipRect(
      child: AnimatedSwitcher(
        key: const ValueKey('music-hub-title-switcher'),
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutCubic,
        layoutBuilder: (current, previous) =>
            current ?? const SizedBox.shrink(),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .18),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: text,
      ),
    );
  }
}

class _TopAction extends StatefulWidget {
  const _TopAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_TopAction> createState() => _TopActionState();
}

class _TopActionState extends State<_TopAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Keep the top actions coupled to the live page background. An opaque
    // purple-black base is conspicuous on the classic pure-black theme and
    // also fights illustrated themes, while this neutral translucent layer
    // retains the glass boundary without introducing a blur pass.
    final surface = dark
        ? Colors.white.withValues(alpha: .07)
        : Colors.black.withValues(alpha: .035);
    final pressedSurface = dark
        ? Colors.white.withValues(alpha: .045)
        : Colors.black.withValues(alpha: .06);
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? .95 : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: RepaintBoundary(
              child: AnimatedContainer(
                key: ValueKey('textured-solid-${widget.tooltip}'),
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _pressed ? pressedSurface : surface,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: .14)
                        : Colors.black.withValues(alpha: .09),
                    width: .9,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _pressed
                            ? (dark ? .08 : .035)
                            : (dark ? .18 : .08),
                      ),
                      blurRadius: _pressed ? 3 : 8,
                      offset: Offset(0, _pressed ? 1 : 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(widget.icon, color: tokens.textPrimary, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showMusicHubPanel(BuildContext pageContext) {
  final reduceMotion = MediaQuery.disableAnimationsOf(pageContext);
  return showGeneralDialog<void>(
    context: pageContext,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: '关闭个人中心',
    barrierColor: const Color(0x730D0B12),
    transitionDuration: reduceMotion
        ? Duration.zero
        : musicHubPanelTransitionDuration,
    pageBuilder: (dialogContext, animation, secondaryAnimation) => Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: .86,
        child: _MusicHubPanel(pageContext: pageContext),
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        reduceMotion
        ? child
        : MusicHubPanelTransition(animation: animation, child: child),
  );
}

class _MusicHubPanel extends ConsumerStatefulWidget {
  const _MusicHubPanel({required this.pageContext});

  final BuildContext pageContext;

  @override
  ConsumerState<_MusicHubPanel> createState() => _MusicHubPanelState();
}

class _MusicHubPanelState extends ConsumerState<_MusicHubPanel> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final account = ref.watch(platformAccountProvider);
    final platform = account.value;
    final accountState = platform != null
        ? _PanelAccountState.signedIn
        : account.isLoading
        ? _PanelAccountState.restoring
        : account.hasError
        ? _PanelAccountState.unavailable
        : _PanelAccountState.signedOut;
    final size = MediaQuery.sizeOf(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 360, minHeight: size.height),
      child: LiquidGlassSurface(
        key: liquidGlassSidePanelSurfaceKey,
        blurSigma: 0,
        showShadow: false,
        showDecorativeGlow: false,
        surfaceColorBuilder: (surfaceContext) =>
            surfaceContext.musicThemeTokens.glassStrong.withValues(alpha: 1),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            right: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'MESTING SPACE',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: MusicTypography.smallCaptionSize,
                            fontWeight: MusicTypography.bodyWeight,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _AccountCard(
                    key: ValueKey('music-hub-account-${accountState.name}'),
                    nickname: switch (accountState) {
                      _PanelAccountState.restoring => '正在恢复账号',
                      _PanelAccountState.unavailable => '账号状态暂不可用',
                      _PanelAccountState.signedOut => '登录后收藏你的音乐',
                      _PanelAccountState.signedIn =>
                        platform!.nickname.isEmpty
                            ? platform.platformLabel
                            : platform.nickname,
                    },
                    caption: switch (accountState) {
                      _PanelAccountState.restoring => '正在读取本机登录状态',
                      _PanelAccountState.unavailable => '请稍后重新打开侧边菜单',
                      _PanelAccountState.signedOut => '同步收藏、歌单和个人资料',
                      _PanelAccountState.signedIn =>
                        '${platform!.platformLabel}账号 · 云端收藏与歌单',
                    },
                    avatarUrl: platform != null
                        ? (ref
                                  .watch(platformProfileProvider)
                                  .value
                                  ?.avatarUrl ??
                              platform.avatarUrl)
                        : null,
                    fallbackIcon: switch (accountState) {
                      _PanelAccountState.restoring =>
                        Icons.person_search_rounded,
                      _PanelAccountState.unavailable => Icons.cloud_off_rounded,
                      _PanelAccountState.signedOut => Icons.music_note_rounded,
                      _PanelAccountState.signedIn => Icons.person_rounded,
                    },
                  ),
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ArtworkFrontierPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _PanelLabel('应用设置'),
                        _PanelSection(
                          children: [
                            _PanelTile(
                              icon: Icons.tune_rounded,
                              title: '设置',
                              subtitle: '主题、账号、安全与云端',
                              highlighted: true,
                              onTap: () => _openSettings(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const _PanelLabel('关于应用'),
                        _PanelSection(
                          children: [
                            _PanelTile(
                              key: const ValueKey('music-hub-legal-documents'),
                              icon: Icons.policy_outlined,
                              title: '用户协议与隐私政策',
                              subtitle: '服务规则、数据处理与个人权利',
                              onTap: () => _openLegalDocuments(context),
                            ),
                            _PanelTile(
                              icon: Icons.policy_outlined,
                              title: '免责声明',
                              subtitle: '在线音乐、版权与账号数据说明',
                              onTap: () => _openDisclaimer(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            platform != null
                                ? '当前使用酷狗账号，收藏和歌单与酷狗云端同步。'
                                : '主题、账号绑定与登录安全已统一放在“设置”，收藏和歌单仍在“我的”页面。',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: MusicTypography.smallCaptionSize,
                              height: 1.55,
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
    );
  }

  Future<void> _openSettings(BuildContext panelContext) {
    return _dismissPanelThenOpenRoute(panelContext, '/music/settings');
  }

  Future<void> _openLegalDocuments(BuildContext panelContext) {
    return _dismissPanelThenOpenRoute(panelContext, '/legal');
  }

  Future<void> _openDisclaimer(BuildContext panelContext) async {
    final pageContext = widget.pageContext;
    if (!await _dismissPanelThenWait(panelContext)) return;
    if (!pageContext.mounted) return;
    await showDisclaimerDialog(pageContext, useMusicHubPanelTransition: true);
  }

  Future<void> _dismissPanelThenOpenRoute(
    BuildContext panelContext,
    String location,
  ) async {
    final pageContext = widget.pageContext;
    if (!await _dismissPanelThenWait(panelContext)) return;
    if (!pageContext.mounted) return;
    pageContext.push(
      location,
      extra: const MusicPageTransitionIntent.fromMusicHubPanel(),
    );
  }

  Future<bool> _dismissPanelThenWait(BuildContext panelContext) async {
    final panelRoute = ModalRoute.of(panelContext);
    // The panel is presented on the root navigator. Pop that same navigator,
    // then wait for its reverse transition plus two committed frames before
    // mounting the messages route. One frame is not enough on some Android
    // compositor paths: the removed dialog layer can still be retained while
    // the new page starts its own transition.
    Navigator.of(panelContext, rootNavigator: true).pop();
    await panelRoute?.completed;
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    return widget.pageContext.mounted;
  }
}

enum _PanelAccountState { restoring, signedIn, signedOut, unavailable }

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.nickname,
    required this.caption,
    required this.avatarUrl,
    required this.fallbackIcon,
    super.key,
  });

  final String nickname;
  final String caption;
  final String? avatarUrl;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: .18), tokens.glassSubtle],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tokens.borderStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            ClipOval(
              child: avatarUrl?.isNotEmpty == true
                  ? ArtworkImage(
                      uri: avatarUrl!,
                      width: 52,
                      height: 52,
                      retryOnNetworkError: true,
                    )
                  : Container(
                      width: 52,
                      height: 52,
                      color: accent.withValues(alpha: .17),
                      child: Icon(fallbackIcon, color: accent, size: 25),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: MusicTypography.subheadlineSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: MusicTypography.smallCaptionSize,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        text,
        style: TextStyle(
          color: context.musicThemeTokens.textMuted,
          fontSize: MusicTypography.smallCaptionSize,
          fontWeight: MusicTypography.bodyWeight,
          letterSpacing: .8,
        ),
      ),
    );
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.glassSubtle,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tokens.border),
      ),
      child: Column(children: children),
    );
  }
}

class _PanelTile extends StatelessWidget {
  const _PanelTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                color: highlighted
                    ? accent.withValues(alpha: .16)
                    : tokens.glass,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                color: highlighted ? accent : tokens.textSecondary,
                size: 19,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: highlighted ? accent : tokens.textPrimary,
                      fontSize: MusicTypography.footnoteSize,
                      fontWeight: MusicTypography.bodyWeight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: MusicTypography.smallCaptionSize,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: tokens.textMuted,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}
