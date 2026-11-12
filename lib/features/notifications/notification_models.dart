import 'dart:convert';

import '../music_platform/domain/platform_session.dart';

enum MusicNoticeKind {
  privateMessage('私信'),
  interaction('评论、赞与关注'),
  artist('关注歌手动态'),
  recommendation('新歌推荐');

  const MusicNoticeKind(this.label);
  final String label;
}

/// Only fixed destinations cross the native boundary. Upstream URLs and signed
/// resource links are never treated as navigation commands.
class MusicNotice {
  const MusicNotice({
    required this.id,
    required this.platform,
    required this.kind,
    required this.title,
    required this.body,
    this.time = 0,
    this.peer = '',
  });
  final String id, title, body, peer;
  final MusicPlatform platform;
  final MusicNoticeKind kind;
  final int time;

  Map<String, Object?> toJson() => {
    'id': id,
    'platform': platform.name,
    'kind': kind.name,
    'title': title,
    'body': body,
    'time': time,
    'peer': peer,
  };
}

class NoticeFeed {
  const NoticeFeed(this.key, this.events, {this.cursor = ''});
  final String key, cursor;
  final List<MusicNotice> events;
}

/// Bounded history survives process death. A first successful read establishes
/// a baseline; it does not alert for the account's existing inbox. Failed reads
/// never enter this reducer, so an error cannot erase history or advance a cursor.
class NoticeDiff {
  NoticeDiff({required this.state, required this.fresh});
  final Map<String, Object?> state;
  final List<MusicNotice> fresh;

  static NoticeDiff apply(NoticeFeed feed, Map<String, dynamic>? previous) {
    final old = (previous?['seen'] as List?)?.whereType<String>().toSet() ?? {};
    final initialized = previous?['initialized'] == true;
    final unique = <String, MusicNotice>{
      for (final event in feed.events)
        if (event.id.isNotEmpty) event.id: event,
    };
    final fresh = initialized
        ? unique.values.where((e) => !old.contains(e.id)).toList()
        : <MusicNotice>[];
    final seen = [
      ...unique.keys,
      ...old.where((id) => !unique.containsKey(id)),
    ];
    return NoticeDiff(
      state: {
        'initialized': true,
        'seen': seen.take(500).toList(),
        'cursor': feed.cursor,
      },
      fresh: fresh,
    );
  }
}

Map<String, dynamic> noticeMap(Object? value) {
  if (value is String) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return {};
    }
  }
  return value is Map ? Map<String, dynamic>.from(value) : {};
}

List<Map<String, dynamic>> noticeRows(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

String noticeText(Object? value, [int limit = 180]) {
  final text = '${value ?? ''}'
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '')
      .trim();
  return text.runes.length > limit
      ? String.fromCharCodes(text.runes.take(limit))
      : text;
}
