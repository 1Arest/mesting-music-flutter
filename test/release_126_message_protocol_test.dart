import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/netease_music_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';

// Verify the encoded wire request. These are synthetic public-protocol fixtures,
// and never contain or obtain a user's real messages or login credentials.
Map<String, dynamic> _body(http.Request request) {
  final hex = request.bodyFields['params']!;
  final bytes = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
  final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
    ..init(
      false,
      PaddedBlockCipherParameters(
        KeyParameter(Uint8List.fromList(utf8.encode('e82ckenh8dichen8'))),
        null,
      ),
    );
  return Map<String, dynamic>.from(
    jsonDecode(utf8.decode(cipher.process(bytes)).split('-36cd479b6b5-')[1])
        as Map,
  );
}

const _session = NeteaseSession(
  userId: '7',
  deviceId: 'fixture-device',
  cookies: {
    'MUSIC_U': 'fixture-cookie',
    '__csrf': 'fixture-csrf',
    'os': 'pc',
    'appver': '3.1.3.203419',
  },
);
Map<String, dynamic> _record({bool modern = true}) => {
  'id': 3,
  'time': 1000,
  'fromUser': {'userId': 8},
  'toUser': {'userId': 7},
  'msg': jsonEncode({'msg': '不支持展示该内容，请前往移动端查看'}),
  if (modern)
    'msgBody': jsonEncode({
      'msgType': 47,
      'body': jsonEncode({
        'mainTitle': {'title': '本次一起听已结束'},
        'subTitle': {'title': '一起听了 12 分钟'},
        'durationSeconds': 720,
        'nativeUrl':
            'orpheus://nm/redirect?url2=${Uri.encodeComponent('https://st.music.163.com/listen-together/record/?id=synthetic')}',
      }),
    }),
  if (!modern)
    'generalMsg': {
      'mainTitle': {'title': '一起听记录'},
      'webUrl': 'https://st.music.163.com/listen-together/report/?id=synthetic',
    },
};

void main() {
  test(
    'private history uses isolated Android eapi identity and renders the mobile record',
    () async {
      var requests = 0;
      final api = NeteaseApi(
        MockClient((request) async {
          requests++;
          expect(request.url.host, 'interface.music.163.com');
          expect(request.url.path, '/eapi/msg/private/history');
          final data = _body(request);
          expect(data['userId'], '8');
          expect(data['header']['os'], 'android');
          expect(data['header']['appver'], '9.5.61');
          expect(data['header']['versioncode'], '9005061');
          expect(data['header']['osver'], '12');
          expect(
            request.headers['user-agent'],
            contains('9.5.61.260802021928(9005061)'),
          );
          expect(request.headers['cookie'], contains('os=android'));
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': {
                'msgs': [_record()],
              },
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'os=android; Path=/, appver=9.5.61; Path=/',
            },
          );
        }),
      )..configure(_session);
      final repository = NeteaseMessagesRepository(NeteaseMusicRepository(api));
      addTearDown(repository.dispose);
      final rows = await repository.history('8');
      expect(requests, 1);
      expect(rows.length, 1);
      expect(rows.single.card?.togetherRecord, isTrue);
      expect(rows.single.card?.duration, const Duration(minutes: 12));
      expect(rows.single.text, isNot(contains('不支持')));
      expect(rows.single.card?.detailUrl?.queryParameters['id'], 'synthetic');
      expect(api.cookies['os'], 'pc');
      expect(api.cookies['appver'], '3.1.3.203419');
    },
  );
  test(
    'conversation previews retain mobile card fields at the outer message boundary',
    () async {
      final api = NeteaseApi(
        MockClient((request) async {
          expect(request.url.path, '/eapi/msg/private/users');
          expect(_body(request)['header']['os'], 'android');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 200,
                'msgs': [
                  {
                    ..._record(modern: false),
                    'lastMsg': _record()['msg'],
                    'newMsgCount': 0,
                  },
                ],
              }),
            ),
            200,
          );
        }),
      )..configure(_session);
      final repository = NeteaseMessagesRepository(NeteaseMusicRepository(api));
      addTearDown(repository.dispose);
      final rows = await repository.conversations();
      expect(rows.single.last.card?.title, '一起听记录');
      expect(rows.single.last.text, startsWith('[一起听记录]'));
    },
  );
  test(
    'mobile identity cannot be applied to sends or other endpoints',
    () async {
      final api = NeteaseApi(
        MockClient((_) async => throw StateError('must not send')),
      )..configure(_session);
      await expectLater(
        api.request('/api/msg/private/send', {}, mobileMessages: true),
        throwsArgumentError,
      );
      await expectLater(
        api.request(
          '/api/msg/private/history',
          {},
          mobileMessages: true,
          weapi: true,
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'compatibility text alone is not fabricated into a successful together report',
    () {
      final row = NeteaseChatMessage.parse({
        'msg': jsonEncode({'msg': '不支持展示该内容，请前往移动端查看'}),
      });
      expect(row.card, isNull);
    },
  );
}
