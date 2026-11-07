import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liquid_glass_widgets/widgets/interactive/liquid_glass_scope.dart';
import 'package:mesting_music/features/recognition/recognition_repository.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:12345');
}

Uint8List wav({int hz = 44100, int channels = 1, bool silent = false}) {
  final frames = hz ~/ 10;
  final payload = frames * channels * 2;
  final bytes = Uint8List(44 + payload);
  final view = ByteData.sublistView(bytes);
  void tag(int at, String value) => bytes.setRange(at, at + 4, value.codeUnits);
  tag(0, 'RIFF');
  view.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, hz, Endian.little);
  view.setUint32(28, hz * channels * 2, Endian.little);
  view.setUint16(32, channels * 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  view.setUint32(40, payload, Endian.little);
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < channels; c++) {
      view.setInt16(
        44 + (i * channels + c) * 2,
        silent ? 0 : (math.sin(i * 2 * math.pi * 440 / hz) * 1500).round(),
        Endian.little,
      );
    }
  }
  return bytes;
}

void main() {
  test('reopened recognition owns a separate temporary directory', () async {
    final root = await Directory.systemTemp.createTemp('recognition-test-');
    addTearDown(() => root.delete(recursive: true));
    final old = await createRecognitionSessionDirectory(root);
    final current = await createRecognitionSessionDirectory(root);
    final first = File('${old.path}/segment-1.wav');
    final second = File('${current.path}/segment-1.wav');
    await first.writeAsBytes([1, 2]);
    await second.writeAsBytes([3, 4]);
    await old.delete(recursive: true);
    expect(await second.readAsBytes(), [3, 4]);
    expect(old.path, isNot(current.path));
  });
  testWidgets(
    'nested repaint layers refresh on next frame and lenses share that frame image',
    (tester) async {
      final color = ValueNotifier(Colors.blue);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LiquidGlassScope(
            child: GlassBackgroundSource(
              child: RepaintBoundary(
                child: ValueListenableBuilder(
                  valueListenable: color,
                  builder: (_, value, _) => ColoredBox(color: value),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderGlassBackgroundBoundary>(
        find.byType(GlassBackgroundSource),
      );
      final version = boundary.paintVersion;
      Future<List<int>> capture() async {
        late final ui.Image snapshot;
        tester.binding.addPostFrameCallback((frame) {
          snapshot = boundary.captureSnapshot(1, frame: frame);
          boundary.captureSnapshot(1, frame: frame).dispose();
        });
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(milliseconds: 16));
        final bytes = await tester.runAsync(
          () => snapshot.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        snapshot.dispose();
        return bytes!.buffer.asUint8List().take(4).toList();
      }

      expect(await capture(), [33, 150, 243, 255]);
      expect(boundary.debugCaptureCount, 1);
      color.value = Colors.red;
      await tester.pump();
      expect(boundary.paintVersion, version);
      expect(await capture(), [244, 67, 54, 255]);
      expect(boundary.debugCaptureCount, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      color.dispose();
    },
  );
  test(
    'recognition source lookup selects matching recording instead of first search hit',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/search');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'data': {
                'lists': [
                  {'hash': 'wrong', 'songname': '同名歌曲', 'album_audio_id': 999},
                  {
                    'hash': 'correct',
                    'songname': '同名歌曲',
                    'album_audio_id': 123,
                  },
                ],
              },
            }),
          ),
          200,
        );
      });
      addTearDown(client.close);
      final repository = RecognitionRepository(
        MusicPlatformApi(server: _Server(), client: client),
      );
      final result = await repository.resolveResult({
        'data': [
          {'song_name': '同名歌曲', 'album_audio_id': 123},
        ],
      });
      expect(result.single.id, 'kugou_correct');
      expect(result.single.platformSongId, '123');
    },
  );
  test(
    'recognition decodes mono/stereo RIFF into bounded 8k PCM and rejects malformed chunks',
    () {
      expect(recognitionPcm(wav()).length, 1600);
      expect(recognitionPcm(wav(channels: 2)).length, 1600);
      expect(recognitionPcm(wav(silent: true)), isEmpty);
      expect(() => recognitionPcm(Uint8List(44)), throwsFormatException);
      final bad = wav();
      ByteData.sublistView(bad).setUint32(40, 0x7fffffff, Endian.little);
      expect(() => recognitionPcm(bad), throwsFormatException);
    },
  );
  test(
    'recognizer keeps original Kugou identity for playback and favorites',
    () {
      final tracks = recognizedTracks({
        'data': [
          {
            'hash': 'abcd1234',
            'song_name': '虚拟',
            'singer_name': '陈粒',
            'album_audio_id': 12345,
          },
        ],
      });
      expect(tracks.single.platformSongId, '12345');
      expect(tracks.single.title, '虚拟');
      expect(
        tracks.single.audioAsset,
        'mesting-platform://kugou/kugou_abcd1234',
      );
    },
  );
  test(
    'liquid source is inside the button edge facing the menu in both directions',
    () {
      for (final y in [40.0, 680.0]) {
        final layout = BetaMenuLayout(
          anchor: Rect.fromLTWH(330, y, 48, 48),
          media: const MediaQueryData(size: Size(390, 844)),
          width: 280,
          fromInnerEdge: true,
        );
        final source = layout.sourceBounds(
          const Size(390, 844),
          const Size(280, 230),
        );
        expect(layout.anchor.contains(source.topLeft), isTrue);
        expect(layout.anchor.contains(source.bottomRight), isTrue);
        expect((source.center - layout.anchor.center).distance, greaterThan(8));
        expect(
          source.center.dy,
          y < 100
              ? greaterThan(layout.anchor.center.dy)
              : lessThan(layout.anchor.center.dy),
        );
      }
    },
  );
  testWidgets(
    'background lenses share full-DPR snapshot until actual repaint',
    (tester) async {
      final color = ValueNotifier(Colors.blue);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LiquidGlassScope(
            child: SizedBox(
              width: 100,
              height: 100,
              child: GlassBackgroundSource(
                child: ValueListenableBuilder(
                  valueListenable: color,
                  builder: (_, value, _) => ColoredBox(color: value),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderGlassBackgroundBoundary>(
        find.byType(GlassBackgroundSource),
      );
      final first = boundary.captureSnapshot(2);
      final second = boundary.captureSnapshot(2);
      expect(first.width, 1600); // Default test view is 800px wide.
      expect(boundary.debugCaptureCount, 1);
      first.dispose();
      second.dispose();
      color.value = Colors.red;
      await tester.pump();
      boundary.captureSnapshot(2).dispose();
      expect(boundary.debugCaptureCount, 2);
      boundary.captureSnapshot(1).dispose();
      expect(boundary.debugCaptureCount, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      color.dispose();
    },
  );
}
