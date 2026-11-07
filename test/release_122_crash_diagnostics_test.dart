import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/diagnostics/app_exit_diagnostics.dart';
import 'package:mesting_music/core/diagnostics/native_crash_summary.dart';
import 'package:mesting_music/features/music_platform/netease/netease_fallback.dart';

Map<String, Object> trace() => {
  'status': 'available',
  'signal': {
    'number': 11,
    'name': 'SIGSEGV',
    'code': 1,
    'codeName': 'SEGV_MAPERR',
    'faultAddress': '0x1c',
    'private': 'SECRET',
  },
  'thread': {
    'name': '1.raster',
    'frames': [
      {
        'library': 'vulkan.adreno.so',
        'function': 'qglinternal::vkCmdBeginRenderPass',
        'relativePc': '0x1234',
        'buildId': 'abcdef0123',
        'path': '/data/SECRET',
      },
    ],
    'memory': 'SECRET',
  },
  'commandLine': 'SECRET',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'allowlisted native signal, crashing thread and frame survive the channel',
    () {
      final report = NativeCrashSummary.parse(trace())!.toJson();
      final text = jsonEncode(report);
      expect(text, contains('vkCmdBeginRenderPass'));
      expect(text, contains('vulkan.adreno.so'));
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('commandLine')));
    },
  );
  test(
    'malformed and private paths, thread labels, URLs and newlines are omitted',
    () {
      final report = NativeCrashSummary.parse({
        'status': 'available',
        'signal': {
          'number': double.nan,
          'codeName': 'SECRET\n',
          'faultAddress': 'https://SECRET',
        },
        'thread': {
          'name': '1.raster\n',
          'frames': [
            {
              'library': '/data/SECRET/lib.so',
              'function': 'https://SECRET',
              'buildId': 'SECRET',
              'relativePc': 'SECRET',
            },
            {'library': 'libflutter.so\n', 'function': 'SomeFunction\n'},
          ],
        },
      })!.toJson();
      expect(jsonEncode(report), isNot(contains('SECRET')));
      expect((report['thread']! as Map)['name'], 'other');
      expect((report['thread']! as Map)['frames'], isEmpty);
      expect(
        NativeCrashSummary.parse({'status': 'new-private-status'}),
        isNull,
      );
      expect(NativeCrashSummary.parse([]), isNull);
    },
  );
  test('frame count and unavailable payloads are bounded', () {
    final valid = trace();
    (valid['thread']! as Map)['frames'] = List.filled(1000, {
      'library': 'libflutter.so',
    });
    expect(
      (NativeCrashSummary.parse(valid)!.toJson()['thread']! as Map)['frames'],
      hasLength(24),
    );
    expect(
      NativeCrashSummary.parse({
        'status': 'unavailable',
        'private': 'SECRET',
      })!.toJson(),
      {'status': 'unavailable'},
    );
  });
  test(
    'old exit records remain valid; historical version and missing memory stay unknown',
    () {
      final parsed = AppExitRecord.parse({
        'reason': 'native_crash',
        'timestampMs': 1793361897696,
        'status': 11,
        'pssKiB': 0,
        'rssKiB': 0,
      });
      expect(parsed!.nativeTrace, isNull);
      expect(parsed.pssKiB, 0);
      expect(
        AppExitRecord.parse({
          'reason': 'anr',
          'timestampMs': 1,
          'nativeTrace': trace(),
        })!.nativeTrace,
        isNull,
      );
    },
  );
  test(
    'copied diagnostics includes sanitized system trace without inventing its version',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            AppExitDiagnostics.channel,
            (call) async => [
              {
                'reason': 'native_crash',
                'timestampMs': 1793361897696,
                'status': 11,
                'pssKiB': 0,
                'rssKiB': 0,
                'nativeTrace': trace(),
              },
            ],
          );
      final diagnostics = NeteaseFallbackDiagnostics();
      try {
        await diagnostics.includeExitHistory();
        await diagnostics.includeExitHistory();
        final rows = jsonDecode(diagnostics.json) as List;
        expect(rows, hasLength(1));
        expect(rows.single['versionUnknown'], isTrue);
        expect(rows.single['nativeTrace']['status'], 'available');
        expect(diagnostics.json, isNot(contains('SECRET')));
      } finally {
        diagnostics.dispose();
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AppExitDiagnostics.channel, null);
      }
    },
  );
}
