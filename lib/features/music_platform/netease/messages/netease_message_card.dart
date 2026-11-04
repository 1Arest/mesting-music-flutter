import 'dart:convert';

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
    this.duration,
  });

  final String title, subtitle, cover;
  final Uri? detailUrl;
  final bool togetherRecord;
  final Duration? duration;

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
        }.contains(uri.host) ||
        (uri.hasPort && uri.port != 443 && uri.port != 80)) {
      return null;
    }
    return uri.replace(scheme: 'https', port: 443);
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
      var decodedLayers = 0;
      while (value is String && value.length <= 32768 && decodedLayers++ < 3) {
        try {
          value = jsonDecode(value);
        } on FormatException {
          break;
        }
      }
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
          ((labels.contains('一起听') &&
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
        for (final field in [
          'totalConnectionTime',
          'currentConnectionTime',
          'durationSeconds',
        ]) {
          final seconds = int.tryParse('${value[field]}');
          if (seconds != null && seconds >= 0 && seconds <= 366 * 86400 * 100) {
            duration = Duration(seconds: seconds);
            break;
          }
        }
        final cover =
            '${value['coverUrl'] ?? value['coverImgUrl'] ?? value['cover'] ?? value['picUrl'] ?? ''}';
        final coverUri = Uri.tryParse(cover);
        final card = NeteaseMessageCard(
          title: title.isEmpty ? '本次一起听记录' : title,
          subtitle: subtitle,
          togetherRecord: record,
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
