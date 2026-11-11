import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'qishui_image_upload_contract.dart';

/// Closed names keep the diagnostic boundary separate from server text. A
/// caller cannot accidentally export a URL, account ID or exception message.
enum QishuiDiagnosticFeature {
  socialStats,
  following,
  followers,
  userInfo,
  userFollow,
  userUnfollow,
  artistCollection,
  officialListening,
  listeningReport,
  coverUpload,
  playlistCover,
}

enum QishuiDiagnosticStage {
  prepare,
  helper,
  request,
  response,
  parse,
  identity,
  submit,
  receipt,
  grant,
  apply,
  storage,
  commit,
  readback,
  ledger,
}

enum QishuiDiagnosticOutcome {
  success,
  http,
  business,
  format,
  unconfirmed,
  localOnly,
  cancelled,
  network,
  refused,
}

enum QishuiDiagnosticReason {
  missingFields,
  invalidFields,
  storeReadFailed,
  storeWriteFailed,
  oversizedResponse,
  responseShape,
  invalidJson,
  emptyResponse,
  identityMissing,
  identityMismatch,
  accountChanged,
  reportDisabled,
  missingSigner,
  notSubmitted,
  receiptMissing,
  receiptRejected,
  httpRejected,
  networkFailure,
  grantInvalid,
  uploadAddressInvalid,
  storageReceiptInvalid,
  commitReceiptInvalid,
  cloudReadbackMismatch,
  unsupportedResponse,
  unknown,
}

enum QishuiDiagnosticGroup {
  all('全部'),
  social('关注与粉丝'),
  listening('听歌时长'),
  cover('歌单封面');

  const QishuiDiagnosticGroup(this.label);
  final String label;
}

/// Local, bounded observations. Recording and exporting never start a network
/// request, inspect credentials, read playback history or replay an event.
class QishuiDiagnostics extends ChangeNotifier {
  QishuiDiagnostics({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final shared = QishuiDiagnostics();
  static const maximumEvents = 160;
  static const maximumCompactCharacters = 4096;
  final DateTime Function() _now;
  final List<Map<String, Object>> _events = [];

  List<Map<String, Object>> get events => List.unmodifiable(_events);

  void record({
    required QishuiDiagnosticFeature feature,
    required QishuiDiagnosticStage stage,
    required QishuiDiagnosticOutcome outcome,
    int? httpStatus,
    Object? businessCode,
    Object? serviceCode,
    QishuiDiagnosticReason? reason,
    Object? response,
    bool? identityReady,
    bool? ownerReady,
    bool? willSubmit,
    bool? receiptAccepted,
  }) {
    final code = _numericCode(businessCode);
    final service = _serviceCode(serviceCode);
    final row = <String, Object>{
      'at': _now().toUtc().toIso8601String(),
      'feature': feature.name,
      'stage': stage.name,
      'outcome': outcome.name,
      if (httpStatus != null && httpStatus >= 100 && httpStatus <= 599)
        'httpStatus': httpStatus,
      'businessCode': ?code,
      'serviceCode': ?service,
      if (serviceCode != null) 'serviceCodePresent': true,
      if (reason != null) 'reason': reason.name,
      if (response != null) 'shape': responseShape(response),
      'identityReady': ?identityReady,
      'ownerReady': ?ownerReady,
      'willSubmit': ?willSubmit,
      'receiptAccepted': ?receiptAccepted,
    };
    // Freeze recursively: no reference to the untrusted response
    // survives and callers cannot mutate a stored nested map after recording.
    _events.add(_freeze(row));
    if (_events.length > maximumEvents) _events.removeAt(0);
    notifyListeners();
  }

  List<Map<String, Object>> select(QishuiDiagnosticGroup group) =>
      List.unmodifiable(_events.where((row) => _belongs(row, group)));

  String export({QishuiDiagnosticGroup group = QishuiDiagnosticGroup.all}) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(_envelope(select(group), group));

  /// Keep whole recent events; never cut JSON or strings to fit a clipboard.
  /// An unusually large single structure may be omitted, while its explicit
  /// failure code and stage stay available. Full file export retains it.
  String exportCompact({
    QishuiDiagnosticGroup group = QishuiDiagnosticGroup.all,
  }) {
    final selected = select(group);
    final end = selected.lastIndexWhere(
      (row) => !{'success', 'cancelled'}.contains(row['outcome']),
    );
    final rows = selected
        .take(end < 0 ? selected.length : end + 1)
        .map((row) => Map<String, Object>.of(row))
        .toList();
    if (rows.length > 10) rows.removeRange(0, rows.length - 10);
    String encode() => jsonEncode(_envelope(rows, group, compact: true));
    var text = encode();
    while (text.length > maximumCompactCharacters && rows.length > 1) {
      rows.removeAt(0);
      text = encode();
    }
    if (text.length > maximumCompactCharacters && rows.isNotEmpty) {
      rows.single.remove('shape');
      rows.single['shapeOmittedFromCompact'] = true;
      text = encode();
    }
    return text;
  }

  void clear() {
    _events.clear();
    notifyListeners();
  }

  Map<String, Object> _envelope(
    List<Map<String, Object>> rows,
    QishuiDiagnosticGroup group, {
    bool compact = false,
  }) => {
    'schema': 178,
    'appVersion': '1.0.91',
    'appVersionCode': 112,
    'platform': 'qishui',
    'memoryOnly': true,
    'group': group.name,
    if (group == QishuiDiagnosticGroup.all ||
        group == QishuiDiagnosticGroup.cover)
      'imageUploadContract': {
        'gatewayPath': QishuiImageUploadContract.apiPath,
        'signature': 'AWS4-HMAC-SHA256',
        'service': QishuiImageUploadContract.service,
        'regionMode': 'officialSdkDefault',
        'region': QishuiImageUploadContract.region,
      },
    'compact': compact,
    'eventCount': rows.length,
    'events': rows,
    'complete': true,
  };

  static bool _belongs(Map<String, Object> row, QishuiDiagnosticGroup group) {
    final feature = row['feature'];
    return switch (group) {
      QishuiDiagnosticGroup.all => true,
      QishuiDiagnosticGroup.listening =>
        feature == 'officialListening' || feature == 'listeningReport',
      QishuiDiagnosticGroup.cover =>
        feature == 'coverUpload' || feature == 'playlistCover',
      QishuiDiagnosticGroup.social =>
        feature != 'officialListening' &&
            feature != 'listeningReport' &&
            feature != 'coverUpload' &&
            feature != 'playlistCover',
    };
  }

  static int? _numericCode(Object? value) {
    if (value is! String && value is! int) return null;
    final text = '$value';
    if (!RegExp(r'^-?\d{1,12}$').hasMatch(text)) return null;
    return int.tryParse(text);
  }

  static String? _serviceCode(Object? value) {
    if (value == null) return null;
    // These are protocol constants, not a general-purpose server-message sink.
    return _knownServiceCodes.contains(value) ? value as String : 'unknown';
  }

  static const _knownServiceCodes = {
    'AccessDenied',
    'Forbidden',
    'Unauthorized',
    'InvalidParameter',
    'InvalidRequest',
    'InvalidArgument',
    'MissingParameter',
    'InvalidAction',
    'InvalidAccessKeyId',
    'InvalidAccessKey',
    'InvalidCredential',
    'InvalidSecurityToken',
    'InvalidToken',
    'ExpiredToken',
    'TokenExpired',
    'RequestExpired',
    'RequestTimeTooSkewed',
    'SignatureDoesNotMatch',
    'InvalidSignature',
    'IncompleteSignature',
    'InvalidAuthorization',
    'AuthorizationQueryParametersError',
    'MalformedAuthorization',
    'InternalError',
    'ServiceUnavailable',
    'RequestLimitExceeded',
    'Throttling',
    'InvalidServiceId',
    'NoSuchService',
    'SignatureExpired',
    'InvalidSessionKey',
    'InvalidStoreUri',
    'InvalidFileType',
    'InvalidImage',
    'InvalidImageFormat',
    'ImageTooLarge',
    'forbidden_route',
    'forbidden_query',
    'forbidden_body_field',
    'forbidden_header',
    'invalid_content_type',
    'body_digest_mismatch',
    'identity_mismatch',
  };

  /// Return types and bounded container counts only. Unknown property NAMES
  /// are not copied either: a service may put personal data in object keys.
  static Map<String, Object> responseShape(Object? value) {
    var remaining = 36;
    Map<String, Object> visit(Object? node, int depth) {
      if (remaining-- <= 0) return const {'type': 'omitted'};
      if (node == null) return const {'type': 'null'};
      if (node is String) return const {'type': 'string'};
      if (node is bool) return const {'type': 'boolean'};
      if (node is num) return const {'type': 'number'};
      if (node is List) {
        return {
          'type': 'array',
          'count': node.length.clamp(0, 100000),
          if (depth < 3 && node.isNotEmpty && remaining > 0)
            'first': visit(node.first, depth + 1),
        };
      }
      if (node is Map) {
        final fields = <String, Object>{};
        if (depth < 3) {
          for (final key in _shapeKeys) {
            if (remaining <= 0) break;
            if (node.containsKey(key)) {
              fields[key] = visit(node[key], depth + 1);
            }
          }
        }
        return {
          'type': 'object',
          'fieldCount': node.length.clamp(0, 100000),
          if (fields.isNotEmpty) 'fields': fields,
        };
      }
      return const {'type': 'other'};
    }

    return visit(value, 0);
  }

  static const _shapeKeys = [
    'data',
    'status_info',
    'status_code',
    'error_code',
    'code',
    'status',
    'message',
    'error',
    'follow_items',
    'users',
    'user_list',
    'following_list',
    'follower_list',
    'items',
    'list',
    'next_cursor',
    'cursor',
    'has_more',
    'item_type',
    'artist',
    'artists',
    'artist_ids',
    'deleted_artists',
    'follow_status',
    'user',
    'my_info',
    'my_stats',
    'user_stats',
    'my_user_state',
    'count_following',
    'count_follower',
    'count_all_liked',
    'count_luna_following',
    'count_luna_follower',
    'listen_duration',
    'music_wall',
    'total_duration',
    'week_duration',
    'week_rank',
    'like_count',
    'success',
    'Result',
    'ResponseMetadata',
    'Error',
    'Code',
    'UploadAddress',
    'InnerUploadAddress',
    'StoreInfos',
    'UploadHosts',
    'Results',
    'Uri',
    'uploader_info',
  ];

  static Map<String, Object> _freeze(Map<String, Object> row) {
    Object freeze(Object? value) {
      if (value is Map) {
        return Map<String, Object>.unmodifiable({
          for (final entry in value.entries)
            if (entry.value != null) '${entry.key}': freeze(entry.value),
        });
      }
      if (value is List) return List<Object>.unmodifiable(value.map(freeze));
      return value!;
    }

    return freeze(row) as Map<String, Object>;
  }
}
