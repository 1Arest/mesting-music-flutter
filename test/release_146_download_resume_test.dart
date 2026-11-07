import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/downloads/audio_download_resume.dart';
import 'netease_v112_fallback_download_test.dart' show recording, until;

/// A bounded local transport with a real abortable stream and byte Range
/// responses. It never resolves a CDN or contacts an account.
class _Ranges extends http.BaseClient {
  final bytes = <int>[73, 68, 51, ...List.generate(97, (i) => i)];
  final first = StreamController<List<int>>();
  final second = StreamController<List<int>>();
  final requests = <http.BaseRequest>[];
  bool changed = false, ignoresRange = false;
  bool holdSecond = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (requests.length == 1) {
      if (request is http.AbortableRequest) {
        unawaited(
          request.abortTrigger?.then((_) async {
            if (!first.isClosed) {
              first.addError(http.RequestAbortedException(request.url));
              await first.close();
            }
          }),
        );
      }
      return http.StreamedResponse(
        first.stream,
        200,
        contentLength: bytes.length,
        headers: {'etag': '"one"'},
      );
    }
    final offset = int.parse(
      request.headers['Range']!.substring(6).split('-').first,
    );
    if (requests.length == 2 && holdSecond) {
      if (request is http.AbortableRequest) {
        unawaited(
          request.abortTrigger?.then((_) async {
            if (!second.isClosed) {
              second.addError(http.RequestAbortedException(request.url));
              await second.close();
            }
          }),
        );
      }
      return http.StreamedResponse(
        second.stream,
        206,
        contentLength: bytes.length - offset,
        // A correct If-Range response need not repeat ETag. The next pause
        // must retain the original validator rather than losing resume state.
        headers: {
          'content-range': 'bytes $offset-${bytes.length - 1}/${bytes.length}',
        },
      );
    }
    if (offset == bytes.length && !ignoresRange) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        416,
        headers: {'content-range': 'bytes */$offset', 'etag': '"one"'},
      );
    }
    return http.StreamedResponse(
      Stream.value(ignoresRange ? bytes : bytes.sublist(offset)),
      ignoresRange ? 200 : 206,
      contentLength: bytes.length - offset,
      headers: {
        'content-range': 'bytes $offset-${bytes.length - 1}/${bytes.length}',
        'etag': changed ? '"two"' : '"one"',
      },
    );
  }

  @override
  void close() {
    if (!first.isClosed) unawaited(first.close());
    if (!second.isClosed) unawaited(second.close());
  }
}

void main() {
  test(
    'large persisted task directory decodes and encodes all records off-thread',
    () async {
      final tasks = [
        for (var i = 0; i < 3000; i++)
          AudioDownloadTask(
            id: 'stored_$i',
            owner: 'netease:7',
            track: recording(id: 'netease_$i'),
            phase: AudioDownloadPhase.paused,
            received: 4096,
            total: 8192,
            validator: '"one"',
          ),
      ];
      final raw = await encodeAudioDownloadSnapshot(tasks);
      expect(raw.length, greaterThan(128 * 1024));
      expect(jsonDecode(raw), hasLength(3000));
      final restored = await decodeAudioDownloadSnapshot(raw);
      expect(restored, hasLength(3000));
      expect(restored.last.id, 'stored_2999');
      expect(restored.last.received, 4096);
      expect(restored.last.validator, '"one"');
      expect(restored.last.phase, AudioDownloadPhase.paused);
    },
  );

  test(
    'account change during directory hydration cancels deferred additions',
    () async {
      var owner = 'netease:7';
      final pending = Completer<List<AudioDownloadTask>>();
      final manager = AudioDownloadManager(
        client: _Ranges(),
        resolve: (_) async => throw StateError('No media request allowed'),
        publish: (_, _, _, _) async => throw StateError('No publish allowed'),
        currentOwner: () => owner,
        directory: () async => Directory.systemTemp,
        persist: (_) async {},
      );
      addTearDown(manager.dispose);
      final restoring = manager.restoreSnapshot(pending.future);
      manager.enqueue(recording());
      expect(manager.tasks, isEmpty);
      expect(manager.restoring, true);
      owner = 'netease:8';
      manager.cancelPending();
      pending.complete([
        AudioDownloadTask(
          id: 'old',
          owner: 'netease:7',
          track: recording(),
          phase: AudioDownloadPhase.paused,
        ),
      ]);
      await restoring;
      expect(manager.restoring, false);
      expect(manager.tasks.single.id, 'old');
      expect(manager.tasks.single.phase, AudioDownloadPhase.paused);
    },
  );

  test(
    'bulk enqueue and account cancellation persist once per batch with no duplicate tasks',
    () async {
      final blocked = Completer<String>();
      var writes = 0;
      final manager = AudioDownloadManager(
        client: _Ranges(),
        resolve: (_) => blocked.future,
        publish: (_, _, _, _) async => throw StateError('No publish allowed'),
        currentOwner: () => 'netease:7',
        directory: () async => Directory.systemTemp,
        persist: (_) async {
          writes++;
        },
      );
      addTearDown(manager.dispose);
      final tracks = [
        for (var i = 0; i < 3000; i++) recording(id: 'netease_$i'),
      ];
      manager.enqueueAll([...tracks, ...tracks.take(50)]);
      await Future<void>.delayed(Duration.zero);
      expect(manager.tasks, hasLength(3000));
      expect(writes, lessThanOrEqualTo(2));
      final before = writes;
      var notifications = 0;
      manager.collectionChanges.addListener(() => notifications++);
      manager.cancelPending();
      await Future<void>.delayed(Duration.zero);
      expect(writes, before + 1);
      expect(notifications, 1);
      expect(
        manager.tasks.every(
          (task) => task.phase == AudioDownloadPhase.cancelled,
        ),
        true,
      );
    },
  );
  test(
    'byte progress updates one task without rebuilding a 3000-task collection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music147-progress',
      );
      addTearDown(() async {
        // Abort is asynchronous: wait for the real transfer's sink to release
        // its Windows handle before deleting this test's private directory.
        for (var attempt = 0; ; attempt++) {
          try {
            await directory.delete(recursive: true);
            return;
          } on FileSystemException {
            if (attempt >= 20) rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      final client = _Ranges();
      final manager = AudioDownloadManager(
        client: client,
        restored: [
          for (var i = 0; i < 3000; i++)
            AudioDownloadTask(
              id: 'old_$i',
              owner: 'netease:7',
              track: recording(),
              phase: AudioDownloadPhase.failed,
            ),
        ],
        resolve: (_) async => 'https://synthetic.invalid/song',
        publish: (_, _, _, _) async => 'content://synthetic/published',
        currentOwner: () => 'netease:7',
        directory: () async => directory,
        persist: (_) async {},
      );
      addTearDown(manager.dispose);
      manager.enqueue(recording());
      await until(
        () => manager.tasks.last.phase == AudioDownloadPhase.downloading,
      );
      final id = manager.tasks.last.id;
      var collections = 0, rows = 0;
      manager.collectionChanges.addListener(() => collections++);
      manager.taskChanges(id).addListener(() => rows++);
      await Future<void>.delayed(const Duration(milliseconds: 270));
      client.first.add(client.bytes.sublist(0, 40));
      await until(() => manager.taskById(id)!.received == 40);
      expect(collections, 0);
      expect(rows, greaterThan(0));
      expect(manager.completedTrackIds('netease:7'), isEmpty);
      manager.pause(id);
      expect(collections, 1);
      expect(manager.taskById(id)!.phase, AudioDownloadPhase.paused);
    },
  );
  test(
    'range validation rejects ignored Range, shifted bytes and changed entity',
    () {
      expect(
        resumedDownloadTotal(
          offset: 10,
          status: 206,
          headers: {'content-range': 'bytes 10-19/20', 'etag': '"one"'},
          validator: '"one"',
        ),
        20,
      );
      for (final record in [
        (200, {'content-range': 'bytes 10-19/20', 'etag': '"one"'}),
        (206, {'content-range': 'bytes 11-19/20', 'etag': '"one"'}),
        (206, {'content-range': 'bytes 10-19/20', 'etag': '"two"'}),
      ]) {
        expect(
          () => resumedDownloadTotal(
            offset: 10,
            status: record.$1,
            headers: record.$2,
            validator: '"one"',
          ),
          throwsFormatException,
        );
      }
    },
  );

  for (final outcome in ['resume', 'full', 'ignored', 'changed', 'remove']) {
    test(
      'paused stream $outcome retains progress and never publishes corrupt bytes',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'music146-resume',
        );
        addTearDown(() => directory.delete(recursive: true));
        final client = _Ranges();
        var published = 0;
        final manager = AudioDownloadManager(
          client: client,
          resolve: (_) async => 'https://synthetic.invalid/song',
          publish: (file, _, _, _) async {
            expect(await file.readAsBytes(), client.bytes);
            published++;
            return 'content://synthetic/published';
          },
          currentOwner: () => 'netease:7',
          directory: () async => directory,
          persist: (_) async {},
        );
        addTearDown(manager.dispose);
        manager.enqueue(recording());
        await until(() => client.requests.isNotEmpty);
        final offset = outcome == 'full' ? client.bytes.length : 40;
        client.first.add(client.bytes.sublist(0, offset));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final id = manager.tasks.single.id;
        manager.pause(id);
        await until(() => manager.tasks.single.received == offset);
        expect(manager.tasks.single.phase, AudioDownloadPhase.paused);
        expect(manager.tasks.single.validator, '"one"');
        expect(await File('${directory.path}/$id.part').length(), offset);
        if (outcome == 'remove') {
          expect(manager.remove(id), true);
          await until(() => !File('${directory.path}/$id.part').existsSync());
          expect(manager.tasks, isEmpty);
          expect(published, 0);
          return;
        }
        client.ignoresRange = outcome == 'ignored';
        client.changed = outcome == 'changed';
        manager.resume(id);
        await until(
          () =>
              manager.tasks.single.phase ==
              ((outcome == 'resume' || outcome == 'full')
                  ? AudioDownloadPhase.completed
                  : AudioDownloadPhase.failed),
        );
        expect(client.requests.last.headers['Range'], 'bytes=$offset-');
        expect(client.requests.last.headers['If-Range'], '"one"');
        expect(published, (outcome == 'resume' || outcome == 'full') ? 1 : 0);
        if ((outcome == 'resume' || outcome == 'full')) {
          await until(() => !File('${directory.path}/$id.part').existsSync());
        }
      },
    );
  }

  test('repeated pause preserves the validator when 206 omits ETag', () async {
    final directory = await Directory.systemTemp.createTemp('music146-cycles');
    addTearDown(() => directory.delete(recursive: true));
    final client = _Ranges()..holdSecond = true;
    var publishes = 0;
    final manager = AudioDownloadManager(
      client: client,
      resolve: (_) async => 'https://synthetic.invalid/song',
      publish: (file, _, _, _) async {
        expect(await file.readAsBytes(), client.bytes);
        publishes++;
        return 'content://synthetic/completed';
      },
      currentOwner: () => 'netease:7',
      directory: () async => directory,
      persist: (_) async {},
    );
    addTearDown(manager.dispose);
    manager.enqueue(recording());
    await until(() => client.requests.isNotEmpty);
    client.first.add(client.bytes.sublist(0, 40));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final id = manager.tasks.single.id;
    manager.pause(id);
    await until(() => manager.tasks.single.received == 40);
    manager.resume(id);
    await until(() => client.requests.length == 2);
    client.second.add(client.bytes.sublist(40, 70));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    manager.pause(id);
    await until(() => manager.tasks.single.received == 70);
    expect(manager.tasks.single.validator, '"one"');
    expect(manager.tasks.single.toJson()['phase'], 'paused');
    expect(manager.tasks.single.toJson()['validator'], '"one"');
    manager.resume(id);
    await until(
      () => manager.tasks.single.phase == AudioDownloadPhase.completed,
    );
    expect(client.requests.last.headers['Range'], 'bytes=70-');
    expect(client.requests.last.headers['If-Range'], '"one"');
    expect(publishes, 1);
  });

  test(
    'deleting blocked resolver releases queued work and rejects its late result',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'music146-remove',
      );
      addTearDown(() => directory.delete(recursive: true));
      final blocked = Completer<String>();
      final client = _Ranges();
      var resolutions = 0, publishes = 0;
      final manager = AudioDownloadManager(
        client: client,
        resolve: (_) => ++resolutions == 1
            ? blocked.future
            : Future.value('https://synthetic.invalid/next'),
        publish: (_, _, _, _) async {
          publishes++;
          return 'content://synthetic/next';
        },
        currentOwner: () => 'netease:7',
        directory: () async => directory,
        persist: (_) async {},
      );
      addTearDown(manager.dispose);
      manager.enqueue(recording());
      final deleted = manager.tasks.single.id;
      manager.enqueue(recording(id: 'second'));
      expect(manager.remove(deleted), true);
      await until(() => client.requests.isNotEmpty);
      client.first.add(client.bytes);
      await client.first.close();
      await until(
        () => manager.tasks.single.phase == AudioDownloadPhase.completed,
      );
      blocked.complete('https://synthetic.invalid/stale');
      await Future<void>.delayed(Duration.zero);
      expect(client.requests.length, 1);
      expect(publishes, 1);
      expect(manager.tasks.single.id, isNot(deleted));
    },
  );
}
