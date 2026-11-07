import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

class _JsUndefined {
  const _JsUndefined();
}

const jsUndefined = _JsUndefined();

/// Small value conversions used by the build-time protocol port. These are
/// ordinary native Dart functions, with no evaluation of scripts or URLs.
/// Keeping JS's defaults here avoids changing a request's wire contract when
/// the upstream used an empty string, zero, or a list as its input.
const jsResourceTypes = <String, String>{
  '0': 'R_SO_4_',
  '1': 'R_MV_5_',
  '2': 'A_PL_0_',
  '3': 'R_AL_3_',
  '4': 'A_DJ_1_',
  '5': 'R_VI_62_',
  '6': 'A_EV_2_',
  '7': 'A_DR_14_',
};
// Public client signature from the pinned upstream protocol configuration.
// This is not a credential or a per-user secret.
const appConf = <String, dynamic>{
  'clientSign':
      '18:C0:4D:B9:8F:FE@@@453832335F384641365F424635335F303030315F303031425F343434415F343643365F333638332@@@@@@6ff673ef74955b38bce2fa8562d95c976ed4758b1227c4e9ee345987cee17bc9',
};
bool jsTruthy(dynamic value) =>
    !identical(value, jsUndefined) &&
    value != null &&
    value != false &&
    value != '' &&
    !(value is num && (value == 0 || value.isNaN));
dynamic jsOr(dynamic value, dynamic Function() fallback) =>
    jsTruthy(value) ? value : fallback();
dynamic jsAnd(dynamic value, dynamic Function() next) =>
    jsTruthy(value) ? next() : value;
bool jsBoolean(dynamic value) =>
    value == true || value == 1 || value == 'true' || value == '1';
String jsType(dynamic value) => identical(value, jsUndefined)
    ? 'undefined'
    : value is String
    ? 'string'
    : value is num
    ? 'number'
    : value is bool
    ? 'boolean'
    : 'object';
String jsString(dynamic value) => identical(value, jsUndefined)
    ? 'undefined'
    : value == null
    ? 'null'
    : value is List
    ? value
          .map((e) => e == null || identical(e, jsUndefined) ? '' : jsString(e))
          .join(',')
    : '$value';
num jsNumber(dynamic value) => identical(value, jsUndefined)
    ? double.nan
    : value == null
    ? 0
    : value == true
    ? 1
    : value == false
    ? 0
    : value is num
    ? value
    : value == ''
    ? 0
    : num.tryParse('$value') ?? double.nan;
bool jsStrictEqual(dynamic a, dynamic b) =>
    (a is num && b is num || a.runtimeType == b.runtimeType) && a == b;
bool jsEqual(dynamic a, dynamic b) =>
    (a == null || identical(a, jsUndefined)) &&
        (b == null || identical(b, jsUndefined)) ||
    (a is String && b is String
        ? a == b
        : a == b || (a != null && b != null && jsNumber(a) == jsNumber(b)));
dynamic jsAdd(dynamic a, dynamic b) => a is String || b is String
    ? jsString(a) + jsString(b)
    : jsNumber(a) + jsNumber(b);
Map<String, dynamic> jsMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<dynamic> jsList(dynamic value) => value is List ? value : <dynamic>[];
dynamic jsGet(dynamic value, dynamic key) {
  if (value is Map) {
    return value.containsKey(jsString(key))
        ? value[jsString(key)]
        : value.containsKey(key)
        ? value[key]
        : jsUndefined;
  }
  if (key == 'length' && value is List) return value.length;
  if (key == 'length' && value is String) return value.length;
  final index = int.tryParse('$key');
  if (value is List && index != null && index >= 0 && index < value.length) {
    return value[index];
  }
  if (value is String && index != null && index >= 0 && index < value.length) {
    return value[index];
  }
  return jsUndefined;
}

dynamic jsClean(dynamic value) =>
    identical(value, jsUndefined) || value is num && !value.isFinite
    ? null
    : value is Map
    ? <String, dynamic>{
        for (final item in value.entries)
          if (!identical(item.value, jsUndefined))
            '${item.key}': jsClean(item.value),
      }
    : value is List
    ? value.map(jsClean).toList()
    : value is double && value == value.truncateToDouble()
    ? value.toInt()
    : value;
String jsJson(dynamic value) => jsonEncode(jsClean(value));
String jsMd5(dynamic value) =>
    md5.convert(utf8.encode(jsString(value))).toString();
dynamic jsMath(String method, List<dynamic> args) => switch (method) {
  'floor' => jsNumber(args.first).floor(),
  'ceil' => jsNumber(args.first).ceil(),
  'round' => jsNumber(args.first).round(),
  'random' => math.Random.secure().nextDouble(),
  'min' => args.map(jsNumber).reduce(math.min),
  'max' => args.map(jsNumber).reduce(math.max),
  _ => throw ArgumentError('Unsupported native numeric operation: $method'),
};
dynamic jsMethod(dynamic value, String method, List<dynamic> args) {
  final s = jsString(value);
  final first = args.isEmpty ? null : args.first;
  switch (method) {
    case 'toString':
      return s;
    case 'split':
      return s.split(first is RegExp ? first : jsString(first));
    case 'test':
      return (value as RegExp).hasMatch(jsString(first));
    case 'join':
      return jsList(
        value,
      ).map(jsString).join(args.isEmpty ? ',' : jsString(first));
    case 'toUpperCase':
      return s.toUpperCase();
    case 'toLowerCase':
      return s.toLowerCase();
    case 'trim':
      return s.trim();
    case 'charCodeAt':
      return s.isEmpty
          ? double.nan
          : s.codeUnitAt(args.isEmpty ? 0 : jsNumber(first).toInt());
    case 'includes':
      return value is List
          ? value.contains(first)
          : s.contains(jsString(first));
    case 'indexOf':
      return value is List ? value.indexOf(first) : s.indexOf(jsString(first));
    case 'replace':
      return first is RegExp
          ? s.replaceAll(first, jsString(args[1]))
          : s.replaceFirst(jsString(first), jsString(args[1]));
    case 'map':
      return jsList(
        value,
      ).map((v) => Function.apply(first as Function, [v])).toList();
    case 'filter':
      return jsList(
        value,
      ).where((v) => jsTruthy(Function.apply(first as Function, [v]))).toList();
    case 'concat':
      return [
        ...jsList(value),
        for (final a in args) ...a is List ? a : [a],
      ];
    case 'slice':
    case 'substring':
    case 'substr':
      final length = value is List ? value.length : s.length;
      var start = args.isEmpty ? 0 : jsNumber(first).toInt();
      if (start < 0) start = math.max(0, length + start);
      start = start.clamp(0, length);
      var end = args.length < 2
          ? length
          : method == 'substr'
          ? start + jsNumber(args[1]).toInt()
          : jsNumber(args[1]).toInt();
      if (end < 0) end = length + end;
      end = end.clamp(start, length);
      return value is List
          ? value.sublist(start, end)
          : s.substring(start, end);
    case 'getFullYear':
      return (value as DateTime).year;
    case 'getMonth':
      return (value as DateTime).month - 1;
    case 'getDate':
      return (value as DateTime).day;
    case 'getTime':
      return (value as DateTime).millisecondsSinceEpoch;
    case 'push':
      (value as List).addAll(args);
      return value.length;
    default:
      throw ArgumentError('Unsupported native value operation: $method');
  }
}
