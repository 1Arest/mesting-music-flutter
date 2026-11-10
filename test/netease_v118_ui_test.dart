import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/audio_downloads_page.dart';
import 'package:mesting_music/features/music_platform/data/cloud_library_repository.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_account_overview.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_page.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/settings/presentation/settings_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:mesting_music/shared/widgets/retained_artwork_frame.dart';
import 'package:mesting_music/shared/widgets/beta_glass_menu_item.dart';
import 'package:mesting_music/shared/widgets/beta_scroll_behavior.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';
import 'netease_v115_sources_test.dart' show TestAccount;
import 'netease_v112_fallback_download_test.dart' show recording;

class _Library extends CloudLibraryRepository {
  _Library(super.db) : super(ownerId: 'netease:7');
  @override
  bool canManage(String id) => id == 'created';
  @override
  Future<String> commentId(String id) async => id;
}

// Only Flutter's image loader uses this client. The disk cache is independently
// forced to fail, proving the fallback actually decodes a cover instead of
// merely replacing an empty box with a different empty image widget.
class _ImageClient extends Fake implements HttpClient {
  _ImageClient(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest(bytes);
}

class _ImageRequest extends Fake implements HttpClientRequest {
  _ImageRequest(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
}

class _ImageResponse extends Fake implements HttpClientResponse {
  _ImageResponse(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_V118')) {
      for (final family in [
        'MestingQA',
        'Noto Sans SC',
        'Microsoft YaHei',
        'Arial',
        'Roboto',
        'sans-serif',
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
              'D:/flutter/mesting-beta5/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
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
    AudioDownloadManager? manager,
    http.Client? client,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = _Library(db);
    addTearDown(library.dispose);
    final api =
        NeteaseApi(
          client ??
              MockClient((request) async {
                if (request.url.path.endsWith('/user/level')) {
                  return http.Response(
                    jsonEncode({
                      'code': 200,
                      'data': {
                        'level': 9,
                        'nowPlayCount': 17874,
                        'nextPlayCount': 20000,
                        'nowLoginCount': 400,
                        'nextLoginCount': 365,
                        'info': '60G 音乐云盘免费容量',
                      },
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  );
                }
                return http.Response(
                  jsonEncode({
                    'code': 200,
                    'data': [],
                    'profile': {'nickname': '林间听雨'},
                    'count': 0,
                    'mvCount': 0,
                    'artistCount': 8,
                    'albumCount': 0,
                    'createdPlaylistCount': 2,
                    'subPlaylistCount': 2,
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              }),
        )..configure(
          const NeteaseSession(
            userId: '7',
            cookies: {'MUSIC_U': 'ui-fixture-only'},
            deviceId: 'fixture',
          ),
        );
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appVersionProvider.overrideWith(
          (ref) async => const AppVersionInfo(
            packageName: 'com.mesting.music.beta',
            versionName: '1.0.18',
            versionCode: 39,
          ),
        ),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        platformAccountProvider.overrideWith(TestAccount.new),

        neteaseMusicRepositoryProvider.overrideWithValue(
          NeteaseMusicRepository(api),
        ),
        platformProfileProvider.overrideWith(
          (ref) async => const PlatformProfileInfo('林间听雨', ''),
        ),
        libraryRepositoryProvider.overrideWithValue(library),
        favoriteTracksProvider.overrideWith(
          (ref) => Stream.value([recording()]),
        ),
        playlistsProvider.overrideWith(
          (ref) => Stream.value([
            for (final id in ['created', 'saved'])
              UserPlaylist(
                ownerId: 'netease:7',
                id: id,
                name: id == 'created' ? '我的日常歌单' : '收藏的好声音',
                description: '',
                coverAsset: 'assets/branding/dress-midnight-launch-v2.webp',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
          ]),
        ),
        neteaseCatalogProvider.overrideWith((ref) async => []),
        if (manager != null)
          audioDownloadManagerProvider.overrideWithValue(manager),
      ],
    );
    addTearDown(c.dispose);
    await c.read(platformAccountProvider.future);
    tester.view.physicalSize = Size(compact ? 320 : 390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: theme,
          scrollBehavior: const BetaScrollBehavior(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(compact ? 1.3 : 1),
            ),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('v118-capture'),
            child: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              body: page,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    return c;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_V118')) return;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('v118-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(
        '.codex-artifacts/2026-10-29-v118-investigation/ui',
      );
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      final mode =
          '${dark ? 'dark' : 'light'}-${compact ? 'compact' : 'regular'}';
      testWidgets('account real Lv.9, progress and empty counts $mode', (
        tester,
      ) async {
        await mount(
          tester,
          const NeteaseAccountOverviewPage(),
          dark: dark,
          compact: compact,
        );
        expect(find.text('当前等级：Lv.9'), findsOneWidget);
        expect(find.text('还需听 2126 首歌'), findsOneWidget);
        expect(find.text('还需登录 0 天'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'level-$mode');
      });
      testWidgets(
        'settings is a list and local effects are not duplicated $mode',
        (tester) async {
          await mount(
            tester,
            const SettingsPage(),
            dark: dark,
            compact: compact,
          );
          expect(find.text('账号管理'), findsOneWidget);
          expect(find.text('账号与同步'), findsOneWidget);
          expect(find.text('本地 SVIP'), findsNothing);
          expect(find.text('音效'), findsNothing);
          expect(find.text('下载与存储'), findsNothing);
          expect(tester.takeException(), isNull);
          await capture(tester, 'settings-$mode');
        },
      );
      testWidgets('download actions share one row $mode', (tester) async {
        final manager = AudioDownloadManager(
          client: MockClient((_) async => http.Response('', 404)),
          resolve: (track) async => '',
          publish: (f, t, e, m) async => '',
          currentOwner: () => 'netease:7',
          directory: () async => Directory.systemTemp,
          persist: (_) async {},
          restored: [
            AudioDownloadTask(
              id: 'done',
              owner: 'netease:7',
              track: recording(),
              phase: AudioDownloadPhase.completed,
              uri: 'content://fixture/tree/a/document/a/song.mp3',
            ),
          ],
        );
        addTearDown(manager.dispose);
        await mount(
          tester,
          const AudioDownloadsPage(downloadedOnly: true),
          dark: dark,
          compact: compact,
          manager: manager,
        );
        final a = tester.getCenter(find.text('播放全部')),
            b = tester.getCenter(find.text('打开目录')),
            d = tester.getCenter(find.text('选择目录'));
        expect(a.dy, closeTo(b.dy, 1));
        expect(b.dy, closeTo(d.dy, 1));
        expect(a.dx, lessThan(b.dx));
        expect(b.dx, lessThan(d.dx));
        expect(tester.takeException(), isNull);
        await capture(tester, 'downloads-$mode');
      });
    }
  }
  testWidgets(
    'successful empty purchased and MV collections show explicit empty states',
    (tester) async {
      await mount(
        tester,
        NeteaseFullTaskPage(
          endpoint: NeteaseEndpoint.fromJson(
            Map<String, dynamic>.from(
              (jsonDecode(
                        File(
                          'assets/data/netease-full-catalog.json',
                        ).readAsStringSync(),
                      )['entries']
                      as List)
                  .firstWhere((e) => e['route'] == '/song/purchased'),
            ),
          ),
        ),
      );
      expect(find.text('暂无已购单曲'), findsOneWidget);
      expect(find.text('数量'), findsNothing);
      await capture(tester, 'empty-purchased');
      await mount(
        tester,
        const NeteaseFeaturesPage(feed: NeteaseFeed.likedMvs),
      );
      expect(find.textContaining('暂无收藏的'), findsOneWidget);
      await capture(tester, 'empty-mvs');
    },
  );
  testWidgets(
    'failed purchased request remains retryable and is not called empty',
    (tester) async {
      await mount(
        tester,
        NeteaseFullTaskPage(
          endpoint: NeteaseEndpoint.fromJson(
            Map<String, dynamic>.from(
              (jsonDecode(
                        File(
                          'assets/data/netease-full-catalog.json',
                        ).readAsStringSync(),
                      )['entries']
                      as List)
                  .firstWhere((e) => e['route'] == '/song/purchased'),
            ),
          ),
        ),
        client: MockClient((_) async => http.Response('{"code":500}', 500)),
      );
      expect(find.text('暂无已购单曲'), findsNothing);
      expect(find.text('重新加载'), findsOneWidget);
    },
  );
  testWidgets(
    'personal page keeps one download entry and lighter scoped weights',
    (tester) async {
      await mount(tester, const BetaPersonalProfile());
      expect(find.text('已下载'), findsOneWidget);
      expect(find.text('下载与存储'), findsNothing);
      expect(find.text('Lv.9'), findsOneWidget);
      final nickname = tester.widget<Text>(find.text('林间听雨'));
      expect(nickname.style!.fontWeight, FontWeight.w500);
      await capture(tester, 'personal');
      await tester.scrollUntilVisible(find.text('收藏的歌单 · 1'), 160);
      expect(find.byType(ArtworkImage), findsWidgets);
      await capture(tester, 'playlist-covers');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'touch scroll clears menu highlight before finger up and never invokes an action',
    (tester) async {
      var actions = 0;
      await mount(
        tester,
        SizedBox(
          height: 500,
          child: ListView(
            children: [
              for (var i = 0; i < 20; i++)
                BetaGlassMenuItem(
                  onTap: () => actions++,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text('菜单 $i'),
                  ),
                ),
            ],
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('菜单 2')),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump(const Duration(milliseconds: 180));
      for (final widget in tester.widgetList<AnimatedScale>(
        find.descendant(
          of: find.byType(BetaGlassMenuItem),
          matching: find.byType(AnimatedScale),
        ),
      )) {
        expect(widget.scale, 1);
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      final containers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(BetaGlassMenuItem),
          matching: find.byType(AnimatedContainer),
        ),
      );
      for (final widget in containers) {
        final gradient =
            (widget.decoration as BoxDecoration).gradient as LinearGradient;
        expect(gradient.colors.every((c) => c.a == 0), true);
      }
      expect(actions, 0);
      await tester.tap(find.text('菜单 3'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(actions, 1);
    },
  );
  testWidgets(
    'unavailable private image cache still renders a visible fallback instead of a blank box',
    (tester) async {
      final cache = PersistentNetworkImageCache(
        directoryProvider: () async =>
            throw const FileSystemException('fixture storage unavailable'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ArtworkImage(
            uri: 'https://cdn.example/cover.jpg',
            width: 64,
            height: 64,
            persistentNetworkCacheKey: 'fixture-cover',
            networkImageCache: cache,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byType(RetainedArtworkFrame), findsOneWidget);
      expect(
        tester
            .widget<RetainedArtworkFrame>(find.byType(RetainedArtworkFrame))
            .image,
        isNotNull,
      );
      if (DistributionChannel.isBeta) {
        expect(find.text('重试'), findsOneWidget);
        expect(find.byIcon(Icons.album_rounded), findsNothing);
      } else {
        expect(find.byIcon(Icons.album_rounded), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cache failure still decodes the actual remote cover', (
    tester,
  ) async {
    late Uint8List png;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      png = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
    });
    debugNetworkImageHttpClientProvider = () => _ImageClient(png);
    addTearDown(() => debugNetworkImageHttpClientProvider = null);
    final cache = PersistentNetworkImageCache(
      directoryProvider: () async =>
          throw const FileSystemException('fixture no storage'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkImage(
          uri: 'https://cdn.example/actual-cover.png',
          width: 64,
          height: 64,
          persistentNetworkCacheKey: 'actual-cover',
          networkImageCache: cache,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(find.byIcon(Icons.album_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    debugNetworkImageHttpClientProvider = null;
  });
}
