import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// The production dependency drift pins sqlite3. This test override selects a
// modern host library without modifying production loading or the shared SDK.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/open.dart';
import 'package:mesting_music/core/audio/actual_listening_counter.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/persistence/playback_persistence_controller.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_coordinator.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_repository.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_worker.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'support/deterministic_audio_player.dart';

const identity = PlatformSession(
  userId: '12345',
  token: 'synthetic-test-token',
);
const track = Track(
  id: 'kugou_0123456789abcdef0123456789abcdef',
  title: '测试录音',
  artist: '测试歌手',
  album: '测试专辑',
  duration: Duration(minutes: 4),
  audioAsset: 'mesting-platform://kugou/test',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.kugou,
  platformSongId: '7654321',
);
final now = DateTime(2026, 10, 28, 10);

class FakeClock implements ListeningClock {
  int micros = 0;
  @override
  int get elapsedMicroseconds => micros;
  @override
  DateTime get now =>
      DateTime(2026, 10, 28).add(Duration(microseconds: micros));
  void elapse(int ms) => micros += ms * 1000;
}

class FakeGateway implements ListeningPlatformGateway {
  int total = 850, historyWrites = 0, gradeWrites = 0;
  bool confirmHistory = false, confirmGrade = false, failEvents = false;
  List<OfficialHistoryFact> facts = [];
  final events = <Map<String, Object?>>[];
  final historyPayloads = <Map<String, Object>>[];
  final gradePayloads = <Map<String, int>>[];
  @override
  Future<void> prepare(PlatformSession identity) async {}
  @override
  Future<String> resolveRecording(
    PlatformSession identity,
    String trackId,
  ) async => '7654321';
  @override
  Future<List<OfficialHistoryFact>> history(PlatformSession identity) async =>
      facts;
  @override
  Future<bool> uploadHistory(
    PlatformSession identity,
    String recordingId,
    int time,
    int count,
  ) async {
    historyWrites++;
    historyPayloads.add({'id': recordingId, 'time': time, 'pc': count});
    if (confirmHistory) facts = [OfficialHistoryFact(recordingId, count, time)];
    return true;
  }

  @override
  Future<int?> gradeSeconds(PlatformSession identity) async => total;
  @override
  Future<bool> reportGrade(
    PlatformSession identity,
    int target,
    int delta,
  ) async {
    gradeWrites++;
    gradePayloads.add({'baseline': target, 'delta': delta});
    if (confirmGrade) total += delta;
    return true;
  }

  @override
  Future<bool> reportEvent(
    PlatformSession identity,
    Map<String, Object?> payload,
  ) async {
    events.add(payload);
    if (failEvents) throw TimeoutException('synthetic unknown outcome');
    return true;
  }
}

class FakeFeed implements ListeningAudioFeed {
  Track? track;
  ListeningPlaybackSnapshot state = const ListeningPlaybackSnapshot(
    playing: false,
    ready: false,
  );
  bool seeking = false;
  final trackEvents = StreamController<Track?>.broadcast(sync: true);
  final stateEvents = StreamController<ListeningPlaybackSnapshot>.broadcast(
    sync: true,
  );
  final seekEvents = StreamController<bool>.broadcast(sync: true);
  final repeats = StreamController<void>.broadcast(sync: true);
  @override
  Track? get currentTrack => track;
  @override
  ListeningPlaybackSnapshot get currentState => state;
  @override
  bool get isSeeking => seeking;
  @override
  Stream<Track?> get tracks => trackEvents.stream;
  @override
  Stream<ListeningPlaybackSnapshot> get states => stateEvents.stream;
  @override
  Stream<bool> get seeks => seekEvents.stream;
  @override
  Stream<void> get repeatBoundaries => repeats.stream;
  void setTrack(Track? next) {
    track = next;
    trackEvents.add(next);
  }

  void setState(bool playing, bool ready, {double speed = 1}) {
    state = ListeningPlaybackSnapshot(
      playing: playing,
      ready: ready,
      speed: speed,
    );
    stateEvents.add(state);
  }

  void seek(bool value) {
    seeking = value;
    seekEvents.add(value);
  }

  Future<void> close() async {
    await trackEvents.close();
    await stateEvents.close();
    await seekEvents.close();
    await repeats.close();
  }
}

class LocalServer implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:4567');
}

const localTrack = Track(
  id: 'local-file',
  title: '文件',
  artist: '',
  album: '',
  duration: Duration(minutes: 3),
  audioAsset: 'content://media/external/audio/media/17',
  coverAsset: 'file:///synthetic-cover.jpg',
  lyricsAsset: '',
);

class SeekingPlayer extends DeterministicAudioPlayer {
  Completer<void>? pendingSeek;
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    at = position ?? Duration.zero;
    await pendingSeek?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final dll = const String.fromEnvironment(
      'SQLITE3_TEST_DLL',
      defaultValue: '',
    );
    if (Platform.isWindows && dll.isNotEmpty) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dll));
    }
  });

  test(
    'actual heard time excludes pause, buffering and seek, ignores 2x media distance',
    () {
      final clock = FakeClock();
      final counter = ActualListeningCounter(clock);
      clock.elapse(1000);
      expect(counter.sample(), 0);
      counter.update(playing: true, ready: true);
      clock.elapse(5000);
      counter.update(ready: false);
      clock.elapse(3000);
      counter.update(ready: true, speed: 2);
      clock.elapse(5000);
      counter.update(seeking: true);
      clock.elapse(2000);
      counter.update(seeking: false);
      clock.elapse(500);
      counter.update(playing: false);
      clock.elapse(10000);
      expect(counter.sample(), 10500);
    },
  );

  group('durable account journal', () {
    late AppDatabase database;
    late ListeningSyncStore store;
    late FakeGateway gateway;
    late ListeningSyncWorker worker;
    PlatformSession? current;
    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      store = ListeningSyncStore(database);
      gateway = FakeGateway();
      current = identity;
      worker = ListeningSyncWorker(
        store: store,
        gateway: gateway,
        identity: identity,
        currentIdentity: () => current,
        now: () => now,
      );
    });
    tearDown(() async {
      worker.dispose();
      await database.close();
    });
    Future<void> put(
      String id,
      String kind,
      Map<String, Object?> payload, {
      ListeningSyncState state = ListeningSyncState.queued,
    }) => store.put(
      owner: 'kugou:12345',
      id: id,
      kind: kind,
      payload: payload,
      now: now,
      state: state,
    );

    test(
      'upgrade imports old songs once, never converts the old 625 minutes into a new delta',
      () async {
        await database.recordPlayback(
          'kugou:12345',
          track,
          const Duration(minutes: 625),
        );
        await database.recordPlayback(
          'kugou:other',
          track,
          const Duration(minutes: 9),
        );
        await store.bootstrapHistory('kugou:12345', now);
        await store.bootstrapHistory('kugou:12345', now);
        final entries = await store.entries('kugou:12345');
        expect(entries.where((e) => e.kind == 'history'), hasLength(1));
        expect(
          entries.where((e) => e.kind == 'grade' || e.kind == 'cscc'),
          isEmpty,
        );
        expect(
          entries.singleWhere((e) => e.kind == 'history').number('playCount'),
          1,
        );
        expect(await store.entries('kugou:other'), isEmpty);
        final history = await (database.select(
          database.playbackHistories,
        )..where((r) => r.ownerId.equals('kugou:12345'))).get();
        expect(history.single.totalPlayedMs, 625 * 60 * 1000);
      },
    );

    test(
      'history acceptance stays distinct from official readback and never blindly retries',
      () async {
        await put('history:one', 'history', {
          'recordingId': '7654321',
          'time': 123456,
          'playCount': 3,
        });
        await worker.flush();
        await worker.flush();
        expect(gateway.historyWrites, 1);
        expect((await store.watchSummary('kugou:12345').first).accepted, 1);
        expect(
          (await store.entry('kugou:12345', 'history:one'))!.state,
          ListeningSyncState.accepted,
        );
        gateway.facts = const [OfficialHistoryFact('7654321', 3, 123456)];
        await worker.flush();
        expect(
          (await store.entry('kugou:12345', 'history:one'))!.state,
          ListeningSyncState.verified,
        );
        expect(gateway.historyWrites, 1);
        expect((await store.watchSummary('kugou:12345').first).verified, 1);
      },
    );

    test(
      'CSCC timeout is unknown and never replays; stale starts are not fabricated later',
      () async {
        gateway.failEvents = true;
        worker.registerLiveSegment('live');
        await put('cscc:start:live', 'cscc', {
          'segmentId': 'live',
          'event': 'start',
          'recordingId': '7654321',
        });
        await put('cscc:start:old', 'cscc', {
          'segmentId': 'old',
          'event': 'start',
          'recordingId': '7654321',
        });
        await worker.flush();
        await worker.flush();
        expect(gateway.events, hasLength(1));
        expect(
          (await store.entry('kugou:12345', 'cscc:start:live'))!.state,
          ListeningSyncState.unknown,
        );
        expect(
          (await store.entry('kugou:12345', 'cscc:start:old'))!.state,
          ListeningSyncState.interrupted,
        );
      },
    );

    test(
      'unchanged official duration is not verified, later deltas wait without repeating an uncertain write',
      () async {
        await put('grade:first', 'grade', {'heardMs': 1500});
        await worker.flush();
        expect(gateway.gradeWrites, 1);
        expect(gateway.gradePayloads.single, {'baseline': 850, 'delta': 1});
        expect(
          (await store.entry('kugou:12345', 'grade:first'))!.state,
          ListeningSyncState.accepted,
        );
        await put('grade:next', 'grade', {'heardMs': 2500});
        await worker.flush();
        expect(gateway.gradeWrites, 1);
        gateway.total = 851;
        gateway.confirmGrade = true;
        await worker.flush();
        expect(gateway.gradeWrites, 2);
        expect(gateway.gradePayloads.last, {'baseline': 851, 'delta': 3});
        expect(gateway.total, 854);
        expect(
          (await store.entry('kugou:12345', 'grade:first'))!.state,
          ListeningSyncState.verified,
        );
        await worker.flush();
        expect(gateway.gradeWrites, 2);
      },
    );

    test(
      'crash recovery allocates only checkpointed milliseconds and is idempotent',
      () async {
        await put('segment:crash', 'segment', {
          'trackId': track.id,
          'recordingId': '7654321',
          'instanceId': 'one',
          'heardMs': 62500,
          'allocatedMs': 60000,
          'time': 123456,
        }, state: ListeningSyncState.open);
        await store.recoverInterrupted('kugou:12345', now);
        await store.recoverInterrupted('kugou:12345', now);
        final rows = await store.entries('kugou:12345');
        expect(
          rows.where((e) => e.kind == 'grade').single.number('heardMs'),
          2500,
        );
        expect(rows.where((e) => e.kind == 'cscc'), isEmpty);
      },
    );

    test(
      'account switch prevents pending writes from reaching the next identity',
      () async {
        await put('history:account-a', 'history', {
          'recordingId': '7654321',
          'time': 123456,
          'playCount': 1,
        });
        current = const PlatformSession(userId: 'other', token: 'other');
        await worker.flush();
        expect(gateway.historyWrites, 0);
        expect(
          (await store.entry('kugou:12345', 'history:account-a'))!.state,
          ListeningSyncState.queued,
        );
      },
    );

    test(
      'explicit verification performs read-back only and never drains queued writes',
      () async {
        await put('grade:queued', 'grade', {'heardMs': 5000});
        await put('history:queued', 'history', {
          'recordingId': '7654321',
          'time': 123,
          'playCount': 1,
        });
        worker.registerLiveSegment('queued');
        await put('cscc:queued', 'cscc', {
          'segmentId': 'queued',
          'recordingId': '7654321',
          'event': 'start',
        });
        await worker.verifyPending();
        expect(gateway.gradeWrites, 0);
        expect(gateway.historyWrites, 0);
        expect(gateway.events, isEmpty);
        final rows = await store.entries('kugou:12345');
        expect(rows.every((r) => r.state == ListeningSyncState.queued), isTrue);
      },
    );

    test(
      'coordinator counts actual intervals and excludes a local file from official reporting',
      () async {
        final feed = FakeFeed(), clock = FakeClock();
        final coordinator = ListeningSyncCoordinator(
          feed: feed,
          store: store,
          gateway: gateway,
          currentIdentity: () => current,
          prepareOwner: (_) async {},
          clock: clock,
          automaticTimers: false,
          observeLifecycle: false,
        );
        await coordinator.activate(identity);
        feed.setTrack(track);
        feed.setState(true, true);
        clock.elapse(4000);
        feed.seek(true);
        clock.elapse(5000);
        feed.seek(false);
        clock.elapse(2000);
        feed.setState(true, false);
        clock.elapse(5000);
        feed.setState(true, true, speed: 2);
        clock.elapse(3000);
        feed.setState(false, true);
        await coordinator.settled;
        final segments = await store.entries('kugou:12345', kinds: {'segment'});
        expect(segments.single.number('heardMs'), 9000);
        feed.setTrack(
          const Track(
            id: 'local-file',
            title: '文件',
            artist: '',
            album: '',
            duration: Duration(minutes: 3),
            audioAsset: 'content://media/1',
            coverAsset: '',
            lyricsAsset: '',
          ),
        );
        feed.setState(true, true);
        clock.elapse(10000);
        coordinator.sample();
        await coordinator.settled;
        expect(
          await store.entries('kugou:12345', kinds: {'segment'}),
          hasLength(1),
        );
        feed.setTrack(
          const Track(
            id: 'audiobook_123_1',
            title: '章节',
            artist: '作者',
            album: '听书',
            duration: Duration(minutes: 3),
            audioAsset: 'mesting-audiobook://123/1',
            coverAsset: '',
            lyricsAsset: '',
            source: TrackSource.kugou,
            provider: '酷狗听书',
            platformSongId: '8888',
          ),
        );
        feed.setState(true, true);
        clock.elapse(10000);
        coordinator.sample();
        await coordinator.settled;
        expect(
          await store.entries('kugou:12345', kinds: {'segment'}),
          hasLength(1),
        );
        await coordinator.dispose();
        await feed.close();
      },
    );
  });

  test(
    'local persistence and playback use content URI, real seconds and file notification art',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final clock = FakeClock();
      final player = SeekingPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      final persistence = PlaybackPersistenceController(
        database: db,
        audioHandler: handler,
        listeningClock: clock,
      );
      try {
        await persistence.activateOwner('kugou:12345');
        persistence.start();
        await handler.replaceQueue([localTrack], autoplay: false);
        await db.recordPlayback('kugou:12345', localTrack, Duration.zero);
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(
          (player.sources.single as UriAudioSource).uri,
          Uri.parse(localTrack.audioAsset),
        );
        expect(
          handler.mediaItem.value!.artUri,
          Uri.parse(localTrack.coverAsset),
        );
        handler.playbackState.add(
          PlaybackState(
            playing: true,
            processingState: AudioProcessingState.ready,
            speed: 2,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        clock.elapse(5000);
        player.pendingSeek = Completer<void>();
        final seek = handler.seek(const Duration(seconds: 90));
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        clock.elapse(3000);
        player.pendingSeek!.complete();
        await seek;
        clock.elapse(2000);
        handler.playbackState.add(
          PlaybackState(
            playing: true,
            processingState: AudioProcessingState.buffering,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        clock.elapse(4000);
        handler.playbackState.add(
          PlaybackState(
            playing: false,
            processingState: AudioProcessingState.ready,
          ),
        );
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        await persistence.dispose();
        final row = (await db.select(db.playbackHistories).get()).single;
        expect(row.totalPlayedMs, 7000);
      } finally {
        await handler.debugDispose();
        await db.close();
      }
    },
  );

  test(
    'version 6 migrates additively to 7 and retains old local duration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting-sync-migration-',
      );
      final file = File('${directory.path}/library.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.recordPlayback(
          'kugou:12345',
          track,
          const Duration(minutes: 625),
        );
        await db.customStatement('DROP TABLE platform_listening_outboxes');
        await db.customStatement('PRAGMA user_version = 6');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final store = ListeningSyncStore(db);
        await store.bootstrapHistory('kugou:12345', now);
        expect(
          await store.entries('kugou:12345', kinds: {'history'}),
          hasLength(1),
        );
        final rows = await (db.select(
          db.playbackHistories,
        )..where((r) => r.ownerId.equals('kugou:12345'))).get();
        expect(rows.single.totalPlayedMs, 625 * 60 * 1000);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'reporting contracts bind expected identity, registered UUID and real device fields',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'status': 1,
            'data': request.url.path == '/register/dev'
                ? {'dfid': 'synthetic-dfid'}
                : {'d_sec': 850},
          }),
          200,
        );
      });
      final api = MusicPlatformApi(server: LocalServer(), client: client)
        ..session = identity;
      final repository = KugouListeningRepository(
        api,
        uuidLoader: () async => 'a' * 32,
        deviceLoader: () async =>
            const ListeningDeviceInfo('synthetic-model', '15', 1080, 2400),
      );
      await repository.prepare(identity);
      expect(await repository.gradeSeconds(identity), 850);
      await repository.reportGrade(identity, 850, 5);
      await repository.reportEvent(identity, {
        'event': 'end',
        'recordingId': '7654321',
        'heardMs': 5000,
        'reason': '暂停或停止',
      });
      expect(requests[1].url.queryParameters['uuid'], 'a' * 32);
      expect(requests[2].url.queryParameters['diff_sec'], '5');
      expect(requests[2].url.queryParameters['d_sec'], '850');
      expect(
        requests[3].url.queryParameters['device_model'],
        'synthetic-model',
      );
      expect(requests[3].url.queryParameters['duration'], '5000');
      expect(requests[3].url.queryParameters['state'], '中断播放');
      expect(
        requests.every(
          (r) => r.headers['authorization']!.contains('userid=12345'),
        ),
        isTrue,
      );
      api.session = null;
      await expectLater(
        repository.uploadHistory(identity, '7654321', 123456, 1),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(requests, hasLength(4));
      client.close();
    },
  );

  test(
    'business status and duplicate normalization do not imply actual booking',
    () {
      expect(
        KugouListeningRepository.businessAccepted({
          'status': 1,
          'duplicate': true,
        }),
        isFalse,
      );
      expect(
        KugouListeningRepository.businessAccepted({
          'status': 1,
          'error_code': 130012,
        }),
        isFalse,
      );
      final facts = KugouListeningRepository.parseHistory({
        'data': {
          'songs': [
            {'mxid': 7654321, 'pc': 3, 'ot': 123456},
          ],
        },
      });
      expect(facts.single.playCount, 3);
      expect(facts.single.timeSeconds, 123456);
    },
  );
}
