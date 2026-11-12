import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/library/data/favorite_mutations.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'support/test_tracks.dart';

void main() {
  testWidgets(
    'rapid intent reversals update immediately and send only the final choice',
    (tester) async {
      final writes = <bool>[];
      final ids = <String>{};
      final state = FavoriteMutations(
        confirmed: () => ids,
        write: (_, value) async => writes.add(value),
      );
      final track = testTracks.first;
      final first = state.toggle(track, wasFavorite: false);
      expect(state.apply(ids), {track.id});
      final second = state.toggle(track, wasFavorite: true);
      expect(state.apply(ids), isEmpty);
      expect(await first, isNull);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        await second,
        isNull,
        reason: 'Cancelled net intent needs no server write or success HUD',
      );
      expect(writes, isEmpty);
      final third = state.toggle(track, wasFavorite: false);
      final fourth = state.toggle(track, wasFavorite: true);
      final last = state.toggle(track, wasFavorite: false);
      expect(state.apply(ids), {track.id});
      expect(await third, isNull);
      expect(await fourth, isNull);
      await tester.pump(const Duration(milliseconds: 499));
      expect(writes, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(writes, [true]);
      expect(await last, true);
      expect(
        state.apply(ids),
        {track.id},
        reason: 'Lagging collection read must not undo the receipt',
      );
      ids.add(track.id);
      state.reconcile(ids);
      expect(state.apply(ids), {track.id});
      state.dispose();
    },
  );

  testWidgets(
    'new intent during an active request waits, preserving the newest visual state',
    (tester) async {
      final writes = <bool>[];
      final replies = <Completer<void>>[];
      final state = FavoriteMutations(
        confirmed: () => {},
        write: (_, value) {
          writes.add(value);
          final reply = Completer<void>();
          replies.add(reply);
          return reply.future;
        },
      );
      final track = testTracks.first;
      final first = state.toggle(track, wasFavorite: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(writes, [true]);
      final last = state.toggle(track, wasFavorite: true);
      expect(await first, isNull);
      expect(state.apply({}), isEmpty);
      replies.first.complete();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        state.apply({}),
        isEmpty,
        reason: 'Earlier success cannot overwrite the later unlike',
      );
      expect(writes, [true]);
      await tester.pump(const Duration(milliseconds: 1499));
      expect(writes, [true]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(writes, [true, false]);
      replies.last.complete();
      await tester.pump();
      expect(await last, false);
      state.dispose();
    },
  );

  testWidgets('different songs share one serial, spaced account lane', (
    tester,
  ) async {
    final sent = <String>[];
    final replies = <Completer<void>>[];
    final state = FavoriteMutations(
      confirmed: () => {},
      write: (track, _) {
        sent.add(track.id);
        final reply = Completer<void>();
        replies.add(reply);
        return reply.future;
      },
    );
    final first = state.toggle(testTracks[0], wasFavorite: false);
    final second = state.toggle(testTracks[1], wasFavorite: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(sent, [testTracks[0].id]);
    await tester.pump(const Duration(seconds: 3));
    expect(
      sent,
      hasLength(1),
      reason: 'Elapsed spacing never permits overlapping requests',
    );
    replies.first.complete();
    await tester.pump();
    expect(await first, true);
    expect(sent, [testTracks[0].id, testTracks[1].id]);
    replies.last.complete();
    await tester.pump();
    expect(await second, true);
    state.dispose();
  });

  testWidgets(
    'failure restores acknowledged state, cancels the batch and never retries itself',
    (tester) async {
      var writes = 0;
      final state = FavoriteMutations(
        confirmed: () => {},
        write: (_, _) async {
          writes++;
          throw StateError('refused');
        },
      );
      final first = state.toggle(testTracks[0], wasFavorite: false);
      final failure = expectLater(first, throwsStateError);
      final second = state.toggle(testTracks[1], wasFavorite: false);
      await tester.pump(const Duration(milliseconds: 500));
      await failure;
      expect(await second, isNull);
      expect(state.apply({}), isEmpty);
      await tester.pump(const Duration(minutes: 1));
      expect(writes, 1);
      state.dispose();
    },
  );

  for (final code in ['301', '405', '415', '460']) {
    testWidgets(
      'platform rejection $code retains its actual identity without relabel/retry',
      (tester) async {
        final error = MusicPlatformException('平台原始拒绝', code: code);
        var writes = 0;
        final state = FavoriteMutations(
          confirmed: () => {},
          write: (_, _) async {
            writes++;
            throw error;
          },
        );
        final result = expectLater(
          state.toggle(testTracks.first, wasFavorite: false),
          throwsA(same(error)),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await result;
        await tester.pump(const Duration(seconds: 10));
        expect(writes, 1);
        expect(state.apply({}), isEmpty);
        state.dispose();
      },
    );
  }

  testWidgets(
    'account disposal cancels unsent choices and suppresses an already sent result',
    (tester) async {
      var writes = 0;
      final reply = Completer<void>();
      final unsent = FavoriteMutations(
        confirmed: () => {},
        write: (_, _) async {
          writes++;
        },
      );
      final abandoned = unsent.toggle(testTracks.first, wasFavorite: false);
      unsent.dispose();
      await tester.pump(const Duration(seconds: 2));
      expect(await abandoned, isNull);
      expect(writes, 0);
      final active = FavoriteMutations(
        confirmed: () => {},
        write: (_, _) {
          writes++;
          return reply.future;
        },
      );
      final pending = active.toggle(testTracks.first, wasFavorite: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(writes, 1);
      active.dispose();
      expect(await pending, isNull);
      reply.complete();
      await tester.pump(const Duration(seconds: 3));
      expect(writes, 1);
    },
  );
}
