import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/data/embedded_music_server.dart';
import 'package:mesting_music/features/music_platform/data/kugou_listening_profile_repository.dart';
import 'package:mesting_music/features/music_platform/data/kugou_official_api.dart';
import 'package:mesting_music/features/music_platform/data/music_platform_api.dart';
import 'package:mesting_music/features/music_platform/domain/kugou_listening_profile.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/kugou_listening_profile_providers.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/kugou_listening_profile_pages.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_providers.dart';
import 'support/release_152_qa.dart';

const _owner = PlatformSession(
  userId: '101',
  token: 'fixture-only',
  nickname: '示例账号',
);
final _now = DateTime(2026, 11, 4, 17, 50);
const _device = {
  'uuid': 'fixture-uuid',
  'mid': 'fixture-mid',
  'dfid': 'fixture-dfid',
};

class _Server implements MusicServer {
  @override
  Future<Uri> start() async => Uri.parse('http://127.0.0.1:15200');
}

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => _owner;
  void select(PlatformSession session) => state = AsyncData(session);
}

MusicPlatformApi _api() => MusicPlatformApi(
  server: _Server(),
  client: MockClient((_) async => http.Response('{}', 500)),
);
KugouOfficialApi _official(
  http.Client client, {
  PlatformSession? Function()? identity,
}) => KugouOfficialApi(
  client: client,
  currentIdentity: identity ?? () => _owner,
  device: () async => _device,
  clock: () => _now,
);

class _FixtureRepository extends KugouListeningProfileRepository {
  _FixtureRepository()
    : super(
        api: _api(),
        official: _official(MockClient((_) async => http.Response('{}', 500))),
        clock: () => _now,
      );
  int reads = 0;
  bool fail = false;
  bool failWrite = false;
  bool liked = false;
  int likes = 0, cityWrites = 0;
  final rankReads = <({KugouGradeRank kind, int page})>[];
  Completer<KugouListeningStatistics>? pending;
  @override
  Future<KugouListeningStatistics> statistics(
    PlatformSession owner,
    KugouListenPeriod period,
    DateTime date,
  ) async {
    reads++;
    if (pending != null) {
      return pending!.future;
    }
    if (fail) {
      throw const KugouOfficialException('统计读取失败');
    }
    return KugouListeningStatistics(
      {
        'listen_duration': 720,
        'accumulate_listen_days': 2,
        'grade_info': {'duration': 324},
        'dates': [
          for (var i = 0; i < 7; i++) {'listen_duration': i == 2 ? 720 : 0},
        ],
        'clocks': [
          for (var i = 0; i < 25; i++) {'listen_duration': i == 14 ? 720 : 0},
        ],
        'months': [
          {'month': 20261001, 'listen_duration': 660},
          {'month': 20261101, 'listen_duration': 720},
        ],
        'rank_song': [
          {
            'song_info': {'name': '示例歌曲', 'singer_name': '示例歌手'},
            'count': 2,
          },
        ],
      },
      period,
      date,
      _now,
    );
  }

  @override
  Future<KugouGrade> grade(PlatformSession owner) async => KugouGrade({
    'p_grade': 1,
    'p_current_point': 324,
    'p_grade_point': 0,
    'p_next_grade': 2,
    'p_next_grade_point': 1000,
    'duration': 324,
    'reg_time': '2021-08-04 00:00:00',
    'timestamp':
        DateTime.utc(2026, 11, 4, 9, 50).millisecondsSinceEpoch ~/ 1000,
    'p_speed': 1.5,
  }, _now);
  @override
  Future<KugouMusicProfile> profile(PlatformSession owner) async =>
      KugouMusicProfile({
        'reg_time': '2021-08-04 00:00:00',
        'servertime': '2026-11-04 17:50:00',
      }, _now);
  @override
  Future<KugouMedalCollection> medals(PlatformSession owner) async =>
      KugouMedalCollection({
        'total': 1,
        'list': [
          {'name': '听歌等级普通款', 'level': 1},
        ],
        'h5_url_index': 'https://h5.kugou.com/fixture-medal/index.html',
      }, _now);
  @override
  Future<KugouGradeRanking> ranking(
    PlatformSession owner,
    KugouGradeRank kind, {
    int page = 1,
  }) async {
    rankReads.add((kind: kind, page: page));
    if (fail) {
      throw const KugouOfficialException('榜单读取失败');
    }
    return KugouGradeRanking(
      {
        'total': 3,
        'area': {'province_name': '广东省', 'city_name': '深圳市'},
        'period_end_time': DateTime(2026, 12).millisecondsSinceEpoch ~/ 1000,
        'self_info': {
          'userid': '101',
          'nickname': '示例账号',
          'p_current_point': 11,
          'rank_distance': 25909,
          'rank': 0,
          'like_num': 0,
          'is_liked_today': false,
        },
        'list': [
          for (var i = page == 1 ? 1 : 3; i <= (page == 1 ? 2 : 3); i++)
            {
              'userid': '${1000 + i}',
              'nickname': '榜单示例用户$i',
              'p_current_point': 34560 - i,
              'rank': i,
              'p_speed': 1.5,
              'like_num': i + (liked ? 1 : 0),
              'is_liked_today': liked,
            },
        ],
      },
      kind,
      page,
      _now,
    );
  }

  @override
  Future<void> setRankLiked(
    PlatformSession owner,
    KugouGradeRank kind,
    String target, {
    required bool liked,
  }) async {
    likes++;
    if (failWrite) {
      throw const KugouOfficialException('结果未知');
    }
    this.liked = liked;
  }

  @override
  Future<KugouRankingCities> rankingCities(PlatformSession owner) async =>
      KugouRankingCities({
        'items': [
          {
            'name': '广东省',
            'full_name': '广东省',
            'items': [
              {'name': '深圳市', 'full_name': '广东省深圳市', 'area_code': '440300'},
              {'name': '广州市', 'full_name': '广东省广州市', 'area_code': '440100'},
            ],
          },
        ],
      }, _now);
  @override
  Future<void> setRankingCity(PlatformSession owner, String cityId) async {
    cityWrites++;
    if (failWrite) {
      throw const KugouOfficialException('结果未知');
    }
  }
}

void main() {
  setUpAll(initialize151QA);

  test('calendar dimensions use natural starts across the year boundary', () {
    expect(
      KugouListenPeriod.week.start(DateTime(2026, 1, 1, 23)),
      DateTime(2025, 12, 29),
    );
    expect(
      KugouListenPeriod.month.shift(DateTime(2026, 1), -1),
      DateTime(2025, 12),
    );
    expect(
      KugouListenPeriod.day.shift(DateTime(2024, 3, 1), -1),
      DateTime(2024, 2, 29),
    );
  });

  test(
    'official seconds, header minutes and monthly series remain distinct',
    () {
      final stats = KugouListeningStatistics(
        {
          'listen_duration': 720,
          'grade_info': {'duration': 324},
          'months': [
            {'month': 20261101, 'listen_duration': 720},
          ],
          'dates': [
            {'listen_duration': 999},
          ],
        },
        KugouListenPeriod.month,
        _now,
        _now,
      );
      expect(stats.seconds, 720);
      expect(stats.totalSeconds, 19440);
      expect(stats.series.single['listen_duration'], 720);
      expect(
        KugouListeningStatistics(
          const {},
          KugouListenPeriod.day,
          _now,
          _now,
        ).seconds,
        isNull,
      );
    },
  );

  for (final year in [2019, 2020, 2021, 2022, 2023, 2024, 2025]) {
    test('annual $year preserves its verified duration unit', () {
      final values = {
        'play_times': 2,
        'play_all': {'play_time': 2, 'total_play_duration': 120},
        'year_all': {'play_min': 2},
      };
      final normalized = kugouAnnualStatistics(
        year,
        year >= 2022 ? {'year_data': values} : values,
      );
      expect(normalized['listen_duration'], year == 2023 ? 2 : 120);
    });
  }

  test('an unpublished annual schema never adopts last year fields', () {
    expect(
      kugouAnnualStatistics(2026, {
        'year_data': {
          'play_all': {'total_play_duration': 120},
        },
      })['listen_duration'],
      isNull,
    );
  });

  test(
    'music age needs both real timestamps and counts completed calendar months',
    () {
      expect(
        kugouMusicAge('2021-08-04 00:00:00', '2026-11-04 17:50:00'),
        '5年3个月',
      );
      expect(kugouMusicAge('2021-08-05', '2026-11-04'), '5年2个月');
      expect(kugouMusicAge(null, '2026-11-04'), isNull);
      expect(kugouMusicAge('2021-02-30', '2026-11-04'), isNull);
      expect(kugouMusicAge('2021-08-04 25:00:00', '2026-11-04'), isNull);
      expect(kugouMusicAge('2026-11-05', '2026-11-04'), isNull);
      final registered =
          DateTime.utc(2021, 8, 3, 16).millisecondsSinceEpoch ~/ 1000;
      final server = DateTime.utc(2026, 11, 3, 16).millisecondsSinceEpoch;
      expect(kugouMusicAge(registered, server), '5年3个月');
    },
  );

  test(
    'grade progress is derived from returned bounds without invented thresholds',
    () {
      expect(
        KugouGrade({
          'p_current_point': 324,
          'p_grade_point': 0,
          'p_next_grade_point': 1000,
        }, _now).progress,
        .324,
      );
      expect(KugouGrade({'p_current_point': 324}, _now).progress, isNull);
      expect(
        KugouGrade({
          'p_current_point': 324,
          'p_grade_point': 0,
          'p_next_grade_point': 300,
        }, _now).progress,
        1,
      );
    },
  );

  test(
    'medal links require a real HTTPS Kugou domain and no user info or custom port',
    () {
      expect(kugouOfficialMedalUri('https://h5.kugou.com/a'), isNotNull);
      for (final value in [
        'http://h5.kugou.com/a',
        'https://h5.kugou.com.evil.test/a',
        'https://evil.test/?next=kugou.com',
        'https://x@h5.kugou.com/a',
        'https://h5.kugou.com:8443/a',
        '',
      ]) {
        expect(kugouOfficialMedalUri(value), isNull, reason: value);
      }
    },
  );

  test('latest and past daily requests use verified signed fields', () async {
    final requests = <http.Request>[];
    final transport = _official(
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'status': 1,
            'data': {'listen_duration': 120},
          }),
          200,
        );
      }),
    );
    final repository = KugouListeningProfileRepository(
      api: _api(),
      official: transport,
      clock: () => _now,
    );
    expect(
      (await repository.statistics(
        _owner,
        KugouListenPeriod.day,
        _now,
      )).seconds,
      120,
    );
    await repository.statistics(
      _owner,
      KugouListenPeriod.day,
      DateTime(2026, 11, 3),
    );
    expect(requests.first.url.host, 'lstatistics2.kugou.com');
    expect(requests.first.url.queryParameters, containsPair('date', '0'));
    expect(
      requests.first.url.queryParameters,
      containsPair('is_real_time', 'true'),
    );
    expect(requests.last.url.queryParameters, containsPair('date', '20261103'));
    expect(
      requests.last.url.queryParameters,
      containsPair('is_real_time', 'false'),
    );
    expect(requests.first.url.queryParameters, containsPair('appid', '3116'));
    expect(requests.first.followRedirects, isFalse);
  });

  test(
    'annual transport uses separate year token and published biz contract',
    () async {
      http.Request? sent;
      final repository = KugouListeningProfileRepository(
        api: _api(),
        official: _official(
          MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'status': 1,
                'data': {
                  'year_data': {
                    'play_all': {'total_play_duration': 120},
                  },
                },
              }),
              200,
            );
          }),
        ),
        clock: () => _now,
      );
      expect(
        (await repository.statistics(
          _owner,
          KugouListenPeriod.year,
          DateTime(2025),
        )).seconds,
        120,
      );
      expect(sent!.url.host, 'inventory2018.kugou.com');
      expect(sent!.url.queryParameters, containsPair('biz', 'v2025'));
      expect(
        sent!.url.queryParameters,
        containsPair('clienttoken', _owner.token),
      );
      expect(sent!.url.queryParameters.containsKey('token'), isFalse);
      final first = sent;
      await expectLater(
        repository.statistics(_owner, KugouListenPeriod.year, DateTime(2026)),
        throwsA(isA<KugouOfficialException>()),
      );
      expect(identical(sent, first), isTrue);
    },
  );

  test('account mutation rejects an in-flight official response', () async {
    final pending = Completer<http.Response>();
    PlatformSession? identity = _owner;
    final api = _official(
      MockClient((_) => pending.future),
      identity: () => identity,
    );
    final loading = api.request(KugouOfficialRoute.statistics, _owner);
    final result = expectLater(loading, throwsA(isA<KugouOfficialException>()));
    await Future<void>.delayed(Duration.zero);
    identity = const PlatformSession(userId: '102', token: 'other-fixture');
    pending.complete(
      http.Response('{"status":1,"data":{"listen_duration":999}}', 200),
    );
    await result;
  });

  test(
    'reader coalesces requests, retains success after failure and retries only requested item',
    () async {
      final repository = _FixtureRepository();
      final reader = KugouListeningProfileReader(
        owner: _owner,
        repository: repository,
      );
      addTearDown(reader.dispose);
      await Future.wait([
        reader.loadStatistics(KugouListenPeriod.day, _now),
        reader.loadStatistics(KugouListenPeriod.day, _now),
      ]);
      expect(repository.reads, 1);
      repository.fail = true;
      await reader.loadStatistics(KugouListenPeriod.day, _now, force: true);
      expect(
        reader.statistics(KugouListenPeriod.day, _now).value!.seconds,
        720,
      );
      expect(reader.statistics(KugouListenPeriod.day, _now).error, '统计读取失败');
      await reader.loadProfile();
      expect(repository.reads, 2);
      expect(reader.profile.value!.musicAge, '5年3个月');
    },
  );

  test('disposed account reader never publishes a late snapshot', () async {
    final repository = _FixtureRepository()
      ..pending = Completer<KugouListeningStatistics>();
    final reader = KugouListeningProfileReader(
      owner: _owner,
      repository: repository,
    );
    var notifications = 0;
    reader.addListener(() => notifications++);
    final state = reader.statistics(KugouListenPeriod.day, _now);
    final pending = reader.loadStatistics(KugouListenPeriod.day, _now);
    reader.dispose();
    repository.pending!.complete(
      KugouListeningStatistics(
        {'listen_duration': 999},
        KugouListenPeriod.day,
        _now,
        _now,
      ),
    );
    await pending;
    expect(state.value, isNull);
    expect(notifications, 1);
    expect(reader.belongsTo(_owner), isFalse);
  });

  test('new level music age uses official timestamp and 360/30 units', () {
    final registered = DateTime.utc(
      2020,
      1,
      1,
    ).subtract(const Duration(hours: 8));
    final seconds =
        registered.add(const Duration(days: 390)).millisecondsSinceEpoch ~/
        1000;
    expect(kugouLevelMusicAge('2020-01-01 00:00:00', seconds), '1年1个月');
    expect(
      kugouLevelMusicAge(
        '2020-01-01 00:00:00',
        seconds - 390 * 86400 + 29 * 86400,
      ),
      '29天',
    );
    expect(kugouLevelMusicAge('2020-01-01', null), isNull);
    expect(kugouLevelMusicAge('2020-02-30', seconds), isNull);
    expect(KugouGrade({'duration': 324}, _now).seconds, 19440);
  });

  test(
    'query cannot override primary or supplementary official identity',
    () async {
      const standard = PlatformSession(
        userId: '101',
        token: 'primary-fixture',
        kugouStandardToken: 'standard-fixture',
      );
      http.Request? sent;
      final api = _official(
        MockClient((request) async {
          sent = request;
          return http.Response('{"status":1,"data":{}}', 200);
        }),
        identity: () => standard,
      );
      await api.request(
        KugouOfficialRoute.levelInfo,
        standard,
        query: {
          'userid': '999',
          'token': 'wrong',
          'clienttoken': 'wrong',
          'kugouid': '999',
          'appid': '3116',
          'mid': 'wrong',
          'signature': 'wrong',
        },
      );
      expect(sent!.url.queryParameters['userid'], '101');
      expect(sent!.url.queryParameters['token'], 'standard-fixture');
      expect(sent!.url.queryParameters['appid'], '1005');
      expect(sent!.url.queryParameters['clientver'], '20869');
      expect(sent!.url.queryParameters['mid'], _device['mid']);
      expect(sent!.url.queryParameters.containsKey('clienttoken'), isFalse);
      expect(sent!.url.queryParameters.containsKey('kugouid'), isFalse);
      expect(
        sent!.url.queryParameters['clienttime'],
        '${_now.millisecondsSinceEpoch}',
      );
    },
  );

  test(
    'ABA switch closes the first transport even after the same UID returns',
    () async {
      final container = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Account.new),
          musicPlatformApiProvider.overrideWithValue(_api()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      final first = container.read(kugouListeningProfileRepositoryProvider);
      expect(first.official.isCurrent(_owner), isTrue);
      (container.read(platformAccountProvider.notifier) as _Account).select(
        const PlatformSession(userId: '102', token: 'other-fixture'),
      );
      // 不读取/重建中间B的provider，模拟一帧内完成切换。
      (container.read(platformAccountProvider.notifier) as _Account).select(
        _owner,
      );
      expect(first.official.isCurrent(_owner), isFalse);
      final last = container.read(kugouListeningProfileRepositoryProvider);
      expect(first.official.isCurrent(_owner), isFalse);
      expect(last.official.isCurrent(_owner), isTrue);
      expect(identical(first, last), isFalse);
    },
  );

  test(
    'new level rank, like and city mutations retain verified contracts and never retry',
    () async {
      final requests = <http.Request>[];
      final repository = KugouListeningProfileRepository(
        api: _api(),
        official: _official(
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode({
                'status': 1,
                'data': {'items': [], 'list': [], 'total': 0},
              }),
              200,
            );
          }),
        ),
        clock: () => _now,
      );
      await repository.ranking(_owner, KugouGradeRank.city, page: 2);
      expect(requests.last.url.host, 'songplay.kugou.com');
      expect(requests.last.url.queryParameters['rank_type'], '4');
      expect(requests.last.url.queryParameters['page'], '2');
      expect(requests.last.url.queryParameters['pagesize'], '50');
      await repository.setRankLiked(
        _owner,
        KugouGradeRank.province,
        '102',
        liked: true,
      );
      expect(requests.last.url.path, '/v1/listen_level/like_user');
      expect(jsonDecode(requests.last.body), {
        'target_userid': 102,
        'rank_type': 3,
      });
      await repository.setRankLiked(
        _owner,
        KugouGradeRank.province,
        '102',
        liked: false,
      );
      expect(requests.last.url.path, '/v1/listen_level/unlike_user');
      await repository.rankingCities(_owner);
      expect(requests.last.url.host, 'userinfo.user.kugou.com');
      expect(requests.last.method, 'POST');
      await repository.setRankingCity(_owner, '440300');
      expect(jsonDecode(requests.last.body), {
        'userid': 101,
        'token': _owner.token,
        'city_id': '440300',
      });
      expect(requests.length, 5);
    },
  );

  testWidgets(
    'rank like unknown result blocks replay until official refresh; city asks before write',
    (tester) async {
      final repository = _FixtureRepository();
      final reader = KugouListeningProfileReader(
        owner: _owner,
        repository: repository,
      );
      addTearDown(reader.dispose);
      await reader.loadGrade();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kugouListeningProfileReaderProvider.overrideWithValue(reader),
            kugouListeningProfileClockProvider.overrideWithValue(() => _now),
          ],
          child: MaterialApp(
            theme: theme152(false),
            home: const KugouListeningGradePage(session: _owner),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final like = find.byKey(const ValueKey('kugou-level-like-2-1001'));
      await tester.scrollUntilVisible(like, 220);
      await Scrollable.ensureVisible(tester.element(like), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(like);
      await tester.pumpAndSettle();
      expect(repository.likes, 1);
      repository.failWrite = true;
      await tester.tap(like);
      await tester.pumpAndSettle();
      expect(repository.likes, 2);
      expect(tester.widget<TextButton>(like).onPressed, isNull);
      await tester.tap(like);
      await tester.pump();
      expect(repository.likes, 2);
      await tester.scrollUntilVisible(find.text('刷新榜单'), -220);
      await Scrollable.ensureVisible(
        tester.element(find.text('刷新榜单')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      repository.failWrite = false;
      await tester.tap(find.text('刷新榜单'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(like, 220);
      await Scrollable.ensureVisible(tester.element(like), alignment: .5);
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(like).onPressed, isNotNull);
      await tester.scrollUntilVisible(find.text('榜单地区'), -220);
      await Scrollable.ensureVisible(
        tester.element(find.text('榜单地区')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('榜单地区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深圳市'));
      await tester.pumpAndSettle();
      expect(find.text('确认榜单地区'), findsOneWidget);
      expect(repository.cityWrites, 0);
      await tester.tap(find.text('返回修改'));
      await tester.pumpAndSettle();
      expect(repository.cityWrites, 0);
      await tester.tap(find.text('榜单地区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深圳市'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(repository.cityWrites, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'official profile pages preserve navigation and fit narrow text dark=$dark large=$large',
        (tester) async {
          tester.view.physicalSize = Size(large ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final reader = KugouListeningProfileReader(
            owner: _owner,
            repository: _FixtureRepository(),
          );
          addTearDown(reader.dispose);
          await reader.loadOverview();
          final opened = <Uri>[];
          Future<void> official(Uri uri) async {
            opened.add(uri);
          }

          final pages = <({String name, Widget page})>[
            for (final period in KugouListenPeriod.values)
              (
                name: 'statistics-${period.name}',
                page: KugouListeningStatisticsPage(
                  session: _owner,
                  onOpenOfficial: official,
                  initialPeriod: period,
                ),
              ),
            for (final rank in KugouGradeRank.values)
              (
                name: 'grade-${rank.name}',
                page: KugouListeningGradePage(
                  session: _owner,
                  onOpenOfficial: official,
                  initialRank: rank,
                ),
              ),
            (name: 'music-age', page: const KugouMusicAgePage(session: _owner)),
          ];
          for (final entry in pages) {
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  kugouListeningProfileReaderProvider.overrideWithValue(reader),
                  kugouOfficialDailySyncStatusProvider.overrideWith(
                    (ref) => Stream.value(null),
                  ),
                  kugouListeningProfileClockProvider.overrideWithValue(
                    () => _now,
                  ),
                ],
                child: MaterialApp(
                  theme: theme152(dark),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                    child: child!,
                  ),
                  home: capture151Builder(
                    KeyedSubtree(key: ValueKey(entry.name), child: entry.page),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byTooltip('返回'), findsOneWidget);
            if (entry.name == 'grade-global') {
              await shot151(
                tester,
                '152-grade-overview-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
              );
            }
            if (entry.name.startsWith('grade-')) {
              await tester.scrollUntilVisible(find.text('听歌等级排行榜'), 240);
              await tester.pumpAndSettle();
            }
            await shot151(
              tester,
              '152-${entry.name}-${dark ? 'dark' : 'light'}-${large ? 'large' : 'normal'}',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
