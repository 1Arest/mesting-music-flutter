import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../domain/app_update_models.dart';

/// The existing distribution host serves APKs, not a separate changelog API.
/// Future releases carry a tiny, version-bound JSON asset. Range reads retrieve
/// only the ZIP directory and this entry, before download/installation starts.
/// This reader never installs, unpacks other entries, follows redirects, or
/// changes the downloader's verified APK identity. Notes are untrusted text.
class PublicApkReleaseNotes {
  const PublicApkReleaseNotes(this.client);
  final http.Client client;
  static const asset = 'assets/flutter_assets/assets/data/release-notes.json';
  static const maxNotesBytes = 32768;

  static List<String> parse(Object? value) {
    final lines = value is List
        ? value
        : value is String
        ? value.split('\n')
        : const [];
    if (lines.length > 50) return const [];
    final result = <String>[];
    var length = 0;
    for (final line in lines) {
      if (line is! String || line.length > 1000) return const [];
      final text = line.trim();
      length += text.length;
      if (length > 12000) return const [];
      if (text.isNotEmpty) result.add(text);
    }
    return List.unmodifiable(result);
  }

  Future<List<String>> load(AppUpdateManifest release) async {
    try {
      final end = release.sizeBytes;
      final tailStart = end > 65557 ? end - 65557 : 0;
      final tail = await _range(release, tailStart, end - 1);
      final td = ByteData.sublistView(tail);
      var eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (td.getUint32(i, Endian.little) == 0x06054b50 &&
            i + 22 + td.getUint16(i + 20, Endian.little) == tail.length) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0 ||
          td.getUint16(eocd + 4, Endian.little) != 0 ||
          td.getUint16(eocd + 6, Endian.little) != 0) {
        return const [];
      }
      final count = td.getUint16(eocd + 10, Endian.little);
      final size = td.getUint32(eocd + 12, Endian.little);
      final start = td.getUint32(eocd + 16, Endian.little);
      if (count == 65535 ||
          size <= 0 ||
          size > 1024 * 1024 ||
          start + size > tailStart + eocd) {
        return const [];
      }
      final directory = start >= tailStart
          ? Uint8List.sublistView(
              tail,
              start - tailStart,
              start - tailStart + size,
            )
          : await _range(release, start, start + size - 1);
      final cd = ByteData.sublistView(directory);
      var position = 0;
      for (var entry = 0; entry < count; entry++) {
        if (position + 46 > directory.length ||
            cd.getUint32(position, Endian.little) != 0x02014b50) {
          return const [];
        }
        final nameLength = cd.getUint16(position + 28, Endian.little);
        final extraLength = cd.getUint16(position + 30, Endian.little);
        final commentLength = cd.getUint16(position + 32, Endian.little);
        final next = position + 46 + nameLength + extraLength + commentLength;
        if (next > directory.length) return const [];
        final name = utf8.decode(
          directory.sublist(position + 46, position + 46 + nameLength),
          allowMalformed: true,
        );
        if (name == asset) {
          final flags = cd.getUint16(position + 8, Endian.little);
          final method = cd.getUint16(position + 10, Endian.little);
          final crc = cd.getUint32(position + 16, Endian.little);
          final packed = cd.getUint32(position + 20, Endian.little);
          final unpacked = cd.getUint32(position + 24, Endian.little);
          final offset = cd.getUint32(position + 42, Endian.little);
          if (flags & 1 != 0 ||
              (method != 0 && method != 8) ||
              packed <= 0 ||
              packed > maxNotesBytes ||
              unpacked > maxNotesBytes ||
              offset + 30 >= start) {
            return const [];
          }
          final local = ByteData.sublistView(
            await _range(release, offset, offset + 29),
          );
          if (local.getUint32(0, Endian.little) != 0x04034b50 ||
              local.getUint16(8, Endian.little) != method) {
            return const [];
          }
          final localNameLength = local.getUint16(26, Endian.little);
          final headerSize =
              localNameLength + local.getUint16(28, Endian.little);
          if (headerSize > 8192 || offset + 30 + headerSize + packed > start) {
            return const [];
          }
          final content = await _range(
            release,
            offset + 30,
            offset + 29 + headerSize + packed,
          );
          if (utf8.decode(content.sublist(0, localNameLength)) != asset) {
            return const [];
          }
          final encoded = content.sublist(headerSize);
          // Stream decoding bounds expansion as well as declared lengths.
          final bytes = method == 0 ? encoded : await _inflate(encoded);
          if (bytes.length != unpacked || _crc32(bytes) != crc) return const [];
          final json = jsonDecode(utf8.decode(bytes));
          if (json is! Map ||
              json['version'] != release.versionName ||
              json['versionCode'] != release.versionCode) {
            return const [];
          }
          return parse(json['releaseNotes']);
        }
        position = next;
      }
    } on Object {
      // Optional notes must never turn a discoverable update into an error.
    }
    return const [];
  }

  Future<List<int>> _inflate(List<int> input) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in ZLibDecoder(
      raw: true,
    ).bind(Stream.value(input))) {
      if (out.length + chunk.length > maxNotesBytes) {
        throw const FormatException();
      }
      out.add(chunk);
    }
    return out.takeBytes();
  }

  Future<Uint8List> _range(
    AppUpdateManifest release,
    int start,
    int end,
  ) async {
    if (start < 0 ||
        end < start ||
        end >= release.sizeBytes ||
        end - start > 1024 * 1024) {
      throw const FormatException();
    }
    final cancel = Completer<void>();
    try {
      final request =
          http.AbortableRequest(
              'GET',
              release.apkUrl,
              abortTrigger: cancel.future,
            )
            ..followRedirects = false
            ..headers.addAll({
              'range': 'bytes=$start-$end',
              'accept-encoding': 'identity',
              if (release.downloadEtag != null)
                'if-match': release.downloadEtag!,
            });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 206 ||
          response.headers['content-range'] !=
              'bytes $start-$end/${release.sizeBytes}' ||
          (release.downloadEtag != null &&
              response.headers['etag'] != release.downloadEtag)) {
        throw const FormatException();
      }
      final expected = end - start + 1;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 4),
      )) {
        if (bytes.length + chunk.length > expected) {
          throw const FormatException();
        }
        bytes.add(chunk);
      }
      if (bytes.length != expected) throw const FormatException();
      return bytes.takeBytes();
    } finally {
      cancel.complete();
    }
  }

  static int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
