import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/network/music_diagnostic_clipboard.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  test(
    'compact snapshot retains latest failure after unrelated success traffic',
    () {
      final diagnostics = MusicNetworkDiagnostics();
      for (final phase in [
        MusicDiagnosticPhase.playerInfoRead,
        MusicDiagnosticPhase.mediaModelParse,
        MusicDiagnosticPhase.mediaSelection,
        MusicDiagnosticPhase.audioRead,
        MusicDiagnosticPhase.audioDecode,
      ]) {
        diagnostics.record(
          platform: 'qishui',
          operation: MusicNetworkOperation.audio,
          outcome: phase == MusicDiagnosticPhase.audioDecode
              ? MusicNetworkOutcome.format
              : MusicNetworkOutcome.success,
          phase: phase,
          nativeStep: phase == MusicDiagnosticPhase.audioDecode
              ? MusicNativeAudioStep.cachePath
              : null,
          nativeReason: phase == MusicDiagnosticPhase.audioDecode
              ? MusicNativeAudioReason.cachePathInvalid
              : null,
        );
      }
      for (var i = 0; i < 60; i++) {
        diagnostics.record(
          platform: 'netease',
          operation: MusicNetworkOperation.read,
          outcome: MusicNetworkOutcome.success,
        );
      }
      final text = diagnostics.exportCompact();
      final report = jsonDecode(text) as Map;
      expect(text.length, lessThanOrEqualTo(4096));
      expect(report['complete'], isTrue);
      expect(report['scope'], 'latestFailure');
      expect(report['eventCount'], 5);
      final rows = report['events'] as List;
      expect(rows.every((e) => e['platform'] == 'qishui'), isTrue);
      expect(rows.last['nativeReason'], 'cachePathInvalid');
      final frozen = text;
      diagnostics.clear();
      expect(text, frozen);
      expect((jsonDecode(text)['events'] as List).length, 5);
    },
  );
  test(
    'maximum populated events stay bounded with intact JSON and last failure',
    () {
      final diagnostics = MusicNetworkDiagnostics();
      for (var i = 0; i < 100; i++) {
        diagnostics.record(
          platform: 'qishui',
          operation: MusicNetworkOperation.playbackUrl,
          outcome: i == 99
              ? MusicNetworkOutcome.format
              : MusicNetworkOutcome.success,
          phase: MusicDiagnosticPhase.audioDecode,
          family: MusicFailureFamily.decrypt,
          nativeStep: MusicNativeAudioStep.sampleDecrypt,
          nativeReason: MusicNativeAudioReason.sampleDecryptFailed,
          elapsedMs: 9999999,
          attempt: 99,
          status: 999999,
          playerInfoUrls: 9999999,
          streamCandidates: 9999999,
          decodableStreams: 9999999,
        );
      }
      expect(diagnostics.rows.length, 80);
      final text = diagnostics.exportCompact();
      final report = jsonDecode(text) as Map;
      expect(text.length, lessThanOrEqualTo(4096));
      final events = report['events'] as List;
      expect(report['eventCount'], events.length);
      expect(events.last['outcome'], 'format');
      expect(events.length, lessThanOrEqualTo(10));
      expect(jsonDecode(diagnostics.export())['events'].length, 80);
    },
  );
  test('empty and success-only exports remain complete', () {
    final diagnostics = MusicNetworkDiagnostics();
    expect(jsonDecode(diagnostics.exportCompact())['events'], isEmpty);
    diagnostics.record(
      platform: 'kugou',
      operation: MusicNetworkOperation.read,
      outcome: MusicNetworkOutcome.success,
    );
    expect(jsonDecode(diagnostics.exportCompact())['scope'], 'recent');
  });
  for (final response in [
    'matching',
    'garbled',
    'missing',
    'writeError',
    'readError',
  ]) {
    test(
      'clipboard $response reports only verified readback as success',
      () async {
        String? copied;
        var writes = 0;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            writes++;
            if (response == 'writeError') {
              throw PlatformException(code: 'unavailable');
            }
            copied = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') {
            if (response == 'readError') {
              throw PlatformException(code: 'unavailable');
            }
            if (response == 'missing') return null;
            return {'text': response == 'garbled' ? '{broken copy' : copied};
          }
          return null;
        });
        final result = await MusicDiagnosticClipboard.copy('{"complete":true}');
        expect(writes, 1);
        expect(result, switch (response) {
          'matching' => MusicDiagnosticCopyResult.verified,
          'garbled' => MusicDiagnosticCopyResult.mismatch,
          _ => MusicDiagnosticCopyResult.unavailable,
        });
      },
    );
  }
}
