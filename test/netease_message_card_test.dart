import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_card.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';

// Synthetic protocol examples, not a captured user's message or acceptance
// evidence for an actual account. No private body is written into diagnostics.
Map<String, Object?> recordEnvelope({Object? body}) => {
  'msg': '当前版本暂不支持此消息',
  'generalMsg':
      body ??
      {
        'mainTitle': {'title': '本次一起听记录'},
        'subTitle': {'title': '我们一起听了 12 分钟'},
        'totalConnectionTime': 720,
        'nativeUrl':
            'orpheus://nm/redirect?url2=${Uri.encodeComponent('https://st.music.163.com/listen-together/record/?id=fixture')}',
      },
};

void main() {
  test(
    'a general card replaces old-client fallback text in history and previews',
    () {
      final row = <String, dynamic>{
        'id': 'record-1',
        'time': 1000,
        'msg': jsonEncode(recordEnvelope()),
        'fromUser': {'userId': 8},
        'toUser': {'userId': 7},
      };
      final message = NeteaseChatMessage.parse(row);
      expect(message.card?.togetherRecord, isTrue);
      expect(message.card?.title, '本次一起听记录');
      expect(message.card?.duration, const Duration(minutes: 12));
      expect(message.text, startsWith('[一起听记录]'));
      expect(message.text, isNot(contains('不支持')));
      final conversation = NeteaseConversation.parse({
        ...row,
        'lastMsg': row['msg'],
        'lastMsgTime': 1000,
      }, '7');
      expect(conversation.last.card, isNotNull);
      expect(conversation.last.text, message.text);
    },
  );
  test('modern body and nested JSON envelopes use the same parser', () {
    for (final key in ['body', 'msgBody', 'json']) {
      final message = NeteaseChatMessage.parse({
        'msg': jsonEncode({'msg': '升级 App 到最新版本即可查看该消息'}),
        key: jsonEncode(recordEnvelope()['generalMsg']),
      });
      final parsed = message.card;
      expect(parsed?.title, '本次一起听记录');
    }
  });
  test('only explicit seconds fields become numeric listening duration', () {
    final result = NeteaseMessageCard.parse({
      'generalMsg': {'title': '一起听报告', 'duration': 999999},
    });
    expect(result?.duration, isNull);
    expect(result?.durationLabel, '');
    expect(result?.detailUrl, isNull);
  });
  test('the outer URL and nested titles remain on the same card', () {
    final card = NeteaseMessageCard.parse({
      'nativeUrl':
          'https://st.music.163.com/listen-together/record/?id=fixture',
      'body': jsonEncode({
        'mainTitle': {'title': '我们的本次一起听记录'},
        'subTitle': {'title': '一起听了 8 分钟'},
        'durationSeconds': 480,
      }),
    });
    expect(card?.title, '我们的本次一起听记录');
    expect(card?.detailUrl?.queryParameters['id'], 'fixture');
    expect(card?.duration?.inMinutes, 8);
  });
  test('a free room ID, plain text, or a profile is not a history record', () {
    expect(NeteaseMessageCard.parse({'roomId': 'r', 'msg': '一起听吗？'}), isNull);
    final result = NeteaseChatMessage.parse({
      'msg': jsonEncode({'msg': '你好'}),
      'fromUser': {'userId': 8, ...recordEnvelope()},
    });
    expect(result.card, isNull);
    expect(result.text, '你好');
  });
  test('an invitation card stays distinct from a completed record', () {
    final card = NeteaseMessageCard.parse({
      'generalMsg': {
        'mainTitle': {'title': '邀请你一起听'},
        'nativeUrl':
            'https://st.music.163.com/listen-together/share/?roomId=r&inviterId=8',
      },
    });
    expect(card?.togetherRecord, isFalse);
    expect(card?.detailUrl?.path, '/listen-together/share/');
  });
  test(
    'only validated official HTTPS destinations survive nested wrappers',
    () {
      final official =
          'https://st.music.163.com/listen-together/record/?id=fixture';
      expect(
        NeteaseMessageCard.officialUrl(
          'orpheus://nm/webview?url=${Uri.encodeComponent(official)}',
        )?.path,
        '/listen-together/record/',
      );
      for (final url in [
        'javascript:alert(1)',
        'file:///private',
        'https://127.0.0.1/record',
        'https://st.music.163.com.evil.test/record',
        'https://account:secret@music.163.com/record',
        'https://evil.test/?url2=${Uri.encodeComponent(official)}',
        'orpheus://nm/unknown?url2=${Uri.encodeComponent(official)}',
        'orpheus://nm/redirect?url2=javascript%3Aalert(1)',
      ]) {
        expect(NeteaseMessageCard.officialUrl(url), isNull, reason: url);
      }
    },
  );
  test('web navigation refuses malformed URLs and unexecuted wrappers', () {
    expect(
      NeteaseMessageCard.canNavigateWeb(
        'https://st.music.163.com/listen-together/record/?id=fixture',
      ),
      isTrue,
    );
    for (final value in [
      'https://[bad',
      'javascript:alert(1)',
      'https://evil.test/record',
      'orpheus://nm/webview?url=https%3A%2F%2Fmusic.163.com',
    ]) {
      expect(NeteaseMessageCard.canNavigateWeb(value), isFalse);
    }
  });
  test('malformed/deep/oversized payloads do not break the conversation', () {
    expect(NeteaseMessageCard.parse({'body': '{bad'}), isNull);
    Object nested = recordEnvelope();
    for (var i = 0; i < 20; i++) {
      nested = {'body': nested};
    }
    expect(NeteaseMessageCard.parse({'body': nested}), isNull);
    expect(NeteaseMessageCard.parse({'body': 'x' * 40000}), isNull);
  });
}
