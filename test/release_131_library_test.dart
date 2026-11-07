import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/music_library_page.dart';
import 'package:mesting_music/features/history/listening_history_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_library_sections.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'support/personal_profile_fixture.dart';
import 'support/pump_artwork_ready.dart';

class _KugouAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: '7001',
    token: 'synthetic',
    platform: MusicPlatform.kugou,
  );
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_131')) {
      for (final family in [
        'Roboto',
        'Microsoft YaHei',
        'Noto Sans SC',
        'sans-serif',
      ]) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_131')) return;
    await tester.pump();
    final shot = tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('library-capture')),
        )
        .toImage();
    await tester.runAsync(() async {
      final image = await shot;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = File('.codex-artifacts/2026-11-01-release131/ui/$name.png');
      await path.parent.create(recursive: true);
      await path.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  final raw =
      jsonDecode(
            File('assets/data/netease-full-catalog.json').readAsStringSync(),
          )
          as Map;
  final all = [
    for (final item in raw['entries'] as List)
      NeteaseEndpoint.fromJson(Map<String, dynamic>.from(item as Map)),
  ];

  test(
    'all existing library workflows have a reachable section without losing catalogue capabilities',
    () {
      final library = all
          .where((e) => e.tab == '音乐库' && e.category != '音乐搜索')
          .toList();
      expect(library.length, 47);
      expect(
        library.map((e) => e.category).toSet(),
        neteaseLibraryCategorySections.keys.toSet(),
      );
      expect(
        library.every(
          (e) =>
              neteaseLibrarySectionFor(e.category) !=
              NeteaseLibrarySection.other,
        ),
        true,
      );
      expect(
        neteaseLibrarySectionFor('future supported capability'),
        NeteaseLibrarySection.other,
      );
      final feeds = neteaseLibrarySectionFeeds.values.expand((e) => e).toList();
      expect(feeds.toSet().length, feeds.length);
      expect(feeds.toSet(), {
        NeteaseFeed.likedAlbums,
        NeteaseFeed.likedArtists,
        NeteaseFeed.likedMvs,
        NeteaseFeed.subscribedPodcasts,
        NeteaseFeed.recentSongs,
        NeteaseFeed.recentPlaylists,
        NeteaseFeed.recentAlbums,
        NeteaseFeed.week,
        NeteaseFeed.allTime,
      });
      // Cloud is one category entry; its full five workflows replace duplicate
      // cloud shortcuts without discarding upload/matching/delete capabilities.
      expect(library.where((e) => e.category == '音乐云盘').length, 5);
    },
  );

  for (final sample in [(false, false), (true, false), (true, true)]) {
    final (netease, dark) = sample;
    testWidgets(
      'real library sections retain actions and platform ownership netease=$netease dark=$dark',
      (tester) async {
        tester.view.physicalSize = Size(dark ? 320 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = await PersonalProfileFixture.create(
          accountFactory: netease ? null : _KugouAccount.new,
          extraOverrides: [
            recentPlaybackProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            neteaseCatalogProvider.overrideWith((ref) async => all),
          ],
        );
        final host = BetaBottomSearchHost(
          location: '/music/library',
          openMusicSearch: () {},
        );
        final router = GoRouter(
          initialLocation: '/music/library',
          routes: [
            GoRoute(
              path: '/music/library',
              builder: (_, _) => const Scaffold(body: MusicLibraryPage()),
            ),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp.router(
              theme: buildMestingTheme(
                musicThemePresetById(dark ? 'classic-dark' : 'classic'),
              ),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(dark ? 1.3 : 1)),
                child: BetaBottomSearchScope(
                  host: host,
                  child: RepaintBoundary(
                    key: const ValueKey('library-capture'),
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await pumpArtworkReady(tester);
        expect(find.text('常用音乐'), findsOneWidget);
        expect(find.text('我的喜欢'), findsOneWidget);
        expect(find.text('已下载'), findsOneWidget);
        expect(find.byTooltip('新建歌单'), findsOneWidget);
        await capture(tester, 'library-$netease-$dark-top');
        if (netease) {
          expect(find.text('音乐云盘'), findsOneWidget);
          expect(find.text('已购音乐'), findsOneWidget);
          await tester.tap(find.text('音乐云盘'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            tester
                .widget<NeteaseFullHubPage>(find.byType(NeteaseFullHubPage))
                .category,
            '音乐云盘',
          );
          Navigator.of(tester.element(find.byType(NeteaseFullHubPage))).pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.scrollUntilVisible(
            find.text('播放足迹'),
            350,
            scrollable: find.byType(Scrollable).first,
          );
          await pumpArtworkReady(tester);
          await capture(tester, 'library-$netease-$dark-history');
          await tester.scrollUntilVisible(
            find.text('导入歌单'),
            350,
            scrollable: find.byType(Scrollable).first,
          );
          await pumpArtworkReady(tester);
          expect(find.text('歌单与收藏管理'), findsOneWidget);
          expect(find.text('收藏概览'), findsOneWidget);
          expect(
            find.text('网易云专区'),
            findsNothing,
            reason: 'The old mixed catch-all panel is reorganized.',
          );
        } else {
          expect(find.text('音乐云盘'), findsNothing);
          expect(find.text('收藏与订阅'), findsNothing);
          await tester.scrollUntilVisible(
            find.text('我的歌单'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('导入歌单'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await capture(tester, 'library-$netease-$dark-bottom');
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        host.dispose();
        await tester.runAsync(fixture.dispose);
      },
    );
  }
}
