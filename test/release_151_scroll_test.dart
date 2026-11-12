import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/shared/models/song_list_memory.dart';
import 'package:mesting_music/shared/widgets/song_list_tools.dart';
import 'release_148_ui_test.dart' show song148;

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  for (final reduced in [false, true]) {
    testWidgets(
      'lazy locate and top have continuous intermediate offsets reduced=$reduced',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final memory = SongListMemory(await SharedPreferences.getInstance());
        final scroll = ScrollController();
        memory.remember('netease:test', 'long', song148(150));
        final tracks = [for (var i = 0; i < 200; i++) song148(i)];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: SongListOwnerScope(
                  owner: 'netease:test',
                  memory: memory,
                  child: SongListTools(
                    listId: 'long',
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: tracks.length,
                      itemBuilder: (_, i) => SongListEntry(
                        track: tracks[i],
                        tracks: tracks,
                        child: SizedBox(height: 80, child: Text('row-$i')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('song-list-last-played')));
        await tester.pump();
        if (!reduced) {
          expect(
            scroll.offset,
            closeTo(0, .5),
            reason: 'no instant estimate jump before lazy rows animate',
          );
          await tester.pump(const Duration(milliseconds: 150));
          final first = scroll.offset;
          expect(first, greaterThan(0));
          expect(first, lessThan(12000));
          await tester.pump(const Duration(milliseconds: 200));
          expect(scroll.offset, greaterThan(first));
          expect(scroll.offset, lessThan(12000));
        }
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('row-150').hitTestable(), findsOneWidget);
        final beforeTop = scroll.offset;
        await tester.tap(find.byKey(const ValueKey('song-list-top')));
        await tester.pump();
        if (!reduced) {
          expect(scroll.offset, closeTo(beforeTop, .5));
          await tester.pump(const Duration(milliseconds: 150));
          final first = scroll.offset;
          expect(first, lessThan(beforeTop));
          expect(first, greaterThan(0));
          await tester.pump(const Duration(milliseconds: 200));
          expect(scroll.offset, lessThan(first));
          expect(scroll.offset, greaterThan(0));
        }
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(scroll.offset, closeTo(0, .5));
        if (!reduced) {
          await tester.tap(find.byKey(const ValueKey('song-list-last-played')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          await tester.drag(find.byType(ListView), const Offset(0, 280));
          await tester.pumpAndSettle();
          expect(
            find.text('row-150').hitTestable(),
            findsNothing,
            reason:
                'an interrupted locate must not resume after manual scrolling',
          );
          expect(scroll.position.isScrollingNotifier.value, isFalse);
        }
        expect(memory.read('netease:test', 'long')!.trackId, song148(150).id);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
        memory.dispose();
      },
    );
  }
}
