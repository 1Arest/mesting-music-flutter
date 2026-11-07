import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:mesting_music/features/downloads/audio_downloads.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/netease_playback_options.dart';
import 'package:mesting_music/features/music_platform/netease/fallback/netease_public_sources.dart';
import 'netease_v112_fallback_download_test.dart' show recording, until;
import 'support/deterministic_audio_player.dart';

class TestAccount extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    userId: '7',
    token: 'synthetic-only',
    platform: MusicPlatform.netease,
  );
  void replace(String uid, {MusicPlatform platform = MusicPlatform.netease}) =>
      state = AsyncData(
        PlatformSession(
          userId: uid,
          token: 'synthetic-only',
          platform: platform,
        ),
      );
}

class SourceFixture implements NeteaseFallbackSource {
  SourceFixture(
    this.label, {
    this.quality = '320',
    this.bitrate = 320000,
    this.wait,
    this.header = false,
    this.searchItems,
  });
  @override
  final String label;
  final String quality;
  final int bitrate;
  final Future<void> Function()? wait;
  final bool header;
  final List<Track>? searchItems;
  int searches = 0, resolutions = 0;
  @override
  Future<List<Track>> search(Track original) async {
    searches++;
    await wait?.call();
    return searchItems ?? [original];
  }

  @override
  Future<Track?> resolve(Track candidate) async {
    resolutions++;
    return candidate.copyWith(
      audioAsset: 'https://cdn.example/$label',
      playbackQuality: quality,
      audioBitrate: bitrate,
      audioHeaders: header
          ? {
              'Referer': 'https://www.bilibili.com/',
              'Cookie': 'must-never-leave',
            }
          : {},
    );
  }
}

http.Response jsonResponse(Map<String, Object?> value, {int status = 200}) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
    );
http.Response media({bool flac = false}) => http.Response.bytes(
  ascii.encode(flac ? 'fLaC' : 'ID3audio'),
  206,
  headers: {
    'content-type': 'application/octet-stream',
    'content-range': 'bytes 0-1023/12000000',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ProviderContainer> container({
    Map<String, Object> initial = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformAccountProvider.overrideWith(TestAccount.new),
      ],
    );
    addTearDown(c.dispose);
    await c.read(platformAccountProvider.future);
    return c;
  }

  test(
    'local SVIP follows UID, persists switches and cannot appear on Kugou',
    () async {
      final c = await container();
      expect(c.read(neteaseLocalSvipProvider), isTrue);
      final settings = c.read(neteaseLocalMembershipSettingsProvider.notifier);
      await settings.setEnabled('7', false);
      expect(c.read(neteaseLocalSvipProvider), isFalse);
      final accounts = c.read(platformAccountProvider.notifier) as TestAccount;
      accounts.replace('8');
      expect(c.read(neteaseLocalSvipProvider), isTrue);
      await settings.setAllowedUids('7，8 8');
      accounts.replace('9');
      expect(c.read(neteaseLocalSvipProvider), isFalse);
      accounts.replace('8', platform: MusicPlatform.kugou);
      expect(c.read(neteaseLocalSvipProvider), isFalse);
      accounts.replace('7');
      expect(c.read(neteaseLocalSvipProvider), isFalse);
      c.invalidate(neteaseLocalMembershipSettingsProvider);
      expect(
        c.read(neteaseLocalMembershipSettingsProvider).accounts['7'],
        isFalse,
      );
    },
  );
  test('invalid UID does not overwrite an existing scope', () async {
    final c = await container();
    final settings = c.read(neteaseLocalMembershipSettingsProvider.notifier);
    await settings.setAllowedUids('7,8');
    expect(
      () => settings.setAllowedUids('7,token=secret'),
      throwsA(isA<Exception>()),
    );
    expect(c.read(neteaseLocalMembershipSettingsProvider).allowedUids, {
      '7',
      '8',
    });
  });
  test(
    'overlapping account saves do not discard either UID preference',
    () async {
      final c = await container();
      final settings = c.read(neteaseLocalMembershipSettingsProvider.notifier);
      await Future.wait([
        settings.setEnabled('7', false),
        settings.setEnabled('8', false),
        settings.setAllowedUids('7 8'),
      ]);
      expect(c.read(neteaseLocalMembershipSettingsProvider).accounts, {
        '7': false,
        '8': false,
      });
      expect(c.read(neteaseLocalMembershipSettingsProvider).allowedUids, {
        '7',
        '8',
      });
    },
  );
  test(
    'options survive storage and unavailable sources cannot be restored',
    () async {
      final c = await container();
      final options = c
          .read(neteasePlaybackOptionsProvider)
          .copyWith(
            strategy: NeteaseSourceStrategy.highestQuality,
            cache: false,
            minimumBitrate: 192000,
            diagnostics: true,
            enabledSources: {NeteasePublicSource.kuwo},
          );
      await c.read(neteasePlaybackOptionsProvider.notifier).save(options);
      c.invalidate(neteasePlaybackOptionsProvider);
      expect(c.read(neteasePlaybackOptionsProvider).toJson(), options.toJson());
      final invalid = NeteasePlaybackOptions.fromJson({
        'lxSourcesVersion': 1,
        'sources': ['youtube', 'gdstudio', 'kuwo'],
        'minimumBitrate': -5,
      });
      expect(invalid.enabledSources, {NeteasePublicSource.kuwo});
      expect(invalid.minimumBitrate, 0);
    },
  );
  test('corrupt settings recover to known defaults', () async {
    final c = await container(
      initial: {
        NeteasePlaybackOptionsController.key: 'broken',
        NeteaseLocalMembershipController.key: '[]',
      },
    );
    expect(
      c.read(neteasePlaybackOptionsProvider).strategy,
      NeteaseSourceStrategy.ordered,
    );
    expect(c.read(neteaseLocalSvipProvider), isTrue);
  });
  test(
    'new sources run before BugPk even with an old supplied list order',
    () async {
      var bugCalls = 0;
      final client = MockClient((r) async {
        if (r.url.host == 'api.bugpk.com') {
          bugCalls++;
          return jsonResponse({'code': 500});
        }
        return media();
      });
      final newer = SourceFixture('new');
      final found = await NeteaseFallbackResolver([
        BugpkNeteaseFallback(client),
        newer,
      ], client).resolve(recording(), current: () => true);
      expect(found!.availabilityMessage, contains('new'));
      expect(bugCalls, 0);
    },
  );
  test(
    'all new-source misses reach exact-ID BugPk as the final stage',
    () async {
      final events = <String>[];
      final client = MockClient((r) async {
        if (r.url.host == 'api.bugpk.com') {
          events.add('bugpk');
          return jsonResponse({
            'code': 200,
            'data': [
              {
                'id': 7,
                'url': 'https://m1.music.126.net/audio',
                'level': 'exhigh',
              },
            ],
          });
        }
        return media();
      });
      final newer = SourceFixture(
        'miss',
        searchItems: [],
        wait: () async => events.add('new'),
      );
      final found = await NeteaseFallbackResolver([
        BugpkNeteaseFallback(client),
        newer,
      ], client).resolve(recording(), current: () => true);
      expect(found!.id, recording().id);
      expect(events, ['new', 'bugpk']);
    },
  );
  test('BugPk delivered bitrate replaces stale recording metadata', () async {
    final source = BugpkNeteaseFallback(
      MockClient(
        (r) async => jsonResponse({
          'code': 200,
          'data': [
            {
              'id': 7,
              'url': 'https://m1.music.126.net/audio',
              'level': 'higher',
              'br': 192000,
            },
          ],
        }),
      ),
    );
    final result = await source.resolve(
      recording().copyWith(
        audioBitrate: 320000,
        audioHeaders: {'Referer': 'https://www.bilibili.com/'},
      ),
    );
    expect(result!.audioBitrate, 192000);
    expect(result.audioHeaders, isEmpty);
  });
  test(
    'highest quality selects actual FLAC, ordered mode retains first success',
    () async {
      final first = SourceFixture('mp3');
      final second = SourceFixture('flac', quality: 'flac', bitrate: 0);
      final client = MockClient(
        (r) async => media(flac: r.url.path == '/flac'),
      );
      final selected = await NeteaseFallbackResolver(
        [first, second],
        client,
        options: const NeteasePlaybackOptions(
          strategy: NeteaseSourceStrategy.highestQuality,
        ),
      ).resolve(recording(), current: () => true);
      expect(selected!.playbackQuality, 'flac');
      final ordered = await NeteaseFallbackResolver([
        first,
        second,
      ], client).resolve(recording(), current: () => true);
      expect(ordered!.playbackQuality, '320');
    },
  );
  test('maximum-quality work is bounded to two providers', () async {
    var active = 0, maximum = 0;
    Future<void> wait() async {
      active++;
      if (active > maximum) maximum = active;
      await Future<void>.delayed(const Duration(milliseconds: 12));
      active--;
    }

    final sources = List.generate(5, (i) => SourceFixture('$i', wait: wait));
    await NeteaseFallbackResolver(
      sources,
      MockClient((r) async => media()),
      options: const NeteasePlaybackOptions(
        strategy: NeteaseSourceStrategy.highestQuality,
      ),
    ).resolve(recording(), current: () => true);
    expect(maximum, 2);
  });
  test(
    'minimum bitrate rejects unknown tiers and lossless claims require FLAC',
    () async {
      final client = MockClient((r) async => media());
      final unknown = SourceFixture('unknown', quality: '', bitrate: 0);
      expect(
        await NeteaseFallbackResolver(
          [unknown],
          client,
          options: const NeteasePlaybackOptions(minimumBitrate: 128000),
        ).resolve(recording(), current: () => true),
        isNull,
      );
      final fakeFlac = SourceFixture(
        'mp3-labelled-flac',
        quality: 'flac',
        bitrate: 0,
      );
      expect(
        await NeteaseFallbackResolver([
          fakeFlac,
        ], client).resolve(recording(), current: () => true),
        isNull,
      );
    },
  );
  test(
    'resolution cache is reprobed, invalid URLs refresh and clear is effective',
    () async {
      var requests = 0;
      final source = SourceFixture('cache');
      final client = MockClient((r) async {
        requests++;
        return requests == 2 ? http.Response('expired', 403) : media();
      });
      final resolver = NeteaseFallbackResolver([source], client);
      await resolver.resolve(recording(), current: () => true);
      await resolver.resolve(recording(), current: () => true);
      expect(source.searches, 2);
      await resolver.resolve(recording(), current: () => true);
      expect(source.searches, 2);
      resolver.clearCache();
      await resolver.resolve(recording(), current: () => true);
      expect(source.searches, 3);
    },
  );
  test(
    'disabled cache resolves each time and stale requests cannot continue after timeout',
    () async {
      final client = MockClient((r) async => media());
      final source = SourceFixture('fresh');
      final resolver = NeteaseFallbackResolver(
        [source],
        client,
        options: const NeteasePlaybackOptions(cache: false),
      );
      await resolver.resolve(recording(), current: () => true);
      await resolver.resolve(recording(), current: () => true);
      expect(source.searches, 2);
      final pending = Completer<void>();
      final slow = SourceFixture('late', wait: () => pending.future);
      expect(
        await NeteaseFallbackResolver(
          [slow],
          client,
          sourceTimeout: const Duration(milliseconds: 5),
        ).resolve(recording(), current: () => true),
        isNull,
      );
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(slow.resolutions, 0);
    },
  );
  test(
    'public headers reach probes and persistence excludes all credentials',
    () async {
      final source = SourceFixture('header', header: true);
      final client = MockClient((r) async {
        expect(r.headers['referer'], 'https://www.bilibili.com/');
        expect(r.headers['cookie'], isNull);
        return media();
      });
      final found = await NeteaseFallbackResolver([
        source,
      ], client).resolve(recording(), current: () => true);
      final restored = Track.fromJson(found!.toJson());
      expect(restored.audioHeaders, {'Referer': 'https://www.bilibili.com/'});
      expect(
        restored.toMediaItem().extras!['audioHeaders'],
        restored.audioHeaders,
      );
      expect(
        publicAudioHeaders({
          'Authorization': 'secret',
          'Origin': 'bad\nheader',
        }),
        isEmpty,
      );
    },
  );
  test(
    'diagnostic output is bounded and contains no identity or stream URL',
    () async {
      final diagnostics = NeteaseFallbackDiagnostics();
      addTearDown(diagnostics.dispose);
      final resolver = NeteaseFallbackResolver(
        [SourceFixture('anonymous')],
        MockClient((r) async => media()),
        diagnostics: diagnostics,
        options: const NeteasePlaybackOptions(diagnostics: true),
      );
      await resolver.resolve(recording(), current: () => true);
      expect(diagnostics.rows.single['result'], 'ready');
      expect(diagnostics.json, isNot(contains('netease_')));
      expect(diagnostics.json, isNot(contains('https:')));
      for (var i = 0; i < 90; i++) {
        diagnostics.record('anonymous', 'miss', i);
      }
      expect(diagnostics.rows.length, 80);
      diagnostics.clear();
      expect(diagnostics.rows, isEmpty);
    },
  );
  test(
    'GD Studio unsupported response is a miss and sends only anonymous ID',
    () async {
      final source = GdStudioNeteaseSource(
        MockClient((r) async {
          expect(r.url.queryParameters, containsPair('source', 'netease'));
          expect(r.headers['cookie'], isNull);
          return jsonResponse({
            'detail': 'Value of source is not supported.',
          }, status: 400);
        }),
      );
      expect(await source.resolve(recording()), isNull);
      expect(NeteasePublicSource.gdstudio.available, isFalse);
    },
  );
  test(
    'Bilibili titles require explicit artist evidence and preserve editions',
    () {
      final original = recording(
        title: '玻璃',
        artist: 'Gareth.T',
        album: '',
        seconds: 162,
      );
      expect(
        bilibiliRecordingTitle('Gareth.T - 玻璃【Official Audio】', original),
        '玻璃',
      );
      expect(bilibiliRecordingTitle('玻璃 - Gareth.T', original), '玻璃');
      expect(
        bilibiliRecordingTitle('Gareth.T - 玻璃 (Live)', original),
        '玻璃 (Live)',
      );
      expect(bilibiliRecordingTitle('玻璃', original), isNull);
      expect(bilibiliRecordingTitle('其它歌手 - 玻璃', original), isNull);
    },
  );
  test(
    'Bilibili video uses WBI visitor metadata and returns DASH audio headers',
    () async {
      final requests = <http.Request>[];
      final source = BilibiliVideoSource(
        MockClient((r) async {
          requests.add(r);
          expect(r.headers['authorization'], isNull);
          if (r.url.host == 'www.bilibili.com') {
            return http.Response(
              '',
              200,
              headers: {'set-cookie': 'buvid3=visitor; Path=/; HttpOnly'},
            );
          }
          if (r.url.path.endsWith('/nav')) {
            return jsonResponse({
              'code': -101,
              'data': {
                'wbi_img': {
                  'img_url':
                      'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
                  'sub_url':
                      'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
                },
              },
            });
          }
          expect(
            r.url.queryParameters['w_rid'],
            matches(RegExp(r'^[0-9a-f]{32}$')),
          );
          if (r.url.path.endsWith('/type')) {
            return jsonResponse({
              'code': 0,
              'data': {
                'result': [
                  {
                    'bvid': 'BV1xx411c7mD',
                    'title': '<em>Gareth.T</em> - 玻璃【Official Audio】',
                    'duration': '2:42',
                  },
                  {
                    'bvid': 'BV1xx411c7mE',
                    'title': '玻璃 Live',
                    'duration': '2:42',
                  },
                ],
              },
            });
          }
          if (r.url.path.endsWith('/view')) {
            return jsonResponse({
              'code': 0,
              'data': {
                'cid': 42,
                'title': 'Gareth.T - 玻璃【Official Audio】',
                'duration': 162,
              },
            });
          }
          return jsonResponse({
            'code': 0,
            'data': {
              'dash': {
                'audio': [
                  {
                    'mimeType': 'audio/mp4',
                    'baseUrl': 'https://cdn.bilivideo.com/audio.m4s',
                    'bandwidth': 192000,
                  },
                ],
              },
            },
          });
        }),
        now: () => DateTime.utc(2026, 10, 29),
      );
      final rows = await source.search(
        recording(title: '玻璃', artist: 'Gareth.T', album: '', seconds: 162),
      );
      expect(rows.length, 1);
      final found = await source.resolve(rows.single);
      expect(found!.audioHeaders['Referer'], 'https://www.bilibili.com/');
      expect(found.audioHeaders.containsKey('Cookie'), isFalse);
      expect(found.audioAsset, endsWith('audio.m4s'));
      expect(found.audioBitrate, 192000);
      expect(found.playbackQuality, '');
      expect(
        requests
            .where((r) => r.url.path.endsWith('/type'))
            .single
            .headers['cookie'],
        'buvid3=visitor',
      );
    },
  );
  test('download receives the resolved anonymous media headers', () async {
    final dir = await Directory(
      '.codex-artifacts/2026-10-29-release115/download-test',
    ).create(recursive: true);
    final manager = AudioDownloadManager(
      client: MockClient((r) async {
        expect(r.headers['referer'], 'https://www.bilibili.com/');
        expect(r.headers['cookie'], isNull);
        return http.Response.bytes([
          ...ascii.encode('    ftyp'),
          ...List.filled(30, 0),
        ], 200);
      }),
      resolveMedia: (track) async => track.copyWith(
        audioAsset: 'https://cdn.bilivideo.com/audio',
        audioHeaders: {
          'Referer': 'https://www.bilibili.com/',
          'Cookie': 'excluded',
        },
      ),
      publish: (file, track, extension, mime) async {
        expect(extension, 'm4a');
        return 'content://saved/test';
      },
      currentOwner: () => 'netease:7',
      directory: () async => dir,
      persist: (_) async {},
    );
    addTearDown(manager.dispose);
    manager.enqueue(recording());
    await until(
      () => {
        AudioDownloadPhase.completed,
        AudioDownloadPhase.failed,
      }.contains(manager.tasks.single.phase),
    );
    expect(manager.tasks.single.phase, AudioDownloadPhase.completed);
  });
  test(
    'the production audio handler supplies anonymous headers to its source',
    () async {
      final dir = await Directory(
        '.codex-artifacts/2026-10-29-release115/player-test',
      ).create(recursive: true);
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.absolute.path);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(handler.debugDispose);
      await handler.replaceQueue([
        recording().copyWith(
          audioAsset: 'https://cdn.example/v115-headers.m4a',
          audioHeaders: {
            'Referer': 'https://www.bilibili.com/',
            'Cookie': 'excluded',
          },
        ),
      ], autoplay: false);
      // The app pins this cache API and verifies its playback contract here.
      // ignore: experimental_member_use
      final source = player.sources.single as LockCachingAudioSource;
      expect(source.headers, {'Referer': 'https://www.bilibili.com/'});
      expect(source.tag.extras['audioHeaders'], {
        'Referer': 'https://www.bilibili.com/',
      });
    },
  );
}
