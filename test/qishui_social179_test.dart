import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostics.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_models.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_social_repository.dart';

import 'qishui_signed_api167_test.dart' show FixtureSigner, reply;
import 'qishui_social177_test.dart' show account177;

/// The 178 field-only receipt and the user's empty official group establish
/// this omitted-array envelope. No account data is copied into this fixture.
Map<String, dynamic> _empty({Object code = 0}) => {
  'status_info': <String, Object>{},
  'status_code': code,
  'next_cursor': '',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('acknowledged omitted list is empty and cannot request more pages', () {
    for (final response in [
      _empty(),
      _empty(code: '0'),
      {..._empty(), 'has_more': false},
      {..._empty(), 'has_more': 0},
      {..._empty(), 'has_more': '0'},
      {'status_code': 0},
      {'status_code': 0, 'data': _empty()},
    ]) {
      final page = QishuiSocialPage.parse(response, '');
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.continuationProblem, isNull);
    }
  });

  // These are deliberately different failures. In particular, an explicit
  // malformed array must not become an empty group and hide a server change.
  final invalid = <String, Map<String, dynamic>>{
    'no success receipt': {},
    'unknown list field': {..._empty(), 'users': []},
    'unknown nested list': {..._empty(), 'items': []},
    'unknown outer list': {'status_code': 0, 'items': [], 'data': _empty()},
    'contradictory outer status': {
      'status_code': 0,
      'status_info': {'code': 5},
      'data': _empty(),
    },
    'contradictory outer continuation': {
      'status_code': 0,
      'has_more': true,
      'data': _empty(),
    },
    'explicit null array': {..._empty(), 'follow_items': null},
    'object array': {..._empty(), 'follow_items': {}},
    'string array': {..._empty(), 'follow_items': ''},
    'more true': {..._empty(), 'has_more': true},
    'more one': {..._empty(), 'has_more': 1},
    'more unknown': {..._empty(), 'has_more': null},
    'nonzero business': _empty(code: 5),
    'contradictory status': {
      ..._empty(),
      'status_info': {'code': 5},
    },
    'invalid status type': {..._empty(), 'status_info': ''},
    'invalid cursor type': {..._empty(), 'next_cursor': 0},
    'invalid cursor contents': {..._empty(), 'next_cursor': 'bad\ncursor'},
  };
  for (final entry in invalid.entries) {
    test('omitted-array compatibility rejects ${entry.key}', () {
      expect(
        () => QishuiSocialPage.parse(entry.value, ''),
        throwsA(isA<QishuiException>()),
      );
    });
  }

  for (final kind in QishuiFollowListKind.values) {
    test(
      '${kind.name} keeps Qishui empty and Douyin rows independent',
      () async {
        final requests = <String>[];
        final api = QishuiApi(
          MockClient((request) async {
            expect(request.url.path, '/luna/users/17701/${kind.pathName}');
            expect(request.method, 'GET');
            expect(request.url.queryParameters['cursor'], '');
            final source = request.url.queryParameters['scene']!;
            requests.add(source);
            if (source == '2') return reply(_empty());
            return reply({
              'status_code': 0,
              'follow_items': [
                {
                  'item_type': 'user',
                  'user': {'id': '17902', 'nickname': 'Synthetic Douyin user'},
                },
              ],
              'has_more': false,
            });
          }),
          signer: FixtureSigner(),
        )..configure(account177());
        addTearDown(api.dispose);
        QishuiDiagnostics.shared.clear();
        final repository = QishuiSocialRepository(QishuiRepository(api));
        final empty = await repository.list(kind);
        expect(empty.items, isEmpty);
        final douyin = await repository.list(
          kind,
          source: QishuiFollowSource.douyin,
        );
        expect(douyin.items.single.userId, '17902');
        expect((await repository.list(kind)).items, isEmpty);
        expect(requests, ['2', '1', '2']);
        // The end-to-end parser must also record a successful parse rather than
        // only showing HTTP 200 followed by the old responseShape failure.
        final events = QishuiDiagnostics.shared.events;
        expect(events.where((e) => e['outcome'] == 'format'), isEmpty);
        expect(
          events.where(
            (e) => e['stage'] == 'parse' && e['outcome'] == 'success',
          ),
          hasLength(3),
        );
      },
    );
  }
}
