import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/compat.dart';
import 'package:ring_download_sdk/src/p8p/lifecycle_trace.dart';

void main() {
  test('lifecycle exports bounded closed fields without wire identity', () {
    for (final code in P8PLifecycleCode.values) {
      final trace = P8PLifecycleEvent(
        code,
        alias: 'private-token',
        metrics: {
          'request_timeout_us': 8000000,
          'reserved_slots': 4,
          'slot_position': 1,
          'slot_phase': 3,
          'piece_ahead': 0,
          'body_bytes': 1048576,
          'body_expected_bytes': 1048576,
          'request_age_us': 1200000,
          'request_remaining_us': 6800000,
          'snapshot_sequence': 1,
          'owner_closed': 0,
          'request_id': 123,
          'generation': 123,
          'private-token': 123,
        },
      );
      expect(trace.alias, isNull);
      expect(() => trace.metrics.clear(), throwsUnsupportedError);
      final exported = AppUpgradeP2PDiagnostic(
        stage: 'transfer',
        code: code.code,
        attempt: trace.alias,
        metrics: trace.metrics,
      ).toJson();
      expect(exported['code'], code.code);
      expect((exported['metrics'] as Map).length, 11);
      final text = jsonEncode(exported);
      expect(text, isNot(contains('private')));
      expect(text, isNot(contains('request_id')));
      expect(text, isNot(contains('generation')));
      expect(utf8.encode('[AppUpgradeP2P] $text').length, lessThan(800));
    }
  });
  test('invalid sizes and unbounded values do not enter lifecycle records', () {
    final event = P8PLifecycleEvent(
      P8PLifecycleCode.rescueSlot,
      metrics: {
        'reserved_slots': 5,
        'slot_phase': 99,
        'slot_position': 9,
        'body_bytes': -1,
        'request_remaining_us': 1 << 60,
      },
    );
    expect(event.metrics, isEmpty);
    expect(
      () => observeP8PLifecycle((_) => throw StateError('logger'), event),
      returnsNormally,
    );
  });
}
