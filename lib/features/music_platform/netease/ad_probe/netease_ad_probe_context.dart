import 'dart:convert';

import '../../../../core/network/music_reward_diagnostic.dart';
import '../netease_free_listen_entry.dart';

/// Only presence bits may cross into the exported report. Keep this type
/// separate from the private request below so neither ext keys nor values can
/// accidentally be serialized by the report/export/UI layers.
final class NeteaseAdProbeRequestInfo {
  const NeteaseAdProbeRequestInfo({
    required this.sourceFromEntry,
    required this.backupUrlFromEntry,
    required this.extFromEntry,
    required this.rightsCommonExtFromEntry,
  });

  final bool sourceFromEntry, backupUrlFromEntry, extFromEntry;
  final bool rightsCommonExtFromEntry;

  Map<String, Object> toMap() => {
    'typeIdsPresent': true,
    'adextjsonPresent': true,
    'taskContextOnly': true,
    'sourceFromEntry': sourceFromEntry,
    'backupUrlFromEntry': backupUrlFromEntry,
    'extFromEntry': extFromEntry,
    'rightsCommonExtFromEntry': rightsCommonExtFromEntry,
    'deviceSdkContextAdded': false,
    'officialClientContextMatched': false,
  };
}

/// Private, single-task ad/get context. This is NOT qualificationJson and must
/// never be passed to an export, logger, WebView or server-issued backup URL.
/// Official9.6.15 Fragment.y starts with source/backupUrl, then ext overrides
/// them. ViewModel.j3 reads the same native Bundle; the existing entry parser
/// already applies that route's bizReportInfo/null-map serialization rules.
final class NeteaseAdProbeContext {
  const NeteaseAdProbeContext._(this.adextjson, this.info);

  final String adextjson;
  final NeteaseAdProbeRequestInfo info;

  /// Local resource bounds, not claimed upstream limits. Reject an excessive
  /// context as a whole rather than silently truncating issued task metadata.
  static NeteaseAdProbeContext? fromEntry(
    NeteaseFreeListenEntry entry,
    MusicRewardDiagnostic diagnostic,
  ) {
    final rawExt = entry.parameters['ext'];
    if (rawExt is! String || utf8.encode(rawExt).length > 65536) return null;
    try {
      final ext = jsonDecode(rawExt);
      if (ext is! Map<String, dynamic>) return null;
      var remaining = 256;
      bool bounded(Object? value, int depth) {
        if (--remaining < 0 || depth > 8) return false;
        if (value is Map<String, dynamic>) {
          return value.entries.every(
            (field) => bounded(field.value, depth + 1),
          );
        }
        if (value is List) {
          return value.every((item) => bounded(item, depth + 1));
        }
        return true;
      }

      if (!bounded(ext, 0)) return null;
      final context = jsonEncode({
        'source': entry.source,
        // ViewModel's absent Bundle value defaults to an empty string. This
        // value is carried only as request data; it is never followed as a URL.
        'backupUrl': entry.parameters['backupUrl'] ?? '',
        ...ext,
      });
      if (utf8.encode(context).length > 65536) return null;
      return NeteaseAdProbeContext._(
        context,
        NeteaseAdProbeRequestInfo(
          sourceFromEntry: diagnostic.hasSource == true,
          backupUrlFromEntry: entry.parameters['backupUrl'] != null,
          extFromEntry: diagnostic.hasExt == true,
          // No entranceComponent or device/SDK identifiers are synthesized.
          // An actual same-task ext field is kept as issued, without rewriting.
          rightsCommonExtFromEntry: ext.containsKey('rightsCommonExt'),
        ),
      );
    } on FormatException {
      return null;
    }
  }
}
