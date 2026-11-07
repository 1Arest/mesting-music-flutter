import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/data/platform_search_repository.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_reads.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/utils/media_uri.dart';
import 'support/deterministic_audio_player.dart';
import 'netease_v116_recovery_test.dart' show localSong, mp3Response;
import 'netease_v115_sources_test.dart' show SourceFixture, TestAccount;
import 'netease_v112_fallback_download_test.dart' show recording, until;

class _DeferredSearch implements PlatformSearchRepository {
  final pending = <String, Completer<PlatformSearchPage>>{};
  @override
  MusicPlatformApi get api =>
      throw UnsupportedError('No network in this fixture');
  @override
  Future<PlatformSearchPage> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) => (pending[query] = Completer<PlatformSearchPage>()).future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<MestingAudioHandler> prepare(DeterministicAudioPlayer player) async {
    final handler = MestingAudioHandler(tracks: [], player: player);
    addTearDown(handler.debugDispose);
    await handler.replaceQueue([localSong('old')]);
    return handler;
  }

  test(
    'selection stops old audio and publishes new identity before lookup finishes',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = await prepare(player);
      final resolved = Completer<Track>();
      handler.configureTrackPlaybackResolver((_) => resolved.future);
      final pending = handler.playSingleTrack(localSong('new'));
      await until(() => handler.mediaItem.value?.id == 'new');
      expect(player.active, false);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.loading,
      );
      expect(handler.playbackState.value.playing, false);
      expect(handler.playbackState.value.updatePosition, Duration.zero);
      resolved.complete(localSong('new'));
      await pending;
      expect(player.active, true);
    },
  );

  test(
    'failed selection stays visible and explicit retry resolves the selected song',
    () async {
      final player = DeterministicAudioPlayer();
      final handler = await prepare(player);
      var attempts = 0;
      handler.configureTrackPlaybackResolver((song) async {
        if (++attempts == 1) throw StateError('synthetic failure');
        return song;
      });
      await expectLater(
        handler.playSingleTrack(localSong('new')),
        throwsStateError,
      );
      expect(handler.mediaItem.value!.id, 'new');
      expect(player.active, false);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.error,
      );
      await handler.play();
      expect(attempts, 2);
      expect(
        player.sources.single.tag,
        isA<MediaItem>().having((m) => m.id, 'selected identity', 'new'),
      );
    },
  );

  test('late lookup failure cannot replace a newer selection', () async {
    final player = DeterministicAudioPlayer();
    final handler = await prepare(player);
    final delayed = Completer<Track>();
    handler.configureTrackPlaybackResolver(
      (song) async => song.id == 'first' ? delayed.future : song,
    );
    final first = handler.playSingleTrack(localSong('first'));
    await until(() => handler.mediaItem.value?.id == 'first');
    await handler.playSingleTrack(localSong('last'));
    delayed.completeError(StateError('late failure'));
    await first;
    expect(handler.mediaItem.value!.id, 'last');
    expect(player.active, true);
    expect(
      handler.playbackState.value.processingState,
      isNot(AudioProcessingState.error),
    );
  });

  test('pause during lookup prevents late autoplay and play retries', () async {
    final player = DeterministicAudioPlayer();
    final handler = await prepare(player);
    final delayed = Completer<Track>();
    var attempts = 0;
    handler.configureTrackPlaybackResolver(
      (song) async => ++attempts == 1 ? delayed.future : song,
    );
    final pending = handler.playSingleTrack(localSong('new'));
    await until(() => handler.mediaItem.value?.id == 'new');
    await handler.pause();
    delayed.complete(localSong('new'));
    await pending;
    expect(player.active, false);
    await handler.play();
    expect(attempts, 2);
    expect(player.active, true);
  });

  test(
    'saved NetEase recording retains its platform identity for offline playback',
    () async {
      final task = AudioDownloadTask(
        id: 'saved',
        owner: 'netease:7',
        track: recording(),
        phase: AudioDownloadPhase.completed,
        uri: 'content://documents/tree/music/document/song.mp3',
      );
      final saved = downloadedPlaybackTrack(task);
      expect(saved.id, recording().id);
      expect(saved.source, TrackSource.netease);
      expect(saved.hasLocalAudio, true);
      expect(saved.isRemote, false);
      final player = DeterministicAudioPlayer();
      final handler = await prepare(player);
      handler.configureTrackPlaybackResolver((track) async {
        if (track.hasLocalAudio) return track;
        throw StateError('network forbidden');
      });
      await handler.replaceQueue([saved]);
      expect(
        player.sources.first.tag,
        isA<MediaItem>().having((m) => m.id, 'id', saved.id),
      );
    },
  );

  test('incomplete download records cannot fall through to an online URL', () {
    expect(
      () => downloadedPlaybackTrack(
        AudioDownloadTask(id: 'x', owner: 'n', track: recording()),
      ),
      throwsException,
    );
    expect(
      () => downloadedPlaybackTrack(
        AudioDownloadTask(
          id: 'x',
          owner: 'n',
          track: recording(),
          phase: AudioDownloadPhase.completed,
          uri: 'https://expired.example/file',
        ),
      ),
      throwsException,
    );
  });

  test(
    'read cursor survives restart while preserving newer incoming messages',
    () async {
      Map<String, int> saved = {};
      final reads = NeteaseMessageReads(
        persist: (value) async {
          saved = value;
        },
      );
      addTearDown(reads.close);
      reads.displayed('friend', DateTime.fromMillisecondsSinceEpoch(100));
      await Future<void>.delayed(Duration.zero);
      final restarted = NeteaseMessageReads(restored: saved);
      addTearDown(restarted.close);
      expect(
        restarted.includes('friend', DateTime.fromMillisecondsSinceEpoch(100)),
        true,
      );
      expect(
        restarted.includes('friend', DateTime.fromMillisecondsSinceEpoch(101)),
        false,
      );
      expect(
        restarted.includes('other', DateTime.fromMillisecondsSinceEpoch(100)),
        false,
      );
      restarted.displayed('friend', DateTime.fromMillisecondsSinceEpoch(90));
      expect(
        restarted.includes('friend', DateTime.fromMillisecondsSinceEpoch(100)),
        true,
      );
    },
  );

  test(
    'forced source probes only its adapter and segregates cached results',
    () async {
      final a = SourceFixture('first');
      final b = SourceFixture('second');
      final resolver = NeteaseFallbackResolver([
        a,
        b,
      ], MockClient((_) async => mp3Response(274)));
      expect(
        await resolver.resolve(
          recording(),
          current: () => true,
          onlySource: 'second',
        ),
        isNotNull,
      );
      expect(a.searches, 0);
      expect(b.searches, 1);
      expect(
        await resolver.resolve(
          recording(),
          current: () => true,
          onlySource: 'missing',
        ),
        isNull,
      );
      expect(a.searches, 0);
    },
  );

  test('artwork normalization upgrades only known public image CDNs', () {
    expect(
      normalizeArtworkUri('http://p1.music.126.net/album.jpg'),
      'https://p1.music.126.net/album.jpg',
    );
    expect(
      normalizeArtworkUri('//p2.music.126.net/album.jpg'),
      'https://p2.music.126.net/album.jpg',
    );
    expect(
      normalizeArtworkUri('http://private.test/image'),
      'http://private.test/image',
    );
    expect(normalizeArtworkUri('assets/cover.webp'), 'assets/cover.webp');
  });

  testWidgets(
    'IME commit debounces requests while preserving displayed results',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final search = _DeferredSearch();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          platformAccountProvider.overrideWith(TestAccount.new),
          platformSearchRepositoryProvider.overrideWithValue(search),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      final controller = container.read(musicSearchControllerProvider.notifier);
      final initial = controller.submit('旧词');
      search.pending['旧词']!.complete(
        PlatformSearchPage([recording()], 1, false),
      );
      await initial;
      controller.setQuery('xz', composing: true);
      await tester.pump(const Duration(seconds: 1));
      expect(search.pending.keys, ['旧词']);
      expect(container.read(musicSearchControllerProvider).hasResults, true);
      expect(container.read(musicSearchControllerProvider).isLoading, false);
      controller.setQuery('薛之谦');
      await tester.pump(const Duration(milliseconds: 300));
      controller.setQuery('薛之');
      await tester.pump(const Duration(milliseconds: 449));
      expect(search.pending.keys, ['旧词']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(search.pending.keys, ['旧词', '薛之']);
      expect(container.read(musicSearchControllerProvider).hasResults, true);
      expect(container.read(musicSearchControllerProvider).isLoading, true);
      controller.setQuery('薛');
      await tester.pump(const Duration(milliseconds: 450));
      search.pending['薛']!.complete(
        PlatformSearchPage([recording(id: 'netease_9')], 1, false),
      );
      await tester.pump();
      search.pending['薛之']!.complete(
        PlatformSearchPage([recording(id: 'netease_8')], 1, false),
      );
      await tester.pump();
      expect(
        container.read(musicSearchControllerProvider).onlineTracks.single.id,
        'netease_9',
      );
      controller.setQuery('');
      expect(container.read(musicSearchControllerProvider).hasResults, false);
    },
  );
}
