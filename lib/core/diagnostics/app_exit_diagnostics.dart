import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'native_crash_summary.dart';

/// Only stable, non-identifying fields from Android's own-process exit history
/// can enter a copyable report. Never retain arbitrary native response fields.
class AppExitRecord {
  const AppExitRecord(
    this.reason,
    this.timestampMs,
    this.status,
    this.pssKiB,
    this.rssKiB, {
    this.nativeTrace,
  });
  final String reason;
  final int timestampMs, status, pssKiB, rssKiB;
  final NativeCrashSummary? nativeTrace;
  static const reasons = {
    'java_crash',
    'native_crash',
    'anr',
    'low_memory',
    'signal',
    'resource_limit',
  };
  static AppExitRecord? parse(Object? value) {
    if (value is! Map || !reasons.contains(value['reason'])) return null;
    int number(String key) =>
        value[key] is num ? (value[key] as num).toInt() : 0;
    final time = number('timestampMs');
    if (time <= 0 || time > 8640000000000000) return null;
    return AppExitRecord(
      value['reason'] as String,
      time,
      number('status'),
      number('pssKiB').clamp(0, 1 << 40),
      number('rssKiB').clamp(0, 1 << 40),
      nativeTrace: value['reason'] == 'native_crash'
          ? NativeCrashSummary.parse(value['nativeTrace'])
          : null,
    );
  }
}

class AppExitDiagnostics {
  static const channel = MethodChannel('com.mesting.music/system_media');
  static Future<List<AppExitRecord>> recent() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    try {
      final rows = await channel
          .invokeListMethod<Object?>('getRecentAppExits')
          .timeout(const Duration(seconds: 6));
      return rows
              ?.map(AppExitRecord.parse)
              .whereType<AppExitRecord>()
              .take(5)
              .toList() ??
          const [];
    } on Exception {
      // Diagnostics are optional on older devices and missing native bridges.
      return const [];
    }
  }
}
