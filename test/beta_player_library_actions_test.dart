import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
import 'package:mesting_music/core/platform/lyrics_overlay_bridge.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/lyrics/presentation/lyrics_overlay_coordinator.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_session_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/player/presentation/now_playing_page.dart';
import 'package:mesting_music/features/themes/app_theme.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';
import 'package:mesting_music/shared/models/track.dart';

const _track = Track(
  id: 'kugou_HASH',
  title: '测试歌曲',
  artist: '歌手',
  album: '',
  duration: Duration(minutes: 3),
  source: TrackSource.kugou,
  audioAsset: 'https://media.example/song.mp3',
  coverAsset: '',
  lyricsAsset: '',
);

class _Handler extends MestingAudioHandler {
  _Handler() : super(tracks: []);
}

class _Store implements PlatformSessionStore {
  @override
  Future<PlatformSession?> read() async =>
      const PlatformSession(userId: '7', token: 'token');
  @override
  Future<void> write(PlatformSession session) async {}
  @override
  Future<void> clear() async {}
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

class _Library extends LibraryRepository {
  _Library(super.database) : super(ownerId: 'kugou:7');
  int toggles = 0;
  @override
  Future<bool> toggleFavorite(Track track) async {
    toggles++;
    return true;
  }
}

class _Overlay extends LyricsOverlayController {
  @override
  LyricsOverlaySettings build() => const LyricsOverlaySettings();
}

void main() {
  testWidgets(
    'Kugou player and notification favorites target the current library without Mesting login',
    (tester) async {
      // Use a phone viewport because the classic record player lays out for
      // portrait screens; Flutter's desktop-sized default is not this fixture.
      tester.view.physicalSize = const Size(390, 873);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final database = AppDatabase(NativeDatabase.memory());
      final library = _Library(database);
      final handler = _Handler();
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authRepositoryProvider.overrideWithValue(
            const UnconfiguredAuthRepository(),
          ),
          platformSessionStoreProvider.overrideWithValue(_Store()),
          musicPlatformApiProvider.overrideWithValue(
            MusicPlatformApi(
              server: _Server(),
              client: MockClient((_) async => http.Response('{}', 200)),
            ),
          ),
          libraryRepositoryProvider.overrideWithValue(library),
          audioHandlerProvider.overrideWithValue(handler),
          currentTrackProvider.overrideWithValue(_track),
          favoriteTrackIdsProvider.overrideWithValue({_track.id}),
          playbackStateProvider.overrideWith(
            (ref) => Stream.value(
              PlaybackState(processingState: AudioProcessingState.ready),
            ),
          ),
          positionProvider.overrideWith((ref) => Stream.value(Duration.zero)),
          durationProvider.overrideWith((ref) => Stream.value(_track.duration)),
          lyricsOverlayProvider.overrideWith(_Overlay.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildMestingTheme(musicThemePresetById('classic')),
            home: const NowPlayingPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('分享给好友'), findsNothing);
      expect(
        find.byKey(const ValueKey('listen-together-player-entry')),
        findsNothing,
      );
      // Beta.16 moved comments into More; the footer now toggles lyrics.
      expect(find.byTooltip('显示或隐藏歌词'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('favorite-button-${_track.id}')));
      await tester.pump();
      expect(library.toggles, 1);
      expect(container.read(currentUserProvider), null);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: LyricsOverlayCoordinator(child: Text('通知收藏测试')),
            ),
          ),
        ),
      );
      await tester.pump();
      await handler.customAction(
        MestingAudioHandler.notificationToggleFavoriteAction,
      );
      await tester.pump();
      await tester.pump();
      expect(library.toggles, 2);
      expect(handler.mediaItem.value, null);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !DistributionChannel.isBeta,
  );
}
