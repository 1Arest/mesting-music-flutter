import 'dart:io';
import 'support/release_147_qa.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/library/data/favorite_track_window.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/experience/presentation/music_library_page.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/models/track_page.dart';
import 'package:mesting_music/shared/widgets/music_list_footer.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_recommendations_page.dart';
import 'support/personal_profile_fixture.dart';
import 'release_146_ui_test.dart'
    show capture, capture146Builder, theme146, shot, ready146;

class _Library extends LibraryRepository {
  _Library(super.db) : super(ownerId: 'netease:7001');
  final requests = <(int, String)>[];
  final tracks = List.generate(
    3000,
    (i) => Track(
      id: 'netease_${8000 + i}',
      title: '测试歌曲 $i',
      artist: '收藏样本',
      album: '合成数据',
      duration: const Duration(minutes: 3),
      audioAsset: '',
      coverAsset: profileFixtureCover,
      lyricsAsset: '',
    ),
  );
  @override
  Stream<TrackPage> watchFavoritePreview() => Stream.fromFuture(favoritePage());
  @override
  Future<TrackPage> favoritePage({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async {
    requests.add((offset, query));
    final selected = query.isEmpty
        ? tracks
        : tracks.where((track) => track.title.contains(query)).toList();
    final end = (offset + limit).clamp(offset, selected.length);
    return TrackPage(
      selected.sublist(offset, end),
      offset: offset,
      nextOffset: end,
      total: selected.length,
      hasMore: end < selected.length,
    );
  }

  @override
  Future<Set<String>> favoriteIds() async =>
      tracks.map((track) => track.id).toSet();
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (capture) {
      await load147IconFonts();
      for (final family in [
        'MestingQA146',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'sans-serif',
      ]) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  for (final dark in [false, true]) {
    testWidgets(
      '3000 favorites page/search/membership use the complete owner collection dark=$dark',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final repository = _Library(db);
        final window = FavoriteTrackWindow(repository);
        final fixture = await PersonalProfileFixture.create(
          browsingLibrary: repository,
          favoritesWindow: window,
        );
        addTearDown(() async {
          await fixture.dispose();
          window.dispose();
          await db.close();
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme146(dark),
              builder: capture146Builder,
              home: const Scaffold(body: MusicLibraryPage(view: 'favorites')),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await ready146(tester);
        expect(window.items, hasLength(30));
        expect(repository.requests, [(0, '')]);
        expect(find.text('3000 首歌曲'), findsOneWidget);
        expect(find.byType(EditorialTrackRow).evaluate().length, lessThan(25));
        expect(find.byType(MusicListEnd), findsNothing);
        await tester.runAsync(
          () => fixture.container.read(completeFavoriteIdsProvider.future),
        );
        expect(
          fixture.container.read(favoriteTrackIdsProvider),
          contains('netease_10999'),
        );
        await shot(tester, 'paged-favorites-${dark ? 'dark' : 'light'}');
        await tester.tap(find.byTooltip('搜索我的喜欢'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), '2999');
        await tester.pump(const Duration(milliseconds: 240));
        await tester.pump();
        await ready146(tester);
        expect(find.text('测试歌曲 2999'), findsOneWidget);
        expect(find.text('测试歌曲 0'), findsNothing);
        expect(repository.requests.last, (0, '2999'));
        expect(window.items, hasLength(30));
        await shot(tester, 'paged-favorites-search-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'fixed new-song response reveals thirty rows at a time dark=$dark',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final repository = _Library(db);
        final fixture = await PersonalProfileFixture.create(
          extraOverrides: [
            platformNewSongsProvider.overrideWith(
              (ref) async => repository.tracks,
            ),
          ],
        );
        addTearDown(() async {
          await fixture.dispose();
          await db.close();
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme146(dark),
              builder: capture146Builder,
              home: const Scaffold(
                body: PlatformRecommendationDetail(
                  title: '新歌速递',
                  newSongs: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await ready146(tester);
        expect(
          tester
              .widget<ListView>(find.byType(ListView))
              .childrenDelegate
              .estimatedChildCount,
          31,
        );
        expect(find.byType(MusicListEnd), findsNothing);
        await shot(tester, 'new-songs-first-window-${dark ? 'dark' : 'light'}');
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent - 50);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await ready146(tester);
        await tester.pump();
        expect(
          tester
              .widget<ListView>(find.byType(ListView))
              .childrenDelegate
              .estimatedChildCount,
          greaterThan(31),
        );
        expect(repository.tracks, hasLength(3000));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
