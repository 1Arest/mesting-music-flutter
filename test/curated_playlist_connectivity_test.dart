import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/discover/discover_providers.dart';
import 'package:mesting_music/features/discover/domain/curated_playlist_tracks.dart';
import 'package:mesting_music/features/discover/presentation/curated_playlist_page.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/search/data/music_search_repository.dart';
import 'package:mesting_music/features/search/domain/music_source.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/themes/mesting_palette.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_tracks.dart';

const _onlineTrack = Track(
  id: 'audius_online_test',
  title: 'Online Track',
  artist: 'Remote Artist',
  album: 'Audius',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/stream',
  coverAsset: 'https://example.com/cover.jpg',
  lyricsAsset: '',
  source: TrackSource.audius,
  provider: 'Audius',
);

void main() {
  test('策划歌单断网且无内置音乐时显示空结果与网络提示', () async {
    final repository = MusicSearchRepository(
      localTracks: testTracks,
      sources: const <MusicSource>[_OfflineSource()],
    );
    final container = ProviderContainer(
      overrides: [musicSearchRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      curatedPlaylistTracksProvider('featured-1').future,
    );

    expect(result.source, CuratedPlaylistTrackSource.unavailable);
    expect(result.tracks, isEmpty);
    expect(result.warnings.single, contains('在线曲库'));
  });

  test('策划歌单联网成功时只显示在线音乐', () async {
    final repository = MusicSearchRepository(
      localTracks: testTracks,
      sources: const <MusicSource>[_OnlineSource()],
    );
    final container = ProviderContainer(
      overrides: [musicSearchRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      curatedPlaylistTracksProvider('featured-1').future,
    );

    expect(result.source, CuratedPlaylistTrackSource.online);
    expect(result.tracks, const <Track>[_onlineTrack]);
    expect(result.tracks.every((track) => track.isRemote), isTrue);
  });

  testWidgets('策划歌单手机端头图保持正方形并等比裁切', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final audioHandler = _TestAudioHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(audioHandler),
          favoriteTracksProvider.overrideWith(
            (ref) => Stream.value(const <Track>[]),
          ),
          curatedPlaylistTracksProvider('featured-1').overrideWith(
            (ref) async => CuratedPlaylistTracks(
              tracks: const <Track>[_onlineTrack],
              source: CuratedPlaylistTrackSource.online,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: CuratedPlaylistPage(playlistId: 'featured-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cover = find.byKey(const ValueKey('curated-playlist-cover-ratio'));
    final coverSize = tester.getSize(cover);
    expect(coverSize.width, closeTo(coverSize.height, .01));
    final artwork = tester.widget<ArtworkImage>(
      find.descendant(of: cover, matching: find.byType(ArtworkImage)),
    );
    expect(artwork.fit, BoxFit.cover);
    expect(artwork.decodeWidth, artwork.decodeHeight);
    final playAll = tester.widget<FilledButton>(
      find.byKey(const ValueKey('curated-playlist-play-all')),
    );
    expect(
      playAll.style?.backgroundColor?.resolve(const <WidgetState>{}),
      MestingPalette.heart,
    );
    expect(
      playAll.style?.foregroundColor?.resolve(const <WidgetState>{}),
      Colors.white,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('在线歌曲当前播放状态使用心动红标题与均衡器', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final audioHandler = _TestAudioHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(audioHandler),
          favoriteTracksProvider.overrideWith(
            (ref) => Stream.value(const <Track>[]),
          ),
          curatedPlaylistTracksProvider('featured-1').overrideWith(
            (ref) async => CuratedPlaylistTracks(
              tracks: const <Track>[_onlineTrack],
              source: CuratedPlaylistTrackSource.online,
            ),
          ),
          currentMediaItemProvider.overrideWith(
            (ref) => Stream.value(_onlineTrack.toMediaItem()),
          ),
          playbackStateProvider.overrideWith(
            (ref) => Stream.value(PlaybackState(playing: true)),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CuratedPlaylistPage(playlistId: 'featured-1')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(
        const ValueKey('curated-playlist-queue-add-audius_online_test'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('curated-playlist-playing-equalizer-audius_online_test'),
      ),
      findsOneWidget,
    );
    final title = tester.widget<Text>(find.text('Online Track'));
    expect(title.style?.color, MestingPalette.heart);
  });

  testWidgets('在线歌曲加号按钮直接加入播放列表', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final idleHandler = _TestAudioHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(idleHandler),
          favoriteTracksProvider.overrideWith(
            (ref) => Stream.value(const <Track>[]),
          ),
          curatedPlaylistTracksProvider('featured-1').overrideWith(
            (ref) async => CuratedPlaylistTracks(
              tracks: const <Track>[_onlineTrack],
              source: CuratedPlaylistTrackSource.online,
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CuratedPlaylistPage(playlistId: 'featured-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addButton = find.byKey(
      const ValueKey('curated-playlist-queue-add-audius_online_test'),
    );
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pump();
    await tester.pump();
    expect(idleHandler.appendedTrack, _onlineTrack);
    expect(find.text('已添加'), findsOneWidget);
  });

  testWidgets('恢复到单独策划歌单时系统返回会回到发现页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final audioHandler = _TestAudioHandler();
    final router = GoRouter(
      initialLocation: '/music/discover/featured-1',
      routes: [
        GoRoute(
          path: '/music/discover',
          builder: (_, _) => const Scaffold(body: Text('发现歌单列表')),
        ),
        GoRoute(
          path: '/music/discover/:playlistId',
          builder: (_, state) => Scaffold(
            body: CuratedPlaylistPage(
              playlistId: state.pathParameters['playlistId']!,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(audioHandler),
          favoriteTracksProvider.overrideWith(
            (ref) => Stream.value(const <Track>[]),
          ),
          curatedPlaylistTracksProvider('featured-1').overrideWith(
            (ref) async => CuratedPlaylistTracks(
              tracks: const <Track>[_onlineTrack],
              source: CuratedPlaylistTrackSource.online,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('curated-playlist-play-all')), findsOne);
    expect(router.canPop(), isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('发现歌单列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _OfflineSource implements MusicSource {
  const _OfflineSource();

  @override
  String get id => 'offline';

  @override
  String get label => '离线测试源';

  @override
  bool get isConfigured => true;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) {
    throw const MusicSourceException(sourceLabel: '离线测试源', message: '无法连接网络');
  }
}

class _OnlineSource implements MusicSource {
  const _OnlineSource();

  @override
  String get id => 'online';

  @override
  String get label => '在线测试源';

  @override
  bool get isConfigured => true;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    return const <Track>[_onlineTrack];
  }
}

class _TestAudioHandler extends MestingAudioHandler {
  _TestAudioHandler() : super(tracks: const <Track>[]);

  Track? appendedTrack;

  @override
  Future<bool> appendToUpcomingQueue(Track track) async {
    appendedTrack = track;
    return true;
  }
}
