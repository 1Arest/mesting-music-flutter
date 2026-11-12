import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_official_audio_cache.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playback_media.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';

import 'netease_v116_recovery_test.dart' show mp3Response;
import 'qishui_protocol_test.dart' show sodaRecording, mediaFixture;
import 'qishui_signed_api167_test.dart' show FixtureSigner, account, reply;

const _player = 'https://vod-luna.douyin.com/player?fixture=private-query170';
const _audio = 'https://audio.example.test/complete';
const _clip = 'https://audio.example.test/preview';

Map<String, Object> _deferred([String player = _player]) => {
  'track_info': {'duration': 230000},
  'track_player': {'url_player_info': player},
};

Map<String, Object> _model({int seconds = 230, String field = 'MainPlayUrl'}) =>
    {
      'Result': {
        'Data': {
          'PlayInfoList': [
            {
              field: seconds == 230 ? _audio : _clip,
              'Duration': seconds,
              'Bitrate': 128000,
              'Format': 'mp3',
            },
          ],
        },
      },
    };

QishuiApi _api(Future<http.Response> Function(http.Request) send) =>
    QishuiApi(MockClient(send), signer: FixtureSigner())..configure(account());

void _anonymous(http.Request request) {
  for (final name in [
    'cookie',
    'authorization',
    'x-tt-token',
    'x-helios',
    'x-medusa',
  ]) {
    expect(request.headers[name], isNull, reason: name);
  }
  if (request.url.host == 'vod-luna.douyin.com') {
    expect(request.followRedirects, isFalse);
    expect(request.headers['user-agent'], startsWith('Mozilla/5.0'));
    expect(request.headers['accept'], 'application/json');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(MusicNetworkDiagnostics.shared.clear);

  test(
    'sanitized retained official reply keeps real model nesting and preview duration',
    () async {
      final fixture = jsonDecode(
        await File(
          'test/fixtures/qishui170_anonymous_media_shape.json',
        ).readAsString(),
      );
      final streams = QishuiMedia.parse(fixture);
      expect(streams, isNotEmpty);
      expect(streams.every((media) => media.canDecodeOfficial), isTrue);
      expect(
        streams.every((media) => media.duration == const Duration(seconds: 60)),
        isTrue,
      );
      final selection = QishuiPlaybackSelection.choose(
        streams,
        catalogDuration: const Duration(seconds: 230),
        download: false,
        requireQuality: false,
      );
      expect(selection.isPreview, isTrue);
      final links = qishuiPlayerInfoUris(fixture);
      expect(links.single.host, 'vod-luna.douyin.com');
      expect(qishuiTrustedPlayerInfo(links.single), isTrue);
      expect(links.single.hasQuery, isFalse);
    },
  );

  test(
    'deferred official Luna origin reaches audio through the production signed API',
    () async {
      final requests = <String>[];
      final api = _api((request) async {
        requests.add(request.url.host);
        if (request.url.host == 'api.qishui.com') {
          expect(request.url.path, '/luna/pc/track_v2');
          expect(request.method, 'POST');
          expect(request.headers['x-helios'], isNotEmpty);
          expect(request.headers['cookie'], isNotEmpty);
          return reply(_deferred());
        }
        _anonymous(request);
        if (request.url.host == 'vod-luna.douyin.com') return reply(_model());
        expect(request.url.toString(), _audio);
        return mp3Response(230);
      });
      final track = await QishuiRepository(api).resolve(sodaRecording());
      expect(track.isPreview, isFalse);
      expect(track.audioAsset, _audio);
      expect(requests, [
        'api.qishui.com',
        'vod-luna.douyin.com',
        'audio.example.test',
      ]);
      final exported = MusicNetworkDiagnostics.shared.export();
      expect(exported, contains('playerInfoRead'));
      expect(exported, contains('mediaModelParse'));
      expect(exported, contains('audioVerify'));
      for (final private in [
        'private-query170',
        'fixture-session',
        _player,
        _audio,
      ]) {
        expect(exported, isNot(contains(private)));
      }
    },
  );

  test(
    'official preview is playable and labeled while catalog duration remains intact',
    () async {
      final api = _api((request) async {
        if (request.url.host == 'api.qishui.com') return reply(_deferred());
        _anonymous(request);
        if (request.url.host == 'vod-luna.douyin.com') {
          return reply(_model(seconds: 30));
        }
        return mp3Response(30);
      });
      final result = await QishuiRepository(api).resolve(sodaRecording());
      expect(result.isPreview, isTrue);
      expect(result.duration, const Duration(seconds: 230));
      expect(result.toMediaItem().extras?['isPreview'], isTrue);
      expect(result.audioAsset, _clip);
    },
  );

  test('full official media outranks a higher bitrate preview', () async {
    final api = _api((request) async {
      if (request.url.host == 'api.qishui.com') {
        return reply({
          'track_player': {
            'video_model': {
              'video_list': [
                {'main_url': _clip, 'duration': 30, 'bitrate': 320000},
                {'main_url': _audio, 'duration': 230, 'bitrate': 128000},
              ],
            },
          },
        });
      }
      expect(request.url.toString(), _audio);
      return mp3Response(230);
    });
    final result = await QishuiRepository(api).resolve(sodaRecording());
    expect(result.audioAsset, _audio);
    expect(result.isPreview, isFalse);
  });

  test(
    'an already granted full recording does not depend on optional player info',
    () async {
      var optionalCalls = 0;
      final api = _api((request) async {
        if (request.url.host == 'api.qishui.com') {
          return reply({...mediaFixture(), ..._deferred()});
        }
        if (request.url.host == 'vod-luna.douyin.com') {
          optionalCalls++;
          return http.Response('unavailable', 503);
        }
        return mp3Response(230);
      });
      expect(
        (await QishuiRepository(api).resolve(sodaRecording())).isPreview,
        isFalse,
      );
      expect(optionalCalls, 0);
    },
  );

  test(
    'an optional link failure retains an authorized embedded preview',
    () async {
      final api = _api((request) async {
        if (request.url.host == 'api.qishui.com') {
          return reply({...mediaFixture(duration: 30), ..._deferred()});
        }
        if (request.url.host == 'vod-luna.douyin.com') {
          return http.Response('', 503);
        }
        return mp3Response(30);
      });
      expect(
        (await QishuiRepository(api).resolve(sodaRecording())).isPreview,
        isTrue,
      );
      expect(
        MusicNetworkDiagnostics.shared.rows.any(
          (row) => row['phase'] == 'playerInfoRead' && row['status'] == 503,
        ),
        isTrue,
      );
    },
  );

  test(
    'preview never becomes a full download or dispatches a quota check',
    () async {
      final paths = <String>[];
      final api = _api((request) async {
        paths.add(request.url.path);
        return reply(mediaFixture(duration: 30));
      });
      await expectLater(
        QishuiRepository(api).resolve(sodaRecording(), download: true),
        throwsA(
          isA<QishuiException>().having(
            (error) => error.kind,
            'kind',
            QishuiFailureKind.entitlement,
          ),
        ),
      );
      expect(paths, ['/luna/pc/track_v2']);
    },
  );

  test(
    'encrypted official preview passes the real private-cache orchestration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qishui170-preview_',
      );
      const channel = MethodChannel('fixture/qishui170-preview');
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, Object?>.from(call.arguments as Map);
            if (call.method == 'prepare') {
              expect(args['encrypted'], isTrue);
              expect(args['playAuth'], 'fixture-ephemeral-auth170');
              await File(
                args['source'] as String,
              ).copy(args['output'] as String);
              return {'path': args['output']};
            }
            expect(call.method, 'inspect');
            return {
              'durationUs': 30000000,
              'format': 'm4a',
              'bytes': 4,
              'bitrate': 64000,
            };
          });
      final api = _api((request) async {
        if (request.url.host == 'api.qishui.com') {
          return reply({
            'track_player': {
              'video_model': {
                'video_duration': 30,
                'video_list': [
                  {
                    'main_url': _clip,
                    'video_meta': {'size': 4, 'vtype': 'm4a', 'bitrate': 64000},
                    'encrypt_info': {
                      'encrypt': true,
                      'spade_a': 'fixture-ephemeral-auth170',
                      'encryption_method': 'cenc-aes-ctr',
                    },
                  },
                ],
              },
            },
          });
        }
        _anonymous(request);
        return http.Response.bytes(
          [1, 2, 3, 4],
          200,
          headers: {'content-length': '4'},
        );
      });
      final cache = QishuiOfficialAudioCache(
        api.client,
        channel: channel,
        temporaryDirectory: () async => directory,
      );
      // The repository independently inspects the cache using its production
      // channel; both metadata reads must validate the actual 30s stream.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            QishuiOfficialAudioCache.channelDefault,
            (_) async => {
              'durationUs': 30000000,
              'format': 'm4a',
              'bytes': 4,
              'bitrate': 64000,
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              QishuiOfficialAudioCache.channelDefault,
              null,
            ),
      );
      final result = await QishuiRepository(
        api,
        audioCache: cache,
      ).resolve(sodaRecording());
      expect(result.isPreview, isTrue);
      expect(result.duration, const Duration(seconds: 230));
      expect(await File.fromUri(Uri.parse(result.audioAsset)).exists(), isTrue);
      expect(
        MusicNetworkDiagnostics.shared.export(),
        isNot(contains('fixture-ephemeral-auth170')),
      );
      expect(
        MusicNetworkDiagnostics.shared.rows.any(
          (row) => row['phase'] == 'audioDecode',
        ),
        isTrue,
      );
    },
  );

  for (final player in [
    'http://vod-luna.douyin.com/player',
    'https://vod-luna.douyin.com.evil.test/player',
    'https://vod-luna-douyin.com/player',
    'https://private@vod-luna.douyin.com/player',
    'https://vod-luna.douyin.com:444/player',
    'https://vod-luna.douyin.com/player#fragment',
  ]) {
    test('untrusted player info cannot dispatch: $player', () async {
      var requests = 0;
      final api = _api((request) async {
        requests++;
        expect(request.url.host, 'api.qishui.com');
        return reply(_deferred(player));
      });
      await expectLater(
        QishuiRepository(api).resolve(sodaRecording()),
        throwsA(
          isA<QishuiException>().having(
            (error) => error.kind,
            'kind',
            QishuiFailureKind.format,
          ),
        ),
      );
      expect(requests, 1);
    });
  }

  for (final status in [302, 401, 403, 503]) {
    test(
      'player info HTTP $status is classified separately from signer success',
      () async {
        final api = _api(
          (request) async => request.url.host == 'api.qishui.com'
              ? reply(_deferred())
              : http.Response('', status),
        );
        await expectLater(
          QishuiRepository(api).resolve(sodaRecording()),
          throwsA(
            isA<QishuiException>().having(
              (error) => error.message,
              'stage',
              contains('播放资料请求'),
            ),
          ),
        );
        expect(
          MusicNetworkDiagnostics.shared.rows.any(
            (row) =>
                row['phase'] == 'playerInfoRead' && row['status'] == status,
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'HTTP200 malformed player info is not reported as a signer outage',
    () async {
      final api = _api(
        (request) async => request.url.host == 'api.qishui.com'
            ? reply(_deferred())
            : http.Response('not-json', 200),
      );
      await expectLater(
        QishuiRepository(api).resolve(sodaRecording()),
        throwsA(
          isA<QishuiException>().having(
            (error) => error.message,
            'stage',
            contains('返回格式'),
          ),
        ),
      );
      expect(
        MusicNetworkDiagnostics.shared.rows.last['phase'],
        'playerInfoRead',
      );
      expect(MusicNetworkDiagnostics.shared.rows.last['outcome'], 'format');
    },
  );

  test(
    'account changes revoke a delayed player-info result before audio fetch',
    () async {
      final response = Completer<http.Response>();
      final entered = Completer<void>();
      final api = _api((request) async {
        if (request.url.host == 'api.qishui.com') return reply(_deferred());
        expect(request.url.host, 'vod-luna.douyin.com');
        entered.complete();
        return response.future;
      });
      final pending = QishuiRepository(api).resolve(sodaRecording());
      final assertion = expectLater(pending, throwsA(isA<QishuiException>()));
      await entered.future;
      api.configure(null);
      response.complete(reply(_model()));
      await assertion;
    },
  );

  for (final field in ['MainUrl', 'PlayURL', 'URL']) {
    test('primary-source $field spelling works inside player model only', () {
      final result = QishuiMedia.parse({
        'track_player': {
          'video_model': {
            'video_duration': 60,
            'video_list': {
              'audio': {
                field: _clip,
                'video_meta': {'bitrate': 128000},
              },
            },
          },
        },
      });
      expect(result.single.url, _clip);
      expect(result.single.duration, const Duration(seconds: 60));
      expect(
        QishuiMedia.parse({
          'track_info': {'url': _audio, 'duration': 230000},
        }),
        isEmpty,
      );
    });
  }

  test('catalog milliseconds never extend the actual preview duration', () {
    final streams = QishuiMedia.parse({
      'track_info': {'duration': 230000},
      'track_player': {
        'video_model': {
          'video_duration': 30,
          'video_list': [
            {
              'main_url': _clip,
              'video_meta': {'bitrate': 128000},
            },
          ],
        },
      },
    });
    final selection = QishuiPlaybackSelection.choose(
      streams,
      catalogDuration: const Duration(seconds: 230),
      download: false,
      requireQuality: true,
    );
    expect(selection.isPreview, isTrue);
    expect(selection.media.duration, const Duration(seconds: 30));
  });

  test('duplicate URL cannot hide a later explicit encryption requirement', () {
    final streams = QishuiMedia.parse({
      'player_models': [
        {'main_url': _audio, 'duration': 230},
        {
          'main_url': _audio,
          'duration': 230,
          'encrypt_info': {'encrypt': true},
        },
      ],
    });
    expect(streams.single.encrypted, isTrue);
    expect(streams.single.canDecodeOfficial, isFalse);
  });

  test(
    'required high quality cannot silently choose a high bitrate preview over full standard',
    () {
      final streams = QishuiMedia.parse({
        'player_models': [
          {'main_url': _audio, 'duration': 230, 'bitrate': 128000},
          {'main_url': _clip, 'duration': 30, 'bitrate': 320000},
        ],
      });
      expect(
        () => QishuiPlaybackSelection.choose(
          streams,
          catalogDuration: const Duration(seconds: 230),
          download: false,
          quality: PlatformAudioQuality.high,
          requireQuality: true,
        ),
        throwsA(isA<QishuiException>()),
      );
    },
  );

  for (final encrypted in [false, true]) {
    test(
      'missing URL and unsupported authorization have distinct messages: $encrypted',
      () {
        final streams = encrypted
            ? QishuiMedia.parse({'main_url': _audio, 'encrypt': true})
            : <QishuiMedia>[];
        expect(
          () => QishuiPlaybackSelection.choose(
            streams,
            catalogDuration: const Duration(seconds: 230),
            download: false,
            requireQuality: true,
          ),
          throwsA(
            isA<QishuiException>().having(
              (error) => error.message,
              'message',
              contains(encrypted ? '缺少播放授权' : '没有可识别'),
            ),
          ),
        );
      },
    );
  }

  test(
    'diagnostic counts are bounded and do not introduce arbitrary payloads',
    () {
      MusicNetworkDiagnostics.shared.record(
        platform: 'qishui',
        operation: MusicNetworkOperation.playbackUrl,
        outcome: MusicNetworkOutcome.format,
        phase: MusicDiagnosticPhase.mediaModelParse,
        streamCandidates: 999999,
        decodableStreams: -2,
        playerInfoUrls: 999999,
      );
      final exported =
          jsonDecode(MusicNetworkDiagnostics.shared.export()) as Map;
      final row = (exported['events'] as List).single as Map;
      expect(row['streamCandidates'], 1000);
      expect(row['decodableStreams'], 0);
      expect(row['playerInfoUrls'], 1000);
    },
  );
}
