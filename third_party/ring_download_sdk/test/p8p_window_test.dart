import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/p8p/window.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_diagnostics.dart';

void main() {
  test('P8P diagnostics preserve closed names and bounded window metrics', () {
    final event = const AppUpgradeP2PDiagnostic(
      stage: 'p8p',
      code: 'window_changed',
      metrics: {'p8p_window': 3, 'private': 123},
    ).toJson();
    expect(event['stage'], 'p8p');
    expect(event['code'], 'window_changed');
    expect(event['metrics'], {'p8p_window': 3});
    final invalid = const AppUpgradeP2PDiagnostic(
      stage: 'p8p',
      code: 'window_changed',
      metrics: {'p8p_window': 99},
    ).toJson();
    expect(invalid['metrics'], isEmpty);
  });
  final vectors =
      jsonDecode(File('test/fixtures/p8p-window-v1.json').readAsStringSync())
          as Map;
  for (final item in vectors['requests'] as List) {
    final entry = item as Map;
    test('P8P shared request vector ${entry['name']}', () {
      int? parse() => P8PWindowProtocol.requested(
        (entry['payload'] as Map)['p8p'],
        enabled: entry['enabled'] as bool,
      );
      if (entry['error'] == true) {
        expect(parse, throwsFormatException);
      } else {
        expect(parse(), entry['expected']);
      }
    });
  }
  for (final item in vectors['capabilities'] as List) {
    final entry = item as Map;
    test('P8P shared capability vector ${entry['name']}', () {
      expect(P8PWindowProtocol.advertised(entry['value']), entry['expected']);
    });
  }
  test(
    'P8P grows only after sustained network pressure and keeps a hard bound',
    () {
      final policy = P8PWindowController(initial: 2);
      policy.observe(waitMicros: 20000, consumeMicros: 1000, readyPieces: 0);
      expect(policy.window, 2);
      policy.observe(waitMicros: 20000, consumeMicros: 1000, readyPieces: 0);
      expect(policy.window, 3);
      for (var i = 0; i < 100; i++) {
        policy.observe(waitMicros: 20000, consumeMicros: 1000, readyPieces: 0);
        expect(policy.window, inInclusiveRange(1, 4));
      }
      expect(policy.window, 4);
    },
  );
  test('P8P bounds ready buffers when the actual consumer is slow', () {
    final policy = P8PWindowController(initial: 4);
    for (var i = 0; i < 100; i++) {
      policy.observe(waitMicros: 1000, consumeMicros: 50000, readyPieces: 1);
    }
    expect(policy.window, 2);
  });
  test('P8P ignores timer noise and isolated pressure spikes', () {
    final policy = P8PWindowController(initial: 4);
    for (var i = 0; i < 100; i++) {
      policy.observe(waitMicros: 0, consumeMicros: 500, readyPieces: 1);
      policy.observe(waitMicros: 1000, consumeMicros: 50000, readyPieces: 1);
    }
    expect(policy.window, 4);
  });
  test('P8P rejects impossible samples before changing policy', () {
    final policy = P8PWindowController();
    expect(
      () => policy.observe(waitMicros: -1, consumeMicros: 0, readyPieces: 0),
      throwsArgumentError,
    );
    expect(
      () => policy.observe(waitMicros: 0, consumeMicros: 0, readyPieces: 5),
      throwsArgumentError,
    );
    expect(policy.window, 4);
    expect(() => P8PWindowController(initial: 5), throwsArgumentError);
  });
}
