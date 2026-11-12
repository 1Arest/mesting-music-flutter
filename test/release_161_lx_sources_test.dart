import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/lx_anonymous_transport.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/lx_netease_source.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/lx_script_engine.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/lx_source_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_options.dart';
import 'package:mesting_music/features/music_platform/netease/netease_track_sources.dart';
import 'netease_v112_fallback_download_test.dart' show recording;
import 'netease_v116_recovery_test.dart' show mp3Prefix;

class _Engine implements LxScriptEngine {
  _Engine({this.result = 'https://cdn.example/full.mp3', this.check});
  final String result;
  final void Function(Map<String, Object?> song, String quality)? check;
  bool disposed = false;
  @override
  Future<String> resolve(
    LxMusicSource source,
    Map<String, Object?> song,
    String quality,
  ) async {
    check?.call(song, quality);
    return result;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all eleven IDs have independent playback and preference identities',
    () {
      expect(LxMusicSource.values.length, 11);
      expect(
        NeteaseTrackSource.values
            .map((s) => s.lx)
            .whereType<LxMusicSource>()
            .toSet(),
        LxMusicSource.values.toSet(),
      );
      expect(
        NeteasePublicSource.values
            .map((s) => s.lx)
            .whereType<LxMusicSource>()
            .toSet(),
        LxMusicSource.values.toSet(),
      );
      expect(LxMusicSource.values.map((s) => s.adapter).toSet().length, 11);
      final old = NeteasePlaybackOptions.fromJson({
        'sources': ['kuwo'],
      });
      expect(old.enabledSources.where((s) => s.lx != null).length, 11);
      final saved = old
          .copyWith(enabledSources: {NeteasePublicSource.kuwo})
          .toJson();
      expect(NeteasePlaybackOptions.fromJson(saved).enabledSources, {
        NeteasePublicSource.kuwo,
      });
    },
  );

  for (final source in LxMusicSource.values) {
    test(
      '${source.name} passes only song metadata and leaves quality for actual media measurement',
      () async {
        final engine = _Engine(
          check: (song, quality) {
            expect(song['source'], 'wy');
            expect(song['songmid'], '7');
            expect(quality, 'flac');
            final text = jsonEncode(song).toLowerCase();
            for (final secret in ['cookie', 'credential', 'token', 'account']) {
              expect(text, isNot(contains(secret)));
            }
          },
        );
        final adapter = LxNeteaseSource(
          source,
          MockClient((_) async => throw StateError('no network')),
          pool: LxEnginePool(),
          engineFactory: (_) => engine,
        );
        final media = await adapter.resolve(
          recording().copyWith(playbackQuality: 'flac'),
        );
        expect(media!.id, 'netease_7');
        expect(media.playbackQuality, '');
        expect(media.audioHeaders, isEmpty);
        expect(media.audioBitrate, 0);
        expect(engine.disposed, isTrue);
      },
    );
  }

  test(
    'script result cannot expose a local file or private-network media URL',
    () async {
      for (final url in [
        'file:///private/music.mp3',
        'http://127.0.0.1/music',
        'https://user:pass@cdn.example/music',
      ]) {
        final adapter = LxNeteaseSource(
          LxMusicSource.fish,
          MockClient((_) async => throw StateError('no I/O expected')),
          pool: LxEnginePool(),
          engineFactory: (_) => _Engine(result: url),
        );
        expect(await adapter.resolve(recording()), isNull);
      }
    },
  );

  test(
    'actual short MP3 preview is rejected even if script returns a successful URL',
    () async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          mp3Prefix(30),
          206,
          headers: {
            'content-type': 'audio/mpeg',
            'content-range': 'bytes 0-1023/480000',
          },
        ),
      );
      final adapter = LxNeteaseSource(
        LxMusicSource.huibq,
        client,
        pool: LxEnginePool(),
        engineFactory: (_) => _Engine(),
      );
      expect(
        await NeteaseFallbackResolver([
          adapter,
        ], client).resolve(recording(), current: () => true),
        isNull,
      );
    },
  );

  test('actual complete MP3 owns the reported source and quality', () async {
    final client = MockClient(
      (request) async => http.Response.bytes(
        mp3Prefix(274),
        206,
        headers: {
          'content-type': 'audio/mpeg',
          'content-range': 'bytes 0-1023/4384000',
        },
      ),
    );
    final adapter = LxNeteaseSource(
      LxMusicSource.huibq,
      client,
      pool: LxEnginePool(),
      engineFactory: (_) => _Engine(),
    );
    final result = await NeteaseFallbackResolver([
      adapter,
    ], client).resolve(recording(), current: () => true);
    expect(result!.playbackQuality, '128');
    expect(result.audioOrigin!.adapter, 'LX · huibq');
    expect(result.platformSongId, '7');
    expect(result.source, recording().source);
  });

  test(
    'private/local URLs and credential-bearing redirects are rejected',
    () async {
      for (final url in [
        'file:///tmp/x',
        'https://user:password@cdn.example/a',
        'http://127.0.0.1/a',
        'http://192.168.1.1/a',
        'http://10.3.2.1/a',
        'https://localhost/a',
        'http://[::1]/a',
      ]) {
        expect(
          LxAnonymousTransport.publicUri(Uri.parse(url)),
          isFalse,
          reason: url,
        );
      }
      var calls = 0;
      final transport = LxAnonymousTransport(
        MockClient((_) async {
          calls++;
          return http.Response(
            '',
            302,
            headers: {'location': 'http://127.0.0.1/private'},
          );
        }),
      );
      await expectLater(
        transport.request('https://api.example/url', {}),
        throwsA(isA<NeteaseSourceFailure>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'anonymous requests and responses never forward cookies or auth headers',
    () async {
      final transport = LxAnonymousTransport(
        MockClient((request) async {
          expect(
            request.headers.keys.map((x) => x.toLowerCase()),
            isNot(contains('cookie')),
          );
          expect(
            request.headers.keys.map((x) => x.toLowerCase()),
            isNot(contains('authorization')),
          );
          expect(request.headers['X-Request-Key'], 'public-script-key');
          expect(request.bodyFields, {'id': '7'});
          return http.Response(
            '{"url":"https://cdn.example/song"}',
            200,
            headers: {'set-cookie': 'secret=1'},
          );
        }),
      );
      final result = await transport.request('https://api.example/url', {
        'method': 'POST',
        'headers': {
          'Cookie': 'private',
          'Authorization': 'private',
          'X-Request-Key': 'public-script-key',
        },
        'form': {'id': '7'},
      });
      expect((result['headers'] as Map).containsKey('set-cookie'), isFalse);
      expect(result['body'], {'url': 'https://cdn.example/song'});
    },
  );

  test(
    'an attempt closing cancels its native adapter without closing shared HTTP',
    () {
      final client = NeteaseSourceClient(
        MockClient((_) async => http.Response('', 200)),
      );
      var closes = 0;
      client.onClose(() => closes++);
      client.close();
      client.close();
      expect(closes, 1);
      client.onClose(() => closes++);
      expect(closes, 2);
    },
  );

  test(
    'engine pool limits concurrency and drops cancelled queued work',
    () async {
      final pool = LxEnginePool(), wait = Completer<void>();
      var active = 0, maximum = 0, staleRan = false, current = true;
      Future<int> work() async {
        active++;
        if (active > maximum) maximum = active;
        await wait.future;
        active--;
        return 1;
      }

      final a = pool.run(work, () => true), b = pool.run(work, () => true);
      final c = pool.run(() async {
        staleRan = true;
        return 3;
      }, () => current);
      final check = expectLater(c, throwsA(isA<NeteaseSourceFailure>()));
      current = false;
      wait.complete();
      await Future.wait([a, b]);
      await check;
      expect(maximum, 2);
      expect(staleRan, isFalse);
    },
  );
}
