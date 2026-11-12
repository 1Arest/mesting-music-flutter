import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/shared/models/song_list_memory.dart';
import 'package:mesting_music/shared/widgets/song_list_tools.dart';
import 'package:mesting_music/shared/widgets/song_list_scroll_motion.dart';
import 'release_148_ui_test.dart' show song148;

void main() {
  setUpAll(LiquidGlassWidgets.initialize);
  testWidgets(
    'measured lazy target retargets while retaining uninterrupted velocity',
    (tester) async {
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: scroll,
              itemCount: 200,
              itemExtent: 80,
              itemBuilder: (_, i) => Text('row $i'),
            ),
          ),
        ),
      );
      var target = 4000.0;
      final movement = SongListScrollMotion.move(
        scroll.position,
        target,
        reduceMotion: false,
        measuredTarget: () => target,
      );
      await tester.pump();
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final a = scroll.offset;
      await tester.pump(const Duration(milliseconds: 16));
      final before = scroll.offset - a;
      target = 5000;
      await tester.pump(const Duration(milliseconds: 16));
      final correction = scroll.offset;
      await tester.pump(const Duration(milliseconds: 16));
      final after = scroll.offset - correction;
      expect(before, greaterThan(5));
      expect(
        after,
        greaterThan(before * .45),
        reason: 'calibration must not decelerate to rest and restart',
      );
      await tester.pumpAndSettle();
      await movement;
      expect(scroll.offset, closeTo(5000, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
  testWidgets(
    'last-played capsule is 210 wide and preserves its dismissal action',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final memory = SongListMemory(await SharedPreferences.getInstance());
      memory.remember('kugou:test', 'list', song148(1));
      final songs = [song148(1)];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongListOwnerScope(
              owner: 'kugou:test',
              memory: memory,
              child: SongListTools(
                listId: 'list',
                child: ListView(
                  children: [
                    SongListEntry(
                      track: songs.first,
                      tracks: songs,
                      child: const SizedBox(height: 80, child: Text('row')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final tools = find.byKey(const ValueKey('song-list-tools'));
      expect(tester.getSize(tools).width, 210);
      expect(
        find.byKey(const ValueKey('song-list-last-played')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      memory.dispose();
    },
  );
}
