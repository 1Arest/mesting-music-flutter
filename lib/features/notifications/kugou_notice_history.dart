import 'dart:convert';
import '../../core/network/music_http_client.dart';
import 'notification_models.dart';
import 'notification_sources.dart';
import 'notification_target.dart';

class KugouNoticeChatMessage {
  const KugouNoticeChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.time,
  });
  final String id, sender, text;
  final int time;
}

/// Official MsgHistoryProtocol.a reads one exact conversation tag. It does not
/// mark a message as read, send a message, or invoke the official application.
Future<List<KugouNoticeChatMessage>> readKugouNoticeHistory(
  NoticeAccount account,
  NoticeTarget target, {
  String before = '',
  String machine = 'Android',
}) async {
  if (target.tag.isEmpty) {
    throw const FormatException('Missing conversation tag');
  }
  final query =
      kugouNoticeParameters(
          account.identity,
          await readKugouNoticeDevice(),
          machine,
          DateTime.now(),
        )
        ..remove('utype')
        ..remove('machine')
        ..addAll({
          'tag': target.tag,
          'filter': '1',
          'pagesize': '30',
          if (NoticeTarget.identifier(before).isNotEmpty) 'maxid': before,
        });
  query['signature'] = kugouNoticeSignature(account.identity, query, '');
  final client = MusicHttpClient();
  try {
    final response = await client
        .get(
          Uri.https(
            'gateway.kugou.com',
            '/msg.mobile/v3/msgtag/history',
            query,
          ),
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw const FormatException('Conversation unavailable');
    }
    return parseKugouNoticeHistory(
      noticeMap(jsonDecode(utf8.decode(response.bodyBytes))),
    );
  } finally {
    client.close();
  }
}

List<KugouNoticeChatMessage> parseKugouNoticeHistory(
  Map<String, dynamic> response,
) {
  if (response['status'] != 1 || response['list'] is! List) {
    throw const FormatException('Conversation not confirmed');
  }
  return [
    for (final row in noticeRows(response['list']))
      if (NoticeTarget.identifier(row['msgid']).isNotEmpty)
        KugouNoticeChatMessage(
          id: NoticeTarget.identifier(row['msgid']),
          sender: NoticeTarget.identifier(row['uid']),
          text: kugouNoticeMessageBody(row['message']).isEmpty
              ? '[消息内容]'
              : kugouNoticeMessageBody(row['message']),
          time: (int.tryParse('${row['addtime']}') ?? 0) * 1000,
        ),
  ]..sort((a, b) => a.time.compareTo(b.time));
}
