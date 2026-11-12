import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_history_reporter.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_history_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_write_journal.dart';
import 'package:mesting_music/shared/models/track.dart';

import 'support/deterministic_audio_player.dart';

/// A real decoder publishes playback events when play starts. The generic
/// queue fake has an empty event stream, so explicitly model that boundary.
class _ReportingPlayer173 extends DeterministicAudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast();
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Future<void> play() async {
    await super.play();
    events.add(playbackEvent);
  }
}

Track _track(String id, {TrackSource source = TrackSource.qishui}) => Track(
  id: '${source.name}_$id',
  platformSongId: id,
  title: 'Fixture $id',
  artist: 'Fixture artist',
  album: '',
  duration: const Duration(minutes: 3),
  audioAsset: 'mesting-platform://${source.name}/$id',
  lyricsAsset: '',
  coverAsset: '',
  source: source,
);

Map<String, dynamic> _page(
  List<String> ids, {
  bool more = false,
  String cursor = '',
}) => {
  'media': [
    for (final id in ids)
      {
        'entity': {
          'track_wrapper': {
            'track': {
              'id': id,
              'name': 'Fixture $id',
              'duration': 180000,
              'artists': [
                {'name': 'Fixture artist'},
              ],
            },
          },
        },
      },
  ],
  'has_more': more,
  'next_cursor': cursor,
};

class _Journal extends QishuiWriteJournal {
  final values = <String>{};
  @override
  Future<bool> pending(String key) async => values.contains(key);
  @override
  Future<void> begin(String key) async {
    values.add(key);
  }

  @override
  Future<void> finish(String key) async {
    values.remove(key);
  }
}

class _Wire {
  var current = true;
  var writes = 0;
  final requests =
      <
        ({
          String path,
          bool get,
          bool write,
          Map<String, Object?> body,
          Map<String, String> query,
        })
      >[];
  List<String> top = [];
  Future<Map<String, dynamic>> Function(String cursor)? read;
  Future<void> Function(Map<String, Object?> body)? submit;

  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    bool get = false,
    bool write = false,
    Future<void>? abortTrigger,
  }) async {
    requests.add((
      path: path,
      get: get,
      write: write,
      body: body,
      query: query,
    ));
    if (write) {
      writes++;
      if (submit != null) {
        await submit!(body);
      } else {
        final rows = body['media']! as List;
        top = [(rows.single as Map)['id'] as String];
      }
      return {'status_code': 0};
    }
    return read == null ? _page(top) : read!(query['cursor'] ?? '');
  }

  QishuiHistoryRepository repository({_Journal? journal}) =>
      QishuiHistoryRepository(
        call: call,
        current: () => current,
        owner: 'synthetic-owner',
        journal: journal ?? _Journal(),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'remote history reads every page in server order and deduplicates boundaries',
    () async {
      final wire = _Wire();
      wire.read = (cursor) async => switch (cursor) {
        '' => _page(['a', 'b'], more: true, cursor: 'next'),
        'next' => {
          'data': _page(['b', 'c']),
        },
        _ => throw StateError('unexpected cursor'),
      };
      final tracks = await wire.repository().all();
      expect(tracks.map((t) => t.platformSongId), ['a', 'b', 'c']);
      expect(wire.requests.map((r) => r.query['cursor']), ['', 'next']);
      expect(wire.requests.every((r) => r.get && !r.write), isTrue);
      expect(
        wire.requests.every((r) => r.path == QishuiHistoryRepository.path),
        isTrue,
      );
    },
  );

  test(
    'looping pagination fails instead of returning a partial full history',
    () async {
      final wire = _Wire()
        ..read = (_) async => _page(['a'], more: true, cursor: 'x');
      await expectLater(
        wire.repository().all(),
        throwsA(isA<QishuiException>()),
      );
      expect(wire.requests, hasLength(2));
      expect(wire.writes, 0);
    },
  );

  test(
    'more without a cursor fails and a malformed response is not an empty history',
    () async {
      final wire = _Wire()..read = (_) async => _page(['a'], more: true);
      await expectLater(
        wire.repository().all(),
        throwsA(isA<QishuiException>()),
      );
      wire.read = (_) async => {'status_code': 0};
      await expectLater(
        wire.repository().all(),
        throwsA(isA<QishuiException>()),
      );
    },
  );

  test(
    'account changes while reading discard the prior account response',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      final wire = _Wire()..read = (_) => gate.future;
      final pending = wire.repository().all();
      wire.current = false;
      gate.complete(_page(['old-owner-song']));
      await expectLater(pending, throwsA(isA<QishuiException>()));
      expect(wire.writes, 0);
    },
  );

  test(
    'confirmed playback sends only recent-media body then checks newest cloud item',
    () async {
      final wire = _Wire();
      await wire.repository().record(_track('a'));
      expect(wire.writes, 1);
      final request = wire.requests.first;
      expect(request.write, isTrue);
      expect(request.get, isFalse);
      expect(request.body, {
        'media': [
          {'id': 'a', 'type': 'track'},
        ],
      });
      expect(wire.requests.last.get, isTrue);
      expect(wire.requests.map((r) => r.path).toSet(), {
        QishuiHistoryRepository.path,
      });
    },
  );

  test(
    'a later real replay may reorder history after a confirmed earlier write',
    () async {
      final journal = _Journal();
      final wire = _Wire();
      final history = wire.repository(journal: journal);
      await history.record(_track('a'));
      await history.record(_track('b'));
      await history.record(_track('a'));
      expect(wire.writes, 3);
      expect(wire.top, ['a']);
      expect(journal.values, isEmpty);
    },
  );

  test(
    'unknown write persists across a new reporter and does not replay when item is merely present',
    () async {
      final journal = _Journal();
      final wire = _Wire()
        ..top = ['newer', 'a']
        ..submit = (_) async => throw const QishuiException(
          'synthetic response lost after dispatch',
          unknownWrite: true,
        );
      await expectLater(
        wire.repository(journal: journal).record(_track('a')),
        throwsA(isA<QishuiException>()),
      );
      expect(journal.values, hasLength(1));
      wire.submit = null;
      final restarted = wire.repository(journal: journal);
      await expectLater(
        restarted.record(_track('a')),
        throwsA(
          isA<QishuiException>().having((e) => e.unknownWrite, 'unknown', true),
        ),
      );
      expect(wire.writes, 1);
      expect(journal.values, hasLength(1));
    },
  );

  test(
    'pending history can be reconciled by top-position readback without another write',
    () async {
      final journal = _Journal();
      final wire = _Wire()
        ..submit = (_) async =>
            throw const QishuiException('lost', unknownWrite: true);
      await expectLater(
        wire.repository(journal: journal).record(_track('a')),
        throwsA(isA<QishuiException>()),
      );
      wire.top = ['a', 'b'];
      await wire.repository(journal: journal).record(_track('a'));
      expect(wire.writes, 1);
      expect(journal.values, isEmpty);
    },
  );

  test(
    'successful dispatch with unreadable readback remains unknown and is not automatically replayed',
    () async {
      final journal = _Journal();
      final wire = _Wire()
        ..read = (_) async => throw StateError('offline readback');
      await expectLater(
        wire.repository(journal: journal).record(_track('a')),
        throwsA(
          isA<QishuiException>().having((e) => e.unknownWrite, 'unknown', true),
        ),
      );
      expect(wire.writes, 1);
      expect(journal.values, hasLength(1));
    },
  );

  test(
    'definite refusal releases journal for a later explicit playback event',
    () async {
      final journal = _Journal();
      final wire = _Wire()
        ..submit = (_) async =>
            throw const QishuiException('synthetic refusal');
      final history = wire.repository(journal: journal);
      await expectLater(
        history.record(_track('a')),
        throwsA(isA<QishuiException>()),
      );
      expect(journal.values, isEmpty);
      wire.submit = null;
      await history.record(_track('a'));
      expect(wire.writes, 2);
    },
  );

  test(
    'reporter ignores other platforms and duplicate deliveries but allows a new playback revision',
    () async {
      final wire = _Wire();
      final statuses = <QishuiHistorySyncPhase>[];
      final reporter = QishuiHistoryReporter(
        history: wire.repository(),
        onStatus: (value) => statuses.add(value.phase),
      );
      await reporter.confirmPlayed(
        _track('a', source: TrackSource.netease),
        playbackRevision: 1,
      );
      expect(wire.writes, 0);
      await reporter.confirmPlayed(_track('a'), playbackRevision: 1);
      await reporter.confirmPlayed(_track('a'), playbackRevision: 1);
      expect(wire.writes, 1);
      await reporter.confirmPlayed(_track('a'), playbackRevision: 2);
      expect(wire.writes, 2);
      expect(
        statuses.where((p) => p == QishuiHistorySyncPhase.confirmed),
        hasLength(2),
      );
      reporter.dispose();
    },
  );

  test(
    'disposal cancels queued account work and suppresses late statuses',
    () async {
      final gate = Completer<void>();
      final wire = _Wire()..submit = (_) => gate.future;
      final statuses = <QishuiHistorySyncStatus>[];
      final reporter = QishuiHistoryReporter(
        history: wire.repository(),
        onStatus: statuses.add,
      );
      final first = reporter.confirmPlayed(_track('a'), playbackRevision: 1);
      await Future<void>.delayed(Duration.zero);
      final second = reporter.confirmPlayed(_track('b'), playbackRevision: 2);
      reporter.dispose();
      final count = statuses.length;
      gate.complete();
      await first;
      await second;
      expect(wire.writes, 1);
      expect(statuses, hasLength(count));
    },
  );

  test(
    'unknown sync is reported separately without throwing into playback',
    () async {
      final wire = _Wire()
        ..submit = (_) async =>
            throw const QishuiException('lost', unknownWrite: true);
      QishuiHistorySyncStatus? status;
      final reporter = QishuiHistoryReporter(
        history: wire.repository(),
        onStatus: (value) => status = value,
      );
      await reporter.confirmPlayed(_track('a'), playbackRevision: 1);
      expect(status?.phase, QishuiHistorySyncPhase.unconfirmed);
      expect(wire.writes, 1);
      reporter.dispose();
    },
  );

  test(
    'actual player restore and failed resolution do not report; confirmed audible play does',
    () async {
      final directory = Directory.systemTemp.createTempSync('history173_');
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (_) async => directory.path);
      final player = _ReportingPlayer173();
      final handler = MestingAudioHandler(tracks: [], player: player);
      final wire = _Wire();
      final reporter = QishuiHistoryReporter(history: wire.repository());
      final subscription = handler.consumedTrackStream.listen((track) {
        unawaited(
          reporter.confirmPlayed(
            track,
            playbackRevision: handler.transportRevision,
          ),
        );
      });
      addTearDown(() async {
        reporter.dispose();
        await subscription.cancel();
        await player.events.close();
        await Future<void>.delayed(Duration.zero);
        await handler.debugDispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathChannel, null);
        directory.deleteSync(recursive: true);
      });
      handler.configureTrackPlaybackResolver((_) async {
        throw const QishuiException(
          'synthetic no media',
          kind: QishuiFailureKind.format,
        );
      });
      await handler.restoreSession(
        tracks: [_track('a')],
        currentIndex: 0,
        position: const Duration(seconds: 20),
        mode: PlaybackMode.list,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(wire.writes, 0);
      await expectLater(handler.play(), throwsA(isA<QishuiException>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(wire.writes, 0);
      handler.configureTrackPlaybackResolver(
        (track) async =>
            track.copyWith(audioAsset: 'file:///synthetic/history173.m4a'),
      );
      await handler.play();
      await Future<void>.delayed(const Duration(milliseconds: 1150));
      expect(wire.writes, 1);
    },
  );
}
