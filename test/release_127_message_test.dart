import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_card.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_diagnostic_action.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_message_diagnostics.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';

const _warning = '当前版本无法显示该信息，请在应用市场下载最新版app';
// Structural regression examples, not a captured account's Together record.
final _record = {
  'mainTitle': {'title': '本次一起听记录'},
  'subTitle': {'title': '一起听了10首歌曲'},
  'durationSeconds': 8700,
  'nativeUrl':
      'https://st.music.163.com/listen-together/record/?id=private-record',
};

void main() {
  setUpAll(LiquidGlassWidgets.initialize);

  test('message containers survive the history and preview boundary', () {
    for (final key in [
      'extra',
      'payload',
      'record',
      'report',
      'jsonMsg',
      'msgContent',
      'customMsg',
      'ext',
    ]) {
      final row = <String, dynamic>{
        'msg': jsonEncode({'msg': _warning}),
        key: jsonEncode({'generalMsg': _record}),
      };
      final message = NeteaseChatMessage.parse(row);
      expect(message.card?.togetherRecord, isTrue, reason: key);
      expect(message.card?.duration, const Duration(hours: 2, minutes: 25));
      expect(message.diagnostics, isNull);
      final preview = NeteaseConversation.parse({
        ...row,
        'lastMsg': row['msg'],
      }, '7');
      expect(preview.last.card?.title, '本次一起听记录', reason: key);
    }
  });

  test(
    'double JSON body and outer URL are read without executing a scheme',
    () {
      final card = NeteaseChatMessage.parse({
        'msg': jsonEncode({'msg': _warning}),
        'nativeUrl': _record['nativeUrl'],
        'msgBody': jsonEncode(jsonEncode({'msgType': 47, 'body': _record})),
      }).card;
      expect(card?.title, '本次一起听记录');
      expect(card?.detailUrl?.queryParameters['id'], 'private-record');
    },
  );

  test('modern plain text wins over an older compatibility notice', () {
    final message = NeteaseChatMessage.parse({
      'msg': jsonEncode({'msg': _warning}),
      'msgBody': jsonEncode({
        'msgType': 0,
        'body': jsonEncode({'msg': '实际正文'}),
      }),
    });
    expect(message.text, '实际正文');
    expect(message.diagnostics, isNull);
    expect(message.card, isNull);
  });

  test('compatibility notice stays unresolved and offers a schema report', () {
    final row = NeteaseChatMessage.parse({
      'msg': jsonEncode({'type': 24, 'msg': _warning}),
      'fromUser': {'title': '一起听记录', 'userId': 'private-user'},
    });
    expect(row.card, isNull);
    expect(row.text, _warning);
    expect(row.diagnostics, isNotNull);
    expect(
      NeteaseMessageCard.parse({
        'mainTitle': {'title': _warning},
      }),
      isNull,
    );
  });

  test(
    'schema export retains types and removes text identifiers keys and URL values',
    () {
      final report = NeteaseMessageDiagnostics.fromRow({
        'id': 123456789,
        'fromUser': {'nickname': 'private-name', 'userId': 'private-user'},
        'futurePrivateContainer': {
          'msgType': 99,
          'payload': 'private-future-text',
        },
        'msg': jsonEncode({
          'type': 24,
          'msg': _warning,
          'secret-user-key': 'private-text',
          'payload': {
            'msgType': 47,
            'generalMsg': _record,
            'id': 'private-id',
            'MUSIC_U': 'private-cookie',
            'url': 'https://evil.example/private-link',
          },
        }),
      });
      for (final private in [
        '123456789',
        'private-name',
        'private-user',
        'private-text',
        'secret-user-key',
        'private-id',
        'private-cookie',
        'private-link',
        'private-record',
        'MUSIC_U',
        'evil.example',
        _warning,
        '本次一起听记录',
        'futurePrivateContainer',
        'private-future-text',
      ]) {
        expect(report.json, isNot(contains(private)), reason: private);
      }
      final data = jsonDecode(report.json) as Map;
      final entries = (data['entries'] as List).cast<Map>();
      expect(entries.any((e) => e['typeCode'] == 24), isTrue);
      expect(entries.any((e) => e['typeCode'] == 47), isTrue);
      expect(entries.any((e) => e['typeCode'] == 99), isTrue);
      expect(entries.any((e) => e['officialWebTarget'] == true), isTrue);
    },
  );

  test(
    'schema traversal stops at fixed budgets for deep wide and oversized bodies',
    () {
      Object body = {'msg': 'private-text'};
      for (var i = 0; i < 15; i++) {
        body = {'body': body};
      }
      for (final value in [body, List.filled(200, _record), 'x' * 40000]) {
        final data = jsonDecode(
          NeteaseMessageDiagnostics.fromRow({'msgBody': value}).json,
        );
        expect(data['truncated'], isTrue);
        expect((data['entries'] as List).length, lessThanOrEqualTo(96));
      }
    },
  );

  for (final invalidate in [false, true]) {
    testWidgets(
      'export requires preview and explicit copy; account invalidation=$invalidate',
      (tester) async {
        final copied = <String>[];
        var current = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                copied.add((call.arguments as Map)['text'] as String);
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final report = NeteaseMessageDiagnostics.fromRow({
          'msg': jsonEncode({'type': 24, 'msg': _warning}),
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NeteaseMessageDiagnosticAction(
                report: report,
                isCurrent: () => current,
              ),
            ),
          ),
        );
        expect(copied, isEmpty);
        await tester.tap(find.text('导出此条诊断'));
        await tester.pumpAndSettle();
        expect(find.text('导出此条消息诊断'), findsOneWidget);
        expect(copied, isEmpty);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(copied, isEmpty);
        await tester.tap(find.text('导出此条诊断'));
        await tester.pumpAndSettle();
        if (invalidate) current = false;
        await tester.tap(find.text('复制诊断'));
        await tester.pumpAndSettle();
        expect(copied, invalidate ? isEmpty : [report.json]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
