import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_controller.dart';
import 'package:mesting_music/features/music_platform/netease/together/netease_together_panel.dart';
import 'netease_v114_workflows_test.dart' show FakeTogetherPlayer;
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';

const _session = NeteaseSession(
  userId: '7',
  cookies: {'MUSIC_U': 'synthetic-ui-session'},
  deviceId: 'fixture-device',
  nickname: '测试用户',
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _session.identity;
  void replace(PlatformSession? account) => state = AsyncData(account);
}

void main() {
  final json =
      jsonDecode(
            File('assets/data/netease-full-catalog.json').readAsStringSync(),
          )
          as Map;
  final entries = [
    for (final raw in json['entries'] as List)
      NeteaseEndpoint.fromJson(Map<String, dynamic>.from(raw)),
  ];
  NeteaseEndpoint endpoint(String route) =>
      entries.firstWhere((e) => e.route == route);
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_NETEASE_FULL')) {
      for (final family in [
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'MestingQA',
        'Microsoft YaHei',
        'Noto Sans SC',
        'sans-serif',
      ]) {
        await (FontLoader(family)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });
  Future<ProviderContainer> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    bool compact = false,
    http.Client? client,
    NeteaseTogetherController? together,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = NeteaseApi(
      client ??
          MockClient(
            (request) async => http.Response(
              jsonEncode({
                'code': 200,
                'data': {'level': 8, 'listenSongs': 1200, 'nickname': '测试用户'},
                'msgs': [
                  {
                    'id': 8,
                    'msg': '你好，分享一首喜欢的音乐',
                    'fromUser': {'userId': 8, 'nickname': '音乐朋友'},
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
    )..configure(_session);
    final container = ProviderContainer(
      overrides: [
        if (together != null)
          neteaseTogetherControllerProvider.overrideWithValue(together),
        if (together != null)
          currentTrackProvider.overrideWithValue(
            const Track(
              id: 'empty',
              title: '',
              artist: '',
              album: '',
              duration: Duration.zero,
              audioAsset: '',
              coverAsset: '',
              lyricsAsset: '',
            ),
          ),
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(_Account.new),
        neteaseMusicRepositoryProvider.overrideWithValue(
          NeteaseMusicRepository(api),
        ),
        neteaseCatalogProvider.overrideWith((ref) async => entries),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    await container.read(neteaseCatalogProvider.future);
    tester.view.physicalSize = compact
        ? const Size(320, 650)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme:
              buildMestingTheme(
                musicThemePresetById(dark ? 'classic-dark' : 'classic'),
              ).copyWith(
                listTileTheme: ListTileThemeData(subtitleTextStyle: TextStyle(
                  fontFamily: 'MestingQA', fontSize: 14,
                  color: dark ? const Color(0xFFB7BAC5) : const Color(0xFF515867))),
                textTheme: buildMestingTheme(
                  musicThemePresetById(dark ? 'classic-dark' : 'classic'),
                ).textTheme.apply(fontFamily: 'MestingQA'),
              ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(compact ? 1.5 : 1)),
            child: RepaintBoundary(
              key: const ValueKey('full-capture'),
              child: child!,
            ),
          ),
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    return container;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_NETEASE_FULL')) return;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('full-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('.codex-artifacts/2026-10-29-release114/ui/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      for (final entry in <String, Widget>{
        'social': const NeteaseFullHubPage(tab: '我的', category: '消息中心'),
        'message': NeteaseFullTaskPage(
          endpoint: endpoint('/send/text'),
          seed: const {'user_ids': '8', 'msg': '分享一首喜欢的音乐'},
        ),
        'account': NeteaseFullTaskPage(endpoint: endpoint('/user/level')),
        'retired': NeteaseFullTaskPage(
          endpoint: endpoint('/comment/hotwall/list'),
        ),
      }.entries) {
        testWidgets('${entry.key} dark=$dark compact=$compact', (tester) async {
          await mount(tester, entry.value, dark: dark, compact: compact);
          expect(find.textContaining('/api/'), findsNothing);
          await capture(
            tester,
            '${entry.key}-${dark ? 'dark' : 'light'}-${compact ? 'compact' : 'phone'}',
          );
        });
      }
    }
  }
  for (final dark in [false, true]) {
    testWidgets(
      'together offers real friends without room ID inputs dark=$dark',
      (tester) async {
        final player = FakeTogetherPlayer();
        addTearDown(player.close);
        final api = NeteaseApi(
          MockClient(
            (_) async =>
                http.Response('{"code":200,"data":{"inRoom":false}}', 200),
          ),
        )..configure(_session);
        final music = NeteaseMusicRepository(api);
        final controller = NeteaseTogetherController(
          music: music,
          player: player,
          messages: NeteaseMessagesRepository(music),
          isCurrent: () => true,
          automaticTimer: false,
        );
        addTearDown(controller.dispose);
        await mount(
          tester,
          const NeteaseTogetherPanel(invitee: NeteasePerson('8', '音乐朋友')),
          dark: dark,
          compact: true,
          together: controller,
        );
        expect(find.text('邀请好友'), findsOneWidget);
        expect(find.text('音乐朋友'), findsOneWidget);
        expect(find.textContaining('邀请人编号'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        await capture(
          tester,
          'v114-together-${dark ? 'dark' : 'light'}-compact',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('NetEase comments use NetEase title and transport together', (
    tester,
  ) async {
    final requests = <Uri>[];
    await mount(
      tester,
      NeteaseFullTaskPage(
        endpoint: endpoint('/comment/music'),
        seed: const {'id': '17', 'name': '玻璃'},
      ),
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          '{"code":200,"data":{"comments":[],"hasMore":false}}',
          200,
        );
      }),
    );
    expect(find.text('网易云评论'), findsOneWidget);
    expect(find.text('酷狗评论'), findsNothing);
    expect(requests, isNotEmpty);
    expect(
      requests.every(
        (uri) =>
            uri.host == 'music.163.com' ||
            uri.host == 'interface.music.163.com',
      ),
      isTrue,
    );
    await capture(tester, 'v114-comments-light-phone');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('messages open conversations without an API form', (
    tester,
  ) async {
    await mount(tester, const NeteaseMessagesPage());
    expect(find.text('我的消息'), findsOneWidget);
    expect(find.text('评论和@提及'), findsOneWidget);
    expect(find.text('音乐朋友'), findsOneWidget);
    expect(find.text('每页数量'), findsNothing);
    expect(find.text('内容编号'), findsNothing);
    await tester.tap(find.text('音乐朋友'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('音乐朋友'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('comment-liquid-glass-input')),
      findsOneWidget,
    );
    expect(find.byTooltip('一起听'), findsOneWidget);
    await capture(tester, 'v114-conversation-light-phone');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final compact in [false, true]) {
    testWidgets(
      'release131 actual messages refresh keeps one Apple indicator compact=$compact',
      (tester) async {
        var hold = false;
        final response = Completer<http.Response>();
        var refreshRequests = 0;
        http.Response reply() => http.Response(
          jsonEncode({
            'code': 200,
            'msgs': [
              {
                'id': 8,
                'msg': '保留这条已有会话',
                'fromUser': {'userId': 8, 'nickname': '音乐朋友'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
        await mount(
          tester,
          const NeteaseMessagesPage(),
          dark: true,
          compact: compact,
          client: MockClient((_) {
            if (hold) {
              refreshRequests++;
              return response.future;
            }
            return Future.value(reply());
          }),
        );
        expect(find.text('音乐朋友'), findsOneWidget);
        hold = true;
        await tester.drag(find.byType(ListView).first, const Offset(0, 750));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(refreshRequests, greaterThan(0));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find
              .byType(CupertinoActivityIndicator)
              .evaluate()
              .where((e) => TickerMode.valuesOf(e).enabled)
              .length,
          1,
        );
        expect(find.text('音乐朋友').hitTestable(), findsOneWidget);
        if (const bool.fromEnvironment('CAPTURE_NETEASE_FULL')) {
          final shot = tester
              .renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('full-capture')),
              )
              .toImage();
          await tester.runAsync(() async {
            final image = await shot;
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final path = File(
              '.codex-artifacts/2026-11-01-release131/ui/messages-refresh-$compact.png',
            );
            await path.parent.create(recursive: true);
            await path.writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        response.complete(reply());
        hold = false;
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('chat sends directly once and preserves its glass composer', (
    tester,
  ) async {
    var sends = 0;
    final receipt = Completer<http.Response>();
    await mount(
      tester,
      const NeteaseChatPage(peer: NeteasePerson('8', '音乐朋友')),
      compact: true,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/msg/private/send')) {
          sends++;
          return receipt.future;
        }
        return http.Response('{"code":200,"msgs":[]}', 200);
      }),
    );
    final input = find.descendant(
      of: find.byKey(const ValueKey('comment-liquid-glass-input')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, '你好😀');
    await tester.tap(find.byKey(const ValueKey('comment-blue-glass-send')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.byKey(const ValueKey('comment-blue-glass-send')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(sends, 1);
    expect(find.text('确认发送私信？'), findsNothing);
    receipt.complete(
      http.Response(
        jsonEncode({
          'code': 200,
          'newMsgs': [
            {
              'id': 9,
              'time': 1793250000000,
              'msg': jsonEncode({'msg': '你好😀'}),
              'fromUser': {'userId': 7},
              'toUser': {'userId': 8},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect((tester.widget<TextField>(input).controller!).text, isEmpty);
    expect(find.text('你好😀'), findsOneWidget);
    await capture(tester, 'v114-chat-light-compact');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('chat blocks the old account after a platform switch', (
    tester,
  ) async {
    var sends = 0;
    final container = await mount(
      tester,
      const NeteaseChatPage(peer: NeteasePerson('8', '音乐朋友')),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/msg/private/send')) sends++;
        return http.Response('{"code":200,"msgs":[]}', 200);
      }),
    );
    (container.read(platformAccountProvider.notifier) as _Account).replace(
      null,
    );
    await tester.pump();
    expect(find.text('账号已变化，请返回后重新打开'), findsOneWidget);
    expect(find.byKey(const ValueKey('comment-blue-glass-send')), findsNothing);
    expect(sends, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'deleting requires confirmation, cancellation performs no write',
    (tester) async {
      var writes = 0;
      await mount(
        tester,
        NeteaseFullTaskPage(
          endpoint: endpoint('/playlist/delete'),
          seed: const {'id': '8'},
        ),
        client: MockClient((_) async {
          writes++;
          return http.Response('{"code":200}', 200);
        }),
      );
      expect(writes, 0);
      await tester.ensureVisible(find.text('删除歌单').last);
      await tester.tap(find.text('删除歌单').last);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('确认删除歌单？'), findsOneWidget);
      expect(writes, 0);
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(writes, 0);
      await tester.tap(find.text('删除歌单').last);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('确认'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(writes, 1);
    },
  );
  testWidgets(
    'dragging from a task action cancels press before finger release',
    (tester) async {
      await mount(
        tester,
        NeteaseFullTaskPage(
          endpoint: endpoint('/playlist/delete'),
          seed: const {'id': '8'},
        ),
        compact: true,
      );
      final action = find.widgetWithText(BetaGlassButton, '删除歌单');
      await tester.ensureVisible(action);
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(action));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveBy(const Offset(0, -140));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('确认删除歌单？'), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(find.text('确认删除歌单？'), findsNothing);
    },
  );
  testWidgets('old form disables its write after switching account', (
    tester,
  ) async {
    var writes = 0;
    final container = await mount(
      tester,
      NeteaseFullTaskPage(
        endpoint: endpoint('/playlist/delete'),
        seed: const {'id': '8'},
      ),
      client: MockClient((_) async {
        writes++;
        return http.Response('{"code":200}', 200);
      }),
    );
    (container.read(platformAccountProvider.notifier) as _Account).replace(
      null,
    );
    await tester.pump();
    expect(find.text('账号已变化，请返回后重新打开'), findsOneWidget);
    expect(find.widgetWithText(BetaGlassButton, '删除歌单'), findsNothing);
    expect(writes, 0);
  });
}
