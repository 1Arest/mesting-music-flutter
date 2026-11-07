import 'package:mesting_music/shared/widgets/artwork_scroll_frontier.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/artwork_reveal_boundary.dart';
import 'package:mesting_music/shared/widgets/mesting_loading_indicator.dart';
import 'support/release_133_qa.dart';

/// Deterministic readiness signals exercise the same registration contract as
/// decoded artwork, without depending on host network/file-codec scheduling.
class _Row extends StatefulWidget {
  const _Row(this.index, this.ready);
  final int index;
  final bool ready;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  ArtworkRevealController? owner;
  ArtworkRevealEntry? entry;
  bool active = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ArtworkRevealBoundary.of(context);
    if (next != owner) {
      entry?.dispose();
      owner = next;
      entry = next?.register(
        () =>
            mounted && active ? context.findRenderObject() as RenderBox? : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    entry?.identity = 'row-${widget.index}';
    entry?.update(ready: widget.ready, enabled: true);
    return SizedBox(
      height: 80,
      child: ColoredBox(
        color: widget.index < 8
            ? const Color(0xFF601820)
            : const Color(0xFF15572A),
        child: Center(child: Text('歌曲 ${widget.index}')),
      ),
    );
  }

  @override
  void deactivate() {
    active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    active = true;
  }

  @override
  void dispose() {
    entry?.dispose();
    super.dispose();
  }
}

const _capture = ValueKey('frontier135');
Future<void> _shot(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_135')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  // A new loader/readiness frame can be scheduled after the drag ends. Paint
  // that frame before snapshotting; keep image work outside fake async.
  if (boundary.debugNeedsPaint) await tester.pump();
  final future = boundary.toImage();
  await tester.runAsync(() async {
    final image = await future;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.codex-artifacts/2026-11-01-release135/ui/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(initialize133QA);
  testWidgets(
    'readiness rebuild retains horizontal page position and controller',
    (tester) async {
      final pager = PageController();
      addTearDown(pager.dispose);
      var ready = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return ArtworkRevealBoundary(
                  child: PageView(
                    controller: pager,
                    children: [
                      Text(ready ? 'ready' : 'loading'),
                      const Text('next'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final position = pager.position;
      update(() => ready = true);
      await tester.pump();
      expect(pager.position, same(position));
      pager.jumpToPage(1);
      await tester.pump();
      expect(pager.page, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final bouncing in [false, true]) {
    testWidgets(
      'fast fling stops at prepared songs, releases on readiness, and allows upward scrolling bouncing=$bouncing',
      (tester) async {
        tester.view.physicalSize = const Size(390, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        var ready = 8;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme133(true),
            home: Scaffold(
              body: RepaintBoundary(
                key: _capture,
                child: ArtworkRevealBoundary(
                  child: StatefulBuilder(
                    builder: (_, state) {
                      update = state;
                      return ListView.builder(
                        controller: scroll,
                        itemExtent: 80,
                        physics: bouncing
                            ? const ArtworkFrontierPhysics(
                                parent: BouncingScrollPhysics(),
                              )
                            : const ArtworkFrontierPhysics(
                                parent: ClampingScrollPhysics(),
                              ),
                        itemCount: 1000,
                        itemBuilder: (_, index) => _Row(index, index < ready),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.fling(
          find.byType(ListView),
          const Offset(0, -2500),
          12000,
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(scroll.offset, lessThanOrEqualTo(225));
        expect(find.text('歌曲 7').hitTestable(), findsOneWidget);
        expect(
          find
              .byType(CupertinoActivityIndicator)
              .evaluate()
              .where((e) => TickerMode.valuesOf(e).enabled)
              .length,
          1,
        );
        await _shot(tester, 'waiting-$bouncing');
        update(() => ready = 16);
        await tester.pump();
        await tester.pump();
        await tester.drag(find.byType(ListView), const Offset(0, -320));
        await tester.pump();
        expect(scroll.offset, greaterThan(225));
        await _shot(tester, 'ready-$bouncing');
        await tester.drag(find.byType(ListView), const Offset(0, 300));
        await tester.pump();
        expect(scroll.offset, lessThan(300));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'data-page footer has one visible loader and replaces it with retry',
    (tester) async {
      var loading = true;
      late StateSetter update;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ArtworkRevealBoundary(
                child: StatefulBuilder(
                  builder: (_, state) {
                    update = state;
                    return ListView.builder(
                      controller: scroll,
                      itemCount: 9,
                      itemBuilder: (_, index) => index < 8
                          ? _Row(index, true)
                          : loading
                          ? const MestingLoadingIndicator()
                          : TextButton(
                              onPressed: () {},
                              child: const Text('重试'),
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();
      await tester.pump();
      expect(
        find
            .byType(CupertinoActivityIndicator)
            .evaluate()
            .where((e) => TickerMode.valuesOf(e).enabled)
            .length,
        1,
      );
      final tree = tester.getSemantics(find.byType(Scaffold)).toStringDeep();
      expect(tree, isNot(contains('内容正在加载')));
      semantics.dispose();
      update(() => loading = false);
      await tester.pump();
      await tester.pump();
      expect(find.text('重试').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
