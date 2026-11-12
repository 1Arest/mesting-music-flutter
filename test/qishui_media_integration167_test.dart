import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_official_audio_cache.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'qishui_signed_api167_test.dart' show FixtureSigner, account, reply;

class VerifiedCacheFixture extends QishuiOfficialAudioCache {
  VerifiedCacheFixture() : super(MockClient((_) async => reply({})));
  int calls = 0;
  @override
  Future<String> resolve(
    QishuiMedia media, {
    required String ownerKey,
    required String trackId,
    required Future<void> abort,
    required bool Function() current,
  }) async {
    expect(current(), true);
    expect(media.playAuth, 'ephemeral-auth167');
    calls++;
    return '/private/qishui_official_audio/${'a' * 32}.m4a';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const track = Track(
    id: 'qishui_media167',
    platformSongId: 'media167',
    title: 'Fixture',
    artist: 'Artist',
    album: '',
    duration: Duration(seconds: 200),
    audioAsset: 'mesting-platform://qishui/media167',
    coverAsset: '',
    lyricsAsset: '',
    source: TrackSource.qishui,
  );
  final model = {
    'track_player': {
      'video_model': {
        'video_duration': 200,
        'video_list': [
          {
            'main_url': base64Encode(
              utf8.encode('https://audio.example.test/recording'),
            ),
            'video_meta': {
              'definition': 'highest',
              'bitrate': 260000,
              'format': 'm4a',
              'size': 6500000,
            },
            'encrypt_info': {
              'encrypt': true,
              'spade_a': 'ephemeral-auth167',
              'encryption_method': 'cenc-aes-ctr',
            },
          },
        ],
      },
    },
  };
  for (final permission in ['accepted', 'quota', 'missing']) {
    test(
      'official encrypted download $permission uses exact quality and no quota write',
      () async {
        final paths = <String>[];
        final cache = VerifiedCacheFixture();
        final api = QishuiApi(
          MockClient((r) async {
            paths.add(r.url.path);
            if (r.url.path.endsWith('check_download')) {
              expect(jsonDecode(r.body), {
                'tracks': [
                  {'track_id': 'media167', 'quality': 4},
                ],
              });
              return reply({
                'track_download_info_list': permission == 'missing'
                    ? []
                    : [
                        {
                          'track_id': 'media167',
                          'quality': 4,
                          'need_download_quota': permission == 'quota',
                        },
                      ],
              });
            }
            expect(r.url.path, '/luna/pc/track_v2');
            return reply(model);
          }),
          signer: FixtureSigner(),
        )..configure(account());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(QishuiOfficialAudioCache.channelDefault, (
              call,
            ) async {
              expect(call.method, 'inspect');
              return {
                'durationUs': 200000000,
                'format': 'm4a',
                'bitrate': 260000,
                'bytes': 6500000,
              };
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                QishuiOfficialAudioCache.channelDefault,
                null,
              ),
        );
        final resolving = QishuiRepository(
          api,
          audioCache: cache,
        ).resolve(track, download: true);
        if (permission == 'accepted') {
          final result = await resolving;
          expect(Uri.parse(result.audioAsset).scheme, 'file');
          expect(result.audioOrigin?.adapter, AudioOrigin.qishui);
          expect(result.toString(), isNot(contains('ephemeral-auth167')));
          expect(cache.calls, 1);
        } else {
          await expectLater(
            resolving,
            throwsA(
              isA<QishuiException>().having(
                (e) => e.kind,
                'rights',
                QishuiFailureKind.entitlement,
              ),
            ),
          );
          expect(cache.calls, 0);
        }
        expect(paths, [
          '/luna/pc/track_v2',
          '/luna/commerce/v2/check_download',
        ]);
      },
    );
  }
  test(
    'decoded metadata cannot upgrade a short official stream to a full recording',
    () async {
      final cache = VerifiedCacheFixture();
      final api = QishuiApi(
        MockClient((r) async => reply(model)),
        signer: FixtureSigner(),
      )..configure(account());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            QishuiOfficialAudioCache.channelDefault,
            (call) async => {
              'durationUs': 60000000,
              'format': 'm4a',
              'bitrate': 260000,
              'bytes': 1950000,
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              QishuiOfficialAudioCache.channelDefault,
              null,
            ),
      );
      await expectLater(
        QishuiRepository(api, audioCache: cache).resolve(track),
        throwsA(
          isA<QishuiException>().having(
            (e) => e.kind,
            'format',
            QishuiFailureKind.format,
          ),
        ),
      );
    },
  );
}
