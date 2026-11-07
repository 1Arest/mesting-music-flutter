import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Wire-format adapter for @neteaseapireborn/api 4.29.7 (MIT).
/// These public protocol constants are not account credentials. Credential
/// storage belongs to NeteaseSessionStore, independently of request encryption.
class NeteaseCrypto {
  static const _iv = '0102030405060708';
  static const _preset = '0CoJUm6Qyw8W8jud';
  static const _eapi = 'e82ckenh8dichen8';
  static final _modulus = BigInt.parse(
    '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7',
    radix: 16,
  );

  static Uint8List _aes(String text, String key, {bool cbc = false}) {
    final cipher = PaddedBlockCipher('AES/${cbc ? 'CBC' : 'ECB'}/PKCS7');
    final keyParameter = KeyParameter(Uint8List.fromList(utf8.encode(key)));
    cipher.init(
      true,
      PaddedBlockCipherParameters(
        cbc
            ? ParametersWithIV(
                keyParameter,
                Uint8List.fromList(utf8.encode(_iv)),
              )
            : keyParameter,
        null,
      ),
    );
    return cipher.process(Uint8List.fromList(utf8.encode(text)));
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Map<String, String> eapi(String path, Map<String, Object?> data) {
    final text = jsonEncode(data);
    final digest = md5.convert(
      utf8.encode('nobody${path}use${text}md5forencrypt'),
    );
    return {
      'params': _hex(
        _aes('$path-36cd479b6b5-$text-36cd479b6b5-$digest', _eapi),
      ).toUpperCase(),
    };
  }

  /// A supplied secret is useful for protocol golden vectors; production always
  /// obtains fresh entropy from Random.secure rather than Math.random upstream.
  static Map<String, String> weapi(
    Map<String, Object?> data, {
    String? secret,
  }) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final key =
        secret ?? List.generate(16, (_) => alphabet[random.nextInt(62)]).join();
    if (key.length != 16) throw ArgumentError('Expected a 16 character secret');
    final first = base64Encode(_aes(jsonEncode(data), _preset, cbc: true));
    final reversed = utf8.encode(key.split('').reversed.join());
    final value = BigInt.parse(_hex(reversed), radix: 16);
    return {
      'params': base64Encode(_aes(first, key, cbc: true)),
      'encSecKey': value
          .modPow(BigInt.from(65537), _modulus)
          .toRadixString(16)
          .padLeft(256, '0'),
    };
  }
}
