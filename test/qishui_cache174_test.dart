import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/core/cache/browse_artwork_projection.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_browse_cache.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'qishui_signed_api167_test.dart' show account, reply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qishui174-');
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await directory.delete(recursive: true);
  });
  BrowseResponseCache cache() => BrowseResponseCache(
    directory: () async => directory,
    initializeOnRead: true,
    refreshInterval: const Duration(hours: 1),
  );
  Future<Map<String, dynamic>> read(QishuiApi api, BrowseCacheWatch watch) =>
      watch.run(() => api.request('/luna/me', get: true));

  test(
    'only display routes enter the cache; private grants and writes stay live',
    () {
      for (final path in [
        '/luna/discover/mix',
        '/luna/feed/song-tab',
        '/luna/me',
        '/luna/me/playlist/v2',
        '/luna/playlist/detail',
        '/luna/search/artist',
      ]) {
        expect(QishuiBrowseCachePolicy.allows(path), isTrue);
      }
      for (final path in [
        '/luna/media_v2',
        '/luna/pc/track_v2',
        '/luna/video/uploader',
        '/luna/commerce/v2/commerce_info',
        '/luna/me/playlist/update',
      ]) {
        expect(QishuiBrowseCachePolicy.allows(path), isFalse);
      }
    },
  );
  test('search nonce does not split snapshots, filters and cursors do', () {
    final a = QishuiBrowseCachePolicy.query(
      {'search_id': 'one', 'keyword': '歌'},
      {'cursor': '0'},
    );
    final b = QishuiBrowseCachePolicy.query(
      {'search_id': 'two', 'keyword': '歌'},
      {'cursor': '0'},
    );
    expect(a, b);
    expect(
      a,
      isNot(QishuiBrowseCachePolicy.query({'keyword': '歌'}, {'cursor': '50'})),
    );
  });
  test(
    'picture preparation uses the rendered Soda DTO URI, not base URLs or alternate CDNs',
    () {
      final cover = {
        'uri': 'tos/cover.png',
        'template_prefix': 'soda',
        'urls': ['https://image.example/', 'https://alternate.example/'],
      };
      final shown = QishuiBrowseCachePolicy.display({
        'playlists': [
          {'id': '1', 'url_cover': cover},
        ],
      });
      expect(shown[browseArtworkProjectionKey], {
        r'$.playlists[0].url_cover':
            'https://image.example/tos/cover.png~soda-resize:960:960.png',
      });
      final storedCover =
          ((shown['playlists'] as List).single as Map)['url_cover'];
      expect(storedCover, cover);
      expect(identical(storedCover, cover), isFalse);
    },
  );
  test(
    'defensive metadata projection strips nested secrets without mutating the response',
    () {
      final raw = <String, dynamic>{
        'status_code': 0,
        'my_info': {'nickname': '上次内容'},
        'tracks': [
          {
            'id': '7',
            'name': '歌曲',
            'PlayAuth': 'secret',
            'tokens': {'x': 'secret'},
          },
        ],
        'security_token': {'secret_access_key': 'secret'},
        'accessToken': 'secret',
        'CREDENTIAL': 'secret',
        'author': '歌手资料仍保留',
      };
      final shown = QishuiBrowseCachePolicy.display(raw);
      expect('$shown', isNot(contains('secret')));
      expect(shown['my_info'], {'nickname': '上次内容'});
      expect(shown['author'], '歌手资料仍保留');
      expect(
        (raw['tracks'] as List).single,
        containsPair('PlayAuth', 'secret'),
      );
    },
  );
  test(
    'process restart renders disk content before the new request finishes, then publishes',
    () async {
      final first = QishuiApi(
        MockClient(
          (_) async => reply({
            'my_info': {'nickname': '旧内容'},
          }),
        ),
        browseCache: cache(),
      )..configure(account());
      final one = BrowseCacheWatch(() {});
      await read(first, one);
      one.dispose();
      first.dispose();
      final pending = Completer<Map<String, dynamic>>();
      var notices = 0;
      final restarted = QishuiApi(
        MockClient((_) async => reply(await pending.future)),
        browseCache: cache(),
      )..configure(account());
      final two = BrowseCacheWatch(() {
        notices++;
      });
      addTearDown(() {
        two.dispose();
        restarted.dispose();
      });
      final old = await read(
        restarted,
        two,
      ).timeout(const Duration(seconds: 2));
      expect((old['my_info'] as Map)['nickname'], '旧内容');
      pending.complete({
        'my_info': {'nickname': '新内容'},
      });
      await restarted.browseCache.settleRefreshes(restarted.browseScope!);
      await Future<void>.delayed(Duration.zero);
      expect(notices, 1);
      expect(
        ((await read(restarted, two))['my_info'] as Map)['nickname'],
        '新内容',
      );
    },
  );
  test(
    'failed background refresh retains the durable successful snapshot',
    () async {
      final original = QishuiApi(
        MockClient(
          (_) async => reply({
            'my_info': {'nickname': '保留'},
          }),
        ),
        browseCache: cache(),
      )..configure(account());
      final a = BrowseCacheWatch(() {});
      await read(original, a);
      a.dispose();
      original.dispose();
      final failed = QishuiApi(
        MockClient((_) async => throw const SocketException('offline')),
        browseCache: cache(),
      )..configure(account());
      final b = BrowseCacheWatch(() {});
      addTearDown(() {
        b.dispose();
        failed.dispose();
      });
      expect((await read(failed, b))['my_info'], {'nickname': '保留'});
      await failed.browseCache.settleRefreshes(failed.browseScope!);
      final restored = await BrowseResponseCache.restoreOnly(
        () => read(failed, b),
      );
      expect(restored['my_info'], {'nickname': '保留'});
    },
  );
  test(
    'another account or protocol cannot hydrate a previous owner snapshot',
    () async {
      final shared = cache();
      final api = QishuiApi(
        MockClient(
          (_) async => reply({
            'my_info': {'nickname': '旧账号'},
          }),
        ),
        browseCache: shared,
      )..configure(account());
      final watch = BrowseCacheWatch(() {});
      addTearDown(() {
        watch.dispose();
        api.dispose();
      });
      await read(api, watch);
      api.configure(
        QishuiSession(
          userId: 'another',
          cookies: account().cookies,
          protocol: QishuiSessionProtocol.web,
        ),
      );
      await expectLater(
        BrowseResponseCache.restoreOnly(() => read(api, watch)),
        throwsA(isA<BrowseSnapshotUnavailable>()),
      );
      api.configure(
        QishuiSession(userId: account().userId, cookies: account().cookies),
      );
      await expectLater(
        BrowseResponseCache.restoreOnly(() => read(api, watch)),
        throwsA(isA<BrowseSnapshotUnavailable>()),
      );
    },
  );
  test(
    'raw readback outside a presentation observer bypasses a warm snapshot',
    () async {
      var version = 1;
      final api = QishuiApi(
        MockClient(
          (_) async => reply({
            'my_info': {'version': version++},
          }),
        ),
        browseCache: cache(),
      )..configure(account());
      final watch = BrowseCacheWatch(() {});
      addTearDown(() {
        watch.dispose();
        api.dispose();
      });
      expect((await read(api, watch))['my_info'], {'version': 1});
      expect((await api.request('/luna/me', get: true))['my_info'], {
        'version': 2,
      });
      expect((await read(api, watch))['my_info'], {'version': 1});
    },
  );
  test(
    'history mutation invalidates recent rows while retaining discovery and libraries',
    () {
      expect(
        QishuiBrowseCachePolicy.affectedBy(
          '/luna/me/recently-played-media',
          '/luna/me/recently-played-media',
        ),
        isTrue,
      );
      for (final path in [
        '/luna/discover/mix',
        '/luna/feed/song-tab',
        '/luna/me/playlist/v2',
      ]) {
        expect(
          QishuiBrowseCachePolicy.affectedBy(
            '/luna/me/recently-played-media',
            path,
          ),
          isFalse,
        );
      }
      expect(
        QishuiBrowseCachePolicy.affectedBy(
          '/luna/me/playlist/update',
          '/luna/playlist/detail',
        ),
        isTrue,
      );
    },
  );

  test(
    'reloading a cancelled page does not reuse its in-flight transport',
    () async {
      final oldResponse = Completer<Map<String, dynamic>>();
      final newResponse = Completer<Map<String, dynamic>>();
      final firstSent = Completer<void>(), secondSent = Completer<void>();
      var calls = 0;
      final api = QishuiApi(
        MockClient((_) async {
          if (++calls == 1) {
            firstSent.complete();
            return reply(await oldResponse.future);
          }
          secondSent.complete();
          return reply(await newResponse.future);
        }),
        browseCache: cache(),
      )..configure(account());
      final first = BrowseCacheWatch(() {}), second = BrowseCacheWatch(() {});
      final abortOld = Completer<void>(), abortNew = Completer<void>();
      addTearDown(() {
        first.dispose();
        second.dispose();
        api.dispose();
      });
      final old = first.run(
        () => api.request('/luna/me', get: true, abortTrigger: abortOld.future),
      );
      final oldCheck = expectLater(old, throwsA(isA<QishuiException>()));
      await firstSent.future;
      abortOld.complete();
      final fresh = second.run(
        () => api.request('/luna/me', get: true, abortTrigger: abortNew.future),
      );
      await secondSent.future.timeout(const Duration(seconds: 2));
      oldResponse.complete({
        'my_info': {'nickname': '旧请求'},
      });
      newResponse.complete({
        'my_info': {'nickname': '新请求'},
      });
      expect((await fresh)['my_info'], {'nickname': '新请求'});
      await oldCheck;
      expect(calls, 2);
    },
  );
}
