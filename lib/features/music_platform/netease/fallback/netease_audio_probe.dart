import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../shared/models/track.dart';

class NeteaseAudioProbe {
  const NeteaseAudioProbe(
    this.reason, {
    this.totalBytes,
    this.bitrate = 0,
    this.duration,
    this.format = '',
    this.sampleRate = 0,
    this.bitsPerSample = 0,
  });
  final String reason;
  final int? totalBytes;
  final int bitrate;
  final Duration? duration;
  final String format;
  final int sampleRate, bitsPerSample;
  bool get hiRes =>
      format == 'flac' && bitsPerSample > 16 && sampleRate >= 48000;
  bool get playable => reason == 'audio_ready';
}

/// A bounded Range request, not a full download. Frame counts can expose a
/// short preview even when the provider labels its URL as a full song.
Future<NeteaseAudioProbe> inspectNeteaseAudio(
  http.Client client,
  String url, {
  int minimumBytes = 0,
  Map<String, String> headers = const {},
  bool requireLossless = false,
  Duration? expectedDuration,
  int prefixBytes = 1024,
  Future<void>? abortTrigger,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return const NeteaseAudioProbe('media_url_invalid');
  }
  final response = await client
      .send(
        http.AbortableRequest('GET', uri, abortTrigger: abortTrigger)
          ..headers.addAll({
            ...publicAudioHeaders(headers),
            'Range': 'bytes=0-${prefixBytes - 1}',
          }),
      )
      .timeout(const Duration(seconds: 8));
  final iterator = StreamIterator(response.stream);
  try {
    if (response.statusCode != 200 && response.statusCode != 206) {
      return NeteaseAudioProbe('media_http_${response.statusCode}');
    }
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    final total = int.tryParse(
      RegExp(
            r'/(\d+)$',
          ).firstMatch(response.headers['content-range'] ?? '')?.group(1) ??
          (response.statusCode == 200
              ? response.headers['content-length'] ?? ''
              : ''),
    );
    if (total != null && minimumBytes > 0 && total < minimumBytes) {
      return NeteaseAudioProbe('media_too_short', totalBytes: total);
    }
    final prefix = <int>[];
    while (prefix.length < prefixBytes &&
        await iterator.moveNext().timeout(const Duration(seconds: 8))) {
      prefix.addAll(iterator.current.take(prefixBytes - prefix.length));
    }
    if (prefix.isEmpty) return const NeteaseAudioProbe('media_empty');
    final opening = utf8
        .decode(prefix.take(48).toList(), allowMalformed: true)
        .trimLeft();
    if (type.contains('text/') ||
        type.contains('json') ||
        opening.startsWith('<') ||
        opening.startsWith('{') ||
        opening.startsWith('[')) {
      return const NeteaseAudioProbe('media_not_audio');
    }
    bool magic(String text, [int start = 0]) =>
        prefix.length >= start + text.length &&
        String.fromCharCodes(prefix.skip(start).take(text.length)) == text;
    final flac = magic('fLaC');
    if (requireLossless && !flac) {
      return const NeteaseAudioProbe('lossless_not_confirmed');
    }
    final mp3 = _mp3Information(prefix);
    if (!(type.contains('audio') ||
        flac ||
        magic('ftyp', 4) ||
        magic('OggS') ||
        type.contains('octet-stream') ||
        magic('ID3') ||
        mp3.bitrate > 0)) {
      return const NeteaseAudioProbe('media_format_unrecognized');
    }
    final duration = flac
        ? _flacDuration(prefix)
        : magic('ftyp', 4)
        ? _mp4Duration(prefix)
        : mp3.duration;
    if (expectedDuration != null &&
        duration != null &&
        duration + const Duration(seconds: 3) < expectedDuration) {
      return NeteaseAudioProbe(
        'media_duration_too_short',
        totalBytes: total,
        bitrate: mp3.bitrate,
        duration: duration,
      );
    }
    return NeteaseAudioProbe(
      'audio_ready',
      totalBytes: total,
      bitrate: mp3.bitrate,
      duration: duration,
      format: flac
          ? 'flac'
          : mp3.bitrate > 0 || magic('ID3')
          ? 'mp3'
          : magic('ftyp', 4)
          ? 'm4a'
          : '',
      // STREAMINFO packs sample rate (20 bits) and bit depth (5 bits)
      // before its 36-bit total sample count. A requested `high` label alone
      // cannot prove Hi-Res; only the actual file header can establish it.
      sampleRate: flac && prefix.length >= 26
          ? (prefix[18] << 12) | (prefix[19] << 4) | (prefix[20] >> 4)
          : 0,
      bitsPerSample: flac && prefix.length >= 26
          ? (((prefix[20] & 1) << 4) | (prefix[21] >> 4)) + 1
          : 0,
    );
  } finally {
    // Cancel also when the server ignores Range and starts streaming the full
    // recording; no unbounded response remains alive after a decision.
    await iterator.cancel();
  }
}

/// MP4/DASH initialization headers can carry the full duration in mdhd/sidx.
/// Traverse only bounded header bytes; never scan compressed media payloads.
Duration? _mp4Duration(List<int> data) {
  int number(int at, int count) {
    var result = 0;
    for (var i = at; i < at + count; i++) {
      result = (result << 8) | data[i];
    }
    return result;
  }

  Duration? visit(int start, int end, int depth) {
    if (depth > 5) return null;
    for (var at = start; at + 8 <= end;) {
      final size = number(at, 4);
      if (size < 8) break;
      final kind = String.fromCharCodes(data.skip(at + 4).take(4));
      final available = (at + size).clamp(at, end);
      final body = at + 8;
      if ({'moov', 'trak', 'mdia'}.contains(kind)) {
        final duration = visit(body, available, depth + 1);
        if (duration != null) return duration;
      } else if ((kind == 'mdhd' || kind == 'mvhd') && body + 20 <= available) {
        final extended = data[body] == 1;
        final rateAt = body + (extended ? 20 : 12);
        final durationAt = rateAt + 4;
        final bytes = extended ? 8 : 4;
        if (durationAt + bytes <= available) {
          final rate = number(rateAt, 4), ticks = number(durationAt, bytes);
          if (rate > 0 && ticks > 0 && ticks != 0xffffffff) {
            return Duration(microseconds: (ticks * 1000000 / rate).round());
          }
        }
      } else if (kind == 'sidx' && body + 24 <= available) {
        final extended = data[body] == 1;
        final countAt = body + (extended ? 30 : 22);
        if (countAt + 2 <= available) {
          final count = number(countAt, 2), rate = number(body + 8, 4);
          final entries = countAt + 2;
          if (rate > 0 && count > 0 && entries + count * 12 <= available) {
            var ticks = 0;
            for (var i = 0; i < count; i++) {
              ticks += number(entries + i * 12 + 4, 4);
            }
            if (ticks > 0) {
              return Duration(microseconds: (ticks * 1000000 / rate).round());
            }
          }
        }
      }
      at += size;
    }
    return null;
  }

  return visit(0, data.length, 0);
}

Duration? _flacDuration(List<int> data) {
  if (data.length < 26 || data[4] & 0x7f != 0) return null;
  var packed = 0;
  for (var i = 18; i < 26; i++) {
    packed = (packed << 8) | data[i];
  }
  final sampleRate = packed >> 44;
  final samples = packed & 0xfffffffff;
  return sampleRate > 0 && samples > 0
      ? Duration(microseconds: (samples * 1000000 / sampleRate).round())
      : null;
}

({int bitrate, Duration? duration}) _mp3Information(List<int> data) {
  var start = 0;
  if (data.length >= 10 && String.fromCharCodes(data.take(3)) == 'ID3') {
    start =
        10 +
        ((data[6] & 127) << 21) +
        ((data[7] & 127) << 14) +
        ((data[8] & 127) << 7) +
        (data[9] & 127);
  }
  int uint32(int at) =>
      (data[at] << 24) |
      (data[at + 1] << 16) |
      (data[at + 2] << 8) |
      data[at + 3];
  for (var at = start; at + 4 <= data.length; at++) {
    if (data[at] != 255 || data[at + 1] & 224 != 224) continue;
    final version = (data[at + 1] >> 3) & 3;
    final layer = (data[at + 1] >> 1) & 3;
    final rateIndex = (data[at + 2] >> 2) & 3;
    final bitIndex = data[at + 2] >> 4;
    if (version == 1 ||
        layer != 1 ||
        rateIndex == 3 ||
        bitIndex == 0 ||
        bitIndex == 15) {
      continue;
    }
    final rates = version == 3
        ? const [
            0,
            32,
            40,
            48,
            56,
            64,
            80,
            96,
            112,
            128,
            160,
            192,
            224,
            256,
            320,
          ]
        : const [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
    final bitrate = rates[bitIndex] * 1000;
    final sampleRate =
        const [44100, 48000, 32000][rateIndex] ~/
        (version == 3
            ? 1
            : version == 2
            ? 2
            : 4);
    final mono = data[at + 3] >> 6 == 3;
    final crc = data[at + 1] & 1 == 0 ? 2 : 0;
    final info =
        at + 4 + crc + (version == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17));
    Duration? duration;
    var measuredBitrate = 0;
    if (info + 12 <= data.length &&
        {
          'Xing',
          'Info',
        }.contains(String.fromCharCodes(data.skip(info).take(4))) &&
        uint32(info + 4) & 1 == 1) {
      final frames = uint32(info + 8);
      if (frames > 0) {
        duration = Duration(
          microseconds:
              (frames * (version == 3 ? 1152 : 576) * 1000000 / sampleRate)
                  .round(),
        );
        final marker = String.fromCharCodes(data.skip(info).take(4));
        if (marker == 'Info') {
          measuredBitrate = bitrate;
        } else if (uint32(info + 4) & 2 == 2 && info + 16 <= data.length) {
          // Xing identifies VBR. Its total bytes/frame count can establish
          // average bitrate; the first frame alone cannot confirm a tier.
          final bytes = uint32(info + 12);
          if (bytes > 0) {
            measuredBitrate = (bytes * 8 * 1000000 / duration.inMicroseconds)
                .round();
          }
        }
      }
    }
    // Only a frame-count duration is authoritative. A VBR file's first frame
    // bitrate alone must not be used to invent its duration or quality tier.
    return (bitrate: measuredBitrate, duration: duration);
  }
  return (bitrate: 0, duration: null);
}

/// Compatibility facade for existing consumers which only need a yes/no probe.
Future<bool> probeAudio(
  http.Client client,
  String url, {
  int minimumBytes = 0,
  Map<String, String> headers = const {},
  bool requireLossless = false,
}) async => (await inspectNeteaseAudio(
  client,
  url,
  minimumBytes: minimumBytes,
  headers: headers,
  requireLossless: requireLossless,
)).playable;
