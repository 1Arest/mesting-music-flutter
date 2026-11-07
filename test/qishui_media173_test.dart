import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_media_attempts.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playback_media.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playback_failures.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_playback_recovery.dart';
import 'qishui_protocol_test.dart' show sodaRecording;
import 'qishui_signed_api167_test.dart' show account, FixtureSigner, reply;
import 'netease_v116_recovery_test.dart' show mp3Response;

List<QishuiMedia> candidates173() => QishuiMedia.parse({
  'PlayInfoList': [
    {
      'MainPlayUrl': 'https://audio.example/primary.mp3',
      'backup_url_1': 'https://audio.example/backup1.mp3',
      'backup_url_2': 'https://audio.example/backup2.mp3',
      'backup_url_3': 'https://audio.example/backup3.mp3',
      'Duration': 230,
      'Bitrate': 128000,
      'Format': 'mp3',
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all distinct backup URLs survive parsing', () {
    expect(candidates173().map((m) => m.url), [
      'https://audio.example/primary.mp3',
      'https://audio.example/backup1.mp3',
      'https://audio.example/backup2.mp3',
      'https://audio.example/backup3.mp3',
    ]);
  });
  test(
    'actual resolver recovers a bad main CDN with same-song backup',
    () async {
      final audioRequests = <String>[];
      final api = QishuiApi(
        MockClient((r) async {
          if (r.url.host == 'api.qishui.com') {
            return reply({
              'track_player': {
                'video_model': {
                  'PlayInfoList': [
                    {
                      'MainPlayUrl': 'https://audio.example/primary.mp3',
                      'backup_url_1': 'https://audio.example/backup1.mp3',
                      'Duration': 230,
                      'Bitrate': 128000,
                      'Format': 'mp3',
                    },
                  ],
                },
              },
            });
          }
          expect(r.headers['cookie'], isNull);
          audioRequests.add(r.url.path);
          return r.url.path.contains('primary')
              ? http.Response(
                  '<html>bad CDN</html>',
                  200,
                  headers: {'content-type': 'text/html'},
                )
              : mp3Response(230);
        }),
        signer: FixtureSigner(),
      )..configure(account());
      addTearDown(api.dispose);
      final track = await QishuiRepository(api).resolve(sodaRecording());
      expect(track.audioAsset, 'https://audio.example/backup1.mp3');
      expect(track.isPreview, false);
      expect(audioRequests.toSet(), {'/primary.mp3', '/backup1.mp3'});
    },
  );
  for (final kind in [
    QishuiFailureKind.connection,
    QishuiFailureKind.authentication,
    QishuiFailureKind.timeout,
    QishuiFailureKind.cancelled,
  ]) {
    test('$kind stops same-song fallback immediately', () async {
      var count = 0;
      final selected = QishuiPlaybackSelection.candidates(
        candidates173(),
        catalogDuration: const Duration(seconds: 230),
        download: false,
        requireQuality: false,
      );
      await expectLater(
        prepareQishuiMediaCandidates(
          selected,
          current: () => true,
          prepare: (_, _) async {
            ++count;
            throw QishuiException('fixture', kind: kind);
          },
        ),
        throwsA(isA<QishuiException>()),
      );
      expect(count, 1);
    });
  }
  test('full authorized media never degrades to preview after CDN failure', () {
    final streams = [
      ...candidates173(),
      QishuiMedia(
        'https://audio.example/preview.mp3',
        const Duration(seconds: 30),
        320000,
        false,
      ),
    ];
    final selected = QishuiPlaybackSelection.candidates(
      streams,
      catalogDuration: const Duration(seconds: 230),
      download: false,
      requireQuality: false,
    );
    expect(selected.every((s) => !s.isPreview), true);
  });
  test(
    'bounded retry deduplicates URLs and honors account cancellation',
    () async {
      var current = true;
      var count = 0;
      final selected = QishuiPlaybackSelection.candidates(
        candidates173(),
        catalogDuration: const Duration(seconds: 230),
        download: false,
        requireQuality: false,
      );
      await expectLater(
        prepareQishuiMediaCandidates(
          [...selected, ...selected],
          current: () => current,
          maximumAttempts: 2,
          prepare: (_, _) async {
            ++count;
            throw const QishuiException(
              'fixture',
              kind: QishuiFailureKind.format,
            );
          },
        ),
        throwsA(isA<QishuiException>()),
      );
      expect(count, 2);
      count = 0;
      await expectLater(
        prepareQishuiMediaCandidates(
          selected,
          current: () => current,
          prepare: (_, _) async {
            ++count;
            current = false;
            throw const QishuiException(
              'fixture',
              kind: QishuiFailureKind.format,
            );
          },
        ),
        throwsA(
          isA<QishuiException>().having(
            (e) => e.kind,
            'cancelled',
            QishuiFailureKind.cancelled,
          ),
        ),
      );
      expect(count, 1);
    },
  );
  test(
    'skipped song memory is bounded, readable and cleared for a new owner',
    () {
      final buffer = QishuiPlaybackFailures.shared;
      buffer.beginOwner('synthetic-owner');
      for (var i = 0; i < 24; i++) {
        expect(
          qishuiCanSkipPlaybackFailure(
            sodaRecording(),
            const QishuiException(
              'fixture-secret-url',
              kind: QishuiFailureKind.format,
            ),
          ),
          true,
        );
      }
      expect(buffer.rows.length, 20);
      expect(buffer.rows.first.title, sodaRecording().title);
      expect(buffer.rows.first.reason, isNot(contains('fixture-secret-url')));
      buffer.beginOwner('another-owner');
      expect(buffer.rows, isEmpty);
    },
  );
}
