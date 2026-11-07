import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../shared/models/track.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/data/platform_catalog.dart';
import '../music_platform/domain/platform_session.dart';

/// A per-run directory outlives its page but never overlaps a reopened page's
/// recording, even when the previous asynchronous cleanup is still pending.
Future<Directory> createRecognitionSessionDirectory(Directory root) =>
    root.createTemp('mesting-recognition-');

/// The upstream recognizer accepts PCM16 LE, mono, 8000 Hz. Decode RIFF by
/// chunks rather than stripping an assumed 44-byte header (WAV can have tags).
/// CPU work runs in an isolate so recognition never blocks navigation frames.
Uint8List recognitionPcm(Uint8List wav) {
  final view = ByteData.sublistView(wav);
  String tag(int p) => String.fromCharCodes(wav.sublist(p, p + 4));
  if (wav.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('录音格式无效');
  }
  var hz = 0, channels = 0;
  Uint8List? pcm;
  for (var p = 12; p + 8 <= wav.length;) {
    final length = view.getUint32(p + 4, Endian.little);
    final start = p + 8;
    if (length > wav.length - start) throw const FormatException('录音不完整');
    if (tag(p) == 'fmt ') {
      if (length < 16 ||
          view.getUint16(start, Endian.little) != 1 ||
          view.getUint16(start + 14, Endian.little) != 16) {
        throw const FormatException('需要 16 位 PCM 录音');
      }
      channels = view.getUint16(start + 2, Endian.little);
      hz = view.getUint32(start + 4, Endian.little);
    } else if (tag(p) == 'data') {
      pcm = Uint8List.sublistView(wav, start, start + length);
    }
    p = start + length + (length & 1);
  }
  if (pcm == null || hz < 8000 || hz > 192000 || channels < 1 || channels > 2) {
    throw const FormatException('录音采样参数无效');
  }
  final input = ByteData.sublistView(pcm);
  final samples = pcm.length ~/ (2 * channels);
  final outputCount = samples * 8000 ~/ hz;
  if (outputCount > 8000 * 12) throw const FormatException('录音片段过长');
  final signal = Int32List(outputCount);
  var sum = 0;
  for (var i = 0; i < outputCount; i++) {
    final begin = i * hz ~/ 8000;
    final end = ((i + 1) * hz ~/ 8000).clamp(begin + 1, samples);
    var value = 0;
    for (var j = begin; j < end; j++) {
      for (var c = 0; c < channels; c++) {
        value += input.getInt16((j * channels + c) * 2, Endian.little);
      }
    }
    signal[i] = value ~/ ((end - begin) * channels);
    sum += signal[i];
  }
  if (outputCount == 0) return Uint8List(0);
  final dc = sum ~/ outputCount;
  var peak = 0;
  for (final sample in signal) {
    if ((sample - dc).abs() > peak) peak = (sample - dc).abs();
  }
  if (peak < 30) return Uint8List(0);
  final gain = (25000 / peak).clamp(1.0, 20.0);
  final result = Uint8List(outputCount * 2);
  final out = ByteData.sublistView(result);
  for (var i = 0; i < outputCount; i++) {
    out.setInt16(
      i * 2,
      ((signal[i] - dc) * gain).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return result;
}

List<Track> recognizedTracks(Map<String, dynamic> response) {
  final raw = response['data'];
  final rows = raw is List
      ? raw
      : raw is Map
      ? [raw]
      : const [];
  return PlatformCatalog.tracks(
    rows
        .whereType<Map>()
        .map(
          (row) => {
            ...row,
            'songname':
                row['songname'] ??
                row['song_name'] ??
                row['SongName'] ??
                row['name'],
            'singername':
                row['singername'] ?? row['singer_name'] ?? row['singer'],
          },
        )
        .toList(),
  );
}

class RecognitionRepository {
  const RecognitionRepository(this.api);
  final MusicPlatformApi api;
  Future<List<Track>> identify(
    Uint8List wav, {
    Future<void>? abort,
    PlatformSession? identity,
  }) async {
    final pcm = await compute(recognitionPcm, wav);
    if (pcm.isEmpty) return const [];
    return resolveResult(
      await api.postBytes(
        '/audio/match',
        pcm,
        abortTrigger: abort,
        expectedSession: identity,
      ),
      abort: abort,
      identity: identity,
    );
  }

  /// Some recognition hits contain only a recording ID. Resolve their source
  /// with that ID (or exact title/artist), never the first unrelated search hit.
  Future<List<Track>> resolveResult(
    Map<String, dynamic> response, {
    Future<void>? abort,
    PlatformSession? identity,
  }) async {
    final tracks = <Track>[...recognizedTracks(response)];
    final raw = response['data'];
    final rows = raw is List
        ? raw
        : raw is Map
        ? [raw]
        : const [];
    for (final row in rows.take(5).whereType<Map>()) {
      if (recognizedTracks({'data': row}).isNotEmpty) continue;
      String field(List<String> keys) {
        for (final key in keys) {
          final value = '${row[key] ?? ''}'.trim();
          if (value.isNotEmpty) return value;
        }
        return '';
      }

      final name = field(['songname', 'song_name', 'SongName', 'name']);
      final artist = field([
        'singername',
        'singer_name',
        'SingerName',
        'author_name',
        'singer',
      ]);
      final id = field(['album_audio_id', 'mixsongid', 'MixSongID']);
      if (name.isEmpty) continue;
      final result = await api.get(
        '/search',
        query: {
          'keywords': '$artist $name'.trim(),
          'pagesize': '5',
          'page': '1',
          'type': 'song',
        },
        abortTrigger: abort,
        expectedSession: identity,
      );
      final candidates = PlatformCatalog.tracks(result);
      String normal(String value) =>
          value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      final matching = candidates.where(
        (track) => id.isNotEmpty
            ? track.platformSongId == id
            : normal(track.title) == normal(name) &&
                  (artist.isEmpty || normal(track.artist) == normal(artist)),
      );
      if (matching.isNotEmpty) tracks.add(matching.first);
    }
    final seen = <String>{};
    return tracks.where((track) => seen.add(track.id)).toList();
  }
}
