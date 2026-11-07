import 'dart:convert';

/// The free-listening button opens the actionUrl supplied by the same account's
/// FREE_LISTEN progress response. We interpret the known native route locally;
/// the URL is never opened, fetched or forwarded to another host.
///
/// The route and conversions follow the inspected 9.6.15 motivationAd/show
/// handler and its Activity Bundle. An entry is context, not proof that an ad
/// was watched. Never construct an entry by guessing a source or ad position.
class NeteaseFreeListenEntry {
  NeteaseFreeListenEntry._(Map<String, Object?> parameters)
    : parameters = Map.unmodifiable(parameters);

  final Map<String, Object?> parameters;

  bool get requestsQualification => parameters['isNeedGetRights'] == true;
  int get source => parameters['source'] as int;

  /// reqParam is a JSON string at the official form/encryption boundary.
  /// In particular, ext is itself the serialized native Bundle string.
  String get qualificationJson => jsonEncode({
    // Fastjson's inspected default MapSerializer omits null entries before
    // FormBody/encryption. Keep nullable Bundle facts in `parameters` while
    // matching that boundary here; do not parse or rewrite the ext string.
    for (final entry in parameters.entries)
      if (entry.value != null) entry.key: entry.value,
  });

  static int? _integer(String? text) {
    if (text == null || !RegExp(r'^[+-]?[0-9]+$').hasMatch(text)) return null;
    final number = int.tryParse(text);
    // The Android route uses Integer.parseInt, not an arbitrary-size integer.
    return number != null && number >= -2147483648 && number <= 2147483647
        ? number
        : null;
  }

  /// The official ext serializer also delegates to Fastjson's default map
  /// writer. Null map entries are omitted; null array elements remain values.
  /// This applies before ext becomes a string, never to opaque rightsExtJson.
  static Object? _nativeJsonValue(Object? value) => switch (value) {
    Map<String, dynamic> map => {
      for (final entry in map.entries)
        if (entry.value != null) entry.key: _nativeJsonValue(entry.value),
    },
    List<dynamic> list => [for (final item in list) _nativeJsonValue(item)],
    _ => value,
  };

  static NeteaseFreeListenEntry? parse(Object? actionUrl) {
    try {
      return _parse(actionUrl);
    } on FormatException {
      // URI query decoding can fail after Uri.tryParse has accepted the URL.
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static NeteaseFreeListenEntry? _parse(Object? actionUrl) {
    // This is a client parsing bound, not a claimed upstream URL limit.
    if (actionUrl is! String || actionUrl.length > 65536) return null;
    final uri = Uri.tryParse(actionUrl);
    if (uri == null ||
        uri.scheme != 'orpheus' ||
        uri.host.toLowerCase() != 'motivationad' ||
        uri.path != '/show' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      return null;
    }
    const fields = {
      'adPosition',
      'resourceId',
      'source',
      'ext',
      'isNeedGetRights',
      'isShowEndToast',
      'showRightsEndDialog',
      'isNeedResume',
      'isNeedMute',
      'backupUrl',
    };
    final all = uri.queryParametersAll;
    // Reject ambiguous versions of the known context fields. Unrelated URL
    // tracking fields never enter the qualification payload.
    if (fields.any((key) => (all[key]?.length ?? 0) > 1)) return null;
    final query = uri.queryParameters;
    final position = _integer(query['adPosition']);
    final resource = query['resourceId'];
    if (position == null || resource == null) return null;

    Map<String, dynamic> ext = {};
    final encodedExt = query['ext'];
    if (encodedExt != null && encodedExt.isNotEmpty) {
      try {
        final decoded = jsonDecode(encodedExt);
        if (decoded is! Map<String, dynamic>) return null;
        ext = Map.of(decoded);
      } on FormatException {
        // A malformed server context is not repaired by making up metadata.
        return null;
      }
    }
    final rawReport = ext['bizReportInfo'];
    final report = switch (rawReport) {
      null => '',
      String value => value,
      Map() || List() => jsonEncode(rawReport),
      _ => '$rawReport',
    };
    // The native route mirrors bizReportInfo in ext and at Bundle top level.
    ext['bizReportInfo'] = report;
    bool flag(String key) => query[key]?.toLowerCase() == 'true';
    return NeteaseFreeListenEntry._({
      'adPosition': position,
      'resourceId': resource,
      'ext': jsonEncode(_nativeJsonValue(ext)),
      'isNeedGetRights': flag('isNeedGetRights'),
      'isShowEndToast': flag('isShowEndToast'),
      'showRightsEndDialog': flag('showRightsEndDialog'),
      // Zero is the inspected route's default. It does not establish a valid
      // reward source; a later gain still needs a real positive issued source.
      'source': _integer(query['source']) ?? 0,
      'isNeedResume': flag('isNeedResume'),
      'isNeedMute': flag('isNeedMute'),
      'backupUrl': query['backupUrl'],
      'bizReportInfo': report,
    });
  }
}
