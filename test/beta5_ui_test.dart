import 'package:mesting_music/shared/widgets/beta_page_motion.dart';
import 'package:mesting_music/features/player/presentation/open_now_playing.dart';
import 'package:mesting_music/features/music_platform/presentation/song_actions_sheet.dart';
import 'package:mesting_music/shared/widgets/beta_glass_action.dart';
import 'package:mesting_music/features/experience/presentation/player_toolbar_glyphs.dart';
import 'package:mesting_music/features/experience/presentation/immersive_lyrics.dart';
import 'package:mesting_music/core/audio/audio_output_controller.dart';
import 'package:mesting_music/features/experience/presentation/music_home_catalogues.dart';
import 'package:mesting_music/features/profile/presentation/profile_page.dart';
import 'package:mesting_music/features/experience/presentation/player_queue_panel.dart';
import 'package:mesting_music/features/player/presentation/shinchan_progress_walker.dart';
import 'package:mesting_music/shared/widgets/beta_text_editing.dart';
import 'package:mesting_music/shared/widgets/song_list_tools.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_profile_edit_page.dart';
import 'package:mesting_music/features/experience/presentation/player_chrome_reveal.dart';
import 'package:mesting_music/features/auth/beta_entry_flow.dart';
import 'package:mesting_music/features/auth/presentation/beta_entry_coordinator.dart';
import 'package:mesting_music/features/auth/presentation/beta_onboarding_page.dart';
import 'package:mesting_music/app/system_back_coordinator.dart';
import 'package:mesting_music/features/music_platform/data/platform_category_search.dart';
import 'package:mesting_music/features/settings/presentation/settings_page.dart';
import 'package:mesting_music/features/settings/presentation/haptic_settings_page.dart';
import 'package:mesting_music/features/music_platform/platform_category_search_providers.dart';
import 'package:mesting_music/features/search/presentation/beta_category_search_results.dart';
import 'package:mesting_music/features/library/presentation/library_access.dart';
import 'dart:async';
import 'package:mesting_music/features/music_platform/netease/netease_rewards_provider.dart';
import 'package:mesting_music/app/router/app_router.dart' as production;
import 'package:mesting_music/features/experience/presentation/floating_playback_pill.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comment_composer.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/music_landing_page.dart';
import 'package:mesting_music/features/experience/presentation/music_library_page.dart';
import 'package:mesting_music/features/experience/presentation/beta_now_playing_page.dart';
import 'package:mesting_music/features/experience/presentation/apple_player_controls.dart';
import 'package:mesting_music/features/experience/presentation/player_content_transition.dart';
import 'package:mesting_music/core/audio/media_volume_controller.dart';
import 'package:mesting_music/features/music_platform/platform_recommendation_providers.dart';
import 'package:mesting_music/features/music_platform/data/platform_recommendations.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_search_landing.dart';
import 'package:mesting_music/features/music_platform/data/platform_explore.dart';
import 'package:mesting_music/features/search/presentation/music_search_page.dart';
import 'package:mesting_music/features/search/presentation/apple_search_results.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/music_platform/cross_platform_music_scope.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';
import 'package:mesting_music/shared/widgets/music_notice.dart';
import 'package:mesting_music/shared/widgets/track_artwork.dart';
import 'package:mesting_music/features/experience/presentation/listening_replay_page.dart';
import 'package:mesting_music/features/player/presentation/music_shell.dart';
import 'package:mesting_music/features/player/player_visual_style.dart';
import 'package:mesting_music/features/player/presentation/now_playing_page.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/features/lyrics/domain/lyrics_document.dart';
import 'package:mesting_music/features/lyrics/lyrics_providers.dart';
import 'package:mesting_music/features/playlists/presentation/playlist_editor_dialog.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoTextField;
import 'package:mesting_music/features/themes/theme_gallery_page.dart';
import 'package:mesting_music/features/themes/startup_style_picker.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/pump_artwork_ready.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/themes/theme_controller.dart';

import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_library_repository.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_account_page.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_comments_page.dart';
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
  coverAsset: 'assets/images/playlists/13416469337261709.jpeg',
  lyricsAsset: '',
);

final _qaRecordingProvider = NotifierProvider<_QARecording, Track>(
  _QARecording.new,
);

class _QARecording extends Notifier<Track> {
  @override
  Track build() => _track;
  void select(Track track) => state = track;
}

/// Local UI catalogue fixtures; real wire parsing is covered separately.
class _CategoryFixtures extends PlatformCategorySearchRepository {
  _CategoryFixtures(super.api);
  @override
  Future<PlatformCategoryPage> search(
    String query,
    PlatformSearchKind kind, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async => PlatformCategoryPage(
    [
      for (var i = 0; i < 4; i++)
        PlatformSearchHit(
          kind: kind,
          id: '$i',
          title: kind == PlatformSearchKind.albums
              ? ['意外', '绅士', '初学者', '天外来物'][i]
              : kind == PlatformSearchKind.artists
              ? ['薛之谦', '薛之谦(2)', '薛之谦fm', '薛之谦jokx'][i]
              : kind == PlatformSearchKind.playlists
              ? ['薛之谦必听热歌', '演唱会曲目', '夜深别听薛之谦', '精选伤感歌单'][i]
              : '演员',
          subtitle: '薛之谦',
          cover: _track.coverAsset,
          globalId: 'collection-real-$i',
          count: 139 + i,
          track: kind == PlatformSearchKind.lyrics ? _track : null,
          lyric: kind == PlatformSearchKind.lyrics
              ? '薛之谦 - 演员  词：薛之谦  曲：薛之谦'
              : '',
        ),
    ],
    4,
    false,
  );
}

class _Output extends AudioOutputController {
  @override
  AudioOutput build() => const AudioOutput(name: '本机扬声器', available: true);
  void connect(String name) =>
      state = AudioOutput(name: name, headphones: true, available: true);
  void disconnect() => state = const AudioOutput(available: true);
  @override
  Future<void> choose() async {}
}

class _Volume extends MediaVolumeController {
  @override
  MediaVolumeState build() =>
      const MediaVolumeState(value: .55, available: true);
  @override
  Future<void> setVolume(double value) async {
    state = MediaVolumeState(value: value, available: true);
  }
}

class _Handler extends MestingAudioHandler {
  _Handler() : super(tracks: []);
  final presentationCommands = StreamController<String>.broadcast(sync: true);
  @override
  Stream<String> get userCommandStream => presentationCommands.stream;
  @override
  Future<void> skipToNext() async => presentationCommands.add('skipNext');
  @override
  Future<void> skipToPrevious() async =>
      presentationCommands.add('skipPrevious');
  int toggles = 0;
  @override
  Future<void> togglePlayPause() async {
    toggles++;
  }
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

/// Navigation retains the production fusion assembly with a deterministic
/// empty second source. It must not read a real keystore or public network.
class _EmptySupplementarySongs extends NeteaseMusicRepository {
  _EmptySupplementarySongs()
    : super(
        NeteaseApi(
          MockClient(
            (_) async =>
                throw StateError('navigation fixture has no NetEase transport'),
          ),
        ),
      );
  @override
  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abort,
  }) async => const PlatformSearchPage([], 0, false);
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
    await LiquidGlassWidgets.initialize();
    // Optional local QA font, never bundled in the application/source assets.
    if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        final loader = FontLoader('BetaQACJK')
          ..addFont(
            font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
        // Cupertino widgets choose the iOS font family inside GlassScaffold.
        // Supply its CJK test substitute as well; device builds use system fonts.
        for (final family in [
          'Roboto', // Material chip labels select this family directly.
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
        ]) {
          await (FontLoader(family)..addFont(
                font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
              ))
              .load();
        }
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File.fromUri(
              File(
                Platform.resolvedExecutable,
              ).uri.resolve('../../material_fonts/MaterialIcons-Regular.otf'),
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await icons.load();
        final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
          ..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          );
        await cupertino.load();
        fontsLoaded = true;
      }
    }
  });
  late ProviderContainer container;
  late AppDatabase database;
  late MusicPlatformApi api;
  late LibraryRepository library;
  var qaPreset = musicThemePresetById('classic');
  late bool metadataReady;
  late List<String> paths;
  Future<void> prepare({
    bool richHome = false,
    int queueCount = 2,
    bool guest = false,
    bool standardOnly = false,
    bool qualityUnknown = false,
    bool playing = false,
    Stream<PlaybackState>? playbackEvents,
    Stream<Duration>? positionEvents,
    Duration position = const Duration(seconds: 37),
    Future<List<PlatformHotSearchBoard>> Function()? hotSearch,
  }) async {
    metadataReady = false;
    paths = [];
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    api = MusicPlatformApi(
      server: _Server(),
      client: MockClient((request) async {
        paths.add(request.url.path);
        final Object data = switch (request.url.path) {
          '/user/detail' => {'nickname': '音乐旅行者'},
          '/audio' =>
            (!qualityUnknown &&
                    (metadataReady ||
                        request.url.queryParameters['hash'] == 'HASH'))
                ? {
                    'audio_info': [
                      {
                        'Audioid': 12345,
                        'hash': 'sd',
                        if (!standardOnly) 'hash_320': 'hq',
                        if (!standardOnly) 'hash_flac': 'sq',
                        if (!standardOnly) 'hash_high': 'hires',
                      },
                    ],
                  }
                : {},
          // The picker now verifies entitlement and delivered quality instead
          // of treating a metadata hash as a playable tier. This synthetic URL
          // is consumed only by the mocked resolver, never by a real network.
          '/song/url' => {
            'url':
                'https://quality-fixture.invalid/${request.url.queryParameters['quality']}',
            'quality': request.url.queryParameters['quality'],
            'bitrate': switch (request.url.queryParameters['quality']) {
              '128' => 128000,
              '320' => 320000,
              _ => 960000,
            },
            'fileSize': 4000000,
          },
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
          '/scene/module' => {
            'content': [
              {
                'module_type': 2,
                'module_id': 'music-fixture',
                'extra': [
                  {'tag_id': 'scene-music', 'content_type': 6},
                ],
              },
            ],
          },
          _ => {
            'info': [
              for (var i = 0; i < 3; i++)
                {
                  'hash': 'HASH$i',
                  'songname': ['认真的雪', '演员', '天外来物'][i],
                  'singername': '薛之谦',
                  'album_audio_id': 12345 + i,
                  'sizable_cover':
                      'assets/images/playlists/13416469337261709.jpeg',
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
    library = guest
        ? LibraryRepository(database, ownerId: legacyLibraryOwnerId)
        : PlatformLibraryRepository(database, api: api, identity: _identity);
    await database.recordPlayback(
      'kugou:7',
      _track,
      const Duration(minutes: 32),
    );
    container = ProviderContainer(
      overrides: [
        // Navigation acceptance has no reward account or platform keystore.
        // The dedicated reward tests exercise automation through mock services.
        neteaseRewardServiceProvider.overrideWith((ref) async => null),
        effectiveMusicThemeProvider.overrideWith((ref) => qaPreset),
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),

        platformSessionStoreProvider.overrideWithValue(
          _Store(guest ? null : _identity),
        ),
        musicPlatformApiProvider.overrideWithValue(api),
        supplementaryNeteaseMusicProvider.overrideWith(
          (_) async => _EmptySupplementarySongs(),
        ),
        platformCategorySearchRepositoryProvider.overrideWithValue(
          _CategoryFixtures(api),
        ),
        libraryRepositoryProvider.overrideWithValue(library),
        audioHandlerProvider.overrideWithValue(_Handler()),
        currentMediaItemProvider.overrideWith(
          (ref) => Stream.value(_track.toMediaItem()),
        ),
        currentTrackProvider.overrideWith(
          (ref) => ref.watch(_qaRecordingProvider),
        ),
        mediaVolumeProvider.overrideWith(_Volume.new),
        audioOutputProvider.overrideWith(_Output.new),
        upcomingQueueProvider.overrideWith(
          (ref) => Stream.value([
            MediaItem(
              id: 'pending-a',
              title: '下一段旋律',
              artist: _track.artist,
              artUri: Uri.parse(_track.coverAsset),
            ),
            MediaItem(
              id: 'pending-b',
              title: '留给夜晚的歌',
              artist: _track.artist,
              artUri: Uri.parse(_track.coverAsset),
            ),
            for (var i = 2; i < queueCount; i++)
              MediaItem(
                id: 'pending-$i',
                title: '待播歌曲 ${i + 1}',
                artist: _track.artist,
                artUri: Uri.parse(_track.coverAsset),
              ),
          ]),
        ),
        // These are parsed UI fixtures, not wire payloads. Real platform cover
        // parsing rejects asset filenames and is covered in beta6_platform_test.
        platformFmProvider.overrideWith((ref) async => [_track]),
        platformHotSearchProvider.overrideWith(
          (ref) async => hotSearch != null
              ? hotSearch()
              : const [
                  PlatformHotSearchBoard('热搜榜', ['认真的雪', '平凡之路', '音乐让我们相遇']),
                ],
        ),
        platformExploreProvider.overrideWith(
          (ref, kind) async => [
            if (richHome) ...[
              for (var index = 0; index < 3; index++)
                PlatformExploreItem(
                  id: '${kind.name}-$index',
                  title: switch (kind) {
                    PlatformExploreKind.rank => [
                      '酷狗飙升榜',
                      '酷狗热歌榜',
                      '酷狗TOP500',
                    ][index],
                    PlatformExploreKind.album => [
                      '此刻，慢下来',
                      '耳边的风',
                      '周末唱片店',
                    ][index],
                    PlatformExploreKind.theme => [
                      '华语流行',
                      '独立与民谣',
                      '城市夜曲',
                    ][index],
                    PlatformExploreKind.scene => [
                      '专注工作',
                      '运动时刻',
                      '夜晚放松',
                    ][index],
                    PlatformExploreKind.playlist => [
                      '温柔华语',
                      '日落与旋律',
                      '周末的耳机',
                    ][index],
                  },
                  cover:
                      'assets/images/playlists/${['13416469337261709', '13416469354055551', '13416469356600254'][index]}.jpeg',
                  kind: kind,
                ),
            ] else
              PlatformExploreItem(
                id: '1',
                title: kind.label,
                cover: _track.coverAsset,
                kind: kind,
              ),
          ],
        ),
        platformDailyProvider.overrideWith((ref) async => [_track]),
        platformNewSongsProvider.overrideWith((ref) async => [_track]),
        platformDiscoveryProvider.overrideWith((ref) async => [_track]),
        positionProvider.overrideWith(
          (ref) => positionEvents ?? Stream.value(position),
        ),
        durationProvider.overrideWith((ref) => Stream.value(_track.duration)),
        lyricsProvider.overrideWith(
          (ref, asset) async => const LyricsDocument(
            isSynced: true,
            lines: [
              LyricsLine(time: Duration.zero, text: '每一段旋律'),
              LyricsLine(time: Duration(seconds: 20), text: '都留下自己的足迹'),
              LyricsLine(time: Duration(seconds: 40), text: '在音乐里继续向前'),
            ],
          ),
        ),
        playbackStateProvider.overrideWith(
          (ref) =>
              playbackEvents ??
              Stream.value(
                PlaybackState(
                  playing: playing,
                  processingState: AudioProcessingState.ready,
                ),
              ),
        ),
      ],
    );
    await container.read(platformAccountProvider.future);
  }

  Future<void> disposeFixture(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await (container.read(audioHandlerProvider) as _Handler)
        .presentationCommands
        .close();
    container.dispose();
    library.dispose();
    // Drift removes cancelled watched queries on a zero-duration timer.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Flutter runs addTearDown on the real loop after draining fake-time streams.
  }

  Future<void> captureScreenshot(
    WidgetTester tester,
    String capture, {
    Duration settle = const Duration(milliseconds: 500),
  }) async {
    if (const bool.fromEnvironment('EXPORT_BETA_SCREENSHOTS')) {
      // Asset decoding uses real I/O. Wait for all visible artwork before QA.
      final context = tester.element(find.byType(MaterialApp).first);
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      await tester.runAsync(() async {
        await Future.wait(
          images.map((image) => precacheImage(image.image, context)),
        );
      });
      await tester.pump(settle);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('beta5-capture')),
      );
      await tester.runAsync(() async {
        final picture = await boundary.toImage();
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(
          const String.fromEnvironment('BETA_SCREENSHOT_DIR'),
        );
        await directory.create(recursive: true);
        await File(
          '${directory.path}/${capture.replaceFirst('beta7-', 'beta9-').replaceFirst('beta8-', 'beta9-')}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        picture.dispose();
      });
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
    String? capture,
    bool shell = false,
    String location = '/music/recommend',
    double scale = 1,
  }) async {
    final theme = buildMestingTheme(
      musicThemePresetById(dark ? 'classic-dark' : 'classic'),
    );
    qaPreset = musicThemePresetById(dark ? 'classic-dark' : 'classic');
    container.invalidate(effectiveMusicThemeProvider);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        for (final path in [
          '/music',
          '/music/recommend',
          '/music/library',
          '/profile',
          '/music/search',
          '/music/settings',
        ])
          GoRoute(
            path: path,
            builder: (context, state) => KeyedSubtree(
              key: ValueKey('$capture-$scale-$dark'),
              child: shell
                  ? MusicShell(location: state.uri.toString(), child: page)
                  : Scaffold(
                      backgroundColor: theme.colorScheme.surface,
                      body: page,
                    ),
            ),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: const ValueKey('beta5-capture'),
          child: LiquidGlassWidgets.wrap(
            brightnessResolver: Theme.maybeBrightnessOf,
            adaptiveQuality: false,
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: fontsLoaded
                  ? theme.copyWith(
                      textTheme: theme.textTheme.apply(fontFamily: 'BetaQACJK'),
                      chipTheme: theme.chipTheme.copyWith(
                        labelStyle:
                            (theme.chipTheme.labelStyle ?? const TextStyle())
                                .copyWith(fontFamily: 'BetaQACJK'),
                      ),
                      listTileTheme: theme.listTileTheme.copyWith(
                        subtitleTextStyle:
                            (theme.listTileTheme.subtitleTextStyle ??
                                    const TextStyle())
                                .copyWith(fontFamily: 'BetaQACJK'),
                      ),
                    )
                  : theme,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
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
    await pumpArtworkReady(tester);
    expect(tester.takeException(), null);
    if (capture != null) await captureScreenshot(tester, capture);
  }

  void viewport(WidgetTester tester, [Size size = const Size(390, 844)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openQuality(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.tap(find.text('音质选择'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'music refinement home shelves and single appearance entry',
    (tester) async {
      viewport(tester);
      await prepare(richHome: true);
      var fixtureDisposed = false;
      addTearDown(() {
        if (!fixtureDisposed) {
          container.dispose();
          library.dispose();
        }
      });
      for (final dark in [false, true]) {
        final suffix = dark ? 'dark' : 'light';
        await pump(
          tester,
          const MusicLandingPage(),
          shell: true,
          dark: dark,
          capture: 'refinement-home-$suffix-top',
        );
        final scrollable = find
            .descendant(
              of: find.byType(MusicLandingPage),
              matching: find.byType(Scrollable),
            )
            .first;
        for (final title in [
          '推荐歌单',
          '猜你喜欢的歌',
          '热门榜单',
          '新歌首发',
          '新碟上架',
          '主题歌单',
          '场景音乐',
        ]) {
          // Each entering batch waits for its real artwork decode. A single
          // fake-time scrollUntilVisible loop cannot cross that frontier.
          for (
            var step = 0;
            step < 40 && find.text(title).hitTestable().evaluate().isEmpty;
            step++
          ) {
            await tester.drag(scrollable, const Offset(0, -330));
            await pumpArtworkReady(tester);
          }
          expect(find.text(title).hitTestable(), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 450));
          expect(tester.takeException(), isNull);
          if (title == '热门榜单' || title == '场景音乐') {
            await captureScreenshot(
              tester,
              'refinement-home-$suffix-${title == '热门榜单' ? 'ranks' : 'scenes'}',
            );
          }
        }
        // The scene action opens real catalogue tracks, not an inert chip.
        await tester.ensureVisible(
          find.byKey(const ValueKey('home-scene-scene-0')),
        );
        await tester.pump(const Duration(milliseconds: 450));
        await tester.tap(find.byKey(const ValueKey('home-scene-scene-0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.text('专注工作'), findsWidgets);
        expect(paths, contains('/scene/module'));
        expect(paths, contains('/scene/audio/list'));
        await pump(
          tester,
          const ProfilePage(),
          shell: true,
          location: '/profile',
          dark: dark,
          capture: 'refinement-profile-$suffix',
        );
        // Beta's shared My page exposes Settings in its header; the old
        // bottom "应用" section belongs to the retired profile composition.
        expect(find.text('装扮'), findsNothing);
        expect(find.bySemanticsLabel('设置'), findsOneWidget);
        await captureScreenshot(tester, 'refinement-profile-$suffix-settings');
        await pump(
          tester,
          const SettingsPage(),
          location: '/music/settings',
          dark: dark,
        );
        expect(find.text('装扮'), findsOneWidget);
      }
      viewport(tester, const Size(320, 780));
      await pump(
        tester,
        const MusicHomeCatalogueShelf(PlatformExploreKind.album),
        scale: 1.5,
        capture: 'refinement-albums-narrow-large',
      );
      expect(find.text('此刻，慢下来'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFixture(tester);
      fixtureDisposed = true;
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'music refinement toolbar and catalogue details remain connected',
    (tester) async {
      viewport(tester);
      await prepare(richHome: true, playing: true);
      var fixtureDisposed = false;
      addTearDown(() {
        if (!fixtureDisposed) {
          container.dispose();
          library.dispose();
        }
      });
      (container.read(audioOutputProvider.notifier) as _Output).connect(
        'vivo TWS 5',
      );
      await pump(
        tester,
        const BetaNowPlayingPage(),
        dark: true,
        capture: 'refinement-player-headphones',
      );
      expect(
        tester
            .widget<PlayerToolbarGlyph>(
              find.byKey(const ValueKey('player-output-glyph')),
            )
            .headphones,
        isTrue,
      );
      viewport(tester, const Size(320, 780));
      await pump(
        tester,
        const MusicHomeCataloguePage(kind: PlatformExploreKind.album),
        scale: 1.5,
        capture: 'refinement-catalogue-narrow-large',
      );
      expect(find.text('此刻，慢下来'), findsOneWidget);
      await tester.tap(find.text('此刻，慢下来'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(paths, contains('/album/songs'));
      expect(tester.takeException(), isNull);
      await disposeFixture(tester);
      fixtureDisposed = true;
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta5 cover-led pages render in both themes and wide layouts',
    (tester) async {
      viewport(tester);
      await prepare();
      for (final dark in [false, true]) {
        final suffix = dark ? 'dark' : 'light';
        await pump(
          tester,
          const MusicLandingPage(),
          shell: true,
          dark: dark,
          capture: 'home-$suffix',
        );
        expect(find.text('为你精选'), findsOneWidget);
        expect(find.byType(BetaMusicBottomBar), findsOneWidget);
        await pump(
          tester,
          const MusicLandingPage(discovery: true),
          shell: true,
          location: '/music',
          dark: dark,
          capture: 'discover-$suffix',
        );
        await pump(
          tester,
          const MusicLibraryPage(),
          shell: true,
          location: '/music/library',
          dark: dark,
          capture: 'library-$suffix',
        );
        await pump(
          tester,
          const MusicLibraryPage(view: 'favorites'),
          shell: true,
          location: '/music/library',
          dark: dark,
          capture: 'favorites-$suffix',
        );
        await pump(
          tester,
          const ListeningReplayPage(),
          shell: true,
          location: '/music/library',
          dark: dark,
          capture: 'replay-$suffix',
        );
        expect(
          find.text('${DateTime.now().month} 月').hitTestable(),
          findsOneWidget,
        );
        await pump(
          tester,
          const BetaNowPlayingPage(key: ValueKey('qa-cover')),
          dark: dark,
          capture: 'player-$suffix',
        );
        await pump(
          tester,
          const BetaNowPlayingPage(
            lyricsInitially: true,
            key: ValueKey('qa-lyrics'),
          ),
          dark: dark,
          capture: 'lyrics-$suffix',
        );
        await pump(
          tester,
          const PlatformAccountPage(),
          dark: dark,
          capture: 'account-$suffix',
        );
        await pump(
          tester,
          const PlatformProfile(),
          shell: true,
          location: '/profile',
          dark: dark,
          capture: 'profile-$suffix',
        );
        await pump(
          tester,
          const SettingsPage(),
          shell: true,
          location: '/music/settings',
          dark: dark,
          capture: 'settings-$suffix',
        );
        // New settings entries can place licenses below the first viewport.
        // Verify the destination by scrolling its real content into view.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('settings-open-source')),
          240,
          scrollable: find
              .descendant(
                of: find.byType(SettingsPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          find.byKey(const ValueKey('settings-open-source')),
          findsOneWidget,
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
          const PlatformCloudPlaylistPage(id: 'kg:22'),
          dark: dark,
          capture: 'playlist-$suffix',
        );
      }
      tester.view.physicalSize = const Size(1024, 768);
      await pump(
        tester,
        const MusicLandingPage(),
        shell: true,
        capture: 'home-wide',
      );
      await pump(
        tester,
        const MusicLibraryPage(),
        shell: true,
        location: '/music/library',
        capture: 'library-wide',
      );
      await pump(
        tester,
        const BetaNowPlayingPage(lyricsInitially: true),
        capture: 'lyrics-wide',
      );
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'small windows and larger text retain transport and editor actions',
    (tester) async {
      viewport(tester, const Size(320, 640));
      await prepare(guest: true);
      await pump(
        tester,
        const BetaNowPlayingPage(key: ValueKey('qa-cover')),
        scale: 1.6,
        capture: 'player-accessibility',
      );
      await pump(
        tester,
        const MusicLibraryPage(),
        shell: true,
        scale: 1.6,
        location: '/music/library',
        capture: 'library-accessibility',
      );
      await pump(tester, const PlatformAccountPage(), capture: 'login-narrow');
      await tester.showKeyboard(find.byType(TextField).first);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      expect(tester.takeException(), null);
      tester.view.resetViewInsets();
      await pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showPlaylistEditorDialog(context, initialName: '慢慢听'),
              child: const Text('编辑歌单'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑歌单'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('保存歌单'), findsOneWidget);
      expect(tester.takeException(), null);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'playlist editor keeps fixed confirmation and cover controls',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showPlaylistEditorDialog(context, initialName: '慢慢听，慢慢喜欢'),
              child: const Text('编辑'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await captureScreenshot(tester, 'playlist-editor-light');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.showKeyboard(
        find.byKey(const ValueKey('playlist-editor-name-field')),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('保存歌单').hitTestable(), findsOneWidget);
      expect(tester.takeException(), null);
      await captureScreenshot(tester, 'playlist-editor-keyboard');
      tester.view.resetViewInsets();
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta7 official bottom morph, embedded search and quality dialog',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(
        tester,
        const MusicLandingPage(),
        shell: true,
        capture: 'beta7-home-expanded',
      );
      expect(
        tester
            .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
            .inline,
        false,
      );
      final navigationLabel = tester.element(find.text('发现').last);
      final navigationText = DefaultTextStyle.of(navigationLabel).style;
      expect(navigationText.fontFamily, isNot('monospace'));
      expect(navigationText.decoration, isNot(TextDecoration.underline));
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester
            .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
            .inline,
        true,
      );
      await captureScreenshot(tester, 'beta7-home-collapsed');
      await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester
            .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
            .inline,
        false,
      );
      await captureScreenshot(tester, 'beta7-search-expanded');
      await tester.enterText(find.byType(CupertinoTextField).last, '薛之谦');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      // Keyboard layout retargets its springs after a frame. Advance real
      // frame-sized steps before checking the settled action/dismiss spacing.
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final submit = find.descendant(
        of: find.byType(BetaGlassAction),
        matching: find.byType(GlassButton),
      );
      final cancel = find.bySemanticsLabel('关闭搜索').last;
      expect(tester.getRect(submit).overlaps(tester.getRect(cancel)), false);
      expect(tester.takeException(), null);
      final searchField = tester.getRect(find.byType(CupertinoTextField).last);
      final keyboardTop = tester.view.physicalSize.height - 280;
      expect(searchField.bottom, lessThanOrEqualTo(keyboardTop));
      expect(searchField.bottom, greaterThan(keyboardTop - 120));
      await captureScreenshot(tester, 'beta7-search-keyboard');
      tester.view.resetViewInsets();
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta7 quality dialog and every player appearance share the entry',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        viewport(tester);
        await prepare();
        await pump(tester, const BetaNowPlayingPage());
        await openQuality(tester);
        await tester.pump(const Duration(milliseconds: 400));
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        for (final label in ['标准', '高品质', '无损', 'Hi-Res']) {
          expect(find.text(label), findsOneWidget);
        }
        await captureScreenshot(tester, 'beta7-quality-dialog');
        for (final style in PlayerVisualStyle.values) {
          await container
              .read(playerVisualStyleProvider.notifier)
              .select(style);
          await pump(tester, NowPlayingPage(key: ValueKey(style.id)));
          expect(
            find.byTooltip('更多操作'),
            findsOneWidget,
            reason: style.displayName,
          );
          expect(find.byType(ApplePlayerControls), findsOneWidget);
          final seek = tester.widget<Slider>(
            find.byKey(const ValueKey('playback-seek-slider')),
          );
          final volume = tester.widget<Slider>(
            find.byKey(const ValueKey('system-media-volume')),
          );
          expect(seek.semanticFormatterCallback!(37000), '0分37秒，共4分19秒');
          expect(volume.semanticFormatterCallback!(.55), '55%');
          final seekNode = tester
              .getSemantics(
                find.byKey(const ValueKey('playback-seek-semantics')),
              )
              .getSemanticsData();
          final volumeNode = tester
              .getSemantics(
                find.byKey(const ValueKey('media-volume-semantics')),
              )
              .getSemanticsData();
          expect(seekNode.label, '播放进度');
          expect(seekNode.value, '0分37秒，共4分19秒');
          expect(seekNode.hasAction(ui.SemanticsAction.increase), true);
          expect(volumeNode.label, '系统媒体音量');
          expect(volumeNode.value, '55%');
          expect(volumeNode.hasAction(ui.SemanticsAction.decrease), true);
          expect(
            find.byKey(const ValueKey('system-media-volume')),
            findsOneWidget,
          );
          expect(find.byTooltip('显示或隐藏歌词'), findsOneWidget);
          expect(find.byTooltip('播放队列'), findsOneWidget);
          await captureScreenshot(tester, 'beta7-player-${style.name}');
        }
        await disposeFixture(tester);
      } finally {
        semantics.dispose();
      }
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta7 dress-up keeps progress characters and removes retired controls',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(
        tester,
        const ThemeGalleryPage(),
        capture: 'beta7-dress-up-top',
      );
      expect(find.text('品牌套装'), findsNothing);
      expect(find.text('经典皮肤'), findsNothing);
      expect(find.text('蜡笔小新'), findsNothing);
      expect(find.text('春日部晴空'), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('背景显示强度'), findsNothing);
      expect(find.text('动态效果性能'), findsNothing);
      expect(find.text('IP 角色装饰'), findsNothing);
      expect(find.text('跟随皮肤'), findsNothing);
      final catalog = find.byKey(const ValueKey('progress-outfit-catalog'));
      await tester.scrollUntilVisible(
        catalog,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('progress-outfit-preview')),
        findsOneWidget,
      );
      await tester.tap(catalog);
      // Selected vinyl and character previews intentionally keep animating.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      expect(find.text('Hello Kitty'), findsWidgets);
      expect(find.text('库洛米'), findsWidgets);
      await captureScreenshot(tester, 'beta7-dress-up-progress');
      expect(tester.takeException(), null);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta8 standard-only song hides unsupported tiers and permission hints',
    (tester) async {
      viewport(tester);
      await prepare(standardOnly: true);
      await pump(tester, const BetaNowPlayingPage());
      await openQuality(tester);
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('标准'), findsOneWidget);
      for (final label in ['高品质', '无损', 'Hi-Res', '需要会员／相应权限']) {
        expect(find.text(label), findsNothing);
      }
      await captureScreenshot(tester, 'beta8-quality-standard-only');
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta8 unknown quality metadata exposes retry instead of fabricated options',
    (tester) async {
      viewport(tester);
      await prepare(qualityUnknown: true);
      await pump(tester, const BetaNowPlayingPage());
      await openQuality(tester);
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('暂未获取到歌曲音质信息'), findsOneWidget);
      expect(find.byKey(const ValueKey('quality-option-128')), findsNothing);
      final before = paths.where((p) => p == '/audio').length;
      await tester.tap(find.text('重新加载'));
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(paths.where((p) => p == '/audio').length, before + 1);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );
  testWidgets(
    'beta7 shared status HUD replaces stale actions at the top',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showMusicNotice(
                context,
                icon: Icons.check_rounded,
                title: '单曲循环',
                message: '播放模式已切换',
              ),
              child: const Text('显示提示'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('显示提示'));
      await tester.pump(const Duration(milliseconds: 300));
      await captureScreenshot(tester, 'beta7-status-hud-light');
      final context = tester.element(find.text('显示提示'));
      showMusicNotice(
        context,
        icon: Icons.favorite_rounded,
        title: '已添加到喜欢',
        message: '',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('单曲循环'), findsNothing);
      expect(find.text('已添加到喜欢'), findsOneWidget);
      await captureScreenshot(tester, 'beta7-status-hud-replaced');
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );
  testWidgets(
    'beta7 standalone search also excludes local recommendation scoring',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(tester, const MusicSearchPage());
      expect(find.byType(PlatformSearchLanding), findsOneWidget);
      expect(find.text('猜你喜欢'), findsNothing);
      expect(find.text('我的热榜'), findsNothing);
      expect(find.text('热门搜索'), findsOneWidget);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta8 search builds a viewport of 480 rows and retains actions',
    (tester) async {
      viewport(tester);
      await prepare();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final songs = [
        for (var i = 0; i < 480; i++)
          Track(
            id: 'kugou_HASH$i',
            title: ['演员', '天外来物', '认真的雪'][i % 3],
            artist: '薛之谦',
            album: '音乐作品',
            duration: _track.duration,
            audioAsset: _track.audioAsset,
            coverAsset: _track.coverAsset,
            lyricsAsset: '',
            source: TrackSource.kugou,
          ),
      ];
      final state = MusicSearchState(
        query: '薛之谦',
        onlineTracks: songs,
        total: 480,
      );
      for (final dark in [false, true]) {
        await pump(
          tester,
          AppleSearchResults(state: state, controller: scroll),
          dark: dark,
          capture: 'beta8-search-results-${dark ? 'dark' : 'light'}',
        );
        final built = find.byType(TrackArtwork).evaluate().length;
        expect(built, lessThan(25));
        // ignore: avoid_print
        print('BETA8_SEARCH_BENCH catalogue=480 visibleArtworkWidgets=$built');
        expect(
          find.byWidgetPredicate((w) => w is SongActionsButton),
          findsWidgets,
        );
      }
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta8 anchored more menu stays grouped at phone and large-text widths',
    (tester) async {
      viewport(tester);
      await prepare();
      await container
          .read(playerVisualStyleProvider.notifier)
          .select(PlayerVisualStyle.classic);
      for (final narrow in [false, true]) {
        tester.view.physicalSize = narrow
            ? const Size(320, 640)
            : const Size(390, 844);
        await pump(tester, const BetaNowPlayingPage(), scale: narrow ? 1.6 : 1);
        await tester.tap(find.byTooltip('更多操作'));
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // 1.0.5 removes the duplicate lyrics action and starts styles folded.
        expect(find.text('查看歌词'), findsNothing);
        // Style values live in their own selector, so they no longer widen
        // the root menu's disclosure row.
        expect(find.text('黑胶唱片'), findsNothing);
        expect(find.text('流光唱片'), findsNothing);
        final styles = find.byKey(const ValueKey('player-style-disclosure'));
        await tester.ensureVisible(styles);
        await tester.tap(styles);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('流光唱片'), findsOneWidget);
        expect(tester.takeException(), null);
        await captureScreenshot(
          tester,
          narrow ? 'beta8-more-narrow' : 'beta8-more-phone',
        );
        await tester.tapAt(const Offset(20, 160));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta8 detail navigation keeps the tab that opened it',
    (tester) async {
      viewport(tester);
      await prepare();
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          ShellRoute(
            builder: (context, state, child) =>
                MusicShell(location: state.uri.toString(), child: child),
            routes: [
              for (final path in [
                '/profile',
                '/music/library',
                '/music',
                '/music/settings',
                '/player',
              ])
                GoRoute(path: path, builder: (_, _) => const SizedBox.expand()),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LiquidGlassWidgets.wrap(
            brightnessResolver: Theme.maybeBrightnessOf,
            child: MaterialApp.router(
              theme: buildMestingTheme(musicThemePresetById('classic')),
              routerConfig: router,
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      int selected() => tester
          .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
          .selectedIndex;
      await settle();
      expect(selected(), 3);
      router.push('/music?view=favorites');
      await settle();
      expect(selected(), 3);
      for (final overlay in ['/music/settings', '/player']) {
        router.push(overlay);
        await settle();
        expect(
          tester
              .widget<BetaMusicShell>(find.byType(BetaMusicShell))
              .chromeVisible,
          overlay == '/music/settings',
        );
        expect(find.byType(BetaMusicBottomBar), findsOneWidget);
        router.pop();
        await settle();
        expect(selected(), 3);
      }
      router.pop();
      await settle();
      expect(selected(), 3);
      router.go('/music/library');
      await settle();
      expect(selected(), 2);
      router.push('/music?view=favorites');
      await settle();
      expect(selected(), 2);
      router.push('/music/settings');
      await settle();
      expect(
        tester
            .widget<BetaMusicShell>(find.byType(BetaMusicShell))
            .chromeVisible,
        true,
      );
      expect(find.byType(BetaMusicBottomBar), findsOneWidget);
      router.pop();
      await settle();
      expect(selected(), 2);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta15 settings controls work after player reveal and guide covers chrome',
    (tester) async {
      viewport(tester);
      for (final sample in [
        (const Size(390, 844), 1.0),
        (const Size(320, 640), 1.6),
        (const Size(844, 390), 1.0),
      ]) {
        tester.view.physicalSize = sample.$1;
        await prepare();
        try {
          production.appRouter.go('/music/settings');
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: const ValueKey('beta5-capture'),
                child: MaterialApp.router(
                  theme: buildMestingTheme(musicThemePresetById('classic')),
                  routerConfig: production.appRouter,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(sample.$2)),
                    child: child!,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          container.read(playerChromeRevealProvider).value = 1;
          await tester.pump();
          final handler = container.read(audioHandlerProvider) as _Handler;
          // Settings gained a section also named "播放" in 1.0.3. Target the
          // real capsule control rather than tapping that static heading.
          await tester.tap(
            find
                .descendant(
                  of: find.byType(FloatingPlaybackPill),
                  matching: find.bySemanticsLabel('播放'),
                )
                .hitTestable()
                .first,
          );
          await tester.pump();
          expect(handler.toggles, 1, reason: 'viewport=$sample');
          await tester.tap(
            find
                .descendant(
                  of: find.byType(BetaMusicBottomBar),
                  matching: find.text('发现'),
                )
                .hitTestable()
                .first,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            production.appRouter.routeInformationProvider.value.uri.path,
            '/music/recommend',
          );
          production.appRouter.go('/music/settings');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          if (sample.$1 == const Size(390, 844)) {
            await captureScreenshot(tester, 'beta15-settings');
            final haptics = find.byKey(const ValueKey('settings-haptics'));
            await tester.scrollUntilVisible(
              haptics,
              160,
              scrollable: find
                  .descendant(
                    of: find.byType(SettingsPage),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await Scrollable.ensureVisible(
              tester.element(haptics),
              alignment: .25,
            );
            await tester.pump();
            await tester.tap(haptics);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(find.byType(HapticSettingsPage), findsOneWidget);
            expect(find.byType(BetaMusicBottomBar), findsNothing);
            await captureScreenshot(tester, 'beta15-haptics');
            await tester.pageBack();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          }
          final guide = find.byKey(const ValueKey('settings-guide'));
          await tester.scrollUntilVisible(
            guide,
            160,
            scrollable: find
                .descendant(
                  of: find.byType(SettingsPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await Scrollable.ensureVisible(tester.element(guide), alignment: .25);
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(guide);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(BetaMusicBottomBar), findsNothing);
          expect(find.byType(BetaOnboardingPage), findsOneWidget);
          await captureScreenshot(
            tester,
            'beta15-guide-${sample.$1.width.toInt()}x${sample.$1.height.toInt()}',
          );
          for (var page = 0; page < 8; page++) {
            final next = find.byKey(const ValueKey('guide-next'));
            expect(
              tester.getRect(next).bottom,
              lessThanOrEqualTo(sample.$1.height),
            );
            await tester.tap(next);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          }
          expect(find.byType(SettingsPage), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'viewport=$sample');
        } finally {
          await disposeFixture(tester);
        }
      }
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta15 player footer keeps icon centers aligned without inline quality text',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(tester, const BetaNowPlayingPage());
      final quality = find.byTooltip('更多操作');
      expect(
        find.descendant(of: quality, matching: find.byType(Text)),
        findsNothing,
      );
      final speaker = find.byKey(const ValueKey('player-output-glyph'));
      expect(
        tester.getCenter(speaker).dy,
        closeTo(
          tester.getCenter(find.bySemanticsLabel('显示或隐藏歌词').first).dy,
          .1,
        ),
      );
      expect(
        tester.getCenter(speaker).dy,
        closeTo(tester.getCenter(find.bySemanticsLabel('播放队列').first).dy, .1),
      );
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  for (final dark in [false, true]) {
    testWidgets(
      'search captions fit the shared type scale dark=$dark',
      (tester) async {
        viewport(tester);
        await prepare(richHome: true);
        await pump(
          tester,
          PlatformSearchLanding(onSearch: (_) {}),
          dark: dark,
          scale: 1.5,
        );
        final caption = find.text('此刻，慢下来');
        await tester.ensureVisible(caption);
        await tester.pump(const Duration(milliseconds: 500));
        final text = tester.widget<Text>(caption);
        expect(text.style!.fontSize, 15);
        expect(text.style!.fontWeight, FontWeight.w400);
        final card = find
            .ancestor(
              of: caption,
              matching: find.byWidgetPredicate(
                (widget) => widget is SizedBox && widget.width == 132,
              ),
            )
            .first;
        expect(tester.getSize(card).height, greaterThanOrEqualTo(201));
        expect(tester.takeException(), isNull);
        await disposeFixture(tester);
      },
      skip: !DistributionChannel.isBeta,
    );
  }

  testWidgets(
    'beta15 hot refresh keeps ranking and reports pending, unchanged, failure and recovery',
    (tester) async {
      viewport(tester);
      var calls = 0;
      const original = [
        PlatformHotSearchBoard('热搜榜', ['真实第一', '真实第二']),
      ];
      var pending = Completer<List<PlatformHotSearchBoard>>();
      await prepare(
        hotSearch: () async => ++calls == 1 ? original : pending.future,
      );
      await pump(tester, PlatformSearchLanding(onSearch: (_) {}));
      final refresh = find.byTooltip('刷新热门搜索');
      await tester.tap(refresh);
      await tester.pump();
      expect(calls, 2);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: refresh, matching: find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('真实第一'), findsOneWidget);
      pending.complete(original);
      await tester.pump();
      await tester.pump();
      expect(find.text('已是最新热搜'), findsOneWidget);
      pending = Completer<List<PlatformHotSearchBoard>>();
      await tester.tap(refresh);
      await tester.pump();
      pending.completeError(StateError('offline fixture'));
      await tester.pump();
      await tester.pump();
      expect(find.text('真实第一'), findsOneWidget);
      expect(find.text('刷新失败，已保留原榜单，请重试'), findsOneWidget);
      pending = Completer<List<PlatformHotSearchBoard>>();
      await tester.tap(refresh);
      await tester.pump();
      pending.complete(const [
        PlatformHotSearchBoard('热搜榜', ['新的真实第一']),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('新的真实第一'), findsOneWidget);
      expect(find.text('热搜已更新'), findsOneWidget);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta15 replay excludes future months in the current year',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(tester, const ListeningReplayPage());
      final months = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(months.length, DateTime.now().month + 1);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta8 playing vinyl stays on grooves and year menu is rounded',
    (tester) async {
      viewport(tester);
      await prepare(playing: true);
      await container
          .read(playerVisualStyleProvider.notifier)
          .select(PlayerVisualStyle.classic);
      await pump(
        tester,
        const BetaNowPlayingPage(),
        capture: 'beta8-vinyl-playing',
      );
      await pump(tester, const ListeningReplayPage());
      await tester.tap(find.byTooltip('选择年份'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('${DateTime.now().year} 年'), findsOneWidget);
      await captureScreenshot(tester, 'beta8-replay-year-menu');
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta9 both search edges and Router system Back follow result, landing, origin',
    (tester) async {
      viewport(tester);
      await prepare();
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          ShellRoute(
            builder: (context, state, child) =>
                MusicShell(location: state.uri.toString(), child: child),
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const MusicLandingPage(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LiquidGlassWidgets.wrap(
            brightnessResolver: Theme.maybeBrightnessOf,
            child: MaterialApp.router(
              theme: buildMestingTheme(musicThemePresetById('classic')),
              routerConfig: router,
            ),
          ),
        ),
      );
      Future<void> frames() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pumpArtworkReady(tester);
      }

      Future<void> openResults() async {
        await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
        await frames();
        await tester.enterText(find.byType(CupertinoTextField).last, '薛之谦');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await frames();
        expect(find.text('搜索结果'), findsNothing);
        expect(
          find.byKey(const ValueKey('search-kind-albums')),
          findsOneWidget,
        );
      }

      await frames();
      final bar = tester.element(find.byType(BetaMusicBottomBar));
      await openResults();
      await tester.dragFrom(const Offset(5, 240), const Offset(140, 0));
      await frames();
      expect(find.byType(PlatformSearchLanding), findsOneWidget);
      await tester.dragFrom(const Offset(385, 240), const Offset(-140, 0));
      await frames();
      expect(find.byType(PlatformSearchLanding), findsNothing);
      expect(
        tester
            .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
            .selectedIndex,
        3,
      );
      expect(
        identical(tester.element(find.byType(BetaMusicBottomBar)), bar),
        true,
      );
      await openResults();
      await tester.binding.handlePopRoute();
      await frames();
      expect(find.byType(PlatformSearchLanding), findsOneWidget);
      await tester.binding.handlePopRoute();
      await frames();
      expect(find.byType(PlatformSearchLanding), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/profile');
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta9 comment filters share one row and composer uses sibling liquid glass',
    (tester) async {
      viewport(tester);
      await prepare();
      for (final dark in [false, true]) {
        await pump(
          tester,
          PlatformCommentsPage(
            resource: _resource,
            repository: PlatformCommentsRepository(api, _identity),
          ),
          dark: dark,
          capture: 'beta9-comments-${dark ? 'dark' : 'light'}',
        );
        final sort = find.byTooltip('评论排序');
        final scope = find.byTooltip('评论范围');
        expect(
          (tester.getCenter(sort).dy - tester.getCenter(scope).dy).abs(),
          lessThan(1),
        );
        expect(find.byType(ChoiceChip), findsNothing);
        expect(
          find.byKey(const ValueKey('comment-liquid-glass-input')),
          findsOneWidget,
        );
        final send = find.byKey(const ValueKey('comment-blue-glass-send'));
        expect(tester.getSize(send), const Size(48, 48));
        expect(tester.getSize(find.byType(TextField)).height, lessThan(60));
        await tester.tap(sort);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.text('最新'), findsOneWidget);
        await tester.tap(find.text('最新').hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('最新'), findsOneWidget);
        expect(find.byType(PlatformCommentComposer), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getBottomRight(send).dy, lessThan(844 - 280));
        expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 2);
        tester.view.resetViewInsets();
      }
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta9 playback pill position events do not rebuild the glass control',
    (tester) async {
      viewport(tester);
      final events = StreamController<PlaybackState>.broadcast(sync: true);
      await prepare(playbackEvents: events.stream);
      await pump(tester, const MusicLandingPage(), shell: true);
      events.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.ready,
        ),
      );
      await tester.pump();
      var rebuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is FloatingPlaybackPill) rebuilds++;
      };
      try {
        for (var i = 0; i < 100; i++) {
          events.add(
            PlaybackState(
              playing: true,
              processingState: AudioProcessingState.ready,
              updatePosition: Duration(milliseconds: i * 100),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
      } finally {
        debugOnRebuildDirtyWidget = previous;
      }
      // ignore: avoid_print
      print(
        'BETA9_PILL_BENCH positionEvents=100 glassControlRebuilds=$rebuilds',
      );
      if (!const bool.fromEnvironment('BETA_BENCHMARK_BASELINE')) {
        expect(rebuilds, lessThanOrEqualTo(1));
      }
      await disposeFixture(tester);
      await events.close();
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta9 narrow comment keyboard and long title remain usable',
    (tester) async {
      viewport(tester, const Size(320, 640));
      await prepare();
      await pump(
        tester,
        PlatformCommentsPage(
          resource: _resource,
          repository: PlatformCommentsRepository(api, _identity),
        ),
        scale: 1.6,
        capture: 'beta9-comments-narrow-large',
      );
      await tester.enterText(
        find.byType(TextField),
        '每一段旋律，都留下自己的故事。\n今天也在认真听歌。',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump(const Duration(milliseconds: 300));
      final send = find.byKey(const ValueKey('comment-blue-glass-send'));
      expect(tester.getBottomRight(send).dy, lessThan(360));
      expect(send.hitTestable(), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 2);
      expect(tester.takeException(), null);
      await captureScreenshot(tester, 'beta9-comments-keyboard-large');
      tester.view.resetViewInsets();
      await pump(
        tester,
        const PlatformPageFrame(
          title: '暖场小曲：深夜酒吧的走心时刻',
          child: Center(child: Text('歌曲列表')),
        ),
        capture: 'beta9-title-start',
      );
      final title = find.text('暖场小曲：深夜酒吧的走心时刻');
      final start = tester.getTopLeft(title).dx;
      await tester.pump(const Duration(seconds: 3));
      expect(tester.getTopLeft(title).dx, lessThan(start));
      await captureScreenshot(
        tester,
        'beta9-title-scrolling',
        settle: Duration.zero,
      );
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta10 search and production routes keep opaque middle frames in both themes',
    (tester) async {
      viewport(tester);
      for (final dark in [false, true]) {
        await prepare();
        await pump(tester, const MusicLandingPage(), shell: true, dark: dark);
        await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        final surface = tester.widget<ColoredBox>(
          find.byKey(const ValueKey('beta10-search-surface')),
        );
        expect(surface.color.a, 1);
        await captureScreenshot(
          tester,
          'beta10-search-enter-middle-${dark ? 'dark' : 'light'}',
          settle: Duration.zero,
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(MusicLandingPage), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        await captureScreenshot(
          tester,
          'beta10-search-exit-middle-${dark ? 'dark' : 'light'}',
          settle: Duration.zero,
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(MusicLandingPage), findsOneWidget);
        await disposeFixture(tester);
      }
      await prepare();
      production.appRouter.go('/music/recommend');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: production.appRouter,
            theme: buildMestingTheme(musicThemePresetById('classic')),
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('beta5-capture'),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      final pushed = production.appRouter.push('/music/search');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester
            .widget<ColoredBox>(
              // Routed search uses the shell's own moving, opaque surface;
              // retained roots intentionally have no primary page transition.
              find.byKey(const ValueKey('beta10-search-surface')).last,
            )
            .color
            .a,
        1,
      );
      await captureScreenshot(
        tester,
        'beta10-route-push-middle',
        settle: Duration.zero,
      );
      production.appRouter.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await captureScreenshot(
        tester,
        'beta10-route-pop-middle',
        settle: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 450));
      await pushed;
      expect(tester.takeException(), isNull);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta10 real player keeps transport through paired content transitions',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(tester, const BetaNowPlayingPage());
      final transport = tester.element(find.byType(ApplePlayerControls));
      Future<void> middle(String label) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          identical(
            transport,
            tester.element(find.byType(ApplePlayerControls)),
          ),
          true,
        );
        expect(tester.takeException(), isNull);
        await captureScreenshot(tester, label, settle: Duration.zero);
      }

      await tester.tap(find.bySemanticsLabel('查看歌词'));
      await middle('beta10-lyrics-enter-middle');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.bySemanticsLabel('返回封面'));
      await middle('beta10-lyrics-exit-middle');
      await tester.pump(const Duration(milliseconds: 400));
      // Use the production menu callback, rather than replacing the page.
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await captureScreenshot(
        tester,
        'beta10-more-enter-middle',
        settle: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 250));
      final styles = find.byKey(const ValueKey('player-style-disclosure'));
      await tester.ensureVisible(styles);
      await tester.tap(styles);
      await tester.pump();
      await tester.tap(find.text('黑胶唱片'));
      await middle('beta10-style-switch-middle');
      await tester.pump(const Duration(milliseconds: 450));
      for (final next in [true, false]) {
        await tester.tap(find.bySemanticsLabel(next ? '下一首' : '上一首'));
        // This UI fixture replaces metadata only; playback itself is covered
        // by deterministic audio-engine tests, without a second audio owner.
        container
            .read(_qaRecordingProvider.notifier)
            .select(
              next
                  ? Track.fromJson({
                      ..._track.toJson(),
                      'id': 'next-recording',
                      'title': '下一段旋律',
                    })
                  : _track,
            );
        await middle('beta10-song-${next ? 'next' : 'previous'}-middle');
        // A retained outgoing artwork stage intentionally freezes its own
        // ticker/direction while the outer transition dismisses it. Check the
        // live content island, not that inactive historical snapshot.
        final transitions = find
            .byType(PlayerContentTransition)
            .evaluate()
            .where((element) => TickerMode.valuesOf(element).enabled)
            .map((element) => element.widget as PlayerContentTransition);
        expect(transitions.every((w) => w.direction == (next ? 1 : -1)), true);
        await tester.pump(const Duration(milliseconds: 450));
      }
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta11 five categories retain results and destination navigation ends search',
    (tester) async {
      viewport(tester);
      await prepare(guest: true);
      for (final dark in [false, true]) {
        await pump(tester, const BetaCategorySearchResults(), dark: dark);
        await container
            .read(musicSearchControllerProvider.notifier)
            .submit('薛之谦');
        for (final kind in PlatformSearchKind.values.where(
          (k) => k != PlatformSearchKind.users,
        )) {
          await tester.tap(find.byKey(ValueKey('search-kind-${kind.name}')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 450));
          expect(find.text('搜索结果'), findsNothing);
          expect(tester.takeException(), isNull);
          await captureScreenshot(
            tester,
            'beta11-search-${kind.name}-${dark ? 'dark' : 'light'}',
          );
        }
      }
      await pump(tester, const MusicLandingPage(), shell: true);
      await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.enterText(find.byType(CupertinoTextField).last, '薛之谦');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await pumpArtworkReady(tester);
      await tester.tap(find.byKey(const ValueKey('search-kind-albums')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      final bar = tester.widget<BetaMusicBottomBar>(
        find.byType(BetaMusicBottomBar),
      );
      bar.onTabSelected(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(container.read(musicSearchControllerProvider).query, '');
      expect(
        container.read(categorySearchProvider).selected,
        PlatformSearchKind.songs,
      );
      expect(container.read(categorySearchProvider).pages, isEmpty);
      await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(PlatformSearchLanding), findsOneWidget);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta11 guest writes are blocked while playback remains available',
    (tester) async {
      viewport(tester);
      await prepare(guest: true);
      // Check the actual provider guard, not the fixture repository override.
      final guestRepo = LibraryRepository(
        database,
        ownerId: legacyLibraryOwnerId,
        canWrite: () => false,
      );
      await expectLater(guestRepo.toggleFavorite(_track), throwsStateError);
      await expectLater(
        guestRepo.createPlaylist(id: 'forbidden', name: 'guest'),
        throwsStateError,
      );
      expect(await guestRepo.isFavorite(_track.id), false);
      bool? allowed;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildMestingTheme(musicThemePresetById('classic')),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async => allowed = await ensureLibraryAccess(
                    context,
                    ref,
                    reason: '登录后收藏',
                    redirect: '/music',
                  ),
                  child: const Text('收藏'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('收藏'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      // Protected writes use the shared platform-choice welcome route.
      expect(find.text('酷狗登录'), findsOneWidget);
      expect(find.text('网易云登录'), findsOneWidget);
      Navigator.of(tester.element(find.text('酷狗登录'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(allowed, false);
      guestRepo.dispose();
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta11 result offsets survive categories/details but never a new same-query session',
    (tester) async {
      viewport(tester, const Size(320, 640));
      await prepare(guest: true);
      production.appRouter.go('/music/recommend');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: production.appRouter,
            theme: buildMestingTheme(musicThemePresetById('classic')),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(); // Mount results after the final moving frame.
        await pumpArtworkReady(tester);
      }

      await settle();
      Future<void> openAlbums() async {
        await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
        await settle();
        await tester.enterText(find.byType(CupertinoTextField).last, '薛之谦');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await settle();
        await tester.tap(find.byKey(const ValueKey('search-kind-albums')));
        await settle();
      }

      ScrollController activeScroll() => tester
          .widget<CustomScrollView>(
            find
                .descendant(
                  of: find.byType(BetaCategorySearchResults),
                  matching: find.byType(CustomScrollView),
                )
                .last,
          )
          .controller!;
      await openAlbums();
      activeScroll().jumpTo(50);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-kind-songs')));
      await settle();
      await tester.tap(find.byKey(const ValueKey('search-kind-albums')));
      await settle();
      expect(activeScroll().offset, closeTo(50, 1));
      final detail = production.appRouter.push(
        '/music/catalog/albums/0',
        extra: PlatformSearchHit(
          kind: PlatformSearchKind.albums,
          id: '0',
          title: '意外',
          cover: _track.coverAsset,
        ),
      );
      await settle();
      expect(
        find.byType(BetaCategorySearchResults).hitTestable(),
        findsNothing,
      );
      production.appRouter.pop();
      await settle();
      await detail;
      expect(
        find.byKey(const ValueKey('search-kind-albums')).hitTestable(),
        findsOneWidget,
      );
      expect(activeScroll().offset, closeTo(50, 1));
      tester
          .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
          .onTabSelected(0);
      await settle();
      await openAlbums();
      expect(activeScroll().offset, 0);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta12 embedded search advertises and consumes real system back history for every category',
    (tester) async {
      viewport(tester);
      await prepare(guest: true);
      production.appRouter.go('/music/recommend');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: production.appRouter,
            theme: buildMestingTheme(musicThemePresetById('classic')),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(); // Mount results after the final moving frame.
        await pumpArtworkReady(tester);
      }

      await settle();
      expect(production.appRouter.canPop(), false);
      await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
      await settle();
      // Android needs a real Navigator target, not only a Dart dispatcher hook.
      expect(production.appRouter.canPop(), true);
      for (final kind in PlatformSearchKind.values.where(
        (k) => k != PlatformSearchKind.users,
      )) {
        await tester.enterText(find.byType(CupertinoTextField).last, '薛之谦');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await settle();
        await tester.tap(find.byKey(ValueKey('search-kind-${kind.name}')));
        await settle();
        expect(production.appRouter.canPop(), true);
        if (kind == PlatformSearchKind.albums) {
          expect(await production.appRouter.routerDelegate.popRoute(), true);
        } else {
          await tester.binding.handlePopRoute();
        }
        await settle();
        expect(container.read(musicSearchControllerProvider).query, isEmpty);
        expect(find.byType(PlatformSearchLanding), findsOneWidget);
        expect(production.appRouter.canPop(), true);
      }
      await tester.binding.handlePopRoute();
      await settle();
      expect(find.byType(PlatformSearchLanding), findsNothing);
      expect(production.appRouter.canPop(), false);
      expect(
        production.appRouter.routeInformationProvider.value.uri.path,
        '/music/recommend',
      );
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta14 Android back registration survives retained-engine resume and follows every page level',
    (tester) async {
      viewport(tester);
      await prepare(guest: true);
      await container.read(betaEntryFlowProvider.notifier).finish();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      bool? androidHandlesBack;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          androidHandlesBack = call.arguments as bool;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      production.appRouter.go('/music/recommend');
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: production.appRouter,
              theme: buildMestingTheme(musicThemePresetById('classic')),
              builder: (context, child) => SystemBackCoordinator(
                canPop: production.appRouter.canPop,
                child: BetaEntryCoordinator(
                  backDispatcher: production.appRouter.backButtonDispatcher,
                  child: child!,
                ),
              ),
            ),
          ),
        );
        var backCheckStep = 0;
        Future<void> settle() async {
          // Route completion, local history and native Back reporting each
          // schedule frames. Advance frame-sized steps rather than one jump.
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          backCheckStep++;
          expect(
            tester.takeException(),
            isNull,
            reason:
                'back step $backCheckStep at ${production.appRouter.routeInformationProvider.value.uri}',
          );
        }

        await settle();
        expect(androidHandlesBack, false);
        await tester.tap(find.byIcon(CupertinoIcons.search).hitTestable().last);
        await settle();
        expect(androidHandlesBack, true, reason: 'search is a secondary page');
        await tester.enterText(find.byType(CupertinoTextField).last, '薛之谦');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await settle();
        expect(androidHandlesBack, true);
        await tester.binding.handlePopRoute();
        await settle();
        expect(container.read(musicSearchControllerProvider).query, isEmpty);
        expect(find.byType(PlatformSearchLanding), findsOneWidget);
        expect(androidHandlesBack, true);
        await tester.binding.handlePopRoute();
        await settle();
        expect(find.byType(PlatformSearchLanding), findsNothing);
        expect(androidHandlesBack, false);
        for (final path in [
          '/music?view=daily',
          '/music/settings',
          '/music/themes',
          '/player',
        ]) {
          final popped = production.appRouter.push<void>(path);
          await settle();
          expect(androidHandlesBack, true, reason: path);
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          // AudioService retains Dart while a fresh Android Activity starts with
          // no OnBackInvokedCallback. Reattachment must republish the current flag.
          androidHandlesBack = false;
          for (final state in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await settle();
          expect(androidHandlesBack, true, reason: 'resume on $path');
          await tester.binding.handlePopRoute();
          await settle();
          await popped;
          expect(
            production.appRouter.routeInformationProvider.value.uri.path,
            '/music/recommend',
          );
          expect(androidHandlesBack, false, reason: 'returned from $path');
        }
        for (final destination in {
          '/music?view=daily': '/music/recommend',
          '/music/settings': '/music/recommend',
          '/music/search': '/music/recommend',
          '/player': '/music/recommend',
        }.entries) {
          production.appRouter.go(destination.key);
          await settle();
          expect(
            androidHandlesBack,
            true,
            reason: 'a restored secondary page still has a logical parent',
          );
          await tester.binding.handlePopRoute();
          await settle();
          expect(
            production.appRouter.routeInformationProvider.value.uri.toString(),
            destination.value,
          );
          expect(
            androidHandlesBack,
            false,
            reason: 'returned from ${destination.key}',
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await disposeFixture(tester);
      }
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'ui188 imperative chart opens exactly one player and returns to that chart',
    (tester) async {
      viewport(tester);
      await prepare(playing: true);
      production.appRouter.go('/music/recommend');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: production.appRouter,
            theme: buildMestingTheme(musicThemePresetById('classic')),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final origin = tester.element(find.byType(FloatingPlaybackPill).first);
      final navigator = Navigator.of(origin, rootNavigator: true);
      unawaited(
        navigator.push(
          MestingPageRoute<void>(
            builder: (_) => Scaffold(
              key: const ValueKey('ui188-chart'),
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () {
                    unawaited(openNowPlaying(context, ref));
                    unawaited(openNowPlaying(context, ref));
                  },
                  child: const Text('ui188-open-player'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('ui188-open-player'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));
      expect(
        find.byType(BetaNowPlayingPage, skipOffstage: false),
        findsOneWidget,
      );
      final close = find.byKey(const ValueKey('player-dismiss-glass'));
      await tester.tap(close);
      await tester.pump();
      for (var frame = 0; frame < 7; frame++) {
        await tester.pump(const Duration(milliseconds: 65));
        expect(
          find
              .byType(BetaNowPlayingPage, skipOffstage: false)
              .evaluate()
              .length,
          lessThanOrEqualTo(1),
        );
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(BetaNowPlayingPage, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ui188-chart')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // The same source must also survive system Back and the real handle
      // gesture, not just the close button used by the supplied recording.
      for (final byHandle in [false, true]) {
        await tester.tap(find.text('ui188-open-player'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
        if (byHandle) {
          await tester.timedDrag(
            find.byKey(const ValueKey('player-dismiss-handle')),
            const Offset(0, 280),
            const Duration(milliseconds: 300),
          );
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 750));
        expect(
          find.byType(BetaNowPlayingPage, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('ui188-chart')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      navigator.pop();
      await tester.pump(const Duration(seconds: 1));
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta12 handle drives one real route exit and a cancelled drag rebounds without popping',
    (tester) async {
      viewport(tester);
      await prepare(playing: true);
      production.appRouter.go('/music/recommend');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: production.appRouter,
            theme: buildMestingTheme(musicThemePresetById('classic')),
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('beta5-capture'),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final pushed = production.appRouter.push('/player');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final player = find.byType(BetaNowPlayingPage);
      final route = ModalRoute.of(tester.element(player))!;
      final handle = find.byKey(const ValueKey('player-dismiss-handle'));
      var drag = await tester.startGesture(tester.getCenter(handle));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 70));
      await tester.pump();
      expect(tester.getTopLeft(player).dy, greaterThan(40));
      await drag.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(tester.getTopLeft(player).dy, closeTo(0, .1));
      expect(route.isCurrent, true);
      drag = await tester.startGesture(tester.getCenter(handle));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 260));
      await tester.pump();
      final releasedAt = tester.getTopLeft(player).dy;
      expect(releasedAt, greaterThan(200));
      await captureScreenshot(
        tester,
        'beta12-player-drag-held',
        settle: Duration.zero,
      );
      await drag.up();
      await tester.pump();
      var previous = releasedAt;
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (player.evaluate().isNotEmpty) {
          final top = tester.getTopLeft(player).dy;
          expect(top, greaterThanOrEqualTo(previous - .5));
          previous = top;
        }
        if (frame == 4) {
          await captureScreenshot(
            tester,
            'beta12-player-drag-finishing',
            settle: Duration.zero,
          );
        }
      }
      expect(player, findsNothing);
      expect(
        production.appRouter.routeInformationProvider.value.uri.path,
        '/music/recommend',
      );
      expect(production.appRouter.canPop(), false);
      await pushed;
      await captureScreenshot(
        tester,
        'beta12-player-drag-complete',
        settle: Duration.zero,
      );
      expect(tester.takeException(), null);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta12 glass background and compact matrix plus responsive startup and edit controls',
    (tester) async {
      for (final scenario in [
        (false, false, const Size(390, 844)),
        (false, true, const Size(390, 844)),
        (true, false, const Size(390, 844)),
        (true, true, const Size(390, 844)),
        (false, true, const Size(900, 740)),
      ]) {
        final (dark, detailed, size) = scenario;
        viewport(tester, size);
        await prepare(playing: true);
        final scroll = ScrollController();
        final page = ListView.builder(
          controller: scroll,
          itemExtent: 96,
          itemCount: 30,
          itemBuilder: (context, index) => detailed
              ? Container(
                  color: index.isEven
                      ? const Color(0xFF496ABD)
                      : const Color(0xFFAB5148),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      TrackArtwork(track: _track, width: 64, height: 64),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          '认真的雪\n薛之谦 · 玻璃背景测试',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.expand(),
        );
        final name =
            'beta12-glass-${dark ? "dark" : "light"}-${detailed ? "content" : "plain"}-${size.width.toInt()}';
        await pump(
          tester,
          page,
          shell: true,
          dark: dark,
          capture: '$name-expanded',
        );
        scroll.jumpTo(300);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        await captureScreenshot(tester, '$name-morph', settle: Duration.zero);
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester
              .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
              .inline,
          true,
        );
        await captureScreenshot(tester, '$name-compact', settle: Duration.zero);
        await disposeFixture(tester);
        scroll.dispose();
      }
      for (final dark in [false, true]) {
        viewport(tester, const Size(320, 640));
        await prepare();
        await pump(
          tester,
          const SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: StartupStylePicker(),
            ),
          ),
          dark: dark,
          scale: 1.6,
          capture: 'beta12-startup-picker-${dark ? "dark" : "light"}-large',
        );
        expect(tester.takeException(), null);
        await disposeFixture(tester);
        viewport(tester);
        await prepare();
        await pump(
          tester,
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showPlaylistEditorDialog(
                  context,
                  initialName: '我的歌单',
                  initialDescription: '把喜欢的音乐留在这里',
                ),
                child: const Text('编辑'),
              ),
            ),
          ),
          dark: dark,
        );
        await tester.tap(find.text('编辑'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await captureScreenshot(
          tester,
          'beta12-playlist-edit-${dark ? "dark" : "light"}',
        );
        expect(tester.takeException(), null);
        await disposeFixture(tester);
      }
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta12 rendered comment action stays saturated blue across scrolling backdrops',
    (tester) async {
      viewport(tester);
      for (final dark in [false, true]) {
        await prepare();
        final scroll = ScrollController();
        final text = TextEditingController();
        await pump(
          tester,
          Scaffold(
            extendBody: true,
            body: ListView.builder(
              controller: scroll,
              itemExtent: 200,
              itemCount: 12,
              itemBuilder: (context, index) => index.isEven
                  ? ColoredBox(
                      color: dark ? const Color(0xFF11141B) : Colors.white,
                    )
                  : TrackArtwork(
                      track: _track,
                      width: 390,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
            ),
            bottomNavigationBar: PlatformCommentComposer(
              controller: text,
              sending: false,
              keyboardVisible: false,
              onSend: () {},
            ),
          ),
          dark: dark,
        );
        for (var step = 0; step < 3; step++) {
          scroll.jumpTo(step * 280.0);
          await tester.pump(const Duration(milliseconds: 16));
          final rect = tester.getRect(
            find.byKey(const ValueKey('comment-blue-glass-send')),
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('beta5-capture')),
          );
          final rgb = await tester.runAsync(() async {
            final picture = await boundary.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final offset =
                ((rect.center.dy.floor() * picture.width) +
                    rect.left.floor() +
                    12) *
                4;
            final sample = [
              bytes!.getUint8(offset),
              bytes.getUint8(offset + 1),
              bytes.getUint8(offset + 2),
            ];
            picture.dispose();
            return sample;
          });
          expect(rgb![2] - rgb[0], greaterThan(80));
          expect(rgb[2] - rgb[1], greaterThan(30));
          // ignore: avoid_print
          print('BETA12_BLUE_SAMPLE ${dark ? "dark" : "light"} $step $rgb');
          await captureScreenshot(
            tester,
            'beta12-blue-scroll-${dark ? "dark" : "light"}-$step',
            settle: Duration.zero,
          );
        }
        await disposeFixture(tester);
        scroll.dispose();
        text.dispose();
      }
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta15 morph retains its optical layer between geometry frames',
    (tester) async {
      viewport(tester);
      await prepare(playing: true);
      await pump(tester, const MusicLandingPage(), shell: true);
      final counts = <String, int>{};
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, _) {
        final name = element.widget.runtimeType.toString();
        if ([
          'AdaptiveLiquidGlassLayer',
          'TrackArtwork',
          'FloatingPlaybackPill',
        ].contains(name)) {
          counts[name] = (counts[name] ?? 0) + 1;
        }
      };
      Object? surface;
      var stable = false;
      try {
        final context = tester.element(find.byType(ListView).first);
        ScrollUpdateNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 2000,
            pixels: 300,
            viewportDimension: 700,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1,
          ),
          context: context,
          scrollDelta: 300,
        ).dispatch(context);
        final layers = find.descendant(
          of: find.byType(GlassTabBar),
          matching: find.byType(AdaptiveLiquidGlassLayer),
        );
        for (var frame = 0; frame < 24; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (frame == 3) surface = tester.widget(layers.first);
          if (frame == 8) {
            stable = identical(surface, tester.widget(layers.first));
          }
        }
      } finally {
        debugOnRebuildDirtyWidget = previous;
      }
      // ignore: avoid_print
      print('BETA15_MORPH_BENCH $counts stableOptics=$stable');
      expect(stable, true);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta11 playing-scroll compact rebuild benchmark',
    (tester) async {
      viewport(tester);
      await prepare(playing: true);
      await pump(tester, const MusicLandingPage(), shell: true);
      final counts = <String, int>{};
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, _) {
        final name = element.widget.runtimeType.toString();
        if ([
          'BetaMusicShell',
          'BetaMusicBottomBar',
          'FloatingPlaybackPill',
          'MusicLandingPage',
        ].contains(name)) {
          counts[name] = (counts[name] ?? 0) + 1;
        }
      };
      try {
        final context = tester.element(find.byType(ListView).first);
        // Same sequence, same clocks, one notification per simulated rendered
        // frame; this measures rebuild scope, not Android GPU frame rate.
        for (var frame = 0; frame < 120; frame++) {
          ScrollUpdateNotification(
            metrics: FixedScrollMetrics(
              minScrollExtent: 0,
              maxScrollExtent: 2000,
              pixels: frame.isEven ? 300 : 0,
              viewportDimension: 700,
              axisDirection: AxisDirection.down,
              devicePixelRatio: 1,
            ),
            context: context,
            scrollDelta: frame.isEven ? 300 : -300,
          ).dispatch(context);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 500));
      } finally {
        debugOnRebuildDirtyWidget = previous;
      }
      // ignore: avoid_print
      print('BETA11_COMPACT_BENCH $counts');
      expect(counts['BetaMusicShell'] ?? 0, 0);
      expect(
        tester
            .widget<BetaMusicBottomBar>(find.byType(BetaMusicBottomBar))
            .inline,
        false,
      );
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta9 capsule uses the shared live toggle for rapid taps',
    (tester) async {
      viewport(tester);
      await prepare(playing: true);
      await pump(tester, const MusicLandingPage(), shell: true);
      final handler = container.read(audioHandlerProvider) as _Handler;
      final pause = find.bySemanticsLabel('暂停').first;
      await tester.tap(pause);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(pause);
      await tester.pump();
      expect(handler.toggles, 2);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );
  for (final dark in [false, true]) {
    testWidgets(
      'beta13 capsule long press opens anchored premium glass and reverses on outside tap ($dark)',
      (tester) async {
        viewport(tester);
        await prepare();
        await pump(tester, const MusicLandingPage(), shell: true, dark: dark);
        final capsule = find.byKey(const ValueKey('beta6-official-play-pill'));
        final rect = tester.getRect(capsule);
        await tester.longPress(capsule);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 340));
        final surface = find.byKey(const ValueKey('beta13-glass-menu-surface'));
        expect(surface, findsOneWidget);
        expect(tester.getRect(surface).bottom, lessThanOrEqualTo(rect.top + 1));
        final glass = tester.widget<GlassContainer>(surface);
        expect(glass.quality, GlassQuality.premium);
        expect(find.text('查看歌词'), findsOneWidget);
        expect(find.text('创建电台'), findsNothing);
        expect(find.text('分享歌词'), findsNothing);
        expect(find.text('不喜欢这首'), findsNothing);
        await captureScreenshot(
          tester,
          'beta13-capsule-menu-${dark ? 'dark' : 'light'}',
        );
        await tester.tapAt(const Offset(12, 100));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(surface, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        expect(surface, findsNothing);
        expect(tester.getRect(capsule), rect);
        expect(tester.takeException(), isNull);
        await disposeFixture(tester);
      },
      skip: !DistributionChannel.isBeta,
    );

    for (final numeric in [false, true]) {
      testWidgets(
        'beta13 editing menu preserves selection and field formatters ($dark/$numeric)',
        (tester) async {
          viewport(tester, const Size(320, 700));
          await prepare();
          final controller = TextEditingController(
            text: numeric ? '13800138000' : '喜欢的音乐',
          );
          await pump(
            tester,
            Padding(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TextField(
                  controller: controller,
                  contextMenuBuilder: buildBetaEditingMenu,
                  selectionControls: betaTextSelectionControls,
                  keyboardType: numeric
                      ? TextInputType.phone
                      : TextInputType.multiline,
                  maxLines: numeric ? 1 : 4,
                  inputFormatters: numeric
                      ? [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ]
                      : null,
                ),
              ),
            ),
            dark: dark,
            scale: 1.3,
          );
          final field = find.byType(TextField);
          await tester.tap(field);
          await tester.pump();
          controller.selection = const TextSelection.collapsed(offset: 2);
          final editable = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          editable.showToolbar();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.byKey(const ValueKey('beta13-glass-menu-surface')),
            findsOneWidget,
          );
          await tester.tap(find.bySemanticsLabel('更多编辑操作'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          if (numeric) {
            expect(find.text('#'), findsNothing);
            expect(find.text('换行'), findsNothing);
          } else {
            expect(find.text('#'), findsOneWidget);
            expect(find.text('换行'), findsOneWidget);
          }
          final menuRect = tester.getRect(
            find.byKey(const ValueKey('beta13-glass-menu-surface')),
          );
          expect(
            menuRect.bottom,
            lessThanOrEqualTo(tester.getRect(field).top - 7),
            reason: 'the gap belongs outside the whole input field',
          );
          expect(find.text('朗读'), findsNothing);
          await captureScreenshot(
            tester,
            'beta13-edit-menu-${dark ? 'dark' : 'light'}-${numeric ? 'numeric' : 'multiline'}',
          );
          if (!numeric) {
            await tester.tap(find.text('#'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 250));
            expect(controller.text, '喜欢#的音乐');
            expect(controller.selection.baseOffset, 3);
          } else {
            editable.hideToolbar();
            editable.userUpdateTextEditingValue(
              const TextEditingValue(
                text: '13#abc800138000',
                selection: TextSelection.collapsed(offset: 14),
              ),
              SelectionChangedCause.toolbar,
            );
            expect(controller.text, '13800138000');
          }
          expect(tester.takeException(), isNull);
          await disposeFixture(tester);
          controller.dispose();
        },
        skip: !DistributionChannel.isBeta,
      );
    }
  }
  testWidgets(
    'beta13 search keeps real results until return motion finishes',
    (tester) async {
      viewport(tester);
      await prepare(guest: true);
      final key = GlobalKey<MusicSearchResultsBodyState>();
      await pump(tester, MusicSearchResultsBody(key: key, onSearch: (_) {}));
      await container
          .read(musicSearchControllerProvider.notifier)
          .submit('薛之谦');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      key.currentState!.returnToLanding(
        () =>
            container.read(musicSearchControllerProvider.notifier).setQuery(''),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(musicSearchControllerProvider).query, '薛之谦');
      expect(find.byType(BetaCategorySearchResults), findsOneWidget);
      expect(find.byType(PlatformSearchLanding), findsOneWidget);
      await captureScreenshot(
        tester,
        'beta13-search-return-middle',
        settle: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(container.read(musicSearchControllerProvider).query, isEmpty);
      expect(find.byType(BetaCategorySearchResults), findsNothing);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'release130 search defers results until settled and reverses over the retained landing',
    (tester) async {
      viewport(tester);
      await prepare(guest: true);
      final key = GlobalKey<MusicSearchResultsBodyState>();
      await pump(tester, MusicSearchResultsBody(key: key, onSearch: (_) {}));
      final landing = tester.element(find.byType(PlatformSearchLanding));
      await container
          .read(musicSearchControllerProvider.notifier)
          .submit('薛之谦');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.byType(BetaCategorySearchResults),
        findsNothing,
        reason:
            'Heavy result rows and decoders mount after the final entry frame.',
      );
      final middle = tester
          .getTopLeft(
            find.byKey(const ValueKey('beta13-search-results-surface')),
          )
          .dx;
      expect(
        middle,
        closeTo(390 * (1 - Curves.easeInOutCubic.transform(.5)), 2),
      );
      await captureScreenshot(
        tester,
        'release130-search-entry-middle',
        settle: Duration.zero,
      );
      expect(
        tester.element(find.byType(PlatformSearchLanding, skipOffstage: false)),
        same(landing),
      );
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump();
      expect(find.byType(BetaCategorySearchResults), findsOneWidget);
      await captureScreenshot(
        tester,
        'release130-search-settled',
        settle: Duration.zero,
      );
      key.currentState!.returnToLanding(
        () =>
            container.read(musicSearchControllerProvider.notifier).setQuery(''),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      final reverse = tester
          .getTopLeft(
            find.byKey(const ValueKey('beta13-search-results-surface')),
          )
          .dx;
      expect(
        reverse,
        closeTo(middle, 2),
        reason: 'Exit follows the same path in the opposite direction.',
      );
      await captureScreenshot(
        tester,
        'release130-search-exit-middle',
        settle: Duration.zero,
      );
      expect(tester.element(find.byType(PlatformSearchLanding)), same(landing));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(container.read(musicSearchControllerProvider).query, isEmpty);
      expect(tester.element(find.byType(PlatformSearchLanding)), same(landing));
      expect(tester.takeException(), isNull);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta13 player entrance never reveals bottom chrome; reverse and drag do',
    (tester) async {
      viewport(tester);
      await prepare();
      production.appRouter.go('/music/recommend');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: production.appRouter,
            theme: buildMestingTheme(musicThemePresetById('classic')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final pushed = production.appRouter.push('/player');
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(container.read(playerChromeRevealProvider).value, 0);
      }
      await tester.pump(const Duration(milliseconds: 500));
      production.appRouter.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(container.read(playerChromeRevealProvider).value, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 500));
      await pushed;
      expect(tester.takeException(), isNull);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'beta13 cold greeting waits for entry, expires once and does not replay on remount',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(tester, const MusicLandingPage());
      expect(find.byKey(const ValueKey('beta13-cold-greeting')), findsNothing);
      await container.read(betaEntryFlowProvider.notifier).finish();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const ValueKey('beta13-cold-greeting')),
        findsOneWidget,
      );
      await captureScreenshot(tester, 'beta13-home-greeting');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('beta13-cold-greeting')), findsNothing);
      await pump(tester, const SizedBox());
      await pump(tester, const MusicLandingPage());
      expect(find.byKey(const ValueKey('beta13-cold-greeting')), findsNothing);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );
  testWidgets(
    'beta13 reviewed companions stay centered and below song text at start middle end',
    (tester) async {
      viewport(tester);
      for (final character in [
        ProgressDecoration.shinchan,
        ProgressDecoration.helloKitty,
        ProgressDecoration.kuromi,
      ]) {
        for (final seconds in [0, 129, 259]) {
          await prepare(position: Duration(seconds: seconds));
          await container
              .read(themeVisualSettingsProvider.notifier)
              .setProgressCharacter(character);
          await container
              .read(themeVisualSettingsProvider.notifier)
              .setProgressStyle(character);
          await pump(tester, const BetaNowPlayingPage(), dark: true);
          final marker = character == ProgressDecoration.shinchan
              ? find.byType(ShinchanProgressWalker)
              : find.byKey(ValueKey('ip-progress-companion-${character.name}'));
          final slider = find.byKey(const ValueKey('playback-seek-slider'));
          final rect = tester.getRect(slider);
          expect(
            tester.getCenter(marker).dx,
            closeTo(rect.left + rect.width * seconds / 259, .1),
          );
          expect(
            tester.getRect(marker).top,
            greaterThan(tester.getRect(find.text(_track.artist).last).bottom),
          );
          if (character != ProgressDecoration.shinchan) {
            expect(tester.getSize(marker), const Size.square(24));
            expect(
              tester.getCenter(marker).dy,
              closeTo(
                rect.center.dy -
                    (character == ProgressDecoration.kuromi ? 3 : 0),
                .1,
              ),
            );
          } else {
            expect(
              tester.getRect(marker).bottom,
              closeTo(rect.center.dy - 3, .1),
              reason: 'the walking feet stand on the top of the 6dp rail',
            );
          }
          await captureScreenshot(
            tester,
            'beta15-companion-${character.name}-$seconds',
          );
          await disposeFixture(tester);
        }
      }
    },
    skip: !DistributionChannel.isBeta,
  );
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(320, 640), 1.6),
    (const Size(844, 390), 1.0),
  ]) {
    testWidgets(
      'beta16 reference lyrics and inline queue ${sample.$1} text ${sample.$2}',
      (tester) async {
        viewport(tester, sample.$1);
        await prepare(queueCount: 12);
        await pump(
          tester,
          const BetaNowPlayingPage(lyricsInitially: true),
          scale: sample.$2,
        );
        expect(find.byIcon(CupertinoIcons.heart), findsOneWidget);
        expect(find.byType(ApplePlayerControls), findsOneWidget);
        final seek = find.byKey(const ValueKey('playback-seek-slider'));
        expect(
          SliderTheme.of(tester.element(seek)).thumbShape,
          same(SliderComponentShape.noThumb),
        );
        expect(tester.widget<Slider>(seek).onChanged, isNotNull);
        expect(find.byType(ImageFiltered), findsWidgets);
        if (sample.$1.height >= 800) {
          await captureScreenshot(tester, 'beta16-immersive-lyrics');
          (container.read(audioOutputProvider.notifier) as _Output).connect(
            '通勤耳机 WH-1000XM5',
          );
          await tester.pump();
          expect(find.text('通勤耳机 WH-1000XM5'), findsOneWidget);
          expect(
            tester
                .widget<PlayerToolbarGlyph>(
                  find.byKey(const ValueKey('player-output-glyph')),
                )
                .headphones,
            true,
          );
          await captureScreenshot(tester, 'beta16-headphones');
        }
        final button = find.byTooltip('播放队列');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
        expect(find.byType(PlayerQueuePanel), findsOneWidget);
        expect(
          find.byKey(const ValueKey('playback-seek-slider')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('system-media-volume')), findsNothing);
        expect(find.byTooltip('上一首'), findsNothing);
        final queueRect = tester.getRect(
          find.byKey(const ValueKey('player-inline-queue')),
        );
        expect(
          queueRect.height,
          greaterThan(sample.$1.height > 800 ? 400 : 40),
        );
        if (sample.$1.height > 800) {
          expect(
            queueRect.overlaps(tester.getRect(find.text('待播歌曲 5'))),
            isTrue,
          );
        }
        expect(find.text('下一段旋律'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('queue-playback-mode')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('player-repeat')), findsNothing);
        await captureScreenshot(
          tester,
          'beta16-inline-queue-${sample.$1.width.toInt()}',
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
        expect(find.byType(PlayerQueuePanel), findsNothing);
        expect(
          find.byKey(const ValueKey('playback-seek-slider')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('system-media-volume')),
          findsOneWidget,
        );
        await disposeFixture(tester);
      },
      skip: !DistributionChannel.isBeta,
    );
  }
  testWidgets(
    'beta16 next lyric crossfades focus without replacing the player transition',
    (tester) async {
      viewport(tester);
      final positions = StreamController<Duration>.broadcast();
      await prepare(positionEvents: positions.stream);
      await pump(tester, const BetaNowPlayingPage(lyricsInitially: true));
      positions.add(const Duration(seconds: 21));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final transition = find
          .ancestor(
            of: find.byType(ImmersiveLyrics),
            matching: find.byType(PlayerContentTransition),
          )
          .first;
      final first = tester.element(transition);
      positions.add(const Duration(seconds: 41));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.element(transition), same(first));
      await captureScreenshot(
        tester,
        'beta16-lyric-between-lines',
        settle: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await disposeFixture(tester);
      await positions.close();
    },
    skip: !DistributionChannel.isBeta,
  );
  testWidgets(
    'beta16 player glass opening and closing keep bounded real geometry',
    (tester) async {
      viewport(tester);
      await prepare();
      await pump(tester, const BetaNowPlayingPage(lyricsInitially: true));
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      await captureScreenshot(
        tester,
        'beta16-more-opening',
        settle: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 450));
      await captureScreenshot(
        tester,
        'beta16-more-open',
        settle: Duration.zero,
      );
      await tester.tapAt(const Offset(8, 350));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await captureScreenshot(
        tester,
        'beta16-more-closing',
        settle: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('待播列表与播放模式'), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );
  testWidgets(
    'beta20 comments from a nested library cover shell chrome through replies',
    (tester) async {
      for (final playlist in [false, true]) {
        viewport(tester);
        await prepare();
        await pump(
          tester,
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Consumer(
                builder: (context, ref, _) => Center(
                  child: TextButton(
                    onPressed: () {
                      if (playlist) {
                        openPlatformPlaylistComments(
                          context,
                          ref,
                          id: 'gid',
                          name: '我的歌单',
                        );
                      } else {
                        openPlatformSongComments(context, ref, _track);
                      }
                    },
                    child: const Text('打开嵌套歌单评论'),
                  ),
                ),
              ),
            ),
          ),
          shell: true,
          location: '/music/library',
        );
        expect(find.byType(BetaMusicBottomBar), findsOneWidget);
        await tester.tap(find.text('打开嵌套歌单评论'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(PlatformCommentComposer), findsOneWidget);
        expect(find.byType(BetaMusicBottomBar), findsNothing);
        expect(find.byType(FloatingPlaybackPill), findsNothing);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(BetaMusicBottomBar).hitTestable(), findsNothing);
        await captureScreenshot(
          tester,
          'beta20-${playlist ? "playlist" : "song"}-comments-keyboard',
        );
        tester.view.resetViewInsets();
        if (!playlist) {
          await tester.tap(find.textContaining('查看回复').first);
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(
            tester
                .widget<PlatformCommentsPage>(find.byType(PlatformCommentsPage))
                .thread,
            isNotNull,
          );
          expect(find.byType(BetaMusicBottomBar), findsNothing);
          Navigator.of(
            tester.element(find.byType(PlatformCommentsPage)),
            rootNavigator: true,
          ).pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }
        Navigator.of(
          tester.element(find.byType(PlatformCommentsPage)),
          rootNavigator: true,
        ).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(BetaMusicBottomBar), findsOneWidget);
        expect(find.text('打开嵌套歌单评论'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await disposeFixture(tester);
      }
    },
    skip: !DistributionChannel.isBeta,
  );

  testWidgets(
    'release151 production router reverses every ordinary route family above retained roots',
    (tester) async {
      viewport(tester);
      await prepare(guest: true);
      await container.read(betaEntryFlowProvider.notifier).finish();
      production.appRouter.go('/music/recommend');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: production.appRouter,
            theme: buildMestingTheme(musicThemePresetById('classic')),
            builder: (_, child) => SystemBackCoordinator(
              canPop: production.appRouter.canPop,
              child: BetaEntryCoordinator(
                backDispatcher: production.appRouter.backButtonDispatcher,
                child: child!,
              ),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 9; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
      }

      Finder tools(String id) => find.byWidgetPredicate(
        (widget) => widget is SongListTools && widget.listId == id,
      );
      await settle();
      for (final root in [
        '/music/recommend',
        '/music',
        '/music/library',
        '/profile',
      ]) {
        production.appRouter.go(root);
        await settle();
        for (final path in [
          '/music?view=daily',
          '/music?view=favorites',
          '/music?view=recent',
          '/music/queue',
          '/music/settings',
          '/music/themes',
          '/profile/edit',
        ]) {
          unawaited(production.appRouter.push<void>(path));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 90));
          // Browser URLs intentionally omit imperative pushes. Match the
          // actual content view, including production's root/query alias.
          final uri = Uri.parse(path);
          final actual = uri.hasQuery
              ? uri.replace(path: '${uri.path}/view').toString()
              : path;
          final incoming = path == '/profile/edit'
              ? find.byType(PlatformProfileEditPage)
              : tools(actual);
          expect(
            tester.getTopLeft(incoming).dx,
            greaterThan(0),
            reason: '$root -> $path',
          );
          expect(
            tester.getTopLeft(tools(root)).dx,
            lessThan(0),
            reason: 'retained parent $root -> $path',
          );
          await settle();
          await tester.binding.handlePopRoute();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          final outgoing = tester.getTopLeft(incoming).dx;
          final returning = tester.getTopLeft(tools(root)).dx;
          expect(
            outgoing,
            greaterThan(0),
            reason: '$path returns toward the right',
          );
          expect(returning, lessThan(0), reason: '$root returns from the left');
          await tester.pump(const Duration(milliseconds: 80));
          expect(tester.getTopLeft(incoming).dx, greaterThan(outgoing));
          expect(tester.getTopLeft(tools(root)).dx, greaterThan(returning));
          await settle();
          expect(
            production.appRouter.routeInformationProvider.value.uri.toString(),
            root,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$root -> $path -> $root',
          );
        }
      }
      await disposeFixture(tester);
    },
    skip: !DistributionChannel.isBeta,
  );
}
