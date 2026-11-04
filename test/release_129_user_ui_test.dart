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
import 'package:mesting_music/features/music_platform/data/platform_category_search.dart';
import 'package:mesting_music/features/music_platform/domain/platform_search_user.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_user_repository.dart';
import 'package:mesting_music/features/music_platform/platform_category_search_providers.dart';
import 'package:mesting_music/features/search/presentation/beta_category_search_results.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

const user = PlatformSearchUser(
  id: '42',
  nickname: '谦谦的音乐日记',
  signature: '把喜欢的音乐留在这里，与你分享每一次单曲循环。',
  followers: 128,
  following: 36,
  level: 8,
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: '7',
    token: 'fixture',
    platform: MusicPlatform.netease,
  );
}

class _Search extends MusicSearchController {
  @override
  MusicSearchState build() => const MusicSearchState(query: '谦');
}

class _Categories extends CategorySearchController {
  @override
  CategorySearchState build() => CategorySearchState(
    '谦',
    selected: PlatformSearchKind.users,
    pages: {
      PlatformSearchKind.users: CategorySearchSlice(
        total: 1,
        more: false,
        items: [
          PlatformSearchHit(
            kind: PlatformSearchKind.users,
            id: user.id,
            title: user.nickname,
            user: user,
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
          NeteaseApi(
            MockClient((_) async => throw StateError('No real network')),
          ),
        ),
      );
  int writes = 0;
  Completer<void>? pending;
  @override
  Future<void> follow(String id, bool value) async {
    writes++;
    await pending?.future;
  }

  @override
  Future<PlatformSearchUser> profile(String id) async => user;
  @override
  Future<NeteaseUserPage<NeteasePublicPlaylist>> playlists(
    String id,
    int offset,
  ) async => const NeteaseUserPage([
    NeteasePublicPlaylist(
      id: '101',
      name: '那些适合深夜听的歌',
      cover: 'assets/images/theme_playlists/shinchan/cover-01.jpg',
      creator: '42',
      trackCount: 23,
    ),
    NeteasePublicPlaylist(
      id: '102',
      name: '一路有音乐',
      cover: 'assets/images/theme_playlists/shinchan/cover-02.jpg',
      creator: '9',
      trackCount: 16,
    ),
  ], false);
  @override
  Future<NeteaseUserPage<PlatformSearchUser>> connections(
    String id, {
    required bool followers,
    required int offset,
  }) async => const NeteaseUserPage([user], false);
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_129')) {
      for (final family in [
        'MestingQA',
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
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });
  Future<ProviderContainer> mount(
    WidgetTester tester,
    _Users users,
    Widget page, {
    bool dark = false,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        platformAccountProvider.overrideWith(_Account.new),
        neteaseUserRepositoryProvider.overrideWithValue(users),
        musicSearchControllerProvider.overrideWith(_Search.new),
        categorySearchProvider.overrideWith(_Categories.new),
      ],
    );
    addTearDown(c.dispose);
    await c.read(platformAccountProvider.future);
    final host = BetaBottomSearchHost(
      location: '/search',
      openMusicSearch: () {},
    );
    addTearDown(host.dispose);
    final theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'MestingQA'),
            listTileTheme: theme.listTileTheme.copyWith(
              titleTextStyle: TextStyle(
                fontFamily: 'MestingQA',
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
              subtitleTextStyle: TextStyle(
                fontFamily: 'MestingQA',
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: BetaBottomSearchScope(host: host, child: child!),
          ),
          home: RepaintBoundary(
            key: const ValueKey('capture129'),
            child: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              body: page,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return c;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_129')) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture129')),
          )
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('.codex-artifacts/2026-11-01-release129/ui')
        ..createSync(recursive: true);
      await File(
        '${folder.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'user search row follows once and shares confirmed state with the profile button',
    (tester) async {
      final users = _Users()..pending = Completer<void>();
      final c = await mount(tester, users, const BetaCategorySearchResults());
      expect(find.byKey(const ValueKey('search-kind-users')), findsOneWidget);
      expect(find.text(user.nickname), findsOneWidget);
      await capture(tester, 'users-search-light');
      await tester.tap(find.byKey(const ValueKey('netease-follow-42')));
      await tester.pump();
      expect(users.writes, 1);
      expect(c.read(neteaseUserRelationsProvider)['42']?.busy, true);
      users.pending!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('已关注'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dragging from the follow lens cancels the operation before finger release',
    (tester) async {
      final users = _Users();
      await mount(
        tester,
        users,
        ListView(
          children: [
            const NeteaseSearchUserRow(user: user),
            const SizedBox(height: 1600),
          ],
        ),
      );
      final button = find.byType(BetaGlassButton);
      final drag = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 180));
      await drag.moveBy(const Offset(0, -55));
      await tester.pump(const Duration(milliseconds: 450));
      expect(users.writes, 0);
      final glass = tester.widget<GlassButton>(find.byType(GlassButton));
      expect(glass.persistPressOnDrag, false);
      await drag.up();
      await tester.pump();
      expect(users.writes, 0);
    },
  );

  testWidgets(
    'unfollow requires confirmation and publishes the server-confirmed state',
    (tester) async {
      final users = _Users();
      const followed = PlatformSearchUser(
        id: '42',
        nickname: '谦谦的音乐日记',
        followed: true,
      );
      final c = await mount(
        tester,
        users,
        const Center(child: NeteaseFollowButton(user: followed)),
      );
      await tester.tap(find.text('已关注'));
      await tester.pumpAndSettle();
      expect(find.text('取消关注？'), findsOneWidget);
      await tester.tap(find.text('保留关注'));
      await tester.pumpAndSettle();
      expect(users.writes, 0);
      await tester.tap(find.text('已关注'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消关注'));
      await tester.pumpAndSettle();
      expect(users.writes, 1);
      expect(c.read(neteaseUserRelationsProvider)['42']?.followed, false);
      expect(find.text('关注'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'public profile fits ${dark ? 'dark narrow large text' : 'light phone'} and opens the follower list',
      (tester) async {
        final users = _Users();
        await mount(
          tester,
          users,
          const NeteaseUserProfilePage(user: user),
          dark: dark,
          width: dark ? 320 : 390,
          scale: dark ? 1.3 : 1,
        );
        expect(find.text('创建的歌单'), findsOneWidget);
        expect(find.text('那些适合深夜听的歌'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          dark ? 'user-profile-dark-320-large' : 'user-profile-light',
        );
        await tester.tap(find.text('128 粉丝'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(NeteaseUserConnectionsPage), findsOneWidget);
        expect(find.byType(NeteaseSearchUserRow), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
