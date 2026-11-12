import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_recommendations_page.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/artwork_reveal_boundary.dart';
import 'package:mesting_music/shared/widgets/artwork_scroll_frontier.dart';
import 'package:mesting_music/shared/widgets/beta_content_insets.dart';
import 'package:mesting_music/shared/widgets/beta_scroll_behavior.dart';
import 'package:mesting_music/shared/widgets/music_refresh_indicator.dart';
import 'package:mesting_music/shared/widgets/music_loading_geometry.dart';
import 'support/personal_profile_fixture.dart';
import 'support/release_144_qa.dart';
import 'release_148_ui_test.dart' show mount148, song148;

void main() {
  setUpAll(initialize144QA);
  test(
    'a later batch with zero revealed extent keeps its trailing indicator',
    () {
      const geometry = MusicLoadingGeometry(top: 0, bottom: 640);
      expect(
        geometry.indicatorTop(
          cutoff: 0,
          extent: 32,
          refreshing: false,
          initialLoading: false,
        ),
        592,
      );
      expect(
        geometry.indicatorTop(
          cutoff: 0,
          extent: 32,
          refreshing: false,
          initialLoading: true,
        ),
        304,
      );
    },
  );
  testWidgets(
    'forward drag never claims refresh; later-content wait stays below songs',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      ArtworkRevealController? reveal;
      final refresh = Completer<void>();
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const BetaScrollBehavior(),
          home: Scaffold(
            body: BetaContentInsets(
              bottom: 180,
              child: Column(
                children: [
                  const SizedBox(height: 100, child: Text('每日推荐')),
                  Expanded(
                    child: ArtworkRevealBoundary(
                      child: Builder(
                        builder: (context) {
                          reveal = ArtworkRevealBoundary.of(context);
                          return MusicRefreshIndicator(
                            onRefresh: () {
                              refreshes++;
                              return refresh.future;
                            },
                            child: ListView.builder(
                              controller: scroll,
                              cacheExtent: 500,
                              itemCount: 60,
                              itemBuilder: (_, i) => _StageRow(i, i < 25),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Material RefreshIndicator announces drag at scroll start before it knows
      // the direction. A normal start at the first song must not paint refresh.
      ScrollStartNotification(
        metrics: scroll.position,
        context: tester.element(find.byType(ListView)),
        dragDetails: DragStartDetails(),
      ).dispatch(tester.element(find.byType(ListView)));
      await tester.pump();
      expect(reveal!.refreshing, isFalse);
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -180));
        await tester.pump(const Duration(milliseconds: 120));
      }
      final fence = ArtworkScrollFrontier.of(
        scroll.position,
      )!.limit(scroll.position)!;
      scroll.jumpTo(fence);
      await tester.pump();
      expect(reveal!.refreshing, isFalse);
      expect(refreshes, 0);
      final indicator = find.byType(CupertinoActivityIndicator);
      expect(indicator, findsOneWidget);
      expect(tester.getTopLeft(indicator).dy, greaterThan(560));
      expect(tester.getBottomLeft(indicator).dy, lessThanOrEqualTo(844 - 180));
      // Genuine leading refresh positioning is covered by the shared geometry
      // tests; this test keeps its entire gesture sequence toward later songs.
      refresh.complete();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets('daily refresh keeps actual mounted songs and scroll offset', (
    tester,
  ) async {
    final pending = Completer<List<Track>>();
    var reads = 0;
    final tracks = [for (var i = 0; i < 65; i++) song148(i)];
    final fixture = await PersonalProfileFixture.create(
      extraOverrides: [
        platformDailyProvider.overrideWith(
          (ref) async => ++reads == 1 ? tracks : pending.future,
        ),
      ],
    );
    await mount148(
      tester,
      fixture,
      const PlatformRecommendationDetail(title: '每日推荐'),
      dark: true,
    );
    final list = find.byType(ListView).first;
    await tester.drag(list, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 300));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    final before = position.pixels;
    fixture.container.invalidate(platformDailyProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(ListView), findsOneWidget);
    expect(position.pixels, closeTo(before, 1));
    pending.complete(tracks);
    await tester.pump(const Duration(milliseconds: 400));
    expect(position.pixels, closeTo(before, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await fixture.dispose();
  });
}

/// Deterministic image/data readiness uses the production render registration,
/// including lazy cache rows. No CDN latency or image placeholder is simulated.
class _StageRow extends StatefulWidget {
  const _StageRow(this.index, this.ready);
  final int index;
  final bool ready;
  @override
  State<_StageRow> createState() => _StageRowState();
}

class _StageRowState extends State<_StageRow> {
  ArtworkRevealEntry? entry;
  bool active = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    entry ??= ArtworkRevealBoundary.of(context)?.register(
      () => mounted && active ? context.findRenderObject() as RenderBox? : null,
    );
    entry?.identity = 'stage-${widget.index}';
    entry?.update(ready: widget.ready, enabled: true);
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 70, child: Text('歌曲 ${widget.index}'));
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
