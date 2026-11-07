import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/audio_downloads_page.dart';
import 'package:mesting_music/features/music_platform/data/cloud_library_repository.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/retained_kugou_scope.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_track_sources.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/netease_source_picker.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/presentation/beta_personal_profile.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/widgets/beta_scroll_behavior.dart';
import 'package:mesting_music/shared/widgets/beta_choice_field.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'netease_v115_sources_test.dart' show TestAccount;
import 'netease_v116_recovery_test.dart' show localSong;
import 'netease_v112_fallback_download_test.dart' show recording;
import 'support/deterministic_audio_player.dart';
import 'support/no_music_account_fixture.dart';

class _Library extends CloudLibraryRepository {
  _Library(super.database) : super(ownerId: 'netease:7');
  @override
  bool canManage(String id) => id == 'created';
  @override
  Future<String> commentId(String id) async => id;
}

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (const bool.fromEnvironment('CAPTURE_V117')) {
      for (final family in [
        'MestingQA',
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

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_V117')) return;
    await tester.runAsync(() async {
      final render = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture117')),
      );
      final image = await render.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final folder = Directory('.codex-artifacts/2026-10-29-release117/ui');
      await folder.create(recursive: true);
      await File(
        '${folder.path}/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<ProviderContainer> mount(
    WidgetTester tester,
    Widget child, {
    bool dark = false,
    double width = 390,
    double textScale = 1,
    AudioDownloadManager? downloads,
    MestingAudioHandler? audio,
    NeteaseSourceAvailability? availability,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = _Library(db);
    addTearDown(library.dispose);
    final now = DateTime(2026, 10, 29);
    final apiClient = MockClient((_) async => http.Response('No network', 500));
    addTearDown(apiClient.close);
    final music = NeteaseMusicRepository(
      NeteaseApi(apiClient)..configure(
        const NeteaseSession(
          userId: '7',
          cookies: {'MUSIC_U': 'synthetic-only'},
          deviceId: 'fixture',
        ),
      ),
    );
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        platformAccountProvider.overrideWith(TestAccount.new),
        savedKugouSessionProvider.overrideWith((ref) async => null),
        if (availability != null) ...[
          neteaseMusicRepositoryProvider.overrideWithValue(music),
          neteaseSourceAvailabilityProvider.overrideWithValue(availability),
        ],
        platformProfileProvider.overrideWith(
          (ref) async =>
              const PlatformProfileInfo('林间听雨', '', signature: '收藏一些喜欢的声音'),
        ),
        libraryRepositoryProvider.overrideWithValue(library),
        favoriteTracksProvider.overrideWith(
          (ref) => Stream.value([localSong('like')]),
        ),
        playlistsProvider.overrideWith(
          (ref) => Stream.value([
            UserPlaylist(
              ownerId: 'netease:7',
              id: 'created',
              name: '午后听见风',
              description: '',
              createdAt: now,
              updatedAt: now,
            ),
            UserPlaylist(
              ownerId: 'netease:7',
              id: 'saved',
              name: '收藏的旋律',
              description: '',
              createdAt: now,
              updatedAt: now,
            ),
          ]),
        ),
        neteaseCatalogProvider.overrideWith((ref) async => []),
        if (downloads != null)
          audioDownloadManagerProvider.overrideWithValue(downloads),
        if (audio != null) audioHandlerProvider.overrideWithValue(audio),
      ],
    );
    addTearDown(c.dispose);
    await c.read(platformAccountProvider.future);
    tester.view.physicalSize = Size(width, 844);
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
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'MestingQA'),
            listTileTheme: theme.listTileTheme.copyWith(
              titleTextStyle: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'MestingQA',
              ),
              subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'MestingQA',
              ),
            ),
          ),
          scrollBehavior: const BetaScrollBehavior(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('capture117'),
            child: ColoredBox(color: theme.colorScheme.surface, child: child),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    return c;
  }

  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets(
        'personal library groups retain Apple controls dark=$dark compact=$compact',
        (tester) async {
          await mount(
            tester,
            const Scaffold(body: BetaPersonalProfile()),
            dark: dark,
            width: compact ? 320 : 390,
            textScale: compact ? 1.3 : 1,
          );
          expect(find.text('林间听雨'), findsOneWidget);
          expect(find.text('已下载'), findsOneWidget);
          expect(find.text('账号选项'), findsNothing);
          expect(find.byType(StretchingOverscrollIndicator), findsNothing);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'profile-${dark ? 'dark' : 'light'}-${compact ? 'narrow' : 'regular'}',
          );
          await tester.scrollUntilVisible(find.text('收藏的歌单 · 1'), 180);
          expect(find.text('创建的歌单 · 1'), findsOneWidget);
          expect(find.text('收藏的歌单 · 1'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('glass choice respects selection and disabled state', (
    tester,
  ) async {
    var selected = 1;
    await mount(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: BetaChoiceField<int>(
              initialValue: 1,
              items: const [
                DropdownMenuItem(value: 1, child: Text('按顺序优先')),
                DropdownMenuItem(value: 2, child: Text('优先最高音质')),
              ],
              onChanged: (value) => selected = value!,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('按顺序优先'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('优先最高音质'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(selected, 2);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Downloaded Play All binds saved URIs in displayed order', (
    tester,
  ) async {
    late DeterministicAudioPlayer player;
    late MestingAudioHandler handler;
    await tester.runAsync(() async {
      player = DeterministicAudioPlayer();
      handler = MestingAudioHandler(tracks: [], player: player);
      await handler.replaceQueue([], autoplay: false);
    });
    addTearDown(handler.debugDispose);
    handler.configureTrackPlaybackResolver((track) async {
      expect(track.hasLocalAudio, true);
      return track;
    });
    final manager = AudioDownloadManager(
      client: MockClient((_) async => http.Response('network forbidden', 500)),
      resolve: (_) async => throw StateError('offline'),
      publish: (_, _, _, _) async => throw StateError('unused'),
      currentOwner: () => 'netease:7',
      directory: () async => Directory.systemTemp,
      persist: (_) async {},
      restored: [
        AudioDownloadTask(
          id: 'first',
          owner: 'netease:7',
          track: recording(id: 'netease_1'),
          phase: AudioDownloadPhase.completed,
          uri: 'content://documents/first.mp3',
        ),
        AudioDownloadTask(
          id: 'last',
          owner: 'netease:7',
          track: recording(id: 'netease_2'),
          phase: AudioDownloadPhase.completed,
          uri: 'content://documents/last.mp3',
        ),
      ],
    );
    addTearDown(manager.dispose);
    const channel = MethodChannel('com.mesting.music/audio_download');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'readable' ? true : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await mount(
      tester,
      const AudioDownloadsPage(downloadedOnly: true),
      downloads: manager,
      audio: handler,
    );
    await capture(tester, 'downloaded');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('downloaded-play-all')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(handler.mediaItem.value?.id, 'netease_2');
    expect(handler.upcomingQueue.single.id, 'netease_1');
    expect(player.active, true);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'third-level routes pop one level from either edge and system Back',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      Widget page(String name, [Widget? next]) => PlatformPageFrame(
        title: name,
        child: Center(
          child: next == null
              ? Text(name)
              : BetaGlassButton(
                  onPressed: () =>
                      nav.currentState!.push(betaContentRoute<void>(next)),
                  child: Text('进入$name'),
                ),
        ),
      );
      final third = page('三级');
      final second = page('二级', third);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          builder: (_, child) => ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              platformAccountProvider.overrideWith(NoMusicAccountFixture.new),
              currentMediaItemProvider.overrideWith(
                (ref) => Stream.value(null),
              ),
            ],
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    nav.currentState!.push(betaContentRoute<void>(second)),
                child: const Text('进入'),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('进入'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('进入二级'));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.dragFrom(const Offset(3, 300), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(find.text('进入二级'), findsOneWidget);
      await tester.tap(find.text('进入二级'));
      await tester.pumpAndSettle();
      await tester.dragFrom(
        Offset(tester.getSize(find.byType(PlatformPageFrame)).width - 3, 300),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('进入二级'), findsOneWidget);
      await tester.tap(find.text('进入二级'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('进入二级'), findsOneWidget);
      expect(nav.currentState!.canPop(), true);
    },
  );

  testWidgets(
    'source detection keeps pending and unavailable rows truly disabled',
    (tester) async {
      final result = Completer<bool>();
      var selected = false;
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final choice = await showDialog<NeteaseTrackSource>(
                  context: context,
                  builder: (_) =>
                      Dialog(child: NeteaseSourcePicker(recording())),
                );
                selected = choice != null;
              },
              child: const Text('打开选源'),
            ),
          ),
        ),
        availability: (_, source, _, _) async =>
            source == NeteaseTrackSource.official ? result.future : false,
      );
      await tester.tap(find.text('打开选源'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final official = find.byKey(const ValueKey('song-source-official'));
      expect(tester.widget<ListTile>(official).enabled, false);
      expect(tester.widget<ListTile>(official).onTap, isNull);
      result.complete(true);
      await tester.pump();
      expect(tester.widget<ListTile>(official).enabled, true);
      final unavailable = tester.widget<ListTile>(
        find.byKey(const ValueKey('song-source-kuwo')),
      );
      expect(unavailable.enabled, false);
      expect(unavailable.onTap, isNull);
      await tester.tap(official);
      await tester.pumpAndSettle();
      expect(selected, true);
    },
  );
}
