import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_repository.dart';

import 'qishui_signed_api167_test.dart' show FixtureSigner, reply;

QishuiSession account177({String user = '17701'}) => QishuiSession(
  userId: user,
  protocol: QishuiSessionProtocol.web,
  cookies: const [
    {
      'name': 'sessionid',
      'value': 'synthetic-social177-only',
      'domain': 'api.qishui.com',
      'path': '/',
      'secure': 'true',
      'hostOnly': 'true',
    },
  ],
);

Map<String, Object> user177(String id, int state) => {
  'user': {'id': id, 'nickname': '合成用户 $id'},
  'my_user_state': {'follow_status': state},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'official counts and aggregate detail never replace missing with zero',
    () {
      final counts = QishuiSocialStats.parse({
        'my_stats': {
          'count_following': 12,
          'count_follower': '34',
          'count_all_liked': 56,
          'count_luna_following': 2,
          'count_luna_follower': 3,
          'all_comments_liked_detail': {
            'count': 9,
            'popup': {'title': '官方合成标题', 'content': '官方合成说明'},
          },
        },
      });
      expect([counts.following, counts.followers, counts.likes], [12, 34, 56]);
      expect([counts.lunaFollowing, counts.lunaFollowers], [2, 3]);
      expect(counts.commentLikes, 9);
      expect(counts.likesDescription, '官方合成说明');
      final unknown = QishuiSocialStats.parse({
        'my_stats': {
          'count_following': -1,
          'count_follower': 1.5,
          'count_luna_following': 100,
        },
      });
      expect(unknown.following, isNull);
      expect(unknown.followers, isNull);
      expect(unknown.likes, isNull);
      expect(unknown.lunaFollowing, 100);
    },
  );

  test('mixed artist identity never becomes a user ID', () {
    final artist = QishuiSocialPerson.parseMixed({
      'item_type': 'artist',
      'artist': {'id': '999', 'name': '合成歌手'},
      'my_user_state': {'follow_status': 1},
    })!;
    expect(artist.artistId, '999');
    expect(artist.userId, isNull);
    final linked = QishuiSocialPerson.parseMixed({
      'item_type': 'artist',
      'artist': {
        'id': '999',
        'name': '合成歌手',
        'user_info': {'id': '888', 'nickname': '合成歌手账号'},
        'state': {'is_collected': true},
      },
      'my_user_state': {'follow_status': 2},
    })!;
    expect(linked.userId, '888');
    expect(linked.artistId, '999');
    expect(linked.following, isTrue);
    expect(linked.key, 'artist:999');
    expect(linked.artistEntity, isTrue);
    expect(
      QishuiSocialPerson.parseMixed({
        'item_type': 'unknown',
        'user': {'id': '777'},
      }),
      isNull,
    );
  });

  test('private account requests remain pending, never accepted following', () {
    final person = QishuiSocialPerson.parseUserInfo(user177('888', 4), '888');
    expect(person.requested, isTrue);
    expect(person.following, isNull);
    expect(person.relationshipLabel, '已申请');
    expect(
      () => QishuiSocialPerson.parseUserInfo(user177('777', 1), '888'),
      throwsA(isA<QishuiException>()),
    );
  });

  test(
    'missing/repeated continuation keeps rows without an endless cursor',
    () {
      final page = QishuiSocialPage.parse({
        'follow_items': [
          {
            'item_type': 'user',
            'user': {'id': '888', 'nickname': '甲'},
          },
          {
            'item_type': 'user',
            'user': {'id': '888', 'nickname': '甲'},
          },
        ],
        'has_more': true,
        'next_cursor': 'same',
      }, 'same');
      expect(page.items, hasLength(1));
      expect(page.hasMore, isFalse);
      expect(page.continuationProblem, isNotEmpty);
    },
  );

  test(
    'statistics fallback uses exact common user info and checks identity',
    () async {
      final paths = <String>[];
      final api = QishuiApi(
        MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path == '/luna/pc/me') {
            return reply({
              'my_info': {'id': '17701'},
            });
          }
          expect(r.method, 'GET');
          expect(r.url.path, '/luna/user/info');
          expect(r.url.queryParameters['user_id'], '17701');
          expect(r.headers['x-helios'], 'fixture-helios');
          return reply({
            ...user177('17701', 0),
            'user_stats': {'count_following': 7, 'count_follower': 8},
          });
        }),
        signer: FixtureSigner(),
      )..configure(account177());
      addTearDown(api.dispose);
      final stats = await QishuiSocialRepository(
        QishuiRepository(api),
      ).fetchStats();
      expect(stats.following, 7);
      expect(stats.followers, 8);
      expect(paths, ['/luna/pc/me', '/luna/user/info']);
    },
  );

  test(
    'profile identity mismatch refuses fallback into another account',
    () async {
      var calls = 0;
      final api = QishuiApi(
        MockClient((r) async {
          calls++;
          return reply({
            'my_info': {'id': '17799'},
          });
        }),
        signer: FixtureSigner(),
      )..configure(account177());
      addTearDown(api.dispose);
      await expectLater(
        QishuiSocialRepository(QishuiRepository(api)).fetchStats(),
        throwsA(isA<QishuiException>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'official groups keep their own scene, first cursor and server cursor',
    () async {
      final cursors = <String>[];
      final api = QishuiApi(
        MockClient((r) async {
          expect(r.url.path, '/luna/users/17701/following');
          expect(
            r.url.queryParameters['scene'],
            cursors.length < 2 ? '2' : '1',
          );
          expect(r.url.queryParameters['count'], '20');
          cursors.add(r.url.queryParameters['cursor']!);
          return reply({
            'follow_items': [],
            'has_more': cursors.length == 1,
            'next_cursor': 'opaque-next',
          });
        }),
        signer: FixtureSigner(),
      )..configure(account177());
      addTearDown(api.dispose);
      final repo = QishuiSocialRepository(QishuiRepository(api));
      final first = await repo.list(QishuiFollowListKind.following);
      await repo.list(
        QishuiFollowListKind.following,
        cursor: first.nextCursor!,
      );
      await repo.list(
        QishuiFollowListKind.following,
        source: QishuiFollowSource.douyin,
      );
      expect(cursors, ['', 'opaque-next', '']);
    },
  );

  test(
    'follow signs exact form and requires same ID plus official readback',
    () async {
      var state = 0, writes = 0;
      final signer = FixtureSigner();
      final api = QishuiApi(
        MockClient((r) async {
          if (r.url.path == '/luna/user/info') {
            return reply(user177('17702', state));
          }
          expect(r.url.path, '/luna/me/follow');
          expect(r.method, 'POST');
          expect(
            r.headers['content-type'],
            startsWith('application/x-www-form-urlencoded'),
          );
          expect(r.body, 'user_id=17702');
          expect(r.body, signer.signedBody);
          expect(signer.signedHeaders!['cookie'], isNull);
          state = 1;
          writes++;
          return reply({'user_id': '17702', 'follow_status': state});
        }),
        signer: signer,
      )..configure(account177());
      addTearDown(api.dispose);
      final changed = await QishuiSocialRepository(
        QishuiRepository(api),
      ).setFollowing('17702', true);
      expect(changed.following, isTrue);
      expect(writes, 1);
    },
  );

  test(
    'unknown mutation stays pending and explicit retry does not repeat it',
    () async {
      var writes = 0;
      final api = QishuiApi(
        MockClient((r) async {
          if (r.url.path == '/luna/user/info') {
            return reply(user177('17703', 0));
          }
          writes++;
          return http.Response('', 503);
        }),
        signer: FixtureSigner(),
      )..configure(account177());
      addTearDown(api.dispose);
      final repo = QishuiSocialRepository(QishuiRepository(api));
      for (var i = 0; i < 2; i++) {
        await expectLater(
          repo.setFollowing('17703', true),
          throwsA(
            isA<QishuiException>().having(
              (e) => e.unknownWrite,
              'unknown',
              true,
            ),
          ),
        );
      }
      expect(writes, 1);
    },
  );

  test('response identity mismatch cannot report confirmed follow', () async {
    var state = 0;
    final api = QishuiApi(
      MockClient((r) async {
        if (r.url.path == '/luna/user/info') {
          return reply(user177('17704', state));
        }
        state = 1;
        return reply({'user_id': '17705', 'follow_status': 1});
      }),
      signer: FixtureSigner(),
    )..configure(account177());
    addTearDown(api.dispose);
    await expectLater(
      QishuiSocialRepository(QishuiRepository(api)).setFollowing('17704', true),
      throwsA(
        isA<QishuiException>().having((e) => e.unknownWrite, 'unknown', true),
      ),
    );
  });

  test('outgoing repository never sends through a replacement login', () async {
    var calls = 0;
    final api = QishuiApi(
      MockClient((r) async {
        calls++;
        return reply({});
      }),
      signer: FixtureSigner(),
    )..configure(account177());
    addTearDown(api.dispose);
    final repo = QishuiSocialRepository(QishuiRepository(api));
    api.configure(account177(user: '17799'));
    await expectLater(
      repo.list(QishuiFollowListKind.followers),
      throwsA(isA<QishuiException>()),
    );
    expect(calls, 0);
  });

  test(
    'pure and linked artists use artist JSON endpoints and official membership',
    () async {
      var member = false, writes = 0;
      final signer = FixtureSigner();
      final api = QishuiApi(
        MockClient((r) async {
          expect(r.url.path, '/luna/me/collection/artist');
          if (r.method == 'GET') {
            return reply({
              'artists': member
                  ? [
                      {'id': '17720', 'name': '合成歌手'},
                    ]
                  : [],
              'has_more': false,
              'next_cursor': '',
            });
          }
          writes++;
          expect(r.headers['content-type'], startsWith('application/json'));
          expect(jsonDecode(r.body), {
            'artist_ids': ['17720'],
          });
          expect(r.body, signer.signedBody);
          expect(jsonDecode(r.body), isNot(contains('user_id')));
          member = true;
          return reply({
            'artist_ids': ['17720'],
            'collect_artist_status': {'17720': 0},
          });
        }),
        signer: signer,
      )..configure(account177());
      addTearDown(api.dispose);
      final artist = QishuiSocialPerson.parseMixed({
        'item_type': 'artist',
        'artist': {
          'id': '17720',
          'name': '合成歌手',
          'user_info': {'id': '17721', 'nickname': '关联账号'},
          'state': {'is_collected': false},
        },
      })!;
      final changed = await QishuiSocialRepository(
        QishuiRepository(api),
      ).setArtistFollowing(artist, true);
      expect(changed.key, 'artist:17720');
      expect(changed.following, isTrue);
      expect(writes, 1);
    },
  );

  test(
    'artist readback cannot treat a partial collection as unfollowed',
    () async {
      final api = QishuiApi(
        MockClient(
          (r) async =>
              reply({'artists': [], 'has_more': true, 'next_cursor': ''}),
        ),
        signer: FixtureSigner(),
      )..configure(account177());
      addTearDown(api.dispose);
      await expectLater(
        QishuiSocialRepository(QishuiRepository(api)).artistMembership('17722'),
        throwsA(isA<QishuiException>()),
      );
    },
  );

  test('unfollow artist uses delete receipt and exhausts pagination', () async {
    var member = true;
    final paths = <String>[];
    final api = QishuiApi(
      MockClient((r) async {
        paths.add('${r.method} ${r.url.path}');
        if (r.method == 'GET') {
          return reply({
            'artists': member
                ? [
                    {'id': '17723'},
                  ]
                : [],
            'has_more': false,
          });
        }
        expect(r.url.path, '/luna/me/collection/artist/delete');
        expect(jsonDecode(r.body), {
          'artist_ids': ['17723'],
        });
        member = false;
        return reply({
          'deleted_artists': ['17723'],
        });
      }),
      signer: FixtureSigner(),
    )..configure(account177());
    addTearDown(api.dispose);
    final artist = QishuiSocialPerson.parseMixed({
      'item_type': 'artist',
      'artist': {'id': '17723', 'name': '合成歌手'},
    })!;
    final changed = await QishuiSocialRepository(
      QishuiRepository(api),
    ).setArtistFollowing(artist, false);
    expect(changed.following, isFalse);
    expect(paths, [
      'GET /luna/me/collection/artist',
      'POST /luna/me/collection/artist/delete',
      'GET /luna/me/collection/artist',
    ]);
  });

  test(
    'self or path injection can never become an authenticated mutation',
    () async {
      var calls = 0;
      final api = QishuiApi(
        MockClient((r) async {
          calls++;
          return reply({});
        }),
        signer: FixtureSigner(),
      )..configure(account177());
      addTearDown(api.dispose);
      final repo = QishuiSocialRepository(QishuiRepository(api));
      for (final id in ['17701', '../17702', '17702?x=1']) {
        await expectLater(
          repo.setFollowing(id, true),
          throwsA(isA<QishuiException>()),
        );
      }
      expect(calls, 0);
    },
  );
}
