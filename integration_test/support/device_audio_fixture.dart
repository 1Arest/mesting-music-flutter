import 'dart:io';
import 'dart:typed_data';

import 'package:mesting_music/shared/models/track.dart';

import '../../test/support/test_tracks.dart';

/// Creates a real, device-local WAV only for Android integration tests.
///
/// The fixture is generated in the test process cache directory and is never
/// declared in pubspec assets, so it cannot add audio back to release builds.
class DeviceAudioFixture {
  DeviceAudioFixture._(this.directory, this.tracks);

  final Directory directory;
  final List<Track> tracks;

  static Future<DeviceAudioFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'mesting-audio-regression-',
    );
    final audioFile = File('${directory.path}/silence-90s.wav');
    await audioFile.writeAsBytes(
      _silentPcmWave(const Duration(seconds: 90)),
      flush: true,
    );
    final audioUri = audioFile.uri.toString();
    return DeviceAudioFixture._(
      directory,
      testTracks
          .map((track) => track.copyWith(audioAsset: audioUri))
          .toList(growable: false),
    );
  }

  Future<void> dispose() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Uint8List _silentPcmWave(Duration duration) {
  const sampleRate = 8000;
  const channels = 1;
  const bitsPerSample = 16;
  const headerLength = 44;
  const bytesPerSample = bitsPerSample ~/ 8;
  const byteRate = sampleRate * channels * bytesPerSample;
  final dataLength = (duration.inMicroseconds * byteRate) ~/ 1000000;
  final bytes = Uint8List(headerLength + dataLength);
  final header = ByteData.sublistView(bytes);

  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, channels * bytesPerSample, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataLength, Endian.little);
  return bytes;
}
