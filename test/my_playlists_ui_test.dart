import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/presentation/music_home_page.dart';

import 'support/test_tracks.dart';

void main() {
  testWidgets('personal playlist library uses the redesigned compact layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final playlist = UserPlaylist(
      ownerId: 'test-user',
      id: 'playlist-1',
      name: '夜晚循环',
      description: '适合一个人慢慢听',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 23),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playlistTracksProvider.overrideWith(
            (ref, id) => Stream.value(testTracks.take(2).toList()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 164),
              child: MyPlaylistsCollectionView(playlists: [playlist]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('my-playlists-overview')), findsOneWidget);
    expect(find.text('私人音乐资料库'), findsOneWidget);
    expect(find.text('全部歌单'), findsOneWidget);
    expect(find.text('按最近编辑排序'), findsOneWidget);
    expect(find.text('夜晚循环'), findsOneWidget);
    expect(find.text('适合一个人慢慢听'), findsOneWidget);
    expect(find.text('2 首歌曲'), findsOneWidget);
    expect(find.textContaining('创建第一个歌单'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty library only points to the profile create drawer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: MyPlaylistsCollectionView(playlists: []),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('my-playlists-empty')), findsOneWidget);
    expect(find.text('这里还没有歌单'), findsOneWidget);
    expect(find.textContaining('“我的”页'), findsOneWidget);
    expect(find.textContaining('右上角 +'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('playlist creation is only invoked from the profile page', () {
    final libraryPage = File(
      'lib/features/library/presentation/music_home_page.dart',
    ).readAsStringSync();
    final addSheet = File(
      'lib/features/playlists/presentation/add_to_playlist_sheet.dart',
    ).readAsStringSync();
    final profilePage = File(
      'lib/features/profile/presentation/profile_page.dart',
    ).readAsStringSync();

    expect(libraryPage, isNot(contains('.createPlaylist(')));
    expect(libraryPage, isNot(contains('showPlaylistEditorDialog(')));
    expect(addSheet, isNot(contains('.createPlaylist(')));
    expect(addSheet, contains('返回“我的”'));
    expect(profilePage, contains("ValueKey('profile-create-menu-button')"));
    expect(profilePage, contains('.createPlaylist('));
  });
}
