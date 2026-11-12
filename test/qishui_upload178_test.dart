import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_image_upload.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';

import 'qishui_cover173_test.dart' show list173;
import 'qishui_signed_api167_test.dart' show account, FixtureSigner, reply;

Map<String, dynamic> _grant() => {
  'uploader_info': {
    'image_host': 'imagex.bytedanceapi.com',
    'service_id': 'fixture-service-178',
    'security_token': {
      'access_key_id': 'AKTEST178',
      'secret_access_key': 'synthetic-secret-key-178',
      'session_token': 'fixture-session-178',
    },
  },
};

const _key = 'tos-cn-i-fixture/image-178.png';
final _time = DateTime.utc(2026, 11, 8, 4, 2, 7);

Map<String, Object> _apply() => {
  'Result': {
    'UploadAddress': {
      'StoreInfos': [
        {'StoreUri': _key, 'Auth': 'private-store-auth-178'},
      ],
      'UploadHosts': ['upload.byteimg.com'],
      'SessionKey': 'fixture-session-key-178',
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(QishuiDiagnostics.shared.clear);
  tearDown(QishuiDiagnostics.shared.clear);

  test(
    'private ImageX path matches independently reproduced official signing vectors',
    () {
      final grant = QishuiImageGrant.parse(_grant());
      expect(grant.endpoint.path, '/top/v1');
      final apply = grant.endpoint.replace(
        queryParameters: {
          'Action': 'ApplyImageUpload',
          'Version': '2018-08-01',
          'ServiceId': grant.serviceId,
          'FileType': 'image',
          'UploadNum': '1',
        },
      );
      final commit = grant.endpoint.replace(
        queryParameters: {
          'Action': 'CommitImageUpload',
          'Version': '2018-08-01',
          'ServiceId': grant.serviceId,
        },
      );
      const prefix =
          'AWS4-HMAC-SHA256 Credential=AKTEST178/'
          '20261108/sdwdmwlll/imagex/aws4_request,'
          'SignedHeaders=x-amz-date;x-amz-security-token,Signature=';
      // These constants come from a separate Python implementation against the
      // retained official BDAuthHelper/AWSV4Auth/native path contract, extended
      // in 179 with the native region default. They are intentionally not
      // calculated with the Dart implementation under test.
      expect(
        QishuiImageSignature.headers(
          method: 'GET',
          uri: apply,
          body: '',
          grant: grant,
          now: _time,
        )['authorization'],
        '${prefix}df9ad51a6e3e04cf9fe2f80da615e795abf8e0aeaa6ff91c899f45c639e3c9cf',
      );
      expect(
        QishuiImageSignature.headers(
          method: 'POST',
          uri: commit,
          body:
              '{"SessionKey":"fixture-session-key-178","SuccessActionStatus":"200"}',
          grant: grant,
          now: _time,
        )['authorization'],
        '${prefix}ac5d10f6313a2fa3d63d571129b2b7478a39955d54847011a2b66936cd0eb97a',
      );
      expect(
        () => QishuiImageSignature.headers(
          method: 'GET',
          uri: apply.replace(path: '/'),
          body: '',
          grant: grant,
          now: _time,
        ),
        throwsA(isA<QishuiException>()),
      );
    },
  );

  test('only the exact official gateway path is accepted in a grant', () {
    final accepted = _grant();
    (accepted['uploader_info'] as Map)['image_host'] =
        'https://imagex.bytedanceapi.com/top/v1';
    expect(QishuiImageGrant.parse(accepted).endpoint.path, '/top/v1');
    for (final path in ['/other', '/top/v1/extra', '/top/v1?Action=Injected']) {
      final invalid = _grant();
      (invalid['uploader_info'] as Map)['image_host'] =
          'https://imagex.bytedanceapi.com$path';
      expect(
        () => QishuiImageGrant.parse(invalid),
        throwsA(isA<QishuiException>()),
      );
    }
  });

  test(
    'Apply and Commit use the signed gateway while storage keeps its distinct path',
    () async {
      var cover = 'old/image.png';
      final stages = <String>[];
      final bytes = Uint8List.fromList([1, 2, 3]);
      final api = QishuiApi(
        MockClient((r) async {
          if (r.url.host == 'api.qishui.com') {
            if (r.url.path == '/luna/video/uploader') return reply(_grant());
            if (r.url.path.endsWith('/playlist/update')) {
              stages.add('playlist');
              cover = (jsonDecode(r.body) as Map)['cover_uri'] as String;
              return reply({'status_code': 0});
            }
            return reply(list173(cover));
          }
          expect(r.headers['cookie'], isNull);
          expect(r.headers['x-helios'], isNull);
          if (r.url.queryParameters['Action'] == 'ApplyImageUpload') {
            stages.add('apply');
            // A root-path request reproduces the rejected old contract in this
            // controlled server. Success here is a protocol regression result,
            // not evidence of an upload to the real official account service.
            if (r.url.path != '/top/v1') return http.Response('{}', 400);
            expect(
              r.headers['authorization'],
              contains('/sdwdmwlll/imagex/aws4_request,SignedHeaders='),
            );
            expect(r.headers['authorization'], isNot(contains(', ')));
            return reply(_apply());
          }
          if (r.url.host == 'upload.byteimg.com') {
            stages.add('storage');
            expect(r.url.path, '/upload/v1/$_key');
            expect(r.bodyBytes, bytes);
            expect(r.headers['authorization'], 'private-store-auth-178');
            return reply({'code': 2000});
          }
          stages.add('commit');
          expect(r.url.path, '/top/v1');
          expect(r.url.queryParameters['Action'], 'CommitImageUpload');
          expect(
            r.headers['authorization'],
            contains('/sdwdmwlll/imagex/aws4_request,SignedHeaders='),
          );
          expect(r.headers['authorization'], isNot(contains(', ')));
          return reply({
            'Result': {
              'Results': [
                {'Uri': _key},
              ],
            },
          });
        }),
        signer: FixtureSigner(),
      )..configure(account());
      addTearDown(api.dispose);
      final updated = await QishuiRepository(
        api,
      ).changePlaylistCover('123', bytes);
      expect(updated.coverUri, _key);
      expect(stages, ['apply', 'storage', 'commit', 'playlist']);
      expect(QishuiDiagnostics.shared.events.last['stage'], 'readback');
      expect(QishuiDiagnostics.shared.events.last['receiptAccepted'], true);
    },
  );

  for (final failure in ['apply', 'storage', 'commit']) {
    test(
      'HTTP 400 at $failure retains only a safe stage and does not update the playlist',
      () async {
        var writes = 0;
        final api = QishuiApi(
          MockClient((r) async {
            if (r.url.host == 'api.qishui.com') {
              if (r.url.path == '/luna/video/uploader') return reply(_grant());
              if (r.url.path.endsWith('/playlist/update')) writes++;
              return reply(list173('old/image.png'));
            }
            final stage = r.url.queryParameters['Action'] == 'ApplyImageUpload'
                ? 'apply'
                : r.url.host == 'upload.byteimg.com'
                ? 'storage'
                : 'commit';
            if (stage == failure) {
              return http.Response(
                jsonEncode({
                  'ResponseMetadata': {
                    'Error': {
                      'Code': failure == 'storage'
                          ? 'private-server-credential-178'
                          : 'SignatureDoesNotMatch',
                      'Message': 'private-server-message-178',
                    },
                  },
                }),
                400,
              );
            }
            if (stage == 'apply') return reply(_apply());
            if (stage == 'storage') return reply({'code': 2000});
            return reply({
              'Result': {
                'Results': [
                  {'Uri': _key},
                ],
              },
            });
          }),
          signer: FixtureSigner(),
        )..configure(account());
        addTearDown(api.dispose);
        await expectLater(
          QishuiRepository(
            api,
          ).changePlaylistCover('123', Uint8List.fromList([1, 2, 3])),
          throwsA(
            isA<QishuiException>().having(
              (e) => e.unknownWrite,
              'no playlist write',
              false,
            ),
          ),
        );
        expect(writes, 0);
        final event = QishuiDiagnostics.shared.events.last;
        expect(event['stage'], failure);
        expect(event['httpStatus'], 400);
        expect(
          event['serviceCode'],
          failure == 'storage' ? 'unknown' : 'SignatureDoesNotMatch',
        );
        final exported = QishuiDiagnostics.shared.export();
        for (final private in [
          'AKTEST178',
          'synthetic-secret-key-178',
          'fixture-session-',
          'private-store-auth-178',
          'private-server-',
          _key,
        ]) {
          expect(exported, isNot(contains(private)));
        }
      },
    );
  }
}
