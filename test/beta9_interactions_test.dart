import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/player/presentation/beta_playback_actions.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/automatic_song_paging.dart';
import 'package:mesting_music/shared/widgets/overflow_marquee.dart';

Track song(String id) => Track(
  id: id,
  title: id,
  artist: '',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'assets/$id.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

/// UI boundary records the selected command; the real handler/engine queue
/// transitions are exercised separately in beta9_playback_test.dart.
class SelectionHandler implements MestingAudioHandler {
  SelectionHandler({this.pending = const []});
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> debugDispose() async {}
  final List<MediaItem> pending;
  String? selected;
  bool? replace;
  List<Track>? all;
  @override
  List<MediaItem> get manuallyQueuedItems => pending;
  @override
  Track? trackForId(String id) => song(id);
  @override
  Future<void> playSingleTrack(
    Track track, {
    bool autoplay = true,
    bool fromHistory = false,
    Iterable<Track>? playbackContext,
    bool preservePendingAdvance = false,
    Track? returnToUpcoming,
    bool replaceUpcoming = false,
    bool discardRecommendations = false,
    bool Function()? isCurrent,
  }) async {
    selected = track.id;
    replace = replaceUpcoming;
  }

  @override
  Future<void> replaceQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool autoplay = true,
    bool recommendationContext = false,
    bool Function()? togetherGuard,
  }) async {
    if (togetherGuard?.call() == false) return;
    all = tracks;
  }
}

void main() {
  for (final hasPending in [false, true]) {
    testWidgets(
      'single selection starts immediately with pending=$hasPending',
      (tester) async {
        final handler = SelectionHandler(
          pending: hasPending
              ? [song('B').toMediaItem(), song('C').toMediaItem()]
              : [],
        );
        addTearDown(handler.debugDispose);

        final container = ProviderContainer(
          overrides: [audioHandlerProvider.overrideWithValue(handler)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed: () => playBetaSelection(context, ref, song('D')),
                    child: const Text('点播'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('点播'));
        await tester.pumpAndSettle();
        expect(handler.selected, 'D');
        expect(handler.replace, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'Play All replaces the pending queue after an immediate single tap',
    (tester) async {
      final handler = SelectionHandler(pending: [song('old').toMediaItem()]);
      final collection = [song('A'), song('B'), song('C')];
      addTearDown(handler.debugDispose);
      final container = ProviderContainer(
        overrides: [audioHandlerProvider.overrideWithValue(handler)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () =>
                          playBetaSelection(context, ref, song('A')),
                      child: const Text('单首'),
                    ),
                    TextButton(
                      onPressed: () => playBetaSelection(
                        context,
                        ref,
                        song('A'),
                        playAll: collection,
                      ),
                      child: const Text('播放全部'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('单首'));
      await tester.pumpAndSettle();
      expect(handler.manuallyQueuedItems.map((item) => item.id), ['old']);
      expect(handler.replace, isFalse);
      await tester.tap(find.text('播放全部'));
      collection.clear();
      await tester.pumpAndSettle();
      expect(handler.selected, 'A');
      expect(handler.all!.map((track) => track.id), ['A', 'B', 'C']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'automatic paging fills a short viewport and coalesces scroll requests',
    (tester) async {
      var count = 2, requests = 0;
      var more = true;
      final first = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: AutomaticSongPaging(
                enabled: more,
                onLoadMore: () async {
                  requests++;
                  if (requests == 1) {
                    await first.future;
                    setState(() => count = 32);
                  } else {
                    setState(() => more = false);
                  }
                },
                child: ListView.builder(
                  itemCount: count,
                  itemExtent: 72,
                  itemBuilder: (_, index) => Text('歌曲 $index'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(requests, 1);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(requests, 1);
      first.complete();
      await tester.pump();
      await tester.pump();
      expect(requests, 1);
      await tester.drag(find.byType(ListView), const Offset(0, -2400));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('加载更多'), findsNothing);
    },
  );
  testWidgets(
    'a long detail title stays on one line and translates only when overflowing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 220,
                child: OverflowMarquee(
                  '暖场小曲：深夜酒吧的走心时刻',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final text = find.text('暖场小曲：深夜酒吧的走心时刻');
      final start = tester.getTopLeft(text).dx;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.getTopLeft(text).dx, lessThan(start));
      expect(tester.widget<Text>(text).maxLines, 1);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
