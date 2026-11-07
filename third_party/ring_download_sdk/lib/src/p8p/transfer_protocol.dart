import 'dart:convert';
import 'dart:typed_data';

class P8PTransferProtocol {
  static const channel = 'p8p-file-v1';
  static const headerBytes = 16;
  static const maxFrameBytes = 48 * 1024;
  static const maxId = 0x7fffffff;
  static const maxInflight = 4;
  static const capability = <String, Object>{
    'version': 1,
    'channel': channel,
    'header_bytes': headerBytes,
    'max_frame_bytes': maxFrameBytes,
    'max_inflight': maxInflight,
    'cancel': true,
  };

  static bool wireId(Object? value) =>
      value is int && value > 0 && value <= maxId;

  static bool advertised(Object? value) {
    if (value is! Map || value['version'] is! int || value['version'] != 1) {
      return false;
    }
    final transfer = value['transfer'];
    return transfer is Map &&
        capability.entries.every((entry) {
          final actual = transfer[entry.key];
          return actual.runtimeType == entry.value.runtimeType &&
              actual == entry.value;
        });
  }

  static Map<String, dynamic> control(String raw) {
    if (raw.length > 1024 || utf8.encode(raw).length > 1024) {
      throw const FormatException('invalid_control');
    }
    Object? value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('invalid_control');
    }
    if (value is! Map<String, dynamic> ||
        value['version'] is! int ||
        value['version'] != 1 ||
        !wireId(value['generation'])) {
      throw const FormatException('invalid_control');
    }
    return value;
  }

  /// Request-side parser also exercised by the shared Python/Dart vectors.
  static Map<String, dynamic> request(String raw, int pieceCount) {
    final value = control(raw);
    if (value['type'] == 'hello') {
      if (value['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String)) {
        throw const FormatException('invalid_control');
      }
    } else if (value['type'] == 'get' || value['type'] == 'cancel') {
      if (!wireId(value['request_id']) ||
          (value['type'] == 'get' &&
              (value['index'] is! int ||
                  value['index'] < 0 ||
                  value['index'] >= pieceCount))) {
        throw const FormatException('invalid_control');
      }
    } else {
      throw const FormatException('invalid_control');
    }
    return value;
  }

  static P8PFrame frame(Uint8List raw) {
    if (raw.length <= headerBytes || raw.length > maxFrameBytes) {
      throw const FormatException('invalid_frame');
    }
    final header = ByteData.sublistView(raw, 0, headerBytes);
    if (header.getUint32(0) != 0x50385031) {
      throw const FormatException('invalid_frame');
    }
    final generation = header.getUint32(4);
    final identity = header.getUint32(8);
    final offset = header.getUint32(12);
    if (!wireId(generation) ||
        !wireId(identity) ||
        offset + raw.length - headerBytes > 1024 * 1024) {
      throw const FormatException('invalid_frame');
    }
    return P8PFrame(
      generation,
      identity,
      offset,
      Uint8List.sublistView(raw, headerBytes),
    );
  }

  static Uint8List encode(
    int generation,
    int identity,
    int offset,
    Uint8List body,
  ) {
    if (!wireId(generation) ||
        !wireId(identity) ||
        offset < 0 ||
        body.isEmpty ||
        body.length > maxFrameBytes - headerBytes ||
        offset + body.length > 1024 * 1024) {
      throw const FormatException('invalid_frame');
    }
    final result = Uint8List(headerBytes + body.length);
    final header = ByteData.sublistView(result, 0, headerBytes);
    header.setUint32(0, 0x50385031);
    header.setUint32(4, generation);
    header.setUint32(8, identity);
    header.setUint32(12, offset);
    result.setRange(headerBytes, result.length, body);
    return result;
  }
}

class P8PFrame {
  const P8PFrame(this.generation, this.identity, this.offset, this.body);
  final int generation, identity, offset;
  final Uint8List body;
}
