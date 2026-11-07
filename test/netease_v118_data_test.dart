import 'netease_v114_workflows_test.dart' show eapiBody;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'package:mesting_music/core/audio/playback_providers.dart';
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_quality_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/downloads/audio_download_storage.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_media_uri.dart';
import 'package:mesting_music/features/music_platform/netease/netease_account_overview.dart';
import 'package:mesting_music/features/music_platform/netease/netease_features_repository.dart';
import 'package:mesting_music/shared/utils/media_uri.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_content.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_repository.dart';
import 'netease_v112_fallback_download_test.dart' show recording;
import 'netease_v115_sources_test.dart' show SourceFixture, TestAccount;
import 'support/deterministic_audio_player.dart';

import 'netease_full_workflows_test.dart' show endpoint;

const session = NeteaseSession(
  userId: '7',
  cookies: {'MUSIC_U': 'fixture-only'},
  deviceId: 'fixture',
);
http.Response response(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
NeteaseMusicRepository repository(http.Client client) =>
    NeteaseMusicRepository(NeteaseApi(client)..configure(session));

class _PendingQualityAudio extends MestingAudioHandler {
  _PendingQualityAudio()
    : super(tracks: [], player: DeterministicAudioPlayer());
  final pending = Completer<bool>();
  @override
  Future<bool> refreshCurrentSource() => pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'saved MVs with vid/title/coverUrl retain their navigation and real cover',
    () {
      final item = NeteaseFeaturesRepository.parse({
        'vid': 10910895,
        'title': '陪你去流浪',
        'coverImgUrl': '',
        'coverUrl': 'http://p1.music.126.net/fixture.jpg',
        'creator': [
          {'userName': '薛之谦'},
        ],
      }, NeteaseEntity.mv);
      expect(item.id, '10910895');
      expect(item.name, '陪你去流浪');
      expect(item.cover, 'https://p1.music.126.net/fixture.jpg');
      expect(item.subtitle, '薛之谦');
    },
  );
  test('empty cover fields do not mask later valid playlist image fields', () {
    expect(
      firstArtworkUri(['', null, 'http://p1.music.126.net/cover.jpg']),
      'https://p1.music.126.net/cover.jpg',
    );
    expect(firstArtworkUri(['', null]), '');
  });
  test(
    'account switch cancels the old quality operation without leaving the new account busy',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final audio = _PendingQualityAudio();
      addTearDown(audio.debugDispose);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          platformAccountProvider.overrideWith(TestAccount.new),
          currentTrackProvider.overrideWithValue(recording()),
          audioHandlerProvider.overrideWithValue(audio),
        ],
      );
      addTearDown(c.dispose);
      await c.read(platformAccountProvider.future);
      final pending = c
          .read(platformQualityProvider.notifier)
          .select(PlatformAudioQuality.jyMaster);
      expect(c.read(platformQualityProvider).switching, true);
      (c.read(platformAccountProvider.notifier) as TestAccount).replace('8');
      expect(c.read(platformQualityProvider).switching, false);
      audio.pending.complete(false);
      expect(await pending, false);
      expect(c.read(platformQualityProvider).switching, false);
      expect(
        prefs.getString('${PlatformQualityController.preferenceKey}_netease'),
        isNull,
      );
    },
  );
  const levels = [
    'standard',
    'higher',
    'exhigh',
    'lossless',
    'hires',
    'jyeffect',
    'sky',
    'jymaster',
    'dolby',
    'vivid',
  ];
  for (final level in levels) {
    test(
      'official $level retains its actual tier, including spatial encodings',
      () async {
        final music = repository(
          MockClient((request) async {
            final wire = eapiBody(request);
            expect(wire['level'], level);
            expect(wire['encodeType'], level == 'vivid' ? 'mp3' : 'flac');
            if (level == 'sky') expect(wire['immerseType'], 'c51');
            if (level == 'vivid') expect(wire['header']['os'], 'android');
            return response({
              'code': 200,
              'data': [
                {
                  'url': 'https://audio.example/song',
                  'level': level,
                  'br': 256000,
                  'time': 274000,
                },
              ],
            });
          }),
        );
        final quality = PlatformAudioQuality.fromNeteaseLevel(level)!;
        final track = await music.resolve(
          recording(),
          quality,
          requireQuality: true,
        );
        expect(track.playbackQuality, quality.code);
        expect(track.isPreview, false);
      },
    );
  }
  test(
    'enhanced request cannot turn a downgraded FLAC into a selected master',
    () async {
      final music = repository(
        MockClient(
          (_) async => response({
            'code': 200,
            'data': [
              {
                'url': 'https://audio.example/song',
                'level': 'lossless',
                'br': 900000,
              },
            ],
          }),
        ),
      );
      final source = SourceFixture('anonymous');
      final fallback = NeteaseFallbackResolver([
        source,
      ], MockClient((_) async => response({})));
      await expectLater(
        resolveNeteaseTrack(
          music: music,
          fallback: fallback,
          allowFallback: true,
          current: () => true,
          track: recording(),
          quality: PlatformAudioQuality.jyMaster,
          requireQuality: true,
        ),
        throwsA(isA<MusicPlatformException>()),
      );
      expect(source.searches, 0);
    },
  );
  test('existing Kugou persistence codes and fallback order are unchanged', () {
    expect(PlatformAudioQuality.values.take(4).map((v) => v.code), [
      '128',
      '320',
      'flac',
      'high',
    ]);
    expect(PlatformAudioQuality.hiRes.fallbackChain.map((v) => v.code), [
      'high',
      'flac',
      '320',
      '128',
    ]);
    expect(
      PlatformAudioQuality.fromNeteaseLevel('higher'),
      isNot(PlatformAudioQuality.high),
    );
  });
  test(
    'account level survives independent profile failure without a batch request',
    () async {
      final paths = <String>[];
      final music = repository(
        MockClient((req) async {
          paths.add(req.url.path);
          if (req.url.path.endsWith('/nuser/account/get')) {
            throw const SocketException('fixture reset');
          }
          if (req.url.path.endsWith('/user/level')) {
            return response({
              'code': 200,
              'data': {
                'level': 9,
                'nextPlayCount': 20000,
                'nowPlayCount': 17874,
                'nextLoginCount': 365,
                'nowLoginCount': 400,
                'info': '<b>60G</b>音乐云盘',
              },
            });
          }
          return response({'code': 200, 'mvCount': 0, 'artistCount': 8});
        }),
      );
      final overview = await loadNeteaseAccountOverview(music);
      expect(overview.level!.level, 9);
      expect(overview.level!.songsRemaining, 2126);
      expect(overview.level!.daysRemaining, 0);
      expect(overview.level!.benefits, '60G音乐云盘');
      expect(overview.failed, ['账号资料']);
      expect(overview.counts['artistCount'], 8);
      expect(paths, hasLength(3));
      expect(paths.any((p) => p.contains('/batch')), false);
    },
  );
  test('missing official level is unknown, while valid zero is retained', () {
    expect(
      NeteaseAccountLevel.parse({
        'data': {'level': 0},
      })!.level,
      0,
    );
    for (final value in [null, -1, 11, 'not-level']) {
      expect(
        NeteaseAccountLevel.parse({
          'data': {'level': value},
        }),
        isNull,
      );
    }
  });
  test(
    'level failure preserves real profile/counts and does not invent Lv.0',
    () async {
      final music = repository(
        MockClient((r) async {
          if (r.url.path.endsWith('/user/level')) {
            throw const SocketException('fixture');
          }
          if (r.url.path.endsWith('/nuser/account/get')) {
            return response({
              'code': 200,
              'profile': {'nickname': '测试用户'},
            });
          }
          return response({'code': 200, 'mvCount': 3});
        }),
      );
      final value = await loadNeteaseAccountOverview(music);
      expect(value.level, isNull);
      expect(value.profile['nickname'], '测试用户');
      expect(value.counts['mvCount'], 3);
      expect(value.failed, ['账号等级']);
    },
  );
  test(
    'purchased song IDs hydrate into playable rows instead of a count fact',
    () async {
      final music = repository(
        MockClient(
          (r) async => r.url.path.contains('mybought')
              ? response({
                  'code': 200,
                  'count': 1,
                  'data': [
                    {'songId': 7, 'price': 2},
                  ],
                })
              : response({
                  'code': 200,
                  'songs': [
                    {
                      'id': 7,
                      'name': '已购歌曲',
                      'ar': [
                        {'name': '歌手'},
                      ],
                      'al': {'name': '专辑'},
                      'dt': 274000,
                    },
                  ],
                }),
        ),
      );
      final payload = await NeteaseFullRepository(
        music,
      ).run(endpoint('/song/purchased'), {});
      final content = NeteaseContent.parse(payload, '/song/purchased');
      expect(content.rows.single.track!.id, 'netease_7');
      expect(content.rows.single.track!.title, '已购歌曲');
    },
  );
  test(
    'successful zero-count collection stays empty; account facts are not collections',
    () {
      expect(neteaseIsCollection('/song/purchased'), true);
      expect(neteaseIsCollection('/mv/sublist'), true);
      expect(neteaseIsCollection('/user/level'), false);
      expect(
        NeteaseContent.parse({
          'code': 200,
          'count': 0,
          'data': [],
        }, '/song/purchased').rows,
        isEmpty,
      );
    },
  );
  test('known MV CDN upgrades to TLS without changing signed query or path', () {
    const original =
        'http://vodkgeyttp8.vod.126.net/cloudmusic/fixture.mp4?wsSecret=fixture%2Fvalue&wsTime=1';
    final target = neteaseMediaUri(original)!;
    expect(target.scheme, 'https');
    expect(target.path, Uri.parse(original).path);
    expect(target.query, Uri.parse(original).query);
    expect(neteaseMediaUri('http://private.example/a')!.scheme, 'http');
    expect(neteaseMediaUri('https://user:password@vod.test/a'), isNull);
    expect(neteaseMediaUri('file:///tmp/video'), isNull);
  });
  test(
    'native local directory failure keeps the local error and never becomes a network error',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AudioDownloadStorage.channel,
            (call) async => throw PlatformException(
              code: 'permission',
              message: '保存目录授权已失效',
            ),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AudioDownloadStorage.channel, null),
      );
      await expectLater(
        const AudioDownloadStorage().openDirectory(
          uri: 'content://fixture/tree/a',
        ),
        throwsA(
          isA<DownloadStorageException>().having(
            (e) => e.message,
            'message',
            '保存目录授权已失效',
          ),
        ),
      );
    },
  );
}
