import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/library/data/favorite_mutations.dart';
import 'package:mesting_music/features/music_platform/domain/membership_badge.dart';
import 'support/test_tracks.dart';

void main() {
  test(
    'favorite changes before response and survives delayed readback',
    () async {
      final done = Completer<void>();
      final ids = <String>{};
      var writes = 0;
      final state = FavoriteMutations(
        quietWindow: Duration.zero,
        minimumWriteInterval: Duration.zero,
        write: (_, next) {
          writes++;
          return done.future;
        },
        confirmed: () => ids,
      );
      addTearDown(state.dispose);
      final track = testTracks.first;
      final pending = state.toggle(track, wasFavorite: false);
      expect(state.apply(ids), {track.id});
      await Future<void>.delayed(Duration.zero);
      expect(writes, 1);
      done.complete();
      expect(await pending, true);
      expect(state.apply(ids), {track.id});
      ids.add(track.id);
      state.reconcile(ids);
      expect(state.apply(ids), {track.id});
    },
  );
  test(
    'failed unlike rolls back a previous success even before collection catches up',
    () async {
      final track = testTracks.first;
      var fail = false;
      final state = FavoriteMutations(
        quietWindow: Duration.zero,
        minimumWriteInterval: Duration.zero,
        write: (_, _) async {
          if (fail) throw StateError('rejected');
        },
        confirmed: () => {},
      );
      addTearDown(state.dispose);
      await state.toggle(track, wasFavorite: false);
      fail = true;
      final pending = state.toggle(track, wasFavorite: true);
      expect(state.apply({}), isEmpty);
      await expectLater(pending, throwsStateError);
      expect(state.apply({}), {track.id});
    },
  );
  test('late result after account disposal has no UI outcome', () async {
    final done = Completer<void>();
    final state = FavoriteMutations(
      write: (_, _) => done.future,
      confirmed: () => {},
    );
    final pending = state.toggle(testTracks.first, wasFavorite: false);
    state.dispose();
    done.complete();
    expect(await pending, isNull);
  });
  test(
    'official membership uses current rights, expiry and highest active tier',
    () {
      final now = DateTime(2026, 11, 10);
      Map<String, dynamic> rights(bool active, int days) => {
        'rights': active,
        'expireTime': now.add(Duration(days: days)).millisecondsSinceEpoch,
      };
      expect(
        neteaseMembershipTier({
          'data': {'redVipLevel': 7},
        }, now),
        isNull,
      );
      expect(
        neteaseMembershipTier({
          'data': {'associator': rights(true, 1), 'redplus': rights(true, -1)},
        }, now),
        MembershipBadgeTier.vip,
      );
      expect(
        neteaseMembershipTier({
          'data': {'associator': rights(true, 1), 'redplus': rights(true, 1)},
        }, now),
        MembershipBadgeTier.svip,
      );
      expect(
        kugouMembershipTier({
          'data': {
            'busi_vip': [
              {
                'product_type': 'tvip',
                'is_vip': 1,
                'vip_end_time': '2026-11-11',
              },
              {
                'product_type': 'svip',
                'is_vip': 1,
                'vip_end_time': '2026-11-09',
              },
            ],
          },
        }, now),
        MembershipBadgeTier.vip,
      );
      expect(
        kugouMembershipTier({
          'data': {
            'busi_vip': [
              {'product_type': 'svip', 'is_vip': 0},
            ],
          },
        }, now),
        isNull,
      );
    },
  );
}
