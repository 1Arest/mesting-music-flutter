import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_card_view.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_page.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_account_source_info.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_listening_reporter.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_settings_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'netease_v115_sources_test.dart' show TestAccount;
import 'netease_message_card_test.dart' show recordEnvelope;

const _capture = bool.fromEnvironment('CAPTURE_V124_FOLLOWUP');
const _captureKey = ValueKey('followup-capture');
const _saved = PlatformSession(
  userId: 'kg-fixture',
  token: 'synthetic-only',
  nickname: '合成酷狗账号',
);

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_capture) return;
    for (final family in [
      'FollowupQA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'Noto Sans SC',
      'Microsoft YaHei',
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
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  final requests = <String>[];
  Future<ProviderContainer> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    bool compact = false,
    bool storageError = false,
    bool unsupported = false,
    PlatformSession? saved = _saved,
  }) async {
    requests.clear();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = MockClient((request) async {
      requests.add(request.url.path);
      return http.Response(
        jsonEncode({
          'code': 200,
          'more': false,
          'msgs': [
            {
              'id': 901,
              'time': 1793433000000,
              'fromUser': {'userId': 8, 'nickname': '合成测试好友'},
              'toUser': {'userId': 7},
              'msg': jsonEncode(
                unsupported
                    ? {'type': 24, 'msg': '当前版本无法显示该信息，请在应用市场下载最新版app'}
                    : recordEnvelope(),
              ),
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = NeteaseApi(client)
      ..configure(
        const NeteaseSession(
          userId: '7',
          cookies: {'MUSIC_U': 'synthetic-only'},
          deviceId: 'fixture',
        ),
      );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(TestAccount.new),
        savedKugouSessionProvider.overrideWith((ref) async {
          if (storageError) throw StateError('synthetic storage failure');
          return saved;
        }),
        neteaseMusicRepositoryProvider.overrideWithValue(
          NeteaseMusicRepository(api),
        ),
        neteaseListeningJournalProvider.overrideWith((ref) => Stream.value([])),
      ],
    );
    final host = BetaBottomSearchHost(
      location: '/fixture',
      openMusicSearch: () {},
    );
    addTearDown(() {
      container.dispose();
      host.dispose();
      client.close();
    });
    await container.read(platformAccountProvider.future);
    tester.view.physicalSize = compact
        ? const Size(320, 650)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: _capture
              ? theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: 'FollowupQA'),
                  listTileTheme: theme.listTileTheme.copyWith(
                    subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'FollowupQA',
                    ),
                  ),
                )
              : theme,
          builder: (context, child) => BetaBottomSearchScope(
            host: host,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(compact ? 1.4 : 1)),
              child: RepaintBoundary(key: _captureKey, child: child!),
            ),
          ),
          home: page,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    return container;
  }

  Future<void> capture(WidgetTester tester, String file) async {
    if (!_capture) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        const String.fromEnvironment(
          'FOLLOWUP_CAPTURE_DIR',
          defaultValue: '.codex-artifacts/2026-10-31-v124-followup/ui',
        ),
      )..createSync(recursive: true);
      await File(
        '${dir.path}/$file.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      final suffix =
          '${dark ? 'dark' : 'light'}-${compact ? 'compact' : 'phone'}';
      testWidgets('real chat shows record and opens read-only details $suffix', (
        tester,
      ) async {
        final container = await mount(
          tester,
          const NeteaseChatPage(peer: NeteasePerson('8', '合成测试好友')),
          dark: dark,
          compact: compact,
        );
        expect(find.textContaining('不支持'), findsNothing);
        expect(
          find.byKey(const ValueKey('netease-together-message-card')),
          findsOneWidget,
        );
        expect(find.text('我们一起听了'), findsOneWidget);
        expect(find.text('12 分钟 0 秒 ›'), findsOneWidget);
        final action = find.byKey(
          const ValueKey('netease-message-card-detail'),
        );
        expect(action.hitTestable(), findsOneWidget);
        await capture(tester, 'chat-$suffix');
        // A drag that begins on the action is still scrolling, not activation.
        final gesture = await tester.startGesture(tester.getCenter(action));
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(NeteaseMessageCardDetailPage), findsNothing);
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(NeteaseMessageCardDetailPage), findsOneWidget);
        expect(find.text('一起听记录'), findsOneWidget);
        expect(find.text('查看网易云原始详情'), findsOneWidget);
        await capture(tester, 'record-$suffix');
        expect(
          requests.any(
            (p) =>
                p.contains('/send') ||
                p.contains('/end') ||
                p.contains('/accept'),
          ),
          isFalse,
        );
        expect(tester.takeException(), isNull);
        (container.read(platformAccountProvider.notifier) as TestAccount)
            .replace('8', platform: MusicPlatform.kugou);
        await tester.pump();
        expect(find.text('账号已变化，请返回聊天后重新打开'), findsOneWidget);
        expect(find.text('本次一起听记录'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
      testWidgets(
        'playback settings expose retained account without a new switch $suffix',
        (tester) async {
          final container = await mount(
            tester,
            const NeteasePlaybackSettingsPage(),
            dark: dark,
            compact: compact,
          );
          await tester.scrollUntilVisible(
            find.byType(NeteaseAccountSourceInfo),
            180,
          );
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('酷狗概念版账号'), findsOneWidget);
          expect(find.text('已保存登录 · 合成酷狗账号'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(NeteaseAccountSourceInfo),
              matching: find.byType(Switch),
            ),
            findsNothing,
          );
          expect(
            container.read(platformAccountProvider).value!.platform,
            MusicPlatform.netease,
          );
          await capture(tester, 'source-$suffix');
          container.read(retainedKugouMutationProvider.notifier).publish(null);
          await tester.pump();
          expect(find.text('尚未登录酷狗账号'), findsOneWidget);
          expect(requests, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'unsupported chat offers explicit diagnostic export without more requests',
    (tester) async {
      await mount(
        tester,
        const NeteaseChatPage(peer: NeteasePerson('8', '合成测试好友')),
        unsupported: true,
        compact: true,
      );
      final action = find.byKey(
        const ValueKey('netease-message-export-diagnostic'),
      );
      expect(action.hitTestable(), findsOneWidget);
      expect(find.text('查看一起听记录'), findsNothing);
      await capture(tester, 'unsupported-chat-compact');
      final count = requests.length;
      await tester.tap(action);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('导出此条消息诊断'), findsOneWidget);
      await capture(tester, 'unsupported-diagnostic-compact');
      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests.length, count);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('saved-login read failure is visible instead of logged out', (
    tester,
  ) async {
    await mount(
      tester,
      const Scaffold(body: NeteaseAccountSourceInfo()),
      storageError: true,
    );
    expect(find.text('账号状态读取失败，请在账号管理中重试'), findsOneWidget);
    expect(find.text('尚未登录酷狗账号'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
