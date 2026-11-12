import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/data/kugou_v4_grade_protocol.dart';

// These are synthetic identities. The wire golden was generated independently
// with PyCryptodome AES and Python's modular exponentiation, rather than copied
// from the Dart implementation's output.
const _device = {
  'mid': 'synthetic-mid',
  'dfid': 'synthetic-dfid',
  'uuid': 'synthetic-uuid',
};

void main() {
  test('20.8.6 native RSA, AES, units and signed exact body match golden', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/kugou_v4_grade_wire.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final input = fixture['input'] as Map<String, dynamic>;
    final request = KugouV4GradeProtocol.build(
      userId: input['userId'] as String,
      token: input['token'] as String,
      credentialAppId: '1005',
      device: _device,
      clientTimeMs: input['clientTimeMs'] as int,
      localMillis: input['localMillis'] as int,
      diffSeconds: input['diffSeconds'] as int,
      yType: input['yType'] as int,
      mType: input['mType'] as int,
      vipUserType: input['vipUserType'] as int,
      vipUserYType: input['vipUserYType'] as int,
      secret: fixture['secret'] as String,
    );
    expect(request.body, fixture['rawBody']);
    expect(jsonDecode(request.body), fixture['body']);
    expect(request.query, fixture['query']);
    expect(request.body, isNot(contains(input['token'] as String)));
    expect(request.query.values, isNot(contains(input['token'])));
    expect(
      KugouV4GradeRequest.endpoint.toString(),
      'https://userinfoservice.kugou.com/v4/get_grade_info',
    );
  });

  test('read has zero counters and no membership assertions by default', () {
    final request = KugouV4GradeProtocol.build(
      userId: '7',
      token: 'synthetic',
      credentialAppId: '1005',
      device: _device,
      clientTimeMs: 1793772345678,
      includeMedals: false,
      secret: '0123456789abcdef',
    );
    final body = jsonDecode(request.body) as Map;
    expect(body['d_sec'], 0);
    expect(body['diff_sec'], 0);
    expect(body['medal'], 0);
    expect(body.containsKey('token'), isFalse);
    expect(() => request.query['appid'] = '3116', throwsUnsupportedError);
  });

  test(
    'Lite and invalid registered-device identity cannot use v4 envelope',
    () {
      for (final appId in ['3116', '', '1001']) {
        expect(
          () => KugouV4GradeProtocol.build(
            userId: '7',
            token: 'synthetic',
            credentialAppId: appId,
            device: _device,
            clientTimeMs: 1793772345678,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => KugouV4GradeProtocol.build(
          userId: '7',
          token: 'synthetic',
          credentialAppId: '1005',
          device: {..._device, 'dfid': '-'},
          clientTimeMs: 1793772345678,
        ),
        throwsArgumentError,
      );
      expect(
        () => KugouV4GradeProtocol.build(
          userId: '7',
          token: 'synthetic',
          credentialAppId: '1005',
          device: _device,
          clientTimeMs: 1793772345678,
          diffSeconds: -1,
        ),
        throwsArgumentError,
      );
    },
  );

  test('fresh encryption randomness does not reuse an account envelope', () {
    KugouV4GradeRequest fresh() => KugouV4GradeProtocol.build(
      userId: '7',
      token: 'synthetic',
      credentialAppId: '1005',
      device: _device,
      clientTimeMs: 1793772345678,
    );
    final first = jsonDecode(fresh().body) as Map;
    final second = jsonDecode(fresh().body) as Map;
    expect(first['pk'], isNot(second['pk']));
    expect(first['params'], isNot(second['params']));
  });
}
