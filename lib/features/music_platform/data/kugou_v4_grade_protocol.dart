import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// The wire envelope used by the standard Android 20.8.6 grade service.
///
/// This module only encodes requests. The caller owns the account epoch,
/// measurement ledger, network timeout and receipt handling. An encoded request
/// must never be logged: [body] contains an encrypted account credential.
class KugouV4GradeRequest {
  const KugouV4GradeRequest({required this.body, required this.query});

  static final endpoint = Uri.https(
    'userinfoservice.kugou.com',
    '/v4/get_grade_info',
  );

  final String body;
  final Map<String, String> query;
}

/// Public protocol constants and independently testable byte encoding.
///
/// Observed in 20.8.6 `protocol.u.a`, `ParamGenerator.W/B0`, `dr3.a` and
/// `dr3.h0`. These are public application protocol values, not user secrets.
/// A Lite credential must never be relabelled as standard authorization.
class KugouV4GradeProtocol {
  static const standardAppId = '1005';
  static const standardClientVersion = '20869';
  static const _appKey = 'OIlwieks28dk2k092lksi2UIkp';
  static final _modulus = BigInt.parse(
    'c8006ed03842d2628209bd314984ca5ed6cfe06e30c95f9d4704d9c49791d7a935'
    'ba950ecb0bc8ebf5f5994f0bac927a7eb151b3c1de343303fa539c83136eccfd7d'
    '7e511e2dbce18eaa9f784c9b50d443e75865979e0a5e216e46c684066a8d6b998'
    '580bbaa22d73f5790286bb14742e83244e44db6d707ffe162c5c7002d45',
    radix: 16,
  );

  /// The native signature uses sorted, unescaped key=value pairs, then the
  /// exact UTF-8 body string. Query URL escaping happens only after signing.
  static String signature(Map<String, String> query, [String body = '']) {
    final keys = query.keys.where((key) => key.isNotEmpty).toList()..sort();
    final pairs = keys.map((key) => '$key=${query[key]}').join();
    return md5.convert(utf8.encode('$_appKey$pairs$body$_appKey')).toString();
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static String _randomSecret() {
    final random = Random.secure();
    // Android generates random AES bytes, renders them as hex and takes the
    // first 16 characters; eight independent bytes produce the same format.
    return _hex(List.generate(8, (_) => random.nextInt(256)));
  }

  static String _encryptParams(String clearText, String secret) {
    final digest = md5.convert(utf8.encode(secret)).toString();
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters(
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(digest))),
            Uint8List.fromList(utf8.encode(digest.substring(16))),
          ),
          null,
        ),
      );
    return _hex(cipher.process(Uint8List.fromList(utf8.encode(clearText))));
  }

  static String _encryptKey(String clearText) {
    final input = utf8.encode(clearText);
    if (input.length > 128) {
      throw ArgumentError('The grade key envelope exceeds its RSA block.');
    }
    // The shipped client copies at offset zero of a new 128-byte array. This
    // is right zero padding, not PKCS#1 padding or left integer padding.
    final padded = Uint8List(128)..setRange(0, input.length, input);
    final integer = BigInt.parse(_hex(padded), radix: 16);
    if (integer >= _modulus) {
      throw ArgumentError('The grade key envelope is outside its RSA block.');
    }
    return integer
        .modPow(BigInt.from(65537), _modulus)
        .toRadixString(16)
        .padLeft(256, '0')
        .toUpperCase();
  }

  /// Builds either a read (zero counters) or a report from a separately owned,
  /// measured ledger. [localMillis] and [diffSeconds] retain their native units;
  /// the caller must not substitute an unverified historical server baseline.
  /// [secret] is only for deterministic fixtures; production supplies none.
  static KugouV4GradeRequest build({
    required String userId,
    required String token,
    required String credentialAppId,
    required Map<String, String> device,
    required int clientTimeMs,
    String credentialClientVersion = standardClientVersion,
    int localMillis = 0,
    int diffSeconds = 0,
    int yType = 0,
    int mType = 0,
    bool includeMedals = true,
    int? vipUserType,
    int? vipUserYType,
    String? secret,
  }) {
    if (credentialAppId != standardAppId) {
      throw ArgumentError('Standard Kugou authorization is required.');
    }
    final uid = int.tryParse(userId);
    if (uid == null || uid <= 0 || token.isEmpty || clientTimeMs <= 0) {
      throw ArgumentError('The grade request requires a current account.');
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(credentialClientVersion)) {
      throw ArgumentError('The credential client version is invalid.');
    }
    if (localMillis < 0 || diffSeconds < 0 || yType < 0 || mType < 0) {
      throw ArgumentError('Grade counters cannot be negative.');
    }
    final secretValue = secret ?? _randomSecret();
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(secretValue)) {
      throw ArgumentError(
        'The grade request secret must be 16 hex characters.',
      );
    }
    final query = <String, String>{
      'clienttime': (clientTimeMs ~/ 1000).toString(),
      for (final key in ['mid', 'dfid', 'uuid']) key: device[key] ?? '',
      'appid': credentialAppId,
      'clientver': credentialClientVersion,
    };
    for (final key in ['mid', 'dfid', 'uuid']) {
      final value = query[key]!;
      if (value.isEmpty || value == '-' || value.length > 128) {
        throw ArgumentError('The grade request requires a registered device.');
      }
    }
    final seconds = localMillis ~/ 1000;
    final checksum = md5
        .convert(utf8.encode('$seconds$diffSeconds$yType$mType'))
        .toString();
    final privateFields = <String, Object>{
      'userid': uid,
      'token': token,
      'user_type': ?vipUserType,
      'user_y_type': ?vipUserYType,
      'md5': checksum,
    };
    final body = jsonEncode({
      'plat': 1,
      'userid': uid,
      'clienttime_ms': clientTimeMs,
      'type': 0,
      'd_sec': seconds,
      'diff_sec': diffSeconds,
      'y_type': yType,
      'm_type': mType,
      'pk': _encryptKey(
        jsonEncode({'clienttime_ms': clientTimeMs, 'key': secretValue}),
      ),
      'params': _encryptParams(jsonEncode(privateFields), secretValue),
      'medal': includeMedals ? 1 : 0,
    });
    query['signature'] = signature(query, body);
    return KugouV4GradeRequest(body: body, query: Map.unmodifiable(query));
  }
}
