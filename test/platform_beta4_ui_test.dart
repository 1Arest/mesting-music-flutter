import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/presentation/music_home_page.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_library_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comments_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_discovery_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_library_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_profile.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';

const _identity = PlatformSession(
  userId: '7',
  token: 'test',
  nickname: '音乐旅行者',
);
const _resource = PlatformCommentResource(
  kind: PlatformCommentKind.song,
  id: '12345',
  name: '认真的雪',
);
const _track = Track(
  id: 'kugou_HASH',
  title: '认真的雪',
  artist: '薛之谦',
  album: '薛之谦',
  duration: Duration(minutes: 4, seconds: 19),
  source: TrackSource.kugou,
  audioAsset: 'mesting-platform://kugou/kugou_HASH',
  platformSongId: '12345',
  coverAsset: 'assets/branding/mesting-mark-master.png',
  lyricsAsset: '',
);

class _Handler extends MestingAudioHandler {
  _Handler() : super(tracks: []);
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

class _Store implements PlatformSessionStore {
  _Store(this.session);
  final PlatformSession? session;
  @override
  Future<PlatformSession?> read() async => session;
  @override
  Future<void> write(PlatformSession session) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var fontsLoaded = false;
  setUpAll(() async {
    // Optional local QA font, never bundled in the application/source assets.
    if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        final loader = FontLoader('BetaQACJK')
          ..addFont(
            font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              'D:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await icons.load();
        fontsLoaded = true;
      }
    }
  });
  late ProviderContainer container;
  late AppDatabase database;
  late MusicPlatformApi api;
  late PlatformLibraryRepository library;
  late bool metadataReady;
  late List<String> paths;
  Future<void> prepare({bool guest = false}) async {
    metadataReady = false;
    paths = [];
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) async {
        paths.add(request.url.path);
        final Object data = switch (request.url.path) {
          '/user/detail' => {'nickname': '音乐旅行者'},
          '/audio' =>
            metadataReady
                ? {
                    'audio_info': [
                      {'Audioid': 12345},
                    ],
                  }
                : {},
          '/song/url' => {},
          '/user/playlist' => {
            'info': [
              {
                'listid': 11,
                'name': '我喜欢',
                'is_def': 2,
                'list_create_userid': 7,
              },
              {
                'listid': 22,
                'name': '慢慢听，慢慢喜欢',
                'global_collection_id': 'gid',
                'list_create_userid': 7,
              },
            ],
          },
          '/comment/music' || '/comment/music/topliked' || '/comment/floor' => {
            'childrenid': 'child',
            'list': [
              {
                'id': 'one',
                'user_id': 8,
                'user_name': '听风的人',
                'content': '一首歌，留住一段记忆。',
                'like_count': 109,
                'reply_num': 4,
                'special_child_id': 'child',
                'createtime': '2026-07-11 10:00:00',
              },
              {
                'id': 'two',
                'user_id': 7,
                'user_name': '音乐旅行者',
                'content': '今天也在认真听歌。',
                'like_count': 31,
                'special_child_id': 'child',
                'createtime': '2026-10-25 08:00:00',
              },
            ],
          },
          '/top/playlist' => [
            {'global_collection_id': 'gid', 'name': '让旋律陪你走过四季'},
          ],
          _ => {
            'info': [
              for (var i = 0; i < 3; i++)
                {
                  'hash': 'HASH$i',
                  'songname': ['认真的雪', '演员', '天外来物'][i],
                  'singername': '薛之谦',
                  'album_audio_id': 12345 + i,
                  'sizable_cover': 'assets/branding/mesting-mark-master.png',
                },
            ],
          },
        };
        return http.Response(
          jsonEncode({'status': 1, 'error_code': 0, 'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..session = guest ? null : _identity;
    library = PlatformLibraryRepository(
      database,
      api: api,
      identity: _identity,
    );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        authRepositoryProvider.overrideWithValue(
          const UnconfiguredAuthRepository(),
        ),
        platformSessionStoreProvider.overrideWithValue(
          _Store(guest ? null : _identity),
        ),
        musicPlatformApiProvider.overrideWithValue(api),
        libraryRepositoryProvider.overrideWithValue(library),
        audioHandlerProvider.overrideWithValue(_Handler()),
        currentMediaItemProvider.overrideWith(
          (ref) => Stream.value(_track.toMediaItem()),
        ),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(PlaybackState()),
        ),
      ],
    );
    await container.read(platformAccountProvider.future);
  }

  Future<void> disposeFixture(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    library.dispose();
    await database.close();
  }

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    String? capture,
  }) async {
    final theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: fontsLoaded
              ? theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: 'BetaQACJK'),
                )
              : theme,
          home: RepaintBoundary(
            key: const ValueKey('beta4-capture'),
            child: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              body: page,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), null);
    if (capture != null &&
        const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('beta4-capture')),
      );
      await tester.runAsync(() async {
        final picture = await boundary.toImage();
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(
          const String.fromEnvironment('BETA_SCREENSHOT_DIR'),
        );
        await directory.create(recursive: true);
        await File(
          '${directory.path}/$capture.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        picture.dispose();
      });
    }
  }

  void viewport(WidgetTester tester, [Size size = const Size(390, 844)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'platform surfaces reuse Mesting collections and support light/dark themes',
    (tester) async {
      viewport(tester);
      await prepare();
      for (final dark in [false, true]) {
        final suffix = dark ? 'dark' : 'light';
        await pump(
          tester,
          const PlatformAccountPage(),
          dark: dark,
          capture: 'account-$suffix',
        );
        await pump(
          tester,
          PlatformCommentsPage(
            resource: _resource,
            repository: PlatformCommentsRepository(api, _identity),
          ),
          dark: dark,
          capture: 'comments-$suffix',
        );
        await pump(
          tester,
          const PlatformLibraryPage(favorites: true),
          dark: dark,
          capture: 'favorites-$suffix',
        );
        expect(find.byType(FavoriteCollectionView), findsOneWidget);
        await pump(
          tester,
          const PlatformProfile(),
          dark: dark,
          capture: 'profile-$suffix',
        );
        await pump(
          tester,
          const PlatformDiscoveryPage(),
          dark: dark,
          capture: 'discovery-$suffix',
        );
        await pump(
          tester,
          const PlatformCloudPlaylistPage(id: 'kg:22'),
          dark: dark,
          capture: 'playlist-$suffix',
        );
      }
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'comment scope, time ordering and reply keep the real thread identity',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(
        tester,
        PlatformCommentsPage(
          resource: _resource,
          repository: PlatformCommentsRepository(api, _identity),
        ),
      );
      expect(paths, contains('/comment/music/topliked'));
      await tester.tap(find.text('最热'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最新'));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('今天也在认真听歌。')).dy,
        lessThan(tester.getTopLeft(find.text('一首歌，留住一段记忆。')).dy),
      );
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pump();
      expect(find.text('一首歌，留住一段记忆。'), findsNothing);
      expect(find.text('今天也在认真听歌。'), findsOneWidget);
      await tester.tap(find.text('回复').first);
      await tester.pump();
      expect(find.text('回复 音乐旅行者'), findsOneWidget);
      expect(tester.takeException(), null);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'hash-only comment entry stays open on failure and can retry successfully',
    (tester) async {
      viewport(tester);
      await prepare();
      final legacy = _track.copyWith(platformSongId: '');
      await pump(
        tester,
        PlatformSongCommentsPage(
          track: legacy,
          repository: PlatformCommentsRepository(api, _identity),
        ),
      );
      expect(find.text('平台未返回歌曲评论标识，请稍后重试'), findsOneWidget);
      metadataReady = true;
      await tester.tap(find.text('重新加载'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('一首歌，留住一段记忆。'), findsOneWidget);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'narrow login and comment composer stay usable with an open keyboard',
    (tester) async {
      viewport(tester, const Size(320, 700));
      await prepare(guest: true);
      await pump(
        tester,
        const PlatformAccountPage(),
        capture: 'guest-login-narrow',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(find.byType(TextField).first);
      await tester.pump();
      expect(tester.takeException(), null);
      tester.view.resetViewInsets();
      await disposeFixture(tester);
      await prepare();
      await pump(
        tester,
        PlatformCommentsPage(
          resource: _resource,
          repository: PlatformCommentsRepository(api, _identity),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.showKeyboard(find.byType(TextField));
      await tester.pump();
      expect(
        tester
            .getBottomRight(
              find.byKey(const ValueKey('comment-blue-glass-send')),
            )
            .dy,
        lessThan(450),
      );
      expect(tester.takeException(), null);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );
}
