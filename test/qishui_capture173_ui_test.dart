import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/experience/presentation/beta_music_shell.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/lyrics/lyrics_providers.dart';
import 'package:mesting_music/features/lyrics/domain/lyrics_document.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_rewards_provider.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_artist_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_pages.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_player_navigation.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playlist_cover_page.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_search_catalog.dart';
import 'package:mesting_music/shared/widgets/beta_bottom_search.dart';
import 'qishui_appearance172_ui_test.dart'
    show AuditMusic172, AuditLibrary172, AuditPlayer172, AuditAuth172;
import 'qishui_protocol_test.dart' show sodaSession, fixtureJson;
import 'qishui_ui168_test.dart' show song168;
import 'qishui_ui_test.dart' show FixtureAccount;
import 'qishui_search173_test.dart' show searchResponse173, searchTrack173;
import 'support/release_152_qa.dart' show theme152;
import 'support/release_147_qa.dart' show load147IconFonts;

const capture173 = bool.fromEnvironment('CAPTURE_173');
const capture173Directory = String.fromEnvironment(
  'UI_CAPTURE_173_DIR',
  defaultValue: '.codex-artifacts/2026-11-07-release173/ui',
);
void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!capture173) return;
    await load147IconFonts();
    for (final name in [
      'SodaQA173',
      'Roboto',
      'Ahem',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      await (FontLoader(name)..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  for (final dark in [false, true]) {
    for (final surface in [
      'music',
      'lyrics',
      'songs',
      'singers',
      'artist',
      'cover',
    ]) {
      testWidgets('$surface rendered dark=$dark', (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({
          // Match the background provider to the Material theme as production
          // does. A dark Theme alone leaves the retained shell on light art.
          'music_theme_preset': dark ? 'classic-dark' : 'classic',
        });
        final prefs = await SharedPreferences.getInstance();
        final api = QishuiApi(MockClient((_) async => fixtureJson({})))
          ..configure(sodaSession());
        final player = AuditPlayer172();
        final catalog = QishuiSearchCatalog(
          request:
              (
                path, {
                body = const {},
                query = const {},
                get = false,
                abortTrigger,
              }) async {
                if (path.endsWith('/search/artist')) {
                  return searchResponse173(
                    kind: 'artists',
                    rows: [
                      {
                        'entity': {
                          'artist': {
                            'id': '123',
                            'name': '界面测试歌手',
                            'count_tracks': 35,
                          },
                        },
                      },
                    ],
                  );
                }
                if (path.endsWith('/search/track')) {
                  return searchResponse173(
                    rows: [
                      {
                        'entity': {
                          'track_wrapper': {
                            'track': searchTrack173('123', '夜色中的慢歌'),
                          },
                        },
                      },
                    ],
                  );
                }
                if (path.endsWith('/artists/123')) {
                  return {
                    'artist_info': {
                      'id': '123',
                      'name': '界面测试歌手',
                      'count_tracks': 35,
                      'description': '歌手资料与作品列表 · 本地界面测试',
                    },
                  };
                }
                return {
                  'tracks': [searchTrack173('123', '夜色中的慢歌')],
                  'has_more': false,
                };
              },
        );
        final c = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            platformAccountProvider.overrideWith(FixtureAccount.new),
            authControllerProvider.overrideWith(AuditAuth172.new),
            qishuiApiProvider.overrideWithValue(api),
            qishuiNavigationProvider.overrideWithValue(true),
            qishuiRepositoryProvider.overrideWithValue(AuditMusic172(api)),
            qishuiSearchCatalogProvider.overrideWithValue(catalog),
            audioHandlerProvider.overrideWithValue(player),
            libraryRepositoryProvider.overrideWithValue(AuditLibrary172()),
            favoriteTrackIdsProvider.overrideWithValue(<String>{}),
            platformRewardAutomationProvider.overrideWith((_) {}),
            currentTrackProvider.overrideWithValue(song168),
            currentMediaItemProvider.overrideWith(
              (_) => Stream.value(song168.toMediaItem()),
            ),
            positionProvider.overrideWith(
              (_) => Stream.value(const Duration(seconds: 42)),
            ),
            durationProvider.overrideWith(
              (_) => Stream.value(const Duration(seconds: 180)),
            ),
            playbackStateProvider.overrideWith(
              (_) => Stream.value(
                PlaybackState(
                  processingState: AudioProcessingState.ready,
                  playing: true,
                ),
              ),
            ),
            lyricsProvider.overrideWith(
              (_, _) async => LyricsDocument(
                isSynced: true,
                lines: [
                  for (var i = 0; i < 12; i++)
                    LyricsLine(
                      time: Duration(seconds: i * 10),
                      text: '让音乐慢慢经过这个夜晚 · 测试句 $i',
                    ),
                ],
              ),
            ),
            qishuiCoverPhotoPickerProvider.overrideWithValue(
              () async => (await rootBundle.load(
                song168.coverAsset,
              )).buffer.asUint8List(),
            ),
          ],
        );
        final host = BetaBottomSearchHost(
          location: '/search',
          openMusicSearch: () {},
        );
        await c.read(platformAccountProvider.future);
        if (surface == 'lyrics') {
          c.read(qishuiMusicLyricsProvider.notifier).showLyrics();
        }
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          host.dispose();
          c.dispose();
          api.dispose();
        });
        Widget page = switch (surface) {
          'music' || 'lyrics' => const BetaMusicShell(
            location: '/music',
            child: QishuiRootPage(QishuiRoot.music),
          ),
          'artist' => const QishuiArtistPage(
            artist: QishuiArtist(id: '123', name: '界面测试歌手'),
          ),
          'cover' => const QishuiPlaylistCoverPage(
            playlist: QishuiPlaylist('123', '自建歌单 · 夜间收藏', ''),
          ),
          _ => const QishuiSearchPage(),
        };
        var theme = theme152(dark);
        if (capture173) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'SodaQA173'),
            primaryTextTheme: theme.primaryTextTheme.apply(
              fontFamily: 'SodaQA173',
            ),
            listTileTheme: theme.listTileTheme.copyWith(
              titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
                fontFamily: 'SodaQA173',
              ),
              subtitleTextStyle: theme.listTileTheme.subtitleTextStyle
                  ?.copyWith(fontFamily: 'SodaQA173'),
            ),
          );
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: LiquidGlassWidgets.wrap(
              adaptiveQuality: false,
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: BetaBottomSearchScope(host: host, child: child!),
                ),
                home: RepaintBoundary(
                  key: const ValueKey('qa173'),
                  child: page,
                ),
              ),
            ),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 60));
          }
        }

        await settle();
        // Flutter's fake clock does not drive filesystem image decoding.
        // Warm the actual bundled fixture before inspecting the rendered page.
        await tester.runAsync(() async {
          await precacheImage(
            AssetImage(song168.coverAsset),
            tester.element(find.byKey(const ValueKey('qa173'))),
          );
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        await settle();
        if (surface == 'songs' || surface == 'singers') {
          await tester.enterText(
            find.byKey(const ValueKey('qishui-catalog-search-field')),
            '夜晚',
          );
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await settle();
          if (surface == 'singers') {
            await tester.tap(find.text('歌手').last);
            await settle();
          }
          tester.testTextInput.hide();
          await settle();
        }
        if (surface == 'cover') {
          await tester.tap(find.text('从相册选择图片'));
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await settle();
        }
        expect(tester.takeException(), isNull);
        if (capture173) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('qa173')),
            );
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              '$capture173Directory/$surface-${dark ? 'dark' : 'light'}-large.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
