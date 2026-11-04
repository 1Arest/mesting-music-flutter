import 'dart:convert';

import 'netease_message_card.dart';
import 'netease_message_protocol.dart';

/// A deliberately lossy schema report for ONE unsupported message. No raw DTO,
/// profile, identifier, text, token or URL value is retained. Generating this
/// object does not write, log, upload or access the clipboard; the UI offers an
/// explicit preview/copy action. Keep it separate from automatic diagnostics.
class NeteaseMessageDiagnostics {
  const NeteaseMessageDiagnostics._(this.json);
  final String json;

  static NeteaseMessageDiagnostics fromRow(Map<String, dynamic> row) {
    const excludedFields = {
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
      'MUSIC_U',
      'MUSIC_A',
      '__csrf',
      'token',
      'accessToken',
      'refreshToken',
    };
    const knownFields = {
      ...NeteaseMessageCard.contentFields,
      'type',
      'msgType',
      'showType',
      'cardType',
      'resourceType',
      'mainTitle',
      'subTitle',
      'title',
      'subtitle',
      'description',
      'text',
      'nativeUrl',
      'actionUrl',
      'reportUrl',
      'recordUrl',
      'webUrl',
      'url',
      'linkUrl',
      'targetUrl',
      'coverUrl',
      'coverImgUrl',
      'cover',
      'picUrl',
      'totalConnectionTime',
      'currentConnectionTime',
      'durationSeconds',
      // Shipped LTRecordMsg names are safe schema identifiers. Their strings,
      // avatars, colors, room selectors and URLs still never leave this report.
      'recordOrpheus',
      'timeTitle',
      'historyTitle',
      'creatorAvatarUrl',
      'acceptorAvatarUrl',
      'isFriend',
      'startColor',
      'endColor',
      'titleColor',
      'songCount',
      'currentSongCount',
      'totalSongCount',
      'statistics',
      'recordId',
      'roomId',
      'id',
      'userId',
      'time',
    };
    const typeFields = {
      'type',
      'msgType',
      'showType',
      'cardType',
      'resourceType',
    };
    final entries = <Map<String, Object?>>[];
    var truncated = false;
    void inspect(Object? value, String path, int depth, [String key = '']) {
      if (entries.length >= 96 || depth > 7) {
        truncated = true;
        return;
      }
      final entry = <String, Object?>{'path': path};
      entries.add(entry);
      if (value is Map) {
        entry['kind'] = 'object';
        entry['fields'] = value.length;
        var index = 0;
        for (final item in value.entries.take(32)) {
          if (excludedFields.contains(item.key)) continue;
          // Unknown keys can themselves contain private text. Anonymous slots
          // reveal the presence of additional fields without exposing a key.
          final name = knownFields.contains(item.key)
              ? '${item.key}'
              : 'other${index++}';
          inspect(item.value, '$path.$name', depth + 1, name);
        }
        if (value.length > 32) truncated = true;
      } else if (value is List) {
        entry['kind'] = 'array';
        entry['items'] = value.length;
        for (var i = 0; i < value.length && i < 4; i++) {
          inspect(value[i], '$path[$i]', depth + 1);
        }
        if (value.length > 4) truncated = true;
      } else if (value is String) {
        entry['kind'] = 'string';
        entry['characters'] = value.length;
        entry['compatibilityNotice'] = NeteaseMessageCard.isCompatibilityText(
          value,
        );
        // Retain JSON shape only, including a second encoded JSON layer. Never
        // turn a free-form sentence into exported diagnostic content.
        if (value.length <= 32768) {
          final text = value.trimLeft();
          if (text.startsWith('{') ||
              text.startsWith('[') ||
              text.startsWith('"')) {
            try {
              final decoded = jsonDecode(value);
              if (decoded is Map ||
                  decoded is List ||
                  decoded is String && decoded != value) {
                inspect(decoded, '$path.json', depth + 1);
              }
            } on FormatException {
              entry['invalidJson'] = true;
            }
          }
          final url = NeteaseMessageCard.officialUrl(value);
          if (url != null) {
            entry['officialWebTarget'] = true;
            entry['togetherPath'] = url.path.contains('listen-together');
            entry['ordinaryTogetherReport'] =
                NeteaseMessageCard.isTogetherReportUrl(url);
            // A route's actual path/query can include a user or room ID.
            entry['queryFieldCount'] = url.queryParameters.length;
          }
        } else {
          truncated = true;
        }
      } else if (value is num) {
        entry['kind'] = 'number';
        // Only small integer message TYPE codes may cross the boundary.
        if (typeFields.contains(key) &&
            value is int &&
            value >= 0 &&
            value <= 255) {
          entry['typeCode'] = value;
        }
      } else {
        entry['kind'] = value == null
            ? 'null'
            : value is bool
            ? 'boolean'
            : 'other';
      }
    }

    // Inspect unknown outer fields too: otherwise the same filtering bug that
    // hid a new message container would hide the evidence needed to fix it.
    // Unknown names and all values remain redacted; profiles/auth are skipped.
    inspect(
      {
        for (final item in row.entries)
          if (!excludedFields.contains(item.key)) item.key: item.value,
      },
      'message',
      0,
    );
    return NeteaseMessageDiagnostics._(
      const JsonEncoder.withIndent('  ').convert({
        'format': 'mesting-netease-message-schema-v1',
        'readerVersion': NeteaseMessageProtocol.appVersion,
        'truncated': truncated,
        'entries': entries,
      }),
    );
  }
}
