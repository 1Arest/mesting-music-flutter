import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/layout/adaptive_layout.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../social/listen_together_providers.dart';
import '../../themes/music_theme_background.dart';
import 'music_navigation.dart';
import 'persistent_mini_player.dart';
import '../../experience/presentation/beta_music_shell.dart';

bool musicShellUsesImmersiveProfileMediaOverlay(String location) {
  final path = Uri.parse(location).path;
  return path == '/profile/avatar' || path == '/profile/background';
}

class MusicShell extends ConsumerStatefulWidget {
  const MusicShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  ConsumerState<MusicShell> createState() => _MusicShellState();
}

class _MusicShellState extends ConsumerState<MusicShell> {
  late int _owner = musicBottomNavigationIndexForLocation(widget.location);

  @override
  void didUpdateWidget(covariant MusicShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This parent survives player/settings/search layouts which unmount the
    // visible glass bar. Content routes must retain their original tab owner.
    _owner = switch (widget.location) {
      '/music/recommend' => 0,
      '/music' => 1,
      '/music/library' => 2,
      '/profile' => 3,
      _ => _owner,
    };
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final child = widget.child;
    ref.watch(listenTogetherControllerProvider);
    final searchOverlay = location.startsWith('/music/search');
    final settingsOverlay = location.startsWith('/music/settings');
    final fullPlayer = location.startsWith('/player');
    final conversationOverlay = location.startsWith('/social/chat/');
    final profileMediaOverlay = musicShellUsesImmersiveProfileMediaOverlay(
      location,
    );
    final pageWidth = MediaQuery.sizeOf(context).width;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final showMiniPlayer =
        !fullPlayer && !settingsOverlay && !conversationOverlay;
    final showNavigation =
        !searchOverlay &&
        !fullPlayer &&
        !settingsOverlay &&
        !conversationOverlay &&
        !profileMediaOverlay;
    if (DistributionChannel.isBeta) {
      return BetaMusicShell(
        location: location,
        navigationOwner: _owner,
        // Beta settings share the persistent music controls. Their hit testing
        // must agree with the visible bar rather than inherit stable's overlay.
        chromeVisible: showNavigation || settingsOverlay || searchOverlay,
        child: child,
      );
    }
    final useNavigationRail =
        showNavigation && mestingUsesNavigationRailForWidth(pageWidth);
    final contentLeft = useNavigationRail ? musicNavigationRailWidth : 0.0;
    final childContent = fullPlayer || profileMediaOverlay
        ? child
        : MestingAdaptiveContentFrame(child: child);
    return MusicThemeBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned(
              left: contentLeft,
              top: 0,
              right: 0,
              bottom: 0,
              child: childContent,
            ),
            if (showMiniPlayer)
              Positioned(
                left: contentLeft + 12,
                right: 12,
                bottom: searchOverlay
                    ? bottomInset + 8
                    : useNavigationRail
                    ? bottomInset + 16
                    : (DistributionChannel.isBeta
                              ? betaMusicBottomNavigationContentHeight
                              : musicBottomNavigationContentHeight) +
                          bottomInset,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: pageWidth >= MestingAdaptiveBreakpoints.medium
                          ? 720
                          : double.infinity,
                    ),
                    child: IgnorePointer(
                      ignoring: profileMediaOverlay,
                      child: AnimatedOpacity(
                        opacity: profileMediaOverlay ? 0 : 1,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: const PersistentMiniPlayer(),
                      ),
                    ),
                  ),
                ),
              ),
            if (useNavigationRail)
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: MusicNavigationRail(),
              ),
            if (showNavigation && !useNavigationRail)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: profileMediaOverlay,
                  child: AnimatedOpacity(
                    opacity: profileMediaOverlay ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: const MusicBottomNavigation(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
