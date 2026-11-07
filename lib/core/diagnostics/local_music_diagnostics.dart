import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Explicit local diagnostic builds only. Never pass a whole DTO, exception
/// message, URL, account identifier, Cookie, or message body to this boundary.
/// Release builds compile the logging/export branch away by default.
class LocalMusicDiagnostics {
  static const enabled = bool.fromEnvironment('MESTING_LOCAL_DIAGNOSTICS');
  static final _emitted = <String, int>{};

  static void record(String event, Map<String, Object?> fields) {
    if (!enabled) return;
    final count = _emitted[event] ?? 0;
    if (count >= 48) return;
    _emitted[event] = count + 1;
    debugPrint('MESTING_LOCAL ${jsonEncode({'event': event, ...fields})}');
  }

  static Map<String, Object?> artwork(String value) {
    final uri = Uri.tryParse(value);
    return {
      'empty': value.isEmpty,
      'scheme': uri?.scheme,
      'host': uri?.host.endsWith('.music.126.net') == true
          ? uri!.host
          : 'other',
      'thumbnail': uri?.queryParameters['param'],
    };
  }

  /// Copies timing-only data to this app's external files folder so ADB can
  /// collect it without account access, root, clipboard reads, or force-stop.
  static Future<void> exportTiming(Map<String, Object> report) async {
    if (!enabled || !Platform.isAndroid) return;
    try {
      final root = await getExternalStorageDirectory();
      if (root == null) return;
      await File(
        '${root.path}/mesting-frame-diagnostics.json',
      ).writeAsString(jsonEncode(report), flush: true);
      record('timing.exported', {'frames': (report['samples'] as List).length});
    } catch (error) {
      record('timing.export_failed', {'type': error.runtimeType.toString()});
    }
  }
}
