import 'package:mesting_music/shared/widgets/liquid_glass_sheet.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/data/song_menu_details.dart';
import 'package:mesting_music/features/music_platform/presentation/song_actions_sheet.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/song_list_bookmark_capsule.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/song_list_tools.dart';
import 'package:mesting_music/shared/models/song_list_memory.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/library/favorite_pins_provider.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/experience/presentation/music_library_page.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_147_qa.dart';
import 'release_148_ui_test.dart' show mount148, shot148, song148;

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_148')) {
      await load147IconFonts();
      for (final family in [
        'MestingQA148',
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
    for (final large in [false, true]) {
      testWidgets(
        'compact cover capsule integrates close, separate locate and large text dark=$dark large=$large',
        (tester) async {
          final fixture = await PersonalProfileFixture.create();
          addTearDown(fixture.dispose);
          var located = 0, dismissed = 0;
          await mount148(
            tester,
            fixture,
            Scaffold(
              body: Center(
                child: SizedBox(
                  width: 238,
                  child: SongListBookmarkCapsule(
                    title: '冬与你pt2 · 很长的歌名',
                    cover: profileFixtureCover,
                    locating: false,
                    onLocate: () => located++,
                    onDismiss: () => dismissed++,
                  ),
                ),
              ),
            ),
            dark: dark,
            large: large,
          );
          final capsule = find.byKey(const ValueKey('song-list-last-played'));
          final close = find.byKey(const ValueKey('song-list-dismiss'));
          expect(tester.getSize(capsule).width, lessThanOrEqualTo(238));
          expect(find.descendant(of: capsule, matching: close), findsOneWidget);
          expect(
            tester
                .widget<ArtworkImage>(
                  find.byKey(const ValueKey('song-list-bookmark-cover')),
                )
                .uri,
            profileFixtureCover,
          );
          await tester.tap(close);
          await tester.pump();
          expect(dismissed, 1);
          expect(located, 0);
          await tester.tap(find.text('上次播放到这首'));
          await tester.pump();
          expect(located, 1);
          await shot148(
            tester,
            'capsule-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
      for (final source in [TrackSource.netease, TrackSource.kugou]) {
        testWidgets(
          'song actions retain real header and full non-trading operations $source dark=$dark large=$large',
          (tester) async {
            final fixture = await PersonalProfileFixture.create();
            addTearDown(fixture.dispose);
            final track = Track.fromJson({
              ...song148(1).toJson(),
              'source': source.name,
            });
            final intents = <Object>[];
            await mount148(
              tester,
              fixture,
              Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => showLiquidGlassBottomSheet<void>(
                        context: context,
                        useRootNavigator: true,
                        useSafeArea: true,
                        isScrollControlled: true,
                        builder: (_) => SongActionsPanel(
                          track: track,
                          favorites: true,
                          onSelect: intents.add,
                          loadDetails: () async => const SongMenuDetails(
                            artists: [SongMenuPerson('真实歌手', id: '1')],
                            creators: [SongMenuPerson('真实词作者', role: '作词')],
                            album: '真实专辑',
                            albumId: '3',
                          ),
                        ),
                      ),
                      child: const Text('打开歌曲菜单'),
                    ),
                  ),
                ),
              ),
              dark: dark,
              large: large,
            );
            await tester.tap(find.text('打开歌曲菜单'));
            await tester.pumpAndSettle();
            expect(find.text('歌曲：${track.title}'), findsOneWidget);
            for (final action in [
              '下一首播放',
              '喜欢',
              source == TrackSource.netease ? '收藏到歌单' : '加入歌单',
              '下载',
              '评论',
              '分享',
            ]) {
              expect(find.text(action), findsOneWidget);
            }
            expect(find.textContaining('购买'), findsNothing);
            expect(find.textContaining('赞赏'), findsNothing);
            await tester.tap(find.byKey(const ValueKey('song-menu-next')));
            expect(intents.single, 'next');
            await tester.pump(const Duration(milliseconds: 400));
            await shot148(
              tester,
              'menu-${source.name}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}-top',
            );
            await tester.drag(find.byType(ListView), const Offset(0, -370));
            await tester.pumpAndSettle();
            expect(find.textContaining('真实词作者').hitTestable(), findsOneWidget);
            expect(find.text('专辑：真实专辑').hitTestable(), findsOneWidget);
            await shot148(
              tester,
              'menu-${source.name}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}-details',
            );
            await tester.tap(find.byTooltip('关闭歌曲菜单'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  testWidgets(
    'favorite list row has vertical menu instead of direct playlist action',
    (tester) async {
      final fixture = await PersonalProfileFixture.create();
      addTearDown(fixture.dispose);
      await mount148(
        tester,
        fixture,
        Scaffold(
          body: EditorialTrackRow(
            track: song148(1),
            contextTracks: [song148(1)],
            favorites: true,
          ),
        ),
      );
      expect(find.byType(SongActionsButton), findsOneWidget);
      expect(find.byTooltip('加入歌单'), findsNothing);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.more_vert_rounded)).icon,
        Icons.more_vert_rounded,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'metadata failure leaves actions available and retry replaces only details',
    (tester) async {
      final fixture = await PersonalProfileFixture.create();
      addTearDown(fixture.dispose);
      var attempts = 0;
      await mount148(
        tester,
        fixture,
        Scaffold(
          body: SongActionsPanel(
            track: song148(1),
            onSelect: (_) {},
            loadDetails: () async {
              if (attempts++ == 0) throw StateError('offline');
              return const SongMenuDetails(album: '恢复的专辑', albumId: '2');
            },
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料加载未完成，重试'));
      await tester.pumpAndSettle();
      expect(find.text('专辑：恢复的专辑'), findsOneWidget);
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'favorite menu commits a local pin and sorted view restores unloaded pinned membership',
    (tester) async {
      final fixture = await PersonalProfileFixture.create(
        extraOverrides: [
          completeFavoriteIdsProvider.overrideWith(
            (ref) async => {
              for (var i = 0; i < 674; i++) 'netease_${8000 + i}',
            },
          ),
        ],
      );
      addTearDown(fixture.dispose);
      final target = fixture.tracks[80];
      final pins = fixture.container.read(favoritePinsProvider);
      await pins.toggle('netease:7001', target);
      final memory = SongListMemory(
        fixture.container.read(sharedPreferencesProvider),
      );
      addTearDown(memory.dispose);
      memory.remember('netease:7001', 'favorites', target);
      await memory.flush();
      await mount148(
        tester,
        fixture,
        Scaffold(
          body: SongListOwnerScope(
            owner: 'netease:7001',
            memory: memory,
            child: const SongListTools(
              listId: 'favorites',
              child: MusicLibraryPage(view: 'favorites'),
            ),
          ),
        ),
      );
      final first = tester
          .widgetList<EditorialTrackRow>(find.byType(EditorialTrackRow))
          .first;
      expect(first.track.id, target.id);
      expect(find.text('674 首歌曲'), findsOneWidget);
      await shot148(tester, 'favorites-pinned-with-cover-capsule-light-normal');
      await tester.tap(find.byKey(ValueKey('song-actions-${target.id}')));
      await tester.pumpAndSettle();
      expect(find.text('取消置顶'), findsOneWidget);
      await tester.tap(find.text('取消置顶'));
      await tester.pumpAndSettle();
      expect(pins.contains('netease:7001', target.id), false);
      expect(
        tester
            .widgetList<EditorialTrackRow>(find.byType(EditorialTrackRow))
            .first
            .track
            .id,
        fixture.tracks.first.id,
      );
      await shot148(tester, 'favorites-unpinned-light-normal');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
