import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_image_upload.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_request_signer.dart';

import 'qishui_cover173_test.dart' show grant173, list173;
import 'qishui_signed_api167_test.dart' show account, reply;
import 'qishui_signer168_test.dart'
    show config168, identity168, signature168, token168;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cover grant signs fixed request before isolated ImageX and official readback',
    () async {
      var image = 'old/cover.png';
      var helperSigns = 0, officialWrites = 0, storageWrites = 0;
      final bytes = Uint8List.fromList([3, 7, 11, 19]);
      final client = MockClient((request) async {
        if (request.url.host == 'nas.example.test') {
          expect(request.headers['authorization'], 'Bearer $token168');
          if (request.url.path == '/config') return config168();
          final envelope = jsonDecode(request.body) as Map;
          final url = Uri.parse(envelope['url'] as String);
          expect(url.host, 'api.qishui.com');
          expect(url.queryParameters['device_id'], identity168['device_id']);
          expect(request.body, isNot(contains('music-secret167')));
          expect(request.body, isNot(contains('fixture-ephemeral-token')));
          helperSigns++;
          if (url.path == '/luna/video/uploader') {
            expect(envelope['method'], 'GET');
            expect(envelope['body'], '');
            expect(url.queryParameters['track_id'], '');
            expect(url.queryParameters['upload_type'], '0');
            expect(url.queryParameters['scene'], '0');
          } else {
            expect(url.path, '/luna/pc/me/playlist/update');
            expect(jsonDecode(envelope['body'] as String), {
              'playlist_id': '123',
              'cover_uri': 'tos-cn-i-fixture/cover.png',
            });
          }
          return signature168();
        }
        if (request.url.host == 'api.qishui.com') {
          expect(request.headers['cookie'], 'sessionid=music-secret167');
          expect(request.headers['authorization'], isNull);
          if (request.url.path == '/luna/video/uploader') {
            expect(request.headers['x-helios'], 'fixture-helios-168');
            return reply(grant173());
          }
          if (request.url.path.endsWith('/playlist/update')) {
            officialWrites++;
            image = (jsonDecode(request.body) as Map)['cover_uri'] as String;
            return reply({'status_code': 0});
          }
          return reply(list173(image));
        }
        expect(request.headers['cookie'], isNull);
        expect(request.headers['x-helios'], isNull);
        expect(request.headers['x-tt-token'], isNull);
        expect(jsonEncode(request.headers), isNot(contains(token168)));
        if (request.url.queryParameters['Action'] == 'ApplyImageUpload') {
          return reply({
            'Result': {
              'UploadAddress': {
                'StoreInfos': [
                  {
                    'StoreUri': 'tos-cn-i-fixture/cover.png',
                    'Auth': 'fixture-store-auth',
                  },
                ],
                'UploadHosts': ['upload.byteimg.com'],
                'SessionKey': 'fixture-session',
              },
            },
          });
        }
        if (request.url.host == 'upload.byteimg.com') {
          storageWrites++;
          expect(request.bodyBytes, bytes);
          expect(request.headers['authorization'], 'fixture-store-auth');
          return reply({'code': 2000});
        }
        expect(request.url.queryParameters['Action'], 'CommitImageUpload');
        return reply({
          'Result': {
            'Results': [
              {'Uri': 'tos-cn-i-fixture/cover.png'},
            ],
          },
        });
      });
      final api = QishuiApi(
        client,
        signer: SodaMRequestSigner(
          client,
          endpoint: Uri.parse('https://nas.example.test/sign'),
          accessToken: token168,
          custom: true,
        ),
      )..configure(account());
      addTearDown(api.dispose);
      final updated = await QishuiRepository(
        api,
      ).changePlaylistCover('123', bytes);
      expect(updated.coverUri, 'tos-cn-i-fixture/cover.png');
      expect(helperSigns, 2);
      expect(officialWrites, 1);
      expect(storageWrites, 1);
    },
  );

  for (final policy in [
    'forbidden_route',
    'forbidden_query',
    'untrusted fixture secret',
  ]) {
    test(
      'helper refusal $policy stops before file upload and exposes only known policy code',
      () async {
        var official = 0;
        final client = MockClient((request) async {
          if (request.url.path == '/config') return config168();
          if (request.url.host == 'nas.example.test') {
            return http.Response(
              jsonEncode({
                'ok': false,
                'code': policy,
                'message': 'do not reveal fixture secret',
              }),
              400,
            );
          }
          official++;
          throw StateError('No official request may follow helper refusal');
        });
        final api = QishuiApi(
          client,
          signer: SodaMRequestSigner(
            client,
            endpoint: Uri.parse('https://nas.example.test/sign'),
            accessToken: token168,
            custom: true,
          ),
        )..configure(account());
        addTearDown(api.dispose);
        await expectLater(
          QishuiImageUploader(api).upload(
            Uint8List.fromList([1]),
            abort: Completer<void>().future,
            current: () => true,
          ),
          throwsA(
            isA<QishuiException>()
                .having((e) => e.message, 'stage', contains('图片上传授权未取得'))
                .having(
                  (e) => e.message,
                  'no raw message',
                  isNot(contains('fixture secret')),
                )
                .having((e) => e.unknownWrite, 'no playlist submitted', false),
          ),
        );
        expect(official, 0);
      },
    );
  }
}
