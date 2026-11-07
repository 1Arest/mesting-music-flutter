import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/netease/netease_native_log.dart';

Uint8List unhex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

void main() {
  test('RFC8439 section2.3.2 independent ChaCha20 block vector', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final nonce = unhex('000000090000004a00000000');
    expect(
      NeteaseNativeLog.chacha(Uint8List(64), key, nonce, 1),
      unhex(
        '10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e'
        'd2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e',
      ),
    );
  });
  test('independent encoder exactly matches controlled official-native fixture', () {
    // Extracted 9.5.12 libbilog with only fixture RNG replaced locally. No user
    // data/network. Raw block is too short for compression, so exact bytes match.
    final expected = unhex(
      '4e43424c030000004c00928bd698c8b140ed897bdd1c3e39ec18'
      'bd363d63a8543be3c6aa2e138f731ca00dd536af4ced6381c449150c43014656'
      '7b0000007b0000002a00000043430200102224007b000000'
      'abd485c84703752ccbdca5f98fa2b55dda9f9a0a0a9c8666aa5ee80892a2942b727e052f',
    );
    expect(
      NeteaseNativeLog.encode(
        line: '1\u0001fixture\u0001{"fixture":true}\n',
        userInfo: '{}',
        sequence: 123,
        uuid: unhex('928bd698c8b140ed897bdd1c3e39ec18'),
        secret: Uint8List.fromList(List.filled(32, 1)),
      ),
      expected,
    );
  });
  test(
    'invalid sequence and oversized payload never produce an upload file',
    () {
      expect(
        () => NeteaseNativeLog.encode(line: 'x', userInfo: '{}', sequence: -1),
        throwsArgumentError,
      );
      expect(
        () => NeteaseNativeLog.encode(
          line: 'x' * 48001,
          userInfo: '{}',
          sequence: 1,
        ),
        throwsArgumentError,
      );
    },
  );
}
