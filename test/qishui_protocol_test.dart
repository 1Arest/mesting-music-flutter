import 'package:flutter/services.dart';
import 'package:mesting_music/core/audio/mesting_audio_handler.dart';
import 'support/deterministic_audio_player.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_login.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_effects.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_welfare_page.dart';
import 'package:mesting_music/features/music_platform/domain/platform_audio_quality.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'netease_v116_recovery_test.dart' show mp3Response;

Future<Map<String, String>> fixtureContext() async => {
  'package': 'fixture.mesting',
  'os_api': '35',
};
http.Response fixtureJson(
  Object? data, {
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);
QishuiSession sodaSession([String uid = 'fixture-user']) => QishuiSession(
  userId: uid,
  cookies: [
    {
      'name': 'sessionid',
      'value': 'fixture-session-$uid',
      'domain': QishuiApi.host,
      'path': '/',
      'hostOnly': 'true',
      'secure': 'true',
    },
  ],
);
Track sodaRecording() => const Track(
  id: 'qishui_recording',
  platformSongId: 'recording',
  title: 'Fixture recording',
  artist: 'Fixture artist',
  album: 'Fixture album',
  duration: Duration(seconds: 230),
  audioAsset: 'mesting-platform://qishui/recording',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.qishui,
);
Map<String, Object> mediaFixture({
  int duration = 230,
  bool encrypted = false,
  int? quality,
}) => {
  'media': [
    {
      'entity': {
        'track_wrapper': {
          'track': {
            'player_info': {
              'video_model': {
                'video_duration': duration,
                if (encrypted) 'sp': 'fixture-encryption-key',
                'video_list': {
                  'audio': {
                    'main_url': base64Encode(
                      utf8.encode('https://cdn.example.test/audio'),
                    ),
                    'bitrate': 128000,
                    'quality': ?quality,
                  },
                },
              },
            },
          },
        },
      },
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'pinned catalog fixture yields exact Soda IDs and full catalog duration',
    () {
      final fixture = jsonDecode(
        File('test/fixtures/qishui-mobile-catalog.json').readAsStringSync(),
      );
      final tracks = sodaTracks(fixture['playlist-detail']);
      expect(
        tracks,
        hasLength(1),
        reason: 'Saved probe retains one bounded catalog example',
      );
      expect(tracks.first.id, 'qishui_6841692289832585217');
      expect(tracks.first.duration, const Duration(milliseconds: 233684));
      expect(tracks.first.source, TrackSource.qishui);
      expect(
        sodaTracks(fixture['playlist-detail']).map((t) => t.id).toSet().length,
        tracks.length,
      );
      expect(QishuiPlaylist.parse(fixture['discover-mix']), isNotEmpty);
    },
  );
  test(
    'Passport SDK vectors mix mobile and scenario once at the wire boundary',
    () {
      expect(qishuiMix('24'), '3731');
      expect(qishuiMix('123456'), '343736313033');
      expect(QishuiLogin.mobile('+86', '138 0000 0000'), '+8613800000000');
      expect(
        () => QishuiLogin.mobile('+86', '123'),
        throwsA(isA<QishuiException>()),
      );
    },
  );
  test(
    'phone flow requires business success, complete headers and own Luna identity',
    () async {
      final paths = <String>[];
      final api = QishuiApi(
        MockClient((request) async {
          paths.add(request.url.path);
          expect(request.url.host, QishuiApi.host);
          expect(request.url.queryParameters['aid'], '8478');
          expect(request.headers['x-helios'], isNull);
          if (request.url.path.endsWith('send_code/')) {
            expect(
              request.url.queryParameters['passport-sdk-version'],
              '601397',
            );
            expect(request.url.queryParameters['version_name'], '19.0.0');
            expect(request.url.queryParameters['version_code'], '100190050');
            expect(
              request.headers['content-type'],
              contains('application/x-www-form-urlencoded'),
            );
            final form = Uri.splitQueryString(request.body);
            expect(form['mobile'], '2e3d3334363d3535353535353535');
            expect(form['type'], '3731');
            expect(form['unbind_exist'], qishuiMix('0'));
            expect(form['auto_read'], '0');
            expect(form.containsKey('is_from_iesaccountsaas'), false);
            return fixtureJson({
              'message': 'success',
              'data': {'sms_code_key': 'fixture-key'},
            });
          }
          if (request.url.path.endsWith('sms_login/')) {
            final form = Uri.splitQueryString(request.body);
            expect(form['code'], '343736313033');
            expect(form.containsKey('sms_code_key'), false);
            expect(form.containsKey('is_from_iesaccountsaas'), false);
            expect(form['mobile'], qishuiMix('+8613800000000'));
            return fixtureJson(
              {
                'message': 'success',
                'data': {'user_id': 'fixture-user'},
              },
              headers: {
                'set-cookie':
                    'sessionid=fixture-session; Path=/; Secure; HttpOnly; Expires=Wed, 01 Jan 2031 00:00:00 GMT, passport_csrf_token=fixture-csrf; Path=/; Secure',
                'x-tt-token': 'fixture-token',
              },
            );
          }
          expect(
            request.headers['cookie'],
            contains('sessionid=fixture-session'),
          );
          expect(request.headers['x-tt-passport-csrf-token'], 'fixture-csrf');
          return fixtureJson({
            'status_code': 0,
            'my_info': {'id': 'fixture-user', 'nickname': 'Fixture user'},
          });
        }),
        context: fixtureContext,
      );
      final login = QishuiLogin(api);
      addTearDown(login.dispose);
      await login.sendCode('+86', '13800000000');
      final session = await login.login('+86', '13800000000', '123456');
      expect(session.complete, isTrue);
      expect(session.nickname, 'Fixture user');
      expect(paths, [
        '/passport/mobile/send_code/',
        '/passport/mobile/sms_login/',
        '/luna/me',
      ]);
      expect(
        api.session,
        isNull,
        reason: 'Login uses a private jar and never publishes itself',
      );
      expect(session.identity.token, isNot(contains('fixture-session')));
    },
  );
  test(
    'business SMS refusal is never retried or reported as success',
    () async {
      var calls = 0;
      final login = QishuiLogin(
        QishuiApi(
          MockClient((_) async {
            calls++;
            return fixtureJson({
              'message': 'error',
              'data': {'error_code': 1000062},
            });
          }),
          context: fixtureContext,
        ),
      );
      addTearDown(login.dispose);
      await expectLater(
        login.sendCode('+86', '13800000000'),
        throwsA(isA<QishuiException>()),
      );
      expect(calls, 1);
      await expectLater(
        login.login('+86', '13800000000', '123456'),
        throwsA(isA<QishuiException>()),
      );
      expect(calls, 1);
    },
  );
  test('success JSON without session cookies is not a login', () async {
    final login = QishuiLogin(
      QishuiApi(
        MockClient(
          (_) async => fixtureJson({
            'message': 'success',
            'data': {'user_id': 'fixture-user'},
          }),
        ),
        context: fixtureContext,
      ),
    );
    addTearDown(login.dispose);
    await login.sendCode('+86', '13800000000');
    await expectLater(
      login.login('+86', '13800000000', '123456'),
      throwsA(isA<QishuiException>()),
    );
  });
  test(
    'malformed and empty HTTP200 results cannot become usable data',
    () async {
      for (final body in ['', '{}', '[]', '<html>not-json</html>']) {
        final api = QishuiApi(
          MockClient((_) async => http.Response(body, 200)),
          context: fixtureContext,
        )..configure(sodaSession());
        await expectLater(
          api.request('/luna/me', get: true),
          throwsA(isA<QishuiException>()),
        );
      }
    },
  );
  test('an old account response cannot mutate the new cookie jar', () async {
    final response = Completer<http.Response>(), started = Completer<void>();
    final api = QishuiApi(
      MockClient((_) {
        started.complete();
        return response.future;
      }),
      context: fixtureContext,
    )..configure(sodaSession('old'));
    final pending = api.request('/luna/me', get: true);
    final failure = expectLater(pending, throwsA(isA<QishuiException>()));
    await started.future;
    api.configure(sodaSession('new'));
    response.complete(
      fixtureJson(
        {'status_code': 0},
        headers: {'set-cookie': 'sessionid=late-old; Path=/; Secure'},
      ),
    );
    await failure;
    expect(api.snapshot('new').cookies.single['value'], 'fixture-session-new');
  });
  test(
    'expired and unrelated cookies never accompany a Luna request',
    () async {
      final session = QishuiSession(
        userId: 'fixture',
        cookies: [
          ...sodaSession().cookies,
          {
            'name': 'expired',
            'value': 'do-not-send',
            'domain': QishuiApi.host,
            'path': '/',
            'expires': '2020-01-01T00:00:00Z',
          },
          {
            'name': 'foreign',
            'value': 'do-not-send',
            'domain': 'other.example',
            'path': '/',
          },
        ],
      );
      final api = QishuiApi(
        MockClient((request) async {
          expect(request.headers['cookie'], isNot(contains('do-not-send')));
          return fixtureJson({'status_code': 0});
        }),
        context: fixtureContext,
      )..configure(session);
      await api.request('/luna/me', get: true);
    },
  );
  test('unsupported encrypted models never enter audio transport', () async {
    for (final data in [mediaFixture(encrypted: true)]) {
      var cdnCalls = 0;
      final api = QishuiApi(
        MockClient((request) async {
          if (request.url.host != QishuiApi.host) cdnCalls++;
          return fixtureJson(data);
        }),
        context: fixtureContext,
      )..configure(sodaSession());
      await expectLater(
        QishuiRepository(api).resolve(sodaRecording()),
        throwsA(isA<QishuiException>()),
      );
      expect(cdnCalls, 0);
    }
  });
  test(
    'actual audio header supplies quality and receives no private headers',
    () async {
      final api = QishuiApi(
        MockClient((request) async {
          if (request.url.host == QishuiApi.host) {
            return fixtureJson(mediaFixture());
          }
          expect(request.headers['cookie'], isNull);
          expect(request.headers['x-tt-token'], isNull);
          return mp3Response(230);
        }),
        context: fixtureContext,
      )..configure(sodaSession());
      final resolved = await QishuiRepository(api).resolve(sodaRecording());
      expect(resolved.source, TrackSource.qishui);
      expect(resolved.audioOrigin?.adapter, AudioOrigin.qishui);
      expect(resolved.playbackQuality, PlatformAudioQuality.standard.code);
      expect(jsonEncode(resolved.toJson()), isNot(contains('fixture-session')));
      expect(resolved.toMediaItem().extras?['audioHeaders'], isEmpty);
    },
  );
  test('streaming permission alone cannot authorize a download', () async {
    final api = QishuiApi(
      MockClient((_) async => fixtureJson(mediaFixture())),
      context: fixtureContext,
    )..configure(sodaSession());
    await expectLater(
      QishuiRepository(api).resolve(sodaRecording(), download: true),
      throwsA(isA<QishuiException>()),
    );
  });
  test(
    'download needs the exact track, quality and an explicit unmetered grant',
    () async {
      final paths = <String>[];
      final api = QishuiApi(
        MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.host != QishuiApi.host) return mp3Response(230);
          if (request.url.path.endsWith('check_download')) {
            expect(jsonDecode(request.body), {
              'tracks': [
                {'track_id': 'recording', 'quality': 7},
              ],
            });
            return fixtureJson({
              'status_code': 0,
              'track_download_info_list': [
                {
                  'track_id': 'recording',
                  'quality': 7,
                  'need_download_quota': false,
                },
              ],
            });
          }
          return fixtureJson(mediaFixture(quality: 7));
        }),
        context: fixtureContext,
      )..configure(sodaSession());
      final resolved = await QishuiRepository(
        api,
      ).resolve(sodaRecording(), download: true);
      expect(resolved.isPreview, isFalse);
      expect(paths, contains('/luna/commerce/v2/check_download'));
    },
  );
  test(
    'effect grants cannot be inferred from activity VIP or expired local data',
    () {
      final commerce = <String, dynamic>{
        'status_info': {'now': 100},
        'membership': {'is_membership': true},
        'benefit_base': {
          'audio_effect': {
            'audio_effect_detail': {
              'bass': {'stage': 'free', 'expire_time': 200},
            },
          },
        },
      };
      expect(qishuiEffectGrant(commerce, 'bass'), isNotNull);
      expect(qishuiEffectGrant(commerce, 'ungranted'), isNull);
      (commerce['status_info'] as Map)['now'] = 201;
      expect(qishuiEffectGrant(commerce, 'bass'), isNull);
    },
  );
  test(
    'late effect qualification cannot re-enable DSP after account reset',
    () async {
      final returned = Completer<http.Response>(), started = Completer<void>();
      final api = QishuiApi(
        MockClient((_) {
          started.complete();
          return returned.future;
        }),
        context: fixtureContext,
      )..configure(sodaSession());
      final writes = <String?>[];
      final coordinator = QishuiEffectCoordinator(
        current: () => true,
        send: (config) async {
          writes.add(config);
          return {'configured': config != null, 'failure': ''};
        },
        status: () async => {},
      );
      addTearDown(coordinator.dispose);
      final selected = coordinator.select(
        const QishuiEffect('bass', 'bass', '{}'),
        QishuiRepository(api),
      );
      final failure = expectLater(selected, throwsA(isA<QishuiException>()));
      await started.future;
      coordinator.reset();
      returned.complete(
        fixtureJson({
          'status_info': {'now': 100},
          'benefit_base': {
            'audio_effect': {
              'audio_effect_detail': {
                'bass': {'stage': 'free', 'expire_time': 200},
              },
            },
          },
        }),
      );
      await failure;
      expect(writes.whereType<String>(), isEmpty);
    },
  );
  test('expired CSRF cookies are never sent as header credentials', () async {
    final api =
        QishuiApi(
          MockClient((request) async {
            expect(
              request.headers['cookie'],
              isNot(contains('expired-secret')),
            );
            expect(request.headers['x-tt-passport-csrf-token'], isNull);
            return fixtureJson({'status_code': 0});
          }),
          context: fixtureContext,
        )..configure(
          QishuiSession(
            userId: 'fixture-user',
            cookies: [
              ...sodaSession().cookies,
              {
                'name': 'passport_csrf_token',
                'value': 'expired-secret',
                'domain': QishuiApi.host,
                'path': '/',
                'expires': '2000-01-01T00:00:00Z',
              },
            ],
          ),
        );
    await api.request('/luna/me', get: true);
  });
  test(
    'a rotated session is durably persisted with the same account epoch',
    () async {
      final original = sodaSession();
      QishuiSession? saved;
      late QishuiApi api;
      api = QishuiApi(
        MockClient(
          (_) async => fixtureJson(
            {'status_code': 0},
            headers: {
              'Set-Cookie':
                  'sessionid=fixture-rotated; Path=/; Secure; HttpOnly',
            },
          ),
        ),
        context: fixtureContext,
        persistRefresh: (expected, updated) async {
          expect(expected.credentialId, original.credentialId);
          saved = updated;
          api.acknowledgeRefresh(expected, updated);
        },
      )..configure(original);
      await api.request('/luna/me', get: true);
      expect(saved!.cookies.single['value'], 'fixture-rotated');
      expect(api.credential, original.credentialId);
    },
  );
  test(
    'preparation failure cannot be classified as an unknown dispatched write',
    () async {
      var sent = false;
      final api = QishuiApi(
        MockClient((_) async {
          sent = true;
          return fixtureJson({});
        }),
        context: () async => throw StateError('fixture context unavailable'),
      );
      await expectLater(
        api.request(
          '/passport/mobile/send_code/',
          authenticated: false,
          write: true,
        ),
        throwsA(
          isA<QishuiException>().having(
            (e) => e.unknownWrite,
            'unknown write',
            isFalse,
          ),
        ),
      );
      expect(sent, isFalse);
    },
  );
  test(
    'an unconfirmed SMS may be submitted if it actually arrives without resending',
    () async {
      var sends = 0;
      final api = QishuiApi(
        MockClient((request) async {
          if (request.url.path.endsWith('send_code/')) {
            sends++;
            throw http.ClientException('fixture lost response');
          }
          if (request.url.path.endsWith('sms_login/')) {
            return fixtureJson(
              {
                'message': 'success',
                'data': {'user_id': 'fixture-passport'},
              },
              headers: {
                'set-cookie': 'sessionid=fixture-session; Path=/; Secure',
              },
            );
          }
          return fixtureJson({
            'status_code': 0,
            'my_info': {'id': 'fixture-luna'},
          });
        }),
        context: fixtureContext,
      );
      final login = QishuiLogin(api);
      addTearDown(login.dispose);
      await expectLater(
        login.sendCode('+86', '13800000000'),
        throwsA(isA<QishuiException>()),
      );
      final result = await login.login('+86', '13800000000', '123456');
      expect(result.userId, 'fixture-luna');
      expect(result.passportUserId, 'fixture-passport');
      expect(sends, 1);
    },
  );
  test(
    'old activity calendar entries never confirm today or replace missing server time',
    () {
      final value = QishuiWelfareStatus({
        'status_info': {'now_ts_ms': 1793923200000},
        'activity_free_vip': {
          'start_time_sec': 1,
          'end_time_sec': 1999999999,
          'calendar_dates': [
            {'date': '2000-01-01', 'status': 8},
          ],
        },
      });
      expect(value.claimed, isFalse);
      expect(
        QishuiWelfareStatus({
          'activity_free_vip': {
            'start_time_sec': 1,
            'end_time_sec': 1999999999,
          },
        }).claimable,
        isFalse,
      );
    },
  );
  test('catalog milliseconds never stand in for missing player duration', () {
    final value = QishuiMedia.parse({
      'track': {
        'duration': 230000,
        'player_info': {
          'video_model': {
            'video_list': {
              'audio': {
                'main_url': 'https://cdn.example.test/preview',
                'bitrate': 128000,
              },
            },
          },
        },
      },
    });
    expect(value, hasLength(1));
    expect(value.single.duration, Duration.zero);
  });
  test(
    'late playback resolution cannot load audio after the selecting owner is gone',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mesting_soda_owner_',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      final player = DeterministicAudioPlayer();
      final handler = MestingAudioHandler(tracks: [], player: player);
      addTearDown(() async {
        await handler.debugDispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (directory.absolute.path.startsWith(
          Directory.systemTemp.absolute.path,
        )) {
          await directory.delete(recursive: true);
        }
      });
      await handler.replaceQueue([], autoplay: false);
      final loads = player.loads;
      final started = Completer<void>(), response = Completer<Track>();
      var current = true;
      handler.configureTrackPlaybackResolver((track) {
        started.complete();
        return response.future;
      });
      final selection = handler.playSingleTrack(
        sodaRecording(),
        isCurrent: () => current,
      );
      await started.future;
      current = false;
      response.complete(sodaRecording());
      await selection;
      expect(player.loads, loads);
      expect(player.active, isFalse);
    },
  );
  test('line timing survives Soda verbatim lyric conversion', () {
    expect(qishuiLrc('[12345,2000]<0,100,0>你<100,200,0>好'), '[00:12.345]你好');
    expect(qishuiLrc('[00:12.34]original'), '[00:12.34]original');
  });
  test(
    'activity calendar success and advertising minutes stay independent',
    () {
      final value = QishuiWelfareStatus({
        'status_info': {'now_ts_ms': 1793923200000},
        'activity_free_vip': {
          'start_time_sec': 1,
          'end_time_sec': 1999999999,
          'calendar_dates': [
            {'date': '2026-11-06', 'status': 8},
          ],
        },
        'play_entitlements': {'reward_tasks_finished': 0},
      });
      expect(value.claimed, isTrue);
      expect(value.claimable, isFalse);
      expect(value.listening['reward_tasks_finished'], 0);
      expect(
        qishuiClaimJournalKey('a', '2026-11-06'),
        isNot(qishuiClaimJournalKey('b', '2026-11-06')),
      );
    },
  );
}
