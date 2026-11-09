import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_search_catalog.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_search_page.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'qishui_protocol_test.dart' show sodaSession, fixtureJson;
import 'qishui_search173_test.dart' show searchTrack173, searchResponse173;
import 'qishui_ui_test.dart' show FixtureAccount;
import 'support/release_152_qa.dart' show theme152;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
  });

  Future<ProviderContainer> mount(
    WidgetTester tester,
    QishuiCatalogRequest request, {
    bool dark = false,
    double scale = 1,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((_) async => fixtureJson({}));
    final api = QishuiApi(client)..configure(sodaSession());
    final music = QishuiRepository(api);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        platformAccountProvider.overrideWith(FixtureAccount.new),
        qishuiApiProvider.overrideWithValue(api),
        qishuiRepositoryProvider.overrideWithValue(music),
        qishuiSearchCatalogProvider.overrideWithValue(
          QishuiSearchCatalog(request: request),
        ),
      ],
    );
    final bottomHost = BetaBottomSearchHost(
      location: '/search',
      openMusicSearch: () {},
    );
    addTearDown(bottomHost.dispose);
    addTearDown(container.dispose);
    addTearDown(api.dispose);
    addTearDown(client.close);
    await container.read(platformAccountProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp(
            theme: theme152(dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: BetaBottomSearchScope(host: bottomHost, child: child!),
            ),
            home: const QishuiSearchPage(),
          ),
        ),
      ),
    );
    await settle(tester);
    return container;
  }

  Future<void> submit(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('qishui-catalog-search-field')),
      query,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
  }

  testWidgets('new keyword cancels old request and ignores its late result', (
    tester,
  ) async {
    final previous = Completer<Map<String, dynamic>>();
    var oldAborted = false;
    await mount(tester, (
      path, {
      body = const {},
      query = const {},
      get = false,
      abortTrigger,
    }) {
      if (body['q'] == '旧关键词') {
        unawaited(
          abortTrigger!.then((_) {
            oldAborted = true;
          }),
        );
        return previous.future;
      }
      return Future.value(
        searchResponse173(
          rows: [
            {
              'entity': {'track': searchTrack173('new', '新的结果')},
            },
          ],
        ),
      );
    });
    await submit(tester, '旧关键词');
    await submit(tester, '新关键词');
    expect(oldAborted, isTrue);
    expect(find.text('新的结果'), findsOneWidget);
    previous.complete(
      searchResponse173(
        rows: [
          {
            'entity': {'track': searchTrack173('old', '过期结果')},
          },
        ],
      ),
    );
    await settle(tester);
    expect(find.text('过期结果'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('artist tab has independent results and opens paged works', (
    tester,
  ) async {
    final calls = <String>[];
    await mount(tester, (
      path, {
      body = const {},
      query = const {},
      get = false,
      abortTrigger,
    }) async {
      calls.add('$path:${query['cursor'] ?? ''}');
      if (path.endsWith('/search/track')) return searchResponse173();
      if (path.endsWith('/search/artist')) {
        return searchResponse173(
          kind: 'artists',
          rows: [
            {
              'entity': {
                'artist': {'id': 'singer', 'name': '搜索歌手', 'count_tracks': 65},
              },
            },
          ],
        );
      }
      if (path.endsWith('/artists/singer')) {
        return {
          'artist_info': {
            'id': 'singer',
            'name': '完整歌手',
            'count_tracks': 65,
            'count_albums': 9,
          },
        };
      }
      return {
        'tracks': [searchTrack173(query['cursor'] == '0' ? 'first' : 'second')],
        'has_more': query['cursor'] == '0',
      };
    });
    await submit(tester, '歌手');
    await tester.tap(find.text('歌手').last);
    await settle(tester);
    expect(find.text('搜索歌手'), findsOneWidget);
    await tester.tap(find.text('搜索歌手'));
    await settle(tester);
    expect(find.text('完整歌手'), findsOneWidget);
    expect(find.text('65 首歌曲'), findsOneWidget);
    expect(find.text('歌曲 first'), findsOneWidget);
    await tester.ensureVisible(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await settle(tester);
    expect(find.text('歌曲 second'), findsOneWidget);
    expect(calls, contains('/luna/artists/singer/tracks:50'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'later page error keeps first rows and retries without duplicates',
    (tester) async {
      var secondAttempts = 0;
      await mount(tester, (
        path, {
        body = const {},
        query = const {},
        get = false,
        abortTrigger,
      }) async {
        if (body['cursor'] == '20') {
          if (++secondAttempts == 1) throw const QishuiException('后续页暂时连接失败');
          return searchResponse173(
            rows: [
              {
                'entity': {'track': searchTrack173('one')},
              },
              {
                'entity': {'track': searchTrack173('two')},
              },
            ],
          );
        }
        return searchResponse173(
          rows: [
            {
              'entity': {'track': searchTrack173('one')},
            },
          ],
          more: true,
          next: '20',
        );
      });
      await submit(tester, '歌曲');
      await tester.tap(find.text('加载更多'));
      await settle(tester);
      expect(find.text('歌曲 one'), findsOneWidget);
      expect(find.text('后续页暂时连接失败'), findsOneWidget);
      await tester.tap(find.text('重试加载'));
      await settle(tester);
      expect(find.text('歌曲 one'), findsOneWidget);
      expect(find.text('歌曲 two'), findsOneWidget);
      expect(secondAttempts, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account change hides pending and loaded search data', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final container = await mount(
      tester,
      (path, {body = const {}, query = const {}, get = false, abortTrigger}) =>
          pending.future,
    );
    await submit(tester, '歌曲');
    (container.read(platformAccountProvider.notifier) as FixtureAccount)
        .changeForTest(null);
    await settle(tester);
    pending.complete(
      searchResponse173(
        rows: [
          {
            'entity': {'track': searchTrack173('old-account')},
          },
        ],
      ),
    );
    await settle(tester);
    expect(find.text('账号已变化'), findsOneWidget);
    expect(find.text('歌曲 old-account'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'search artists remains usable at narrow large text dark=$dark',
      (tester) async {
        await mount(
          tester,
          (
            path, {
            body = const {},
            query = const {},
            get = false,
            abortTrigger,
          }) async {
            return searchResponse173(
              kind: path.endsWith('/artist') ? 'artists' : 'tracks',
              rows: [
                if (path.endsWith('/artist'))
                  {
                    'entity': {
                      'artist': {
                        'id': 'singer',
                        'name': '一位名字很长的测试歌手',
                        'count_tracks': 0,
                      },
                    },
                  },
              ],
            );
          },
          dark: dark,
          scale: 1.4,
          size: const Size(320, 700),
        );
        await submit(tester, '歌手');
        await tester.tap(find.text('歌手').last);
        await settle(tester);
        expect(find.text('一位名字很长的测试歌手'), findsOneWidget);
        expect(find.text('0 首歌曲'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

/// Glass/activity animations can keep scheduling frames. Pump a bounded window
/// instead of waiting for an arbitrary loading request to settle forever.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
