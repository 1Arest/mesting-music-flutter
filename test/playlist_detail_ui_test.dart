import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/playlists/presentation/playlist_detail_page.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/utils/duration_format.dart';

import 'support/test_tracks.dart';

void main() {
  testWidgets('playlist detail shows track count without aggregate duration', (
    tester,
  ) async {
    // Both lazy rows must actually be in the viewport before asserting their
    // individual metadata; the old default landscape fixture hid the second.
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 7, 23);
    final tracks = testTracks.take(2).toList(growable: false);
    final playlist = UserPlaylist(
      ownerId: 'test-user',
      id: 'playlist-1',
      name: '测试歌单',
      description: '只显示歌曲数量',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playlistProvider.overrideWith((ref, id) async => playlist),
          playlistTracksProvider.overrideWith(
            (ref, id) => Stream.value(tracks),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PlaylistDetailPage(playlistId: 'playlist-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('playlist-hero-track-count')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('playlist-section-track-count')),
      findsOneWidget,
    );
    expect(find.text('2 首'), findsNWidgets(2));
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .toList();
    expect(
      visibleText.where((text) => RegExp(r'2 首.*\d+:\d+').hasMatch(text)),
      isEmpty,
    );
    for (final track in tracks) {
      expect(
        visibleText.any(
          (text) => text.contains(formatDuration(track.duration)),
        ),
        isTrue,
        reason: '单曲 ${track.title} 的时长必须保留',
      );

      final surface = tester.widget<Material>(
        find.byKey(ValueKey('playlist-track-surface-${track.id}')),
      );
      expect(surface.clipBehavior, Clip.antiAlias);
      expect(surface.shape, isA<RoundedRectangleBorder>());
      final shape = surface.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(22));
    }

    final playAllInk = tester.widget<Ink>(
      find.byKey(const ValueKey('playlist-hero-action-primary')),
    );
    final playAllDecoration = playAllInk.decoration! as BoxDecoration;
    expect(playAllDecoration.color, MestingPalette.heart);
    expect(playAllDecoration.borderRadius, BorderRadius.circular(17));
    expect(
      playAllDecoration.boxShadow,
      isNull,
      reason: '播放全部按钮下方不应残留带直角的装饰阴影背景',
    );
  });

  testWidgets(
    'system back from a restored playlist detail returns to my playlists',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime(2026, 7, 27);
      final playlist = UserPlaylist(
        ownerId: 'test-user',
        id: 'restored-playlist',
        name: '恢复的歌单',
        description: '',
        createdAt: now,
        updatedAt: now,
      );
      final router = GoRouter(
        initialLocation: '/music/playlists/restored-playlist',
        routes: [
          GoRoute(
            path: '/music',
            builder: (_, state) => Scaffold(
              body: Text('view=${state.uri.queryParameters['view']}'),
            ),
          ),
          GoRoute(
            path: '/music/playlists/:playlistId',
            builder: (_, state) => PlaylistDetailPage(
              playlistId: state.pathParameters['playlistId']!,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistProvider.overrideWith((ref, id) async => playlist),
            playlistTracksProvider.overrideWith(
              (ref, id) => Stream.value(const <Track>[]),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('恢复的歌单'), findsOneWidget);
      expect(router.canPop(), isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('view=playlists'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('playlist picker only lists favorite tracks', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 7, 24);
    final favorite = testTracks.first;
    final existingNonFavorite = testTracks[1];
    final playlist = UserPlaylist(
      ownerId: 'test-user',
      id: 'playlist-favorites-only',
      name: '收藏歌单',
      description: '只能从我的喜欢添加',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playlistProvider.overrideWith((ref, id) async => playlist),
          playlistTracksProvider.overrideWith(
            (ref, id) => Stream.value([existingNonFavorite]),
          ),
          favoriteTracksProvider.overrideWith(
            (ref) => Stream.value([favorite]),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PlaylistDetailPage(playlistId: 'playlist-favorites-only'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加歌曲'));
    await tester.pumpAndSettle();

    final picker = find.byKey(const ValueKey('favorite-track-picker'));
    expect(picker, findsOneWidget);
    expect(
      tester.getSize(picker).height,
      lessThan(900 * .65),
      reason: '收藏歌曲较少时，抽屉应按内容收紧而不是占据屏幕 88%',
    );
    expect(find.text('从我的喜欢添加'), findsOneWidget);
    expect(
      find.descendant(of: picker, matching: find.text(favorite.title)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: picker,
        matching: find.text(existingNonFavorite.title),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'playlist picker places included favorites before available favorites',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime(2026, 7, 25);
      final availableFirst = testTracks[0];
      final includedFirst = testTracks[1];
      final availableSecond = testTracks[2];
      final includedSecond = testTracks[3];
      final playlist = UserPlaylist(
        ownerId: 'test-user',
        id: 'playlist-included-first',
        name: '排序歌单',
        description: '',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistProvider.overrideWith((ref, id) async => playlist),
            playlistTracksProvider.overrideWith(
              (ref, id) => Stream.value([includedFirst, includedSecond]),
            ),
            favoriteTracksProvider.overrideWith(
              (ref) => Stream.value([
                availableFirst,
                includedFirst,
                availableSecond,
                includedSecond,
              ]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PlaylistDetailPage(playlistId: 'playlist-included-first'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('添加歌曲'));
      await tester.pumpAndSettle();

      final picker = find.byKey(const ValueKey('favorite-track-picker'));
      Finder titleOf(Track track) =>
          find.descendant(of: picker, matching: find.text(track.title));
      final orderedTitles = [
        titleOf(includedFirst),
        titleOf(includedSecond),
        titleOf(availableFirst),
        titleOf(availableSecond),
      ];
      for (final title in orderedTitles) {
        expect(title, findsOneWidget);
      }
      final verticalOffsets = orderedTitles
          .map((title) => tester.getTopLeft(title).dy)
          .toList(growable: false);
      expect(verticalOffsets, orderedEquals([...verticalOffsets]..sort()));
    },
  );

  testWidgets('empty favorite picker explains how to add songs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 7, 24);
    final playlist = UserPlaylist(
      ownerId: 'test-user',
      id: 'playlist-no-favorites',
      name: '空歌单',
      description: '',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playlistProvider.overrideWith((ref, id) async => playlist),
          playlistTracksProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
          favoriteTracksProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PlaylistDetailPage(playlistId: 'playlist-no-favorites'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加歌曲'));
    await tester.pumpAndSettle();

    expect(find.text('还没有收藏歌曲'), findsOneWidget);
    expect(find.text('去我的喜欢'), findsOneWidget);
    expect(find.textContaining('在线曲库暂时不可用'), findsNothing);
  });
}
