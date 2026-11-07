import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/audiobooks/audiobook_models.dart';
import 'package:mesting_music/features/audiobooks/audiobook_repository.dart';
import 'package:mesting_music/features/audiobooks/audiobook_playback.dart';
import 'package:mesting_music/features/audiobooks/audiobooks_page.dart';
import 'package:mesting_music/features/experience/presentation/music_functions_page.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/platform_explore_providers.dart';
import 'package:mesting_music/features/player/presentation/music_shell.dart';
import 'package:mesting_music/features/search/presentation/music_search_page.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_recommendations.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_recommendation_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_recommendations_page.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:mesting_music/shared/widgets/mesting_loading_indicator.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:19108');
}

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}

class _Search extends MusicSearchController {
  @override
  MusicSearchState build() => const MusicSearchState();
  @override
  void setQuery(String query, {bool composing = false}) =>
      state = MusicSearchState(query: query);
  @override
  Future<void> submit(String query) async => setQuery(query);
}

class _NoProgress implements AudiobookPlaybackBinding {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Books extends AudiobookRepository {
  _Books(MusicPlatformApi api) : super(api, null);
  final searches = <String>[];
  @override
  Future<List<BookCategory>> categories({Future<void>? abortTrigger}) async =>
      const [BookCategory('906', '有声小说')];
  @override
  Future<BookPage<BookAlbum>> albums({
    String category = '906',
    int page = 1,
    Future<void>? abortTrigger,
  }) async => BookPage(
    const [BookAlbum(id: 'book', name: '书库内容', author: '作者')],
    page: page,
    hasMore: false,
  );
  @override
  Future<BookPage<BookAlbum>> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    searches.add(query);
    return BookPage(
      [BookAlbum(id: 'result', name: '$query · 搜索结果', author: '作者')],
      page: page,
      hasMore: false,
    );
  }
}

List<Track> _tracks(int start, int count) => [
  for (var i = start; i < start + count; i++)
    Track(
      id: 'fixture_$i',
      title: '首屏歌曲 $i',
      artist: '本地测试',
      album: '',
      duration: const Duration(minutes: 3),
      audioAsset: '',
      coverAsset: '',
      lyricsAsset: '',
    ),
];

class _Recommendations extends PlatformRecommendations {
  _Recommendations(MusicPlatformApi api, SharedPreferences preferences)
    : super(api, preferences, null);
  final pending = Completer<List<Track>>();
  int calls = 0;
  @override
  Future<List<Track>> personalFm(
    PlatformFmStation station, {
    bool first = true,
    Track? anchor,
    String? action,
  }) {
    calls++;
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const export = bool.fromEnvironment('EXPORT_SEARCH_FIXES');
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!export) return;
    final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
    );
    for (final family in [
      'FixQA',
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(family)..addFont(Future.value(font))).load();
    }
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  late SharedPreferences preferences;
  late MusicPlatformApi api;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    final client = MockClient((_) async => http.Response('{"data":[]}', 200));
    addTearDown(client.close);
    api = MusicPlatformApi(server: _Server(), client: client);
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    _Recommendations? recommendations,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var theme = buildMestingTheme(musicThemePresetById('classic'));
    if (export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'FixQA'),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          platformAccountProvider.overrideWith(_Account.new),
          musicPlatformApiProvider.overrideWithValue(api),
          favoriteTrackIdsProvider.overrideWithValue({}),
          platformFmProvider.overrideWith((ref) async => _tracks(0, 5)),
          if (recommendations != null)
            platformRecommendationsProvider.overrideWithValue(recommendations),
        ],
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp(
            theme: theme,
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: const ValueKey('search-fixes-capture'),
              child: Scaffold(body: child),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!export) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('search-fixes-capture')),
      );
      final picture = await boundary.toImage();
      final png = await picture.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        const String.fromEnvironment('SEARCH_FIXES_SCREENSHOT_DIR'),
      );
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      picture.dispose();
    });
  }

  Future<({GoRouter router, ProviderContainer container, _Books books})> shell(
    WidgetTester tester, {
    bool dark = false,
    String location = '/music',
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final books = _Books(api);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        platformAccountProvider.overrideWith(_Account.new),
        currentUserProvider.overrideWithValue(null),
        musicPlatformApiProvider.overrideWithValue(api),
        currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
        platformRewardAutomationProvider.overrideWith((ref) {}),
        musicSearchControllerProvider.overrideWith(_Search.new),
        platformHotSearchProvider.overrideWith(
          (ref) async => [
            const PlatformHotSearchBoard('热搜榜', ['无奈的思绪', '时过境迁']),
          ],
        ),
        platformExploreProvider.overrideWith((ref, kind) async => []),
        audiobookRepositoryProvider.overrideWithValue(books),
        audiobookProgressBindingProvider.overrideWith((ref) => _NoProgress()),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              MusicShell(location: state.uri.toString(), child: child),
          routes: [
            GoRoute(
              path: '/music',
              builder: (_, _) => const MusicFunctionsPage(),
            ),
            GoRoute(
              path: '/music/recommend',
              builder: (_, _) => const Scaffold(body: Text('发现占位')),
            ),
            GoRoute(
              path: '/music/search',
              builder: (_, _) => const MusicSearchPage(),
            ),
            GoRoute(
              path: '/music/audiobooks',
              builder: (_, _) => const AudiobooksPage(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    var theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    if (export) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'FixQA'),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          brightnessResolver: Theme.maybeBrightnessOf,
          child: MaterialApp.router(
            routerConfig: router,
            theme: theme,
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                key: const ValueKey('search-fixes-capture'),
                child: child!,
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    return (router: router, container: container, books: books);
  }

  Future<void> settleSearch(WidgetTester tester) async {
    // The official pill retargets its geometry in a post-layout callback;
    // advancing one large frame can capture its previous resting width.
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    testWidgets(
      'feature and direct search use the bottom field with working return $dark',
      (tester) async {
        final fixture = await shell(tester, dark: dark);
        await tester.tap(find.byKey(const ValueKey('function-搜索')));
        await settleSearch(tester);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(CupertinoTextField), findsOneWidget);
        expect(
          tester.getSize(find.byType(CupertinoTextField)).width,
          greaterThan(100),
        );
        expect(
          tester.getTopLeft(find.byType(CupertinoTextField)).dy,
          greaterThan(650),
        );
        expect(find.text('热门搜索'), findsOneWidget);
        expect(
          fixture.router.routeInformationProvider.value.uri.path,
          '/music',
        );
        await capture(tester, 'function-search-${dark ? 'dark' : 'light'}');
        await tester.binding.handlePopRoute();
        await settleSearch(tester);
        expect(find.byKey(const ValueKey('function-搜索')), findsOneWidget);
        fixture.router.push<void>('/music/search');
        await settleSearch(tester);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(CupertinoTextField), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(CupertinoTextField)).dy,
          greaterThan(650),
        );
        await tester.binding.handlePopRoute();
        await settleSearch(tester);
        expect(
          fixture.router.routeInformationProvider.value.uri.path,
          '/music',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'book bottom search keeps query ownership, clear and keyboard behavior $dark',
      (tester) async {
        final fixture = await shell(
          tester,
          dark: dark,
          location: '/music/audiobooks',
        );
        expect(find.byType(TextField), findsNothing);
        await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
        await settleSearch(tester);
        final field = find.byType(CupertinoTextField);
        expect(field, findsOneWidget);
        expect(tester.widget<CupertinoTextField>(field).placeholder, '搜索书名、作者');
        expect(tester.getTopLeft(field).dy, greaterThan(650));
        await tester.enterText(field, '山海');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await settleSearch(tester);
        expect(fixture.books.searches, ['山海']);
        expect(find.text('山海 · 搜索结果'), findsOneWidget);
        expect(
          fixture.container.read(musicSearchControllerProvider).query,
          isEmpty,
        );
        await capture(tester, 'book-search-${dark ? 'dark' : 'light'}');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.tap(field);
        await settleSearch(tester);
        expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(544));
        await capture(tester, 'book-keyboard-${dark ? 'dark' : 'light'}');
        await tester.enterText(field, '');
        await settleSearch(tester);
        expect(find.text('书库内容'), findsOneWidget);
        expect(
          fixture.container.read(musicSearchControllerProvider).query,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.binding.handlePopRoute();
        await settleSearch(tester);
        expect(find.text('挑一本，慢慢听'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'menu connector surfaces leave the scene after separation and rejoin on reverse',
    (tester) async {
      final motion = AnimationController(
        vsync: tester,
        duration: betaMenuOpenDuration,
      );
      await mount(
        tester,
        Builder(
          builder: (context) => BetaLiquidMenu(
            animation: motion,
            layout: BetaMenuLayout(
              anchor: const Rect.fromLTWH(330, 40, 48, 48),
              media: MediaQuery.of(context),
              width: 280,
              fromInnerEdge: true,
            ),
            child: const SizedBox(width: 280, height: 400),
          ),
        ),
      );
      final connectors = find.byWidgetPredicate(
        (widget) =>
            widget is GlassContainer &&
            (widget.key == const ValueKey('beta105-liquid-source') ||
                widget.key == const ValueKey('beta105-liquid-neck')),
      );
      expect(connectors, findsNWidgets(2));
      motion.value = .71;
      await tester.pump();
      expect(connectors, findsNWidgets(2));
      motion.value = .72;
      await tester.pump();
      expect(connectors, findsNothing);
      motion.value = 1;
      await tester.pump();
      expect(
        connectors,
        findsNothing,
        reason:
            'A subpixel connector still influences the blended SDF and leaves a dot/bump.',
      );
      motion.value = .45;
      await tester.pump();
      expect(connectors, findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      motion.dispose();
    },
  );

  testWidgets(
    'a book search survives a covered route without leaking text or focus',
    (tester) async {
      final fixture = await shell(tester, location: '/music/audiobooks');
      await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
      await settleSearch(tester);
      var field = find.byType(CupertinoTextField);
      await tester.enterText(field, '保留的书名');
      fixture.router.push<void>('/music/search');
      await settleSearch(tester);
      field = find.byType(CupertinoTextField);
      expect(tester.widget<CupertinoTextField>(field).placeholder, '搜索歌曲、歌手');
      expect(
        tester.widget<CupertinoTextField>(field).controller!.text,
        isEmpty,
      );
      await tester.enterText(field, '歌曲查询');
      await settleSearch(tester);
      expect(
        fixture.container.read(musicSearchControllerProvider).query,
        '歌曲查询',
      );
      expect(fixture.books.searches, isEmpty);
      await tester.binding.handlePopRoute();
      await settleSearch(tester);
      await tester.binding.handlePopRoute();
      await settleSearch(tester);
      field = find.byType(CupertinoTextField);
      expect(tester.widget<CupertinoTextField>(field).placeholder, '搜索书名、作者');
      expect(
        tester.widget<CupertinoTextField>(field).controller!.text,
        '保留的书名',
      );
      expect(
        tester.widget<CupertinoTextField>(field).focusNode!.hasFocus,
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final config in [
    (const Size(320, 740), 1.6, 'small-large-text'),
    (const Size(768, 1024), 1.0, 'wide'),
  ]) {
    testWidgets('shared book field fits the keyboard ${config.$3}', (
      tester,
    ) async {
      await shell(
        tester,
        location: '/music/audiobooks',
        size: config.$1,
        scale: config.$2,
      );
      await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
      await settleSearch(tester);
      final field = find.byType(CupertinoTextField);
      await tester.enterText(field, '山海');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      // Official spring layout retargets after its first new keyboard frame.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.getBottomRight(field).dy,
        lessThanOrEqualTo(config.$1.height - 280),
      );
      expect(find.byType(TextField), findsNothing);
      await capture(tester, 'book-${config.$3}');
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('restored direct search closes to its logical parent once', (
    tester,
  ) async {
    final fixture = await shell(tester, location: '/music/search');
    await settleSearch(tester);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleSearch(tester);
    expect(
      fixture.router.routeInformationProvider.value.uri.path,
      '/music/recommend',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'raw Navigator coverage restores the book field after a music overlay closes',
    (tester) async {
      await shell(tester, location: '/music/audiobooks');
      await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
      await settleSearch(tester);
      await tester.enterText(find.byType(CupertinoTextField), '保留的小说');
      final navigator = Navigator.of(
        tester.element(find.byType(AudiobooksPage)),
      );
      navigator.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('专辑占位'))),
      );
      await settleSearch(tester);
      await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
      await settleSearch(tester);
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .placeholder,
        '搜索歌曲、歌手',
      );
      // An asynchronous destination can finish while the shell search is open.
      // Its return must not replace the active music overlay's controller.
      navigator.pop();
      await settleSearch(tester);
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .placeholder,
        '搜索歌曲、歌手',
      );
      await tester.binding.handlePopRoute();
      await settleSearch(tester);
      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(field.placeholder, '搜索书名、作者');
      expect(field.controller!.text, '保留的小说');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('FM requests its next batch only after downward scrolling', (
    tester,
  ) async {
    final repository = _Recommendations(api, preferences);
    await mount(
      tester,
      const PlatformRecommendationDetail(
        title: '私人 FM',
        kind: PlatformRecommendationKind.fm,
      ),
      recommendations: repository,
    );
    repository.pending.complete(_tracks(5, 15));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 2));
    expect(repository.calls, 1);
    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(repository.calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'FM exhaustion and initial errors never loop or expose a pending partial batch',
    (tester) async {
      final exhausted = _Recommendations(api, preferences);
      await mount(
        tester,
        const PlatformRecommendationDetail(
          title: '私人 FM',
          kind: PlatformRecommendationKind.fm,
        ),
        recommendations: exhausted,
      );
      exhausted.pending.complete(_tracks(0, 5));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.byType(EditorialTrackRow), findsNWidgets(5));
      expect(exhausted.calls, 1);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(exhausted.calls, 1);
      await tester.pumpWidget(const SizedBox());

      final failed = _Recommendations(api, preferences);
      await mount(
        tester,
        const PlatformRecommendationDetail(
          title: '私人 FM',
          kind: PlatformRecommendationKind.fm,
        ),
        recommendations: failed,
      );
      failed.pending.completeError(const MusicPlatformException('本地模拟失败'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.text('推荐暂时无法读取'), findsOneWidget);
      expect(find.byType(EditorialTrackRow), findsNothing);
      expect(find.byType(MestingLoadingIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('FM waits for its initial viewport batch before showing any songs', (
    tester,
  ) async {
    final repository = _Recommendations(api, preferences);
    await mount(
      tester,
      const PlatformRecommendationDetail(
        title: '私人 FM',
        kind: PlatformRecommendationKind.fm,
      ),
      recommendations: repository,
    );
    expect(repository.calls, 1);
    expect(
      find.byType(EditorialTrackRow),
      findsNothing,
      reason:
          'The cached first five must not appear while the rest of the first screen is pending.',
    );
    repository.pending.complete(_tracks(5, 15));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(find.byType(EditorialTrackRow), findsWidgets);
    await capture(tester, 'fm-ready');
    expect(
      repository.calls,
      1,
      reason:
          'A settled first screen must not immediately prefetch another page.',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('FM loading indicator has no filled panel behind it', (
    tester,
  ) async {
    final repository = _Recommendations(api, preferences);
    await mount(
      tester,
      const PlatformRecommendationDetail(
        title: '私人 FM',
        kind: PlatformRecommendationKind.fm,
      ),
      recommendations: repository,
    );
    final indicator = find.byType(MestingLoadingIndicator);
    await capture(tester, 'fm-loading');
    expect(indicator, findsWidgets);
    expect(
      find.ancestor(of: indicator, matching: find.byType(PlatformPanel)),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
