import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/features/music_platform/data/kugou_medal_repository.dart';
import 'package:mesting_music/features/music_platform/data/kugou_official_api.dart';
import 'package:mesting_music/features/music_platform/domain/kugou_medal_catalog.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/kugou_medals_page.dart';
import 'support/release_152_qa.dart';

const _owner = PlatformSession(
  userId: '7',
  token: 'fixture-lite',
  nickname: '测试账号',
  kugouStandardToken: 'fixture-standard',
);
Map<String, dynamic> _medal(int id, {bool earned = true, int selected = 0}) => {
  'id': id,
  'type': 'listen',
  'classify_id': id,
  'name': '听歌徽章$id',
  'is_light_up': earned ? 1 : 0,
  'is_exptime': 0,
  'selected_no': selected,
  'comment_selected_no': 0,
  'ds2nd_classify_name': '1',
  'receive_time': earned ? '2026-11-04' : '',
};

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _owner;
}

KugouMedalRepository _repository(
  Future<http.Response> Function(http.Request) handler, {
  PlatformSession? Function()? current,
}) => KugouMedalRepository(
  KugouOfficialApi(
    client: MockClient(handler),
    currentIdentity: current ?? () => _owner,
    device: () async => {
      'mid': 'fixture-mid',
      'dfid': 'fixture-dfid',
      'uuid': 'fixture-uuid',
    },
    clock: () => DateTime(2026, 11, 4),
  ),
);
http.Response _json(Object? data) => http.Response(
  jsonEncode({'status': 1, 'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

/// 布局测试使用已解析的真实合同形状；上面的传输测试单独校验签名/请求。
class _UIRepository extends KugouMedalRepository {
  _UIRepository() : super(_repository((_) async => _json({})).official);
  @override
  Future<KugouMedalSummary> summary(PlatformSession owner) async =>
      KugouMedalSummary({
        'user_info': {'medal_total': 1},
        'classify_list': [
          {'type': 'listen', 'name': '畅听'},
        ],
      }, DateTime(2026, 11, 4));
  @override
  Future<KugouMedalList> list(
    PlatformSession owner,
    String category, {
    int page = 1,
  }) async => KugouMedalList(
    [KugouMedalItem(_medal(1)), KugouMedalItem(_medal(2, earned: false))],
    2,
    page,
    DateTime(2026, 11, 4),
  );
  @override
  Future<KugouMedalDetail> detail(
    PlatformSession owner,
    KugouMedalItem item,
  ) async => KugouMedalDetail({
    'medal_list': [_medal(1), _medal(2, earned: false)],
    'medal_rule_data': jsonEncode({
      'task_list': [
        {'title': '听歌达到官方要求的时长'},
      ],
    }),
  }, 'listen');
  @override
  Future<KugouMedalList> owned(
    PlatformSession owner, {
    required int source,
    int page = 1,
  }) async => KugouMedalList(
    [KugouMedalItem(_medal(1))],
    1,
    page,
    DateTime(2026, 11, 4),
  );
}

void main() {
  setUpAll(initialize151QA);
  test(
    'collection reads current identity and real category/earned states',
    () async {
      final repo = _repository((request) async {
        expect(request.url.host, 'medal.kugou.com');
        expect(request.url.queryParameters['token'], 'fixture-standard');
        expect(request.url.queryParameters['appid'], '1005');
        final body = jsonDecode(request.body) as Map;
        expect(body['target_userid'], 7);
        if (request.url.path.endsWith('user_summary_medal')) {
          return _json({
            'user_info': {'medal_total': 1},
            'classify_list': [
              {'type': 'listen', 'name': '畅听'},
            ],
            'medals': [_medal(1)],
          });
        }
        expect(body, {
          'target_userid': 7,
          'type': 'listen',
          'page': 1,
          'page_size': 30,
          'sort': 0,
        });
        return _json({
          'list': [_medal(1), _medal(2, earned: false)],
          'total': 2,
        });
      });
      expect((await repo.summary(_owner)).total, 1);
      final list = await repo.list(_owner, 'listen');
      expect(list.items.map((m) => m.earned), [true, false]);
      expect(list.hasMore, false);
    },
  );
  test(
    'wear action uses actual earned state and does not optimistically mutate it',
    () async {
      final bodies = <Map>[];
      final repo = _repository((request) async {
        bodies.add(jsonDecode(request.body) as Map);
        return _json({});
      });
      final worn = KugouMedalItem(_medal(1, selected: 1));
      await repo.wear(_owner, worn);
      expect(bodies.single, {
        'type': 'listen',
        'classify_id': 1,
        'wear_action': 1,
        'source': 3,
      });
      expect(
        worn.selected(1),
        1,
        reason: 'a request receipt is not a refreshed wearing state',
      );
      await expectLater(
        repo.wear(_owner, KugouMedalItem(_medal(2, earned: false))),
        throwsA(isA<KugouOfficialException>()),
      );
      expect(bodies.length, 1);
    },
  );
  test(
    'homepage and comments retain independent source, limit and selection order',
    () async {
      final bodies = <Map>[];
      final repo = _repository((r) async {
        bodies.add(jsonDecode(r.body) as Map);
        return _json({});
      });
      final a = KugouMedalItem(_medal(2)), b = KugouMedalItem(_medal(1));
      await repo.select(_owner, 2, [a, b]);
      expect(bodies.single, {
        'source': 2,
        'selected_medals': [
          {'type': 'listen', 'classify_id': 2, 'id': 2},
          {'type': 'listen', 'classify_id': 1, 'id': 1},
        ],
      });
      await expectLater(
        repo.select(_owner, 2, [a, b, a]),
        throwsA(isA<KugouOfficialException>()),
      );
      await repo.select(_owner, 1, []);
      expect(bodies.last, {'source': 1, 'selected_medals': []});
      expect(bodies.length, 2);
    },
  );
  test(
    'foreign or refreshed standard credential cannot submit an old badge action',
    () async {
      var calls = 0;
      final repo = _repository(
        (_) async {
          calls++;
          return _json({});
        },
        current: () => const PlatformSession(
          userId: '7',
          token: 'fixture-lite',
          kugouStandardToken: 'new-standard',
        ),
      );
      await expectLater(
        repo.wear(_owner, KugouMedalItem(_medal(1))),
        throwsA(isA<KugouOfficialException>()),
      );
      expect(calls, 0);
    },
  );
  for (final large in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'gallery, details and wear management render large=$large dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = _UIRepository();
          for (final page in [
            const KugouMedalGalleryPage(session: _owner),
            KugouMedalDetailPage(
              owner: _owner,
              item: KugouMedalItem(_medal(1)),
            ),
            const KugouMedalWearPage(owner: _owner),
          ]) {
            final container = ProviderContainer(
              overrides: [
                platformAccountProvider.overrideWith(_Account.new),
                kugouMedalRepositoryProvider.overrideWithValue(repo),
              ],
            );
            await container.read(platformAccountProvider.future);
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  theme: theme152(dark),
                  builder: (_, child) => MediaQuery(
                    data: MediaQueryData(
                      size: Size(large ? 320 : 390, 844),
                      textScaler: TextScaler.linear(large ? 2 : 1),
                    ),
                    child: child!,
                  ),
                  home: capture151Builder(page),
                ),
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            for (var frame = 0; frame < 20; frame++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(
              find.byType(BetaActivityIndicator),
              findsNothing,
              reason: '${page.runtimeType} must finish its real mock request',
            );
            expect(tester.takeException(), isNull);
            expect(find.byTooltip('返回'), findsOneWidget);
            expect(find.text('听歌徽章1'), findsWidgets);
            await shot151(
              tester,
              '152-${page.runtimeType}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
            );
            await tester.pumpWidget(const SizedBox());
            container.dispose();
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
