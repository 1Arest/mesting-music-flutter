import 'dart:convert';

import '../../../../shared/utils/media_uri.dart' show normalizeArtworkUri;

/// A private-message card is distinct from a song share or an invitation.
/// GeneralMessage can be inside msg, body, msgBody or another JSON string;
/// its plain-text msg is often only an older-client compatibility warning.
class NeteaseMessageCard {
  const NeteaseMessageCard({
    required this.title,
    this.subtitle = '',
    this.cover = '',
    this.detailUrl,
    this.togetherRecord = false,
    this.togetherRoomId = '',
    this.durationDescription = '',
    this.togetherAvatars = const [],
    this.duration,
  });

  final String title, subtitle, cover;
  final Uri? detailUrl;
  final bool togetherRecord;

  /// Only the official report's room selector is carried into the read-only
  /// repository. Opening a historical card never reuses it as a live room.
  final String togetherRoomId;
  final Duration? duration;

  /// Type 51 supplies an already formatted session label, not a numeric total.
  final String durationDescription;

  /// The official payload orders creator then acceptor; neither role implies
  /// the current account. Keep both slots instead of relabelling them as self.
  final List<String> togetherAvatars;

  String get durationLabel {
    final value = duration;
    if (value == null) return '';
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    return hours > 0
        ? '$hours 小时 $minutes 分钟'
        : minutes > 0
        ? '$minutes 分钟 $seconds 秒'
        : '$seconds 秒';
  }

  String get summary =>
      '${togetherRecord ? '[一起听记录] ' : '[消息卡片] '}$title'
      '${subtitle.isEmpty ? '' : ' · $subtitle'}';

  static String _text(Object? value, [int limit = 600]) {
    if (value is Map) value = value['title'] ?? value['text'];
    if (value is! String) return '';
    final text = value.trim();
    if (text.isEmpty || text.length > limit || isCompatibilityText(text)) {
      return '';
    }
    return text;
  }

  static bool isCompatibilityText(String value) =>
      value.contains('不支持') ||
      (value.contains('升级') && value.contains('消息')) ||
      (value.contains('无法显示') && RegExp('信息|消息|内容').hasMatch(value)) ||
      value.contains('请前往移动端查看');

  /// Use one boundary for history, conversation previews and nested payloads.
  /// Previously several supported containers were dropped before parse() saw
  /// them. Profiles remain outside this boundary even if they contain titles.
  static const contentFields = [
    'generalMsg',
    'body',
    'msgBody',
    'json',
    'jsonMsg',
    'msgContent',
    'customMsg',
    'data',
    'content',
    'listenTogether',
    'listenTogetherRecord',
    'listenTogetherInfo',
    'msg',
    'lastMsg',
    'message',
    'extInfo',
    'extJsonInfo',
    'ext',
    'extra',
    'payload',
    'card',
    'cardInfo',
    'report',
    'record',
    'cards',
    'richMsg',
    'commonMessage',
    'resource',
    'resources',
    'resourceJson',
    'jsonData',
    'cardData',
    'shareInfo',
  ];

  static Map<String, dynamic> messageEnvelope(Map<String, dynamic> row) => {
    for (final field in [
      ...contentFields,
      'nativeUrl',
      'actionUrl',
      'reportUrl',
      'recordUrl',
      'webUrl',
      'url',
      'linkUrl',
      'targetUrl',
      'msgType',
      'type',
    ])
      if (row[field] != null) field: row[field],
  };

  /// A WebView may navigate only to an already-unwrapped HTTPS target.
  /// Both parse failures must never accidentally compare equal as nulls.
  static bool canNavigateWeb(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }
    final allowed = officialUrl(value);
    return allowed != null && allowed == uri.replace(port: 443);
  }

  /// Only exact music web hosts can be opened. Redirect/webview wrappers are
  /// decoded as data; no arbitrary scheme, script, HTML or outer URI executes.
  static Uri? officialUrl(Object? value, [int depth = 0]) {
    if (value is Map) {
      value = value['url'] ?? value['webUrl'] ?? value['targetUrl'];
    }
    if (value is! String || value.length > 16384 || depth > 5) return null;
    var text = value.trim().replaceAll('&amp;', '&');
    if (RegExp(r'^(https?|orpheus)%3a', caseSensitive: false).hasMatch(text)) {
      try {
        text = Uri.decodeComponent(text);
      } on FormatException {
        return null;
      }
      return officialUrl(text, depth + 1);
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.userInfo.isNotEmpty) return null;
    if (uri.scheme == 'orpheus' &&
        uri.host == 'nm' &&
        {'/redirect', '/webview'}.contains(uri.path)) {
      for (final key in ['url2', 'url', 'url1']) {
        final result = officialUrl(uri.queryParameters[key], depth + 1);
        if (result != null) return result;
      }
      return null;
    }
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !{
          'music.163.com',
          'st.music.163.com',
          'y.music.163.com',
          'mp.music.163.com',
        }.contains(uri.host) ||
        (uri.hasPort && uri.port != 443 && uri.port != 80)) {
      return null;
    }
    return uri.replace(scheme: 'https', port: 443);
  }

  /// The shipped official link configuration points ordinary two-person
  /// reports at this activity, not at the separate multi-room result page.
  /// Inspect the URL as data; never execute an orpheus/native bridge action.
  static bool isTogetherReportUrl(Uri? uri) =>
      uri != null &&
      uri.host == 'mp.music.163.com' &&
      uri.path == '/5fbcd6a217aef81f3a03eda5/ending/index.html';

  static String _roomId(Uri? uri) {
    if (!isTogetherReportUrl(uri)) return '';
    final value = uri!.queryParameters['roomId'] ?? '';
    return RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(value) ? value : '';
  }

  /// A legacy generalMsg may carry its time only in the human-readable title
  /// or subtitle. Read explicit units; bare numbers are not guessed as seconds.
  static Duration? _durationText(String text) {
    final parts = RegExp(r'(\d+)\s*(小时|分钟|秒)').allMatches(text);
    var seconds = 0;
    var found = false;
    int? previousEnd;
    for (final match in parts) {
      if (previousEnd != null &&
          text.substring(previousEnd, match.start).trim().isNotEmpty) {
        break;
      }
      if (match.start > 0 && text[match.start - 1] == '-') return null;
      final amount = int.tryParse(match.group(1)!);
      if (amount == null) return null;
      seconds +=
          amount *
          switch (match.group(2)) {
            '小时' => 3600,
            '分钟' => 60,
            _ => 1,
          };
      found = true;
      previousEnd = match.end;
    }
    return found && seconds <= 366 * 86400 * 100
        ? Duration(seconds: seconds)
        : null;
  }

  static Object? _decodeContent(Object? value) {
    var layers = 0;
    while (value is String && value.length <= 32768 && layers++ < 3) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        break;
      }
    }
    return value;
  }

  static String _recordAvatar(Object? value) {
    if (value is! String || value.length > 4096) return '';
    // Reuse the common artwork policy for older official HTTP CDN links, then
    // apply this message's narrower host/credential boundary before rendering.
    final normalized = normalizeArtworkUri(value);
    final uri = Uri.tryParse(normalized);
    return uri?.scheme == 'https' &&
            uri!.userInfo.isEmpty &&
            (!uri.hasPort || uri.port == 443) &&
            RegExp(r'^p[1-6]\.music\.126\.net$').hasMatch(uri.host)
        ? normalized
        : '';
  }

  /// Official MsgBody maps 51 to post.meta.LTRecordMsg, not CommonMessage.
  /// Its wire body uses recordOrpheus/timeTitle and two participant avatars.
  /// The privacy-redacted reports hide the body's outer field name. Instead
  /// of guessing that name, scan a bounded number of direct children of an
  /// explicitly typed message. Require this DTO signature plus the validated
  /// ordinary-report URL; never recursively read profiles as message bodies.
  static NeteaseMessageCard? _type51Record(Map value) {
    final candidates = <Map>[value];
    for (final entry in value.entries.take(24)) {
      if (const {
        'fromUser',
        'toUser',
        'user',
        'profile',
        'sender',
        'receiver',
        'cookie',
        'cookies',
        'headers',
        'authorization',
      }.contains(entry.key)) {
        continue;
      }
      final child = _decodeContent(entry.value);
      if (child is Map) candidates.add(child);
    }
    for (final body in candidates) {
      if (!body.containsKey('recordOrpheus') ||
          !body.containsKey('timeTitle')) {
        continue;
      }
      final url = officialUrl(body['recordOrpheus']);
      if (!isTogetherReportUrl(url)) continue;
      final title = _text(body['title'], 200);
      final timeTitle = _text(body['timeTitle'], 120);
      if (title.isEmpty || timeTitle.isEmpty) continue;
      return NeteaseMessageCard(
        title: title,
        subtitle: timeTitle,
        togetherRecord: true,
        togetherRoomId: _roomId(url),
        detailUrl: url,
        duration: _durationText(timeTitle),
        durationDescription: timeTitle,
        togetherAvatars: List.unmodifiable([
          _recordAvatar(body['creatorAvatarUrl']),
          _recordAvatar(body['acceptorAvatarUrl']),
        ]),
      );
    }
    return null;
  }

  /// Traversal is limited to message-content fields, never peer profiles. This
  /// supports historical and current envelopes without guessing a numeric type
  /// or treating a free-form roomId as a record. Unknown fields are not shown.
  static NeteaseMessageCard? parse(Map<String, dynamic> envelope) {
    final queue = <({Object? value, int depth, Uri? inheritedUrl})>[
      (value: envelope, depth: 0, inheritedUrl: null),
    ];
    NeteaseMessageCard? fallback;
    var bestScore = -1;
    var visited = 0;
    while (queue.isNotEmpty && visited++ < 48) {
      final node = queue.removeAt(0);
      if (node.depth > 5) continue;
      Object? value = node.value;
      // Some transports put a JSON string inside a JSON string. Decode only a
      // bounded number of layers; malformed bodies never break the chat list.
      value = _decodeContent(value);
      if (value is List) {
        for (final item in value.take(12)) {
          queue.add((
            value: item,
            depth: node.depth + 1,
            inheritedUrl: node.inheritedUrl,
          ));
        }
        continue;
      }
      if (value is! Map) continue;
      if (int.tryParse('${value['type'] ?? value['msgType']}') == 51) {
        final typed = _type51Record(value);
        if (typed != null) return typed;
        // A malformed type-51 body remains diagnosable; its title alone must
        // not fabricate a working ended-session card or bypass URL checks.
        continue;
      }
      final title = _text(value['mainTitle'] ?? value['title'], 200);
      final subtitle = _text(
        value['subTitle'] ??
            value['subtitle'] ??
            value['description'] ??
            value['content'] ??
            value['text'],
      );
      final rawUrl =
          value['nativeUrl'] ??
          value['actionUrl'] ??
          value['reportUrl'] ??
          value['recordUrl'] ??
          value['webUrl'] ??
          value['url'] ??
          value['linkUrl'] ??
          value['targetUrl'];
      final url = officialUrl(rawUrl) ?? node.inheritedUrl;
      final labels = '$title $subtitle';
      final invitation =
          url != null &&
          (url.path.contains('/listen-together/share') ||
              url.path.contains('/listen-together/multishare'));
      final record =
          !invitation &&
          (isTogetherReportUrl(url) ||
              (labels.contains('一起听') &&
                  RegExp('记录|报告|结束|时长|听了|共同听过').hasMatch(labels)) ||
              RegExp(
                r'listen[-/]?together.*(record|report|history)',
                caseSensitive: false,
              ).hasMatch('${url ?? rawUrl ?? ''}'));
      // Plain text with a title is not a structured card by itself. Recognized
      // card fields or a validated action must accompany it.
      final structured =
          value.containsKey('mainTitle') ||
          value.containsKey('nativeUrl') ||
          record ||
          (url != null && subtitle.isNotEmpty);
      if (structured && (title.isNotEmpty || record)) {
        Duration? duration;
        for (final field in ['currentConnectionTime', 'durationSeconds']) {
          final seconds = int.tryParse('${value[field]}');
          if (seconds != null && seconds >= 0 && seconds <= 366 * 86400 * 100) {
            duration = Duration(seconds: seconds);
            break;
          }
        }
        // A report's session value and its all-time relationship total are
        // separate statistics. Retain the old generic-card interpretation only
        // for messages that are not recognized as an ended together session.
        if (!record && duration == null) {
          final total = int.tryParse('${value['totalConnectionTime']}');
          if (total != null && total >= 0 && total <= 366 * 86400 * 100) {
            duration = Duration(seconds: total);
          }
        }
        if (record) {
          duration ??= _durationText(subtitle) ?? _durationText(title);
        }
        final cover =
            '${value['coverUrl'] ?? value['coverImgUrl'] ?? value['cover'] ?? value['picUrl'] ?? ''}';
        final coverUri = Uri.tryParse(cover);
        final card = NeteaseMessageCard(
          title: title.isEmpty ? '本次一起听记录' : title,
          subtitle: subtitle,
          togetherRecord: record,
          togetherRoomId: record ? _roomId(url) : '',
          detailUrl: url,
          duration: duration,
          cover:
              coverUri?.scheme == 'https' &&
                  {
                    'p1.music.126.net',
                    'p2.music.126.net',
                    'p3.music.126.net',
                  }.contains(coverUri?.host)
              ? cover
              : '',
        );
        // A wrapper may own the URL while its body owns the actual titles.
        final score =
            (record ? 100 : 0) +
            (title.isNotEmpty ? 10 : 0) +
            (url != null ? 4 : 0) +
            (subtitle.isNotEmpty ? 2 : 0) +
            (duration != null ? 1 : 0);
        if (score > bestScore) {
          fallback = card;
          bestScore = score;
        }
      }
      for (final key in contentFields) {
        if (value[key] != null) {
          queue.add((
            value: value[key],
            depth: node.depth + 1,
            inheritedUrl: url,
          ));
        }
      }
    }
    return fallback;
  }
}
