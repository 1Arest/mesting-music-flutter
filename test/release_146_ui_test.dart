import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/shared/widgets/music_list_footer.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/audio_downloads_page.dart';
import 'package:mesting_music/features/experience/presentation/favorite_tracks_search.dart';
import 'package:mesting_music/features/experience/presentation/music_library_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comment_composer.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/music_loading_geometry.dart';
import 'netease_v112_fallback_download_test.dart' show recording;
import 'support/personal_profile_fixture.dart';
import 'support/release_144_qa.dart' show theme144;

const capture = bool.fromEnvironment('CAPTURE_146');
const captureDirectory = String.fromEnvironment(
  'CAPTURE_146_DIR',
  defaultValue: '.codex-artifacts/2026-11-03-release146/ui',
);
const boundary = ValueKey('qa146');

Future<void> ready146(WidgetTester tester) async {
  // Use the exact resized providers painted by the rows. Warming the original
  // AssetImage alone has a different cache key and leaves the readiness fence.
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  if (images.isNotEmpty) {
    await tester.runAsync(
      () => Future.wait([
        for (final image in images)
          precacheImage(image.image, tester.element(find.byType(MaterialApp))),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await ready146(tester);
  if (!capture) return;
  final frame = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundary),
  );
  await tester.runAsync(() async {
    final image = await frame.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$captureDirectory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

ThemeData theme146(bool dark) {
  final theme = theme144(dark);
  return capture
      ? theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'MestingQA146'),
          listTileTheme: theme.listTileTheme.copyWith(
            titleTextStyle: TextStyle(
              fontFamily: 'MestingQA146',
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
            subtitleTextStyle: TextStyle(
              fontFamily: 'MestingQA146',
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        )
      : theme;
}

// Production paints its theme surface above the transparent scaffold. Include
// that surface and the Navigator overlay so menus/HUDs are visible in captures.
Widget capture146Builder(BuildContext context, Widget? child) =>
    RepaintBoundary(
      key: boundary,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: child!,
      ),
    );

/// A finite feed of bundled covers exercises the real navigation and end
/// marker. No platform account or remote artwork is read by host rendering.
class _Feed146 extends NeteaseFeaturesRepository {
  const _Feed146(super.music);
  @override
  Future<NeteaseBatch> load(
    NeteaseFeed feed, {
    int page = 1,
    int before = 0,
    String id = '',
    String category = '全部',
    String area = 'ALL',
    int artistArea = 1,
  }) async => NeteaseBatch([
    for (var i = 0; i < 4; i++)
      NeteaseItem(
        id: '$i',
        name: '播客样本 ${i + 1}',
        subtitle: '本地合成内容',
        cover: profileFixtureCover,
        kind: NeteaseEntity.podcast,
      ),
  ]);
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (capture) {
      for (final family in [
        'MestingQA146',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'Noto Sans SC',
        'Microsoft YaHei',
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

  test(
    'filter searches all favorite rows including songs beyond the viewport',
    () async {
      final fixture = await PersonalProfileFixture.create();
      addTearDown(fixture.dispose);
      expect(
        filterFavoriteTracks(fixture.tracks, '673').single.id,
        'netease_8673',
      );
      expect(filterFavoriteTracks(fixture.tracks, '合成数据').length, 674);
      expect(
        filterFavoriteTracks(fixture.tracks, 'not-in-my-library'),
        isEmpty,
      );
      expect(filterFavoriteTracks(fixture.tracks, '歌曲 673').length, 1);
    },
  );

  test(
    'append spinner sits above current chrome independent of prepared row cutoff',
    () {
      final geometry = MusicLoadingGeometry.inWindow(
        origin: 100,
        height: 720,
        windowHeight: 844,
        safeTop: 44,
        chromeBottom: 120,
      );
      for (final cutoff in [70.0, 210.0, 400.0]) {
        expect(
          geometry.indicatorTop(cutoff: cutoff, extent: 32, refreshing: false),
          576,
        );
      }
      expect(
        geometry.indicatorTop(cutoff: 400, extent: 32, refreshing: true),
        18,
      );
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'favorites local search retains creation and has no button inflation dark=$dark',
      (tester) async {
        final fixture = await PersonalProfileFixture.create(
          extraOverrides: [
            currentMediaItemProvider.overrideWith((_) => Stream.value(null)),
            audioDownloadManagerProvider.overrideWith((ref) {
              final manager = AudioDownloadManager(
                client: MockClient((_) async => http.Response('', 404)),
                resolve: (_) async => 'https://synthetic.invalid/unused',
                publish: (_, _, _, _) async => 'content://synthetic/unused',
                currentOwner: () => 'netease:7001',
                directory: () async => Directory.systemTemp,
                persist: (_) async {},
                restored: [
                  AudioDownloadTask(
                    id: 'complete',
                    owner: 'netease:7001',
                    track: recording(id: 'netease_8000'),
                    phase: AudioDownloadPhase.completed,
                    uri: 'content://synthetic/complete',
                  ),
                  AudioDownloadTask(
                    id: 'other',
                    owner: 'netease:other',
                    track: recording(id: 'netease_8673'),
                    phase: AudioDownloadPhase.completed,
                    uri: 'content://synthetic/other',
                  ),
                ],
              );
              ref.onDispose(manager.dispose);
              return manager;
            }),
          ],
        );
        addTearDown(fixture.dispose);
        await fixture.container.read(platformAccountProvider.future);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              builder: capture146Builder,
              theme: theme146(dark),
              home: const Scaffold(body: MusicLibraryPage(view: 'favorites')),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => precacheImage(
            const AssetImage(profileFixtureCover),
            tester.element(find.byType(MaterialApp)),
          ),
        );
        await tester.pump();
        expect(find.byTooltip('新建歌单'), findsOneWidget);
        expect(find.text('已下载'), findsOneWidget);
        await tester.tap(find.byTooltip('搜索我的喜欢'));
        await tester.pump();
        final composer = tester.widget<PlatformCommentComposer>(
          find.byType(PlatformCommentComposer),
        );
        expect(composer.expandOnPress, false);
        expect(composer.singleLine, true);
        await tester.enterText(find.byType(TextField), '673');
        await tester.pump();
        expect(find.text('测试歌曲 673'), findsOneWidget);
        expect(find.text('测试歌曲 0'), findsNothing);
        expect(find.text('已下载'), findsNothing);
        await shot(tester, 'favorites-search-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'failed download left swipe removes task and red action preserves optics dark=$dark',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('music146-ui'),
        ))!;
        addTearDown(
          () => tester.runAsync(() => directory.delete(recursive: true)),
        );
        final manager = AudioDownloadManager(
          client: MockClient((_) async => http.Response('', 404)),
          resolve: (_) async => 'https://synthetic.invalid/unused',
          publish: (_, _, _, _) async => 'content://synthetic/unused',
          currentOwner: () => 'netease:7001',
          directory: () async => directory,
          persist: (_) async {},
          restored: [
            AudioDownloadTask(
              id: 'failed',
              owner: 'netease:7001',
              track: recording(),
              phase: AudioDownloadPhase.failed,
              error: '测试失败',
            ),
            AudioDownloadTask(
              id: 'paused',
              owner: 'netease:7001',
              track: recording(
                id: 'paused',
                title: '暂停的歌曲',
              ).copyWith(coverAsset: profileFixtureCover),
              phase: AudioDownloadPhase.paused,
              received: 512 * 1024,
              total: 2 * 1024 * 1024,
              validator: '"synthetic"',
            ),
            AudioDownloadTask(
              id: 'completed',
              owner: 'netease:7001',
              track: recording(
                id: 'completed',
                title: '已下载的样本',
              ).copyWith(coverAsset: profileFixtureCover),
              phase: AudioDownloadPhase.completed,
              uri: 'content://synthetic/completed',
              received: 2 * 1024 * 1024,
            ),
          ],
        );
        addTearDown(manager.dispose);
        final fixture = await PersonalProfileFixture.create(
          extraOverrides: [
            currentMediaItemProvider.overrideWith((_) => Stream.value(null)),
            audioDownloadManagerProvider.overrideWithValue(manager),
          ],
        );
        addTearDown(fixture.dispose);
        await fixture.container.read(platformAccountProvider.future);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              builder: capture146Builder,
              theme: theme146(dark),
              home: const Scaffold(body: AudioDownloadsPage()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester
              .widgetList<BetaGlassButton>(find.byType(BetaGlassButton))
              .any((button) => button.red),
          true,
        );
        expect(find.byType(Dismissible), findsNWidgets(2));
        expect(find.byTooltip('继续下载'), findsOneWidget);
        await shot(tester, 'download-tasks-${dark ? 'dark' : 'light'}');
        final failed = find.byKey(const ValueKey('download-dismiss-failed'));
        await tester.drag(failed, const Offset(-400, 0));
        await tester.pumpAndSettle();
        expect(manager.tasks.any((task) => task.id == 'failed'), false);
        expect(manager.tasks.length, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('podcast navigation fits one line or a menu dark=$dark', (
      tester,
    ) async {
      final fixture = await PersonalProfileFixture.create(
        extraOverrides: [
          currentMediaItemProvider.overrideWith((_) => Stream.value(null)),
          neteaseFeaturesProvider.overrideWith(
            (ref) => _Feed146(ref.read(neteaseMusicRepositoryProvider)),
          ),
        ],
      );
      addTearDown(fixture.dispose);
      await fixture.container.read(platformAccountProvider.future);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: fixture.container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: capture146Builder,
            theme: theme146(dark),
            home: const Scaffold(
              body: NeteaseFeaturesPage(feed: NeteaseFeed.podcasts),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => precacheImage(
          const AssetImage(profileFixtureCover),
          tester.element(find.byType(MaterialApp)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final menu = find.byKey(const ValueKey('podcast-navigation-menu'));
      expect(menu, findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<NeteaseFeed>>(
              find.byType(DropdownButton<NeteaseFeed>),
            )
            .items,
        hasLength(7),
      );
      expect(find.byType(MusicListEnd), findsOneWidget);
      await shot(tester, 'podcasts-narrow-${dark ? 'dark' : 'light'}');
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await shot(tester, 'podcasts-menu-${dark ? 'dark' : 'light'}');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1200, 844);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      final entries = tester
          .widgetList<TextButton>(find.byType(TextButton))
          .where((button) => button.child is Text)
          .toList();
      expect(entries, hasLength(7));
      final tops = [
        for (final entry in entries) tester.getTopLeft(find.byWidget(entry)).dy,
      ];
      expect(tops.toSet(), hasLength(1));
      await shot(tester, 'podcasts-wide-${dark ? 'dark' : 'light'}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
