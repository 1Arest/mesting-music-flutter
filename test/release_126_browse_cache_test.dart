import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/core/cache/cached_browse_loader.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mesting-browse-126-');
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await directory.delete(recursive: true);
  });
  BrowseResponseCache cache({int bytes = 1024 * 1024, int entries = 100}) =>
      BrowseResponseCache(
        initializeOnRead: true,
        directory: () async => directory,
        maxBytes: bytes,
        maxEntryBytes: bytes,
        maxEntries: entries,
        refreshInterval: const Duration(minutes: 5),
      );
  Future<BrowseJson> read(
    BrowseResponseCache c,
    Future<BrowseJson> Function() load, {
    String scope = 'netease:7',
    String route = '/playlist/detail',
    Map<String, Object?> query = const {'id': 1},
    void Function()? check,
    String identity = '',
  }) => c.read(
    scope: scope,
    route: route,
    query: query,
    load: load,
    checkCurrent: check ?? () {},
    requestIdentity: identity,
  );
  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 25));

  test(
    'startup discards an interrupted write without deleting unrelated files',
    () async {
      final folder = await Directory(
        '${directory.path}/mesting_browse_cache_v1',
      ).create();
      final unfinished = File(
        '${folder.path}/${'a' * 64}_${'b' * 64}.json.tmp',
      );
      final unrelated = File('${folder.path}/unrelated.tmp');
      await unfinished.writeAsString('unfinished');
      await unrelated.writeAsString('keep');
      await cache().initialize();
      expect(await unfinished.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
    },
  );

  test(
    'restart returns the last successful page before network then updates its reader',
    () async {
      final before = cache(), firstWatch = BrowseCacheWatch(() {});
      expect(
        await firstWatch.run(
          () => read(
            before,
            () async => {
              'items': [1],
            },
          ),
        ),
        {
          'items': [1],
        },
      );
      firstWatch.dispose();
      final network = Completer<BrowseJson>(), started = Completer<void>();
      final changed = Completer<void>();
      var updates = 0;
      final after = cache(),
          watch = BrowseCacheWatch(() {
            updates++;
            if (!changed.isCompleted) changed.complete();
          });
      addTearDown(watch.dispose);
      final old = await watch.run(
        () => read(after, () {
          started.complete();
          return network.future;
        }),
      );
      expect(old, {
        'items': [1],
      });
      await started.future;
      expect(updates, 0);
      network.complete({
        'items': [2, 3],
      });
      await changed.future.timeout(const Duration(seconds: 5));
      expect(updates, 1);
      expect(
        await watch.run(
          () => read(after, () async => throw StateError('not due')),
        ),
        {
          'items': [2, 3],
        },
      );
    },
  );
  test(
    'failed refresh keeps disk data and ordinary live calls bypass snapshots',
    () async {
      final c = cache(), seed = BrowseCacheWatch(() {});
      await seed.run(() => read(c, () async => {'name': 'saved'}));
      seed.dispose();
      final restarted = cache(), watch = BrowseCacheWatch(() {});
      addTearDown(watch.dispose);
      expect(
        await watch.run(
          () => read(
            restarted,
            () async => throw const SocketException('offline'),
          ),
        ),
        {'name': 'saved'},
      );
      await flush();
      expect(await read(restarted, () async => {'name': 'live'}), {
        'name': 'live',
      });
      final third = cache();
      expect(
        await watch.run(
          () => read(third, () async => throw const SocketException('offline')),
        ),
        {'name': 'saved'},
      );
      await flush();
    },
  );
  test(
    'platform, account, resource and page query are isolated and canonical',
    () async {
      final c = cache(), watch = BrowseCacheWatch(() {});
      addTearDown(watch.dispose);
      for (final scope in ['netease:7', 'netease:8', 'kugou:7']) {
        for (final page in [1, 2]) {
          final result = await watch.run(
            () => read(
              c,
              () async => {'value': '$scope/$page'},
              scope: scope,
              query: {'page': page, 'id': 1},
            ),
          );
          expect(result['value'], '$scope/$page');
        }
      }
      expect(
        (await watch.run(
          () => read(
            c,
            () async => throw StateError('same query'),
            query: {'id': 1, 'page': 1},
          ),
        ))['value'],
        'netease:7/1',
      );
      final files = await Directory(
        '${directory.path}/mesting_browse_cache_v1',
      ).list().toList();
      expect(files.length, 6);
      expect(files.every((file) => !file.path.contains('netease')), isTrue);
    },
  );
  test(
    'an account switch rejects both a disk read and a late network result',
    () async {
      final c = cache(),
          watch = BrowseCacheWatch(() {}),
          response = Completer<BrowseJson>();
      addTearDown(watch.dispose);
      var current = true;
      void check() {
        if (!current) throw StateError('changed');
      }

      final future = watch.run(
        () => read(c, () => response.future, check: check, identity: 'old'),
      );
      await flush();
      current = false;
      final rejected = expectLater(future, throwsStateError);
      response.complete({'name': 'must not persist'});
      await rejected;
      expect(
        await Directory(
          '${directory.path}/mesting_browse_cache_v1',
        ).list().isEmpty,
        isTrue,
      );
      await expectLater(
        watch.run(() => read(c, () async => {}, check: check)),
        throwsStateError,
      );
    },
  );
  test(
    'different credentials never share a pending request for the same saved owner',
    () async {
      final c = cache(),
          a = BrowseCacheWatch(() {}),
          b = BrowseCacheWatch(() {});
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final first = Completer<BrowseJson>(), second = Completer<BrowseJson>();
      final old = a.run(() => read(c, () => first.future, identity: 'old'));
      final fresh = b.run(() => read(c, () => second.future, identity: 'new'));
      await flush();
      second.complete({'value': 'new'});
      expect(await fresh, {'value': 'new'});
      first.complete({'value': 'old'});
      expect(await old, {'value': 'old'});
    },
  );
  test('corrupt snapshot falls back to a validated fresh response', () async {
    final c = cache(), watch = BrowseCacheWatch(() {});
    addTearDown(watch.dispose);
    await watch.run(() => read(c, () async => {'ok': 1}));
    final file =
        (await Directory(
              '${directory.path}/mesting_browse_cache_v1',
            ).list().toList()).single
            as File;
    await file.writeAsString('{broken');
    expect(await watch.run(() => read(cache(), () async => {'ok': 2})), {
      'ok': 2,
    });
    expect(jsonDecode(await file.readAsString())['body'], {'ok': 2});
  });
  test('business rejection does not replace a successful page', () async {
    final c = cache(), watch = BrowseCacheWatch(() {});
    addTearDown(watch.dispose);
    await watch.run(
      () => read(
        c,
        () async => {
          'code': 200,
          'items': ['saved'],
        },
      ),
    );
    c.revalidateScope('netease:7');
    expect(
      (await watch.run(() => read(c, () async => {'code': 301})))['items'],
      ['saved'],
    );
    await flush();
    final restarted = cache();
    expect(
      (await watch.run(
        () => read(restarted, () async => {'code': 301}),
      ))['items'],
      ['saved'],
    );
    await flush();
  });
  test(
    'successful edits invalidate scope and block an earlier in-flight cache write',
    () async {
      final c = cache(),
          watch = BrowseCacheWatch(() {}),
          result = Completer<BrowseJson>();
      addTearDown(watch.dispose);
      await watch.run(
        () => read(
          c,
          () async => {
            'items': ['old'],
          },
        ),
      );
      c.revalidateScope('netease:7');
      await watch.run(() => read(c, () => result.future));
      await flush();
      await c.invalidateScope('netease:7');
      result.complete({
        'items': ['late-old'],
      });
      await flush();
      expect(
        await watch.run(
          () => read(
            c,
            () async => {
              'items': ['new'],
            },
          ),
        ),
        {
          'items': ['new'],
        },
      );
    },
  );
  test(
    'capacity eviction removes least recently used pages from memory and disk',
    () async {
      final c = cache(entries: 2), watch = BrowseCacheWatch(() {});
      addTearDown(watch.dispose);
      for (var id = 1; id <= 3; id++) {
        await watch.run(
          () => read(c, () async => {'id': id}, query: {'id': id}),
        );
      }
      expect(
        (await Directory(
          '${directory.path}/mesting_browse_cache_v1',
        ).list().toList()).length,
        2,
      );
      var calls = 0;
      expect(
        (await watch.run(
          () => read(c, () async {
            calls++;
            return {'id': 10};
          }, query: {'id': 1}),
        ))['id'],
        10,
      );
      expect(calls, 1);
    },
  );
  test(
    'a disposed page is never notified and page replacement retains later rows',
    () async {
      final c = cache(), watch = BrowseCacheWatch(() {});
      await watch.run(
        () => read(
          c,
          () async => {
            'rows': [1],
          },
        ),
      );
      watch.dispose();
      final network = Completer<BrowseJson>();
      var updates = 0;
      final viewer = BrowseCacheWatch(() => updates++);
      c.revalidateScope('netease:7');
      await viewer.run(() => read(c, () => network.future));
      viewer.dispose();
      network.complete({
        'rows': [2],
      });
      // Disposing the view cancels notifications, not the valid cache write.
      // Await the persisted result before deleting the fixture directory.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      var saved = false;
      while (!saved && DateTime.now().isBefore(deadline)) {
        for (final entry in await Directory(
          '${directory.path}/mesting_browse_cache_v1',
        ).list().toList()) {
          if (entry is! File || !entry.path.endsWith('.json')) {
            continue;
          }
          try {
            final body = jsonDecode(await entry.readAsString())['body'];
            saved = jsonEncode(body) == '{"rows":[2]}';
          } on Object {
            /* An atomic replacement may be in progress. */
          }
          if (saved) break;
        }
        if (!saved) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      expect(saved, isTrue);
      expect(updates, 0);
      final list = ['a', 'b', 'c', 'd'];
      replaceBrowsePage(list, ['a', 'b'], ['x', 'b'], (item) => item);
      expect(list, ['x', 'b', 'c', 'd']);
    },
  );
  test(
    'storage failure falls back to live data and never blocks browsing',
    () async {
      final c = BrowseResponseCache(
        initializeOnRead: true,
        directory: () async => throw const FileSystemException('unavailable'),
      );
      final watch = BrowseCacheWatch(() {});
      addTearDown(watch.dispose);
      expect(await watch.run(() => read(c, () async => {'live': true})), {
        'live': true,
      });
    },
  );
}
