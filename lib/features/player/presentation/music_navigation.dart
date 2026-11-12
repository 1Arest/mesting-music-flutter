import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../themes/mesting_palette.dart';
import '../../themes/music_theme_tokens.dart';
import 'music_page_transition.dart';
import '../../experience/presentation/beta_bottom_bar.dart';
import '../../../core/platform/distribution_channel.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../themes/music_typography.dart';

const double musicBottomNavigationContentHeight = 64;
const double betaMusicBottomNavigationContentHeight = 84;
const double musicNavigationRailWidth = 88;
const List<BoxShadow> musicBottomNavigationOuterShadows = <BoxShadow>[];

Color musicBottomNavigationSelectedColorFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? MestingPalette.heartBright
    : MestingPalette.heart;

int musicBottomNavigationIndexForLocation(String location) {
  final uri = Uri.parse(location);
  final view = uri.queryParameters['view'];
  if (!DistributionChannel.isBeta &&
      (view == 'playlists' || uri.path.startsWith('/music/playlists'))) {
    return 3;
  }

  if (uri.path.startsWith('/profile') || uri.path.startsWith('/social')) {
    return 3;
  }
  if (view == 'favorites' ||
      view == 'playlists' ||
      uri.path.startsWith('/music/library') ||
      uri.path.startsWith('/music/playlists') ||
      uri.path == '/music/replay') {
    return 2;
  }
  if (uri.path == '/music/recommend' || view == 'daily') return 0;
  return 1;
}

/// Logical parent for a restored Beta detail without a real route underneath.
/// A pushed page always pops its actual history first; this policy only handles
/// the final shell route, where Android would otherwise return to the launcher.
String? betaMusicBackDestination(String location, {required String tabRoot}) {
  final uri = Uri.parse(location);
  final alias = {
    '/music/view',
    '/music/library/view',
    '/music/recommend/view',
    '/profile/view',
  }.contains(uri.path);
  final path = alias
      ? uri.path.substring(0, uri.path.length - '/view'.length)
      : uri.path;
  if (path == '/music') {
    return switch (uri.queryParameters['view']) {
      'daily' => '/music/recommend',
      'favorites' || 'playlists' => '/profile',
      _ => alias ? '/music' : null,
    };
  }
  if (path == '/music/library') {
    return !alias && uri.queryParameters['view'] == null
        ? null
        : '/music/library';
  }
  if (path == '/music/recommend' || path == '/profile') {
    return alias ? path : null;
  }
  if (path.startsWith('/legal')) return '/music/settings';
  if (path == '/profile/delete-account') return '/music/settings';
  if (path.startsWith('/profile/')) return '/profile';
  if (path.startsWith('/social/saved-messages/')) {
    return '/social/saved-messages';
  }
  if (path.startsWith('/social/chat/') || path.startsWith('/social/users/')) {
    return '/social/messages';
  }
  if (path.startsWith('/social')) return '/profile';
  if (path.startsWith('/music/playlists/')) return '/music?view=playlists';
  return switch (path) {
    '/music/search' || '/music/settings' || '/player' => '/music/recommend',
    '/music/replay' => '/music/library',
    '/music/queue' => '/music',
    _ => tabRoot,
  };
}

class MusicBottomNavigation extends ConsumerWidget {
  const MusicBottomNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final location = GoRouterState.of(context).uri.toString();
    final selected = musicBottomNavigationIndexForLocation(location);

    if (DistributionChannel.isBeta) {
      return BetaMusicBottomBar(
        selectedIndex: selected,
        onTabSelected: (index) =>
            _goToMusicTab(context, selected, index, betaMusicRoutes[index]),
        searchConfig: GlassSearchBarConfig(
          hintText: '搜索歌曲、歌手',
          onSearchToggle: (active) {
            if (active) context.push('/music/search');
          },
        ),
      );
    }

    return SizedBox(
      height: musicBottomNavigationContentHeight + bottomInset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const [Color(0xEB17131F), Color(0xF5100D16)]
                    : const [Color(0xECFFFFFF), Color(0xF5FFFDF9)],
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: dark ? .13 : .58),
                ),
              ),
              boxShadow: musicBottomNavigationOuterShadows,
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _LiquidGlassPainter(dark: dark, accent: accent),
            ),
          ),
          Padding(
            // 系统手势区即为安全距离，导航内容不额外抬高。
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Row(
              children: [
                _BottomNavItem(
                  label: '推荐',
                  icon: Icons.auto_awesome_rounded,
                  active: selected == 0,
                  onTap: () =>
                      _goToMusicTab(context, selected, 0, '/music/recommend'),
                  tokens: tokens,
                ),
                _BottomNavItem(
                  label: '发现音乐',
                  icon: Icons.music_note_rounded,
                  active: selected == 1,
                  onTap: () => _goToMusicTab(context, selected, 1, '/music'),
                  tokens: tokens,
                ),
                _BottomNavItem(
                  label: '我的喜欢',
                  icon: Icons.favorite_rounded,
                  active: selected == 2,
                  onTap: () => _goToMusicTab(
                    context,
                    selected,
                    2,
                    '/music?view=favorites',
                  ),
                  tokens: tokens,
                ),
                _BottomNavItem(
                  label: '我的',
                  icon: Icons.person_rounded,
                  active: selected == 3,
                  onTap: () => _goToMusicTab(context, selected, 3, '/profile'),
                  tokens: tokens,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MusicNavigationRail extends ConsumerWidget {
  const MusicNavigationRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.musicThemeTokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final location = GoRouterState.of(context).uri.toString();
    final selected = musicBottomNavigationIndexForLocation(location);

    return SizedBox(
      key: const ValueKey('music-navigation-rail'),
      width: musicNavigationRailWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xF014111C), Color(0xF50E0C14)]
                : const [Color(0xF5FFFFFF), Color(0xF2FFF9F7)],
          ),
          border: Border(
            right: BorderSide(
              color: Colors.white.withValues(alpha: dark ? .12 : .62),
            ),
          ),
        ),
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              const SizedBox(height: 18),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: .96),
                      accent.withValues(alpha: .62),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: dark ? .24 : .18),
                      blurRadius: 18,
                      spreadRadius: -3,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const Spacer(),
              _RailNavItem(
                label: DistributionChannel.isBeta ? '首页' : '推荐',
                icon: DistributionChannel.isBeta
                    ? Icons.home_rounded
                    : Icons.auto_awesome_rounded,
                active: selected == 0,
                onTap: () =>
                    _goToMusicTab(context, selected, 0, '/music/recommend'),
                tokens: tokens,
              ),
              _RailNavItem(
                label: '发现',
                icon: DistributionChannel.isBeta
                    ? Icons.grid_view_rounded
                    : Icons.music_note_rounded,
                active: selected == 1,
                onTap: () => _goToMusicTab(context, selected, 1, '/music'),
                tokens: tokens,
              ),
              _RailNavItem(
                label: DistributionChannel.isBeta ? '音乐库' : '喜欢',
                icon: DistributionChannel.isBeta
                    ? Icons.library_music_rounded
                    : Icons.favorite_rounded,
                active: selected == 2,
                onTap: () => _goToMusicTab(
                  context,
                  selected,
                  2,
                  DistributionChannel.isBeta
                      ? '/music/library'
                      : '/music?view=favorites',
                ),
                tokens: tokens,
              ),
              _RailNavItem(
                label: '我的',
                icon: Icons.person_rounded,
                active: selected == 3,
                onTap: () => _goToMusicTab(context, selected, 3, '/profile'),
                tokens: tokens,
              ),
              const Spacer(),
              if (DistributionChannel.isBeta)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: IconButton.filledTonal(
                    tooltip: '搜索歌曲',
                    onPressed: () => context.push('/music/search'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(52),
                      foregroundColor: tokens.textPrimary,
                      backgroundColor: accent.withValues(alpha: .12),
                    ),
                    icon: const Icon(Icons.search_rounded),
                  ),
                ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

void _goToMusicTab(
  BuildContext context,
  int current,
  int target,
  String location,
) {
  if (current == target) return;
  context.go(
    location,
    extra: MusicPageTransitionIntent.betweenTabs(current, target),
  );
}

class _RailNavItem extends StatelessWidget {
  const _RailNavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final MusicThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final selectedColor = DistributionChannel.isBeta
        ? Theme.of(context).colorScheme.primary
        : musicBottomNavigationSelectedColorFor(brightness);
    final color = active ? selectedColor : tokens.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            key: ValueKey('music-navigation-rail-item-$label'),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: 68,
            height: 62,
            decoration: BoxDecoration(
              color: active
                  ? selectedColor.withValues(
                      alpha: brightness == Brightness.dark ? .16 : .11,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: active
                  ? Border.all(
                      color: selectedColor.withValues(alpha: .25),
                      width: .8,
                    )
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: MusicTypography.smallCaptionSize,
                    fontWeight: MusicTypography.bodyWeight,
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

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final MusicThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final selectedColor = musicBottomNavigationSelectedColorFor(brightness);
    final color = active ? selectedColor : tokens.textMuted;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: active ? 1 : .96,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                key: ValueKey('music-bottom-navigation-indicator-$label'),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                width: active ? 44 : 34,
                height: 30,
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                style: TextStyle(
                  color: color,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassPainter extends CustomPainter {
  const _LiquidGlassPainter({required this.dark, required this.accent});

  final bool dark;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: dark ? .035 : .16),
          accent.withValues(alpha: dark ? .055 : .045),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0, .48, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sheen);

    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = Colors.white.withValues(alpha: dark ? .08 : .32);
    canvas.drawLine(
      const Offset(16, 1.5),
      Offset(size.width - 16, 1.5),
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.accent != accent;
}
