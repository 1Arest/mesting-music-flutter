import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/auth/domain/password_policy.dart';

void main() {
  test('密码只校验 8–64 位，不强制字符类型组合', () {
    expect(validateAccountPassword('abcdefgh'), isNull);
    expect(validateAccountPassword('lowercaseonly'), isNull);
    expect(validateAccountPassword('Min20040402'), isNull);
    expect(validateAccountPassword('password'), isNull);
  });

  test('密码长度边界保持生效', () {
    expect(validateAccountPassword('1234567'), '密码长度需为 8–64 位');
    expect(validateAccountPassword('a' * 64), isNull);
    expect(validateAccountPassword('a' * 65), '密码长度需为 8–64 位');
  });
}
