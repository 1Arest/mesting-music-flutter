import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/playback_scrub_controller.dart';

void main() {
  test('drag stays at the finger while old engine positions arrive', () {
    final scrub = PlaybackScrubController();
    addTearDown(scrub.dispose);
    scrub.begin(40000);
    scrub.update(90000);
    scrub.observe(const Duration(seconds: 12));
    expect(scrub.previewMilliseconds, 90000);
  });

  test(
    'a cached nearby tick cannot pull a fine seek back on release',
    () async {
      final scrub = PlaybackScrubController();
      addTearDown(scrub.dispose);
      scrub.observe(const Duration(milliseconds: 39500));
      await scrub.commit(40000, (_) async {});
      expect(scrub.previewMilliseconds, 40000);
      scrub.observe(const Duration(milliseconds: 39700));
      expect(scrub.previewMilliseconds, 40000);
      scrub.observe(const Duration(seconds: 40));
      expect(scrub.previewMilliseconds, isNull);
    },
  );

  test(
    'slow playing seek hands off to the confirmed advancing engine clock',
    () async {
      final scrub = PlaybackScrubController();
      addTearDown(scrub.dispose);
      final gate = Completer<void>();
      scrub.observe(const Duration(seconds: 20));
      final command = scrub.commit(
        40000,
        (_) => gate.future,
        confirmedPosition: () => const Duration(seconds: 42),
      );
      scrub.observe(const Duration(seconds: 42));
      expect(scrub.previewMilliseconds, 40000);
      gate.complete();
      await command;
      expect(scrub.previewMilliseconds, isNull);
    },
  );

  test(
    'same-position paused seek finishes when equal stream data is deduplicated',
    () async {
      final scrub = PlaybackScrubController();
      addTearDown(scrub.dispose);
      scrub.observe(const Duration(seconds: 40));
      await scrub.commit(40000, (_) async {});
      expect(scrub.previewMilliseconds, isNull);
    },
  );

  test(
    'release requests audio once and waits for the position acknowledgement',
    () async {
      final scrub = PlaybackScrubController();
      addTearDown(scrub.dispose);
      final gate = Completer<void>();
      final seeks = <Duration>[];
      scrub.begin(30000);
      scrub.update(90000);
      expect(seeks, isEmpty);
      final command = scrub.commit(90000, (position) {
        seeks.add(position);
        return gate.future;
      });
      scrub.observe(const Duration(seconds: 12));
      gate.complete();
      await command;
      expect(seeks, [const Duration(seconds: 90)]);
      expect(scrub.previewMilliseconds, 90000);
      scrub.observe(const Duration(seconds: 90));
      expect(scrub.previewMilliseconds, isNull);
    },
  );

  test('an earlier seek completion cannot clear a second live drag', () async {
    final scrub = PlaybackScrubController();
    addTearDown(scrub.dispose);
    final gate = Completer<void>();
    final first = scrub.commit(90000, (_) => gate.future);
    scrub.begin(60000);
    scrub.update(40000);
    scrub.observe(const Duration(seconds: 90));
    gate.complete();
    await first;
    expect(scrub.previewMilliseconds, 40000);
    await scrub.commit(40000, (_) async {});
    expect(scrub.previewMilliseconds, 40000);
    scrub.observe(const Duration(seconds: 40));
    expect(scrub.previewMilliseconds, isNull);
  });

  test(
    'track changes cancel old completions even when returning to the same ID',
    () async {
      final scrub = PlaybackScrubController();
      addTearDown(scrub.dispose);
      final gate = Completer<void>();
      final old = scrub.commit(90000, (_) => gate.future);
      scrub.reset();
      scrub.reset();
      scrub.begin(12000);
      gate.complete();
      await old;
      expect(scrub.previewMilliseconds, 12000);
    },
  );

  test(
    'a failed latest seek releases its preview and reports the error',
    () async {
      final scrub = PlaybackScrubController();
      addTearDown(scrub.dispose);
      await expectLater(
        scrub.commit(90000, (_) async => throw StateError('fixture')),
        throwsStateError,
      );
      expect(scrub.previewMilliseconds, isNull);
    },
  );
}
