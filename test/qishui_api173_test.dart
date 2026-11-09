import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_web_routes.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playback_recovery.dart';
import 'qishui_signed_api167_test.dart' show account, reply, FixtureSigner;
import 'qishui_search173_test.dart' show searchResponse173, searchTrack173;
import 'qishui_protocol_test.dart' show sodaRecording;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'add-to-playlist search shares the signed official JSON POST contract',
    () async {
      final signer = FixtureSigner();
      final api = QishuiApi(
        MockClient((r) async {
          expect(r.method, 'POST');
          expect(r.url.path, '/luna/search/track');
          expect(r.url.queryParameters['device_platform'], 'windows');
          expect(r.url.queryParameters['channel'], 'official');
          expect(r.headers['cookie'], isNotNull);
          expect(r.headers['x-helios'], 'fixture-helios');
          expect(r.body, signer.signedBody);
          return reply(
            searchResponse173(
              rows: [
                {
                  'entity': {
                    'track_wrapper': {'track': searchTrack173('123')},
                  },
                },
              ],
            ),
          );
        }),
        signer: signer,
      )..configure(account());
      addTearDown(api.dispose);
      final result = await QishuiRepository(api).search('测试');
      expect(result.single.platformSongId, '123');
      expect(signer.signedHeaders!.containsKey('cookie'), isFalse);
    },
  );
  test('artist PC translations are exact GET endpoints', () {
    for (final path in [
      '/luna/search/artist',
      '/luna/artists/123',
      '/luna/artists/123/tracks',
    ]) {
      final route = QishuiWebRoute.resolve(path, const {}, const {
        'cursor': '50',
      }, false);
      expect(route.get, true);
      expect(route.path, path.replaceFirst('/luna/', '/luna/pc/'));
      expect(route.query['cursor'], '50');
    }
    expect(
      () => QishuiWebRoute.resolve(
        '/luna/artists/../me',
        const {},
        const {},
        false,
      ),
      throwsA(isA<QishuiException>()),
    );
  });
  test('uploader is a precise common path, not a guessed PC prefix', () {
    final route = QishuiWebRoute.resolve(
      '/luna/video/uploader',
      const {},
      const {'upload_type': '0', 'scene': '0'},
      false,
    );
    expect(route.path, '/luna/video/uploader');
    expect(route.get, true);
    expect(
      () => QishuiWebRoute.resolve(
        '/luna/video/uploader',
        const {},
        const {},
        true,
      ),
      throwsA(isA<QishuiException>()),
    );
  });
  test('official global 403 is not confused with a CDN-only refusal', () {
    final song = sodaRecording();
    expect(
      qishuiCanSkipPlaybackFailure(
        song,
        const QishuiException(
          'fixture',
          kind: QishuiFailureKind.refused,
          code: 'http_403',
        ),
      ),
      false,
    );
    expect(
      qishuiCanSkipPlaybackFailure(
        song,
        const QishuiException(
          'fixture',
          kind: QishuiFailureKind.refused,
          code: 'media_http_403',
        ),
      ),
      true,
    );
  });
  test('cloud history mutation is distinct from GET read', () {
    final read = QishuiWebRoute.resolve(
      '/luna/me/recently-played-media',
      const {},
      const {},
      false,
    );
    final write = QishuiWebRoute.resolve(
      '/luna/me/recently-played-media',
      const {'media': []},
      const {},
      true,
    );
    expect(read.get, true);
    expect(write.get, false);
    expect(read.path, write.path);
  });
}
