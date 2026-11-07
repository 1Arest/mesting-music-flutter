import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/discover/data/curated_playlists.dart';
import 'package:mesting_music/features/discover/presentation/discover_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('发现歌单底部为胶囊播放器和导航栏保留完整空间', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: DiscoverPage())),
      ),
    );
    await tester.pump();

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final clearanceSliver = scrollView.slivers.last as SliverToBoxAdapter;
    final clearance = clearanceSliver.child! as SizedBox;
    expect(clearance.key, const ValueKey('discover-bottom-clearance'));
    expect(clearance.height, discoverPageBottomClearance);
    expect(discoverPageBottomClearance, greaterThanOrEqualTo(160));
    expect(tester.takeException(), isNull);
  });

  testWidgets('从发现页进入任意歌单会保留系统返回栈', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final firstPlaylist = curatedPlaylists.first;
    final router = GoRouter(
      initialLocation: '/music/discover',
      routes: [
        GoRoute(
          path: '/music/discover',
          builder: (_, _) => const Scaffold(body: DiscoverPage()),
        ),
        GoRoute(
          path: '/music/discover/:playlistId',
          builder: (_, state) => Scaffold(
            body: Text('detail=${state.pathParameters['playlistId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(firstPlaylist.name).first);
    await tester.pumpAndSettle();

    expect(find.text('detail=${firstPlaylist.id}'), findsOneWidget);
    expect(router.canPop(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('发现歌单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
