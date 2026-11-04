import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Large snapshots leave the UI isolate before UTF-8/JSON work begins. Workers
/// receive JSON values only, with no providers, clients or platform channels.
const backgroundJsonThreshold = 128 * 1024;

Object? _decodeBytes(Uint8List bytes) => jsonDecode(utf8.decode(bytes));
Object? _decodeText(String text) => jsonDecode(text);
String _encodeValue(Object? value) => jsonEncode(value);

Future<Object?> decodeJsonBytes(Uint8List bytes) =>
    bytes.length < backgroundJsonThreshold
    ? Future.value(_decodeBytes(bytes))
    : compute(_decodeBytes, bytes, debugLabel: 'music-json-decode');

Future<Object?> decodeJsonText(String text) =>
    text.length < backgroundJsonThreshold
    ? Future.value(_decodeText(text))
    : compute(_decodeText, text, debugLabel: 'music-snapshot-decode');

/// Stop estimation at a fixed budget: fully encoding on the UI isolate to
/// decide whether work is large would perform the very work being deferred.
bool largeJsonValue(Object? value) {
  var remaining = backgroundJsonThreshold;
  void visit(Object? current, int depth) {
    if (remaining <= 0) return;
    remaining -= 32;
    if (depth >= 128) {
      remaining = 0;
    } else if (current is String) {
      remaining -= current.length * 2;
    } else if (current is Map) {
      for (final entry in current.entries) {
        visit(entry.key, depth + 1);
        visit(entry.value, depth + 1);
        if (remaining <= 0) break;
      }
    } else if (current is List) {
      for (final item in current) {
        visit(item, depth + 1);
        if (remaining <= 0) break;
      }
    }
  }

  visit(value, 0);
  return remaining <= 0;
}

Future<String> encodeJsonValue(Object? value) => largeJsonValue(value)
    ? compute(_encodeValue, value, debugLabel: 'music-snapshot-encode')
    : Future.value(jsonEncode(value));

Future<Object?> copyJsonValueAsync(Object? value) => largeJsonValue(value)
    ? compute(copyJsonValue, value, debugLabel: 'music-snapshot-copy')
    : Future.value(copyJsonValue(value));

Uint8List _encodeBytes(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));
Future<Uint8List> encodeJsonBytes(Object? value) => largeJsonValue(value)
    ? compute(_encodeBytes, value, debugLabel: 'music-snapshot-bytes')
    : Future.value(_encodeBytes(value));

/// Cache readers keep independent nested containers without serializing the
/// same already-validated JSON twice on every read.
Object? copyJsonValue(Object? value) {
  if (value is List) return [for (final item in value) copyJsonValue(item)];
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: copyJsonValue(entry.value),
    };
  }
  return value;
}
