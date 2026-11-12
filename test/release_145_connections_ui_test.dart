import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_personal_connections_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_repository.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'package:mesting_music/shared/widgets/beta_page_search_layout.dart';

import 'release_145_connections_test.dart' as fixture;

const _capture = bool.fromEnvironment('CAPTURE_145_CONNECTIONS');
const _captureKey = ValueKey('connections145-capture');

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!_capture) return;
    for (final family in [
      'Mesting145QA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
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

  Future<ProviderContainer> mount(
    WidgetTester tester,
    fixture.Connections145Music music, {
    bool dark = false,
    bool initialFollowers = false,
    double width = 390,
    double scale = 1,
    String ownerId = 'netease:7',
    BetaBottomSearchHost? searchHost,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
        platformAccountProvider.overrideWith(fixture.Connections145Account.new),
        neteaseUserRepositoryProvider.overrideWithValue(
          NeteaseUserRepository(music),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    // Deterministic host tests do not depend on deferred Material shader loads.
    theme = theme.copyWith(splashFactory: NoSplash.splashFactory);
    if (_capture) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Mesting145QA'),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: searchHost == null
                ? child!
                : BetaBottomSearchScope(host: searchHost, child: child!),
          ),
          home: RepaintBoundary(
            key: _captureKey,
            child: NeteasePersonalConnectionsPage(
              ownerId: ownerId,
              initialFollowers: initialFollowers,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  BetaPageSearchController taskSearch(WidgetTester tester) => tester
      .widget<BetaPageSearchLayout>(find.byType(BetaPageSearchLayout))
      .controller;

  Future<void> enterQuery(WidgetTester tester, String query) async {
    if (!taskSearch(tester).active) {
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '搜索关注或粉丝',
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.byType(CupertinoSearchTextField), findsNothing);
    await tester.enterText(find.byType(EditableText), query);
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_capture) return;
    await tester.pump(const Duration(milliseconds: 100));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    if (boundary.debugNeedsPaint) await tester.pump();
    // Acquire the painted frame before entering real async. The bottom text
    // editor can otherwise invalidate its layer between yielding and toImage.
    final imageFuture = boundary.toImage();
    await tester.runAsync(() async {
      final image = await imageFuture;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '.codex-artifacts/2026-11-03-release145-social/ui/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  fixture.Connections145Music music({int users = 45}) =>
      fixture.Connections145Music((route, query) {
        if (route == '/user/detail') {
          return {
            'profile': {
              'userId': int.parse('${query['uid']}'),
              'nickname': '公开用户',
              'follows': 45,
              'followeds': 3,
            },
          };
        }
        if (route == '/user/playlist') return {'playlist': [], 'more': false};
        if (route == '/follow' || route == '/artist/sub') return {'code': 200};
        if (route == '/artist/sublist') {
          return {
            'data': [
              {'id': 42, 'name': '合成歌手', 'picUrl': ''},
            ],
            'more': false,
          };
        }
        if (route == '/user/followeds') {
          return {
            'followeds': [
              {...fixture.connection145User(42), 'followed': false},
              {...fixture.connection145User(43), 'followed': true},
              fixture.connection145User(999),
            ],
            'more': false,
          };
        }
        if (route == '/user/follows') {
          final offset = query['offset'] as int;
          final end = (offset + 30).clamp(0, users);
          return {
            'follow': [
              for (var i = offset; i < end; i++)
                fixture.connection145User(100 + i),
            ],
            'more': end < users,
          };
        }
        throw StateError('Unexpected local fixture route: $route');
      });

  for (final dark in [false, true]) {
    testWidgets(
      'Apple relation page has complete search, artist filtering and proper $dark theme',
      (tester) async {
        final source = music();
        await mount(tester, source, dark: dark);
        expect(find.text('关注与粉丝'), findsOneWidget);
        expect(find.text('关注 45'), findsOneWidget);
        expect(find.byType(CupertinoSearchTextField), findsNothing);
        expect(find.byType(GlassTabBar), findsOneWidget);
        expect(find.byType(EditableText), findsOneWidget);
        expect(find.text('46 个条目'), findsOneWidget);
        await capture(tester, 'following-${dark ? 'dark' : 'light'}');
        await enterQuery(tester, '144');
        await tester.pump();
        expect(find.text('用户 144'), findsOneWidget);
        expect(find.text('1 个搜索结果'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('personal-connections-filter')),
            matching: find.text('歌手'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('用户 144'), findsNothing);
        await enterQuery(tester, '');
        await tester.pump();
        expect(find.text('合成歌手'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('each tab retains its search, loaded pages and scroll position', (
    tester,
  ) async {
    final source = music();
    await mount(tester, source);
    final editor = tester.element(find.byType(EditableText));
    final followingScroll = tester
        .widget<CustomScrollView>(
          find.byKey(const PageStorageKey('personal-connections-list-0')),
        )
        .controller!;
    followingScroll.jumpTo(700);
    await tester.pump();
    final position = followingScroll.offset;
    await tester.tap(find.text('粉丝 3'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('关注我的人'), findsOneWidget);
    await enterQuery(tester, '999');
    await tester.pump();
    expect(find.text('用户 999'), findsOneWidget);
    expect(taskSearch(tester).focus.hasFocus, true);
    tester.testTextInput.hide();
    await tester.tap(find.text('关注 45'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taskSearch(tester).focus.hasFocus, false);
    expect(tester.element(find.byType(EditableText)), same(editor));
    expect(followingScroll.offset, position);
    expect(
      source.calls.where((call) => call.$1 == '/user/follows'),
      hasLength(2),
    );
    await tester.tap(find.text('粉丝 3'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taskSearch(tester).focus.hasFocus, false);
    expect(taskSearch(tester).text.text, '999');
    expect(
      source.calls.where((call) => call.$1 == '/user/followeds'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an existing shell binds the local search without a duplicate editor',
    (tester) async {
      final host = BetaBottomSearchHost(
        location: '/relations',
        openMusicSearch: () {},
      );
      addTearDown(host.dispose);
      final source = music();
      await mount(tester, source, searchHost: host);
      final search = taskSearch(tester);
      expect(host.current, same(search));
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(CupertinoSearchTextField), findsNothing);
      expect(find.byType(GlassTabBar), findsNothing);
      search.text.text = '144';
      search.changed('144');
      await tester.pump();
      expect(find.text('用户 144'), findsOneWidget);
      await tester.tap(find.text('粉丝 3'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(host.current, same(search));
      expect(search.text.text, isEmpty);
      await tester.tap(find.text('关注 45'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(search.text.text, '144');
      expect(source.calls.where((call) => call.$1 == '/search'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(host.current, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filter changes dismiss the one bottom editor without losing query',
    (tester) async {
      await mount(tester, music());
      await enterQuery(tester, '合成');
      final search = taskSearch(tester);
      final editor = tester.element(find.byType(EditableText));
      expect(search.focus.hasFocus, true);
      tester.testTextInput.hide();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('personal-connections-filter')),
          matching: find.text('歌手'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(search.focus.hasFocus, false);
      expect(search.text.text, '合成');
      expect(tester.element(find.byType(EditableText)), same(editor));
      expect(find.text('合成歌手'), findsOneWidget);
      expect(tester.getCenter(find.byType(EditableText)).dy, greaterThan(650));
      await capture(tester, 'following-active-bottom-search');
      await tester.tap(
        find.byKey(const ValueKey('personal-connections-sort-0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoActionSheetAction, '昵称顺序'));
      await tester.pumpAndSettle();
      expect(search.focus.hasFocus, false);
      expect(find.byType(EditableText), findsOneWidget);
      expect(find.byType(CupertinoSearchTextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'fan follow-back becomes mutual and failed writes remain actionable',
    (tester) async {
      final source = music();
      final container = await mount(tester, source, initialFollowers: true);
      expect(find.text('互相关注'), findsOneWidget);
      await capture(tester, 'fans-light');
      await tester.tap(find.byKey(const ValueKey('netease-follow-42')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(neteaseUserRelationsProvider)['42']?.followed,
        true,
      );
      expect(find.text('互相关注'), findsNWidgets(2));
      final original = source.reply;
      source.reply = (route, query) =>
          route == '/follow' ? {'code': 500} : original(route, query);
      await tester.tap(find.byKey(const ValueKey('netease-follow-999')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(neteaseUserRelationsProvider)['999']?.followed,
        false,
      );
      expect(container.read(neteaseUserRelationsProvider)['999']?.busy, false);
      expect(find.textContaining('操作未完成'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('artist unsubscribe uses its own confirmation and endpoint', (
    tester,
  ) async {
    final source = music(users: 0);
    await mount(tester, source);
    await tester.tap(find.byKey(const ValueKey('netease-artist-follow-42')));
    await tester.pumpAndSettle();
    expect(find.text('取消关注歌手？'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消关注'));
    await tester.pumpAndSettle();
    expect(source.calls.where((call) => call.$1 == '/artist/sub').single.$2, {
      'id': '42',
      'subscribe': false,
    });
    expect(source.calls.where((call) => call.$1 == '/follow'), isEmpty);
    expect(find.text('关注'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fan unfollow confirms once and keeps the row in place', (
    tester,
  ) async {
    final source = music();
    final container = await mount(
      tester,
      source,
      initialFollowers: true,
      dark: true,
    );
    await capture(tester, 'fans-dark');
    final row = find.byKey(const ValueKey('connection-user:43'));
    final before = tester.getTopLeft(row);
    await tester.tap(find.byKey(const ValueKey('netease-follow-43')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '保留关注'));
    await tester.pumpAndSettle();
    expect(source.calls.where((call) => call.$1 == '/follow'), isEmpty);
    await tester.tap(find.byKey(const ValueKey('netease-follow-43')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消关注'));
    await tester.pumpAndSettle();
    expect(source.calls.where((call) => call.$1 == '/follow').single.$2, {
      'id': '43',
      't': 0,
    });
    expect(container.read(neteaseUserRelationsProvider)['43']?.followed, false);
    expect(tester.getTopLeft(row), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'empty fans and no search matches have distinct complete states',
    (tester) async {
      final source = music();
      final original = source.reply;
      source.reply = (route, query) => route == '/user/followeds'
          ? {'followeds': [], 'more': false}
          : original(route, query);
      await mount(tester, source, initialFollowers: true);
      expect(find.text('还没有粉丝'), findsOneWidget);
      await enterQuery(tester, '不存在的用户');
      await tester.pump();
      expect(find.text('没有找到匹配的人'), findsOneWidget);
      expect(find.text('还没有粉丝'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'search result opens the existing public profile and keeps draft on return',
    (tester) async {
      final source = music();
      await mount(tester, source);
      await enterQuery(tester, '144');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.text('用户 144'));
      await tester.pumpAndSettle();
      expect(find.byType(NeteaseUserProfilePage), findsOneWidget);
      final context = tester.element(find.byType(NeteaseUserProfilePage));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(taskSearch(tester).text.text, '144');
      expect(find.text('用户 144'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'partial-search failure shows retry before a definitive empty result',
    (tester) async {
      final source = music();
      final original = source.reply;
      var fail = true;
      source.reply = (route, query) {
        if (route == '/user/follows' && query['offset'] == 30 && fail) {
          throw StateError('fixture second page failure');
        }
        return original(route, query);
      };
      await mount(tester, source);
      await enterQuery(tester, '144');
      await tester.pump();
      expect(find.text('没有找到匹配的人'), findsNothing);
      expect(find.text('列表未加载完整，重试后继续'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('重试'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('用户 144'), findsOneWidget);
      expect(find.text('1 个搜索结果'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account change hides old rows and rejects pending completion permanently',
    (tester) async {
      final source = music();
      final container = await mount(tester, source);
      final account =
          container.read(platformAccountProvider.notifier)
              as fixture.Connections145Account;
      account.select('8');
      await tester.pump();
      expect(find.text('账号已变化，请返回后重新打开'), findsOneWidget);
      expect(find.text('用户 100'), findsNothing);
      account.select('7');
      await tester.pump();
      expect(find.text('账号已变化，请返回后重新打开'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late list response cannot return after an A-B-A account switch',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final source = music();
      final original = source.reply;
      source.reply = (route, query) =>
          route == '/user/follows' ? pending.future : original(route, query);
      final container = await mount(tester, source);
      final account =
          container.read(platformAccountProvider.notifier)
              as fixture.Connections145Account;
      account.select('8');
      await tester.pump();
      pending.complete({
        'follow': [fixture.connection145User(888)],
        'more': false,
      });
      await tester.pump();
      account.select('7');
      await tester.pump();
      expect(find.text('账号已变化，请返回后重新打开'), findsOneWidget);
      expect(find.text('用户 888'), findsNothing);
      expect(
        source.calls.where((call) => call.$1 == '/artist/sublist'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('narrow dark page and large text retain reachable controls', (
    tester,
  ) async {
    await mount(tester, music(users: 0), dark: true, width: 320, scale: 1.3);
    expect(
      find.byKey(const ValueKey('netease-artist-follow-42')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('personal-connections-sort-0')),
      findsOneWidget,
    );
    await capture(tester, 'following-narrow-dark-large-text');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
