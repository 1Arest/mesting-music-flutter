import 'dart:convert';

import '../../../../core/network/music_network_diagnostics.dart';
import '../../../../core/network/music_reward_diagnostic.dart';
import 'netease_ad_probe_context.dart';

/// These outcomes describe configuration reads, never ad completion or credit.
enum NeteaseAdProbeOutcome {
  configurationObserved('广告配置已返回，尚未验证展示或领奖'),
  noAds('本次广告位没有返回广告'),
  unsupportedLayout('广告返回结构暂不支持，请导出诊断'),
  invalidEntry('任务入口暂不支持，未读取广告'),
  invalidContext('任务上下文超出本地支持范围，未读取广告'),
  noSession('请先登录网易云账号'),
  businessRejected('平台未接受配置读取，请导出诊断'),
  requestFailed('配置读取未完成，请导出诊断'),
  receiptIncomplete('配置回执不完整，请导出诊断'),
  cancelled('本次读取已停止'),
  accountChanged('账号已变化，本次结果已丢弃'),
  dayChanged('日期已变化，请重新读取');

  const NeteaseAdProbeOutcome(this.label);
  final String label;
}

enum NeteaseAdProbeStage { entry, adData }

/// The report can retain only generated structural metadata. The raw response,
/// slot ID, URL, contextInfo and credentials never become fields of this class.
class NeteaseAdProbeReport {
  const NeteaseAdProbeReport._(
    this.outcome,
    this.stage,
    this.identity,
    this._details, {
    this.entry,
    this.requestInfo,
    this.httpStatus,
    this.businessCode,
    this.networkOutcome,
  });

  final NeteaseAdProbeOutcome outcome;
  final NeteaseAdProbeStage stage;
  final MusicRewardIdentity identity;
  final MusicRewardDiagnostic? entry;
  final NeteaseAdProbeRequestInfo? requestInfo;
  final int? httpStatus, businessCode;
  final MusicNetworkOutcome? networkOutcome;
  final Map<String, Object?> _details;

  factory NeteaseAdProbeReport.stopped({
    required NeteaseAdProbeOutcome outcome,
    required NeteaseAdProbeStage stage,
    required MusicRewardIdentity identity,
    MusicRewardDiagnostic? entry,
    NeteaseAdProbeRequestInfo? requestInfo,
    Map<String, dynamic>? response,
    int? httpStatus,
    int? businessCode,
    MusicNetworkOutcome? networkOutcome,
  }) => NeteaseAdProbeReport._(
    outcome,
    stage,
    identity,
    response == null ? const {} : {'receiptHints': _receiptHints(response)},
    entry: entry,
    requestInfo: requestInfo,
    httpStatus: _code(httpStatus, maximum: 599, minimum: 100),
    businessCode: _code(businessCode),
    networkOutcome: networkOutcome,
  );

  /// Only the same request's exact issued slot may be selected. Unknown slot
  /// names are never copied, and another slot is not substituted as a match.
  factory NeteaseAdProbeReport.observe({
    required Map<String, dynamic> response,
    required String requestedSlot,
    required MusicRewardIdentity identity,
    required MusicRewardDiagnostic entry,
    NeteaseAdProbeRequestInfo? requestInfo,
  }) {
    final ads = response['ads'];
    final present = ads is Map && ads.containsKey(requestedSlot);
    final ad = present ? ads[requestedSlot] : null;
    final empty = ads is Map && ads.isEmpty || ads is List && ads.isEmpty;
    final outcome = empty || present && ad == null
        ? NeteaseAdProbeOutcome.noAds
        : ad is Map && ad.isNotEmpty
        ? NeteaseAdProbeOutcome.configurationObserved
        : NeteaseAdProbeOutcome.unsupportedLayout;
    final shape = _AdShape();
    final selectedAd = shape.inspect(ad);
    final responseShape = shape.inspect(response);
    // Observe a single returned alias structurally, without accepting it as an
    // exact position match or changing the outcome. Multiple unknown positions
    // remain ambiguous. Neither their names nor any raw values are exported.
    final singleAlias = !present && ads is Map && ads.length == 1;
    final aliasProjector = _AdShape();
    final aliasShape = singleAlias
        ? aliasProjector.inspect(ads.values.first)
        : null;
    return NeteaseAdProbeReport._(
      outcome,
      NeteaseAdProbeStage.adData,
      identity,
      {
        'adsType': _AdShape.type(ads),
        'slotCount': ads is Map
            ? ads.length.clamp(0, 100)
            : ads is List
            ? ads.length.clamp(0, 100)
            : 0,
        'requestedSlotPresent': present,
        'singleSlotAliasObserved': singleAlias,
        'singleSlotAliasShape': ?aliasShape,
        'receiptHints': _receiptHints(response),
        'selectedAd': selectedAd,
        'responseShape': responseShape,
        'shapeLimited': shape.limited || aliasProjector.limited,
      },
      entry: entry,
      requestInfo: requestInfo,
      httpStatus: 200,
      businessCode: _code(response['code']),
    );
  }

  /// Project hints before the main shape budget is consumed by an ad. Server
  /// text stays opaque even if it is an object containing recognized ad keys.
  /// noRetry is observational only; every chain remains one attempt regardless.
  static Map<String, Object?> _receiptHints(Map<String, dynamic> response) => {
    for (final key in ['noRetry', 'message', 'mainMsg', 'image'])
      key: {
        'present': response.containsKey(key),
        'type': _AdShape.type(response[key]),
        if (key == 'noRetry' && (response[key] == 0 || response[key] == '0'))
          'value': 0,
        if (key == 'noRetry' && (response[key] == 1 || response[key] == '1'))
          'value': 1,
      },
  };

  static int? _code(Object? value, {int minimum = -999, int maximum = 999999}) {
    // Never stringify an arbitrary platform object into a diagnostic sink.
    final number = value is int
        ? value
        : value is String && RegExp(r'^-?[0-9]{1,6}$').hasMatch(value)
        ? int.tryParse(value)
        : null;
    return number != null && number >= minimum && number <= maximum
        ? number
        : null;
  }

  Map<String, Object?> _envelope({bool compact = false}) => {
    'schema': 2,
    'feature': 'neteaseAdConfiguration',
    'appVersion': '1.0.91',
    'appVersionCode': 112,
    'outcome': outcome.name,
    'stage': stage.name,
    'identity': identity.name,
    'transport': 'existingEapi',
    'readOnly': true,
    'adDisplayed': false,
    'trackingSubmitted': false,
    'rewardSubmitted': false,
    'complete': true,
    if (httpStatus != null) 'httpStatus': httpStatus,
    if (businessCode != null) 'businessCode': businessCode,
    if (networkOutcome != null) 'networkOutcome': networkOutcome!.name,
    if (entry != null) 'entry': entry!.toMap(),
    if (requestInfo != null) 'requestContext': requestInfo!.toMap(),
    // Keep the small receipt hints even when the compact report omits shapes.
    if (compact && _details.containsKey('receiptHints'))
      'receiptHints': _details['receiptHints'],
    if (!compact) 'configuration': _details,
    if (compact) 'configurationOmitted': true,
  };

  String get json => const JsonEncoder.withIndent('  ').convert(_envelope());

  /// Copy a closed JSON document; never cut a response in the middle of a
  /// string. The full bounded structural detail remains available as a file.
  String get compactJson {
    final full = jsonEncode(_envelope());
    return full.length <= 4096 ? full : jsonEncode(_envelope(compact: true));
  }
}

/// A closed-key, bounded projector. Unknown values and field names are not
/// exported, even when they look like URLs, errors, account IDs or JS snippets.
class _AdShape {
  int _remaining = 120;
  bool limited = false;
  static const _links = {
    'url',
    'imageUrl',
    'image',
    'videoUrl',
    'mp4Url',
    'playUrl',
    'actionUrl',
    'targetUrl',
    'redirectUrl',
    'landingPageUrl',
    'webviewUrl',
    'h5Url',
    'materialUrl',
    'link',
    'scheme',
  };
  static const _fields = {
    ..._links,
    'data',
    'body',
    'ads',
    'code',
    'message',
    'creativeType',
    'type',
    'video',
    'videoInfo',
    'videoAdInfo',
    'materials',
    'material',
    'adInfo',
    'adExtMap',
    'extJson',
    'generalRightsInfo',
    'listeningRightHintInfo',
    'contextInfo',
    'req_id',
    'reqId',
    'requestId',
    'adLogId',
    'rightsGainMethod',
    'rightsGainDuration',
    'rightsGainType',
    'extraRightsGainMethod',
    'extraRightsGainDuration',
    'nextRightsGainDuration',
    'rightsUpperLimit',
    'qualified',
    'rightsExtJson',
    'source',
    'duration',
    'width',
    'height',
    'lightInteraction',
    'lightInteractionInfo',
  };
  static const _jsonFields = {
    'adExtMap',
    'extJson',
    'generalRightsInfo',
    'listeningRightHintInfo',
  };
  static const _ruleNumbers = {
    'creativeType',
    'rightsGainMethod',
    'rightsGainType',
    'extraRightsGainMethod',
    'rightsGainDuration',
    'extraRightsGainDuration',
    'nextRightsGainDuration',
    'rightsUpperLimit',
    'duration',
    'width',
    'height',
  };

  static String type(Object? value) => switch (value) {
    null => 'missing',
    String() => 'text',
    bool() => 'boolean',
    num() => 'number',
    Map() => 'object',
    List() => 'list',
    _ => 'other',
  };

  Map<String, Object?> inspect(Object? value, [int depth = 0, String? field]) {
    final result = <String, Object?>{'type': type(value)};
    if (_remaining-- <= 0 || depth > 5) {
      limited = true;
      return {...result, 'limited': true};
    }
    if (field == 'message' || field == 'mainMsg' || field == 'noRetry') {
      return result;
    }
    if (_links.contains(field)) {
      result['linkKind'] = _linkKind(value);
      return result;
    }
    if (_ruleNumbers.contains(field)) {
      // Values are explicit rule/format fields only, with an upper bound.
      // No duration unit or eligibility is inferred from an integer alone.
      final number = value is int
          ? value
          : value is String && RegExp(r'^[0-9]{1,9}$').hasMatch(value)
          ? int.tryParse(value)
          : null;
      final maximum = switch (field) {
        'creativeType' || 'rightsUpperLimit' => 1000,
        'rightsGainMethod' || 'extraRightsGainMethod' => 6,
        'rightsGainType' => 100,
        'width' || 'height' => 16384,
        _ => 604800000,
      };
      if (number != null && number >= 0 && number <= maximum) {
        result['value'] = number;
      }
    }
    if (field == 'qualified') {
      if (const {true, 1, '1', 'true'}.contains(value)) result['value'] = true;
      if (const {false, 0, '0', 'false'}.contains(value)) {
        result['value'] = false;
      }
    }
    if (_jsonFields.contains(field) && value is String) {
      if (value.length > 65536) {
        limited = true;
        return {...result, 'jsonTooLong': true};
      }
      try {
        result['decoded'] = inspect(jsonDecode(value), depth + 1);
      } on FormatException {
        result['jsonMalformed'] = true;
      }
    } else if (value is Map) {
      result['fieldCount'] = value.length.clamp(0, 100);
      final fields = <String, Object?>{};
      // Inspect known keys only. Never iterate/serialize an arbitrary key.
      for (final key in _fields) {
        if (_remaining <= 0) {
          limited = true;
          break;
        }
        if (value.containsKey(key)) {
          fields[key] = inspect(value[key], depth + 1, key);
        }
      }
      result['fields'] = fields;
    } else if (value is List) {
      result['count'] = value.length.clamp(0, 100);
      if (value.isNotEmpty) result['first'] = inspect(value.first, depth + 1);
      if (value.length > 1) result['additionalItemsOmitted'] = true;
    }
    return result;
  }

  static String _linkKind(Object? value) {
    if (value == null || value == '') return 'missing';
    if (value is! String) return 'wrongType';
    if (value.length > 65536) return 'tooLong';
    try {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.userInfo.isNotEmpty) return 'malformed';
      return switch (uri.scheme.toLowerCase()) {
        'https' => 'https',
        'http' => 'http',
        'orpheus' => 'officialNative',
        '' => 'relative',
        _ => 'otherScheme',
      };
    } on FormatException {
      return 'malformed';
    }
  }
}
