import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_connection_models.dart';
import 'package:mesting_music/features/music_platform/netease/netease_connections_controller.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_extended_routes.dart';

class Connections145Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: '7',
    token: 'fixture',
    platform: MusicPlatform.netease,
  );
  void select(String userId, {String token = 'fixture'}) => state = AsyncData(
    PlatformSession(
      userId: userId,
      token: token,
      platform: MusicPlatform.netease,
    ),
  );
}

typedef Connections145Reply =
    FutureOr<Map<String, dynamic>> Function(
      String route,
      Map<String, Object?> query,
    );

/// Every route is intercepted; even an unanticipated API call fails locally.
class Connections145Music extends NeteaseMusicRepository {
  Connections145Music(this.reply)
    : super(
        NeteaseApi(MockClient((_) async => throw StateError('No real traffic')))
          ..configure(
            const NeteaseSession(
              userId: '7',
              deviceId: 'fixture',
              cookies: {'MUSIC_U': 'fixture'},
            ),
          ),
      );
  Connections145Reply reply;
  final calls = <(String, Map<String, Object?>)>[];
  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async {
    calls.add((route, query));
    return reply(route, query);
  }
}

Map<String, dynamic> connection145User(int id, {int? followTime}) => {
  'userId': id,
  'nickname': '用户 ${id.toString().padLeft(3, '0')}',
  'followTime': ?followTime,
};

NeteaseConnectionsController connections145Controller(
  Connections145Music music, {
  bool followers = false,
  bool Function()? isCurrent,
}) => NeteaseConnectionsController(
  repository: NeteaseUserRepository(music),
  userId: '7',
  followers: followers,
  isCurrent: isCurrent ?? () => true,
);

void main() {
  test('official totals retain absent/invalid values and genuine zero', () {
    final missing = NeteasePersonalStats.fromProfile({});
    expect(missing.following, isNull);
    expect(missing.followers, isNull);
    final valid = NeteasePersonalStats.fromProfile({
      'follows': '0',
      'followeds': 41,
    });
    expect(valid.following, 0);
    expect(valid.followers, 41);
    expect(NeteasePersonalStats.fromProfile({'follows': -1}).following, isNull);
    expect(
      NeteasePersonalStats.fromProfile({'follows': 1.4}).following,
      isNull,
    );
  });

  test(
    'official summary verifies the returned account before exposing it',
    () async {
      final music = Connections145Music(
        (route, query) => {
          'code': 200,
          'profile': {'userId': 8, 'follows': 9},
        },
      );
      await expectLater(
        NeteaseUserRepository(music).personalStats('7'),
        throwsException,
      );
      expect(music.calls.single.$2, {'uid': '7'});
    },
  );

  test(
    'following/fan membership supplies the correct mutual-state flags',
    () async {
      final music = Connections145Music(
        (route, query) => {
          'code': 200,
          'more': false,
          route == '/user/follows' ? 'follow' : 'followeds': [
            {...connection145User(42), 'followed': route == '/user/followeds'},
          ],
        },
      );
      final repository = NeteaseUserRepository(music);
      final following = await repository.personalConnections(
        '7',
        followers: false,
        offset: 0,
      );
      expect(following.items.single.user!.followed, true);
      final fans = await repository.personalConnections(
        '7',
        followers: true,
        offset: 0,
      );
      expect(fans.items.single.user!.followed, true);
      expect(fans.items.single.user!.followsMe, true);
    },
  );

  test(
    'raw pagination excludes invalid IDs without consuming the wrong offset',
    () async {
      final music = Connections145Music(
        (route, query) => {
          'code': 200,
          'total': 4,
          'follow': [
            connection145User(42),
            {'userId': '../bad', 'nickname': 'invalid'},
            'invalid row',
          ],
        },
      );
      final page = await NeteaseUserRepository(
        music,
      ).personalConnections('7', followers: false, offset: 0);
      expect(page.items.single.id, '42');
      expect(page.consumed, 3);
      expect(page.more, true);
    },
  );

  test(
    'artists and users with the same numeric ID keep distinct write contracts',
    () async {
      final music = Connections145Music((route, query) => {'code': 200});
      final repository = NeteaseUserRepository(music);
      await repository.follow('42', false);
      await repository.subscribeArtist('42', false);
      await repository.subscribeArtist('42', true);
      expect(music.calls.map((call) => call.$1), [
        '/follow',
        '/artist/sub',
        '/artist/sub',
      ]);
      final unsub = neteaseExtendedRoute(music.calls[1].$1, music.calls[1].$2)!;
      expect(unsub.path, '/api/artist/unsub');
      expect(unsub.data, {'artistId': '42', 'artistIds': '[42]'});
      expect(music.calls[2].$2['subscribe'], true);
    },
  );

  test(
    'unknown/rejected artist response never becomes confirmed success',
    () async {
      final music = Connections145Music((route, query) => {'code': 500});
      await expectLater(
        NeteaseUserRepository(music).subscribeArtist('42', false),
        throwsException,
      );
      await expectLater(
        NeteaseUserRepository(music).subscribeArtist('../42', true),
        throwsException,
      );
      expect(music.calls, hasLength(1));
    },
  );

  test(
    'full following list searches beyond first pages of both namespaces',
    () async {
      final music = Connections145Music((route, query) {
        final artist = route == '/artist/sublist';
        final offset = query['offset']! as int;
        final total = artist ? 42 : 65;
        final end = (offset + 30).clamp(0, total);
        return {
          'code': 200,
          'more': end < total,
          artist ? 'data' : 'follow': [
            for (var i = offset; i < end; i++)
              if (artist)
                {'id': 1000 + i, 'name': '歌手 $i'}
              else
                connection145User(100 + i),
          ],
        };
      });
      final controller = connections145Controller(music);
      await controller.start();
      expect(controller.complete, false);
      expect(music.calls, hasLength(2));
      await controller.loadRemaining();
      expect(controller.complete, true);
      expect(controller.items, hasLength(107));
      expect(music.calls.map((call) => (call.$1, call.$2['offset'])), [
        ('/user/follows', 0),
        ('/artist/sublist', 0),
        ('/user/follows', 30),
        ('/artist/sublist', 30),
        ('/user/follows', 60),
      ]);
      controller.setQuery('164');
      expect(controller.visible.single.id, '164');
      controller.setQuery('歌手 41');
      expect(controller.visible.single.id, '1041');
      controller.setFilter(NeteaseConnectionFilter.users);
      expect(controller.visible, isEmpty);
      controller.setQuery('');
      controller.setSort(NeteaseConnectionSort.name);
      expect(controller.visible.first.id, '100');
      controller.dispose();
    },
  );

  test('fan pagination never loads unrelated artist subscriptions', () async {
    final music = Connections145Music(
      (route, query) => {
        'code': 200,
        'more': false,
        'followeds': [connection145User(42)],
      },
    );
    final controller = connections145Controller(music, followers: true);
    await controller.start();
    expect(controller.complete, true);
    expect(music.calls.single.$1, '/user/followeds');
    expect(controller.visible.single.user!.followsMe, true);
    controller.dispose();
  });

  test(
    'partial page failure retains rows and resumes at the failed raw cursor',
    () async {
      var fail = true;
      final music = Connections145Music((route, query) {
        if (route == '/artist/sublist') return {'data': [], 'more': false};
        final offset = query['offset'] as int;
        if (offset > 0 && fail) throw StateError('fixture page failure');
        return {
          'follow': [connection145User(offset == 0 ? 42 : 43)],
          'more': offset == 0,
        };
      });
      final controller = connections145Controller(music)..setQuery('043');
      await controller.start();
      expect(controller.complete, false);
      expect(controller.error, isNotNull);
      expect(controller.items.single.id, '42');
      expect(controller.visible, isEmpty);
      fail = false;
      await controller.loadRemaining();
      expect(controller.complete, true);
      expect(controller.visible.single.id, '43');
      expect(music.calls.last.$2['offset'], 1);
      controller.dispose();
    },
  );

  test(
    'repeated upstream pages stop with a retry instead of an infinite loop',
    () async {
      var recovered = false;
      final music = Connections145Music((route, query) {
        if (route == '/artist/sublist') return {'data': [], 'more': false};
        final offset = query['offset'] as int;
        return {
          'follow': [connection145User(recovered && offset > 0 ? 43 : 42)],
          'more': !recovered,
        };
      });
      final controller = connections145Controller(music);
      await controller.start();
      expect(controller.complete, false);
      await controller.loadMore();
      expect(controller.error, isNotNull);
      expect(controller.items, hasLength(1));
      expect(music.calls, hasLength(3));
      recovered = true;
      await controller.loadRemaining();
      expect(controller.complete, true);
      expect(controller.items, hasLength(2));
      expect(music.calls.last.$2['offset'], 1);
      controller.dispose();
    },
  );

  test(
    'late pages cannot populate an invalidated or disposed account',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final music = Connections145Music((route, query) => pending.future);
      var current = true;
      final controller = connections145Controller(
        music,
        isCurrent: () => current,
      );
      final loading = controller.start();
      current = false;
      pending.complete({
        'follow': [connection145User(42)],
        'more': false,
      });
      await loading;
      expect(controller.items, isEmpty);
      expect(music.calls, hasLength(1));
      controller.dispose();
    },
  );

  test(
    'refresh is atomic and retains the old usable list after failure',
    () async {
      var phase = 0;
      final music = Connections145Music((route, query) {
        if (phase == 1) throw StateError('refresh failure');
        if (route == '/artist/sublist') return {'data': [], 'more': false};
        return {
          'follow': [connection145User(phase == 0 ? 42 : 43)],
          'more': false,
        };
      });
      final controller = connections145Controller(music);
      await controller.start();
      controller.setQuery('用户');
      controller.setFilter(NeteaseConnectionFilter.users);
      controller.setSort(NeteaseConnectionSort.name);
      phase = 1;
      await controller.refresh();
      expect(controller.items.single.id, '42');
      expect(controller.error, isNotNull);
      phase = 2;
      await controller.refresh();
      expect(controller.items.single.id, '43');
      expect(controller.query, '用户');
      expect(controller.filter, NeteaseConnectionFilter.users);
      expect(controller.sort, NeteaseConnectionSort.name);
      expect(controller.error, isNull);
      controller.dispose();
    },
  );

  test(
    'time ordering requires explicit comparable relation timestamps',
    () async {
      final music = Connections145Music((route, query) {
        if (route == '/artist/sublist') return {'data': [], 'more': false};
        return {
          'follow': [
            {...connection145User(42), 'createTime': 1793700000000},
            connection145User(43, followTime: 1793700000000),
          ],
          'more': false,
        };
      });
      final controller = connections145Controller(music);
      await controller.start();
      expect(controller.canSortByTime, false);
      expect(controller.setSort(NeteaseConnectionSort.followTime), false);
      expect(controller.items.first.followedAt, isNull);
      controller.setQuery('043');
      expect(controller.canSortByTime, true);
      expect(controller.setSort(NeteaseConnectionSort.followTime), true);
      controller.setQuery('');
      expect(controller.sort, NeteaseConnectionSort.official);
      controller.dispose();
    },
  );

  for (final artist in [false, true]) {
    for (final outcome in ['success', 'failure', 'A-B-A']) {
      test(
        '${artist ? 'artist' : 'user'} write is single-flight and account-safe: $outcome',
        () async {
          final pending = Completer<Map<String, dynamic>>();
          var statsReads = 0;
          final music = Connections145Music((route, query) {
            if (route == '/user/detail') {
              statsReads++;
              return {
                'profile': {'userId': 7, 'follows': statsReads, 'followeds': 2},
              };
            }
            return pending.future;
          });
          final container = ProviderContainer(
            overrides: [
              platformAccountProvider.overrideWith(Connections145Account.new),
              neteaseUserRepositoryProvider.overrideWithValue(
                NeteaseUserRepository(music),
              ),
            ],
          );
          await container.read(platformAccountProvider.future);
          final stats = container.listen(
            neteasePersonalStatsProvider,
            (_, next) {},
          );
          await container.read(neteasePersonalStatsProvider.future);
          Future<void> write() => artist
              ? container
                    .read(neteaseArtistRelationsProvider.notifier)
                    .setSubscribed('42', true, previous: false)
              : container
                    .read(neteaseUserRelationsProvider.notifier)
                    .setFollowed('42', true, previous: false);
          final writing = write();
          await write();
          expect(
            music.calls.where((call) => call.$1 != '/user/detail'),
            hasLength(1),
          );
          if (outcome == 'A-B-A') {
            final account =
                container.read(platformAccountProvider.notifier)
                    as Connections145Account;
            account.select('8');
            if (artist) {
              expect(container.read(neteaseArtistRelationsProvider), isEmpty);
            } else {
              expect(container.read(neteaseUserRelationsProvider), isEmpty);
            }
            account.select('7');
            if (artist) {
              expect(container.read(neteaseArtistRelationsProvider), isEmpty);
            } else {
              expect(container.read(neteaseUserRelationsProvider), isEmpty);
            }
          }
          pending.complete({'code': outcome == 'failure' ? 500 : 200});
          if (outcome == 'failure') {
            await expectLater(writing, throwsException);
          } else {
            await writing;
          }
          final state = artist
              ? container.read(neteaseArtistRelationsProvider)['42']
              : container.read(neteaseUserRelationsProvider)['42'];
          expect(
            state?.followed,
            outcome == 'A-B-A' ? null : outcome == 'success',
          );
          expect(state?.busy, outcome == 'A-B-A' ? null : false);
          if (outcome == 'success') {
            await container.read(neteasePersonalStatsProvider.future);
            expect(statsReads, 2);
          }
          stats.close();
          container.dispose();
        },
      );
    }
  }
}
