import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/audio/actual_listening_counter.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_reporter.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_listening_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';
import 'package:mesting_music/shared/models/track.dart';

class _Clock implements ListeningClock {
  int ms = 0;
  @override
  int get elapsedMicroseconds => ms * 1000;
  @override
  DateTime get now => DateTime.utc(2026, 11, 7).add(Duration(milliseconds: ms));
  void advance(int value) => ms += value;
}

class _Store implements QishuiListeningStore {
  final values = <String, QishuiListeningLedger>{};
  @override
  Future<QishuiListeningLedger> read(String owner) async =>
      values[owner] ?? const QishuiListeningLedger();
  @override
  Future<void> write(String owner, QishuiListeningLedger value) async {
    values[owner] = value;
  }
}

class _Signer implements QishuiRequestSigner {
  int calls = 0;
  final String did;
  _Signer({this.did = '12345678901234'});
  @override
  Future<Map<String, String>> identity(Future<void> abort) async => {
    'device_id': did,
    'iid': '12345678901235',
    'fp': 'fixture177',
    'user_agent': 'LunaPC/3.7.0(452316191)',
  };
  @override
  void invalidateIdentity() {}
  @override
  Future<QishuiSignedRequest> sign(
    Uri uri,
    String method,
    String body,
    Map<String, String> headers,
    Future<void> abort,
  ) async {
    calls++;
    return QishuiSignedRequest(uri, const {
      'x-helios': 'fixture-helios177',
      'x-medusa': 'fixture-medusa177',
    });
  }
}

QishuiSession _session(String owner) => QishuiSession(
  userId: owner,
  protocol: QishuiSessionProtocol.web,
  cookies: const [
    {
      'name': 'sessionid',
      'value': 'music-private177',
      'domain': 'api.qishui.com',
      'path': '/',
      'secure': 'true',
    },
  ],
  tokens: const {'x-tt-token': 'fixture-token177'},
);

Track _song(String id) => Track(
  id: 'qishui_$id',
  platformSongId: id,
  title: 'Fixture $id',
  artist: 'Fixture',
  album: '',
  duration: const Duration(minutes: 4),
  audioAsset: 'file:///fixture/$id.m4a',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.qishui,
);

http.Response _reply(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'music wall seconds remain separate from event milliseconds and missing values',
    () {
      final snapshot = QishuiListeningSnapshot.parse({
        'listen_duration': {'total_duration': 3601, 'week_duration': '125'},
      }, fetchedAt: DateTime.utc(2026, 11, 7));
      expect(snapshot.totalSeconds, 3601);
      expect(snapshot.weekSeconds, 125);
      expect(snapshot.likeCount, isNull);
      expect(
        () => QishuiListeningSnapshot.parse({
          'listen_duration': {'total_duration': 1.5},
        }, fetchedAt: DateTime.now()),
        throwsA(isA<QishuiException>()),
      );
      expect(
        () => QishuiListeningSnapshot.parse({}, fetchedAt: DateTime.now()),
        throwsA(isA<QishuiException>()),
      );
    },
  );

  test(
    'official music wall is a signed common POST read and owner-bound',
    () async {
      final signer = _Signer();
      final api = QishuiApi(
        MockClient((request) async {
          expect(request.url.path, '/luna/me/music_wall');
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'feed_music_wall_extra': <String, Object>{},
            'ab_param':
                '{"enable_new_music_wall":1,"enable_fav_artists":false,"enable_fav_playables":false}',
          });
          expect(request.headers['cookie'], 'sessionid=music-private177');
          expect(request.headers['x-helios'], 'fixture-helios177');
          return _reply({
            'listen_duration': {'total_duration': 172800},
          });
        }),
        signer: signer,
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: _Store(),
      );
      expect((await repository.fetch()).totalSeconds, 172800);
      api.configure(_session('9002'));
      await expectLater(repository.fetch(), throwsA(isA<QishuiException>()));
    },
  );

  test(
    'MCS uses real signer device/account but sends no official Cookie or application signatures',
    () async {
      final signer = _Signer();
      final store = _Store();
      final api = QishuiApi(
        MockClient((request) async {
          expect(request.url, Uri.parse('https://mcs.zijieapi.com/v1/json'));
          expect(request.followRedirects, false);
          expect(request.headers['cookie'], isNull);
          expect(request.headers['x-tt-token'], isNull);
          expect(request.headers['x-helios'], isNull);
          expect(request.headers['authorization'], isNull);
          expect(
            request.headers['x-ss-stub'],
            md5.convert(utf8.encode(request.body)).toString().toUpperCase(),
          );
          expect(request.body, isNot(contains('music-private177')));
          final body = jsonDecode(request.body) as Map;
          expect(body['user']['user_id'], '9001');
          expect(body['user']['device_id'], '12345678901234');
          expect(body['header']['app_version'], '3.7.0');
          expect(body['header']['os_version'], isNull);
          expect(body['header']['custom'], isA<String>());
          expect(body['events'][0]['params'], isA<String>());
          return _reply({'message': 'success'});
        }),
        signer: signer,
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: store,
      );
      expect(
        await repository.submit(
          [
            QishuiListeningEvent('audio_over', {
              'duration': 1000,
            }, DateTime.utc(2026, 11, 7)),
          ],
          heardMilliseconds: 1000,
          playing: false,
        ),
        QishuiListeningDelivery.accepted,
      );
      expect(signer.calls, 0);
      final saved = await repository.ledger();
      expect(saved.heardMilliseconds, 1000);
      expect(saved.transportAcceptedMilliseconds, 1000);
      expect(saved.unconfirmedMilliseconds, 0);
    },
  );

  test(
    'missing real identity never invents a device and unknown writes never replay on restore',
    () async {
      var requests = 0;
      final store = _Store();
      final api = QishuiApi(
        MockClient((request) async {
          requests++;
          return _reply({});
        }),
        signer: _Signer(did: ''),
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: store,
      );
      expect(
        await repository.submit(
          [
            QishuiListeningEvent('audio_over', {
              'duration': 1250,
            }, DateTime.now()),
          ],
          heardMilliseconds: 1250,
          playing: false,
        ),
        QishuiListeningDelivery.unconfirmed,
      );
      expect(requests, 0);
      final restored = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: store,
      );
      expect((await restored.ledger()).heardMilliseconds, 1250);
      expect((await restored.ledger()).unconfirmedMilliseconds, 1250);
      expect(requests, 0);
    },
  );

  test(
    'HTTP 200 without explicit receipt keeps local time unconfirmed exactly once',
    () async {
      var requests = 0;
      final api = QishuiApi(
        MockClient((_) async {
          requests++;
          return _reply({});
        }),
        signer: _Signer(),
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: _Store(),
      );
      expect(
        await repository.submit(
          [
            QishuiListeningEvent('audio_over', {
              'duration': 2000,
            }, DateTime.now()),
          ],
          heardMilliseconds: 2000,
          playing: false,
        ),
        QishuiListeningDelivery.unconfirmed,
      );
      expect(requests, 1);
      expect((await repository.ledger()).transportAcceptedMilliseconds, 0);
      expect((await repository.ledger()).unconfirmedMilliseconds, 2000);
    },
  );

  test(
    'monotonic hearing excludes paused/buffering/seeking time and never charges a progress jump',
    () async {
      final bodies = <Map>[];
      final store = _Store();
      final api = QishuiApi(
        MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map);
          return _reply({'message': 'success'});
        }),
        signer: _Signer(),
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: store,
      );
      final clock = _Clock();
      final reporter = QishuiListeningReporter(
        repository: repository,
        clock: clock,
      );
      addTearDown(reporter.dispose);
      void update({
        bool playing = true,
        bool ready = true,
        bool seeking = false,
        int position = 0,
        double speed = 1,
      }) => reporter.update(
        track: _song('111'),
        playing: playing,
        ready: ready,
        seeking: seeking,
        speed: speed,
        position: Duration(milliseconds: position),
      );
      update(playing: false, position: 60000);
      clock.advance(10000);
      update();
      clock.advance(1000);
      update(seeking: true, position: 120000, speed: 2);
      clock.advance(5000);
      update(ready: false, position: 120000);
      clock.advance(5000);
      update(position: 120000, speed: 2);
      clock.advance(1000);
      update(playing: false, position: 122000, speed: 2);
      await reporter.settle();
      expect(reporter.heardMilliseconds, 2000);
      final saved = await repository.ledger();
      expect(saved.heardMilliseconds, 2000);
      expect(saved.transportAcceptedMilliseconds, 2000);
      final events = bodies
          .expand((body) => body['events'] as List)
          .cast<Map>()
          .toList();
      expect(events.where((e) => e['event'] == 'audio_play').length, 1);
      final over = events.singleWhere((e) => e['event'] == 'audio_over');
      expect(jsonDecode(over['params'] as String)['duration'], 2000);
      expect(events.any((e) => e['event'] == 'audio_finish'), false);
    },
  );

  test(
    'pause resume and repeat submit disjoint intervals rather than cumulative duplicates',
    () async {
      final store = _Store();
      final api = QishuiApi(
        MockClient((_) async => _reply({'code': 0})),
        signer: _Signer(),
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: store,
      );
      final clock = _Clock();
      final reporter = QishuiListeningReporter(
        repository: repository,
        clock: clock,
      );
      addTearDown(reporter.dispose);
      void frame(bool playing) => reporter.update(
        track: _song('111'),
        playing: playing,
        ready: true,
        seeking: false,
      );
      frame(true);
      clock.advance(1000);
      frame(false);
      await reporter.settle();
      clock.advance(9000);
      frame(true);
      clock.advance(2000);
      await reporter.finish(reason: 'finished');
      frame(true);
      clock.advance(3000);
      await reporter.finish(reason: 'finished');
      expect((await repository.ledger()).heardMilliseconds, 6000);
      expect((await repository.ledger()).transportAcceptedMilliseconds, 6000);
    },
  );

  test(
    'account teardown persists old-owner remainder locally and never dispatches under the new account',
    () async {
      var requests = 0;
      final store = _Store();
      final api = QishuiApi(
        MockClient((_) async {
          requests++;
          return _reply({'code': 0});
        }),
        signer: _Signer(),
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: store,
      );
      final clock = _Clock();
      final reporter = QishuiListeningReporter(
        repository: repository,
        clock: clock,
      );
      reporter.update(
        track: _song('111'),
        playing: true,
        ready: true,
        seeking: false,
      );
      clock.advance(1750);
      api.configure(_session('9002'));
      reporter.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(store.values['9001']?.heardMilliseconds, 1750);
      expect(store.values['9002'], isNull);
      expect(requests, 0);
    },
  );

  test(
    'contradictory transport receipt cannot mark a duration accepted',
    () async {
      final api = QishuiApi(
        MockClient((_) async => _reply({'code': 0, 'message': 'failed'})),
        signer: _Signer(),
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: _Store(),
      );
      expect(
        await repository.submit(
          [
            QishuiListeningEvent('audio_over', {
              'duration': 500,
            }, DateTime.now()),
          ],
          heardMilliseconds: 500,
          playing: false,
        ),
        QishuiListeningDelivery.unconfirmed,
      );
      expect((await repository.ledger()).transportAcceptedMilliseconds, 0);
      expect((await repository.ledger()).unconfirmedMilliseconds, 500);
    },
  );

  test(
    'account change before queued segment persists locally without sending',
    () async {
      var requests = 0;
      final store = _Store();
      final api = QishuiApi(
        MockClient((_) async {
          requests++;
          return _reply({'code': 0});
        }),
        signer: _Signer(),
      )..configure(_session('9001'));
      addTearDown(api.dispose);
      final repository = QishuiListeningRepository(
        api: api,
        current: () => true,
        store: store,
      );
      final clock = _Clock();
      final reporter = QishuiListeningReporter(
        repository: repository,
        clock: clock,
      );
      reporter.update(
        track: _song('111'),
        playing: true,
        ready: true,
        seeking: false,
      );
      clock.advance(2500);
      reporter.update(
        track: _song('111'),
        playing: false,
        ready: true,
        seeking: false,
      );
      api.configure(_session('9002'));
      reporter.dispose();
      await reporter.settle();
      expect(store.values['9001']?.heardMilliseconds, 2500);
      expect(store.values['9001']?.transportAcceptedMilliseconds, 0);
      expect(requests, 0);
    },
  );
}
