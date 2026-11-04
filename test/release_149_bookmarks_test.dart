import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/shared/models/song_list_memory.dart';
import 'package:mesting_music/shared/widgets/song_list_tools.dart';
import 'package:mesting_music/shared/widgets/beta_content_insets.dart';
import 'release_148_ui_test.dart' show song148;

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  Future<SongListMemory> memory() async {
    SharedPreferences.setMockInitialValues({});
    return SongListMemory(await SharedPreferences.getInstance());
  }

  test(
    'last deliberate selection persists per owner and logical list',
    () async {
      final store = await memory();
      store.remember('netease:one', 'favorites', song148(1));
      store.remember('netease:one', 'playlist:2', song148(2));
      store.remember('kugou:one', 'favorites', song148(3));
      await store.flush();
      final restored = SongListMemory(store.preferences);
      expect(restored.read('netease:one', 'favorites')!.trackId, song148(1).id);
      expect(
        restored.read('netease:one', 'playlist:2')!.trackId,
        song148(2).id,
      );
      expect(restored.read('kugou:one', 'favorites')!.trackId, song148(3).id);
      expect(restored.read('netease:two', 'favorites'), isNull);
      final data =
          jsonDecode(store.preferences.getString(SongListMemory.storageKey)!)
              as Map;
      expect((data.values.first as Map).keys.toSet(), {'id', 'title', 'at', 'cover'});
      restored.dispose();
      store.dispose();
    },
  );
  test(
    'rapid selections persist the newest song without unlimited storage',
    () async {
      final store = await memory();
      for (var i = 0; i < 260; i++) {
        store.remember('owner', 'list:$i', song148(i));
      }
      store.remember('owner', 'list:259', song148(999));
      await store.flush();
      final restored = SongListMemory(store.preferences);
      expect(restored.read('owner', 'list:0'), isNull);
      expect(restored.read('owner', 'list:259')!.trackId, song148(999).id);
      expect(
        (jsonDecode(store.preferences.getString(SongListMemory.storageKey)!)
                as Map)
            .length,
        256,
      );
      restored.dispose();
      store.dispose();
    },
  );
  test('corrupt optional bookmarks do not break opening a list', () async {
    SharedPreferences.setMockInitialValues({
      SongListMemory.storageKey: '{broken',
    });
    final store = SongListMemory(await SharedPreferences.getInstance());
    expect(store.read('owner', 'list'), isNull);
    store.remember('owner', 'list', song148(0));
    await store.flush();
    store.dispose();
  });
  for (final dark in [false, true]) {
    testWidgets(
      'locates an unloaded lazy song without playback and returns to top dark=$dark',
      (tester) async {
        final store = await memory();
        addTearDown(store.dispose);
        store.remember('netease:test', 'songs', song148(85));
        await store.flush();
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        var visible = 30, pages = 0, plays = 0;
        await tester.pumpWidget(
          _Harness(
            store: store,
            dark: dark,
            child: StatefulBuilder(
              builder: (context, setState) {
                final tracks = [for (var i = 0; i < visible; i++) song148(i)];
                return SongListTools(
                  listId: 'songs',
                  hasMore: visible < 120,
                  loadMore: () async {
                    pages++;
                    setState(() => visible += 30);
                  },
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: tracks.length,
                    itemBuilder: (context, index) => SongListEntry(
                      track: tracks[index],
                      tracks: tracks,
                      child: SizedBox(
                        height: 80,
                        child: ListTile(
                          title: Text(tracks[index].title),
                          onTap: () {
                            plays++;
                            SongListTools.remember(context, tracks[index]);
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text('歌曲 85'),
          findsOneWidget,
        ); // Hint only, the lazy row does not exist yet.
        await tester.tap(find.byKey(const ValueKey('song-list-last-played')));
        for (var i = 0; i < 45; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }
        expect(pages, 2);
        expect(visible, 90);
        expect(plays, 0);
        expect(
          find
              .byType(SongListEntry)
              .evaluate()
              .any(
                (e) => (e.widget as SongListEntry).track.id == song148(85).id,
              ),
          isTrue,
        );
        expect(scroll.offset, greaterThan(5000));
        expect(find.byKey(const ValueKey('song-list-top')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('song-list-top')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        expect(scroll.offset, closeTo(0, 1));
        expect(plays, 0);
        expect(store.read('netease:test', 'songs')!.trackId, song148(85).id);
        await tester.tap(find.byKey(const ValueKey('song-list-dismiss')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('song-list-last-played')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'owner change during locate stops pagination and hides the old hint',
    (tester) async {
      final store = await memory();
      addTearDown(store.dispose);
      store.remember('netease:test', 'songs', song148(85));
      await store.flush();
      final gate = Completer<void>();
      var owner = 'netease:test', pages = 0;
      late StateSetter change;
      final tracks = [for (var i = 0; i < 30; i++) song148(i)];
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return _Harness(
              store: store,
              owner: owner,
              child: SongListTools(
                listId: 'songs',
                hasMore: true,
                loadMore: () async {
                  pages++;
                  await gate.future;
                },
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) => SongListEntry(
                    track: tracks[index],
                    tracks: tracks,
                    child: SizedBox(
                      height: 80,
                      child: Text(tracks[index].title),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('song-list-last-played')));
      await tester.pump();
      change(() => owner = 'kugou:other');
      await tester.pump();
      gate.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(pages, 1);
      expect(find.byKey(const ValueKey('song-list-last-played')), findsNothing);
      expect(store.read('kugou:other', 'songs'), isNull);
      expect(store.read('netease:test', 'songs'), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'empty replacement detaches the previous top action and can restore rows',
    (tester) async {
      final store = await memory();
      addTearDown(store.dispose);
      var empty = false;
      late StateSetter update;
      final tracks = [for (var i = 0; i < 40; i++) song148(i)];
      await tester.pumpWidget(
        _Harness(
          store: store,
          child: StatefulBuilder(
            builder: (context, setter) {
              update = setter;
              return SongListTools(
                listId: 'songs',
                child: empty
                    ? const Center(child: Text('没有歌曲'))
                    : ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (context, index) => SongListEntry(
                          track: tracks[index],
                          tracks: tracks,
                          child: SizedBox(
                            height: 80,
                            child: Text(tracks[index].title),
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('song-list-top')), findsOneWidget);
      update(() => empty = true);
      await tester.pumpAndSettle();
      expect(find.text('没有歌曲'), findsOneWidget);
      expect(find.byKey(const ValueKey('song-list-top')), findsNothing);
      update(() => empty = false);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('song-list-top')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'narrow large text tools fit above chrome and hide while typing',
    (tester) async {
      final store = await memory();
      addTearDown(store.dispose);
      store.remember('netease:test', 'songs', song148(3));
      await store.flush();
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _Harness(
          store: store,
          large: true,
          child: SongListTools(
            listId: 'songs',
            child: ListView(
              children: [
                SongListEntry(
                  track: song148(3),
                  tracks: [song148(3)],
                  child: const SizedBox(height: 80, child: Text('歌曲 3')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final tools = tester.getRect(
        find.byKey(const ValueKey('song-list-tools')),
      );
      expect(tools.left, greaterThanOrEqualTo(0));
      expect(tools.right, lessThanOrEqualTo(320));
      expect(tools.bottom, lessThan(720 - 96));
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pump();
      expect(find.byKey(const ValueKey('song-list-tools')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.store,
    required this.child,
    this.owner = 'netease:test',
    this.dark = false,
    this.large = false,
  });
  final SongListMemory store;
  final Widget child;
  final String owner;
  final bool dark, large;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(large ? 1.6 : 1)),
          child: SongListOwnerScope(
            owner: owner,
            memory: store,
            child: BetaContentInsets(bottom: 96, child: child),
          ),
        ),
      ),
    ),
  );
}
