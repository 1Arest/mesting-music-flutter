import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/features/player/presentation/music_navigation.dart';
import 'package:mesting_music/features/player/presentation/music_shell.dart';
import 'package:mesting_music/features/profile/presentation/profile_page.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';

void main() {
  test('bottom navigation keeps a compact accessible content height', () {
    expect(musicBottomNavigationContentHeight, 64);
    expect(
      musicBottomNavigationContentHeight,
      greaterThanOrEqualTo(kMinInteractiveDimension),
    );
  });

  test('playlist routes follow the active channel navigation contract', () {
    final playlistTab = DistributionChannel.isBeta ? 2 : 3;
    expect(musicBottomNavigationIndexForLocation('/profile'), 3);
    expect(musicBottomNavigationIndexForLocation('/profile/account'), 3);
    expect(musicBottomNavigationIndexForLocation('/social?tab=1'), 3);
    expect(musicBottomNavigationIndexForLocation('/social/users/friend'), 3);
    expect(musicBottomNavigationIndexForLocation('/music?view=playlists'), playlistTab);
    expect(musicBottomNavigationIndexForLocation('/music/playlists'), playlistTab);
    expect(
      musicBottomNavigationIndexForLocation('/music/playlists/playlist-1'),
      playlistTab,
    );
    expect(musicBottomNavigationIndexForLocation('/music?view=favorites'), 2);
    expect(musicBottomNavigationIndexForLocation('/music/recommend'), 0);
    expect(musicBottomNavigationIndexForLocation('/music'), 1);
  });

  test(
    'profile media previews hide persistent player and navigation chrome',
    () {
      expect(
        musicShellUsesImmersiveProfileMediaOverlay('/profile/avatar'),
        isTrue,
      );
      expect(
        musicShellUsesImmersiveProfileMediaOverlay('/profile/background'),
        isTrue,
      );
      expect(
        musicShellUsesImmersiveProfileMediaOverlay(
          '/profile/background?source=profile',
        ),
        isTrue,
      );
      expect(musicShellUsesImmersiveProfileMediaOverlay('/profile'), isFalse);
      expect(
        musicShellUsesImmersiveProfileMediaOverlay('/profile/edit'),
        isFalse,
      );
    },
  );

  testWidgets('opening playlists from profile preserves the back stack', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/profile-probe',
      routes: [
        GoRoute(
          path: '/profile-probe',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => openMyPlaylistsFromProfile(context),
              child: const Text('open playlists'),
            ),
          ),
        ),
        GoRoute(
          path: '/music',
          builder: (_, state) =>
              Scaffold(body: Text('view=${state.uri.queryParameters['view']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open playlists'));
    await tester.pumpAndSettle();

    expect(find.text('view=playlists'), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('open playlists'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile search opens the shared music and user search page', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/profile-probe',
      routes: [
        GoRoute(
          path: '/profile-probe',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => openMusicSearchFromProfile(context),
              child: const Text('open search'),
            ),
          ),
        ),
        GoRoute(
          path: '/music/search',
          builder: (_, _) => const Scaffold(body: Text('shared search')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open search'));
    await tester.pumpAndSettle();

    expect(find.text('shared search'), findsOneWidget);
    expect(router.canPop(), isTrue);
    expect(tester.takeException(), isNull);
  });
}
