import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_library_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_page.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/platform_recommendation_providers.dart';
import 'package:mesting_music/features/music_platform/platform_explore_providers.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_profile.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/history/listening_history_providers.dart';
import 'package:mesting_music/features/experience/presentation/music_landing_page.dart';
import 'package:mesting_music/features/experience/presentation/music_functions_page.dart';
import 'package:mesting_music/features/experience/presentation/music_library_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';

const account = PlatformSession(
  userId: '7',
  token: 'synthetic-fixture',
  nickname: '梅斯特林',
  platform: MusicPlatform.netease,
);
const track = Track(
  id: 'netease_7',
  title: '陪你去流浪',
  artist: '薛之谦',
  album: '尘',
  duration: Duration(minutes: 4),
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.netease,
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => account;
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_NETEASE_V112')) {
      for (final family in [
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
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = NeteaseApi(
      MockClient((_) async => http.Response('{"code":200}', 200)),
    );
    final music = NeteaseMusicRepository(api);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(_Account.new),
        platformProfileProvider.overrideWith((ref) async => null),
        libraryRepositoryProvider.overrideWithValue(
          NeteaseLibraryRepository(db, music: music, identity: account),
        ),
        favoriteTracksProvider.overrideWith((ref) => Stream.value([])),
        playlistsProvider.overrideWith((ref) => Stream.value([])),
        recentPlaybackProvider.overrideWith((ref) => Stream.value([])),
        platformFmProvider.overrideWith((ref) async => [track]),
        platformDailyProvider.overrideWith((ref) async => [track]),
        platformNewSongsProvider.overrideWith((ref) async => [track]),
        platformExploreProvider.overrideWith((ref, kind) async => []),
        neteaseFeedPreviewProvider.overrideWith(
          (ref, feed) async => NeteaseBatch([
            NeteaseItem(
              id: '7',
              name: '网易云推荐',
              kind: NeteaseEntity.playlist,
              subtitle: '为你精选',
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(platformAccountProvider.future);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildMestingTheme(
            musicThemePresetById(dark ? 'classic-dark' : 'classic'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => RepaintBoundary(
                key: const ValueKey('capture-v112'),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: page,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_NETEASE_V112')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture-v112')),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '.codex-artifacts/2026-10-29-netease-completion/ui/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final entry in <String, Widget>{
      'discover': const MusicLandingPage(),
      'functions': const MusicFunctionsPage(),
      'library': const MusicLibraryPage(),
      'profile': const PlatformProfile(),
    }.entries) {
      testWidgets('NetEase ${entry.key} theme=$dark', (tester) async {
        await mount(tester, entry.value, dark: dark);
        expect(find.textContaining('酷狗'), findsNothing);
        if (entry.key == 'functions') {
          expect(find.text('一起听'), findsNothing);
          expect(find.text('听书'), findsNothing);
          expect(find.text('听歌识曲'), findsNothing);
        }
        if (entry.key == 'profile') {
          expect(find.text('签到与会员'), findsNothing);
          expect(find.text('签到'), findsOneWidget);
          expect(find.text('我喜欢的音乐'), findsOneWidget);
        }
        await capture(tester, '${entry.key}-${dark ? 'dark' : 'light'}');
      });
    }
  }
  for (final entry in <String, Widget>{
    'functions': const MusicFunctionsPage(),
    'library': const MusicLibraryPage(),
    'profile': const PlatformProfile(),
  }.entries) {
    testWidgets('NetEase ${entry.key} compact with large text', (tester) async {
      await mount(tester, entry.value, size: const Size(320, 650), scale: 1.5);
      await capture(tester, '${entry.key}-compact');
    });
  }
}
