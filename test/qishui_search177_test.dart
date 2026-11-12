import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_search_catalog.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_session.dart';

import 'qishui_search173_test.dart'
    show searchId173, searchResponse173, searchTrack173;
import 'qishui_signed_api167_test.dart' show FixtureSigner, reply;

const _identity177 = {
  'device_id': '12345678901234',
  'iid': '12345678901235',
  'fp': 'fixture-pc-search-177',
  'user_agent': 'LunaPC/3.7.0(452316191)',
};

QishuiSession _account177(String suffix) => QishuiSession(
  userId: 'search-owner-$suffix',
  protocol: QishuiSessionProtocol.web,
  cookies: [
    {
      'name': 'sessionid',
      'value': 'fixture-session-$suffix',
      'domain': 'api.qishui.com',
      'path': '/',
      'secure': 'true',
      'hostOnly': 'true',
    },
    {
      'name': 'passport_csrf_token',
      'value': 'fixture-csrf-$suffix',
      'domain': 'api.qishui.com',
      'path': '/',
      'secure': 'true',
      'hostOnly': 'true',
    },
  ],
  tokens: {'x-tt-token': 'fixture-token-$suffix'},
);

/// Pausing at the signing boundary makes cancellation/account changes
/// deterministic without dispatching a real request or waiting on a timer.
class _PausedSigner177 extends FixtureSigner {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<QishuiSignedRequest> sign(
    Uri uri,
    String method,
    String body,
    Map<String, String> headers,
    Future<void> abort,
  ) async {
    entered.complete();
    await release.future;
    return super.sign(uri, method, body, headers, abort);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'song search signs and dispatches identical official JSON POST bytes',
    () async {
      String? signedBody;
      String? signedUrl;
      var officialReads = 0;
      final helperCalls = <String>[];
      final client = MockClient((request) async {
        if (request.url.host == 'helper177.example.test') {
          helperCalls.add(request.url.path);
          expect(request.headers['cookie'], isNull);
          expect(request.headers['x-tt-token'], isNull);
          expect(request.headers['x-tt-passport-csrf-token'], isNull);
          if (request.url.path == '/config') {
            return reply({'ok': true, 'identity': _identity177});
          }
          expect(request.url.path, '/sign');
          final envelope = jsonDecode(request.body) as Map;
          signedBody = envelope['body'] as String;
          signedUrl = envelope['url'] as String;
          expect(envelope['method'], 'POST');
          expect(jsonDecode(signedBody!), {
            'q': '天外来物 & moon',
            'cursor': '0',
            'search_id': searchId173,
            'search_method': 'input',
          });
          // Even an enabled media-cookie opt-in cannot widen to search.
          expect(request.body, isNot(contains('fixture-session-first')));
          expect(request.body, isNot(contains('fixture-csrf-first')));
          expect(request.body, isNot(contains('fixture-token-first')));
          expect((envelope['headers'] as Map).keys, isNot(contains('cookie')));
          return reply({
            'ok': true,
            'device_id': _identity177['device_id'],
            'headers': {
              'X-Helios': 'fixture-search-helios',
              'X-Medusa': 'fixture-search-medusa',
            },
          });
        }
        officialReads++;
        expect(request.method, 'POST');
        expect(request.url.host, 'api.qishui.com');
        expect(request.url.path, '/luna/search/track');
        expect(request.url.toString(), signedUrl);
        expect(request.url.queryParameters['aid'], '386088');
        expect(request.url.queryParameters['device_platform'], 'windows');
        expect(
          request.url.queryParameters['device_id'],
          _identity177['device_id'],
        );
        expect(request.url.queryParameters.containsKey('q'), isFalse);
        expect(request.url.queryParameters.containsKey('cursor'), isFalse);
        expect(request.bodyBytes, utf8.encode(signedBody!));
        expect(
          request.headers['x-ss-stub'],
          md5.convert(request.bodyBytes).toString().toUpperCase(),
        );
        expect(request.headers['x-helios'], 'fixture-search-helios');
        expect(request.headers['x-medusa'], 'fixture-search-medusa');
        expect(
          request.headers['cookie'],
          contains('sessionid=fixture-session-first'),
        );
        expect(request.headers['x-tt-token'], 'fixture-token-first');
        expect(
          request.headers['x-tt-passport-csrf-token'],
          'fixture-csrf-first',
        );
        return reply(
          searchResponse173(
            rows: [
              {
                'entity': {'track': searchTrack173('17701', '天外来物')},
              },
            ],
          ),
        );
      });
      final api = QishuiApi(
        client,
        signer: SodaMRequestSigner(
          client,
          endpoint: Uri.parse('https://helper177.example.test/sign'),
          accessToken: 'fixture-helper177-access-token',
          custom: true,
          accountBoundSigning: true,
        ),
      )..configure(_account177('first'));
      addTearDown(api.dispose);
      final catalog = QishuiSearchCatalog(
        request:
            (
              path, {
              body = const {},
              query = const {},
              get = false,
              abortTrigger,
            }) => api.request(
              path,
              body: body,
              query: query,
              get: get,
              abortTrigger: abortTrigger,
            ),
      );
      final page = await catalog.searchTracks(
        ' 天外来物 & moon ',
        searchId: searchId173,
      );
      expect(page.items.single.platformSongId, '17701');
      expect(page.items.single.title, '天外来物');
      expect(helperCalls, ['/config', '/sign']);
      expect(officialReads, 1);
    },
  );

  test('artist search retains its working unsigned PC GET path', () async {
    var reads = 0;
    final api = QishuiApi(
      MockClient((request) async {
        reads++;
        expect(request.method, 'GET');
        expect(request.url.path, '/luna/pc/search/artist');
        expect(request.url.queryParameters['q'], '测试歌手');
        expect(request.body, isEmpty);
        expect(request.headers['x-helios'], isNull);
        return reply(
          searchResponse173(
            kind: 'artists',
            rows: [
              {
                'entity': {
                  'artist': {'id': '17702', 'name': '测试歌手'},
                },
              },
            ],
          ),
        );
      }),
    )..configure(_account177('artist'));
    addTearDown(api.dispose);
    final catalog = QishuiSearchCatalog(
      request:
          (
            path, {
            body = const {},
            query = const {},
            get = false,
            abortTrigger,
          }) => api.request(
            path,
            body: body,
            query: query,
            get: get,
            abortTrigger: abortTrigger,
          ),
    );
    final page = await catalog.searchArtists('测试歌手', searchId: searchId173);
    expect(page.items.single.id, '17702');
    expect(reads, 1);
  });

  for (final change in ['cancel', 'account']) {
    test('$change while signing prevents official search dispatch', () async {
      final signer = _PausedSigner177();
      var dispatches = 0;
      final api = QishuiApi(
        MockClient((request) async {
          dispatches++;
          return reply(searchResponse173());
        }),
        signer: signer,
      )..configure(_account177('before'));
      addTearDown(api.dispose);
      final abort = Completer<void>();
      final pending = QishuiRepository(
        api,
      ).search('测试', abortTrigger: abort.future);
      final rejected = expectLater(
        pending,
        throwsA(
          isA<QishuiException>().having(
            (error) => error.unknownWrite,
            'read is not unknown write',
            false,
          ),
        ),
      );
      await signer.entered.future;
      if (change == 'account') {
        api.configure(_account177('after'));
      } else {
        abort.complete();
        // Deliver the cancellation edge before releasing the signer fixture.
        await Future<void>.delayed(Duration.zero);
      }
      signer.release.complete();
      await rejected;
      expect(dispatches, 0);
    });
  }

  test(
    'a detached old repository cannot search through a new account',
    () async {
      var dispatches = 0;
      final api = QishuiApi(
        MockClient((request) async {
          dispatches++;
          return reply(searchResponse173());
        }),
        signer: FixtureSigner(),
      )..configure(_account177('before'));
      addTearDown(api.dispose);
      final old = QishuiRepository(api);
      api.configure(_account177('after'));
      await expectLater(old.search('测试'), throwsA(isA<QishuiException>()));
      expect(dispatches, 0);
    },
  );

  for (final response in [
    http.Response('', 200),
    http.Response('{invalid-json', 200),
    http.Response('', 503),
  ]) {
    test(
      'search refusal ${response.statusCode}/${response.body.length} is a read failure without automatic retry',
      () async {
        var dispatches = 0;
        final api = QishuiApi(
          MockClient((request) async {
            dispatches++;
            return response;
          }),
          signer: FixtureSigner(),
        )..configure(_account177('empty'));
        addTearDown(api.dispose);
        await expectLater(
          QishuiRepository(api).search('测试'),
          throwsA(
            isA<QishuiException>().having(
              (error) => error.unknownWrite,
              'read is not unknown write',
              false,
            ),
          ),
        );
        expect(dispatches, 1);
      },
    );
  }

  test('a valid empty song group remains an empty result', () async {
    final api = QishuiApi(
      MockClient((request) async => reply(searchResponse173())),
      signer: FixtureSigner(),
    )..configure(_account177('zero'));
    addTearDown(api.dispose);
    expect(await QishuiRepository(api).search('没有匹配的歌曲'), isEmpty);
  });
}
