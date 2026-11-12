import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_card.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_diagnostics.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';

// Synthetic bodies follow the shipped MsgBody -> LTRecordMsg mapping. Opaque
// outer names model the two privacy-redacted shapes; neither fixture is a
// reconstructed user's raw DTO. Do not parse diagnostic otherN aliases as keys.
Map<String, Object?> type51Fixture({
  String time = '26小时5分钟',
  Object type = 51,
  bool stringBody = false,
  String? url,
}) {
  final body = <String, Object?>{
    'recordOrpheus':
        url ??
        'https://mp.music.163.com/5fbcd6a217aef81f3a03eda5/ending/index.html?roomId=synthetic_room&roomType=FRIEND&scene=MOBILE_FRIEND',
    'startColor': '#FF6359',
    'timeTitle': time,
    'endColor': '#FF4646',
    'isFriend': true,
    'serverFlag': false,
    'creatorAvatarUrl': 'https://p1.music.126.net/synthetic-creator.png',
    'title': '我们一起听了',
    'acceptorAvatarUrl': 'https://p2.music.126.net/synthetic-acceptor.png',
    'titleColor': '#FFFFFF',
  };
  return {
    'opaqueBrief': 'x' * (time.length == 3 ? 9 : 13),
    'opaqueMessageId': 'x' * 21,
    'opaqueRecordContainer': stringBody ? jsonEncode(body) : body,
    'opaqueExtra': {'opaqueDigest': 'x' * 32},
    'opaqueSource': {'a': 'x' * 15, 'b': 'x' * 23, 'c': 'x' * 3, 'd': 1},
    'opaqueFlag': true,
    'type': type,
  };
}

Map<String, dynamic> _row(Map<String, Object?> payload) => {
  'id': 901,
  'time': 1700000000000,
  'fromUser': {'userId': 8},
  'toUser': {'userId': 7},
  'msg': jsonEncode(payload),
};

void main() {
  for (final time in ['26小时5分钟', '3分钟']) {
    for (final stringBody in [false, true]) {
      test(
        'type51 ended record parses opaque body, time=$time encoded=$stringBody',
        () {
          final payload = type51Fixture(time: time, stringBody: stringBody);
          expect(payload.length, 7);
          expect(time.length, time == '3分钟' ? 3 : 7);
          final message = NeteaseChatMessage.parse(_row(payload));
          final card = message.card!;
          expect(card.togetherRecord, true);
          expect(card.togetherRoomId, 'synthetic_room');
          expect(card.durationDescription, time);
          expect(
            card.duration,
            time.length == 3
                ? const Duration(minutes: 3)
                : const Duration(hours: 26, minutes: 5),
          );
          expect(card.togetherAvatars, [
            'https://p1.music.126.net/synthetic-creator.png',
            'https://p2.music.126.net/synthetic-acceptor.png',
          ]);
          expect(message.text, contains('[一起听记录]'));
          expect(message.text, contains(time));
          expect(message.text, isNot('[分享内容]'));
          expect(message.diagnostics, isNull);
          final conversation = NeteaseConversation.parse({
            ..._row(payload),
            'lastMsg': jsonEncode(payload),
            'lastMsgTime': 1700000000000,
          }, '7');
          expect(conversation.last.card?.togetherRoomId, card.togetherRoomId);
          expect(conversation.last.text, message.text);
        },
      );
    }
  }

  test('modern msgType/body uses the same explicit type51 boundary', () {
    final legacy = type51Fixture(type: '51');
    final card = NeteaseMessageCard.parse({
      'msgBody': {'msgType': 51, 'body': legacy['opaqueRecordContainer']},
    });
    expect(card?.togetherRoomId, 'synthetic_room');
  });

  test('an unparsed label is retained without inventing numeric duration', () {
    final card = NeteaseChatMessage.parse(
      _row(type51Fixture(time: '不到一分钟')),
    ).card!;
    expect(card.duration, isNull);
    expect(card.durationDescription, '不到一分钟');
  });

  test(
    'record fields in a profile or an untyped unknown container are not messages',
    () {
      final payload = type51Fixture();
      expect(
        NeteaseChatMessage.parse({'msg': '你好', 'fromUser': payload}).card,
        isNull,
      );
      expect(NeteaseMessageCard.parse({'opaque': payload}), isNull);
      expect(
        NeteaseMessageCard.parse({
          'type': 51,
          'profile': payload['opaqueRecordContainer'],
        }),
        isNull,
      );
      expect(
        NeteaseChatMessage.parse(_row(type51Fixture(type: 6))).card,
        isNull,
      );
      expect(
        NeteaseMessageCard.parse({'roomId': 'synthetic_room', 'type': 51}),
        isNull,
      );
    },
  );

  test(
    'type51 never relaxes report URL validation or turns invitations into history',
    () {
      for (final url in [
        'javascript:alert(1)',
        'https://mp.music.163.com.evil.test/5fbcd6a217aef81f3a03eda5/ending/index.html',
        'https://secret@mp.music.163.com/5fbcd6a217aef81f3a03eda5/ending/index.html',
        'https://st.music.163.com/listen-together/share/?roomId=synthetic_room',
      ]) {
        final message = NeteaseChatMessage.parse(_row(type51Fixture(url: url)));
        expect(message.card, isNull, reason: url);
        expect(message.diagnostics, isNotNull);
      }
    },
  );

  test(
    'avatar slots retain creator/acceptor order and reject non-CDN identities',
    () {
      final payload = type51Fixture();
      final body = payload['opaqueRecordContainer'] as Map;
      body['creatorAvatarUrl'] = 'https://evil.test/private.png';
      body['acceptorAvatarUrl'] = 'http://p6.music.126.net/synthetic.png';
      final card = NeteaseChatMessage.parse(_row(payload)).card!;
      expect(card.togetherAvatars, [
        '',
        'https://p6.music.126.net/synthetic.png',
      ]);
      expect(() => card.togetherAvatars.add('x'), throwsUnsupportedError);
    },
  );

  test(
    'malformed and over-budget typed bodies remain unsupported and diagnosable',
    () {
      for (final body in [
        '{bad',
        'x' * 40000,
        {'title': '我们一起听了'},
        [],
      ]) {
        final payload = type51Fixture()..['opaqueRecordContainer'] = body;
        final message = NeteaseChatMessage.parse(_row(payload));
        expect(message.card, isNull);
        expect(message.diagnostics, isNotNull);
      }
    },
  );

  test(
    'diagnostic retains only proven schema names and never report values',
    () {
      final value = NeteaseMessageDiagnostics.fromRow(
        _row(type51Fixture()),
      ).json;
      final report = jsonDecode(value) as Map;
      expect(report['truncated'], false);
      expect(value, contains('recordOrpheus'));
      expect(value, contains('timeTitle'));
      expect(value, contains('ordinaryTogetherReport'));
      for (final private in [
        'synthetic_room',
        '26小时5分钟',
        'https://',
        'synthetic-creator',
        'MUSIC_U',
      ]) {
        expect(value, isNot(contains(private)), reason: private);
      }
    },
  );
}
