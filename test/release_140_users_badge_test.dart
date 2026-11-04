import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:pointycastle/export.dart';
import 'package:mesting_music/app/router/app_router.dart' as production;
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/music_platform/data/platform_category_search.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/music_platform/domain/platform_search_user.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_unread.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_crypto.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_repository.dart';
import 'package:mesting_music/features/music_platform/platform_category_search_providers.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';

import 'support/personal_profile_fixture.dart';

const _session = NeteaseSession(
  userId: '7001',
  deviceId: 'fixture',
  cookies: {'MUSIC_U': 'fixture', '__csrf': 'fixture-csrf'},
);
const _user = PlatformSearchUser(id: '42', nickname: '待查看的好友');
const _secret = 'abcdefghijklmnop';

// Observe the actual NeteaseApi request, including the two AES layers. Only
// entropy is fixed for this synthetic fixture; route dispatch stays unmocked.
Map<String, dynamic> _decodeWeapi(http.Request request) {
  Uint8List decode(String value, String key) {
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        false,
        PaddedBlockCipherParameters(
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(key))),
            Uint8List.fromList(utf8.encode('0102030405060708')),
          ),
          null,
        ),
      );
    return cipher.process(base64Decode(value));
  }

  final first = utf8.decode(decode(request.bodyFields['params']!, _secret));
  return Map<String, dynamic>.from(
    jsonDecode(utf8.decode(decode(first, '0CoJUm6Qyw8W8jud'))) as Map,
  );
}

NeteaseApi _api(http.Client client) => NeteaseApi(
  client,
  weapiEncoder: (data) => NeteaseCrypto.weapi(data, secret: _secret),
)..configure(_session);

class _Search extends MusicSearchController {
  @override
  MusicSearchState build() => const MusicSearchState(query: '好友');
}

class _Categories extends CategorySearchController {
  @override
  CategorySearchState build() => const CategorySearchState(
    '好友',
    selected: PlatformSearchKind.users,
    pages: {
      PlatformSearchKind.users: CategorySearchSlice(
        total: 1,
        more: false,
        items: [
          PlatformSearchHit(
            kind: PlatformSearchKind.users,
            id: '42',
            title: '待查看的好友',
            user: _user,
          ),
        ],
      ),
    },
  );
}

class _Users extends NeteaseUserRepository {
  _Users()
    : super(
        NeteaseMusicRepository(
          NeteaseApi(MockClient((_) async => throw StateError('No network'))),
        ),
      );
  final profileReads = <String>[];
  @override
  Future<PlatformSearchUser> profile(String id) async {
    profileReads.add(id);
    return _user;
  }

  @override
  Future<NeteaseUserPage<NeteasePublicPlaylist>> playlists(
    String id,
    int offset,
  ) async => const NeteaseUserPage([], false);
}

void main() {
  setUpAll(() => LiquidGlassWidgets.initialize());

  test(
    'follow and unfollow reach the real encrypted relationship endpoints',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.method, 'POST');
        expect(request.url.host, 'music.163.com');
        expect(request.headers['cookie'], contains('MUSIC_U=fixture'));
        expect(
          request.bodyFields['encSecKey'],
          matches(RegExp(r'^[0-9a-f]{256}$')),
        );
        expect(_decodeWeapi(request), {'csrf_token': 'fixture-csrf'});
        return http.Response('{"code":200}', 200);
      });
      addTearDown(client.close);
      final repository = NeteaseUserRepository(
        NeteaseMusicRepository(_api(client)),
      );
      await repository.follow('42', true);
      await repository.follow('42', false);
      expect(requests.map((r) => r.url.path), [
        '/weapi/user/follow/42',
        '/weapi/user/delfollow/42',
      ]);
      expect(requests.length, 2);
    },
  );

  for (final reply in ['{"code":500}', '{}']) {
    test(
      'a rejected or incomplete follow receipt is not accepted or retried: $reply',
      () async {
        var count = 0;
        final client = MockClient((_) async {
          count++;
          return http.Response(reply, 200);
        });
        addTearDown(client.close);
        final repository = NeteaseUserRepository(
          NeteaseMusicRepository(_api(client)),
        );
        await expectLater(repository.follow('42', true), throwsException);
        expect(count, 1);
      },
    );
  }

  test('invalid and self IDs cannot issue a relationship request', () async {
    var count = 0;
    final client = MockClient((_) async {
      count++;
      return http.Response('{"code":200}', 200);
    });
    addTearDown(client.close);
    final repository = NeteaseUserRepository(
      NeteaseMusicRepository(_api(client)),
    );
    for (final id in ['7001', '../42', '', '0']) {
      await expectLater(repository.follow(id, true), throwsException);
    }
    expect(count, 0);
  });

  test(
    'a late relationship response cannot succeed for a changed account',
    () async {
      final response = Completer<http.Response>();
      var count = 0;
      final client = MockClient((_) {
        count++;
        return response.future;
      });
      addTearDown(client.close);
      final api = _api(client);
      final repository = NeteaseUserRepository(NeteaseMusicRepository(api));
      final write = repository.follow('42', true);
      final rejected = expectLater(write, throwsException);
      api.configure(null);
      response.complete(http.Response('{"code":200}', 200));
      await rejected;
      expect(count, 1);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('unread badges use accessible red and white in dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMestingTheme(
            musicThemePresetById(dark ? 'classic-dark' : 'classic'),
          ),
          home: const Scaffold(
            body: Row(
              children: [
                NeteaseUnreadBadge(0),
                NeteaseUnreadBadge(1),
                NeteaseUnreadBadge(100),
              ],
            ),
          ),
        ),
      );
      final badges = find.byKey(const ValueKey('netease-unread-badge'));
      expect(badges, findsNWidgets(2));
      for (final container in tester.widgetList<Container>(badges)) {
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, NeteaseUnreadColors.background);
      }
      final label = tester.widget<Text>(find.text('99+'));
      expect(label.style!.color, NeteaseUnreadColors.foreground);
      final contrast =
          (NeteaseUnreadColors.foreground.computeLuminance() + .05) /
          (NeteaseUnreadColors.background.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
      expect(find.text('0'), findsNothing);
    });

    for (final entryRoute in ['/music/search', '/profile']) {
      testWidgets(
        'production search opens a visible friend profile and returns to results dark=$dark entry=$entryRoute',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final users = _Users();
          final fixture = await PersonalProfileFixture.create(
            extraOverrides: [
              neteaseUserRepositoryProvider.overrideWithValue(users),
              musicSearchControllerProvider.overrideWith(_Search.new),
              categorySearchProvider.overrideWith(_Categories.new),
              currentMediaItemProvider.overrideWith(
                (ref) => Stream.value(null),
              ),
              platformRewardAutomationProvider.overrideWith((ref) {}),
            ],
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await fixture.dispose();
          });
          production.appRouter.go(entryRoute);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: fixture.container,
              child: MaterialApp.router(
                routerConfig: production.appRouter,
                theme: buildMestingTheme(
                  musicThemePresetById(dark ? 'classic-dark' : 'classic'),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          if (entryRoute == '/profile') {
            await tester.tap(
              find
                  .descendant(
                    of: find.byType(BetaMusicBottomBar),
                    matching: find.byIcon(CupertinoIcons.search),
                  )
                  .hitTestable()
                  .last,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          }
          expect(
            find.byType(NeteaseSearchUserRow).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.text(_user.nickname).hitTestable());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            find.byType(NeteaseUserProfilePage).hitTestable(),
            findsOneWidget,
          );
          expect(find.text('用户主页').hitTestable(), findsOneWidget);
          expect(users.profileReads, ['42']);
          expect(
            Navigator.of(tester.element(find.byType(NeteaseUserProfilePage))),
            production.appRootNavigatorKey.currentState,
          );
          await tester.tap(
            find.descendant(
              of: find.byType(NeteaseUserProfilePage),
              matching: find.byType(BetaGlassBackButton),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(NeteaseUserProfilePage), findsNothing);
          expect(
            find.byType(NeteaseSearchUserRow).hitTestable(),
            findsOneWidget,
          );
          expect(
            fixture.container.read(categorySearchProvider).selected,
            PlatformSearchKind.users,
          );
          expect(
            fixture.container.read(musicSearchControllerProvider).query,
            '好友',
          );
          expect(tester.takeException(), isNull);
        },
        skip: !DistributionChannel.isBeta,
      );
    }
  }
}
