import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/search/presentation/apple_search_results.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/playback_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/download_failure.dart';
import 'package:mesting_music/features/library/data/library_repository.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/playlists/playlist_audit.dart';
import 'package:mesting_music/features/playlists/presentation/playlist_audit_page.dart';
import 'package:mesting_music/features/search/domain/song_version_filter.dart';
import 'package:mesting_music/features/settings/presentation/playback_settings_page.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/shared/models/song_search_facts.dart';
import 'support/ui_fix_capture.dart';

Track tune(
  String id, {
  String title = '歌',
  String artist = '歌手',
  int seconds = 200,
  String audio = '',
}) => Track(
  id: id,
  title: title,
  artist: artist,
  album: '',
  duration: Duration(seconds: seconds),
  audioAsset: audio,
  coverAsset: '',
  lyricsAsset: '',
);

class LocalLibrary extends Fake implements LibraryRepository {
  LocalLibrary(this.rows);
  List<Track> rows;
  final removed = <String>[];
  @override
  String get ownerId => 'local';
  @override
  Stream<List<Track>> watchPlaylistTracks(String playlistId) =>
      Stream.value(rows);
  @override
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    removed.add(trackId);
    rows = rows.where((t) => t.id != trackId).toList();
  }
}

class SearchFixture extends MusicSearchController {
  @override
  MusicSearchState build() => const MusicSearchState(query: 'test');
}

void main() {
  setUpAll(initializeUiFixCapture);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('playback defaults, clamping and fast writes survive restart', () async {
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    final initial = container.read(playbackPreferencesProvider);
    expect(initial.prepareNext, isTrue);
    expect(initial.balance, isFalse);
    expect(initial.crossfade, isFalse);
    expect(initial.seconds, 3);
    await Future.wait([
      container.read(playbackPreferencesProvider.notifier).change({
        'seconds': 6,
      }),
      container.read(playbackPreferencesProvider.notifier).change({
        'balance': true,
      }),
    ]);
    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(playbackPreferencesProvider).seconds, 6);
    expect(restored.read(playbackPreferencesProvider).balance, isTrue);
    expect(PlaybackPreferences.fromJson({'seconds': 50}).seconds, 6);
  });
  test('recording version never assumes missing metadata is original', () {
    expect(
      recordingVersion(tune('concert', title: '演唱会'), null),
      SongVersionFilter.unknown,
    );
    expect(
      recordingVersion(tune('cover-title', title: 'Cover Me'), null),
      SongVersionFilter.unknown,
    );
    expect(
      recordingVersion(tune('a', title: 'Alive'), null),
      SongVersionFilter.unknown,
    );
    expect(
      recordingVersion(
        tune('b', title: '歌 (Live)'),
        const SongSearchFacts(kind: SearchRecordingKind.original),
      ),
      SongVersionFilter.live,
    );
    expect(
      recordingVersion(tune('c', title: '歌（伴奏）'), null),
      SongVersionFilter.instrumental,
    );
    expect(
      recordingVersion(
        tune('d'),
        const SongSearchFacts(kind: SearchRecordingKind.cover),
      ),
      SongVersionFilter.cover,
    );
    expect(
      recordingVersion(
        tune('e'),
        const SongSearchFacts(workRelation: SearchWorkRelation.original),
      ),
      SongVersionFilter.original,
    );
  });
  test('audit separates versions, artists and unknown durations', () {
    final result = duplicateRecordings([
      tune('a'),
      tune('b'),
      tune('live', title: '歌 (Live)'),
      tune('cover', artist: '另一歌手'),
      tune('unknown', seconds: 0),
    ]);
    expect(result, hasLength(1));
    expect(result.single.map((t) => t.id), ['a', 'b']);
  });
  test(
    'bulk operations isolate owner and leave saving/completed tasks alone',
    () async {
      var owner = 'mine';
      final directory = await Directory.systemTemp.createTemp(
        'batch-download-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final blocker = Completer<String>();
      var publishes = 0, writes = 0;
      final manager = AudioDownloadManager(
        client: MockClient(
          (_) async => http.Response.bytes([73, 68, 51, 0, 0], 200),
        ),
        resolve: (_) => blocker.future,
        publish: (_, _, _, _) async {
          publishes++;
          return 'file://saved';
        },
        currentOwner: () => owner,
        directory: () async => directory,
        persist: (_) async {
          writes++;
        },
        restored: [
          AudioDownloadTask(id: 'queued', owner: 'mine', track: tune('a')),
          AudioDownloadTask(id: 'other', owner: 'other', track: tune('b')),
          AudioDownloadTask(
            id: 'saved',
            owner: 'mine',
            track: tune('c'),
            phase: AudioDownloadPhase.completed,
          ),
          AudioDownloadTask(
            id: 'saving',
            owner: 'mine',
            track: tune('d'),
            phase: AudioDownloadPhase.saving,
          ),
        ],
      );
      addTearDown(manager.dispose);
      manager.manageBatch('pause');
      await Future<void>.delayed(Duration.zero);
      expect(manager.taskById('queued')!.phase, AudioDownloadPhase.paused);
      expect(manager.taskById('other')!.phase, AudioDownloadPhase.queued);
      expect(manager.taskById('saving')!.phase, AudioDownloadPhase.saving);
      expect(manager.taskById('saved')!.phase, AudioDownloadPhase.completed);
      expect(writes, 1);
      manager.manageBatch('resume');
      await Future<void>.delayed(Duration.zero);
      manager.manageBatch('pause');
      owner = 'other';
      blocker.complete('https://invalid.example/audio.mp3');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(publishes, 0);
    },
  );
  test(
    'audit restrictions require saved catalogue evidence, never an empty URL alone',
    () {
      final unresolved = Track.fromJson({
        ...tune('network').toJson(),
        'source': 'netease',
        'availabilityMessage': '点击获取网易云播放地址',
      });
      expect(hasRecordedRestriction(unresolved), isFalse);
      expect(
        hasRecordedRestriction(
          unresolved.copyWith(availabilityMessage: '网络超时，请登录重试'),
        ),
        isFalse,
      );
      expect(
        hasRecordedRestriction(
          unresolved.copyWith(availabilityMessage: '该歌曲受会员、地区或版权限制'),
        ),
        isTrue,
      );
      expect(
        hasRecordedRestriction(
          unresolved.copyWith(
            audioAsset: 'https://audio.example/preview',
            isPreview: true,
          ),
        ),
        isFalse,
      );
    },
  );
  test('failure grouping preserves uncertainty and login state', () {
    expect(
      classifyDownloadFailure('SocketException timeout'),
      DownloadFailure.network,
    );
    expect(classifyDownloadFailure('ENOSPC no space'), DownloadFailure.storage);
    expect(classifyDownloadFailure('登录过期 401'), DownloadFailure.authorization);
    expect(classifyDownloadFailure('音源已下架'), DownloadFailure.source);
    expect(
      classifyDownloadFailure('unknown decoder error'),
      DownloadFailure.other,
    );
  });
  testWidgets(
    'search version selection filters rows and resets with a new query',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final tracks = [
        tune('unknown', title: '普通版本'),
        tune('live', title: '歌曲 (Live)'),
      ];
      Widget host(String query) => ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          musicSearchControllerProvider.overrideWith(SearchFixture.new),
          currentTrackProvider.overrideWithValue(tune('active')),
          favoriteTrackIdsProvider.overrideWithValue({}),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AppleSearchResults(
              state: MusicSearchState(query: query, onlineTracks: tracks),
              controller: scroll,
            ),
          ),
        ),
      );
      await tester.pumpWidget(host('first'));
      await tester.pumpAndSettle();
      expect(find.text('普通版本'), findsOneWidget);
      expect(find.text('歌曲 (Live)'), findsOneWidget);
      await tester.tap(find.text('全部版本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('现场'));
      await tester.pumpAndSettle();
      expect(find.text('普通版本'), findsNothing);
      expect(find.text('歌曲 (Live)'), findsOneWidget);
      await tester.pumpWidget(host('second'));
      await tester.pumpAndSettle();
      expect(find.text('全部版本'), findsOneWidget);
      expect(find.text('普通版本'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final dark in [false, true]) {
    testWidgets('Apple playback settings fit large text dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const RepaintBoundary(
              key: uiFixCaptureKey,
              child: PlaybackSettingsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoSwitch>(find.byKey(const ValueKey('prepareNext')))
            .value,
        isTrue,
      );
      final fade = find.byKey(const ValueKey('crossfade'));
      await tester.ensureVisible(fade);
      await tester.pumpAndSettle();
      await tester.tap(fade);
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('crossfade-seconds'));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      expect(tester.widget<CupertinoSlider>(slider).value, 3);
      await captureUiFix(tester, 'playback-settings-$dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'playlist audit confirms removal of relation only, keeps versions',
    (tester) async {
      final missing = tune(
        'missing',
        audio: 'file:///nonexistent/music-test-file.mp3',
      );
      final preferences = await SharedPreferences.getInstance();
      final repository = LocalLibrary([
        tune('a'),
        tune('b'),
        tune('live', title: '歌 (Live)'),
        missing,
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryRepositoryProvider.overrideWithValue(repository),
            sharedPreferencesProvider.overrideWithValue(preferences),
          ],
          child: const MaterialApp(home: PlaylistAuditPage(playlistId: 'list')),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.text('疑似重复 · 1 组'), findsOneWidget);
      expect(find.text('本地文件不可读取 · 1 首'), findsOneWidget);
      final checks = find.byType(CupertinoCheckbox);
      await tester.tap(checks.first);
      await tester.pumpAndSettle();
      final remove = find.text('移除所选 1 首');
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(repository.removed, isEmpty);
      await tester.tap(find.text('移除所选歌曲'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(repository.removed, hasLength(1));
      expect(repository.rows.any((t) => t.id == 'live'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
