import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/artwork_reveal_boundary.dart';
import 'package:mesting_music/shared/widgets/artwork_scroll_frontier.dart';
import 'package:mesting_music/shared/widgets/beta_content_insets.dart';
import 'package:mesting_music/shared/widgets/beta_scroll_behavior.dart';
import 'package:mesting_music/shared/widgets/music_loading_geometry.dart';
import 'package:mesting_music/shared/widgets/music_refresh_indicator.dart';

void main() {
  test('nested headers consume safe area and chrome only once', () {
    final root = MusicLoadingGeometry.inWindow(
      origin: 0,
      height: 844,
      windowHeight: 844,
      safeTop: 54,
      chromeBottom: 200,
    );
    final nested = MusicLoadingGeometry.inWindow(
      origin: 140,
      height: 670,
      windowHeight: 844,
      safeTop: 54,
      chromeBottom: 200,
    );
    expect(root.top, 54);
    expect(nested.top, 0);
    expect(root.bottom, 644);
    expect(nested.bottom + 140, root.bottom);
    expect(nested.footer(670), 228); // 166 overlap + 62 for spinner/gaps.
    final top = nested.indicatorTop(cutoff: 442, extent: 32, refreshing: false);
    expect(top, 456);
    expect(nested.bottom - (top + 32), 16);
  });

  for (final boundary in [false, true]) {
    testWidgets('refresh indicator clears centered camera boundary=$boundary', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);
      final refresh = Completer<void>();
      Widget content = MusicRefreshIndicator(
        onRefresh: () => refresh.future,
        child: ListView(children: const [SizedBox(height: 1200)]),
      );
      if (boundary) content = ArtworkRevealBoundary(child: content);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BetaContentInsets(bottom: 204, child: content)),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, 340));
      await tester.pump(const Duration(milliseconds: 300));
      final indicator = find.byType(CupertinoActivityIndicator);
      expect(indicator, findsOneWidget);
      expect(tester.getTopLeft(indicator).dy, greaterThanOrEqualTo(59 + 18));
      refresh.complete();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('waiting fence and spinner share nested list coordinates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const BetaScrollBehavior(),
        home: Scaffold(
          body: BetaContentInsets(
            bottom: 200,
            child: ArtworkRevealBoundary(
              child: Column(
                children: [
                  const SizedBox(height: 100, child: Text('Fixed header')),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      cacheExtent: 500,
                      itemCount: 40,
                      itemBuilder: (_, index) =>
                          _ReadinessRow(index, index < 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 150));
    }
    final frontier = ArtworkScrollFrontier.of(scroll.position)!;
    // Reach the exact fence after the drag's final spring has settled. This
    // checks its measured coordinates independently of platform overscroll.
    scroll.jumpTo(frontier.limit(scroll.position)!);
    await tester.pump();
    final indicator = find.byType(CupertinoActivityIndicator);
    expect(indicator, findsOneWidget);
    // 16dp above the real chrome edge, not 100dp above due to the fixed header.
    expect(tester.getBottomLeft(indicator).dy, closeTo(622, 6));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Deterministic readiness without image codecs/network: exercises the same
/// render registrations and lazy viewport used by actual artwork rows.
class _ReadinessRow extends StatefulWidget {
  const _ReadinessRow(this.index, this.ready);
  final int index;
  final bool ready;
  @override
  State<_ReadinessRow> createState() => _ReadinessRowState();
}

class _ReadinessRowState extends State<_ReadinessRow> {
  ArtworkRevealEntry? entry;
  bool active = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    entry ??= ArtworkRevealBoundary.of(context)?.register(
      () => mounted && active ? context.findRenderObject() as RenderBox? : null,
    );
    entry?.identity = 'row-${widget.index}';
    entry?.update(ready: widget.ready, enabled: true);
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 64, child: Text('Row ${widget.index}'));
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
