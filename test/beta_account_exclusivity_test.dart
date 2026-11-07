import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/beta_account_choice.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/auth/presentation/auth_page.dart';
import 'package:mesting_music/features/auth/presentation/first_launch_auth_coordinator.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/profile/presentation/profile_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_discovery_page.dart';
import 'package:mesting_music/features/settings/presentation/settings_page.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/search/data/hot_music_repository.dart';
import 'package:mesting_music/features/auth/account_capabilities.dart';
import 'package:mesting_music/features/auth/presentation/auth_protected_page.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_avatar.dart';
import 'package:mesting_music/features/player/presentation/music_hub_top_bar.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comments_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';

class _Store implements PlatformSessionStore {
  PlatformSession? value;
  @override
  Future<PlatformSession?> read() async => value;
  @override
  Future<void> write(PlatformSession session) async {
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

class _Legacy extends UnconfiguredAuthRepository {
  int restores = 0;
  final pending = Completer<AuthSession?>();
  @override
  Future<AuthSession?> restoreSession() {
    restores++;
    return pending.future;
  }
}

void main() {
  late SharedPreferences preferences;
  late _Store store;
  late _Legacy legacy;
  late MusicPlatformApi api;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    store = _Store();
    legacy = _Legacy();
    api = MusicPlatformApi(
      server: _Server(),
      client: MockClient(
        (_) async => http.Response('{"status":1,"data":[]}', 200),
      ),
    );
  });
  overrides() => [
    sharedPreferencesProvider.overrideWithValue(preferences),
    platformSessionStoreProvider.overrideWithValue(store),
    musicPlatformApiProvider.overrideWithValue(api),
    authRepositoryProvider.overrideWithValue(legacy),
    playlistsProvider.overrideWith((ref) => Stream.value([])),
    favoriteTracksProvider.overrideWith((ref) => Stream.value([])),
    appVersionProvider.overrideWith(
      (ref) async => const AppVersionInfo(
        packageName: 'com.mesting.music.beta',
        versionName: '1.0.37-beta.2',
        versionCode: 2,
      ),
    ),
    hotMusicRepositoryProvider.overrideWith(
      (ref) => HotMusicRepository(
        rankingLoader: ({int limit = 9}) async => [],
        preferences: preferences,
        localTracks: [],
      ),
    ),
  ];

  test(
    'platform login defeats delayed CloudBase restoration and logout persists guest choice',
    () async {
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      container.read(authControllerProvider);
      await container.read(platformAccountProvider.future);
      await container.read(platformAccountProvider.notifier).accept({
        'userid': '7',
        'token': 'test',
        'nickname': '酷狗昵称',
      });
      legacy.pending.complete(
        AuthSession(
          user: const AuthUser(uid: 'old', nickname: '旧账号'),
          accessToken: 'old',
          refreshToken: '',
          expiresAt: DateTime(2100),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserProvider), null);
      expect(container.read(platformAccountProvider).value?.userId, '7');
      await container.read(platformAccountProvider.notifier).signOut();
      expect(
        container.read(betaAccountChoiceProvider),
        BetaAccountChoice.guest,
      );
      expect(api.session, null);
      final restarted = ProviderContainer(overrides: overrides());
      addTearDown(restarted.dispose);
      expect(await restarted.read(authControllerProvider.future), null);
      expect(await restarted.read(platformAccountProvider.future), null);
      expect(legacy.restores, 1);
    },
    skip: !DistributionChannel.isBeta,
  );

  test(
    'Mesting selection blocks a stale platform login callback',
    () async {
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await container
          .read(betaAccountChoiceProvider.notifier)
          .select(BetaAccountChoice.mesting);
      await expectLater(
        container.read(platformAccountProvider.notifier).accept({
          'userid': '7',
          'token': 'test',
        }),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(store.value, null);
      expect(api.session, null);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'Kugou profile hides old login; logout restores welcome and all choices',
    (tester) async {
      store.value = const PlatformSession(
        userId: '7',
        token: 'test',
        nickname: '酷狗昵称',
      );
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ProfilePage())),
        ),
      );
      await tester.pump();
      expect(find.text('酷狗昵称'), findsOneWidget);
      expect(find.text('登录或创建账号'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('我喜欢的音乐'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('我喜欢的音乐'), findsOneWidget);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AuthPage(initialMode: 'login', redirect: '/profile'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Mesting 账号登录 / 注册'), findsNothing);
      expect(find.text('退出登录'), findsOneWidget);
      await container.read(platformAccountProvider.notifier).signOut();
      await tester.pump();
      expect(find.text('酷狗登录'), findsOneWidget);
      expect(find.text('网易云登录'), findsOneWidget);
      // Three platform entries can put consent below a short viewport.
      await tester.ensureVisible(find.bySemanticsLabel('我已阅读并同意用户协议和隐私政策'));
      await tester.tap(find.bySemanticsLabel('我已阅读并同意用户协议和隐私政策'));
      await tester.ensureVisible(find.text('酷狗登录'));
      await tester.pump();
      await tester.tap(find.text('酷狗登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Mesting 账号登录'), findsNothing);
      expect(find.text('酷狗扫码登录'), findsOneWidget);
      expect(find.text('QQ 扫码登录'), findsOneWidget);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'Beta discovery renders upstream content and settings show the current account only',
    (tester) async {
      final paths = <String>[];
      api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'status': 1,
              'data': request.url.path == '/top/playlist'
                  ? [
                      {'global_collection_id': 'gid-1', 'name': '真实接口精选歌单'},
                    ]
                  : [
                      {
                        'hash': 'HASH',
                        'songname': '真实接口每日推荐',
                        'singername': '测试歌手',
                      },
                    ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      store.value = const PlatformSession(
        userId: '7',
        token: 'test',
        nickname: '酷狗昵称',
      );
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: PlatformDiscoveryPage()),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('酷狗概念版 · 为你推荐'), findsOneWidget);
      expect(find.text('真实接口每日推荐'), findsWidgets);
      expect(
        paths,
        containsAll(['/everyday/recommend', '/home/discover', '/top/playlist']),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SettingsPage())),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('settings-account-management')),
        findsOneWidget,
      );
      expect(find.text('酷狗账号 · 已登录'), findsOneWidget);
      expect(find.text('酷狗昵称'), findsNothing);
      expect(find.text('登录 / 注册'), findsNothing);
      expect(find.text('账号与绑定'), findsNothing);
      expect(tester.takeException(), null);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'restored platform session enters app without replaying login success or tour',
    (tester) async {
      store.value = const PlatformSession(userId: '7', token: 'test');
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: FirstLaunchAuthCoordinator(
              child: Scaffold(body: Text('已进入首页')),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('已进入首页'), findsOneWidget);
      // Restoration is not a new interactive login and must not emit a success
      // event or mark an unseen guide as completed on the user's behalf.
      expect(container.read(betaEntryFlowProvider), BetaEntryStage.idle);
      expect(find.byKey(const ValueKey('entry-success')), findsNothing);
      expect(find.byKey(const ValueKey('entry-guide')), findsNothing);
      expect(container.read(currentUserProvider), null);
    },
    skip: !DistributionChannel.isBeta,
  );

  test(
    'avatar refresh reads current platform profile and logout clears its owner',
    () async {
      store.value = const PlatformSession(
        userId: '7',
        token: 'test',
        nickname: '旧昵称',
      );
      api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          expect(request.url.path, '/user/detail');
          expect(request.headers['Authorization'], 'token=test;userid=7');
          return http.Response(
            jsonEncode({
              'status': 1,
              'data': {
                'nickname': '平台昵称',
                'pic': 'https://img.example/{size}/avatar.jpg',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      final profile = await container.read(platformProfileProvider.future);
      expect(profile?.nickname, '平台昵称');
      expect(profile?.avatarUrl, 'https://img.example/400/avatar.jpg');
      await container.read(platformAccountProvider.notifier).signOut();
      expect(await container.read(platformProfileProvider.future), null);
      expect(container.read(showMestingFeaturesProvider), false);
      expect(container.read(showPlatformFeaturesProvider), false);
      expect(container.read(canUseCurrentLibraryProvider), false);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'account route is opaque in transparent Mesting themes for light and dark',
    (tester) async {
      store.value = const PlatformSession(
        userId: '7',
        token: 'test',
        nickname: '酷狗昵称',
      );
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData(
                brightness: brightness,
                scaffoldBackgroundColor: Colors.transparent,
              ),
              home: const RepaintBoundary(
                key: ValueKey('account-visual-check'),
                child: Scaffold(body: PlatformAccountPage()),
              ),
            ),
          ),
        );
        await tester.pump();
        final scaffold = tester.widget<Scaffold>(
          find.byKey(const ValueKey('platform-account-opaque-page')),
        );
        expect(scaffold.backgroundColor?.a, 1.0);
        expect(find.byType(PlatformAvatar), findsOneWidget);
        expect(tester.takeException(), null);
        if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
          await tester.pump(const Duration(milliseconds: 400));
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('account-visual-check')),
          );
          await tester.runAsync(() async {
            final screenshot = await boundary.toImage();
            final bytes = await screenshot.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory(
              const String.fromEnvironment('BETA_SCREENSHOT_DIR'),
            );
            await directory.create(recursive: true);
            await File(
              '${directory.path}/beta3-account-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            screenshot.dispose();
          });
        }
      }
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'Kugou sidebar omits Mesting messages and protected pages reject direct access',
    (tester) async {
      store.value = const PlatformSession(
        userId: '7',
        token: 'test',
        nickname: '酷狗昵称',
      );
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: MusicHubTopBar(title: '我的', subtitle: '酷狗概念版'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(find.text('我的消息'), findsNothing);
      expect(find.text('好友与消息'), findsNothing);
      expect(find.text('酷狗昵称'), findsOneWidget);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: AuthProtectedPage(
                reason: 'Mesting 消息',
                redirect: '/social/messages',
                child: Text('不应出现的 Mesting 消息内容'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('不应出现的 Mesting 消息内容'), findsNothing);
      expect(find.text('此功能属于 Mesting 账号，返回我的'), findsOneWidget);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'comment UI posts only on explicit send and exposes delete for its owner only',
    (tester) async {
      store.value = const PlatformSession(userId: '7', token: 'test');
      final writes = <http.Request>[];
      final refresh = Completer<http.Response>();
      api = MusicPlatformApi(
        server: _Server(),
        client: MockClient((request) async {
          if (request.method == 'POST') writes.add(request);
          if (request.method == 'GET' &&
              request.url.path.startsWith('/comment/') &&
              writes.isNotEmpty) {
            return refresh.future;
          }
          return http.Response(
            jsonEncode({
              'status': 1,
              'error_code': 0,
              'data': {
                'list': [
                  {
                    'id': 'own',
                    'user_id': 7,
                    'content': '我的平台评论',
                    'special_child_id': 'child',
                  },
                  {
                    'id': 'other',
                    'user_id': 8,
                    'content': '其他人的平台评论',
                    'special_child_id': 'child',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      final session = await container.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PlatformCommentsPage(
              resource: const PlatformCommentResource(
                kind: PlatformCommentKind.song,
                id: '12345',
                name: '歌曲',
              ),
              repository: PlatformCommentsRepository(api, session!),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('我的平台评论'), findsOneWidget);
      expect(find.byTooltip('删除自己的评论'), findsOneWidget);
      expect(writes, isEmpty);
      await tester.enterText(find.byType(TextField), '仅测试提交');
      await tester.tap(find.byKey(const ValueKey('comment-blue-glass-send')));
      await tester.pump();
      await tester.pump();
      expect(writes.length, 1);
      expect(writes.single.url.queryParameters['content'], '仅测试提交');
      // A successful POST is acknowledged independently of a slow readback.
      expect(find.text('已发送'), findsOneWidget);
      expect(find.text('我的平台评论'), findsOneWidget);
      expect(find.byType(PlatformFeedbackState), findsNothing);
      refresh.complete(http.Response('{"status":1,"data":{"list":[]}}', 200));
      await tester.pump();
      await container.read(platformAccountProvider.notifier).signOut();
      await tester.pump();
      expect(find.text('我的平台评论'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
    skip: !DistributionChannel.isBeta,
  );
}
