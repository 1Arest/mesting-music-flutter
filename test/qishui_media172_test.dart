import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playback_media.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'qishui_protocol_test.dart' show sodaRecording;
import 'qishui_signed_api167_test.dart' show account, FixtureSigner, reply;
import 'netease_v116_recovery_test.dart' show mp3Response;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(MusicNetworkDiagnostics.shared.clear);
  for (final httpStatus in [false, true]) {
    test(
      '${httpStatus ? 'HTTP' : 'business'} 301 is distinguishable without leaking response data',
      () async {
        var requests = 0;
        final api = QishuiApi(
          MockClient((r) async {
            requests++;
            if (httpStatus) {
              return http.Response(
                '{"fixture_private":"secret"}',
                301,
                headers: {'location': 'https://other.example/private-query'},
              );
            }
            return reply({
              'status_code': 301,
              'message': 'fixture-private-body',
            });
          }),
          signer: FixtureSigner(),
        )..configure(account());
        addTearDown(api.dispose);
        await expectLater(
          QishuiRepository(api).media('fixture'),
          throwsA(
            isA<QishuiException>().having(
              (e) => e.code,
              'source code',
              httpStatus ? 'http_301' : '301',
            ),
          ),
        );
        expect(requests, 1);
        final rows = MusicNetworkDiagnostics.shared.rows;
        expect(
          rows.any(
            (r) =>
                r['outcome'] == (httpStatus ? 'http' : 'business') &&
                r['status'] == 301,
          ),
          true,
        );
        expect(
          MusicNetworkDiagnostics.shared.export(),
          isNot(contains('fixture-private-body')),
        );
      },
    );
  }
  test(
    'JSON-string player container reaches the actual player-info loader',
    () async {
      final api = QishuiApi(
        MockClient((r) async {
          if (r.url.host == 'api.qishui.com') {
            return reply({
              'track_player': jsonEncode({
                'url_player_info':
                    'https://vod-luna.douyin.com/player?fixture=secret',
              }),
            });
          }
          expect(r.headers['cookie'], isNull);
          if (r.url.host == 'vod-luna.douyin.com') {
            return reply({
              'Result': {
                'Data': {
                  'PlayInfoList': [
                    {
                      'MainPlayUrl': 'https://audio.example/full.mp3',
                      'Duration': 230,
                      'Bitrate': 128000,
                      'Format': 'mp3',
                    },
                  ],
                },
              },
            });
          }
          return mp3Response(230);
        }),
        signer: FixtureSigner(),
      )..configure(account());
      addTearDown(api.dispose);
      final result = await QishuiRepository(api).resolve(sodaRecording());
      expect(result.isPreview, false);
      expect(result.audioAsset, 'https://audio.example/full.mp3');
      expect(
        MusicNetworkDiagnostics.shared.exportCompact(),
        isNot(contains('fixture=secret')),
      );
    },
  );
  test(
    'HTTP 200 catalog-only reply stays a media failure, never a decoding failure',
    () async {
      final api = QishuiApi(
        MockClient(
          (_) async => reply({
            'track_info': {'duration': 230000},
            'lyric': {'content': 'fixture'},
          }),
        ),
        signer: FixtureSigner(),
      )..configure(account());
      addTearDown(api.dispose);
      await expectLater(
        QishuiRepository(api).resolve(sodaRecording()),
        throwsA(
          isA<QishuiException>().having(
            (e) => e.kind,
            'stage',
            QishuiFailureKind.format,
          ),
        ),
      );
      final rows = MusicNetworkDiagnostics.shared.rows;
      expect(
        rows.any(
          (r) => r['phase'] == 'playerInfoRead' && r['playerInfoUrls'] == 0,
        ),
        true,
      );
      expect(
        rows.any(
          (r) => r['phase'] == 'mediaModelParse' && r['streamCandidates'] == 0,
        ),
        true,
      );
      expect(rows.any((r) => r['phase'] == 'audioDecode'), false);
      expect(
        qishuiPlayerInfoUris({
          'cover': 'https://images.example/picture',
          'lyric': 'not-json',
        }),
        isEmpty,
      );
    },
  );
}
