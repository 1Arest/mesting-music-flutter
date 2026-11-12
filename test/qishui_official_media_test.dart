import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_official_audio_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'official nested video_meta and encrypt_info retain exact stream facts',
    () {
      final result = QishuiMedia.parse({
        'track_player': {
          'video_model': jsonEncode(
            jsonEncode({
              'video_duration': 60.25,
              'video_list': [
                {
                  'main_url': 'https://cdn.example.test/audio',
                  'backup_url': 'https://backup.example.test/audio',
                  'video_meta': {
                    'quality': 'medium',
                    'vtype': 'm4a',
                    'size': 513038,
                    'bitrate': 68405,
                  },
                  'encrypt_info': {
                    'encrypt': true,
                    'spade_a': 'synthetic-envelope',
                    'encryption_method': 'cenc-aes-ctr',
                  },
                },
              ],
            }),
          ),
        },
      });
      expect(result.length, 2);
      final media = result.first;
      expect(media.duration, const Duration(milliseconds: 60250));
      expect(media.bitrate, 68405);
      expect(media.fileSize, 513038);
      expect(media.qualityName, 'medium');
      expect(media.format, 'm4a');
      expect(media.encrypted, true);
      expect(media.canDecodeAuthorized, true);
    },
  );

  test(
    'PascalCase player info duration and authorization never become catalog milliseconds',
    () {
      final result = QishuiMedia.parse({
        'track': {'duration': 230000},
        'Result': {
          'Data': {
            'PlayInfoList': [
              {
                'MainPlayUrl': 'https://cdn.example.test/audio',
                'Duration': 30.125,
                'PlayAuth': 'synthetic-envelope',
                'Bitrate': 128000,
                'Size': 400000,
                'Format': 'm4a',
                'Quality': 'higher',
                'EncryptionMethod': 'cenc-aes-ctr',
              },
            ],
          },
        },
      });
      expect(result.single.duration, const Duration(milliseconds: 30125));
      expect(result.single.playAuth, 'synthetic-envelope');
      expect(result.single.qualityName, 'higher');
      expect(result.single.encrypted, true);
    },
  );

  test(
    'unknown encryption cannot pass as clear or enter authorized decoder',
    () {
      final item = QishuiMedia.parse({
        'MainPlayUrl': 'https://cdn.example.test/audio',
        'Duration': 200,
        'PlayAuth': 'synthetic-envelope',
        'EncryptionMethod': 'cbcs',
      }).single;
      expect(item.encrypted, true);
      expect(item.canDecodeAuthorized, false);
    },
  );

  test('unknown encrypted data without authorization stays blocked', () {
    final item = QishuiMedia.parse({
      'main_url': 'https://cdn.example.test/audio',
      'duration': 200,
      'encrypt_info': {'encrypt': true},
    }).single;
    expect(item.encrypted, true);
    expect(item.canDecodeAuthorized, false);
  });

  test(
    'track_info metadata parses without trusting surrounding player duration',
    () {
      final tracks = sodaTracks({
        'track_info': {
          'id': 'fixture',
          'name': 'Fixture',
          'duration': 234000,
          'artists': [
            {'name': 'Artist'},
          ],
        },
        'track_player': {
          'video_model': {'video_duration': 30},
        },
      });
      expect(tracks.single.duration, const Duration(seconds: 234));
    },
  );

  late Directory temp;
  const channel = MethodChannel('fixture/qishui_official_audio');
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qishui-cache-fixture-');
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });
  const media = QishuiMedia(
    'https://cdn.example.test/audio',
    Duration(seconds: 230),
    128000,
    false,
    fileSize: 4,
  );

  test(
    'private cache downloads anonymously and verifies local duration before return',
    () async {
      final client = MockClient((request) async {
        expect(
          request.headers.keys.where(
            (k) => {
              'cookie',
              'authorization',
              'x-tt-token',
              'x-helios',
              'x-medusa',
            }.contains(k.toLowerCase()),
          ),
          isEmpty,
        );
        expect(request.followRedirects, false);
        return http.Response.bytes(
          [1, 2, 3, 4],
          200,
          headers: {'content-length': '4', 'content-type': 'audio/mp4'},
        );
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, Object?>.from(call.arguments as Map);
            if (call.method == 'prepare') {
              final output = File(args['output'] as String);
              await File(args['source'] as String).copy(output.path);
              return {'path': output.path};
            }
            if (call.method == 'inspect') {
              return {
                'durationUs': 230000000,
                'format': 'm4a',
                'bytes': 4,
                'bitrate': 128000,
              };
            }
            return null;
          });
      final cache = QishuiOfficialAudioCache(
        client,
        channel: channel,
        temporaryDirectory: () async => temp,
      );
      final path = await cache.resolve(
        media,
        ownerKey: 'fixture-owner',
        trackId: 'fixture',
        abort: Completer<void>().future,
        current: () => true,
      );
      expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
      expect(
        (await File(path).parent.list().toList()).length,
        1,
        reason: 'encrypted/source material is removed',
      );
    },
  );

  test('partial official body is rejected before decoder dispatch', () async {
    var called = false;
    final cache = QishuiOfficialAudioCache(
      MockClient((_) async => http.Response.bytes([1, 2], 200)),
      channel: channel,
      temporaryDirectory: () async => temp,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          called = true;
          return null;
        });
    await expectLater(
      cache.resolve(
        media,
        ownerKey: 'owner',
        trackId: 'fixture',
        abort: Completer<void>().future,
        current: () => true,
      ),
      throwsA(isA<QishuiException>()),
    );
    expect(called, false);
    expect(
      await Directory('${temp.path}/qishui_official_audio').list().toList(),
      isEmpty,
    );
  });

  test(
    'local short-preview duration rejects and removes unpublished cache',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, Object?>.from(call.arguments as Map);
            if (call.method == 'prepare') {
              await File(
                args['source'] as String,
              ).copy(args['output'] as String);
              return {'path': args['output']};
            }
            return {
              'durationUs': 30000000,
              'format': 'm4a',
              'bytes': 4,
              'bitrate': 128000,
            };
          });
      final cache = QishuiOfficialAudioCache(
        MockClient((_) async => http.Response.bytes([1, 2, 3, 4], 200)),
        channel: channel,
        temporaryDirectory: () async => temp,
      );
      await expectLater(
        cache.resolve(
          media,
          ownerKey: 'owner',
          trackId: 'fixture',
          abort: Completer<void>().future,
          current: () => true,
        ),
        throwsA(isA<QishuiException>()),
      );
      expect(
        await Directory('${temp.path}/qishui_official_audio').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'account change after native preparation rejects delayed result',
    () async {
      var current = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, Object?>.from(call.arguments as Map);
            if (call.method == 'prepare') {
              await File(
                args['source'] as String,
              ).copy(args['output'] as String);
              current = false;
              return {'path': args['output']};
            }
            return null;
          });
      final cache = QishuiOfficialAudioCache(
        MockClient((_) async => http.Response.bytes([1, 2, 3, 4], 200)),
        channel: channel,
        temporaryDirectory: () async => temp,
      );
      await expectLater(
        cache.resolve(
          media,
          ownerKey: 'owner',
          trackId: 'fixture',
          abort: Completer<void>().future,
          current: () => current,
        ),
        throwsA(
          predicate(
            (e) =>
                e is QishuiException && e.kind == QishuiFailureKind.cancelled,
          ),
        ),
      );
      expect(
        await Directory('${temp.path}/qishui_official_audio').list().toList(),
        isEmpty,
      );
    },
  );
}
