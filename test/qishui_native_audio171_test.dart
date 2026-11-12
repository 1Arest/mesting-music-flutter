import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_native_audio_failure.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_official_audio_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final diagnostics = MusicNetworkDiagnostics.shared;
  const channel = MethodChannel('test/qishui171');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  setUp(() async {
    diagnostics.clear();
    directory = await Directory.systemTemp.createTemp('qishui171-');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
    diagnostics.clear();
  });

  for (final step in MusicNativeAudioStep.values) {
    test(
      'native ${step.name} failure survives production cache orchestration',
      () async {
        final reason = switch (step) {
          MusicNativeAudioStep.cachePath =>
            MusicNativeAudioReason.cachePathInvalid,
          MusicNativeAudioStep.sourceRead =>
            MusicNativeAudioReason.sourceReadFailed,
          MusicNativeAudioStep.authorization =>
            MusicNativeAudioReason.authorizationInvalid,
          MusicNativeAudioStep.containerParse =>
            MusicNativeAudioReason.sampleTableInvalid,
          MusicNativeAudioStep.sampleDecrypt =>
            MusicNativeAudioReason.sampleDecryptFailed,
          MusicNativeAudioStep.cacheWrite =>
            MusicNativeAudioReason.cacheWriteFailed,
          MusicNativeAudioStep.metadataRead =>
            MusicNativeAudioReason.metadataUnsupported,
        };
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'prepare' &&
              step == MusicNativeAudioStep.metadataRead) {
            final args = call.arguments as Map;
            await File(args['output'] as String).writeAsBytes([1, 2, 3]);
            return {'path': args['output']};
          }
          throw PlatformException(
            code: 'format',
            message: 'private path and auth',
            details: {
              'step': step.name,
              'reason': reason.name,
              'family': step == MusicNativeAudioStep.sampleDecrypt
                  ? 'decrypt'
                  : 'format',
              'untrusted': 'https://private/?PlayAuth=secret',
            },
          );
        });
        final cache = QishuiOfficialAudioCache(
          MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
          channel: channel,
          temporaryDirectory: () async => directory,
        );
        await expectLater(
          cache.resolve(
            const QishuiMedia(
              'https://audio.example.test/file',
              Duration(seconds: 200),
              128000,
              true,
              playAuth: 'synthetic',
            ),
            ownerKey: 'synthetic-owner',
            trackId: 'synthetic-track',
            abort: Completer<void>().future,
            current: () => true,
          ),
          throwsA(
            isA<QishuiException>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('private path')),
            ),
          ),
        );
        final last = diagnostics.rows.last;
        expect(last['nativeStep'], step.name);
        expect(last['nativeReason'], reason.name);
        expect(
          last['phase'],
          step == MusicNativeAudioStep.metadataRead
              ? 'audioVerify'
              : 'audioDecode',
        );
        expect(
          diagnostics.rows.any(
            (e) => e['phase'] == 'audioRead' && e['outcome'] == 'success',
          ),
          isTrue,
        );
        expect(diagnostics.export(), isNot(contains('PlayAuth')));
        expect(
          await directory.list(recursive: true).where((e) => e is File).isEmpty,
          isTrue,
        );
      },
    );
  }

  test('untrusted details and exception text become closed unknown fields', () {
    final result = QishuiNativeAudioFailure.from(
      PlatformException(
        code: 'secret',
        message: 'private',
        details: {'step': 'private', 'reason': 'secret', 'family': 'private'},
      ),
    );
    expect(result.step, isNull);
    expect(result.reason, MusicNativeAudioReason.unknown);
    expect(result.family, MusicFailureFamily.format);
    expect(result.message, isNot(contains('secret')));
  });
  test('old format-only bridge remains compatible with new Dart caller', () {
    final result = QishuiNativeAudioFailure.from(
      PlatformException(code: 'format'),
    );
    expect(result.reason, MusicNativeAudioReason.unknown);
  });
  test('missing bridge is separate from CDN connection failure', () {
    final result = QishuiNativeAudioFailure.from(
      MissingPluginException('private'),
    );
    expect(result.family, MusicFailureFamily.pluginUnavailable);
    expect(result.reason, MusicNativeAudioReason.bridgeUnavailable);
  });
}
