import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';

/// Host structural workload comparison at a 120Hz cadence, not GPU FPS proof.
/// Run with MOTION_METRICS_PATH before/after render-boundary changes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  testWidgets(
    'bottom bar retains accessory while springs move at 120Hz cadence',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final compact = ValueNotifier(false);
      addTearDown(compact.dispose);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final accessoryKey = GlobalKey();
      await tester.pumpWidget(
        LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          brightnessResolver: Theme.maybeBrightnessOf,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ValueListenableBuilder<bool>(
                  valueListenable: compact,
                  builder: (context, small, _) => BetaMusicBottomBar(
                    selectedIndex: 0,
                    onTabSelected: (_) {},
                    isSearchActive: small,
                    inline: small,
                    accessory: SizedBox(
                      key: accessoryKey,
                      height: 50,
                      child: const Row(
                        children: [
                          Icon(Icons.music_note),
                          Expanded(child: Text('真实附件布局')),
                          Icon(Icons.play_arrow),
                        ],
                      ),
                    ),
                    searchConfig: GlassSearchBarConfig(
                      controller: controller,
                      focusNode: focus,
                      hintText: '搜索歌曲、歌手',
                      onSearchToggle: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = accessoryKey.currentContext;
      final counts = <String, int>{};
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final name = element.widget.runtimeType.toString();
        counts.update(name, (n) => n + 1, ifAbsent: () => 1);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      final watch = Stopwatch()..start();
      for (var cycle = 0; cycle < 4; cycle++) {
        compact.value = !compact.value;
        for (var frame = 0; frame < 84; frame++) {
          await tester.pump(const Duration(microseconds: 8333));
          expect(accessoryKey.currentContext, same(original));
          expect(tester.takeException(), isNull);
        }
      }
      watch.stop();
      debugOnRebuildDirtyWidget = null;
      expect(
        counts['SearchPill'] ?? 0,
        lessThan(160),
        reason:
            'search subtree rebuilds only for height changes, not each spring tick',
      );
      expect(counts['SearchableTabIndicator'] ?? 0, lessThan(160));
      final metrics = {
        'frames': 336,
        'cadenceUs': 8333,
        'hostElapsedMs': watch.elapsedMilliseconds,
        'totalWidgetBuilds': counts.values.fold(0, (a, b) => a + b),
        'searchPillBuilds': counts['SearchPill'] ?? 0,
        'byWidget': counts,
      };
      const output = String.fromEnvironment('MOTION_METRICS_PATH');
      if (output.isNotEmpty) {
        await tester.runAsync(
          () => File(output).writeAsString(jsonEncode(metrics)),
        );
      }
      // Print only the compact counters; full widget counts go to the evidence.
      // ignore: avoid_print
      print(
        'MOTION_METRICS ${jsonEncode(Map.of(metrics)..remove('byWidget'))}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
