import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_full_repository.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_content.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_recognition.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_upload_workflows.dart';

const session = NeteaseSession(
  userId: '7',
  cookies: {'MUSIC_U': 'synthetic-contract-only'},
  deviceId: 'fixture-device',
);
NeteaseEndpoint endpoint(
  String route, {
  bool write = false,
  String? unavailable,
}) => NeteaseEndpoint(
  route: route,
  title: '测试内容',
  tab: '功能',
  category: '听歌工具',
  description: '',
  parameters: [],
  write: write,
  unavailable: unavailable,
);
void main() {
  test('NOS receives only its upload token and verified image bytes', () async {
    final requests = <http.Request>[];
    final api = NeteaseApi(
      MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'music.163.com') {
          return http.Response(
            jsonEncode({
              'code': 200,
              'result': {
                'objectKey': 'fixture/image.jpg',
                'token': 'nos-fixture',
                'docId': 99,
              },
            }),
            200,
          );
        }
        expect(request.url.host, 'nosup-hz1.127.net');
        expect(request.headers['cookie'], isNull);
        expect(request.headers['x-nos-token'], 'nos-fixture');
        expect(request.bodyBytes, [0xff, 0xd8, 0xff, 0xd9]);
        return http.Response('{"code":200}', 200);
      }),
    )..configure(session);
    expect(
      await NeteaseUploadWorkflows(
        api,
        session.credentialId,
      ).picture(Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9])),
      99,
    );
    expect(requests.length, 2);
  });
  test('curves retain their real category ID for detail navigation', () {
    final content = NeteaseContent.parse({
      'code': 200,
      'data': [
        {
          'tagId': 1000,
          'tagName': '流行',
          'childrenTags': [
            {'tagId': 1001, 'tagName': '独立流行'},
          ],
        },
      ],
    }, '/style/list');
    expect(content.rows.single.id, '1000');
    expect(content.rows.single.title, '流行');
    expect(content.rows.single.kind, 'style');
    final children = NeteaseContent.parse(
      content.rows.single.raw,
      '/style/detail',
    );
    expect(children.rows.single.id, '1001');
  });
  test(
    'mutating response cannot leak credentials into content rendering',
    () async {
      final api = NeteaseApi(
        MockClient((request) async {
          expect(request.url.host, 'interface.music.163.com');
          expect(request.url.path, '/eapi/msg/private/send');
          return http.Response(
            jsonEncode({
              'code': 200,
              'cookie': 'hidden',
              'data': {'token': 'hidden', 'message': '已发送'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..configure(session);
      final result = await NeteaseFullRepository(NeteaseMusicRepository(api))
          .run(endpoint('/send/text', write: true), {
            'user_ids': '8',
            'msg': 'synthetic fixture',
          });
      expect(result, {
        'code': 200,
        'data': {'message': '已发送'},
      });
    },
  );
  test('changed account rejects the result of an in-flight request', () async {
    final pending = Completer<http.Response>();
    final api = NeteaseApi(MockClient((_) => pending.future))
      ..configure(session);
    final result = NeteaseFullRepository(
      NeteaseMusicRepository(api),
    ).run(endpoint('/user/level'), {});
    final assertion = expectLater(result, throwsA(anything));
    await Future<void>.delayed(Duration.zero);
    api.configure(null);
    pending.complete(http.Response('{"code":200,"data":{"level":10}}', 200));
    await assertion;
  });
  test(
    'documented retired feature makes no request and keeps its reason',
    () async {
      var requests = 0;
      final api = NeteaseApi(
        MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      )..configure(session);
      await expectLater(
        NeteaseFullRepository(
          NeteaseMusicRepository(api),
        ).run(endpoint('/comment/hotwall/list', unavailable: '官方已下架'), {}),
        throwsA(anything),
      );
      expect(requests, 0);
    },
  );
  test('batches reject unknown paths before network dispatch', () async {
    var requests = 0;
    final api = NeteaseApi(
      MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    )..configure(session);
    await expectLater(
      NeteaseFullRepository(NeteaseMusicRepository(api)).run(
        endpoint('/batch'),
        {
          'requests': [
            {'route': '/admin/delete', 'query': <String, Object?>{}},
          ],
        },
      ),
      throwsA(anything),
    );
    expect(requests, 0);
  });
  test('music records render playable provider-qualified tracks and facts', () {
    final result = NeteaseContent.parse({
      'code': 200,
      'data': {
        'list': [
          {
            'data': {
              'id': 7,
              'name': '合约歌曲',
              'ar': [
                {'name': '歌手'},
              ],
              'al': {'name': '专辑'},
              'dt': 123000,
            },
          },
        ],
      },
      'cookie': 'hidden',
    }, '/record/recent/song');
    expect(result.rows.single.track!.id, 'netease_7');
    expect(result.rows.single.track!.duration, const Duration(seconds: 123));
    expect(result.facts.values, isNot(contains('hidden')));
  });
  test('WAV parser walks metadata chunks and rejects another sample rate', () {
    final wav = Uint8List(44 + 16000);
    final view = ByteData.sublistView(wav);
    wav.setRange(0, 4, ascii.encode('RIFF'));
    wav.setRange(8, 12, ascii.encode('WAVE'));
    wav.setRange(12, 16, ascii.encode('fmt '));
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, 8000, Endian.little);
    view.setUint16(34, 16, Endian.little);
    wav.setRange(36, 40, ascii.encode('data'));
    view.setUint32(40, 16000, Endian.little);
    view.setInt16(44, 16384, Endian.little);
    expect(neteaseFingerprintPcm(wav).first, .5);
    expect(neteaseFingerprintPcm(wav).length, 8000);
    view.setUint32(24, 44100, Endian.little);
    expect(() => neteaseFingerprintPcm(wav), throwsFormatException);
  });
}
