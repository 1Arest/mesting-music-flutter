import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/kugou_listening_profile_repository.dart';
import 'package:mesting_music/features/music_platform/data/kugou_official_api.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/kugou_listening_profile_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/kugou_listening_profile_pages.dart';
import 'package:mesting_music/features/music_platform/presentation/kugou_standard_authorization_page.dart';

import 'support/release_152_qa.dart';

const _owner = PlatformSession(
  userId: '155',
  token: 'synthetic-primary',
  kugouStandardToken: 'synthetic-standard',
);
const _device = {
  'mid': 'fixture-mid',
  'uuid': 'fixture-uuid',
  'dfid': 'fixture-dfid',
};
bool _authorized155 = false;

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _owner;
  @override
  Future<void> acceptKugouStandard(
    Map<String, dynamic> result, {
    required PlatformSession expected,
    bool Function()? isCurrent,
  }) async {
    expect(isCurrent?.call(), isTrue);
    expect(expected, _owner);
    expect(result['token'], _owner.kugouStandardToken);
    _authorized155 = true;
    // Simulate the documented same-token server result: this must still reset
    // a prior failed reader. Repository save transactions have separate tests.
  }
}

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:1');
}

void main() {
  setUpAll(initialize151QA);
  testWidgets(
    '155 successful same-token QR verification refreshes failed overview in place',
    (tester) async {
      var generations = 0, accepted = false;
      _authorized155 = false;
      final now = DateTime(2026, 11, 5);
      final scope = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Account.new),
          kugouStandardAuthorizationDeviceProvider.overrideWithValue(
            () async => _device,
          ),
          kugouStandardAuthorizationClientFactoryProvider.overrideWithValue(
            () => MockClient((request) async {
              final data = request.url.path.endsWith('/qrcode')
                  ? {'qrcode': 'synthetic-challenge'}
                  : request.url.path.endsWith('/get_userinfo_qrcode')
                  ? {
                      'status': 4,
                      'userid': _owner.userId,
                      'token': _owner.kugouStandardToken,
                    }
                  : {
                      'userid': _owner.userId,
                      'd_sec': 100,
                      'p_grade': 9,
                      'p_next_grade': 10,
                      'p_grade_point': 0,
                      'p_next_grade_point': 200,
                      'p_current_point': 100,
                    };
              return http.Response(
                jsonEncode({'error_code': 0, 'status': 1, 'data': data}),
                200,
              );
            }),
          ),
          kugouListeningProfileRepositoryProvider.overrideWith((ref) {
            generations++;
            final client = MockClient((request) async {
              if (!_authorized155) {
                throw const SocketException('synthetic-network-failure');
              }
              final data = request.url.path.endsWith('my_info')
                  ? {
                      'grade': {
                        'p_grade': 9,
                        'reg_time': '2016-01-01 00:00:00',
                      },
                      'timestamp': now.millisecondsSinceEpoch ~/ 1000,
                    }
                  : request.url.path.endsWith('my_medals')
                  ? {'total': 3, 'list': []}
                  : {
                      'grade_info': {'duration': 120},
                      'listen_duration': 300,
                    };
              return http.Response(
                jsonEncode({'status': 1, 'data': data}),
                200,
              );
            });
            ref.onDispose(client.close);
            return KugouListeningProfileRepository(
              api: MusicPlatformApi(server: _Server(), client: client),
              official: KugouOfficialApi(
                client: client,
                currentIdentity: () => _owner,
                device: () async => _device,
              ),
              clock: () => now,
            );
          }),
        ],
      );
      await scope.read(platformAccountProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
            theme: theme152(false),
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const KugouPersonalStatistics(session: _owner),
                    TextButton(
                      onPressed: () async {
                        accepted = await openKugouStandardAuthorization(
                          context,
                          _owner,
                        );
                      },
                      child: const Text('重新验证'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final before = scope.read(kugouListeningProfileReaderProvider)!;
      expect(before.grade.error, isNotNull);
      await tester.tap(find.text('重新验证'));
      for (
        var i = 0;
        i < 100 && (!accepted || find.text('Lv.9').evaluate().isEmpty);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        accepted,
        isTrue,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join('\n'),
      );
      expect(generations, 1);
      expect(scope.read(kugouListeningProfileReaderProvider), same(before));
      expect(find.text('Lv.9'), findsOneWidget);
      expect(find.text('3枚'), findsOneWidget);
      expect(
        scope.read(kugouListeningProfileReaderProvider)!.grade.value?.musicAge,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scope.dispose();
    },
  );
}
