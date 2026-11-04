import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/platform_category_search.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_providers.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: '7',
    token: 'fixture',
    platform: MusicPlatform.netease,
  );
  void switchOwner() => state = const AsyncData(
    PlatformSession(
      userId: '8',
      token: 'other',
      platform: MusicPlatform.netease,
    ),
  );
}

class _Music extends NeteaseMusicRepository {
  _Music()
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
  final calls = <(String, Map<String, Object?>)>[];
  Map<String, dynamic> reply = {'code': 200};
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> call(
    String route, [
    Map<String, Object?> query = const {},
    Future<void>? abort,
  ]) async {
    calls.add((route, query));
    return pending?.future ?? reply;
  }
}

void main() {
  test(
    'user category sends type 1002, keeps upstream IDs and paginates by 30',
    () async {
      final music = _Music()
        ..reply = {
          'code': 200,
          'result': {
            'userprofileCount': 31,
            'userprofiles': [
              {
                'userId': 42,
                'nickname': '<em>薛</em>之谦',
                'signature': '音乐',
                'followed': true,
                'avatarUrl': 'https://image.example/avatar.jpg',
              },
            ],
          },
        };
      final page = await music.category(
        '薛之谦',
        PlatformSearchKind.users,
        page: 1,
      );
      expect(music.calls.single.$2, containsPair('type', 1002));
      expect(music.calls.single.$2, containsPair('limit', 30));
      expect(page.items.single.id, '42');
      expect(page.items.single.title, '薛之谦');
      expect(page.items.single.user?.followed, true);
      expect(page.hasMore, true);
      await music.category('薛之谦', PlatformSearchKind.users, page: 2);
      expect(music.calls.last.$2, containsPair('offset', 30));
    },
  );

  test(
    'public profile and playlists expose only public data and advance raw offset',
    () async {
      final music = _Music()
        ..reply = {
          'code': 200,
          'level': 8,
          'profile': {
            'userId': 42,
            'nickname': '用户',
            'follows': 3,
            'followeds': 9,
          },
        };
      final repository = NeteaseUserRepository(music);
      final profile = await repository.profile('42');
      expect(profile.level, 8);
      expect(profile.followers, 9);
      music.reply = {
        'code': 200,
        'more': true,
        'playlist': [
          {'id': 1, 'privacy': 10, 'name': 'private'},
          {
            'id': 2,
            'privacy': 0,
            'name': 'public',
            'trackCount': 3,
            'creator': {'userId': 42},
          },
        ],
      };
      final page = await repository.playlists('42', 30);
      expect(page.items.single.name, 'public');
      expect(page.consumed, 2);
      expect(music.calls.last.$2, containsPair('offset', 30));
      expect(page.more, true);
    },
  );

  test(
    'follow writes use actual ID/t, reject self and do not accept rejected status',
    () async {
      final music = _Music();
      final repository = NeteaseUserRepository(music);
      await repository.follow('42', true);
      await repository.follow('42', false);
      expect(music.calls.map((v) => v.$2['t']), [1, 0]);
      expect(music.calls.first.$1, '/follow');
      await expectLater(repository.follow('7', true), throwsException);
      await expectLater(repository.follow('../42', true), throwsException);
      music.reply = {'code': 500};
      await expectLater(repository.follow('42', true), throwsException);
      expect(music.calls.length, 3);
    },
  );

  for (final outcome in ['success', 'failure', 'account switch']) {
    test(
      'relationship single-flight and confirmed shared state: $outcome',
      () async {
        final music = _Music()..pending = Completer<Map<String, dynamic>>();
        final c = ProviderContainer(
          overrides: [
            platformAccountProvider.overrideWith(_Account.new),
            neteaseUserRepositoryProvider.overrideWithValue(
              NeteaseUserRepository(music),
            ),
          ],
        );
        await c.read(platformAccountProvider.future);
        final changes = c.read(neteaseUserRelationsProvider.notifier);
        final first = changes.setFollowed('42', true, previous: false);
        await changes.setFollowed('42', true, previous: false);
        expect(music.calls.length, 1);
        expect(c.read(neteaseUserRelationsProvider)['42']?.busy, true);
        if (outcome == 'account switch') {
          (c.read(platformAccountProvider.notifier) as _Account).switchOwner();
          expect(c.read(neteaseUserRelationsProvider), isEmpty);
        }
        music.pending!.complete({'code': outcome == 'failure' ? 500 : 200});
        if (outcome == 'failure') {
          await expectLater(first, throwsException);
        } else {
          await first;
        }
        final relation = c.read(neteaseUserRelationsProvider)['42'];
        if (outcome == 'account switch') {
          expect(relation, isNull);
        } else {
          expect(relation?.followed, outcome == 'success');
          expect(relation?.busy, false);
        }
        c.dispose();
      },
    );
  }
}
