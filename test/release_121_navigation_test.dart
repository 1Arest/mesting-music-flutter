import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/beta_tab_navigation.dart';
import 'package:mesting_music/shared/widgets/beta_scroll_chrome.dart';
import 'package:mesting_music/features/experience/presentation/player_content_transition.dart';

void main() {
  testWidgets('scroll morphs keep their duration and latest requested target', (
    tester,
  ) async {
    final chrome = BetaScrollChrome();
    addTearDown(chrome.dispose);
    chrome.request(true);
    expect(chrome.value, isTrue);
    chrome.request(false);
    await tester.pump(const Duration(milliseconds: 110));
    expect(chrome.value, isTrue);
    expect(chrome.requestedCompact, isFalse);
    chrome.request(true);
    await tester.pump(const Duration(milliseconds: 190));
    expect(chrome.value, isTrue);
    chrome.request(false);
    expect(chrome.value, isFalse);
    chrome.request(true);
    chrome.show(false); // Navigation cancels an old page's pending scroll.
    await tester.pump(const Duration(seconds: 1));
    expect(chrome.value, isFalse);
    expect(chrome.requestedCompact, isFalse);
  });
  test('burst immediately dispatches every changed destination', () {
    final queue = BetaTabNavigation(), calls = <int>[];
    void request(int index) =>
        queue.request(index: index, currentIndex: 0, navigate: calls.add);
    request(2);
    request(3);
    request(0);
    request(1);
    expect(calls, [2, 3, 0, 1]);
    queue.settled(3); // A departed/stale route must not release another intent.
    expect(calls, [2, 3, 0, 1]);
    queue.settled(2);
    expect(calls, [2, 3, 0, 1]);
    queue.settled(1);
    expect(calls, [2, 3, 0, 1]);
  });
  test(
    'same-frame reselect returns immediately to the selected destination',
    () {
      final queue = BetaTabNavigation(), calls = <int>[];
      for (final i in [2, 3, 2]) {
        queue.request(index: i, currentIndex: 0, navigate: calls.add);
      }
      queue.settled(2);
      expect(calls, [2, 3, 2]);
      queue.cancel();
      queue.request(index: 2, currentIndex: -1, navigate: calls.add);
      expect(calls, [
        2,
        3,
        2,
        2,
      ], reason: 'A detail can return to its own root tab.');
    },
  );
  test('detail or disposal discards pending tab callbacks', () {
    final queue = BetaTabNavigation(), calls = <int>[];
    for (final i in [2, 3]) {
      queue.request(index: i, currentIndex: 0, navigate: calls.add);
    }
    queue.cancel();
    queue.settled(2);
    expect(calls, [2, 3]);
  });
  test('duplicate destination is ignored without delaying a return tap', () {
    final navigation = BetaTabNavigation(), calls = <int>[];
    for (final i in [2, 2, 0]) {
      navigation.request(index: i, currentIndex: 0, navigate: calls.add);
    }
    expect(calls, [2, 0]);
  });
  testWidgets('rapid player changes retain only two content trees and settle', (
    tester,
  ) async {
    var visible = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PlayerContentTransition(
              child: Text('surface-$visible', key: ValueKey(visible)),
            );
          },
        ),
      ),
    );
    for (var i = 1; i < 30; i++) {
      update(() => visible = i);
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        find.textContaining('surface-').evaluate().length,
        lessThanOrEqualTo(2),
      );
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('surface-'), findsOneWidget);
    expect(find.text('surface-29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('departing player content preserves its original 280ms fade', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PlayerContentTransition(
              child: Text('fade-$selected', key: ValueKey(selected)),
            );
          },
        ),
      ),
    );
    update(() => selected = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('fade-0'), matching: find.byType(Opacity))
          .first,
    );
    expect(opacity.opacity, closeTo(Curves.easeInCubic.transform(.5), .005));
    await tester.pumpAndSettle();
    expect(find.text('fade-0'), findsNothing);
  });
  testWidgets('reversing player content preserves its mounted state', (
    tester,
  ) async {
    var selected = 0, creations = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PlayerContentTransition(
              child: _MountedProbe(
                key: ValueKey(selected),
                onCreate: () => creations++,
              ),
            );
          },
        ),
      ),
    );
    expect(creations, 1);
    update(() => selected = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(creations, 2);
    update(() => selected = 0);
    await tester.pump();
    expect(creations, 2);
    await tester.pumpAndSettle();
    expect(find.byType(_MountedProbe), findsOneWidget);
  });
}

class _MountedProbe extends StatefulWidget {
  const _MountedProbe({required this.onCreate, super.key});
  final VoidCallback onCreate;
  @override
  State<_MountedProbe> createState() => _MountedProbeState();
}

class _MountedProbeState extends State<_MountedProbe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const Text('mounted');
}
