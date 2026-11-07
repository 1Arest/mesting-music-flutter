import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/netease/netease_free_listen_entry.dart';

/// Synthetic server entry values only. These tests exercise the pure parser;
/// no value identifies a real advertisement, account or accepted reward.
String _entry(Map<String, String> fields) => Uri(
  scheme: 'orpheus',
  host: 'motivationAd',
  path: '/show',
  queryParameters: fields,
).toString();

Map<String, String> _fields([Map<String, String> extra = const {}]) => {
  'adPosition': '314',
  'resourceId': 'synthetic-resource',
  'source': '271',
  'isNeedGetRights': 'true',
  ...extra,
};

/// Installing this guard makes an accidental HTTP client construction fail
/// before a connection could open, including for malicious backup URLs.
class _NoNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('The entry parser must not construct an HTTP client');
  }
}

void main() {
  group('official motivationAd/show Bundle contract', () {
    test('keeps query types and serializes reqParam and ext separately', () {
      final parsed = NeteaseFreeListenEntry.parse(
        _entry(
          _fields({
            'isShowEndToast': 'TRUE',
            'showRightsEndDialog': 'true',
            'isNeedResume': 'true',
            'isNeedMute': 'true',
            'backupUrl': 'https://synthetic.invalid/never-open',
            'ext': jsonEncode({
              'entryMarker': 'synthetic-entry',
              'nested': {'opaque': 'preserved'},
              'bizReportInfo': {'synthetic': true, 'number': 7},
            }),
          }),
        ),
      )!;
      final payload = jsonDecode(parsed.qualificationJson) as Map;
      expect(payload['adPosition'], 314);
      expect(payload['adPosition'], isA<int>());
      expect(payload['source'], 271);
      expect(payload['source'], isA<int>());
      expect(payload['resourceId'], 'synthetic-resource');
      expect(payload['isNeedGetRights'], isTrue);
      expect(payload['isShowEndToast'], isTrue);
      expect(payload['showRightsEndDialog'], isTrue);
      expect(payload['isNeedResume'], isTrue);
      expect(payload['isNeedMute'], isTrue);
      expect(payload['backupUrl'], 'https://synthetic.invalid/never-open');
      expect(payload['ext'], isA<String>());
      final ext = jsonDecode(payload['ext'] as String) as Map;
      expect(ext['entryMarker'], 'synthetic-entry');
      expect(ext['nested'], {'opaque': 'preserved'});
      expect(ext['bizReportInfo'], isA<String>());
      expect(jsonDecode(ext['bizReportInfo'] as String), {
        'synthetic': true,
        'number': 7,
      });
      expect(payload['bizReportInfo'], ext['bizReportInfo']);
      expect(payload, isNot(contains('entryMarker')));
      expect(payload, isNot(contains('userId')));
      expect(parsed.requestsQualification, isTrue);
    });

    test(
      'missing optional context follows native false, zero and null defaults',
      () {
        final parsed = NeteaseFreeListenEntry.parse(
          _entry({'adPosition': '-3', 'resourceId': ''}),
        )!;
        expect(parsed.parameters['adPosition'], -3);
        // Native validation requires the resource key, not a nonempty value.
        expect(parsed.parameters['resourceId'], '');
        expect(parsed.source, 0);
        expect(parsed.requestsQualification, isFalse);
        for (final flag in [
          'isNeedGetRights',
          'isShowEndToast',
          'showRightsEndDialog',
          'isNeedResume',
          'isNeedMute',
        ]) {
          expect(parsed.parameters[flag], isFalse, reason: flag);
        }
        expect(parsed.parameters['backupUrl'], isNull);
        expect(parsed.parameters['bizReportInfo'], '');
        expect(jsonDecode(parsed.parameters['ext']! as String), {
          'bizReportInfo': '',
        });
      },
    );

    test('qualification form omits null backupUrl while Bundle keeps null', () {
      final parsed = NeteaseFreeListenEntry.parse(
        _entry({'adPosition': '314', 'resourceId': 'synthetic-resource'}),
      )!;
      // The native Bundle contains a nullable backupUrl. JSONObject's actual
      // form serialization omits null map values without WriteMapNullValue.
      expect(parsed.parameters, contains('backupUrl'));
      expect(parsed.parameters['backupUrl'], isNull);
      final payload = jsonDecode(parsed.qualificationJson) as Map;
      expect(payload, isNot(contains('backupUrl')));
      expect(payload['source'], 0);
      expect(payload['isNeedGetRights'], isFalse);
      for (final entry in parsed.parameters.entries) {
        if (entry.value != null) {
          expect(payload[entry.key], entry.value, reason: entry.key);
        }
      }
    });

    test('qualification form preserves a nonnull backupUrl verbatim', () {
      const backup = 'https://synthetic.invalid/never-open?q=synthetic%20value';
      final parsed = NeteaseFreeListenEntry.parse(
        _entry(_fields({'backupUrl': backup})),
      )!;
      final payload = jsonDecode(parsed.qualificationJson) as Map;
      expect(parsed.parameters['backupUrl'], backup);
      expect(payload['backupUrl'], backup);
      expect(payload['isNeedGetRights'], isTrue);
    });

    test('native ext serialization omits null maps and keeps array nulls', () {
      final parsed = NeteaseFreeListenEntry.parse(
        _entry(
          _fields({
            'ext': jsonEncode({
              'absent': null,
              'nested': {'absent': null, 'keep': 1},
              'list': [
                null,
                {'absent': null, 'keep': 2},
              ],
            }),
          }),
        ),
      )!;
      final payload = jsonDecode(parsed.qualificationJson) as Map;
      expect(jsonDecode(payload['ext'] as String), {
        'nested': {'keep': 1},
        'list': [
          null,
          {'keep': 2},
        ],
        'bizReportInfo': '',
      });
      expect(payload, isNot(contains('backupUrl')));
    });

    for (final value in ['true', 'TRUE', 'TrUe']) {
      test(
        'only Java Boolean.parseBoolean true enables qualification: $value',
        () {
          final parsed = NeteaseFreeListenEntry.parse(
            _entry(_fields({'isNeedGetRights': value})),
          )!;
          expect(parsed.requestsQualification, isTrue);
        },
      );
    }
    for (final value in ['', 'false', '1', 'yes', ' true', 'true ']) {
      test(
        'non-true flag cannot start qualification: ${jsonEncode(value)}',
        () {
          final parsed = NeteaseFreeListenEntry.parse(
            _entry(_fields({'isNeedGetRights': value})),
          )!;
          expect(parsed.requestsQualification, isFalse);
        },
      );
    }

    for (final report in [
      null,
      'synthetic opaque report',
      7,
      false,
      ['synthetic', 2],
      {'synthetic': 'object'},
    ]) {
      test(
        'bizReportInfo keeps its native string layer: ${jsonEncode(report)}',
        () {
          final parsed = NeteaseFreeListenEntry.parse(
            _entry(
              _fields({
                'ext': jsonEncode({'bizReportInfo': report}),
              }),
            ),
          )!;
          final ext = jsonDecode(parsed.parameters['ext']! as String) as Map;
          final expected = report == null
              ? ''
              : report is String
              ? report
              : jsonEncode(report);
          expect(parsed.parameters['bizReportInfo'], expected);
          expect(ext['bizReportInfo'], expected);
        },
      );
    }

    test(
      'nested ext and unrelated tracking fields cannot override Bundle context',
      () {
        final parsed = NeteaseFreeListenEntry.parse(
          _entry(
            _fields({
              'userId': 'synthetic-untrusted-user',
              'tracking': 'ignored',
              'reqUid': 'synthetic-untrusted-ad-token',
              'bizReportInfo': 'ignored-top-level-query',
              'ext': jsonEncode({
                'source': 999,
                'adPosition': 998,
                'isNeedGetRights': false,
                'bizReportInfo': 'synthetic-nested-report',
              }),
            }),
          ),
        )!;
        expect(parsed.source, 271);
        expect(parsed.parameters['adPosition'], 314);
        expect(parsed.requestsQualification, isTrue);
        expect(parsed.parameters['bizReportInfo'], 'synthetic-nested-report');
        expect(parsed.parameters.keys, isNot(contains('tracking')));
        expect(parsed.parameters.keys, isNot(contains('reqUid')));
        expect(parsed.parameters.keys, isNot(contains('userId')));
        expect(jsonDecode(parsed.parameters['ext']! as String)['source'], 999);
        expect(() => parsed.parameters['source'] = 999, throwsUnsupportedError);
      },
    );

    for (final source in [
      'not-a-number',
      '2147483648',
      '-2147483649',
      '0x10',
      ' 42',
      '42 ',
    ]) {
      test(
        'invalid Java decimal source stays native zero: ${jsonEncode(source)}',
        () {
          final parsed = NeteaseFreeListenEntry.parse(
            _entry(_fields({'source': source})),
          )!;
          expect(parsed.source, 0);
        },
      );
    }

    for (final position in ['0', '-2147483648', '2147483647', '+42', '0042']) {
      test('valid signed decimal adPosition is preserved: $position', () {
        final parsed = NeteaseFreeListenEntry.parse(
          _entry(_fields({'adPosition': position})),
        )!;
        expect(parsed.parameters['adPosition'], int.parse(position));
      });
    }
  });

  group('malformed or unrelated entries do not reach a network client', () {
    final invalid = <String, Object?>{
      'null': null,
      'non-string': 271,
      'empty': '',
      'HTTP': 'http://motivationAd/show?adPosition=1&resourceId=synthetic',
      'HTTPS': 'https://motivationAd/show?adPosition=1&resourceId=synthetic',
      'arbitrary host':
          'orpheus://synthetic.invalid/show?adPosition=1&resourceId=synthetic',
      'host suffix':
          'orpheus://motivationAd.synthetic.invalid/show?adPosition=1&resourceId=synthetic',
      'wrong route':
          'orpheus://motivationAd/claim?adPosition=1&resourceId=synthetic',
      'route suffix':
          'orpheus://motivationAd/show/other?adPosition=1&resourceId=synthetic',
      'userinfo':
          'orpheus://user:secret@motivationAd/show?adPosition=1&resourceId=synthetic',
      'explicit port':
          'orpheus://motivationAd:443/show?adPosition=1&resourceId=synthetic',
      'fragment': '${_entry(_fields())}#synthetic',
      'missing position': _entry({'resourceId': 'synthetic'}),
      'missing resource': _entry({'adPosition': '314'}),
      'integer overflow': _entry(_fields({'adPosition': '2147483648'})),
      'hex integer': _entry(_fields({'adPosition': '0x10'})),
      'leading integer whitespace': _entry(_fields({'adPosition': ' 314'})),
      'trailing integer whitespace': _entry(_fields({'adPosition': '314 '})),
      'broken JSON': _entry(_fields({'ext': '{"synthetic":'})),
      'list ext': _entry(_fields({'ext': '["synthetic"]'})),
      'scalar ext': _entry(_fields({'ext': '7'})),
      'null ext': _entry(_fields({'ext': 'null'})),
      'invalid UTF-8 resource':
          'orpheus://motivationAd/show?adPosition=1&resourceId=%FF',
      'invalid UTF-8 ext':
          'orpheus://motivationAd/show?adPosition=1&resourceId=synthetic&ext=%C0%AF',
      'oversized URL': '${_entry(_fields())}&ignored=${'x' * 65536}',
      for (final key in [
        'adPosition',
        'resourceId',
        'source',
        'ext',
        'isNeedGetRights',
        'isShowEndToast',
        'showRightsEndDialog',
        'isNeedResume',
        'isNeedMute',
        'backupUrl',
      ])
        'duplicate $key': '${_entry(_fields())}&$key=first&$key=second',
    };
    for (final entry in invalid.entries) {
      test('rejects ${entry.key} as data without opening it', () {
        final guard = _NoNetwork();
        NeteaseFreeListenEntry? parsed;
        expect(
          () => HttpOverrides.runWithHttpOverrides(
            () => parsed = NeteaseFreeListenEntry.parse(entry.value),
            guard,
          ),
          returnsNormally,
        );
        expect(parsed, isNull);
        expect(guard.attempts, 0);
      });
    }

    test(
      'valid entry and backupUrl are interpreted without opening either URL',
      () {
        final guard = _NoNetwork();
        final parsed = HttpOverrides.runWithHttpOverrides(
          () => NeteaseFreeListenEntry.parse(
            _entry(_fields({'backupUrl': 'http://127.0.0.1:1/never-open'})),
          ),
          guard,
        );
        expect(parsed, isNotNull);
        expect(guard.attempts, 0);
      },
    );
  });
}
