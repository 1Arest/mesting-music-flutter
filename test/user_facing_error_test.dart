import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/core/errors/user_facing_error.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';

void main() {
  test('keeps deliberate Chinese domain messages', () {
    expect(
      userFacingErrorMessage(
        const AuthRequestException('邮箱或密码不正确'),
        fallback: '登录失败',
      ),
      '邮箱或密码不正确',
    );
  });

  test(
    'translates common transport errors without leaking English details',
    () {
      expect(
        userFacingErrorMessage(
          const HandshakeException('Connection terminated during handshake'),
        ),
        '安全连接建立失败，请切换网络后重试',
      );
      expect(
        userFacingErrorMessage(TimeoutException('request timed out')),
        '网络响应超时，请稍后重试',
      );
      expect(
        userFacingErrorMessage(http.ClientException('connection reset')),
        '网络连接不可用，请检查网络后重试',
      );
    },
  );

  test('uses a Chinese fallback for unknown internal exceptions', () {
    final message = userFacingErrorMessage(
      StateError('Unexpected internal state'),
      fallback: '登录失败，请稍后重试',
    );

    expect(message, '登录失败，请稍后重试');
    expect(message, isNot(contains('StateError')));
    expect(message, isNot(contains('Unexpected')));
  });
}
