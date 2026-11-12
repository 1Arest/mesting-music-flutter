import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Independent encoder for the Android NCBL v3 container, verified against
/// account-free native fixtures from official 9.5.12. No official library is
/// bundled. These legacy wire primitives are compatibility, not storage crypto.
/// Cookies belong only in the in-memory user-info section and fixed-host HTTPS.
class NeteaseNativeLog {
  static final _modulus = BigInt.parse(
    'fd90bd466ff9bc8a3fec2fbcf263b90d5c564879fa5d7aab89b31c1d5cb4139d',
    radix: 16,
  );

  static Uint8List encode({
    required String line,
    required String userInfo,
    required int sequence,
    Uint8List? uuid,
    Uint8List? secret,
  }) {
    if (sequence < 0 || sequence > 0xffffffff) {
      throw ArgumentError('Native sequence outside uint32');
    }
    final random = Random.secure();
    Uint8List bytes(int count) =>
        Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
    final id = Uint8List.fromList(uuid ?? bytes(16));
    final key = Uint8List.fromList(secret ?? bytes(32));
    if (id.length != 16 || key.length != 32) {
      throw ArgumentError('Invalid native UUID/key length');
    }
    if (uuid == null) {
      id[6] = (id[6] & 15) | 64;
      id[8] = (id[8] & 63) | 128;
    }
    // Native code bounds its first random byte before raw RSA wrapping.
    if (secret == null && key[0] >= 0xa3) key[0] = 0xa2;
    final value = BigInt.parse(_hex(key), radix: 16);
    if (value >= _modulus) throw ArgumentError('Native key exceeds modulus');
    final wrapped = _unhex(
      value
          .modPow(BigInt.from(65537), _modulus)
          .toRadixString(16)
          .padLeft(64, '0'),
    );
    final info = Uint8List.fromList(utf8.encode(userInfo));
    final plain = Uint8List.fromList(utf8.encode(line));
    if (info.length > 16000 || plain.isEmpty || plain.length > 48000) {
      throw ArgumentError('Native event exceeds bounded single-file size');
    }
    // A valid Zstandard stream with one raw block avoids new native/dependency
    // requirements. Like the official flush block, it leaves the stream open.
    final zstd = BytesBuilder()
      ..add([0x28, 0xb5, 0x2f, 0xfd, 0, 0x58])
      ..add(_le(plain.length << 3, 3))
      ..add(plain);
    final compressed = zstd.takeBytes();
    final counter = ByteData.sublistView(id).getUint32(12, Endian.little) >> 2;
    final nonce = Uint8List.sublistView(id, 0, 12);
    final headerLength = 70 + (info.isEmpty ? 0 : 4 + info.length);
    final result = BytesBuilder()
      ..add(ascii.encode('NCBL'))
      ..add(_le(3, 4))
      ..add(_le(headerLength, 2))
      ..add(id)
      ..add(wrapped)
      ..add(_le(sequence, 4))
      ..add(_le(sequence, 4))
      ..add(_le(compressed.length + 6, 4));
    if (info.isNotEmpty) {
      result
        ..add([0x43, 0x43])
        ..add(_le(info.length, 2))
        ..add(chacha(info, wrapped, nonce, counter));
    }
    result
      ..add(_le(compressed.length, 2))
      ..add(_le(sequence, 4))
      ..add(chacha(compressed, key, nonce, counter));
    return result.takeBytes();
  }

  /// RFC 8439 ChaCha20 with an explicit initial 32-bit counter. The existing
  /// cipher dependency starts only at zero, so keep this small compatibility
  /// core independently covered by both RFC and original-native vectors.
  static Uint8List chacha(
    Uint8List input,
    Uint8List key,
    Uint8List nonce,
    int counter,
  ) {
    if (key.length != 32 || nonce.length != 12 || counter < 0) {
      throw ArgumentError('Invalid ChaCha20 inputs');
    }
    int word(Uint8List a, int offset) =>
        ByteData.sublistView(a).getUint32(offset, Endian.little);
    const mask = 0xffffffff;
    int rotate(int value, int count) =>
        ((value << count) | (value >> (32 - count))) & mask;
    final state = <int>[
      0x61707865,
      0x3320646e,
      0x79622d32,
      0x6b206574,
      for (var i = 0; i < 8; i++) word(key, i * 4),
      counter,
      for (var i = 0; i < 3; i++) word(nonce, i * 4),
    ];
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += 64) {
      if (state[12] > mask) throw StateError('ChaCha20 counter exhausted');
      final x = List<int>.from(state);
      void round(int a, int b, int c, int d) {
        x[a] = (x[a] + x[b]) & mask;
        x[d] = rotate(x[d] ^ x[a], 16);
        x[c] = (x[c] + x[d]) & mask;
        x[b] = rotate(x[b] ^ x[c], 12);
        x[a] = (x[a] + x[b]) & mask;
        x[d] = rotate(x[d] ^ x[a], 8);
        x[c] = (x[c] + x[d]) & mask;
        x[b] = rotate(x[b] ^ x[c], 7);
      }

      for (var i = 0; i < 10; i++) {
        round(0, 4, 8, 12);
        round(1, 5, 9, 13);
        round(2, 6, 10, 14);
        round(3, 7, 11, 15);
        round(0, 5, 10, 15);
        round(1, 6, 11, 12);
        round(2, 7, 8, 13);
        round(3, 4, 9, 14);
      }
      final block = ByteData(64);
      for (var i = 0; i < 16; i++) {
        block.setUint32(i * 4, (x[i] + state[i]) & mask, Endian.little);
      }
      final bytes = block.buffer.asUint8List();
      for (var i = 0; i < 64 && offset + i < input.length; i++) {
        output[offset + i] = input[offset + i] ^ bytes[i];
      }
      state[12]++;
    }
    return output;
  }

  static List<int> _le(int value, int count) =>
      List.generate(count, (i) => (value >> (i * 8)) & 255);
  static String _hex(List<int> value) =>
      value.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  static Uint8List _unhex(String value) => Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}
