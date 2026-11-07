import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_image_upload.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'qishui_signed_api167_test.dart' show account, FixtureSigner, reply;

Map<String, dynamic> grant173() => {
  'uploader_info': {
    'image_host': 'imagex.bytedanceapi.com',
    'service_id': 'fixture-service',
    'security_token': {
      'access_key_id': 'fixture-ak',
      'secret_access_key': 'fixture-sk',
      'session_token': 'fixture-ephemeral-token',
    },
  },
};
Map<String, dynamic> list173(String image, {String owner = 'owner167'}) => {
  'playlists': [
    {
      'id': '123',
      'title': '我的歌单',
      'type': 2,
      'count_tracks': 0,
      'owner': {'id': owner},
      'url_cover': {
        'uri': image,
        'url_list': ['https://p1.byteimg.com/$image'],
      },
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('CRC32 matches standard check vector', () {
    expect(QishuiImageSignature.crc32(utf8.encode('123456789')), 'cbf43926');
  });
  test('grant refuses IP, HTTP, credentials and unrelated storage domains', () {
    for (final host in [
      'http://imagex.bytedanceapi.com',
      '127.0.0.1',
      'https://a@imagex.bytedanceapi.com',
      'evil.example',
      'imagex.bytedanceapi.com.evil.example',
    ]) {
      final grant = grant173();
      (grant['uploader_info'] as Map)['image_host'] = host;
      expect(
        () => QishuiImageGrant.parse(grant),
        throwsA(isA<QishuiException>()),
      );
    }
  });
  test(
    'ImageX apply/upload/commit sends no music identity and requires matching URI',
    () async {
      var stage = 0;
      final api = QishuiApi(
        MockClient((r) async {
          stage++;
          if (r.url.host == 'api.qishui.com') {
            expect(r.url.path, '/luna/video/uploader');
            expect(r.url.queryParameters['upload_type'], '0');
            expect(r.headers['cookie'], isNotNull);
            return reply(grant173());
          }
          expect(r.headers['cookie'], isNull);
          expect(r.headers['x-helios'], isNull);
          if (r.url.queryParameters['Action'] == 'ApplyImageUpload') {
            expect(r.headers['authorization'], startsWith('AWS4-HMAC-SHA256 '));
            expect(
              r.headers['x-amz-security-token'],
              'fixture-ephemeral-token',
            );
            return reply({
              'Result': {
                'UploadAddress': {
                  'StoreInfos': [
                    {
                      'StoreUri': 'tos-cn-i-test/cover.png',
                      'Auth': 'fixture-store-auth',
                    },
                  ],
                  'UploadHosts': ['upload.byteimg.com'],
                  'SessionKey': 'fixture-session',
                },
              },
            });
          }
          if (r.url.host == 'upload.byteimg.com') {
            expect(r.headers['authorization'], 'fixture-store-auth');
            expect(r.headers['x-amz-security-token'], isNull);
            expect(r.bodyBytes, [1, 2, 3]);
            return reply({'code': 2000});
          }
          expect(r.url.queryParameters['Action'], 'CommitImageUpload');
          expect(jsonDecode(r.body)['SessionKey'], 'fixture-session');
          return reply({
            'Result': {
              'Results': [
                {'Uri': 'tos-cn-i-test/cover.png'},
              ],
            },
          });
        }),
        signer: FixtureSigner(),
      )..configure(account());
      addTearDown(api.dispose);
      final result = await QishuiImageUploader(api).upload(
        Uint8List.fromList([1, 2, 3]),
        abort: Completer<void>().future,
        current: () => true,
      );
      expect(result, 'tos-cn-i-test/cover.png');
      expect(stage, 4);
    },
  );
  test(
    'unknown playlist cover update is journaled and never uploaded again',
    () async {
      var uploads = 0, writes = 0;
      final api = QishuiApi(
        MockClient((r) async {
          if (r.url.path.endsWith('/playlist/update')) {
            writes++;
            return http.Response('', 503);
          }
          return reply(list173('old/image.png'));
        }),
        signer: FixtureSigner(),
      )..configure(account());
      addTearDown(api.dispose);
      final repo = QishuiRepository(api);
      final bytes = Uint8List.fromList([11, 22, 33]);
      Future<String> upload(
        Uint8List _,
        Future<void> abort,
        bool Function() current,
      ) async {
        uploads++;
        return 'tos-cn-i-fixture/new.png';
      }

      for (var i = 0; i < 2; i++) {
        await expectLater(
          repo.changePlaylistCover('123', bytes, upload: upload),
          throwsA(
            isA<QishuiException>().having(
              (e) => e.unknownWrite,
              'unknown',
              true,
            ),
          ),
        );
      }
      expect(uploads, 1);
      expect(writes, 1);
    },
  );
  test(
    'official readback confirms cover identity and unauthorized owner never uploads',
    () async {
      var image = 'old/image.png';
      var uploads = 0;
      var owner = 'owner167';
      final api = QishuiApi(
        MockClient((r) async {
          if (r.url.path.endsWith('/playlist/update')) {
            image = jsonDecode(r.body)['cover_uri'] as String;
            return reply({'status_code': 0});
          }
          return reply(list173(image, owner: owner));
        }),
        signer: FixtureSigner(),
      )..configure(account());
      addTearDown(api.dispose);
      final repo = QishuiRepository(api);
      Future<String> upload(
        Uint8List _,
        Future<void> abort,
        bool Function() current,
      ) async {
        uploads++;
        return 'tos-cn-i-fixture/confirmed.png';
      }

      final result = await repo.changePlaylistCover(
        '123',
        Uint8List.fromList([55]),
        upload: upload,
      );
      expect(result.coverUri, 'tos-cn-i-fixture/confirmed.png');
      owner = 'other-account';
      await expectLater(
        repo.changePlaylistCover(
          '123',
          Uint8List.fromList([66]),
          upload: upload,
        ),
        throwsA(isA<QishuiException>()),
      );
      expect(uploads, 1);
    },
  );
}
