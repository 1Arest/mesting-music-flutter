import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/settings/presentation/music_network_diagnostics_page.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/audio_downloads_page.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/app_update/app_update_providers.dart';
import 'package:mesting_music/features/app_update/domain/app_update_models.dart';
import 'package:mesting_music/features/settings/presentation/settings_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_login_options_page.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/lyrics/domain/lyrics_document.dart';
import 'package:mesting_music/features/lyrics/lyrics_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/platform_profile_provider.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_account_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_appearance.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_effects.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_effects_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_pages.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_player_navigation.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playlist_batch_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playlist_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playlist_tools.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_qr_login.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_qr_login_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_settings.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_signer_settings_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_welfare_page.dart';
import 'package:mesting_music/features/themes/music_theme_tokens.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/track_artwork.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'qishui_protocol_test.dart' show sodaSession, fixtureJson;
import 'qishui_qr_protocol_test.dart' show FixtureQrGateway;
import 'qishui_signer168_test.dart' show MemorySignerStore168, token168;
import 'qishui_ui168_test.dart' show Player168, song168, settle168;
import 'qishui_ui_test.dart' show FixtureAccount;
import 'qishui_signed_api167_test.dart' show account;
import 'support/release_147_qa.dart' show load147IconFonts;
import 'support/release_152_qa.dart' show theme152;

const capture172 = bool.fromEnvironment('CAPTURE_172');
const captureDirectory172 = String.fromEnvironment(
  'UI_CAPTURE_172_DIR',
  defaultValue: '.codex-artifacts/2026-11-06-release172/ui',
);
const boundary172 = ValueKey('qa172');
const list172 = QishuiPlaylist(
  'fixture-list',
  '夜晚的慢歌 · 界面测试',
  'assets/images/playlists/13416469337261709.jpeg',
  count: 8,
  kind: 1,
  ownerId: 'fixture',
  ownerName: '测试账号',
);
final songs172 = List.generate(
  8,
  (i) => i == 0
      ? song168
      : Track(
          id: 'qishui_172-$i',
          title: '第 $i 首测试歌曲',
          artist: '界面测试歌手',
          album: '测试专辑',
          duration: const Duration(minutes: 3),
          audioAsset: 'mesting-platform://qishui/$i',
          coverAsset: song168.coverAsset,
          lyricsAsset: '',
          source: TrackSource.qishui,
        ),
);

class AuditMusic172 extends QishuiRepository {
  AuditMusic172(super.api);
  bool activityFixture = false;
  // The production search now has an independent paged catalog adapter. Keep
  // this existing appearance fixture at the transport boundary it actually
  // calls, rather than accidentally dispatching an empty mock response.
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    bool get = false,
    bool write = false,
    Future<void>? abortTrigger,
  }) {
    if (path.startsWith('/luna/search/')) {
      return Future.value({
        'tracks': [
          for (final song in songs172)
            {
              'id': song.platformSongId,
              'name': song.title,
              'artists': [
                {'name': song.artist},
              ],
              'duration': song.duration.inMilliseconds,
            },
        ],
      });
    }
    return super.call(
      path,
      body: body,
      query: query,
      get: get,
      write: write,
      abortTrigger: abortTrigger,
    );
  }

  @override
  Future<Map<String, dynamic>> profile() async => {
    'my_info': {'nickname': '界面测试账号'},
  };
  @override
  Future<List<QishuiPlaylist>> discover({Future<void>? abortTrigger}) async => [
    list172,
    const QishuiPlaylist('two', '午后安静时光', '', count: 6),
  ];
  @override
  Future<List<QishuiPlaylist>> playlists({Future<void>? abortTrigger}) async =>
      [list172];
  @override
  Future<List<Track>> feed({
    QishuiFeedMode? mode,
    Future<void>? abortTrigger,
  }) async => songs172;
  @override
  Future<List<Track>> recent({Future<void>? abortTrigger}) async => songs172;
  @override
  Future<List<Track>> playlist(
    String id, {
    String cursor = '',
    Future<void>? abortTrigger,
  }) async => songs172;
  @override
  Future<List<Track>> search(
    String text, {
    String cursor = '',
    Future<void>? abortTrigger,
  }) async => songs172;
  @override
  Future<List<QishuiFeedMode>> modes({Future<void>? abortTrigger}) async => [
    const QishuiFeedMode('relax', '轻松听', {'preference_mode': 'relax'}),
  ];
  @override
  Future<Map<String, dynamic>> commerce({Future<void>? abortTrigger}) async => {
    'status_info': {
      'now_ts_ms': DateTime.utc(2026, 11, 7).millisecondsSinceEpoch,
    },
    'play_entitlements': {
      'expire_at': DateTime.utc(2026, 12, 6).millisecondsSinceEpoch,
    },
    'membership': {'is_membership': false},
    if (activityFixture)
      'activity_free_vip': {
        'start_time_sec':
            DateTime.utc(2026, 11, 6).millisecondsSinceEpoch ~/ 1000,
        'end_time_sec':
            DateTime.utc(2026, 11, 8).millisecondsSinceEpoch ~/ 1000,
      },
  };
}

class AuditPlayer172 extends Player168 {
  @override
  List<MediaItem> get upcomingQueue =>
      songs172.skip(1).map((t) => t.toMediaItem()).toList();
  @override
  PlaybackOrder get playbackOrder => const PlaybackOrder();
  @override
  Track? trackForId(String id) => songs172.where((t) => t.id == id).firstOrNull;
  @override
  bool isAutomaticallyQueued(String id) => false;
}

class AuditLibrary172 extends Fake implements LibraryRepository {}

class AuditAuth172 extends AuthController {
  @override
  Future<AuthSession?> build() async => null;
}

class AuditWebAccount172 extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => account().identity;
}

const version172 = AppVersionInfo(
  packageName: 'com.mesting.music',
  versionName: '1.0.72',
  versionCode: 93,
);

class AuditUpdate172 extends AppUpdateController {
  @override
  AppUpdateState build() => const AppUpdateState(currentVersion: version172);
}

void main() {
  setUp(MusicNetworkDiagnostics.shared.clear);
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    // Warm the local effect JSON outside a widget test's fake clock. Awaiting
    // a cached load created inside that clock from runAsync can deadlock QA.
    await loadQishuiEffects();
    if (capture172) {
      await load147IconFonts();
      for (final name in [
        'SodaQA172',
        'Microsoft YaHei',
        'Roboto',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        'Ahem',
        'Noto Sans SC',
      ]) {
        await (FontLoader(name)..addFont(
              File(
                'C:/Windows/Fonts/msyh.ttc',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
      }
    }
  });
  Future<(ProviderContainer, GoRouter)> mount(
    WidgetTester tester,
    String surface, {
    bool dark = false,
    bool narrow = false,
    bool web = false,
  }) async {
    tester.view.physicalSize = narrow
        ? const Size(320, 700)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    if (surface == 'diagnostics') {
      for (final outcome in [
        MusicNetworkOutcome.http,
        MusicNetworkOutcome.business,
      ]) {
        MusicNetworkDiagnostics.shared.record(
          platform: 'qishui',
          operation: MusicNetworkOperation.playbackUrl,
          outcome: outcome,
          phase: MusicDiagnosticPhase.responseValidate,
          status: 301,
        );
      }
    }
    final api = QishuiApi(MockClient((_) async => fixtureJson({})))
      ..configure(web ? account() : sodaSession());
    final music = AuditMusic172(api), player = AuditPlayer172();
    music.activityFixture = web;
    final store = MemorySignerStore168()
      ..value = QishuiSignerConfig.parse(
        'https://nas.example.test/qishui-signer/',
        token168,
        accountBoundSigning: true,
      );
    final downloads = AudioDownloadManager(
      client: MockClient((_) async => fixtureJson({})),
      currentOwner: () => api.session!.identity.ownerId,
      directory: () async => Directory.systemTemp,
      persist: (_) async {},
      publish: (_, _, _, _) async => 'file:///unused',
      resolve: (_) async => 'https://unused.example/audio',
      restored: const [],
    );
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authControllerProvider.overrideWith(AuditAuth172.new),
        appVersionProvider.overrideWith((_) async => version172),
        appUpdateControllerProvider.overrideWith(AuditUpdate172.new),
        platformAccountProvider.overrideWith(
          web ? AuditWebAccount172.new : FixtureAccount.new,
        ),
        qishuiNavigationProvider.overrideWithValue(true),
        qishuiApiProvider.overrideWithValue(api),
        qishuiRepositoryProvider.overrideWithValue(music),
        platformRewardAutomationProvider.overrideWith((_) {}),
        platformProfileProvider.overrideWith(
          (_) async => const PlatformProfileInfo('界面测试账号', ''),
        ),
        qishuiSignerSettingsStoreProvider.overrideWithValue(store),
        qishuiQrLoginFactoryProvider.overrideWithValue(
          () => QishuiQrLogin(FixtureQrGateway()),
        ),
        qishuiEffectsProvider.overrideWith((ref) {
          final effects = QishuiEffectCoordinator(
            send: (_) async => {},
            status: () async => {},
            current: () => true,
          );
          ref.onDispose(effects.dispose);
          return effects;
        }),
        audioDownloadManagerProvider.overrideWithValue(downloads),
        audioHandlerProvider.overrideWithValue(player),
        favoriteTrackIdsProvider.overrideWithValue(<String>{}),
        libraryRepositoryProvider.overrideWithValue(AuditLibrary172()),
        currentTrackProvider.overrideWithValue(song168),
        currentMediaItemProvider.overrideWith(
          (_) => Stream.value(song168.toMediaItem()),
        ),
        playbackStateProvider.overrideWith(
          (_) => Stream.value(PlaybackState()),
        ),
        positionProvider.overrideWith(
          (_) => Stream.value(const Duration(seconds: 20)),
        ),
        upcomingQueueProvider.overrideWith(
          (_) => Stream.value(player.upcomingQueue),
        ),
        playbackOrderProvider.overrideWith(
          (_) => Stream.value(const PlaybackOrder()),
        ),
        lyricsProvider.overrideWith(
          (_, _) async => LyricsDocument(
            isSynced: true,
            lines: List.generate(
              12,
              (i) => LyricsLine(
                time: Duration(seconds: i * 10),
                text: '让音乐慢慢经过这个夜晚 · 测试句 $i',
              ),
            ),
          ),
        ),
      ],
    );
    await c.read(platformAccountProvider.future);
    Widget page(String name) => switch (name) {
      'discover' => const QishuiRootPage(QishuiRoot.discover),
      'music' => const QishuiRootPage(QishuiRoot.music),
      'mine' => const QishuiRootPage(QishuiRoot.mine),
      'playlist' => const QishuiPlaylistPage(
        playlist: list172,
        owned: true,
        navigationIndex: 3,
      ),
      'batch' => QishuiPlaylistBatchPage(
        playlist: list172,
        tracks: songs172,
        owned: true,
      ),
      'add' => const QishuiPlaylistAddSongsPage(),
      'history' => QishuiTrackPage(title: '历史播放', load: (_) async => songs172),
      'search' => const QishuiSearchPage(),
      'account' => const QishuiAccountPage(),
      'signer' => const QishuiSignerSettingsPage(),
      'welfare' => const QishuiWelfarePage(),
      'effects' => const QishuiEffectsPage(),
      'downloads' => const AudioDownloadsPage(),
      'qr' => const QishuiQrLoginPage(),
      'settings' => const SettingsPage(),
      'diagnostics' => const MusicNetworkDiagnosticsPage(),
      'switch-platform' => const MusicPlatformSwitchPage(),
      'empty' => QishuiTrackPage(title: '暂无歌曲', load: (_) async => []),
      'error' => QishuiTrackPage(
        title: '读取失败',
        load: (_) async => throw const QishuiException(
          '汽水连接未完成，请重试',
          kind: QishuiFailureKind.connection,
        ),
      ),
      'loading' => QishuiTrackPage(
        title: '正在读取',
        load: (_) => Completer<List<Track>>().future,
      ),
      _ => const SizedBox(),
    };
    final router = GoRouter(
      initialLocation: surface == 'lyrics'
          ? '/music'
          : surface == 'mine'
          ? '/profile'
          : '/$surface',
      routes: [
        ShellRoute(
          builder: (_, state, child) => BetaMusicShell(
            location: state.uri.toString(),
            navigationOwner:
                {
                  '/profile',
                  '/playlist',
                  '/history',
                  '/account',
                  '/signer',
                  '/welfare',
                  '/effects',
                  '/settings',
                }.contains(state.uri.path)
                ? 3
                : null,
            child: child,
          ),
          routes: [
            for (final name in [
              'discover',
              'music',
              'mine',
              'playlist',
              'history',
              'search',
              'account',
              'signer',
              'welfare',
              'effects',
              'empty',
              'error',
              'loading',
              'settings',
              'diagnostics',
            ])
              GoRoute(
                path: name == 'mine' ? '/profile' : '/$name',
                builder: (_, _) => page(name),
              ),
          ],
        ),
        for (final name in [
          'batch',
          'add',
          'downloads',
          'qr',
          'switch-platform',
        ])
          GoRoute(path: '/$name', builder: (_, _) => page(name)),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      c.dispose();
      api.dispose();
      downloads.dispose();
    });
    var theme = theme152(dark);
    if (capture172) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'SodaQA172'),
        // A modal captures Material Theme, while CupertinoButton installs its
        // own text style. Provide the same host-only CJK font there as well;
        // default device fonts are intentionally unavailable in widget tests.
        cupertinoOverrideTheme: theme.cupertinoOverrideTheme?.copyWith(
          textTheme: theme.cupertinoOverrideTheme?.textTheme?.copyWith(
            textStyle: theme.cupertinoOverrideTheme?.textTheme?.textStyle
                .copyWith(fontFamily: 'SodaQA172'),
            actionTextStyle: theme
                .cupertinoOverrideTheme
                ?.textTheme
                ?.actionTextStyle
                .copyWith(fontFamily: 'SodaQA172'),
          ),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
            fontFamily: 'SodaQA172',
          ),
          subtitleTextStyle: theme.listTileTheme.subtitleTextStyle?.copyWith(
            fontFamily: 'SodaQA172',
          ),
        ),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: LiquidGlassWidgets.wrap(
          adaptiveQuality: false,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(narrow ? 1.4 : 1)),
              child: RepaintBoundary(key: boundary172, child: child!),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        AssetImage(song168.coverAsset),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await settle168(tester);
    if (surface == 'lyrics') {
      c.read(qishuiMusicLyricsProvider.notifier).showLyrics();
      await settle168(tester);
    }
    return (c, router);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!capture172) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle168(tester);
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.byKey(boundary172))
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captureDirectory172/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final surface in [
      'discover',
      'music',
      'lyrics',
      'mine',
      'playlist',
      'batch',
      'add',
      'history',
      'search',
      'account',
      'signer',
      'welfare',
      'effects',
      'downloads',
      'qr',
      'empty',
      'error',
      'loading',
      'settings',
      'diagnostics',
      'switch-platform',
    ]) {
      testWidgets('$surface follows effective appearance dark=$dark', (
        tester,
      ) async {
        await mount(tester, surface, dark: dark);
        final expected = dark || surface == 'lyrics'
            ? Brightness.dark
            : Brightness.light;
        if (find.byType(BetaMusicBottomBar).evaluate().isNotEmpty) {
          expect(
            Theme.of(
              tester.element(find.byType(BetaMusicBottomBar).first),
            ).brightness,
            expected,
          );
        }
        if (surface == 'playlist') {
          expect(find.byType(TrackArtwork), findsWidgets);
        }
        if (surface == 'signer') {
          expect(
            find.byKey(const ValueKey('qishui-account-signing')),
            findsOneWidget,
          );
        }
        if (surface == 'welfare') {
          expect(find.textContaining('已同步免费听权益'), findsOneWidget);
        }
        if (surface == 'diagnostics') {
          expect(find.textContaining('HTTP 301'), findsOneWidget);
          expect(find.textContaining('业务码 301'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await shot(tester, '$surface-${dark ? 'dark' : 'light'}');
      });
    }
    for (final surface in ['lyrics', 'signer', 'playlist', 'qr', 'welfare']) {
      testWidgets('$surface narrow large text dark=$dark', (tester) async {
        await mount(tester, surface, dark: dark, narrow: true);
        expect(tester.takeException(), isNull);
        await shot(tester, '$surface-${dark ? 'dark' : 'light'}-large');
      });
    }
  }
  testWidgets(
    'lyrics coordinates chrome and restores the application theme on exit',
    (tester) async {
      final (c, router) = await mount(tester, 'lyrics');
      expect(
        Theme.of(tester.element(find.byType(BetaMusicBottomBar))).brightness,
        Brightness.dark,
      );
      final button = find.byKey(ValueKey('song-actions-${song168.id}'));
      expect(Theme.of(tester.element(button)).brightness, Brightness.dark);
      c.read(qishuiMusicLyricsProvider.notifier).showCover();
      await settle168(tester);
      expect(
        Theme.of(tester.element(find.byType(BetaMusicBottomBar))).brightness,
        Brightness.light,
      );
      c.read(qishuiMusicLyricsProvider.notifier).showLyrics();
      await settle168(tester);
      router.go('/profile');
      await settle168(tester);
      expect(
        Theme.of(tester.element(find.byType(BetaMusicBottomBar))).brightness,
        Brightness.light,
      );
      expect(c.read(qishuiMusicLyricsProvider), true);
    },
  );
  for (final dark in [false, true]) {
    for (final popup in ['song-menu', 'queue', 'privacy', 'rename', 'remove']) {
      testWidgets('$popup inherits its visible page theme dark=$dark', (
        tester,
      ) async {
        final lyrics = popup == 'song-menu' || popup == 'queue';
        await mount(tester, lyrics ? 'lyrics' : 'playlist', dark: dark);
        if (popup == 'song-menu') {
          await tester.tap(find.byKey(ValueKey('song-actions-${song168.id}')));
        } else if (popup == 'queue') {
          await tester.tap(find.bySemanticsLabel('待播列表').first);
        } else {
          final context = tester.element(find.byType(QishuiPlaylistPage));
          if (popup == 'privacy') {
            unawaited(showQishuiPlaylistPrivacy(context, false));
          }
          if (popup == 'rename') unawaited(askQishuiPlaylistName(context));
          if (popup == 'remove') {
            unawaited(confirmQishuiPlaylistRemoval(context, 2));
          }
        }
        await settle168(tester);
        final overlay = popup == 'rename' || popup == 'remove'
            ? find.byType(AlertDialog)
            : find.byType(BottomSheet);
        expect(overlay, findsOneWidget);
        expect(
          Theme.of(tester.element(overlay)).brightness,
          dark || lyrics ? Brightness.dark : Brightness.light,
        );
        expect(tester.takeException(), isNull);
        await shot(tester, '$popup-${dark ? 'dark' : 'light'}');
      });
    }
    testWidgets('signer opt-in and HTTP validation stay readable dark=$dark', (
      tester,
    ) async {
      await mount(tester, 'signer', dark: dark, narrow: true);
      final switchFinder = find.byKey(const ValueKey('qishui-account-signing'));
      await tester.ensureVisible(switchFinder);
      await settle168(tester);
      expect(tester.widget<SwitchListTile>(switchFinder).value, true);
      await shot(tester, 'signer-opt-in-${dark ? 'dark' : 'light'}');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('qishui-signer-address')),
        -300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await settle168(tester);
      await tester.enterText(
        find.byKey(const ValueKey('qishui-signer-address')),
        'http://nas.example.test/',
      );
      final save = find.byKey(const ValueKey('qishui-signer-save'));
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await settle168(tester);
      await tester.tap(save);
      await settle168(tester);
      expect(find.textContaining('仅支持自建 HTTPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'signer-invalid-http-${dark ? 'dark' : 'light'}');
    });
    testWidgets('Qishui search results remain readable dark=$dark', (
      tester,
    ) async {
      await mount(tester, 'search', dark: dark);
      await tester.enterText(find.byType(TextField).first, '测试');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle168(tester);
      expect(find.text(song168.title), findsWidgets);
      expect(tester.takeException(), isNull);
      await shot(tester, 'search-results-${dark ? 'dark' : 'light'}');
    });
    for (final tab in ['下载', '历史播放']) {
      testWidgets('Mine $tab follows appearance dark=$dark', (tester) async {
        await mount(tester, 'mine', dark: dark);
        await tester.ensureVisible(find.text(tab).last);
        await tester.tap(find.text(tab).last);
        await settle168(tester);
        expect(tester.takeException(), isNull);
        await shot(
          tester,
          'mine-${tab == '下载' ? 'downloads' : 'history'}-${dark ? 'dark' : 'light'}',
        );
      });
    }
  }
  for (final dark in [false, true]) {
    testWidgets(
      'QR benefits read never enables unsupported activity write dark=$dark',
      (tester) async {
        final (c, _) = await mount(
          tester,
          'welfare',
          dark: dark,
          narrow: true,
          web: true,
        );
        expect(
          QishuiWelfareStatus(
            await c.read(qishuiRepositoryProvider).commerce(),
          ).claimable,
          true,
        );
        final button = find.ancestor(
          of: find.text('请在官版App领取'),
          matching: find.byType(BetaGlassButton),
        );
        expect(tester.widget<BetaGlassButton>(button).onPressed, isNull);
        expect(find.textContaining('已同步免费听权益'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'welfare-web-read-only-${dark ? 'dark' : 'light'}');
      },
    );
  }
  test(
    'artwork theme replaces light component styles while retaining font and unrelated state',
    () {
      final base = theme152(false).copyWith(
        textTheme: theme152(false).textTheme.apply(fontFamily: 'fixture172'),
      );
      final dark = qishuiArtworkTheme(base);
      expect(dark.brightness, Brightness.dark);
      expect(
        dark.extension<MusicThemeTokens>()!.textPrimary,
        isNot(base.extension<MusicThemeTokens>()!.textPrimary),
      );
      expect(dark.textTheme.bodyMedium!.fontFamily, 'fixture172');
      expect(dark.listTileTheme.titleTextStyle!.fontFamily, 'fixture172');
      expect(
        dark.cupertinoOverrideTheme!.textTheme!.textStyle.fontFamily,
        'fixture172',
      );
    },
  );
}
