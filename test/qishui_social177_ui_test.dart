import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_pages.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_repository.dart';
import 'qishui_social177_test.dart' show account177, user177;
import 'qishui_signed_api167_test.dart' show FixtureSigner, reply;
import 'support/release_147_qa.dart' show load147IconFonts;

const _capture = bool.fromEnvironment('CAPTURE_177');

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => account177().identity;
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (_capture) {
      await load147IconFonts();
      await (FontLoader('SodaQA177')..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  Future<void> pump(WidgetTester tester) async {
    for (var n = 0; n < 12; n++) {
      await tester.pump(const Duration(milliseconds: 70));
    }
  }

  Future<ProviderContainer> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    double scale = 1.4,
    Future<Map<String, dynamic>> Function(String, Map<String, String>)? list,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var followed = false;
    final api = QishuiApi(
      MockClient((request) async {
        if (request.url.path.endsWith('/following') ||
            request.url.path.endsWith('/follower')) {
          if (list != null) {
            return reply(
              await list(request.url.path, request.url.queryParameters),
            );
          }
          return reply({
            'has_more': false,
            'follow_items': [
              {
                'item_type': 'user',
                'user': {
                  'id': '17702',
                  'nickname': '合成用户',
                  'signature': '这是受控界面样本',
                },
                'my_user_state': {'follow_status': followed ? 1 : 0},
              },
              {
                'item_type': 'artist',
                'artist': {
                  'id': '17720',
                  'name': '合成歌手',
                  'state': {'is_collected': true},
                },
              },
            ],
          });
        }
        if (request.url.path == '/luna/user/info') {
          return reply(user177('17702', followed ? 1 : 0));
        }
        if (request.url.path == '/luna/me/follow' ||
            request.url.path == '/luna/me/unfollow') {
          followed = request.url.path.endsWith('/follow');
          return reply({'user_id': '17702', 'follow_status': followed ? 1 : 0});
        }
        return reply({
          'my_info': {'id': '17701'},
          'my_stats': {'count_following': 18},
        });
      }),
      signer: FixtureSigner(),
    )..configure(account177());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        platformAccountProvider.overrideWith(_Account.new),
        qishuiApiProvider.overrideWithValue(api),
        qishuiSocialStatsProvider.overrideWith(
          (ref) async => const QishuiSocialStats(
            following: 18,
            followers: 27,
            likes: 93,
            commentLikes: 63,
            likesTitle: '获赞统计',
            likesDescription: '这里展示官方返回的评论获赞明细。',
          ),
        ),
        qishuiOfficialListeningProvider.overrideWith(
          (ref) async => QishuiListeningSnapshot(
            fetchedAt: DateTime(2026, 11, 7, 20),
            totalSeconds: 445500,
            weekSeconds: 3600,
          ),
        ),
        qishuiListeningLedgerProvider.overrideWith(
          (ref) async => const QishuiListeningLedger(
            heardMilliseconds: 125000,
            transportAcceptedMilliseconds: 120000,
            unconfirmedMilliseconds: 5000,
          ),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      api.dispose();
    });
    await container.read(platformAccountProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: _capture ? 'SodaQA177' : null,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('capture177-page'),
            child: page,
          ),
        ),
      ),
    );
    await pump(tester);
    return container;
  }

  for (final dark in [false, true]) {
    for (final surface in ['following', 'likes', 'user', 'listening']) {
      testWidgets('$surface dark=$dark rendered with independent real states', (
        tester,
      ) async {
        final page = switch (surface) {
          'following' => const QishuiFollowListPage(
            kind: QishuiFollowListKind.following,
          ),
          'likes' => const QishuiLikesPage(),
          'user' => const QishuiSocialUserPage(
            person: QishuiSocialPerson(
              key: 'user:17702',
              name: '合成用户',
              userId: '17702',
              followStatus: 0,
            ),
          ),
          _ => const QishuiListeningPage(),
        };
        await mount(tester, page, dark: dark);
        expect(tester.takeException(), isNull);
        if (_capture) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture177-page')),
            );
            final image = await boundary.toImage();
            try {
              final data = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              final file = File(
                '.codex-artifacts/2026-11-07-release177/ui/$surface-${dark ? 'dark' : 'light'}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              );
            } finally {
              image.dispose();
            }
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
    'switching group cancels old response and uses separate first cursor',
    (tester) async {
      final old = Completer<Map<String, dynamic>>();
      final requests = <String>[];
      await mount(
        tester,
        const QishuiFollowListPage(kind: QishuiFollowListKind.followers),
        list: (_, query) async {
          requests.add('${query['scene']}:${query['cursor']}');
          if (query['scene'] == '2') return old.future;
          return {
            'has_more': false,
            'follow_items': [
              {
                'item_type': 'user',
                'user': {'id': '17703', 'nickname': '新分组用户'},
              },
            ],
          };
        },
      );
      await tester.tap(find.text('抖音'));
      await pump(tester);
      old.complete({
        'has_more': false,
        'follow_items': [
          {
            'item_type': 'user',
            'user': {'id': '17704', 'nickname': '旧迟到用户'},
          },
        ],
      });
      await pump(tester);
      expect(requests, ['2:', '1:']);
      expect(find.text('新分组用户'), findsOneWidget);
      expect(find.text('旧迟到用户'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final kind in QishuiFollowListKind.values) {
    testWidgets(
      '${kind.name} shows sparse empty group and retains Douyin rows',
      (tester) async {
        final scenes = <String>[];
        await mount(
          tester,
          QishuiFollowListPage(kind: kind),
          list: (_, query) async {
            scenes.add(query['scene']!);
            if (query['scene'] == '2') {
              return {
                'status_info': <String, Object>{},
                'status_code': 0,
                'next_cursor': '',
              };
            }
            return {
              'follow_items': [
                {
                  'item_type': 'user',
                  'user': {'id': '17902', 'nickname': '抖音分组用户'},
                },
              ],
              'has_more': false,
            };
          },
        );
        expect(find.text('汽水暂无可显示的记录'), findsOneWidget);
        expect(find.text('重试'), findsNothing);
        await tester.tap(find.text('抖音'));
        await pump(tester);
        expect(find.text('抖音分组用户'), findsOneWidget);
        expect(find.text('汽水暂无可显示的记录'), findsNothing);
        await tester.tap(find.text('汽水'));
        await pump(tester);
        expect(find.text('汽水暂无可显示的记录'), findsOneWidget);
        expect(find.text('抖音分组用户'), findsNothing);
        expect(find.text('重试'), findsNothing);
        expect(scenes, ['2', '1', '2']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('user detail follows then unfollows with official readback', (
    tester,
  ) async {
    await mount(
      tester,
      const QishuiSocialUserPage(
        person: QishuiSocialPerson(
          key: 'user:17702',
          name: '合成用户',
          userId: '17702',
          followStatus: 0,
        ),
      ),
    );
    await tester.tap(find.text('关注').last);
    await pump(tester);
    expect(find.text('已关注'), findsOneWidget);
    await tester.tap(find.text('已关注'));
    await pump(tester);
    expect(find.text('关注'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
