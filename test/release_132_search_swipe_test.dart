import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_category_search.dart';
import 'package:mesting_music/features/music_platform/domain/platform_search_user.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/platform_category_search_providers.dart';
import 'package:mesting_music/features/search/presentation/beta_category_search_results.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/shared/widgets/beta_swipe_pages.dart';
import 'support/pump_artwork_ready.dart';
import 'support/release_132_qa.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => throw StateError('No network in host tests');
}

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

class _Search extends MusicSearchController {
  @override
  MusicSearchState build() => const MusicSearchState(query: '薛之谦');
  void query(String value) => state = MusicSearchState(query: value);
}

class _Repository extends PlatformCategorySearchRepository {
  _Repository()
    : super(
        MusicPlatformApi(
          server: _Server(),
          client: MockClient(
            (_) async => throw StateError('No HTTP in swipe fixture'),
          ),
        ),
      );
  final calls = <PlatformSearchKind>[];
  @override
  Future<PlatformCategoryPage> search(
    String query,
    PlatformSearchKind kind, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    calls.add(kind);
    const cover = 'assets/images/theme_playlists/shinchan/cover-01.jpg';
    return PlatformCategoryPage(
      [
        for (var i = 0; i < 32; i++)
          PlatformSearchHit(
            kind: kind,
            id: '${kind.name}-$i',
            title: '$query · ${kind.label} $i',
            subtitle: '搜索结果',
            cover: cover,
            user: kind == PlatformSearchKind.users
                ? PlatformSearchUser(
                    id: 'user-$i',
                    nickname: '$query的听众 $i',
                    avatar: cover,
                  )
                : null,
          ),
      ],
      32,
      false,
    );
  }
}

void main() {
  setUpAll(initialize132QA);
  Future<(ProviderContainer, _Repository)> mount(
    WidgetTester tester, {
    required bool netease,
    bool narrow = false,
  }) async {
    tester.view.physicalSize = Size(narrow ? 320 : 390, narrow ? 650 : 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final repo = _Repository();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        platformAccountProvider.overrideWith(_Account.new),
        usesNeteaseProvider.overrideWithValue(netease),
        musicSearchControllerProvider.overrideWith(_Search.new),
        platformCategorySearchRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    await c.read(platformAccountProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: RepaintBoundary(
          key: capture132Key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme132(netease),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(narrow ? 1.3 : 1)),
              child: child!,
            ),
            home: const Scaffold(
              body: SafeArea(child: BetaCategorySearchResults()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (c, repo);
  }

  Future<void> finish(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await pumpArtworkReady(tester);
  }

  for (final netease in [false, true]) {
    testWidgets(
      'search swipes both ways, taps sync, retained scroll and lazy reads netease=$netease',
      (tester) async {
        final (c, repo) = await mount(tester, netease: netease);
        expect(repo.calls, isEmpty);
        final pager = find.byType(PageView);
        await tester.drag(pager, const Offset(-310, 0));
        await finish(tester);
        expect(
          c.read(categorySearchProvider).selected,
          PlatformSearchKind.albums,
        );
        expect(repo.calls, [PlatformSearchKind.albums]);
        final albumScroll = tester
            .widgetList<CustomScrollView>(find.byType(CustomScrollView))
            .singleWhere(
              (w) => w.key == const PageStorageKey('category-薛之谦-albums'),
            )
            .controller!;
        albumScroll.jumpTo(480);
        await finish(tester);
        await tester.drag(pager, const Offset(-310, 0));
        await finish(tester);
        expect(
          c.read(categorySearchProvider).selected,
          PlatformSearchKind.artists,
        );
        await capture132UI(
          tester,
          'search-${netease ? 'netease-dark' : 'kugou-light'}-artists',
        );
        await tester.drag(pager, const Offset(310, 0));
        await finish(tester);
        expect(
          c.read(categorySearchProvider).selected,
          PlatformSearchKind.albums,
        );
        expect(albumScroll.offset, closeTo(480, 1));
        expect(
          repo.calls.where((k) => k == PlatformSearchKind.albums).length,
          1,
        );
        // Jump across categories must not start searches for intermediate pages.
        await tester.tap(
          find.byKey(ValueKey('search-kind-${netease ? 'users' : 'lyrics'}')),
        );
        await finish(tester);
        expect(repo.calls, [
          PlatformSearchKind.albums,
          PlatformSearchKind.artists,
          netease ? PlatformSearchKind.users : PlatformSearchKind.lyrics,
        ]);
        expect(
          tester.widget<PageView>(pager).controller!.page,
          closeTo(netease ? 5 : 4, .001),
        );
        await capture132UI(
          tester,
          'search-${netease ? 'netease-dark-users' : 'kugou-light-lyrics'}',
        );
        await tester.drag(pager, const Offset(-300, 0));
        await finish(tester);
        expect(
          tester.widget<PageView>(pager).controller!.page,
          closeTo(netease ? 5 : 4, .001),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'rapid category reversal and query reset retain the latest intent',
    (tester) async {
      final (c, _) = await mount(tester, netease: true, narrow: true);
      await tester.tap(find.byKey(const ValueKey('search-kind-users')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(const ValueKey('search-kind-albums')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.byKey(const ValueKey('search-kind-artists')));
      await finish(tester);
      expect(
        c.read(categorySearchProvider).selected,
        PlatformSearchKind.artists,
      );
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        closeTo(2, .001),
      );
      await capture132UI(tester, 'search-narrow-dark-large-text');
      (c.read(musicSearchControllerProvider.notifier) as _Search).query('新关键词');
      await finish(tester);
      final scroll = tester
          .widgetList<CustomScrollView>(find.byType(CustomScrollView))
          .singleWhere(
            (w) => w.key == const PageStorageKey('category-新关键词-artists'),
          )
          .controller!;
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('shared pager click can reverse to an intermediate live page', (
    tester,
  ) async {
    var index = 0;
    late StateSetter update;
    final reported = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return BetaSwipePages(
                index: index,
                length: 6,
                onChanged: (value) {
                  reported.add(value);
                  update(() => index = value);
                },
                itemBuilder: (_, i) => Center(child: Text('page $i')),
              );
            },
          ),
        ),
      ),
    );
    update(() => index = 5);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final live = controller.page!.round();
    update(() => index = live);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(live.toDouble(), .001));
    expect(
      reported,
      isEmpty,
      reason: 'programmatic intermediate pages are not user selection',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
